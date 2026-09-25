import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';
import 'support/look_fixtures.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late LookRepository lookRepository;
  late WardrobeRepository wardrobeRepository;
  late CharacterSheetRepository characterSheets;
  late FeedCubit cubit;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('form-feed-test-');
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((options) async {
          if (options.path == 'v1/looks') {
            return jsonResponse(
              jsonEncode({
                'looks': [lookJson(state: 'generating', assetId: null)],
              }),
            );
          }
          if (options.path == 'v1/character-sheets') {
            return jsonResponse(jsonEncode({'characterSheets': <Object>[]}));
          }
          return jsonResponse('{}', 404);
        }),
    );
    final media = MediaRepository(database, null, 'test', directory);
    lookRepository = LookRepository(database, api, 'test', media);
    wardrobeRepository = WardrobeRepository(database, null, 'test', media);
    characterSheets = CharacterSheetRepository(api);
    cubit = FeedCubit(lookRepository, wardrobeRepository, characterSheets);
  });

  tearDown(() async {
    await cubit.close();
    await lookRepository.close();
    await wardrobeRepository.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'markUnavailable keeps cached looks but disables online markings',
    () async {
      await lookRepository.refresh();
      await cubit.loadCache();
      await cubit.refresh();
      expect(cubit.state.online, isTrue);
      expect(cubit.state.looks, isNotEmpty);
      await lookRepository.setLookMarked(
        'look-0001',
        liked: true,
        marked: true,
      );
      await cubit.toggleMark('look-0001', liked: true);
      cubit.markUnavailable();
      expect(cubit.state.stale, isTrue);
      expect(cubit.state.online, isFalse);
      final likedBefore = cubit.state.liked['look-0001'];
      await cubit.toggleMark('look-0001', liked: true);
      expect(cubit.state.liked['look-0001'], likedBefore);
    },
  );

  test('local liked and saved marks reload from preferences', () async {
    await lookRepository.refresh();
    await cubit.loadCache();
    await lookRepository.setLookMarked('look-0001', liked: true, marked: true);
    await lookRepository.setLookMarked('look-0001', liked: false, marked: true);
    await cubit.refresh();
    expect(cubit.state.liked['look-0001'], isTrue);
    expect(cubit.state.saved['look-0001'], isTrue);
  });

  test(
    'incompatible refresh keeps cached looks without stale banner',
    () async {
      await lookRepository.refresh();
      await cubit.loadCache();
      await cubit.refresh();
      expect(cubit.state.looks, isNotEmpty);
      final api = FormApi(
        Dio()
          ..httpClientAdapter = FakeServer((options) async {
            if (options.path == 'v1/looks') {
              return jsonResponse(
                jsonEncode({
                  'looks': [
                    {'id': 'broken'},
                  ],
                }),
              );
            }
            if (options.path == 'v1/character-sheets') {
              return jsonResponse(jsonEncode({'characterSheets': <Object>[]}));
            }
            return jsonResponse('{}', 404);
          }),
      );
      final media = MediaRepository(database, null, 'test', directory);
      final brokenRepo = LookRepository(database, api, 'test', media);
      final brokenCubit = FeedCubit(
        brokenRepo,
        wardrobeRepository,
        CharacterSheetRepository(api),
      );
      addTearDown(brokenCubit.close);
      addTearDown(brokenRepo.close);
      await brokenCubit.loadCache();
      await brokenCubit.refresh();
      expect(brokenCubit.state.failure, ApiFailure.incompatible);
      expect(brokenCubit.state.stale, isFalse);
      expect(brokenCubit.state.online, isTrue);
      expect(brokenCubit.state.looks, isNotEmpty);
    },
  );

  test('loadCache does not mark feed stale before refresh', () async {
    await lookRepository.refresh();
    await cubit.loadCache();
    expect(cubit.state.stale, isFalse);
    expect(cubit.state.looks, isNotEmpty);
  });
}
