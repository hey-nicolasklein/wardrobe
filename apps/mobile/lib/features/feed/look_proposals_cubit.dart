import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

/// Outfits one swipe session shows at most. High enough to feel endless while
/// the user narrows the outfit down with marks, low enough to bound a session.
const maxSessionProposals = 20;

/// How the user marked a piece on a proposal card.
enum PieceMark { keep, exclude }

class LookProposalsState {
  const LookProposalsState({
    this.proposals,
    this.picked = const {},
    this.skipped = const {},
    this.marks = const {},
    this.proposing = false,
    this.failure,
  });

  /// The session's proposals in planning order. Null until the first load.
  final List<Look>? proposals;

  /// Proposals swiped right and sent off to render.
  final Set<String> picked;

  /// Proposals swiped left.
  final Set<String> skipped;

  /// Pieces kept for, or ruled out of, the next proposals.
  final Map<String, PieceMark> marks;

  /// A batch is being requested from the server.
  final bool proposing;
  final ApiFailure? failure;

  Set<String> get kept => {
    for (final entry in marks.entries)
      if (entry.value == PieceMark.keep) entry.key,
  };

  Set<String> get excluded => {
    for (final entry in marks.entries)
      if (entry.value == PieceMark.exclude) entry.key,
  };

  /// Proposals still to decide on, in deck order. Failed plans drop out.
  List<Look> get deck => [
    for (final look in proposals ?? const <Look>[])
      if (look.state != 'failed' &&
          !picked.contains(look.id) &&
          !skipped.contains(look.id))
        look,
  ];

  int get decided => picked.length + skipped.length;

  bool get planning => proposals?.any((look) => look.isActive) ?? true;

  /// A round ends with the one outfit the user picked, or when the deck runs
  /// out of outfits.
  bool get finished =>
      proposals != null && !proposing && (picked.isNotEmpty || deck.isEmpty);

  LookProposalsState copyWith({
    List<Look>? proposals,
    Set<String>? picked,
    Set<String>? skipped,
    Map<String, PieceMark>? marks,
    bool? proposing,
    ApiFailure? Function()? failure,
  }) => LookProposalsState(
    proposals: proposals ?? this.proposals,
    picked: picked ?? this.picked,
    skipped: skipped ?? this.skipped,
    marks: marks ?? this.marks,
    proposing: proposing ?? this.proposing,
    failure: failure == null ? this.failure : failure(),
  );
}

/// One swipe session. Polls proposals while they are planned, renders the
/// ones swiped right, and keeps the deck topped up: kept pieces become fixed
/// pieces of the next proposals, excluded ones never come back.
class LookProposalsCubit extends Cubit<LookProposalsState> {
  LookProposalsCubit(
    this.looks, {
    required this.quality,
    this.request,
    this.pollInterval = const Duration(seconds: 1),
  }) : super(const LookProposalsState()) {
    unawaited(refresh());
  }

  final LookRepository looks;
  final String quality;

  /// The composer's propose body. Null when the page was opened without one,
  /// which turns off topping up and "more outfits".
  final Map<String, dynamic>? request;
  final Duration pollInterval;
  Timer? _poll;

  /// Bumped by every adjustment, so a poll that started before it cannot
  /// bring back the outfits as they were.
  int _revision = 0;

  Future<void> refresh() async {
    _poll?.cancel();
    final revision = _revision;
    try {
      final fresh = await looks.proposals();
      if (isClosed) return;
      if (revision != _revision) {
        _poll = Timer(pollInterval, () => unawaited(refresh()));
        return;
      }
      // Decided proposals keep their place here, even after the server
      // dropped them, so the end screen can show what was picked.
      final kept = [
        ...?state.proposals?.where(
          (look) =>
              (state.picked.contains(look.id) ||
                  state.skipped.contains(look.id)) &&
              !fresh.any((other) => other.id == look.id),
        ),
      ];
      emit(
        state.copyWith(
          proposals: [...fresh, ...kept]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          failure: () => null,
        ),
      );
    } on FormApiException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(failure: () => error.failure));
    }
    if (state.planning) _poll = Timer(pollInterval, () => unawaited(refresh()));
  }

  /// Keeps a piece: it moves into the waiting outfits and all later ones.
  /// The outfit it was marked on ([onLookId]) stays as the user sees it.
  Future<void> keep(String itemId, {String? onLookId}) =>
      _mark(itemId, PieceMark.keep, onLookId);

  /// Swaps a piece out of the waiting outfits and all later ones. The outfit
  /// it was marked on ([onLookId]) stays as the user sees it.
  Future<void> swap(String itemId, {String? onLookId}) =>
      _mark(itemId, PieceMark.exclude, onLookId);

  /// A tap on a piece: the first keeps it, the second leaves it out, the
  /// third drops the mark again.
  Future<void> cycle(String itemId, {String? onLookId}) =>
      switch (state.marks[itemId]) {
        null => keep(itemId, onLookId: onLookId),
        PieceMark.keep => swap(itemId, onLookId: onLookId),
        PieceMark.exclude => Future.sync(() => unmark(itemId)),
      };

  /// Drops a mark. Outfits already adjusted stay as they are.
  void unmark(String itemId) =>
      emit(state.copyWith(marks: {...state.marks}..remove(itemId)));

  Future<void> _mark(String itemId, PieceMark mark, String? onLookId) async {
    emit(state.copyWith(marks: {...state.marks, itemId: mark}));
    _revision++;
    try {
      final adjusted = await looks.adjustProposals(
        keep: mark == PieceMark.keep ? [itemId] : const [],
        exclude: mark == PieceMark.exclude ? [itemId] : const [],
        except: [?onLookId],
      );
      if (isClosed) return;
      _revision++;
      final byId = {for (final look in adjusted) look.id: look};
      emit(
        state.copyWith(
          proposals: [
            for (final look in state.proposals ?? const <Look>[])
              byId[look.id] ?? look,
          ],
          failure: () => null,
        ),
      );
    } on FormApiException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(failure: () => error.failure));
    }
  }

  void skip(String lookId) {
    emit(state.copyWith(skipped: {...state.skipped, lookId}));
    unawaited(_topUp());
  }

  /// Renders the outfit and ends the round: one pick per round.
  Future<void> pick(String lookId) async {
    if (state.picked.isNotEmpty) return;
    emit(state.copyWith(picked: {...state.picked, lookId}));
    try {
      await looks.render(lookId, quality: quality);
    } on FormApiException catch (error) {
      if (isClosed) return;
      // Back on the deck, so the user can try again.
      emit(
        state.copyWith(
          picked: {...state.picked}..remove(lookId),
          failure: () => error.failure,
        ),
      );
    }
  }

  /// Keeps three proposals ahead of the user until the session limit. New
  /// ones are planned with the marks so far.
  Future<void> _topUp() async {
    final body = request;
    if (body == null || state.proposing || state.picked.isNotEmpty) return;
    final ahead = state.deck.length;
    final room = maxSessionProposals - state.decided - ahead;
    final count = (3 - ahead).clamp(0, room);
    if (count <= 0) return;
    final exact = {...?(body['exactItemIds'] as List?)?.cast<String>()};
    emit(state.copyWith(proposing: true, failure: () => null));
    try {
      await looks.propose(
        {
          ...body,
          'exactItemIds': [...exact, ...state.kept.difference(exact)],
          'idempotencyKey': newIdempotencyKey(),
        },
        count: count,
        append: true,
        excludedItemIds: state.excluded.toList(),
      );
      if (isClosed) return;
      emit(state.copyWith(proposing: false));
      await refresh();
    } on FormApiException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(proposing: false, failure: () => error.failure));
    }
  }

  /// Starts the next round for the composer's request, keeping the marks so
  /// far, so the user styles on from where the last round ended.
  Future<void> restyle() async {
    final body = request;
    if (body == null || state.proposing) return;
    final marks = state.marks;
    emit(LookProposalsState(marks: marks, proposing: true));
    final exact = {...?(body['exactItemIds'] as List?)?.cast<String>()};
    try {
      await looks.propose(
        {
          ...body,
          'exactItemIds': [...exact, ...state.kept.difference(exact)],
          'idempotencyKey': newIdempotencyKey(),
        },
        excludedItemIds: state.excluded.toList(),
      );
      if (isClosed) return;
      await refresh();
      if (!isClosed) emit(state.copyWith(proposing: false));
    } on FormApiException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(proposing: false, failure: () => error.failure));
    }
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}
