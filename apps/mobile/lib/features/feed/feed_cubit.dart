import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class FeedState {
  const FeedState({
    this.looks,
    this.itemsById = const {},
    this.pendingStarts = const {},
    this.liked = const {},
    this.saved = const {},
    this.views = const {},
    this.revealed = const {},
    this.hasActiveCharacterReference,
    this.loading = false,
    this.stale = true,
    this.failure,
    this.online = true,
    this.pendingPhotos = const [],
    this.pendingWorn = const {},
  });

  final List<CachedLook>? looks;
  final Map<String, WardrobeItem> itemsById;
  final Map<String, List<String>> pendingStarts;
  final Map<String, bool> liked;
  final Map<String, bool> saved;
  final Map<String, LookFeedView> views;
  final Set<String> revealed;
  final bool? hasActiveCharacterReference;
  final bool loading;
  final bool stale;
  final ApiFailure? failure;
  final bool online;

  /// Local paths of photos being uploaded as looks. They show as developing
  /// prints until the server has them.
  final List<String> pendingPhotos;

  /// Local photos being added to a combination as the photo it was worn in,
  /// by look id. The look shows it developing until the server has it.
  final Map<String, String> pendingWorn;

  /// Looks shown on their own: combinations, photo looks and generated looks
  /// that are not an image of one of them, see [imagesOf].
  List<CachedLook> get archive => [
    for (final record in looks ?? const <CachedLook>[])
      if (!_isImageOfBase(record.look)) record,
  ];

  /// The AI images made of the combination or photo look [lookId], newest
  /// first.
  List<CachedLook> imagesOf(String lookId) => [
    for (final record in looks ?? const <CachedLook>[])
      if (record.look.parentLookId == lookId &&
          record.look.isGenerated &&
          _baseIds.contains(lookId))
        record,
  ];

  /// What a look shows on its print: its own photo, or its newest finished
  /// image. Null means the pieces laid out flat.
  CachedLook? coverOf(CachedLook record) {
    if (record.look.cardAssetId != null) return record;
    for (final image in imagesOf(record.look.id)) {
      if (image.look.isReady && image.look.cardAssetId != null) return image;
    }
    return null;
  }

  Set<String> get _baseIds => {
    for (final record in looks ?? const <CachedLook>[])
      if (record.look.isBase) record.look.id,
  };

  bool _isImageOfBase(Look look) =>
      look.parentLookId != null &&
      look.isGenerated &&
      _baseIds.contains(look.parentLookId);

  String get failureKey => switch (failure) {
    ApiFailure.incompatible => LocaleKeys.feedInvalidResponse,
    ApiFailure.missingSession => LocaleKeys.missingSession,
    ApiFailure.rejected => LocaleKeys.rejected,
    ApiFailure.unavailable || null => LocaleKeys.unavailable,
  };

  FeedState copyWith({
    List<CachedLook>? looks,
    Map<String, WardrobeItem>? itemsById,
    Map<String, List<String>>? pendingStarts,
    Map<String, bool>? liked,
    Map<String, bool>? saved,
    Map<String, LookFeedView>? views,
    Set<String>? revealed,
    bool? hasActiveCharacterReference,
    bool? loading,
    bool? stale,
    ApiFailure? failure,
    bool clearFailure = false,
    bool? online,
    List<String>? pendingPhotos,
    Map<String, String>? pendingWorn,
  }) => FeedState(
    looks: looks ?? this.looks,
    itemsById: itemsById ?? this.itemsById,
    pendingStarts: pendingStarts ?? this.pendingStarts,
    liked: liked ?? this.liked,
    saved: saved ?? this.saved,
    views: views ?? this.views,
    revealed: revealed ?? this.revealed,
    hasActiveCharacterReference:
        hasActiveCharacterReference ?? this.hasActiveCharacterReference,
    loading: loading ?? this.loading,
    stale: stale ?? this.stale,
    failure: clearFailure ? null : (failure ?? this.failure),
    online: online ?? this.online,
    pendingPhotos: pendingPhotos ?? this.pendingPhotos,
    pendingWorn: pendingWorn ?? this.pendingWorn,
  );
}

class FeedCubit extends Cubit<FeedState> {
  FeedCubit(
    this.lookRepository,
    this.wardrobeRepository,
    this.characterSheets,
  ) : super(const FeedState()) {
    _characterSubscription = characterSheets.changes.listen(
      (_) => unawaited(_reloadCharacter()),
    );
    _subscription = lookRepository.changes.listen(
      (_) => unawaited(_reloadLocal()),
    );
  }

  final LookRepository lookRepository;
  final WardrobeRepository wardrobeRepository;
  final CharacterSheetRepository characterSheets;
  late final StreamSubscription<void> _subscription;
  late final StreamSubscription<void> _characterSubscription;

  Future<void> _reloadCharacter() async {
    final sheets = await characterSheets.cached();
    if (!isClosed) {
      emit(
        state.copyWith(
          hasActiveCharacterReference: sheets.any((s) => s.isActiveReady),
        ),
      );
    }
  }

  bool _refreshing = false;
  int _availability = 0;
  Timer? _poll;
  bool _foreground = true;

  void setForeground({required bool foreground}) {
    _foreground = foreground;
    _schedulePoll(state);
  }

  void setOnline({required bool online}) {
    if (state.online == online) return;
    emit(state.copyWith(online: online));
  }

  /// Switching between worn and flat also hides revealed pieces, as in the
  /// PWA.
  void setLookView(String lookId, LookFeedView view) {
    emit(
      state.copyWith(
        views: {...state.views, lookId: view},
        revealed: {...state.revealed}..remove(lookId),
      ),
    );
  }

  void toggleRevealed(String lookId) {
    final next = {...state.revealed};
    if (!next.remove(lookId)) next.add(lookId);
    emit(state.copyWith(revealed: next));
  }

  /// Hearts go to the server (they weight future shot types) and show right
  /// away; a failed request takes the heart back. Bookmarks stay on the phone.
  Future<void> toggleMark(String lookId, {required bool liked}) async {
    if (!state.online) return;
    final current = liked
        ? state.liked[lookId] ?? false
        : state.saved[lookId] ?? false;
    if (!liked) {
      await lookRepository.setLookMarked(
        lookId,
        liked: false,
        marked: !current,
      );
      await _reloadLocal();
      return;
    }
    emit(state.copyWith(liked: {...state.liked, lookId: !current}));
    try {
      await lookRepository.setLiked(lookId, liked: !current);
    } on FormApiException {
      if (!isClosed) {
        emit(state.copyWith(liked: {...state.liked, lookId: current}));
      }
    }
  }

  void _schedulePoll(FeedState next) {
    _poll?.cancel();
    // Photo looks are polled too, until their pieces are detected.
    final running =
        next.looks?.any(
          (record) => record.look.isActive || record.look.isAnalysing,
        ) ??
        false;
    if (_foreground && !next.stale && !next.loading && running) {
      _poll = Timer(const Duration(seconds: 3), () => unawaited(refresh()));
    }
  }

  @override
  void onChange(Change<FeedState> change) {
    super.onChange(change);
    _schedulePoll(change.nextState);
  }

  Future<Map<String, bool>> _loadMarks(
    Iterable<Look> looks, {
    required bool liked,
  }) async {
    final marks = <String, bool>{};
    for (final look in looks) {
      marks[look.id] = liked
          ? look.liked
          : await lookRepository.lookMarked(look.id, liked: false);
    }
    return marks;
  }

  /// Also rereads wardrobe items, so a look started from a piece added since
  /// the last refresh can show that piece right away.
  Future<void> _reloadLocal() async {
    final looks = await lookRepository.cached();
    final wardrobe = await wardrobeRepository.cached();
    final pendingStarts = await lookRepository.loadLookStarts();
    final liked = await _loadMarks(looks.map((l) => l.look), liked: true);
    final saved = await _loadMarks(looks.map((l) => l.look), liked: false);
    if (isClosed) return;
    emit(
      state.copyWith(
        looks: looks,
        itemsById: {for (final item in wardrobe) item.item.id: item.item},
        pendingStarts: pendingStarts,
        liked: liked,
        saved: saved,
      ),
    );
  }

  void markUnavailable() {
    _availability++;
    emit(state.copyWith(stale: true, online: false));
  }

  Future<void> loadCache() async {
    final characters = await characterSheets.cached();
    final looks = await lookRepository.cached();
    final hasSnapshot = await lookRepository.hasSnapshot();
    final wardrobe = await wardrobeRepository.cached();
    final pendingStarts = await lookRepository.loadLookStarts();
    final liked = await _loadMarks(looks.map((l) => l.look), liked: true);
    final saved = await _loadMarks(looks.map((l) => l.look), liked: false);
    if (isClosed) return;
    emit(
      FeedState(
        looks: looks.isEmpty && !hasSnapshot ? null : looks,
        itemsById: {for (final item in wardrobe) item.item.id: item.item},
        hasActiveCharacterReference: characters.any((s) => s.isActiveReady),
        pendingStarts: pendingStarts,
        liked: liked,
        saved: saved,
        stale: false,
      ),
    );
  }

  Future<void> refresh() async {
    if (_refreshing || isClosed) return;
    _refreshing = true;
    final availability = _availability;
    emit(state.copyWith(loading: true, clearFailure: true));
    try {
      var looks = await lookRepository.refresh();
      try {
        await lookRepository.uploadLocalHearts(looks.map((l) => l.look));
        looks = await lookRepository.cached();
      } on FormApiException {
        // Retried on the next refresh; the upload flag is only set on success.
      }
      final wardrobe = await wardrobeRepository.cached();
      bool? activeSheet;
      try {
        activeSheet = (await characterSheets.activeReady()) != null;
      } on FormApiException {
        activeSheet = state.hasActiveCharacterReference;
      }
      if (availability != _availability || isClosed) return;
      final pendingStarts = await lookRepository.loadLookStarts();
      final liked = await _loadMarks(looks.map((l) => l.look), liked: true);
      final saved = await _loadMarks(looks.map((l) => l.look), liked: false);
      emit(
        FeedState(
          looks: looks,
          itemsById: {for (final item in wardrobe) item.item.id: item.item},
          pendingStarts: pendingStarts,
          liked: liked,
          saved: saved,
          views: state.views,
          revealed: state.revealed,
          hasActiveCharacterReference: activeSheet,
          stale: false,
          pendingPhotos: state.pendingPhotos,
          pendingWorn: state.pendingWorn,
        ),
      );
    } on FormApiException catch (error) {
      if (availability != _availability || isClosed) return;
      if (error.failure == ApiFailure.unavailable) {
        await _reloadLocal();
        emit(state.copyWith(loading: false, stale: true, online: false));
      } else if (error.failure == ApiFailure.incompatible) {
        await _reloadLocal();
        emit(
          state.copyWith(
            loading: false,
            stale: false,
            online: true,
            failure: error.failure,
          ),
        );
      } else {
        emit(state.copyWith(loading: false, failure: error.failure));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<String> createLook(LookCommand command, List<String> selectedIds) =>
      lookRepository.create(command, selectedIds);

  /// Puts an AI image on the combination [lookId], see
  /// [LookRepository.createImage].
  Future<String> createImage(
    String lookId, {
    required String mode,
    required String idempotencyKey,
    String? baseAssetId,
    String quality = 'low',
  }) => lookRepository.createImage(
    lookId,
    mode: mode,
    idempotencyKey: idempotencyKey,
    baseAssetId: baseAssetId,
    quality: quality,
  );

  /// Uploads [paths] one after another as photo looks. Each shows as a
  /// developing print until it is in. Returns how many failed.
  Future<int> addPhotoLooks(
    List<String> paths,
    Future<Uint8List> Function(String path) prepare,
  ) async {
    emit(state.copyWith(pendingPhotos: [...state.pendingPhotos, ...paths]));
    var failed = 0;
    for (final path in paths) {
      try {
        await lookRepository.createPhotoLook(await prepare(path));
      } on Object {
        failed++;
      } finally {
        if (!isClosed) {
          emit(
            state.copyWith(
              pendingPhotos: [...state.pendingPhotos]..remove(path),
            ),
          );
        }
      }
    }
    return failed;
  }

  /// Adds the photo at [path] to the combination [lookId] as the photo it
  /// was worn in. Its pieces are found in the background, as for a photo
  /// look.
  Future<void> addWornPhoto(
    String lookId,
    String path,
    Future<Uint8List> Function(String path) prepare,
  ) async {
    emit(state.copyWith(pendingWorn: {...state.pendingWorn, lookId: path}));
    try {
      await lookRepository.createPhotoLook(await prepare(path), lookId: lookId);
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            pendingWorn: {...state.pendingWorn}..remove(lookId),
          ),
        );
      }
    }
  }

  /// Links wardrobe pieces to a combination or photo look.
  Future<void> setLookItems(String lookId, List<String> itemIds) =>
      lookRepository.setItems(lookId, itemIds);

  /// Adds a piece detected on a photo look to the wardrobe, orders its
  /// catalog image and links it to the look.
  Future<void> addFoundPiece(
    Look look,
    LookFoundPiece piece, {
    required String quality,
  }) async {
    final itemId = await lookRepository.addFoundPiece(
      piece,
      quality: quality,
    );
    await lookRepository.setItems(
      look.id,
      {
        ...look.wardrobeItemIds,
        itemId,
      }.toList(),
    );
    await wardrobeRepository.refreshAndNotify();
    await _reloadLocal();
  }

  Future<void> retryLook(String lookId) async {
    await lookRepository.execute(LookCommand.retry(lookId));
  }

  Future<void> deleteLook(String lookId) async {
    await lookRepository.execute(LookCommand.delete(lookId));
  }

  @override
  Future<void> close() async {
    _poll?.cancel();
    await _subscription.cancel();
    await _characterSubscription.cancel();
    return super.close();
  }
}
