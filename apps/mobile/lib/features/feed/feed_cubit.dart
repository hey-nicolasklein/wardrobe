import 'dart:async';

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
  );
}

class FeedCubit extends Cubit<FeedState> {
  FeedCubit(
    this.lookRepository,
    this.wardrobeRepository,
    this.characterSheets,
  ) : super(const FeedState()) {
    _subscription = lookRepository.changes.listen(
      (_) => unawaited(_reloadLocal()),
    );
  }

  final LookRepository lookRepository;
  final WardrobeRepository wardrobeRepository;
  final CharacterSheetRepository characterSheets;
  late final StreamSubscription<void> _subscription;
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

  Future<void> toggleMark(String lookId, {required bool liked}) async {
    if (!state.online) return;
    final current = liked
        ? state.liked[lookId] ?? false
        : state.saved[lookId] ?? false;
    await lookRepository.setLookMarked(
      lookId,
      liked: liked,
      marked: !current,
    );
    await _reloadLocal();
  }

  void _schedulePoll(FeedState next) {
    _poll?.cancel();
    final running = next.looks?.any((record) => record.look.isActive) ?? false;
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
      marks[look.id] = await lookRepository.lookMarked(look.id, liked: liked);
    }
    return marks;
  }

  Future<void> _reloadLocal() async {
    final looks = await lookRepository.cached();
    final pendingStarts = await lookRepository.loadLookStarts();
    final liked = await _loadMarks(looks.map((l) => l.look), liked: true);
    final saved = await _loadMarks(looks.map((l) => l.look), liked: false);
    if (isClosed) return;
    emit(
      state.copyWith(
        looks: looks,
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
      final looks = await lookRepository.refresh();
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
    return super.close();
  }
}
