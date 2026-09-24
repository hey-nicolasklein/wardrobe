import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class WardrobeState {
  const WardrobeState({
    this.items,
    this.filter = const WardrobeFilter(),
    this.loading = false,
    this.stale = true,
    this.failure,
  });
  final List<CachedItem>? items;
  final WardrobeFilter filter;
  final bool loading;
  final bool stale;
  final ApiFailure? failure;
}

class WardrobeCubit extends Cubit<WardrobeState> {
  WardrobeCubit(this.repository) : super(const WardrobeState()) {
    _subscription = repository.changes.listen(
      (_) => unawaited(_reloadCommitted()),
    );
  }
  final WardrobeRepository repository;
  late final StreamSubscription<void> _subscription;
  bool _refreshing = false;
  int _availability = 0;
  Timer? _poll;
  bool _foreground = true;

  void setForeground({required bool foreground}) {
    _foreground = foreground;
    _schedulePoll(state);
  }

  void _schedulePoll(WardrobeState next) {
    _poll?.cancel();
    final running =
        next.items?.any(
          (r) => ['queued', 'generating'].contains(r.item.status),
        ) ??
        false;
    if (_foreground && !next.stale && !next.loading && running) {
      _poll = Timer(const Duration(seconds: 3), () => unawaited(refresh()));
    }
  }

  @override
  void onChange(Change<WardrobeState> change) {
    super.onChange(change);
    _schedulePoll(change.nextState);
  }

  Future<void> _reloadCommitted() async {
    final items = await repository.cached();
    if (!isClosed) {
      emit(
        WardrobeState(
          items: items,
          filter: state.filter,
          loading: state.loading,
          stale: state.stale,
          failure: state.failure,
        ),
      );
    }
  }

  void filter(WardrobeFilter filter) => emit(
    WardrobeState(
      items: state.items,
      filter: filter,
      loading: state.loading,
      stale: state.stale,
      failure: state.failure,
    ),
  );
  void markUnavailable() {
    _availability++;
    emit(WardrobeState(items: state.items, filter: state.filter));
  }

  Future<void> loadCache() async {
    final items = await repository.cached();
    final hasSnapshot = await repository.hasSnapshot();
    if (!isClosed) {
      emit(
        WardrobeState(
          items: items.isEmpty && !hasSnapshot ? null : items,
          filter: state.filter,
        ),
      );
    }
  }

  Future<void> refresh() async {
    if (_refreshing || isClosed) return;
    _refreshing = true;
    final availability = _availability;
    emit(
      WardrobeState(
        items: state.items,
        filter: state.filter,
        loading: true,
        stale: state.stale,
      ),
    );
    try {
      final items = await repository.refresh();
      if (!isClosed) {
        emit(
          WardrobeState(
            items: items,
            filter: state.filter,
            stale: availability != _availability,
          ),
        );
      }
    } on Exception catch (error) {
      if (!isClosed) {
        emit(
          WardrobeState(
            items: state.items,
            filter: state.filter,
            failure: error is FormApiException
                ? error.failure
                : ApiFailure.unavailable,
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> close() async {
    _poll?.cancel();
    await _subscription.cancel();
    await super.close();
  }
}
