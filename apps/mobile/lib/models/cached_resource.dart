import 'package:form_mobile/services/form_api.dart';

class CachedResource<T> {
  const CachedResource({
    this.value,
    this.refreshing = false,
    this.stale = true,
    this.failure,
  });

  final T? value;
  final bool refreshing;
  final bool stale;
  final ApiFailure? failure;

  bool get canMutate => value != null && !stale && failure == null;
}
