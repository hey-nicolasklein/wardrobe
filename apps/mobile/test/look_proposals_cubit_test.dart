import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/look_proposals_cubit.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';
import 'support/look_fixtures.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late LookRepository looks;
  late List<String> rendered;
  late List<Map<String, dynamic>> proposals;
  late List<Map<String, dynamic>> proposeBodies;
  late List<Map<String, dynamic>> adjustBodies;

  Map<String, dynamic> proposal(String id, String state, String createdAt) =>
      lookJson(id: id, state: state, assetId: null)
        ..['createdAt'] = createdAt
        ..['reasons'] = [
          {'kind': 'never-styled', 'itemId': 'wardrobe-item-0001'},
        ];

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('form-proposals-test-');
    rendered = [];
    proposeBodies = [];
    adjustBodies = [];
    proposals = [
      proposal('look-a', 'proposed', '2026-10-05T12:00:00.000Z'),
      proposal('look-b', 'proposed', '2026-10-05T12:00:01.000Z'),
      proposal('look-c', 'failed', '2026-10-05T12:00:02.000Z'),
    ];
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((options) async {
          if (options.path == 'v1/looks/proposals/adjust') {
            adjustBodies.add(options.data as Map<String, dynamic>);
            return jsonResponse(
              jsonEncode({
                'looks': [
                  proposal('look-a', 'proposed', '2026-10-05T12:00:00.000Z')
                    ..['wardrobeItemIds'] = ['swapped-in'],
                ],
              }),
            );
          }
          if (options.method == 'POST' &&
              options.path == 'v1/looks/proposals') {
            proposeBodies.add(options.data as Map<String, dynamic>);
            return jsonResponse(jsonEncode({'lookIds': <String>[]}), 202);
          }
          if (options.path == 'v1/looks/proposals') {
            return jsonResponse(jsonEncode({'looks': proposals}));
          }
          if (options.path.endsWith('/render')) {
            final id = options.path.split('/')[2];
            rendered.add(id);
            proposals.removeWhere((look) => look['id'] == id);
            return jsonResponse(jsonEncode({'lookId': id, 'jobId': 'j'}), 202);
          }
          if (options.path == 'v1/looks') {
            return jsonResponse(jsonEncode({'looks': <Object>[]}));
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

  test(
    'swiping works through the deck and renders only picked outfits',
    () async {
      final cubit = LookProposalsCubit(looks, quality: 'medium');
      addTearDown(cubit.close);
      await cubit.refresh();
      // The failed plan never reaches the deck.
      expect(cubit.state.deck.map((look) => look.id), ['look-a', 'look-b']);
      expect(cubit.state.deck.first.reasons!.single.kind, 'never-styled');

      cubit.skip('look-a');
      expect(cubit.state.deck.map((look) => look.id), ['look-b']);
      await cubit.pick('look-b');
      await cubit.refresh();
      expect(rendered, ['look-b']);
      expect(cubit.state.picked, {'look-b'});
      expect(cubit.state.finished, isTrue);
    },
  );
  test(
    'swaps and kept pieces adjust waiting outfits and shape new ones',
    () async {
      final cubit = LookProposalsCubit(
        looks,
        quality: 'low',
        request: {
          'exactItemIds': <String>[],
          'categories': <String>[],
          'occasion': null,
          'style': 'candid',
          'completion': 'wardrobe',
          'idempotencyKey': 'composer-key-000001',
        },
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      await cubit.keep('jacket');
      await cubit.swap('pants');
      expect(adjustBodies, [
        {
          'keepItemIds': ['jacket'],
          'excludeItemIds': <String>[],
        },
        {
          'keepItemIds': <String>[],
          'excludeItemIds': ['pants'],
        },
      ]);
      // The adjusted outfit replaces the waiting one in place.
      expect(cubit.state.deck.first.wardrobeItemIds, ['swapped-in']);

      cubit.skip('look-a');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final body = proposeBodies.single;
      expect(body['append'], isTrue);
      expect(body['exactItemIds'], ['jacket']);
      expect(body['excludedItemIds'], ['pants']);
      expect(body.containsKey('discardLookIds'), isFalse);
    },
  );
}
