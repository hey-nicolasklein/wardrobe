import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/services/app_database.dart';

import 'support/character_fixtures.dart';

void main() {
  late AppDatabase database;
  late CharacterApi api;
  late CharacterSheetRepository repository;
  late CharacterCubit cubit;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    api = CharacterApi();
    repository = CharacterSheetRepository(
      api,
      database: database,
      scope: 'test',
    );
    api.sheets = [
      characterJson(active: true),
      characterJson(id: 'old'),
      characterJson(id: 'pending', state: 'processing'),
      characterJson(id: 'failed', state: 'failed'),
    ];
    await repository.fetch();
    cubit = CharacterCubit(repository);
    await cubit.loadCache();
  });
  tearDown(() async {
    await cubit.close();
    await repository.close();
    await database.close();
  });

  Future<void> online() async {
    final loaded = cubit.stream.firstWhere(
      (s) => !s.loading && !s.stale && s.online,
    );
    cubit.setOnline(online: true);
    await loaded;
  }

  test(
    'cached pending and failed states restore offline without mutations',
    () async {
      expect(cubit.state.sheets, hasLength(4));
      expect(cubit.state.stale, true);
      final requests = api.requests.length;
      await cubit.activate('old');
      await cubit.delete('failed');
      await cubit.refresh();
      expect(api.requests, hasLength(requests));
    },
  );

  test(
    'foreground refresh updates server states and stale failures keep cache',
    () async {
      await online();
      cubit.setForeground(foreground: false);
      api.sheets = [characterJson(active: true)];
      final requests = api.requests.length;
      await cubit.refresh();
      expect(api.requests, hasLength(requests));
      final updated = cubit.stream.firstWhere(
        (s) => s.sheets.length == 1 && !s.loading,
      );
      cubit.setForeground(foreground: true);
      await updated;
      api.offline = true;
      await cubit.refresh();
      expect(cubit.state.stale, true);
      expect(cubit.state.sheets, hasLength(1));
      expect(cubit.state.canMutate, false);
    },
  );

  test('late refresh after going offline cannot enable writes', () async {
    await online();
    api.holdFetch = Completer<void>();
    final refresh = cubit.refresh();
    await Future<void>.delayed(Duration.zero);
    cubit.setOnline(online: false);
    api.holdFetch!.complete();
    await refresh;
    expect(cubit.state.online, false);
    expect(cubit.state.canMutate, false);
  });

  test('activation retry keeps key and blocks unrelated commands', () async {
    await online();
    api.loseActivation = true;
    await cubit.activate('old');
    expect(cubit.state.active!.id, 'reference-1');
    final requests = api.requests.length;
    await cubit.delete('failed');
    expect(api.requests, hasLength(requests));
    await cubit.retry();
    expect(cubit.state.active!.id, 'old');
    final calls = api.requests
        .where((r) => r.path.endsWith('/activate'))
        .toList();
    expect(calls, hasLength(2));
    expect(calls.first.data, calls.last.data);
  });

  test(
    'active and pending deletion are disabled, failed deletion succeeds',
    () async {
      await online();
      final requests = api.requests.length;
      await cubit.delete('reference-1');
      await cubit.delete('pending');
      expect(api.requests, hasLength(requests));
      await cubit.delete('failed');
      expect(cubit.state.find('failed'), isNull);
    },
  );
  test(
    'pending polling pauses in background and resumes on foreground',
    () async {
      await cubit.close();
      cubit = CharacterCubit(
        repository,
        pollInterval: const Duration(milliseconds: 20),
      );
      await cubit.loadCache();
      await online();
      api.sheets = [characterJson(state: 'failed')];
      await cubit.stream.firstWhere(
        (s) =>
            !s.loading &&
            s.sheets.length == 1 &&
            s.sheets.single.state == 'failed',
      );
      expect(cubit.state.history.single.state, 'failed');
      cubit.setForeground(foreground: false);
      final count = api.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(api.requests, hasLength(count));
    },
  );

  test(
    'reconnection during an in-flight refresh schedules a fresh read',
    () async {
      await online();
      api.holdFetch = Completer<void>();
      final initial = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      cubit
        ..setOnline(online: false)
        ..setOnline(online: true);
      final ready = cubit.stream.firstWhere(
        (s) => s.online && !s.stale && !s.loading,
      );
      api.holdFetch!.complete();
      await initial;
      await ready;
      expect(cubit.state.canMutate, true);
    },
  );
}
