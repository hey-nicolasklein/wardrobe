import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/character/character_setup_cubit.dart';
import 'package:form_mobile/features/settings/character/collage_geometry.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/character_draft.dart';
import 'package:form_mobile/repository/character_draft_repository.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/photo_preparation.dart';
import 'package:image/image.dart' as img;

import 'support/character_fixtures.dart';

class TestPreparation extends PhotoPreparation {
  @override
  Future<PreparedPhoto> prepare(String path) async {
    final image = img.Image(width: 120, height: 160);
    img.fill(
      image,
      color: img.ColorRgb8(
        path == 'red' ? 240 : 0,
        path == 'green' ? 240 : 0,
        path == 'blue' ? 240 : 0,
      ),
    );
    return PreparedPhoto(img.encodeJpg(image), 120, 160);
  }
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late CharacterApi api;
  late CharacterSheetRepository sheets;
  late CharacterDraftRepository repository;
  late CharacterSetupCubit cubit;
  var paths = <String>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('form-character-unit-');
    database = AppDatabase(NativeDatabase.memory());
    api = CharacterApi();
    sheets = CharacterSheetRepository(api, database: database, scope: 'test');
    repository = CharacterDraftRepository(sheets, directory, TestPreparation());
    paths = ['red'];
    cubit = CharacterSetupCubit(
      repository,
      online: true,
      pick: () async => paths,
    );
  });
  tearDown(() async {
    await cubit.close();
    await sheets.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'selection cancellation and count validation leave the draft unchanged',
    () async {
      paths = [];
      await cubit.choose();
      expect(cubit.state.draft, isNull);
      paths = ['a', 'b', 'c', 'd', 'e'];
      await cubit.choose();
      expect(cubit.state.error, LocaleKeys.character_photoCount);
      expect(cubit.state.draft, isNull);
      expect(api.requests, isEmpty);
    },
  );

  test(
    'draft photos survive the app container moving between launches',
    () async {
      await cubit.choose();
      await repository.render((await repository.load())!);
      // iOS gives the app a new container path after an update or reinstall.
      final moved = Directory('${directory.path}-moved');
      await directory.rename(moved.path);
      addTearDown(() => moved.rename(directory.path));
      final draft = (await CharacterDraftRepository(
        sheets,
        moved,
        TestPreparation(),
      ).load())!;
      expect(draft.photos.single.path, startsWith(moved.path));
      expect(File(draft.photos.single.path).existsSync(), isTrue);
      expect(draft.previewPath, startsWith(moved.path));
      expect(File(draft.previewPath!).existsSync(), isTrue);
    },
  );

  test(
    'crop edits and note survive forward/back navigation and reopening',
    () async {
      paths = ['red', 'green'];
      await cubit.choose();
      cubit
        ..zoom(2)
        ..pan(0.2, -0.4);
      final first = cubit.state.photo.crop.toJson();
      await cubit.next();
      expect(cubit.state.index, 1);
      cubit.zoom(3);
      await cubit.back();
      expect(cubit.state.photo.crop.toJson(), first);
      await cubit.next();
      expect(cubit.state.photo.crop.zoom, 3);
      await cubit.next();
      cubit.note('Test note');
      await cubit.crop(0);
      expect(cubit.state.draft!.note, 'Test note');
      final restored = CharacterSetupCubit(repository, online: false);
      addTearDown(restored.close);
      await restored.restore();
      expect(restored.state.draft!.photos.first.crop.toJson(), first);
      expect(restored.state.draft!.note, 'Test note');
      expect(restored.state.online, false);
    },
  );

  test(
    'rendered layout uses deterministic source placement for all counts',
    () async {
      for (var count = 1; count <= 4; count++) {
        final draft = await repository.prepare(
          ['red', 'green', 'blue', 'red'].take(count).toList(),
        );
        await repository.render(draft);
        final output = img.decodeJpg(
          await File(draft.previewPath!).readAsBytes(),
        )!;
        expect((output.width, output.height), (864, 1536));
        final tiles = collageLayout(count);
        for (var i = 0; i < count; i++) {
          final tile = tiles[i];
          final pixel = output.getPixel(
            tile.left + tile.width ~/ 2,
            tile.top + tile.height ~/ 2,
          );
          expect([pixel.r, pixel.g, pixel.b][i % 3], greaterThan(220));
        }
        await repository.discard(draft);
      }
    },
  );

  test(
    'changed crops render a new preview file and preserve original photos',
    () async {
      await cubit.choose();
      await cubit.next();
      final first = cubit.state.draft!.previewPath!;
      await cubit.crop(0);
      cubit.zoom(2);
      await cubit.next();
      expect(cubit.state.draft!.previewPath, isNot(first));
      expect(File(cubit.state.draft!.photos.single.path).existsSync(), true);
    },
  );

  test(
    'exact reviewed bytes upload once across completion loss and restart',
    () async {
      await cubit.choose();
      await cubit.next();
      cubit.note('  Height 180 cm  ');
      final draft = cubit.state.draft!;
      final reviewed = await File(draft.previewPath!).readAsBytes();
      api.loseCompletion = true;
      await cubit.submit();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.editable, false);
      expect(api.uploads.single, orderedEquals(reviewed));
      final restored = CharacterSetupCubit(repository, online: true);
      addTearDown(restored.close);
      await restored.restore();
      expect(restored.state.draft!.creationKey, draft.creationKey);
      await restored.submit();
      expect(restored.state.step, CharacterStep.finished);
      expect(api.uploads, hasLength(1));
      expect(api.completions.toSet(), {draft.completionKey});
      expect(api.creations.keys.single, draft.creationKey);
      expect(api.sheets.single['note'], 'Height 180 cm');
      expect(api.sheets.single['active'], true);
      expect(api.sheets.single['referenceAssetIds'], [
        draft.assetId ?? 'uploaded-1',
      ]);
      expect(await repository.load(), isNull);
      expect(File(draft.photos.single.path).existsSync(), false);
    },
  );

  test(
    'upload retry reuses intent and completion key before creation',
    () async {
      await cubit.choose();
      await cubit.next();
      api.failUpload = true;
      await cubit.submit();
      final key = cubit.state.draft!.completionKey;
      await cubit.submit();
      expect(cubit.state.step, CharacterStep.finished);
      expect(api.intentCount, 1);
      expect(api.completions.toSet(), {key});
      expect(api.creations, hasLength(1));
    },
  );

  test(
    'expired missing upload gets a new asset and completion command',
    () async {
      await cubit.choose();
      await cubit.next();
      api.failUpload = true;
      await cubit.submit();
      final draft = cubit.state.draft!;
      final completionKey = draft.completionKey;
      final creationKey = draft.creationKey;
      draft.intent!['expiresAt'] = DateTime(2020).toIso8601String();
      await cubit.submit();
      expect(api.intentCount, 2);
      expect(draft.completionKey, isNot(completionKey));
      expect(draft.creationKey, creationKey);
      expect(api.sheets.single['assetId'], 'uploaded-2');
    },
  );

  test(
    'lost creation response retries frozen payload and stable key only once',
    () async {
      await cubit.choose();
      await cubit.next();
      cubit.note('original');
      api.loseCreation = true;
      await cubit.submit();
      expect(cubit.state.step, CharacterStep.review);
      cubit.note('changed');
      await cubit.crop(0);
      cubit.zoom(6);
      expect(cubit.state.draft!.note, 'original');
      expect(cubit.state.step, CharacterStep.review);
      await cubit.submit();
      expect(cubit.state.step, CharacterStep.finished);
      expect(api.creations, hasLength(1));
      expect(api.uploads, hasLength(1));
      final creates = api.requests
          .where((r) => r.path == 'v1/character-sheets' && r.method == 'POST')
          .toList();
      expect(creates, hasLength(2));
      expect(creates.first.data, creates.last.data);
    },
  );

  test(
    'offline submit sends nothing, and discard removes protected local files',
    () async {
      await cubit.choose();
      await cubit.next();
      final file = File(cubit.state.draft!.previewPath!);
      cubit.setOnline(online: false);
      await cubit.submit();
      expect(api.requests, isEmpty);
      expect(cubit.state.canSubmit, false);
      await cubit.discard();
      expect(file.existsSync(), false);
      expect(await repository.load(), isNull);
      expect(cubit.state.step, CharacterStep.select);
    },
  );

  test('draft DTO serializes all crop and upload checkpoints', () async {
    await cubit.choose();
    await cubit.next();
    api.loseCompletion = true;
    await cubit.submit();
    final json = cubit.state.draft!.toJson();
    expect(CharacterDraft.fromJson(json).toJson(), json);
  });
  test(
    'accepted creation with failed refresh retries only the refresh',
    () async {
      await cubit.choose();
      await cubit.next();
      api.afterCreation = () => api.offline = true;
      await cubit.submit();
      expect(cubit.state.draft!.createdId, isNotNull);
      expect(cubit.state.step, CharacterStep.review);
      api.offline = false;
      await cubit.submit();
      expect(cubit.state.step, CharacterStep.finished);
      expect(
        api.requests.where(
          (r) => r.method == 'POST' && r.path == 'v1/character-sheets',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'offline during upload stops completion and resumes the same command',
    () async {
      await cubit.choose();
      await cubit.next();
      api.afterUpload = () => cubit.setOnline(online: false);
      await cubit.submit();
      expect(api.completions, isEmpty);
      expect(api.creations, isEmpty);
      expect(cubit.state.busy, false);
      cubit.setOnline(online: true);
      await cubit.submit();
      expect(cubit.state.step, CharacterStep.finished);
      expect(api.uploads, hasLength(1));
    },
  );
}
