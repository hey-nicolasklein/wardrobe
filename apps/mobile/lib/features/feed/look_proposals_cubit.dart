import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

/// Outfits in one round. Short enough that the end is in sight, long enough
/// for marks to steer the later outfits. "More outfits" starts the next round.
const roundSize = 8;

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
    this.undoable,
  });

  /// The session's proposals in planning order. Null until the first load.
  final List<Look>? proposals;

  /// Proposals swiped right and saved to the Looks feed.
  final Set<String> picked;

  /// Proposals swiped left.
  final Set<String> skipped;

  /// Pieces kept for, or ruled out of, the next proposals.
  final Map<String, PieceMark> marks;

  /// A batch is being requested from the server.
  final bool proposing;
  final ApiFailure? failure;

  /// The latest pick while it can still be taken back with
  /// [LookProposalsCubit.undoPick].
  final String? undoable;

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

  /// A round ends when the deck runs out of outfits: [roundSize] is
  /// reached, or there is nothing to top up from.
  bool get finished => proposals != null && !proposing && deck.isEmpty;

  LookProposalsState copyWith({
    List<Look>? proposals,
    Set<String>? picked,
    Set<String>? skipped,
    Map<String, PieceMark>? marks,
    bool? proposing,
    ApiFailure? Function()? failure,
    String? Function()? undoable,
  }) => LookProposalsState(
    proposals: proposals ?? this.proposals,
    picked: picked ?? this.picked,
    skipped: skipped ?? this.skipped,
    marks: marks ?? this.marks,
    proposing: proposing ?? this.proposing,
    failure: failure == null ? this.failure : failure(),
    undoable: undoable == null ? this.undoable : undoable(),
  );
}

/// One swipe session. Polls proposals while they are planned, saves every
/// outfit swiped right as a look, for free, and keeps the deck topped up:
/// kept pieces become fixed pieces of the next proposals, excluded ones never
/// come back.
class LookProposalsCubit extends Cubit<LookProposalsState> {
  LookProposalsCubit(
    this.looks, {
    this.request,
    this.pollInterval = const Duration(seconds: 1),
    this.undoWindow = const Duration(seconds: 4),
  }) : super(const LookProposalsState()) {
    unawaited(refresh());
  }

  final LookRepository looks;

  /// The composer's propose body. Null when the page was opened without one,
  /// which turns off topping up and "more outfits".
  final Map<String, dynamic>? request;
  final Duration pollInterval;

  /// How long a pick can be taken back before it is saved as a look.
  final Duration undoWindow;
  Timer? _poll;
  Timer? _pendingKeep;
  Completer<void>? _pendingPick;
  String? _pendingId;

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

  /// Puts back a mark [unmark] dropped. Outfits were never changed back, so
  /// only the mark itself returns.
  void restoreMark(String itemId, PieceMark mark) =>
      emit(state.copyWith(marks: {...state.marks, itemId: mark}));

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

  /// Saves the outfit as a look once [undoWindow] passed without [undoPick],
  /// and moves on to the next one. Completes once kept.
  Future<void> pick(String lookId) {
    if (state.picked.contains(lookId)) return Future.value();
    _flushPending();
    emit(
      state.copyWith(
        picked: {...state.picked, lookId},
        undoable: () => lookId,
      ),
    );
    final done = _pendingPick = Completer<void>();
    _pendingId = lookId;
    _pendingKeep = Timer(undoWindow, () {
      _pendingPick = null;
      _pendingKeep = null;
      _pendingId = null;
      if (!isClosed) emit(state.copyWith(undoable: () => null));
      done.complete(_keep(lookId));
    });
    unawaited(_topUp());
    return done.future;
  }

  /// Saves a pick still waiting out its undo window right away.
  void _flushPending() {
    final id = _pendingId;
    if (id == null || !(_pendingKeep?.isActive ?? false)) return;
    _pendingKeep!.cancel();
    _pendingPick?.complete(_keep(id));
    _pendingKeep = null;
    _pendingPick = null;
    _pendingId = null;
    if (!isClosed) emit(state.copyWith(undoable: () => null));
  }

  /// Takes back the latest pick still inside its [undoWindow]: the outfit
  /// returns to the top of the deck and nothing is saved.
  void undoPick() {
    final timer = _pendingKeep;
    final id = _pendingId;
    if (timer == null || !timer.isActive || id == null) return;
    timer.cancel();
    _pendingKeep = null;
    _pendingId = null;
    _pendingPick?.complete();
    _pendingPick = null;
    emit(
      state.copyWith(
        picked: {...state.picked}..remove(id),
        undoable: () => null,
      ),
    );
  }

  Future<void> _keep(String lookId) async {
    try {
      await looks.keepProposal(lookId);
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

  /// Keeps three proposals ahead of the user until the round is full. New
  /// ones are planned with the marks so far.
  Future<void> _topUp() async {
    final body = request;
    if (body == null || state.proposing) return;
    final ahead = state.deck.length;
    final room = roundSize - state.decided - ahead;
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
    // Closing the sheet inside the undo window keeps the pick.
    _flushPending();
    return super.close();
  }
}
