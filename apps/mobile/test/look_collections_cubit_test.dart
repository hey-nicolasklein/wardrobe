import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/look_collections_cubit.dart';
import 'package:form_mobile/repository/look_collection_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';

void main() {
  late AppDatabase database;
  late LookCollectionsCubit cubit;
  late bool failFiling;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    failFiling = false;
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((options) async {
          if (options.method == 'POST') {
            final body = options.data as Map<String, dynamic>;
            return jsonResponse(
              jsonEncode({...body, 'id': 'trip', 'lookIds': <String>[]}),
              201,
            );
          }
          if (options.path.contains('/looks/')) {
            return failFiling
                ? jsonResponse('{}', 503)
                : jsonResponse(jsonEncode({'included': true}));
          }
          return jsonResponse(jsonEncode({'collections': <Object>[]}));
        }),
    );
    cubit = LookCollectionsCubit(
      LookCollectionRepository(database, api, 'test'),
    );
  });

  tearDown(() async {
    await cubit.close();
    await database.close();
  });

  test('a new Sammlung holds the look it was started from', () async {
    await cubit.create(name: 'Urlaub', emoji: '🌴', lookId: 'look-a');

    expect(collectionsOf(cubit.state, 'look-a').single.name, 'Urlaub');
    // Kept on the phone, so it shows offline too.
    final reloaded = LookCollectionsCubit(cubit.repository);
    await reloaded.loadCache();
    expect(reloaded.state.single.lookIds, ['look-a']);
    await reloaded.close();
  });

  test('filing shows at once and rolls back when the server refuses', () async {
    await cubit.create(name: 'Urlaub', emoji: '🌴');
    failFiling = true;

    final filing = cubit.toggle('trip', 'look-a');
    expect(cubit.state.single.lookIds, ['look-a']);
    await expectLater(filing, throwsA(isA<FormApiException>()));
    expect(cubit.state.single.lookIds, isEmpty);
  });
}
