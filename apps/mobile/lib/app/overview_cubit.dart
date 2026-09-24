import 'package:bloc/bloc.dart';
import 'package:form_mobile/models/cached_resource.dart';
import 'package:form_mobile/repository/overview_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class OverviewCubit extends Cubit<Map<Collection, CachedResource<int>>> {
  OverviewCubit(this._repository)
    : super({
        for (final collection in Collection.values)
          collection: const CachedResource(refreshing: true),
      });

  final OverviewRepository _repository;
  final Set<Collection> _refreshing = {};

  Future<void> loadCache() async {
    for (final collection in Collection.values) {
      final value = await _repository.collection(collection).readCache();
      if (isClosed) return;
      emit({...state, collection: CachedResource(value: value)});
    }
  }

  Future<void> refresh(Collection collection) async {
    if (isClosed || !_refreshing.add(collection)) return;
    try {
      await for (final resource
          in _repository.collection(collection).refresh()) {
        if (isClosed) return;
        emit({...state, collection: resource});
      }
    } finally {
      _refreshing.remove(collection);
    }
  }

  void markUnavailable() {
    if (isClosed) return;
    emit({
      for (final entry in state.entries)
        entry.key: CachedResource(
          value: entry.value.value,
          failure: ApiFailure.unavailable,
        ),
    });
  }
}
