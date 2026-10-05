import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

class LookProposalsState {
  const LookProposalsState({
    this.proposals,
    this.picked = const {},
    this.skipped = const {},
    this.proposing = false,
    this.failure,
  });

  /// The batch in planning order. Null until the first load.
  final List<Look>? proposals;

  /// Proposals swiped right and sent off to render.
  final Set<String> picked;

  /// Proposals swiped left.
  final Set<String> skipped;

  /// A new batch is being requested, see [LookProposalsCubit.more].
  final bool proposing;
  final ApiFailure? failure;

  /// Proposals still to decide on, in deck order. Failed plans drop out.
  List<Look> get deck => [
    for (final look in proposals ?? const <Look>[])
      if (look.state != 'failed' &&
          !picked.contains(look.id) &&
          !skipped.contains(look.id))
        look,
  ];

  bool get planning => proposals?.any((look) => look.isActive) ?? true;

  /// Every proposal is decided or failed.
  bool get finished => proposals != null && !proposing && deck.isEmpty;

  LookProposalsState copyWith({
    List<Look>? proposals,
    Set<String>? picked,
    Set<String>? skipped,
    bool? proposing,
    ApiFailure? Function()? failure,
  }) => LookProposalsState(
    proposals: proposals ?? this.proposals,
    picked: picked ?? this.picked,
    skipped: skipped ?? this.skipped,
    proposing: proposing ?? this.proposing,
    failure: failure == null ? this.failure : failure(),
  );
}

/// Polls the proposals while they are planned, renders the ones swiped right,
/// and can ask for another batch with the composer's original request.
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
  /// which hides "more proposals".
  final Map<String, dynamic>? request;
  final Duration pollInterval;
  Timer? _poll;

  Future<void> refresh() async {
    _poll?.cancel();
    try {
      final fresh = await looks.proposals();
      if (isClosed) return;
      // Picked proposals leave the server's list; they keep their place here.
      final kept = [
        ...?state.proposals?.where(
          (look) =>
              state.picked.contains(look.id) &&
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

  void skip(String lookId) =>
      emit(state.copyWith(skipped: {...state.skipped, lookId}));

  Future<void> pick(String lookId) async {
    if (state.picked.contains(lookId)) return;
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

  /// Replaces the deck with a new batch for the same request.
  Future<void> more() async {
    final body = request;
    if (body == null || state.proposing) return;
    emit(state.copyWith(proposing: true, failure: () => null));
    try {
      await looks.propose({...body, 'idempotencyKey': newIdempotencyKey()});
      if (isClosed) return;
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
