import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/intake/intake_failure.dart';
import 'package:form_mobile/features/settings/character/collage_geometry.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/character_draft.dart';
import 'package:form_mobile/repository/character_draft_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:image_picker/image_picker.dart';

enum CharacterStep { select, crop, review, finished }

class CharacterSetupState {
  const CharacterSetupState({
    this.draft,
    this.step = CharacterStep.select,
    this.index = 0,
    this.busy = false,
    this.online = false,
    this.progress,
    this.error,
  });
  final CharacterDraft? draft;
  final CharacterStep step;
  final int index;
  final bool busy;
  final bool online;
  final double? progress;
  final String? error;
  bool get editable => !busy && !(draft?.locked ?? false);
  bool get canSubmit =>
      online &&
      !busy &&
      draft?.previewPath != null &&
      step == CharacterStep.review;
  CharacterPhoto get photo => draft!.photos[index];
  CollageTile get tile => collageLayout(draft!.photos.length)[index];
  CropBounds get bounds => photo.crop.bounds(photo.width, photo.height, tile);
  bool get isLastPhoto => index == draft!.photos.length - 1;
  bool get lowResolution =>
      photo.crop.lowResolution(photo.width, photo.height, tile);

  CharacterSetupState copyWith({
    CharacterDraft? draft,
    CharacterStep? step,
    int? index,
    bool? busy,
    bool? online,
    double? progress,
    String? error,
  }) => CharacterSetupState(
    draft: draft ?? this.draft,
    step: step ?? this.step,
    index: index ?? this.index,
    busy: busy ?? this.busy,
    online: online ?? this.online,
    progress: progress,
    error: error,
  );
}

class CharacterSetupCubit extends Cubit<CharacterSetupState> {
  CharacterSetupCubit(
    this.repository, {
    required bool online,
    Future<List<String>> Function()? pick,
  }) : pick = pick ?? _pick,
       super(CharacterSetupState(online: online));
  final CharacterDraftRepository repository;
  final Future<List<String>> Function() pick;

  static Future<List<String>> _pick() async =>
      (await ImagePicker().pickMultiImage()).map((f) => f.path).toList();

  void setOnline({required bool online}) =>
      emit(state.copyWith(online: online));
  void _update(CharacterSetupState next) {
    if (!isClosed) emit(next);
  }

  String _failure(Object error) => error is FormApiException
      ? switch (error.failure) {
          ApiFailure.unavailable => LocaleKeys.character_offline,
          ApiFailure.missingSession => LocaleKeys.missingSession,
          ApiFailure.incompatible => LocaleKeys.character_incompatible,
          ApiFailure.rejected => LocaleKeys.character_failed,
        }
      : intakeFailureKey(error, fallback: LocaleKeys.character_failed);

  Future<void> restore() async {
    _update(state.copyWith(busy: true));
    try {
      final draft = await repository.load();
      _update(
        state.copyWith(
          draft: draft,
          busy: false,
          step: draft == null
              ? CharacterStep.select
              : draft.previewPath == null
              ? CharacterStep.crop
              : CharacterStep.review,
        ),
      );
    } on Object catch (error) {
      _update(state.copyWith(busy: false, error: _failure(error)));
    }
  }

  Future<void> choose() async {
    if (!state.editable) return;
    _update(state.copyWith(busy: true));
    try {
      final paths = await pick();
      if (paths.isEmpty) {
        _update(state.copyWith(busy: false));
        return;
      }
      if (paths.length > 4) {
        _update(
          state.copyWith(busy: false, error: LocaleKeys.character_photoCount),
        );
        return;
      }
      final old = state.draft;
      final draft = await repository.prepare(paths);
      // The old files are removed without clearing the new draft's checkpoint.
      if (old != null) await repository.removeFiles(old);
      _update(
        state.copyWith(
          draft: draft,
          step: CharacterStep.crop,
          index: 0,
          busy: false,
        ),
      );
    } on Object catch (error) {
      _update(
        state.copyWith(
          busy: false,
          error: intakeFailureKey(
            error,
            fallback: LocaleKeys.intake_invalidPhoto,
          ),
        ),
      );
    }
  }

  void zoom(double value) {
    if (!state.editable || state.step != CharacterStep.crop) return;
    state.photo.crop = state.photo.crop.withZoom(value);
    state.draft!.previewPath = null;
    _update(state.copyWith());
  }

  void pan(double dx, double dy) {
    if (!state.editable || state.step != CharacterStep.crop) return;
    state.photo.crop = state.photo.crop.pan(
      state.photo.width,
      state.photo.height,
      state.tile,
      dx,
      dy,
    );
    state.draft!.previewPath = null;
    _update(state.copyWith());
  }

  void note(String value) {
    if (!state.editable) return;
    state.draft!.note = value;
    _update(state.copyWith());
  }

  Future<void> crop(int index) async {
    if (!state.editable || index < 0 || index >= state.draft!.photos.length) {
      return;
    }
    await _checkpoint(CharacterStep.crop, index);
  }

  Future<void> back() async {
    if (!state.editable) return;
    await _checkpoint(
      state.index == 0 ? CharacterStep.select : CharacterStep.crop,
      state.index == 0 ? 0 : state.index - 1,
    );
  }

  Future<void> _checkpoint(CharacterStep step, int index) async {
    _update(state.copyWith(busy: true));
    try {
      await repository.persist(state.draft!);
      _update(state.copyWith(step: step, index: index, busy: false));
    } on Object catch (error) {
      _update(state.copyWith(busy: false, error: _failure(error)));
    }
  }

  Future<void> next() async {
    if (!state.editable) return;
    if (state.index < state.draft!.photos.length - 1) {
      await crop(state.index + 1);
      return;
    }
    _update(state.copyWith(busy: true));
    try {
      await repository.render(state.draft!);
      _update(state.copyWith(step: CharacterStep.review, busy: false));
    } on Object catch (error) {
      _update(state.copyWith(busy: false, error: _failure(error)));
    }
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;
    final draft = state.draft!;
    if (draft.note.length > 1000) {
      _update(state.copyWith(error: LocaleKeys.character_noteLimit));
      return;
    }
    _update(state.copyWith(busy: true, progress: 0));
    try {
      draft.locked = true;
      await repository.persist(draft);
      await repository.upload(
        draft,
        (value) => _update(state.copyWith(progress: value)),
        () => state.online && !isClosed,
      );
      if (!state.online || isClosed) {
        throw const FormApiException(ApiFailure.unavailable);
      }
      draft.createdId ??= await repository.sheets.create(
        draft.assetId!,
        draft.note,
        draft.creationKey,
      );
      await repository.persist(draft);
      await repository.sheets.fetch();
      await repository.discard(draft);
      _update(state.copyWith(step: CharacterStep.finished, busy: false));
    } on Object catch (error) {
      _update(state.copyWith(busy: false, error: _failure(error)));
    }
  }

  Future<void> discard() async {
    if (state.busy || state.draft == null) return;
    _update(state.copyWith(busy: true));
    try {
      await repository.discard(state.draft!);
      _update(CharacterSetupState(online: state.online));
    } on Object catch (error) {
      _update(state.copyWith(busy: false, error: _failure(error)));
    }
  }
}
