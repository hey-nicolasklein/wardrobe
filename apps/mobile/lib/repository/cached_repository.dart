import 'package:form_mobile/models/cached_resource.dart';
import 'package:form_mobile/services/form_api.dart';

/// Emits cached data before refreshing it and retains it when the server is
/// unavailable.
class CachedRepository<T> {
  const CachedRepository({
    required this.readCache,
    required this.fetch,
    required this.writeCache,
  });

  final Future<T?> Function() readCache;
  final Future<T> Function() fetch;
  final Future<void> Function(T) writeCache;

  Stream<CachedResource<T>> refresh() async* {
    final cached = await readCache();
    yield CachedResource(value: cached, refreshing: true);
    try {
      final fresh = await fetch();
      await writeCache(fresh);
      yield CachedResource(value: fresh, stale: false);
    } on FormApiException catch (error) {
      yield CachedResource(
        value: error.failure == ApiFailure.unavailable ? cached : null,
        failure: error.failure,
      );
    }
  }
}
