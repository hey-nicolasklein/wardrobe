import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'look_json_test.dart';
import 'support/fake_server.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late LookRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('form-look-repo-test-');
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((options) async {
          if (options.method == 'DELETE') return jsonResponse('', 204);
          if (options.path == 'v1/looks') {
            return jsonResponse(
              jsonEncode({
                'looks': [contractLookJson()],
              }),
            );
          }
          return jsonResponse('{}', 404);
        }),
    );
    repository = LookRepository(
      database,
      api,
      'test',
      MediaRepository(database, null, 'test', directory),
    );
  });

  tearDown(() async {
    await repository.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test('refresh stores normalized looks and reloads cache', () async {
    final looks = await repository.refresh();
    expect(looks, hasLength(1));
    expect(looks.first.look.id, contractLookJson()['id']);
    final cached = await repository.cached();
    expect(cached, hasLength(1));
  });

  test('malformed remote data never replaces usable cache', () async {
    await repository.refresh();
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer(
          (_) async => jsonResponse('{"looks":[{"id":"broken"}]}'),
        ),
    );
    final broken = LookRepository(
      database,
      api,
      'test',
      MediaRepository(database, null, 'test', directory),
    );
    addTearDown(broken.close);
    await expectLater(broken.refresh(), throwsA(isA<FormApiException>()));
    final cached = await broken.cached();
    expect(cached, hasLength(1));
  });

  test('delete accepts an empty 204 and removes the cached look', () async {
    final looks = await repository.refresh();
    await repository.execute(LookCommand.delete(looks.first.look.id));
    expect(await repository.cached(), isEmpty);
  });
}
