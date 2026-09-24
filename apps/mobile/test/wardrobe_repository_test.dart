import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/wardrobe/item_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';
import 'support/wardrobe_fixtures.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late WardrobeRepository repository;
  late MediaRepository media;
  late Future<ResponseBody> Function(RequestOptions) respond;
  late List<RequestOptions> requests;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('form-wardrobe-test-');
    requests = [];
    respond = (options) async {
      if (options.path == 'v1/wardrobe-items') {
        return jsonResponse(
          jsonEncode({
            'wardrobeItems': [itemJson()],
          }),
        );
      }
      return jsonResponse(jsonEncode(detailJson()));
    };
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((options) {
          requests.add(options);
          return respond(options);
        }),
    );
    media = MediaRepository(database, null, 'test', directory);
    repository = WardrobeRepository(database, api, 'test', media);
  });
  tearDown(() async {
    await media.settle();
    await repository.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'committed deletion updates grid even when subsequent network fails',
    () async {
      final cubit = WardrobeCubit(repository);
      addTearDown(cubit.close);
      await cubit.refresh();
      final updated = cubit.stream.firstWhere(
        (state) => state.items?.isEmpty ?? false,
      );
      respond = (request) async =>
          jsonResponse('{}', request.method == 'DELETE' ? 200 : 503);
      await repository.execute(
        'wardrobe-item-0001',
        ItemCommand.delete(cubit.state.items!.single.item),
      );
      await updated;
      await cubit.refresh();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.stale, isTrue);
    },
  );

  test(
    'item polling stops in background and adopts completed generation',
    () async {
      var generation = 'processing';
      respond = (_) async =>
          jsonResponse(jsonEncode(detailJson(generation: generation)));
      final cubit = ItemCubit(repository, 'wardrobe-item-0001');
      addTearDown(cubit.close);
      await cubit.load(online: true);
      cubit.setForeground(foreground: false);
      final before = requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 3100));
      expect(requests.length, before);
      generation = 'kept';
      final completed = cubit.stream.firstWhere(
        (state) => !(state.detail?.generating ?? true),
      );
      cubit.setForeground(foreground: true);
      await completed.timeout(const Duration(seconds: 5));
      expect(cubit.state.detail!.currentImage, isNotNull);
    },
  );

  test('list and detail synchronize without losing cached detail', () async {
    await repository.detail('wardrobe-item-0001');
    await repository.refresh();
    expect(
      (await repository.cached()).single.detail!.currentImage!.id,
      'shelf-version-01',
    );
    final other = WardrobeRepository(database, null, 'other-server', media);
    expect(await other.cached(), isEmpty);
    await other.close();
  });

  test(
    'cached-first Cubit preserves data and filters after failed refresh',
    () async {
      await repository.refresh();
      final cubit = WardrobeCubit(repository);
      addTearDown(cubit.close);
      await cubit.loadCache();
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.stale, isTrue);
      cubit.filter(const WardrobeFilter(query: 'linen'));
      final pending = Completer<ResponseBody>();
      respond = (_) => pending.future;
      final refresh = cubit.refresh();
      expect(cubit.state.loading, isTrue);
      expect(cubit.state.items, hasLength(1));
      pending.complete(jsonResponse('{}', 503));
      await refresh;
      expect(cubit.state.stale, isTrue);
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.filter.query, 'linen');
      respond = (_) async => jsonResponse('{"wardrobeItems":[]}');
      await cubit.refresh();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.stale, isFalse);
      expect(await repository.cached(), isEmpty);
    },
  );

  test(
    'item stays read-only offline and failed deletes do not alter cache',
    () async {
      await repository.detail('wardrobe-item-0001');
      final cubit = ItemCubit(repository, 'wardrobe-item-0001');
      addTearDown(cubit.close);
      await cubit.load(online: false);
      final command = ItemCommand.delete(cubit.state.detail!.wardrobeItem);
      expect(cubit.state.canMutate, isFalse);
      final before = requests.length;
      await cubit.execute(command);
      expect(requests.length, before);
      await cubit.refresh();
      expect(cubit.state.canMutate, isTrue);
      respond = (_) async => jsonResponse('{}', 409);
      await cubit.execute(command);
      expect(cubit.state.deleted, isFalse);
      expect(await repository.cached(), hasLength(1));
      expect(cubit.state.pending, isNull);
      respond = (_) async => jsonResponse('{}');
      await cubit.execute(command);
      expect(cubit.state.deleted, isTrue);
      expect(await repository.cached(), isEmpty);
    },
  );

  test(
    'uncertain generation retries reuse key and refresh adopted image',
    () async {
      final cubit = ItemCubit(repository, 'wardrobe-item-0001');
      addTearDown(cubit.close);
      await cubit.load(online: true);
      final command = ItemCommand.generate(
        'wardrobe-item-0001',
        'medium',
        null,
      );
      respond = (_) async => jsonResponse('{}', 503);
      await cubit.execute(command);
      expect(cubit.state.pending, same(command));
      expect(cubit.state.canMutate, isFalse);
      respond = (options) async => jsonResponse(
        jsonEncode(
          options.method == 'POST'
              ? {
                  'jobId': 'job-000000000001',
                  'generationAttemptId': 'generation-00001',
                }
              : detailJson(version: 4),
        ),
      );
      await cubit.refresh();
      await cubit.execute(cubit.state.pending!);
      final posts = requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(2));
      expect(posts.first.data, posts.last.data);
      expect(cubit.state.pending, isNull);
      expect(cubit.state.detail!.wardrobeItem.recordVersion, 4);
      expect((await repository.cached()).single.item.recordVersion, 4);
    },
  );

  test('offline signal during request cannot reenable mutations', () async {
    final cubit = ItemCubit(repository, 'wardrobe-item-0001');
    addTearDown(cubit.close);
    await cubit.load(online: true);
    final pending = Completer<ResponseBody>();
    respond = (_) => pending.future;
    final refresh = cubit.refresh();
    cubit.markUnavailable();
    pending.complete(jsonResponse(jsonEncode(detailJson())));
    await refresh;
    expect(cubit.state.canMutate, isFalse);
  });

  test('malformed remote data never replaces usable cache', () async {
    await repository.refresh();
    respond = (_) async => jsonResponse('{"wardrobeItems":[{"id":4}]}');
    await expectLater(repository.refresh(), throwsA(isA<FormApiException>()));
    expect(
      (await repository.cached()).single.item.id,
      WardrobeItem.fromJson(itemJson()).id,
    );
  });
}
