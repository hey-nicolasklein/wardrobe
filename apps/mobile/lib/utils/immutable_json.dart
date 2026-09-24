Map<String, dynamic> immutableJson(Map<String, dynamic> value) =>
    Map.unmodifiable(value.map((key, value) => MapEntry(key, _freeze(value))));

Object? _freeze(Object? value) => switch (value) {
  Map<String, dynamic>() => immutableJson(value),
  List<dynamic>() => List<dynamic>.unmodifiable(value.map(_freeze)),
  _ => value,
};
