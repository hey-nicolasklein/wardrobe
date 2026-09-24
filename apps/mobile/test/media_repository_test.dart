import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late MediaRepository media;
  late FakeServer server;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('form-media-test-');
    database = AppDatabase(NativeDatabase.memory());
    server = FakeServer(
      (options) async => ResponseBody.fromBytes([1, 2, 3, 4], 200),
    );
    media = MediaRepository(
      database,
      FormApi(Dio()..httpClientAdapter = server),
      'test',
      directory,
      maxBytes: 8,
    );
  });
  tearDown(() async {
    await media.settle();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'index, access time, offline lookup and least-recent eviction',
    () async {
      final a = await media.load('a', previewPath: '/a');
      await media.load('b', previewPath: '/b');
      await database
          .update(database.mediaCacheEntries)
          .write(
            MediaCacheEntriesCompanion(lastAccessedAt: Value(DateTime(2000))),
          );
      expect(await media.load('a', online: false), isNotNull);
      final indexed = await database.select(database.mediaCacheEntries).get();
      expect(
        indexed.singleWhere((e) => e.assetId == 'a').lastAccessedAt.year,
        DateTime.now().year,
      );
      await media.load('c', previewPath: '/c');
      expect(a!.existsSync(), isTrue);
      expect(await media.load('b', online: false), isNull);
      expect(server.paths, ['/a', '/b', '/c']);
      expect(
        (await database.select(database.mediaCacheEntries).get()).fold(
          0,
          (n, e) => n + e.byteCount,
        ),
        8,
      );
    },
  );

  test('clear and eviction protect draft and active-operation files', () async {
    final draft = await media.load('draft', previewPath: '/draft');
    await media.protect('draft', protected: true);
    final active = await media.load('active', previewPath: '/active');
    await media.protect('active', protected: true);
    final downloaded = await media.load(
      'downloaded',
      previewPath: '/downloaded',
    );
    await media.clearDownloaded();
    expect(draft!.existsSync(), isTrue);
    expect(active!.existsSync(), isTrue);
    expect(downloaded!.existsSync(), isFalse);
    expect(
      await database.select(database.mediaCacheEntries).get(),
      hasLength(2),
    );
  });

  test(
    'concurrent loads share download and missing files are recovered',
    () async {
      final files = await Future.wait([
        media.load('a', previewPath: '/a'),
        media.load('a', previewPath: '/a'),
      ]);
      expect(server.paths, ['/a']);
      expect(files.first!.path, files.last!.path);
      await files.first!.delete();
      expect(await media.load('a', online: false), isNull);
      expect(await media.load('a', previewPath: '/a'), isNotNull);
      expect(server.paths, ['/a', '/a']);
    },
  );

  test('offline reads bypass a stalled download', () async {
    await media.load('cached', previewPath: '/cached');
    final pending = Completer<ResponseBody>();
    final stalled = MediaRepository(
      database,
      FormApi(Dio()..httpClientAdapter = FakeServer((_) => pending.future)),
      'test',
      directory,
    );
    final download = stalled.load('new', previewPath: '/new');
    expect(
      await stalled
          .load('cached', online: false)
          .timeout(const Duration(seconds: 1)),
      isNotNull,
    );
    pending.complete(ResponseBody.fromBytes([1], 200));
    await download;
  });

  test('oversized images do not exceed download budget', () async {
    final tiny = MediaRepository(
      database,
      FormApi(Dio()..httpClientAdapter = server),
      'tiny',
      directory,
      maxBytes: 2,
    );
    expect(await tiny.load('a', previewPath: '/a'), isNull);
    expect(await database.select(database.mediaCacheEntries).get(), isEmpty);
  });
}
