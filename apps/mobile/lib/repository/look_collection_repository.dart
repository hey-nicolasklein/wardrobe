import 'dart:convert';

import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

/// A Sammlung: a named group of looks, e.g. "🌴 Urlaub".
class LookCollection {
  const LookCollection({
    required this.id,
    required this.name,
    required this.emoji,
    this.lookIds = const [],
  });

  factory LookCollection.fromJson(Map<String, dynamic> json) => LookCollection(
    id: json['id'] as String,
    name: json['name'] as String,
    emoji: json['emoji'] as String,
    lookIds: (json['lookIds'] as List<dynamic>).cast<String>(),
  );

  final String id;
  final String name;
  final String emoji;

  /// Newest first.
  final List<String> lookIds;

  LookCollection withLook(String lookId, {required bool included}) =>
      LookCollection(
        id: id,
        name: name,
        emoji: emoji,
        lookIds: [
          if (included) lookId,
          for (final id in lookIds)
            if (id != lookId) id,
        ],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'lookIds': lookIds,
  };
}

/// Sammlungen live on the server. The last list is kept on the phone so they
/// show offline too.
class LookCollectionRepository {
  LookCollectionRepository(this.database, this.api, this.scope);

  final AppDatabase database;
  final FormApi? api;
  final String scope;

  String get _cacheKey => 'look-collections:$scope';

  Future<List<LookCollection>> cached() async {
    final raw = await database.preference(_cacheKey);
    if (raw == null) return const [];
    try {
      return _parse(jsonDecode(raw) as List<dynamic>);
    } on Object {
      return const [];
    }
  }

  Future<List<LookCollection>> refresh() async {
    final response = await _request('v1/look-collections');
    final List<LookCollection> collections;
    try {
      collections = _parse(response['collections'] as List<dynamic>);
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
    await remember(collections);
    return collections;
  }

  Future<void> remember(List<LookCollection> collections) =>
      database.setPreference(
        _cacheKey,
        jsonEncode([for (final c in collections) c.toJson()]),
      );

  Future<LookCollection> create({
    required String name,
    required String emoji,
  }) async => LookCollection.fromJson(
    await _request(
      'v1/look-collections',
      method: 'POST',
      data: {'name': name, 'emoji': emoji},
    ),
  );

  Future<void> update(
    String collectionId, {
    required String name,
    required String emoji,
  }) => _request(
    'v1/look-collections/$collectionId',
    method: 'PATCH',
    data: {'name': name, 'emoji': emoji},
  );

  Future<void> delete(String collectionId) =>
      _request('v1/look-collections/$collectionId', method: 'DELETE');

  Future<void> setLook(
    String collectionId,
    String lookId, {
    required bool included,
  }) => _request(
    'v1/look-collections/$collectionId/looks/$lookId',
    method: 'PUT',
    data: {'included': included},
  );

  static List<LookCollection> _parse(List<dynamic> json) => [
    for (final entry in json)
      LookCollection.fromJson(entry as Map<String, dynamic>),
  ];

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    return api!.request(path, method: method, data: data);
  }
}
