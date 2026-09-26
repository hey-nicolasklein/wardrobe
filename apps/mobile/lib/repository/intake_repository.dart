import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:form_mobile/models/intake.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/photo_preparation.dart';

class IntakeRepository {
  IntakeRepository(
    this.database,
    this.api,
    this.scope,
    this.directory,
    this.prepare,
    this.refreshWardrobe,
  );
  final AppDatabase database;
  final FormApi? api;
  final String scope;
  final Directory directory;
  final PhotoPreparation prepare;
  final Future<void> Function() refreshWardrobe;

  Future<List<IntakeDraft>> load() async {
    final records = await (database.select(
      database.intakeRecords,
    )..where((r) => r.scope.equals(scope))).get();
    final drafts = records.map((r) {
      final json = jsonDecode(r.draftJson) as Map<String, dynamic>;
      return IntakeDraft.fromJson({
        ...json,
        'filePath': _local(json['filePath'] as String),
      });
    }).toList();
    for (final draft in drafts.where((d) => d.phase == DraftPhase.discarded)) {
      await remove(draft);
    }
    return drafts.where((d) => d.phase != DraftPhase.discarded).toList();
  }

  Future<void> persist(IntakeDraft draft) => database
      .into(database.intakeRecords)
      .insertOnConflictUpdate(
        IntakeRecordsCompanion.insert(
          scope: scope,
          id: draft.id,
          draftJson: jsonEncode(draft.toJson()),
        ),
      );

  /// The photo's path in the current [directory]. Saved paths are absolute
  /// and name the app container of the launch that wrote them; iOS moves the
  /// container on app updates and reinstalls, the file name stays.
  String _local(String path) => '${directory.path}/${path.split('/').last}';

  Future<void> cleanOrphanFiles() async {
    if (!directory.existsSync()) return;
    final records = await database.select(database.intakeRecords).get();
    final protectedPaths = records
        .map(
          (row) => _local(
            (jsonDecode(row.draftJson) as Map<String, dynamic>)['filePath']
                as String,
          ),
        )
        .toSet();
    await for (final file in directory.list()) {
      if (file is File &&
          file.path.endsWith('.jpg') &&
          !protectedPaths.contains(file.path)) {
        await file.delete();
      }
    }
  }

  Future<IntakeDraft> add(String path) async {
    final photo = await prepare.prepare(path);
    final id = intakeKey();
    await directory.create(recursive: true);
    final file = File('${directory.path}/$id.jpg');
    await file.writeAsBytes(photo.bytes, flush: true);
    final preference = await database.preference('wardrobe-quality');
    final draft = IntakeDraft(
      id: id,
      filePath: file.path,
      width: photo.width,
      height: photo.height,
      completionKey: intakeKey(),
      detectionKey: intakeKey(),
      quality: ['low', 'medium', 'high'].contains(preference)
          ? preference!
          : 'low',
    );
    try {
      await persist(draft);
    } on Object {
      await file.delete();
      rethrow;
    }
    return draft;
  }

  Future<void> remove(IntakeDraft draft) async {
    // Keep the tombstone until deletion succeeds, including after a restart.
    draft.phase = DraftPhase.discarded;
    await persist(draft);
    final file = File(draft.filePath);
    if (file.existsSync()) await file.delete();
    await (database.delete(
      database.intakeRecords,
    )..where((r) => r.scope.equals(scope) & r.id.equals(draft.id))).go();
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) {
    final client = api;
    if (client == null) throw const FormApiException(ApiFailure.unavailable);
    return client.request(
      path,
      method: body == null ? 'GET' : 'POST',
      data: body,
    );
  }

  Future<void> _complete(IntakeDraft draft) async {
    final data = await request(
      'v1/source-photos/complete',
      body: {
        'assetId': draft.intent!['assetId'],
        'idempotencyKey': draft.completionKey,
      },
    );
    draft
      ..sourceId = (data['sourcePhoto'] as Map<String, dynamic>)['id'] as String
      ..phase = DraftPhase.uploaded;
    await persist(draft);
  }

  Future<void> upload(
    IntakeDraft draft,
    void Function(double) progress,
    bool Function() canContinue,
  ) async {
    if (draft.intent != null) {
      // Probe completion first if a previous response may have been lost.
      try {
        await _complete(draft);
        return;
      } on FormApiException catch (error) {
        if (error.code != 'upload-missing') rethrow;
      }
    }
    if (!canContinue()) return;
    if (draft.intent == null ||
        DateTime.parse(
          draft.intent!['expiresAt'] as String,
        ).isBefore(DateTime.now())) {
      final replacesAsset = draft.intent != null;
      final intent = await request(
        'v1/source-photos/upload-intents',
        body: {
          'fileName': 'wardrobe.jpg',
          'contentType': 'image/jpeg',
          'byteSize': await File(draft.filePath).length(),
        },
      );
      // A definitely missing asset can be replaced with a new command.
      draft
        ..intent = intent
        ..completionKey = replacesAsset ? intakeKey() : draft.completionKey
        ..phase = DraftPhase.uploading;
      await persist(draft);
    }
    if (!canContinue()) return;
    await api!.upload(
      draft.intent!['uploadUrl'] as String,
      await File(draft.filePath).readAsBytes(),
      draft.intent!['headers'] as Map<String, dynamic>,
      (sent, total) => progress(total <= 0 ? 0 : sent / total),
    );
    if (!canContinue()) return;
    await _complete(draft);
  }

  Future<void> detect(IntakeDraft draft) async {
    await request(
      'v1/source-photos/${draft.sourceId}/detections',
      body: {'idempotencyKey': draft.detectionKey},
    );
    draft.phase = DraftPhase.detecting;
    await persist(draft);
  }

  Future<void> poll(IntakeDraft draft) async {
    final data = await request('v1/source-photos/${draft.sourceId}/detections');
    final attempt = data['attempt'] as Map<String, dynamic>?;
    if (attempt?['state'] == 'failed') {
      draft.phase = DraftPhase.manual;
    } else if (attempt?['state'] == 'succeeded') {
      final proposals = (data['detections'] as List<dynamic>)
          .map((p) => DetectionProposal.fromJson(p as Map<String, dynamic>))
          .where((p) => p.category != 'unsupported');
      draft.choices.addAll(
        proposals.map(
          (p) => IntakeChoice(
            itemKey: intakeKey(),
            generationKey: intakeKey(),
            proposal: p,
            selected: p.category != 'accessory',
            ownership: draft.ownership,
          ),
        ),
      );
      draft.phase = draft.choices.isEmpty
          ? DraftPhase.manual
          : DraftPhase.ready;
    }
    await persist(draft);
  }

  Future<void> save(IntakeDraft draft, bool Function() canContinue) async {
    for (final choice in draft.choices.where(
      (c) => c.selected && !c.enqueued,
    )) {
      if (!canContinue()) return;
      if (choice.itemId == null) {
        final data = await request(
          choice.proposal == null
              ? 'v1/wardrobe-items/from-photo'
              : 'v1/wardrobe-items',
          body: choice.command,
        );
        choice.itemId =
            (data['wardrobeItem'] as Map<String, dynamic>)['id'] as String;
        await persist(draft);
        await refreshWardrobe();
      }
      if (!canContinue()) return;
      await request(
        'v1/generations',
        body: {
          'wardrobeItemId': choice.itemId,
          'quality': draft.quality,
          'size': '816x816',
          'autoKeep': true,
          'idempotencyKey': choice.generationKey,
        },
      );
      choice.enqueued = true;
      await persist(draft);
    }
    draft.phase = DraftPhase.finished;
    await persist(draft);
  }

  Future<void> finish(IntakeDraft draft) async {
    await refreshWardrobe();
    await remove(draft);
  }
}
