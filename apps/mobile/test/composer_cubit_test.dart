import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';
import 'support/look_fixtures.dart';
import 'support/wardrobe_fixtures.dart';

WardrobeItem _item(String id, String category, String name) {
  final json = itemJson(id: id);
  (json['metadata'] as Map<String, dynamic>)
    ..['category'] = category
    ..['name'] = name;
  return WardrobeItem.fromJson(json);
}

void main() {
  late AppDatabase database;
  late Directory directory;
  late LookRepository looks;
  late List<Map<String, dynamic>> createBodies;
  late bool failNextCreate;

  final shirt = _item('wardrobe-item-shirt', 'top', 'Linen shirt');
  final boots = _item('wardrobe-item-boots', 'shoes', 'Chelsea boots');
  final eligible = [shirt, boots];

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('form-composer-test-');
    createBodies = [];
    failNextCreate = false;
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((options) async {
          if (options.method == 'POST' && options.path == 'v1/looks') {
            createBodies.add(options.data as Map<String, dynamic>);
            if (failNextCreate) {
              failNextCreate = false;
              return jsonResponse('{}', 503);
            }
            return jsonResponse(jsonEncode({'lookId': 'look-0001'}), 202);
          }
          if (options.path == 'v1/looks') {
            return jsonResponse(
              jsonEncode({
                'looks': [lookJson()],
              }),
            );
          }
          return jsonResponse('{}', 404);
        }),
    );
    looks = LookRepository(
      database,
      api,
      'test',
      MediaRepository(database, null, 'test', directory),
    );
  });

  tearDown(() async {
    await looks.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test('selected-only ignores search and category, as in the PWA', () {
    final cubit = ComposerCubit(looks, preselectedIds: [boots.id])
      ..setQuery('linen')
      ..setItemCategory('top');
    expect(cubit.state.visible(eligible), [shirt]);
    cubit.toggleSelectedOnly();
    expect(cubit.state.visible(eligible), [boots]);
    cubit.setItemCategory(null);
    expect(cubit.state.selectedOnly, isFalse);
  });

  test('clearing the selection turns wardrobe completion back on', () {
    final cubit = ComposerCubit(looks, preselectedIds: [shirt.id])
      ..toggleCategory('shoes')
      ..toggleCompleteWithWardrobe();
    expect(cubit.state.completeWithWardrobe, isFalse);
    expect(cubit.state.categories, isEmpty);
    cubit.toggleItem(shirt.id);
    expect(cubit.state.completeWithWardrobe, isTrue);
    cubit.toggleCompleteWithWardrobe();
    expect(cubit.state.completeWithWardrobe, isTrue);
  });

  test('selection stops at the contract limit', () {
    final cubit = ComposerCubit(
      looks,
      preselectedIds: [
        for (var i = 0; i < maxComposerPieces; i++) 'wardrobe-item-$i',
      ],
    )..toggleItem(shirt.id);
    expect(cubit.state.limitReached, isTrue);
    expect(cubit.state.selectedIds, hasLength(maxComposerPieces));
    cubit.toggleItem('wardrobe-item-0');
    expect(cubit.state.limitReached, isFalse);
  });

  test('reset clears every choice including search', () {
    final cubit = ComposerCubit(looks, preselectedIds: [shirt.id])
      ..setOccasion('party')
      ..setQuery('boots')
      ..setItemCategory('shoes')
      ..toggleSelectedOnly()
      ..reset();
    expect(cubit.state.selectedIds, isEmpty);
    expect(cubit.state.occasion, isNull);
    expect(cubit.state.query, isEmpty);
    expect(cubit.state.itemCategory, isNull);
    expect(cubit.state.selectedOnly, isFalse);
  });

  test('the command only sends categories while completing', () {
    final cubit = ComposerCubit(looks, preselectedIds: [shirt.id])
      ..setOccasion('casual')
      ..toggleCategory('shoes');
    expect(cubit.command().body['categories'], ['shoes']);
    expect(cubit.command().body['occasion'], 'casual');
    expect(cubit.command().body['quality'], 'low');
    cubit.setQuality('high');
    expect(cubit.command().body['quality'], 'high');
    cubit.toggleCompleteWithWardrobe();
    expect(cubit.command().body['categories'], isEmpty);
    expect(cubit.command().body['completeWithWardrobe'], isFalse);
  });

  test('a failed submit retries with the same idempotency key', () async {
    failNextCreate = true;
    final cubit = ComposerCubit(looks, preselectedIds: [shirt.id]);
    addTearDown(cubit.close);
    await cubit.submit();
    expect(cubit.state.failure, ApiFailure.unavailable);
    expect(cubit.state.createdLookId, isNull);
    await cubit.submit();
    expect(cubit.state.createdLookId, 'look-0001');
    expect(createBodies, hasLength(2));
    expect(
      createBodies.map((body) => body['idempotencyKey']).toSet(),
      {cubit.idempotencyKey},
    );
    expect(await looks.loadLookStarts(), {
      'look-0001': [shirt.id],
    });
  });
}
