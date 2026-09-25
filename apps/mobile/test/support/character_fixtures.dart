import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:form_mobile/services/form_api.dart';

Map<String, dynamic> characterJson({
  String id = 'reference-1',
  String state = 'ready',
  bool active = false,
  String date = '2026-09-01T10:00:00.000Z',
}) => {
  'id': id,
  'state': state,
  'referenceAssetIds': ['asset-1'],
  'note': 'A note',
  'assetId': state == 'ready' ? 'asset-1' : null,
  'active': active,
  'model': 'photo-collage-v1',
  'quality': 'high',
  'size': '864x1536',
  'providerRequestId': null,
  'costMicrounits': state == 'ready' ? 0 : null,
  'failureCategory': state == 'failed' ? 'provider' : null,
  'createdAt': date,
  'finishedAt': state == 'ready' ? date : null,
};

class CharacterApi extends FormApi {
  CharacterApi() : super(Dio());
  List<Map<String, dynamic>> sheets = [];
  final requests =
      <({String path, String method, Map<String, dynamic>? data})>[];
  final uploads = <Uint8List>[];
  final completions = <String>[];
  final creations = <String, String>{};
  void Function()? afterCreation;
  void Function()? afterUpload;
  bool offline = false;
  bool loseCompletion = false;
  bool loseCreation = false;
  bool loseActivation = false;
  bool loseDeletion = false;
  bool failUpload = false;
  bool completed = false;
  bool malformed = false;
  int intentCount = 0;
  Completer<void>? holdFetch;
  Completer<void>? holdActivation;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    requests.add((path: path, method: method, data: data));
    if (offline) throw const FormApiException(ApiFailure.unavailable);
    if (path.endsWith('/upload-intents')) {
      intentCount++;
      return {
        'assetId': 'uploaded-$intentCount',
        'uploadUrl': 'https://upload.invalid/test',
        'headers': <String, dynamic>{},
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      };
    }
    if (path.endsWith('/complete')) {
      completions.add(data!['idempotencyKey'] as String);
      if (uploads.isEmpty) {
        throw const FormApiException(
          ApiFailure.rejected,
          code: 'upload-missing',
        );
      }
      completed = true;
      if (loseCompletion) {
        loseCompletion = false;
        throw const FormApiException(ApiFailure.unavailable);
      }
      return {
        'asset': {'id': data['assetId']},
      };
    }
    if (path.endsWith('/activate')) {
      await holdActivation?.future;
      final id = path.split('/')[2];
      sheets = [
        for (final s in sheets) {...s, 'active': s['id'] == id},
      ];
      if (loseActivation) {
        loseActivation = false;
        throw const FormApiException(ApiFailure.unavailable);
      }
      return {};
    }
    if (method == 'DELETE') {
      final id = path.split('/').last;
      if (!sheets.any((s) => s['id'] == id)) {
        throw const FormApiException(
          ApiFailure.incompatible,
          code: 'wardrobe-item-not-found',
        );
      }
      sheets.removeWhere((s) => s['id'] == id);
      if (loseDeletion) {
        loseDeletion = false;
        throw const FormApiException(ApiFailure.unavailable);
      }
      return {};
    }
    if (method == 'POST') {
      final key = data!['idempotencyKey'] as String;
      final id = creations.putIfAbsent(key, () {
        final id = 'created-${creations.length}';
        sheets = [
          for (final s in sheets) {...s, 'active': false},
          {
            ...characterJson(id: id, active: true),
            'note': data['note'],
            'referenceAssetIds': data['referenceAssetIds'],
            'assetId': (data['referenceAssetIds'] as List<dynamic>).single,
          },
        ];
        return id;
      });
      if (loseCreation) {
        loseCreation = false;
        throw const FormApiException(ApiFailure.unavailable);
      }
      afterCreation?.call();
      return {'characterSheetId': id};
    }
    final snapshot = [
      for (final sheet in sheets) Map<String, dynamic>.from(sheet),
    ];
    await holdFetch?.future;
    return {'characterSheets': malformed ? 'invalid' : snapshot};
  }

  @override
  Future<void> upload(
    String url,
    Uint8List bytes,
    Map<String, dynamic> headers,
    void Function(int, int) progress,
  ) async {
    if (failUpload) {
      failUpload = false;
      throw const FormApiException(ApiFailure.unavailable);
    }
    uploads.add(Uint8List.fromList(bytes));
    progress(bytes.length, bytes.length);
    afterUpload?.call();
  }
}
