import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/models/intake.dart';
import 'package:form_mobile/repository/intake_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/photo_preparation.dart';
import 'package:image/image.dart' as img;

class IntakeApi extends FormApi {
  IntakeApi() : super(Dio());
  final calls = <(String, Map<String, dynamic>?)>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)? respond;
  Future<void> Function()? onUpload;
  int uploads = 0;
  int _assets = 0;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    calls.add((
      path,
      data == null
          ? null
          : jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
    ));
    if (respond != null) return respond!(path, data);
    return answer(path, data);
  }

  Map<String, dynamic> answer(String path, Map<String, dynamic>? body) {
    if (path.endsWith('upload-intents')) {
      return {
        'assetId': 'asset-${_assets++}',
        'uploadUrl': 'https://example.test/upload',
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'headers': <String, dynamic>{'Content-Type': 'image/jpeg'},
      };
    }
    if (path.endsWith('/complete')) {
      return {
        'sourcePhoto': {'id': 'source-${body!['assetId']}'},
      };
    }
    if (path.endsWith('/detections')) {
      return body != null
          ? {}
          : {
              'attempt': {'state': 'succeeded'},
              'detections': [proposal().toJson()],
            };
    }
    if (path.endsWith('wardrobe-items') || path.endsWith('from-photo')) {
      return {
        'wardrobeItem': {'id': 'item-${body!['idempotencyKey']}'},
      };
    }
    return {};
  }

  @override
  Future<void> upload(
    String url,
    Uint8List bytes,
    Map<String, dynamic> headers,
    void Function(int, int) progress,
  ) async {
    uploads++;
    await onUpload?.call();
    progress(bytes.length, bytes.length);
  }
}

DetectionProposal proposal([String id = 'proposal-0000000001']) =>
    DetectionProposal(
      id: id,
      name: 'Shirt',
      category: 'top',
      colors: ['blue'],
      boundingBox: DetectionBox(x: 100, y: 200, width: 300, height: 400),
    );

IntakeChoice choice([String id = 'proposal-0000000001']) => IntakeChoice(
  itemKey: intakeKey(),
  generationKey: intakeKey(),
  proposal: proposal(id),
);

Future<void> send(IntakeBloc bloc, IntakeEvent event) async {
  final done = bloc.stream.firstWhere((s) => !s.busy);
  bloc.add(event);
  await done.timeout(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original limit is inclusive, dimensions never upscale or exceed 2400',
    () {
      validatePhotoSize(maximumPhotoBytes);
      expect(
        () => validatePhotoSize(maximumPhotoBytes + 1),
        throwsFormatException,
      );
      expect(() => validatePhotoSize(0), throwsFormatException);
      expect(photoDimensions(4000, 3000), (2400, 1800));
      expect(photoDimensions(3000, 4000), (1800, 2400));
      expect(photoDimensions(10, 20), (10, 20));
      expect(photoDimensions(1, 9999), (1, 2400));
    },
  );
  test('JPEG normalization bakes EXIF orientation and strips metadata', () {
    final input = img.Image(width: 8, height: 4);
    input.exif.imageIfd.orientation = 6;
    final result = normalizePhoto(img.encodeJpg(input))!;
    expect((result.width, result.height), (4, 8));
    final decoded = img.decodeJpg(result.bytes)!;
    expect(decoded.exif.imageIfd.orientation, isNull);
    expect(result.bytes.take(2), [255, 216]);
  });
  test('normalized boxes map to exactly the same source crop', () {
    final box = proposal().boundingBox;
    expect(
      box.pixels(const Size(2400, 1800)),
      const Rect.fromLTWH(240, 360, 720, 720),
    );
    expect(
      () => DetectionBox(x: 999, y: 0, width: 2, height: 1),
      throwsFormatException,
    );
    expect(
      () => DetectionBox(x: 0, y: 0, width: 1, height: 0),
      throwsFormatException,
    );
    expect(
      DetectionProposal.fromJson(proposal().toJson()).boundingBox.toJson(),
      box.toJson(),
    );
  });
  test(
    'manual validation matches supported categories, metadata, and ownership',
    () {
      final edit = ItemEdit(
        name: ' Shirt ',
        category: 'top',
        colors: ' blue, white ',
        notes: '',
        state: 'owning',
      );
      expect(edit.metadata.name, 'Shirt');
      expect(edit.metadata.colors, ['blue', 'white']);
      expect(
        () => ItemEdit(
          name: '',
          category: 'top',
          colors: 'blue',
          notes: '',
          state: 'owning',
        ),
        throwsFormatException,
      );
      expect(
        () => ItemEdit(
          name: 'Shirt',
          category: 'unsupported',
          colors: 'blue',
          notes: '',
          state: 'owning',
        ),
        throwsFormatException,
      );
      expect(ItemEdit.validColors('blue,'), isFalse);
    },
  );

  late Directory directory;
  late AppDatabase database;
  late IntakeApi api;
  late IntakeRepository repository;
  late int refreshes;
  Future<IntakeDraft> draft({
    DraftPhase phase = DraftPhase.local,
    List<IntakeChoice>? choices,
  }) async {
    final file = File('${directory.path}/${intakeKey()}.jpg');
    await file.writeAsBytes([255, 216, 255]);
    final value = IntakeDraft(
      id: intakeKey(),
      filePath: file.path,
      width: 2400,
      height: 1800,
      completionKey: intakeKey(),
      detectionKey: intakeKey(),
      phase: phase,
      choices: choices,
    );
    if (phase.index >= DraftPhase.uploaded.index) {
      value.sourceId = 'source-000000000001';
    }
    await repository.persist(value);
    return value;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('form-intake-test-');
    database = AppDatabase(NativeDatabase.memory());
    api = IntakeApi();
    refreshes = 0;
    repository = IntakeRepository(
      database,
      api,
      'test',
      directory,
      PhotoPreparation(),
      () async {
        refreshes++;
      },
    );
  });
  tearDown(() async {
    api.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'every unfinished phase survives closing and reopening SQLite',
    () async {
      await database.close();
      final dbFile = File('${directory.path}/drafts.sqlite');
      database = AppDatabase(NativeDatabase(dbFile));
      repository = IntakeRepository(
        database,
        api,
        'test',
        directory,
        PhotoPreparation(),
        () async {},
      );
      final originals = <IntakeDraft>[];
      for (final phase in DraftPhase.values.where(
        (p) => p != DraftPhase.discarded,
      )) {
        originals.add(await draft(phase: phase, choices: [choice()]));
      }
      await database.close();
      database = AppDatabase(NativeDatabase(dbFile));
      repository = IntakeRepository(
        database,
        api,
        'test',
        directory,
        PhotoPreparation(),
        () async {},
      );
      final restored = await repository.load();
      expect(
        restored.map((d) => jsonEncode(d.toJson())).toSet(),
        originals.map((d) => jsonEncode(d.toJson())).toSet(),
      );
      expect(restored.every((d) => File(d.filePath).existsSync()), isTrue);
    },
  );

  test(
    'draft photos survive the app container moving between launches',
    () async {
      final original = File('${directory.path}/input.png');
      await original.writeAsBytes(
        img.encodePng(img.Image(width: 20, height: 30)),
      );
      final saved = await repository.add(original.path);
      // iOS gives the app a new container path after an update or reinstall.
      final moved = await Directory.systemTemp.createTemp('form-intake-moved-');
      addTearDown(() => moved.delete(recursive: true));
      final name = saved.filePath.split('/').last;
      await File(saved.filePath).copy('${moved.path}/$name');
      repository = IntakeRepository(
        database,
        api,
        'test',
        moved,
        PhotoPreparation(),
        () async {},
      );
      await repository.cleanOrphanFiles();
      final restored = (await repository.load()).single;
      expect(restored.filePath, '${moved.path}/$name');
      expect(File(restored.filePath).existsSync(), isTrue);
    },
  );

  test(
    'photo preparation persists JPEG and metadata before network access',
    () async {
      final original = File('${directory.path}/input.png');
      await original.writeAsBytes(
        img.encodePng(img.Image(width: 20, height: 30)),
      );
      final saved = await repository.add(original.path);
      expect((saved.width, saved.height), (20, 30));
      expect(
        img.decodeJpg(await File(saved.filePath).readAsBytes()),
        isNotNull,
      );
      expect((await repository.load()).single.id, saved.id);
      expect(api.calls, isEmpty);
    },
  );

  test(
    'sequential uploads preserve siblings and retry detection keys',
    () async {
      final first = await draft();
      final second = await draft();
      final bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      var fail = true;
      api.respond = (path, body) async {
        if (path.endsWith('/detections') &&
            body != null &&
            body['idempotencyKey'] == first.detectionKey &&
            fail) {
          throw const FormApiException(ApiFailure.unavailable);
        }
        return api.answer(path, body);
      };
      final complete = bloc.stream.firstWhere((s) => !s.busy);
      bloc.availability(online: true, visible: true);
      await complete;
      expect(
        bloc.state.drafts.firstWhere((d) => d.id == first.id).failure,
        'unavailable',
      );
      expect(
        bloc.state.drafts.firstWhere((d) => d.id == second.id).phase,
        DraftPhase.ready,
      );
      expect(api.uploads, 2);
      final paths = api.calls.map((c) => c.$1).toList();
      expect(
        paths.indexOf('v1/source-photos/complete'),
        lessThan(paths.lastIndexOf('v1/source-photos/upload-intents')),
      );
      fail = false;
      await send(bloc, IntakeEvent(IntakeAction.retry, id: first.id));
      expect(
        bloc.state.drafts.every((d) => d.phase == DraftPhase.ready),
        isTrue,
      );
      expect(api.uploads, 2);
      expect(
        api.calls
            .where(
              (c) =>
                  c.$1.endsWith('/detections') &&
                  c.$2?['idempotencyKey'] == first.detectionKey,
            )
            .length,
        2,
      );
      await bloc.close();
    },
  );

  test(
    'lost PUT response resumes without another upload',
    () async {
      final saved = await draft();
      api.onUpload = () async {
        throw const FormApiException(ApiFailure.unavailable);
      };
      await expectLater(
        repository.upload(saved, (_) {}, () => true),
        throwsA(isA<FormApiException>()),
      );
      final restored = (await repository.load()).single;
      final completionKey = restored.completionKey;
      await repository.upload(restored, (_) {}, () => true);
      expect(restored.phase, DraftPhase.uploaded);
      expect(restored.completionKey, completionKey);
      expect(api.uploads, 1);
    },
  );

  test(
    'expired missing upload receives a new intent',
    () async {
      final saved = await draft();
      saved.intent = {
        'assetId': 'expired',
        'expiresAt': DateTime(2020).toIso8601String(),
        'uploadUrl': 'url',
        'headers': <String, dynamic>{},
      };
      final oldKey = saved.completionKey;
      api.respond = (path, body) async {
        if (path.endsWith('/complete') && body!['assetId'] == 'expired') {
          throw const FormApiException(
            ApiFailure.rejected,
            code: 'upload-missing',
          );
        }
        return api.answer(path, body);
      };
      await repository.upload(saved, (_) {}, () => true);
      expect(saved.completionKey, isNot(oldKey));
      expect(saved.phase, DraftPhase.uploaded);
      expect(api.uploads, 1);
    },
  );

  test(
    'backgrounding during PUT defers completion and resumes safely',
    () async {
      final saved = await draft();
      var active = true;
      api.onUpload = () async {
        active = false;
      };
      await repository.upload(saved, (_) {}, () => active);
      expect(saved.phase, DraftPhase.uploading);
      expect(api.calls.any((c) => c.$1.endsWith('/complete')), isFalse);
      await repository.upload(saved, (_) {}, () => true);
      expect(saved.phase, DraftPhase.uploaded);
      expect(api.uploads, 1);
    },
  );

  test(
    'batch ownership, individual override and selection persist in order',
    () async {
      final saved = await draft(
        phase: DraftPhase.ready,
        choices: [choice('one'), choice('two')],
      );
      final bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      await send(
        bloc,
        IntakeEvent(IntakeAction.ownership, id: saved.id, value: false),
      );
      await send(
        bloc,
        IntakeEvent(
          IntakeAction.ownership,
          id: saved.id,
          choiceKey: saved.choices.first.itemKey,
          value: true,
        ),
      );
      await send(
        bloc,
        IntakeEvent(
          IntakeAction.select,
          id: saved.id,
          choiceKey: saved.choices.last.itemKey,
          value: false,
        ),
      );
      final restored = (await repository.load()).single;
      expect(restored.choices.map((c) => c.ownership), ['owning', 'wanting']);
      expect(restored.choices.map((c) => c.selected), [true, false]);
      expect(api.calls, isEmpty);
      await bloc.close();
    },
  );

  test(
    'partial save resumes only incomplete generation',
    () async {
      final saved = await draft(
        phase: DraftPhase.ready,
        choices: [choice('one'), choice('two')],
      );
      var bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      bloc.availability(online: true);
      var fail = true;
      api.respond = (path, body) async {
        if (path == 'v1/generations' &&
            body!['idempotencyKey'] == saved.choices.last.generationKey &&
            fail) {
          throw const FormApiException(ApiFailure.unavailable);
        }
        return api.answer(path, body);
      };
      await send(bloc, IntakeEvent(IntakeAction.save, id: saved.id));
      final partial = (await repository.load()).single;
      expect(partial.choices.first.enqueued, isTrue);
      expect(partial.choices.last.itemId, isNotNull);
      expect(partial.choices.last.enqueued, isFalse);
      expect(File(saved.filePath).existsSync(), isTrue);
      await send(
        bloc,
        IntakeEvent(IntakeAction.ownership, id: saved.id, value: false),
      );
      expect(bloc.state.drafts.single.choices.last.ownership, 'owning');
      await bloc.close();
      bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      bloc.availability(online: true);
      fail = false;
      await send(bloc, IntakeEvent(IntakeAction.retry, id: saved.id));
      expect(bloc.state.drafts, isEmpty);
      expect(api.calls.where((c) => c.$1 == 'v1/wardrobe-items').length, 2);
      final generations = api.calls
          .where((c) => c.$1 == 'v1/generations')
          .toList();
      expect(generations.length, 3);
      expect(generations[1].$2, generations[2].$2);
      expect(refreshes, greaterThanOrEqualTo(1));
      expect(File(saved.filePath).existsSync(), isFalse);
      await bloc.close();
    },
  );

  test('offline restore and save do not issue remote commands', () async {
    final saved = await draft(phase: DraftPhase.ready, choices: [choice()]);
    final bloc = IntakeBloc(repository);
    await send(bloc, const IntakeEvent(IntakeAction.restore));
    await send(bloc, IntakeEvent(IntakeAction.save, id: saved.id));
    expect(bloc.state.drafts.single.phase, DraftPhase.ready);
    expect(api.calls, isEmpty);
    await bloc.close();
  });

  test('accessories are opt-in and retain their selection on reload', () async {
    final saved = await draft(phase: DraftPhase.detecting);
    api.respond = (_, _) async => {
      'attempt': {'state': 'succeeded'},
      'detections': [
        proposal().toJson(),
        {...proposal('accessory').toJson(), 'category': 'accessory'},
      ],
    };
    await repository.poll(saved);
    expect(saved.phase, DraftPhase.ready);
    expect(saved.choices.map((choice) => choice.selected), [true, false]);
    final restored = (await repository.load()).single;
    expect(restored.choices.last.proposal!.category, 'accessory');
    expect(restored.choices.last.selected, isFalse);
    restored.choices.last.selected = true;
    await repository.persist(restored);
    expect((await repository.load()).single.choices.last.selected, isTrue);
    expect(
      ItemEdit(
        name: 'Glasses',
        category: 'accessory',
        colors: 'black',
        notes: '',
        state: 'wanting',
      ).metadata.category,
      'accessory',
    );
  });

  test('failed and unsupported-only detection use manual fallback', () async {
    for (final status in ['failed', 'succeeded']) {
      final saved = await draft(phase: DraftPhase.detecting);
      api.respond = (_, _) async => {
        'attempt': {'state': status},
        'detections': [
          {...proposal().toJson(), 'category': 'unsupported'},
        ],
      };
      await repository.poll(saved);
      expect(saved.phase, DraftPhase.manual);
    }
  });

  test(
    'manual save uses UUID and default generation',
    () async {
      final saved = await draft(phase: DraftPhase.manual);
      final bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      bloc.availability(online: true);
      await send(
        bloc,
        IntakeEvent(
          IntakeAction.manual,
          id: saved.id,
          edit: ItemEdit(
            name: 'Shirt',
            category: 'top',
            colors: 'blue',
            notes: '',
            state: 'wanting',
          ),
        ),
      );
      final create = api.calls
          .firstWhere((c) => c.$1.endsWith('/from-photo'))
          .$2!;
      expect(create['state'], 'wanting');
      expect(
        create['idempotencyKey'],
        matches(
          RegExp(
            '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(api.calls.last.$2!['quality'], 'low');
      expect(bloc.state.drafts, isEmpty);
      await bloc.close();
    },
  );

  test(
    'route and foreground return resume polling',
    () async {
      await draft(phase: DraftPhase.detecting);
      api.respond = (_, _) async => {
        'attempt': {'state': 'processing'},
        'detections': <dynamic>[],
      };
      final bloc = IntakeBloc(
        repository,
        pollInterval: const Duration(milliseconds: 15),
      );
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      var next = bloc.stream.firstWhere((s) => !s.busy);
      bloc.availability(online: true, visible: true);
      await next;
      bloc.availability(visible: false);
      final count = api.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(api.calls.length, count);
      next = bloc.stream.firstWhere((s) => !s.busy);
      bloc.availability(visible: true);
      await next;
      expect(api.calls.length, greaterThan(count));
      bloc.availability(foreground: false);
      final paused = api.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(api.calls.length, paused);
      next = bloc.stream.firstWhere((s) => !s.busy);
      bloc.availability(foreground: true);
      await next;
      expect(api.calls.length, greaterThan(paused));
      expect(api.calls.every((c) => c.$2 == null), isTrue);
      await bloc.close();
    },
  );

  test('discard deletes only its protected file and metadata', () async {
    final first = await draft();
    final second = await draft();
    await repository.remove(first);
    expect(File(first.filePath).existsSync(), isFalse);
    expect(File(second.filePath).existsSync(), isTrue);
    expect((await repository.load()).single.id, second.id);
    expect(api.calls, isEmpty);
  });
  test('discard during upload prevents completion and detection', () async {
    final saved = await draft();
    final bloc = IntakeBloc(repository);
    await send(bloc, const IntakeEvent(IntakeAction.restore));
    final uploaded = Completer<void>();
    final release = Completer<void>();
    api.onUpload = () async {
      uploaded.complete();
      await release.future;
    };
    bloc.availability(online: true, visible: true);
    await uploaded.future;
    final discarded = bloc.stream.firstWhere(
      (s) => !s.busy && s.drafts.isEmpty,
    );
    bloc.discard(saved.id);
    release.complete();
    await discarded;
    expect(api.calls.any((c) => c.$1.endsWith('/complete')), isFalse);
    expect(File(saved.filePath).existsSync(), isFalse);
    await bloc.close();
  });

  test(
    'uncertain item creation retries its frozen command after restart',
    () async {
      final saved = await draft(phase: DraftPhase.ready, choices: [choice()]);
      var bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      bloc.availability(online: true);
      api.respond = (path, body) async {
        if (path == 'v1/wardrobe-items') {
          throw const FormApiException(ApiFailure.unavailable);
        }
        return api.answer(path, body);
      };
      await send(bloc, IntakeEvent(IntakeAction.save, id: saved.id));
      final original = api.calls.single.$2;
      await bloc.close();
      bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      await send(
        bloc,
        IntakeEvent(
          IntakeAction.select,
          id: saved.id,
          choiceKey: saved.choices.single.itemKey,
          value: false,
        ),
      );
      expect(bloc.state.drafts.single.choices.single.selected, isTrue);
      api.respond = null;
      bloc.availability(online: true);
      await send(bloc, IntakeEvent(IntakeAction.retry, id: saved.id));
      expect(
        api.calls.where((c) => c.$1 == 'v1/wardrobe-items').last.$2,
        original,
      );
      expect(bloc.state.drafts, isEmpty);
      await bloc.close();
    },
  );

  test(
    'cache refresh failure retains a finished draft without repeating saves',
    () async {
      final saved = await draft(
        phase: DraftPhase.finished,
        choices: [choice()],
      );
      var fail = true;
      repository = IntakeRepository(
        database,
        api,
        'test',
        directory,
        PhotoPreparation(),
        () async {
          if (fail) throw const FormApiException(ApiFailure.unavailable);
        },
      );
      final bloc = IntakeBloc(repository);
      await send(bloc, const IntakeEvent(IntakeAction.restore));
      final done = bloc.stream.firstWhere((s) => !s.busy);
      bloc.availability(online: true, visible: true);
      await done;
      expect(bloc.state.drafts.single.phase, DraftPhase.finished);
      expect(File(saved.filePath).existsSync(), isTrue);
      fail = false;
      await send(bloc, IntakeEvent(IntakeAction.retry, id: saved.id));
      expect(bloc.state.drafts, isEmpty);
      expect(api.calls, isEmpty);
      await bloc.close();
    },
  );

  test('orphan cleanup protects drafts from all server scopes', () async {
    final first = await draft();
    final other = IntakeRepository(
      database,
      api,
      'other',
      directory,
      PhotoPreparation(),
      () async {},
    );
    final second = await draft();
    await other.persist(second);
    final orphan = File('${directory.path}/orphan.jpg');
    await orphan.writeAsBytes([1]);
    await repository.cleanOrphanFiles();
    expect(orphan.existsSync(), isFalse);
    expect(File(first.filePath).existsSync(), isTrue);
    expect(File(second.filePath).existsSync(), isTrue);
  });
}
