import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/character_fixtures.dart';

void main() {
  late AppDatabase database;
  late CharacterApi api;
  late CharacterSheetRepository repository;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    api = CharacterApi();
    repository = CharacterSheetRepository(
      api,
      database: database,
      scope: 'test',
    );
  });
  tearDown(() async {
    await repository.close();
    await database.close();
  });

  test(
    'records round trip and enforce current contract without refinement',
    () {
      final json = characterJson();
      expect(CharacterSheet.fromJson(json).toJson(), json);
      expect(json.containsKey('refinement'), false);
      for (final patch in [
        {'referenceAssetIds': <String>[]},
        {
          'referenceAssetIds': ['1', '2', '3', '4', '5'],
        },
        {'costMicrounits': -1},
        {'note': 'x' * 1001},
        {'state': 'unknown'},
      ]) {
        expect(
          () => CharacterSheet.fromJson({...json, ...patch}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'sort newest first, choose active and separate pending from history',
    () async {
      api.sheets = [
        characterJson(active: true),
        characterJson(
          id: 'new',
          state: 'processing',
          date: '2026-09-03T10:00:00.000Z',
        ),
        characterJson(
          id: 'failed',
          state: 'failed',
          date: '2026-09-02T10:00:00.000Z',
        ),
      ];
      final state = CharacterState(sheets: await repository.fetch());
      expect(state.sheets.map((s) => s.id), ['new', 'failed', 'reference-1']);
      expect(state.current!.id, 'reference-1');
      expect(state.pending.single.id, 'new');
      expect(state.history.single.id, 'failed');
      expect((await repository.activeReady())!.id, 'reference-1');
    },
  );

  test('eligibility matches PWA for every state and active flag', () {
    for (final state in ['queued', 'processing', 'ready', 'failed']) {
      for (final active in [true, false]) {
        final sheet = CharacterSheet.fromJson(
          characterJson(state: state, active: active),
        );
        expect(sheet.canActivate, !active && state == 'ready');
        expect(sheet.canDelete, !active && ['ready', 'failed'].contains(state));
        expect(sheet.canReplace, state == 'ready');
      }
    }
  });

  test(
    'scoped cache reopens and survives refresh failures',
    () async {
      api.sheets = [characterJson(state: 'failed')];
      await repository.fetch();
      final restored = CharacterSheetRepository(
        api,
        database: database,
        scope: 'test',
      );
      final other = CharacterSheetRepository(
        api,
        database: database,
        scope: 'other',
      );
      addTearDown(restored.close);
      addTearDown(other.close);
      expect((await restored.cached()).single.failureCategory, 'provider');
      expect(await other.cached(), isEmpty);
      api.offline = true;
      await expectLater(repository.fetch(), throwsA(isA<FormApiException>()));
      api
        ..offline = false
        ..malformed = true;
      await expectLater(repository.fetch(), throwsA(isA<FormApiException>()));
      expect((await repository.cached()).single.state, 'failed');
    },
  );

  test(
    'activation updates all cached active flags only after success',
    () async {
      api.sheets = [characterJson(active: true), characterJson(id: 'old')];
      await repository.fetch();
      api.offline = true;
      await expectLater(
        repository.activate('old', 'activation-key'),
        throwsA(isA<FormApiException>()),
      );
      expect(
        (await repository.cached()).where((s) => s.active).single.id,
        'reference-1',
      );
      api
        ..offline = false
        ..holdActivation = Completer<void>();
      final activation = repository.activate('old', 'activation-key');
      await Future<void>.delayed(Duration.zero);
      expect(
        (await repository.cached()).where((s) => s.active).single.id,
        'reference-1',
      );
      api.holdActivation!.complete();
      await activation;
      expect(
        (await repository.cached()).where((s) => s.active).single.id,
        'old',
      );
    },
  );

  test('late collection response cannot undo a successful deletion', () async {
    api.sheets = [characterJson()];
    await repository.fetch();
    api.holdFetch = Completer<void>();
    final refresh = repository.fetch();
    await Future<void>.delayed(Duration.zero);
    await repository.delete('reference-1');
    api.holdFetch!.complete();
    await refresh;
    expect(await repository.cached(), isEmpty);
  });

  test(
    'lost delete response keeps cache until idempotent retry confirms absence',
    () async {
      api.sheets = [characterJson()];
      await repository.fetch();
      api.loseDeletion = true;
      await expectLater(
        repository.delete('reference-1'),
        throwsA(isA<FormApiException>()),
      );
      expect(await repository.cached(), hasLength(1));
      await repository.delete('reference-1');
      expect(await repository.cached(), isEmpty);
    },
  );
}
