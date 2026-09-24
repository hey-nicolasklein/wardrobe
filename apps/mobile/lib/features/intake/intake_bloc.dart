import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/intake.dart';
import 'package:form_mobile/repository/intake_repository.dart';
import 'package:form_mobile/services/form_api.dart';

enum IntakeAction {
  restore,
  add,
  advance,
  retry,
  select,
  ownership,
  save,
  manual,
  discard,
}

class IntakeEvent {
  const IntakeEvent(
    this.action, {
    this.id,
    this.choiceKey,
    this.paths = const [],
    this.value,
    this.edit,
  });
  final IntakeAction action;
  final String? id;
  final String? choiceKey;
  final List<String> paths;
  final bool? value;
  final ItemEdit? edit;
}

class IntakeState {
  const IntakeState({
    this.drafts = const [],
    this.busy = false,
    this.progress = 0,
    this.activeDraftId,
    this.error,
  });
  final List<IntakeDraft> drafts;
  final bool busy;
  final double progress;
  final String? activeDraftId;
  final String? error;
}

class IntakeBloc extends Bloc<IntakeEvent, IntakeState> {
  IntakeBloc(this.repository, {this.pollInterval = const Duration(seconds: 3)})
    : super(const IntakeState()) {
    on<IntakeEvent>(_handle, transformer: sequential());
  }
  final IntakeRepository repository;
  final Duration pollInterval;
  final List<IntakeDraft> _drafts = [];
  Timer? _timer;
  final _discarding = <String>{};
  bool _online = false;
  bool _foreground = true;
  bool _visible = false;
  bool get canContinue => _online && _foreground && !isClosed;

  void discard(String id) {
    _discarding.add(id);
    add(IntakeEvent(IntakeAction.discard, id: id));
  }

  void availability({bool? online, bool? foreground, bool? visible}) {
    _online = online ?? _online;
    _foreground = foreground ?? _foreground;
    _visible = visible ?? _visible;
    _timer?.cancel();
    if (canContinue && _visible) add(const IntakeEvent(IntakeAction.advance));
  }

  void _publish(
    Emitter<IntakeState> emit, {
    bool busy = false,
    double progress = 0,
    String? activeDraftId,
    String? error,
  }) {
    emit(
      IntakeState(
        drafts: List.unmodifiable(_drafts.map((d) => d.snapshot())),
        busy: busy,
        progress: progress,
        activeDraftId: activeDraftId,
        error: error,
      ),
    );
  }

  Future<void> _handle(IntakeEvent event, Emitter<IntakeState> emit) async {
    _timer?.cancel();
    _publish(emit, busy: true);
    try {
      if (event.action == IntakeAction.restore) {
        _drafts
          ..clear()
          ..addAll(await repository.load());
        await repository.cleanOrphanFiles();
      } else if (event.action == IntakeAction.add) {
        String? failure;
        for (final path in event.paths) {
          try {
            _drafts.add(await repository.add(path));
            _publish(emit, busy: true);
          } on Object catch (error) {
            failure = intakeFailureKey(
              error,
              fallback: error is FormatException
                  ? LocaleKeys.intake_invalidPhoto
                  : LocaleKeys.intake_localSaveFailed,
            );
          }
        }
        _publish(emit, error: failure);
        if (canContinue) add(const IntakeEvent(IntakeAction.advance));
        return;
      } else if (event.action != IntakeAction.advance) {
        final draft = _drafts.where((d) => d.id == event.id).firstOrNull;
        if (draft == null) return;
        switch (event.action) {
          case IntakeAction.discard:
            await repository.remove(draft);
            _drafts.remove(draft);
            _discarding.remove(draft.id);
          case IntakeAction.select:
            final choice = draft.choices
                .where((c) => c.itemKey == event.choiceKey)
                .firstOrNull;
            if (choice != null && !choice.locked) {
              choice.selected = event.value!;
            }
            await repository.persist(draft);
          case IntakeAction.ownership:
            final ownership = event.value! ? 'owning' : 'wanting';
            if (event.choiceKey == null) draft.ownership = ownership;
            for (final choice in draft.choices.where(
              (c) =>
                  !c.locked &&
                  (event.choiceKey == null || c.itemKey == event.choiceKey),
            )) {
              choice.ownership = ownership;
            }
            await repository.persist(draft);
          case IntakeAction.manual:
            if (!canContinue ||
                draft.phase != DraftPhase.manual ||
                event.edit == null ||
                event.edit!.state == 'archived') {
              break;
            }
            draft.choices.add(
              IntakeChoice(
                itemKey: intakeKey(),
                generationKey: intakeKey(),
                metadata: event.edit!.metadata,
                ownership: event.edit!.state,
              ),
            );
            await _beginSave(draft);
          case IntakeAction.save:
            if (canContinue &&
                draft.phase == DraftPhase.ready &&
                draft.choices.any((c) => c.selected && !c.enqueued)) {
              await _beginSave(draft);
            }
          case IntakeAction.retry:
            if (canContinue) {
              draft.failure = null;
              await repository.persist(draft);
            }
          case IntakeAction.restore || IntakeAction.add || IntakeAction.advance:
            break;
        }
      }
      for (final draft in List<IntakeDraft>.of(_drafts)) {
        if (!canContinue) break;
        if (draft.failure != null || _discarding.contains(draft.id)) continue;
        try {
          if (draft.phase == DraftPhase.discarded) {
            await repository.remove(draft);
            _drafts.remove(draft);
            continue;
          }
          if (draft.phase == DraftPhase.local ||
              draft.phase == DraftPhase.uploading) {
            await repository.upload(
              draft,
              (value) => _publish(
                emit,
                busy: true,
                progress: value,
                activeDraftId: draft.id,
              ),
              () => canContinue && !_discarding.contains(draft.id),
            );
            _publish(emit, busy: true);
          }
          if (!canContinue) break;
          if (_discarding.contains(draft.id)) continue;
          if (draft.phase == DraftPhase.uploaded) {
            await repository.detect(draft);
          }
          if (!canContinue) break;
          if (_discarding.contains(draft.id)) continue;
          if (_visible && draft.phase == DraftPhase.detecting) {
            await repository.poll(draft);
          }
          if (!canContinue) break;
          if (_discarding.contains(draft.id)) continue;
          if (draft.phase == DraftPhase.saving) {
            await repository.save(
              draft,
              () => canContinue && !_discarding.contains(draft.id),
            );
          }
          if (_discarding.contains(draft.id)) continue;
          if (draft.phase == DraftPhase.finished && canContinue) {
            await repository.finish(draft);
            _drafts.remove(draft);
          }
        } on Object catch (error) {
          draft.failure = error is FormApiException
              ? switch (error.failure) {
                  ApiFailure.unavailable => 'unavailable',
                  ApiFailure.missingSession => 'missingSession',
                  ApiFailure.incompatible => 'wardrobeInvalidResponse',
                  ApiFailure.rejected => 'rejected',
                }
              : 'intake.failed';
          await repository.persist(draft);
        }
      }
      _publish(emit);
    } on Object {
      _publish(emit, error: 'intake.failed');
    } finally {
      if (state.busy) _publish(emit);
      if (canContinue &&
          _visible &&
          _drafts.any(
            (d) => d.phase == DraftPhase.detecting && d.failure == null,
          )) {
        _timer = Timer(
          pollInterval,
          () => add(const IntakeEvent(IntakeAction.advance)),
        );
      }
    }
  }

  Future<void> _beginSave(IntakeDraft draft) async {
    for (final choice in draft.choices.where(
      (c) => c.selected && !c.enqueued,
    )) {
      choice.command ??= {
        if (choice.proposal != null)
          'detectionProposalId': choice.proposal!.id
        else ...{
          'sourcePhotoId': draft.sourceId,
          'metadata': choice.metadata!.toJson(),
        },
        'state': choice.ownership,
        'idempotencyKey': choice.itemKey,
      };
    }
    draft.phase = DraftPhase.saving;
    await repository.persist(draft);
  }

  @override
  Future<void> close() {
    _online = false;
    _timer?.cancel();
    return super.close();
  }
}
