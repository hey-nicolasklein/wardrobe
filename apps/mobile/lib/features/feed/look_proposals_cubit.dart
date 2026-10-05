import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class LookProposalsState {
  const LookProposalsState({
    this.proposals,
    this.rendered = const {},
    this.failure,
  });

  /// Null until the first load.
  final List<Look>? proposals;

  /// Proposals sent off to render. They leave the server's proposal list, so
  /// they are kept here to show what was picked.
  final Set<String> rendered;
  final ApiFailure? failure;

  bool get planning => proposals?.any((look) => look.isActive) ?? true;

  LookProposalsState copyWith({
    List<Look>? proposals,
    Set<String>? rendered,
    ApiFailure? Function()? failure,
  }) => LookProposalsState(
    proposals: proposals ?? this.proposals,
    rendered: rendered ?? this.rendered,
    failure: failure == null ? this.failure : failure(),
  );
}

/// Polls the proposals while they are planned and renders the picked ones.
class LookProposalsCubit extends Cubit<LookProposalsState> {
  LookProposalsCubit(
    this.looks, {
    required this.quality,
    this.pollInterval = const Duration(seconds: 2),
  }) : super(const LookProposalsState()) {
    unawaited(refresh());
  }

  final LookRepository looks;
  final String quality;
  final Duration pollInterval;
  Timer? _poll;

  Future<void> refresh() async {
    _poll?.cancel();
    try {
      final proposals = await looks.proposals();
      if (isClosed) return;
      // Rendered ones keep their place in the list.
      final kept = [
        ...?state.proposals?.where(
          (look) =>
              state.rendered.contains(look.id) &&
              !proposals.any((fresh) => fresh.id == look.id),
        ),
      ];
      emit(
        state.copyWith(
          proposals: [...proposals, ...kept]
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

  Future<void> render(String lookId) async {
    if (state.rendered.contains(lookId)) return;
    emit(state.copyWith(rendered: {...state.rendered, lookId}));
    try {
      await looks.render(lookId, quality: quality);
    } on FormApiException catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          rendered: {...state.rendered}..remove(lookId),
          failure: () => error.failure,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}
