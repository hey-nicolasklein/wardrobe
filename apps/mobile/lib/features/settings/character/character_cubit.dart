import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

class CharacterState {
  const CharacterState({
    this.sheets = const [],
    this.loading = false,
    this.online = false,
    this.stale = true,
    this.busy = false,
    this.error,
  });
  final List<CharacterSheet> sheets;
  final bool loading;
  final bool online;
  final bool stale;
  final bool busy;
  final String? error;
  CharacterSheet? get active => sheets.where((s) => s.active).firstOrNull;
  CharacterSheet? get current => active ?? sheets.firstOrNull;
  List<CharacterSheet> get pending =>
      sheets.where((s) => s.isPending && s.id != current?.id).toList();
  List<CharacterSheet> get history =>
      sheets.where((s) => !s.active && !s.isPending).toList();
  List<CharacterSheet> historyExcept(String? id) =>
      history.where((s) => s.id != id).toList();
  int get pastCount => historyExcept(current?.id).length;
  bool get canMutate => online && !stale && !busy;
  bool get canCreate => online && !busy;
  CharacterSheet? find(String id) =>
      sheets.where((s) => s.id == id).firstOrNull;
  CharacterState copyWith({
    List<CharacterSheet>? sheets,
    bool? loading,
    bool? online,
    bool? stale,
    bool? busy,
    String? error,
  }) => CharacterState(
    sheets: sheets ?? this.sheets,
    loading: loading ?? this.loading,
    online: online ?? this.online,
    stale: stale ?? this.stale,
    busy: busy ?? this.busy,
    error: error,
  );
}

class CharacterCubit extends Cubit<CharacterState> {
  CharacterCubit(
    this.repository, {
    this.pollInterval = const Duration(seconds: 3),
  }) : super(const CharacterState()) {
    _subscription = repository.changes.listen((_) => unawaited(loadCache()));
  }
  final CharacterSheetRepository repository;
  final Duration pollInterval;
  late final StreamSubscription<void> _subscription;
  Timer? _poll;
  bool _foreground = true;
  int _availability = 0;
  ({String id, bool delete, String key})? _command;

  Future<void> loadCache() async {
    final sheets = await repository.cached();
    if (!isClosed) emit(state.copyWith(sheets: sheets, error: state.error));
  }

  void setOnline({required bool online}) {
    _availability++;
    emit(state.copyWith(online: online, stale: !online || state.stale));
    if (online && _foreground) unawaited(refresh());
    _schedule();
  }

  void setForeground({required bool foreground}) {
    _foreground = foreground;
    if (foreground && state.online) unawaited(refresh());
    _schedule();
  }

  void _schedule() {
    _poll?.cancel();
    if (_foreground &&
        state.online &&
        !state.stale &&
        !state.loading &&
        !state.busy &&
        state.sheets.any((s) => s.isPending)) {
      _poll = Timer(pollInterval, () => unawaited(refresh()));
    }
  }

  @override
  void onChange(Change<CharacterState> change) {
    super.onChange(change);
    // Schedule after the new state has been installed.
    scheduleMicrotask(() {
      if (!isClosed) _schedule();
    });
  }

  Future<void> refresh() async {
    if (state.loading || !state.online || !_foreground || isClosed) return;
    final availability = _availability;
    emit(state.copyWith(loading: true));
    try {
      final sheets = await repository.fetch();
      if (!isClosed && availability == _availability) {
        emit(state.copyWith(sheets: sheets, stale: false, loading: false));
      }
    } on FormApiException catch (error) {
      if (!isClosed && availability == _availability) {
        emit(
          state.copyWith(loading: false, stale: true, error: failureKey(error)),
        );
      }
    } finally {
      if (!isClosed && state.loading) emit(state.copyWith(loading: false));
      if (!isClosed && availability != _availability && state.online) {
        unawaited(refresh());
      }
    }
  }

  static String failureKey(FormApiException error) => switch (error.failure) {
    ApiFailure.unavailable => LocaleKeys.character_offline,
    ApiFailure.missingSession => LocaleKeys.missingSession,
    ApiFailure.incompatible => LocaleKeys.character_incompatible,
    ApiFailure.rejected => switch (error.code) {
      'active-character-sheet' => LocaleKeys.character_activeDelete,
      'character-sheet-processing' => LocaleKeys.character_pendingDelete,
      _ => LocaleKeys.character_failed,
    },
  };

  bool get hasPendingCommand => _command != null;
  bool canActivate(CharacterSheet sheet) =>
      state.canMutate &&
      (_command == null
          ? sheet.canActivate
          : _command!.id == sheet.id && !_command!.delete);
  bool canDelete(CharacterSheet sheet) =>
      state.canMutate &&
      (_command == null
          ? sheet.canDelete
          : _command!.id == sheet.id && _command!.delete);
  Future<void> retry() async {
    final command = _command;
    if (command != null) await _mutate(command.id, delete: command.delete);
  }

  Future<void> activate(String id) => _mutate(id, delete: false);
  Future<void> delete(String id) => _mutate(id, delete: true);

  Future<void> _mutate(String id, {required bool delete}) async {
    if (!state.canMutate) return;
    final sheet = state.find(id);
    final pending = _command;
    if (pending != null && (pending.id != id || pending.delete != delete)) {
      return;
    }
    if (pending == null &&
        (sheet == null || !(delete ? sheet.canDelete : sheet.canActivate))) {
      return;
    }
    final command = _command ??= (
      id: id,
      delete: delete,
      key: newIdempotencyKey(),
    );
    emit(state.copyWith(busy: true));
    try {
      if (delete) {
        await repository.delete(id);
      } else {
        await repository.activate(id, command.key);
      }
      _command = null;
      final sheets = await repository.cached();
      if (!isClosed) emit(state.copyWith(sheets: sheets, busy: false));
    } on FormApiException catch (error) {
      if (error.failure == ApiFailure.rejected) _command = null;
      if (!isClosed) {
        emit(state.copyWith(busy: false, error: failureKey(error)));
      }
    }
  }

  @override
  Future<void> close() async {
    _poll?.cancel();
    await _subscription.cancel();
    return super.close();
  }
}
