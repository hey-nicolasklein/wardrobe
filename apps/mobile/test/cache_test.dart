import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/app/overview_cubit.dart';
import 'package:form_mobile/models/cached_resource.dart';
import 'package:form_mobile/repository/cached_repository.dart';
import 'package:form_mobile/repository/overview_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';

void main() {
  test('cached data emits before the remote request completes', () async {
    final remote = Completer<int>();
    int? stored = 4;
    final repository = CachedRepository<int>(
      readCache: () async => stored,
      fetch: () => remote.future,
      writeCache: (value) async => stored = value,
    );
    final stream = StreamIterator(repository.refresh());
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.value, 4);
    expect(stream.current.stale, isTrue);
    expect(stream.current.canMutate, isFalse);
    remote.complete(7);
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.value, 7);
    expect(stream.current.canMutate, isTrue);
    expect(stored, 7);
    await stream.cancel();
  });

  for (final cached in [null, 0, 8]) {
    test(
      'failed refresh preserves cached $cached without making it writable',
      () async {
        final repository = CachedRepository<int>(
          readCache: () async => cached,
          fetch: () async =>
              throw const FormApiException(ApiFailure.unavailable),
          writeCache: (_) async => fail('Failed request must not update cache'),
        );
        final result = await repository.refresh().last;
        expect(result.value, cached);
        expect(result.stale, isTrue);
        expect(result.canMutate, isFalse);
        expect(result.failure, ApiFailure.unavailable);
      },
    );
  }

  test('revoked access hides cached content', () async {
    final repository = CachedRepository<int>(
      readCache: () async => 5,
      fetch: () async =>
          throw const FormApiException(ApiFailure.missingSession),
      writeCache: (_) async => fail('No write on failed session'),
    );
    expect((await repository.refresh().last).value, isNull);
  });

  test(
    'schema v1 persists isolated collection summaries and media index',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      expect(
        tables.map((row) => row.read<String>('name')),
        containsAll([
          'preferences',
          'collection_summaries',
          'media_cache_entries',
        ]),
      );
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 1);
      final first = OverviewRepository(database, null, 'server-a');
      final second = OverviewRepository(database, null, 'server-b');
      await first.collection(Collection.feed).writeCache(0);
      expect(await first.collection(Collection.feed).readCache(), 0);
      expect(await first.collection(Collection.wardrobe).readCache(), isNull);
      expect(await second.collection(Collection.feed).readCache(), isNull);
      await database
          .into(database.mediaCacheEntries)
          .insert(
            MediaCacheEntriesCompanion.insert(
              scope: 'server-a',
              assetId: 'asset',
              localPath: 'media/asset.jpg',
              byteCount: 42,
              lastAccessedAt: DateTime.utc(2026),
              protected: const Value(true),
            ),
          );
      final media = await database
          .select(database.mediaCacheEntries)
          .getSingle();
      expect(media.protected, isTrue);
      expect(media.byteCount, 42);
    },
  );

  test(
    'overview transitions from cached to loaded to offline without losing data',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final adapter = FakeServer(
        (_) async => jsonResponse('{"looks":[{},{}]}'),
      );
      final api = FormApi(Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);
      final repository = OverviewRepository(database, api, 'server-a');
      await repository.collection(Collection.feed).writeCache(1);
      final cubit = OverviewCubit(repository);
      addTearDown(cubit.close);
      await cubit.loadCache();
      expect(cubit.state[Collection.feed]!.value, 1);
      final states = <CachedResource<int>>[];
      final subscription = cubit.stream.listen(
        (state) => states.add(state[Collection.feed]!),
      );
      addTearDown(subscription.cancel);
      await cubit.refresh(Collection.feed);
      expect(cubit.state[Collection.feed]!.value, 2);
      expect(cubit.state[Collection.feed]!.stale, isFalse);
      cubit.markUnavailable();
      expect(cubit.state[Collection.feed]!.value, 2);
      expect(cubit.state[Collection.feed]!.canMutate, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        states.any((state) => state.refreshing && state.value == 1),
        isTrue,
      );
    },
  );
}
