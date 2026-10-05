import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

/// Outfits one swipe session shows at most.
const maxSessionProposals = 10;

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

  /// The session used up its outfits, or nothing more can be planned.
  bool get finished => proposals != null && !proposing && deck.isEmpty;

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
    this.pollInterval = const Duration(seconds: 2),
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

  /// Marks changed since the open proposals were requested.
  bool _stale = false;

  Future<void> refresh() async {
    _poll?.cancel();
    try {
      final fresh = await looks.proposals();
      if (isClosed) return;
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

  /// Cycles a piece: neutral → keep → exclude → neutral.
  void togglePiece(String itemId) {
    final marks = {...state.marks};
    switch (marks[itemId]) {
      case null:
        marks[itemId] = PieceMark.keep;
      case PieceMark.keep:
        marks[itemId] = PieceMark.exclude;
      case PieceMark.exclude:
        marks.remove(itemId);
    }
    _stale = true;
    emit(state.copyWith(marks: marks));
  }

  void skip(String lookId) {
    emit(state.copyWith(skipped: {...state.skipped, lookId}));
    unawaited(_topUp());
  }

  Future<void> pick(String lookId) async {
    if (state.picked.contains(lookId)) return;
    emit(state.copyWith(picked: {...state.picked, lookId}));
    unawaited(_topUp());
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

  /// Keeps two proposals ahead of the user until the session limit. After
  /// new marks, the waiting proposals are outdated and get replaced.
  Future<void> _topUp() async {
    final body = request;
    if (body == null || state.proposing) return;
    final outdated = _stale
        ? state.deck.map((look) => look.id).toList()
        : <String>[];
    final ahead = state.deck.length - outdated.length;
    final room = maxSessionProposals - state.decided - ahead;
    final count = (2 - ahead).clamp(0, room);
    if (count <= 0) return;
    _stale = false;
    final exact = {...?(body['exactItemIds'] as List?)?.cast<String>()};
    emit(
      state.copyWith(
        proposing: true,
        failure: () => null,
        proposals: [
          ...?state.proposals?.where((look) => !outdated.contains(look.id)),
        ],
      ),
    );
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
        discardLookIds: outdated,
      );
      if (isClosed) return;
      emit(state.copyWith(proposing: false));
      await refresh();
    } on FormApiException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(proposing: false, failure: () => error.failure));
    }
  }

  /// Starts a fresh session for the composer's original request.
  Future<void> more() async {
    final body = request;
    if (body == null || state.proposing) return;
    emit(state.copyWith(proposing: true, failure: () => null));
    try {
      await looks.propose({...body, 'idempotencyKey': newIdempotencyKey()});
      if (isClosed) return;
      _stale = false;
      emit(const LookProposalsState(proposing: true));
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
