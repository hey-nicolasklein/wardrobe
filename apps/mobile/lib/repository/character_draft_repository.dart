import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:form_mobile/features/settings/character/collage_geometry.dart';
import 'package:form_mobile/models/character_draft.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/photo_preparation.dart';
import 'package:form_mobile/utils/idempotency_key.dart';
import 'package:image/image.dart' as img;

Uint8List renderCharacterCollage(List<CharacterPhoto> photos) {
  final output = img.Image(width: collageWidth, height: collageHeight);
  img.fill(output, color: img.ColorRgb8(255, 255, 255));
  final tiles = collageLayout(photos.length);
  for (var i = 0; i < photos.length; i++) {
    final photo = photos[i];
    final tile = tiles[i];
    final image = img.decodeJpg(File(photo.path).readAsBytesSync())!;
    final bounds = photo.crop.bounds(photo.width, photo.height, tile);
    final crop = img.copyCrop(
      image,
      x: bounds.x.round(),
      y: bounds.y.round(),
      width: bounds.width.round(),
      height: bounds.height.round(),
    );
    final resized = img.copyResize(
      crop,
      width: tile.width,
      height: tile.height,
      interpolation: img.Interpolation.linear,
    );
    img.compositeImage(output, resized, dstX: tile.left, dstY: tile.top);
  }
  return img.encodeJpg(output, quality: 95);
}

class CharacterDraftRepository {
  CharacterDraftRepository(this.sheets, this.directory, this.preparation);
  final CharacterSheetRepository sheets;
  final Directory directory;
  final PhotoPreparation preparation;
  String get _key => 'character-draft:${sheets.scope}';

  Future<CharacterDraft?> load() async {
    final raw = await sheets.database.preference(_key);
    return raw == null || raw.isEmpty
        ? null
        : CharacterDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> persist(CharacterDraft draft) =>
      sheets.database.setPreference(_key, jsonEncode(draft.toJson()));

  Future<CharacterDraft> prepare(List<String> paths) async {
    collageLayout(paths.length);
    final id = newIdempotencyKey();
    final folder = await Directory(
      '${directory.path}/$id',
    ).create(recursive: true);
    final photos = <CharacterPhoto>[];
    try {
      for (final path in paths) {
        final photo = await preparation.prepare(path);
        final file = File('${folder.path}/${photos.length}.jpg');
        await file.writeAsBytes(photo.bytes, flush: true);
        photos.add(
          CharacterPhoto(
            path: file.path,
            width: photo.width,
            height: photo.height,
          ),
        );
      }
      final draft = CharacterDraft(
        id: id,
        photos: photos,
        creationKey: newIdempotencyKey(),
        completionKey: newIdempotencyKey(),
      );
      await persist(draft);
      return draft;
    } on Object {
      await folder.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> render(CharacterDraft draft) async {
    final bytes = await compute(renderCharacterCollage, draft.photos);
    final file = File(
      '${directory.path}/${draft.id}/reviewed-${newIdempotencyKey()}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    draft.previewPath = file.path;
    await persist(draft);
  }

  Future<void> discard(CharacterDraft draft) async {
    await sheets.database.setPreference(_key, '');
    await removeFiles(draft);
  }

  Future<void> removeFiles(CharacterDraft draft) async {
    final folder = Directory('${directory.path}/${draft.id}');
    if (folder.existsSync()) await folder.delete(recursive: true);
  }

  Future<void> _complete(CharacterDraft draft) async {
    final response = await sheets.request(
      'v1/source-photos/complete',
      method: 'POST',
      data: {
        'assetId': draft.intent!['assetId'],
        'idempotencyKey': draft.completionKey,
      },
    );
    final asset = response['asset'] as Map<String, dynamic>;
    draft.assetId = asset['id'] as String;
    await persist(draft);
  }

  Future<void> upload(
    CharacterDraft draft,
    void Function(double) progress,
    bool Function() online,
  ) async {
    void checkOnline() {
      if (!online()) throw const FormApiException(ApiFailure.unavailable);
    }

    checkOnline();
    if (draft.assetId != null) return;
    if (draft.intent != null) {
      try {
        await _complete(draft);
        return;
      } on FormApiException catch (error) {
        if (error.code != 'upload-missing') rethrow;
      }
    }
    checkOnline();
    if (draft.intent == null ||
        DateTime.parse(
          draft.intent!['expiresAt'] as String,
        ).isBefore(DateTime.now())) {
      final replacesAsset = draft.intent != null;
      draft.intent = await sheets.request(
        'v1/source-photos/upload-intents',
        method: 'POST',
        data: {
          'fileName': 'character-reference.jpg',
          'contentType': 'image/jpeg',
          'byteSize': await File(draft.previewPath!).length(),
        },
      );
      if (replacesAsset) draft.completionKey = newIdempotencyKey();
      await persist(draft);
    }
    checkOnline();
    // Upload the frozen preview file without rendering another derivative.
    await sheets.api!.upload(
      draft.intent!['uploadUrl'] as String,
      await File(draft.previewPath!).readAsBytes(),
      draft.intent!['headers'] as Map<String, dynamic>,
      (sent, total) => progress(total <= 0 ? 0 : sent / total),
    );
    checkOnline();
    await _complete(draft);
  }

  Future<void> clearLocalDraft() async {
    final draft = await load();
    if (draft != null) await removeFiles(draft);
    await sheets.database.setPreference(_key, '');
  }
}
