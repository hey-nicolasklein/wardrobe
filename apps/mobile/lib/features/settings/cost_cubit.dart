import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/settings/cost_week.dart';
import 'package:form_mobile/models/generation_costs.dart';
import 'package:form_mobile/repository/generation_cost_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class CostState {
  const CostState({
    required this.week,
    required this.currentWeek,
    this.loading = false,
    this.costs,
    this.failure,
    this.presentationGeneration = 0,
  });

  final CostWeek week;
  final CostWeek currentWeek;
  final bool loading;
  final GenerationCosts? costs;
  final ApiFailure? failure;

  /// Bumps when settled costs change so the gauge can replay its intro.
  final int presentationGeneration;

  bool get isCurrentWeek => week == currentWeek;
  bool get canGoNext => week.compareTo(currentWeek) < 0;
}

class CostCubit extends Cubit<CostState> {
  factory CostCubit(
    GenerationCostRepository repository, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    final current = CostWeek.fromDate(clock());
    return CostCubit._(repository, clock, current);
  }

  CostCubit._(this._repository, this._now, CostWeek current)
    : super(CostState(week: current, currentWeek: current));

  final GenerationCostRepository _repository;
  final DateTime Function() _now;
  int _requestId = 0;

  Future<void> refresh() => _load(state.week);

  Future<void> previousWeek() => _load(state.week.offset(-1));

  Future<void> nextWeek() async {
    final current = CostWeek.fromDate(_now());
    if (state.week.compareTo(current) >= 0) return;
    await _load(state.week.offset(1));
  }

  Future<void> goToCurrentWeek() async {
    final current = CostWeek.fromDate(_now());
    if (state.week == current) return;
    await _load(current);
  }

  Future<void> _load(CostWeek requested) async {
    if (isClosed) return;
    final current = CostWeek.fromDate(_now());
    final week = requested.compareTo(current) > 0 ? current : requested;
    final id = ++_requestId;
    emit(
      CostState(
        week: week,
        currentWeek: current,
        loading: true,
        costs: state.costs,
        presentationGeneration: state.presentationGeneration,
      ),
    );
    try {
      final costs = await _repository.fetch(week);
      if (isClosed || id != _requestId) return;
      emit(
        CostState(
          week: week,
          currentWeek: current,
          costs: costs,
          presentationGeneration: state.presentationGeneration + 1,
        ),
      );
    } on Object catch (error) {
      if (isClosed || id != _requestId) return;
      emit(
        CostState(
          week: week,
          currentWeek: current,
          failure: error is FormApiException
              ? error.failure
              : ApiFailure.unavailable,
        ),
      );
    }
  }
}
