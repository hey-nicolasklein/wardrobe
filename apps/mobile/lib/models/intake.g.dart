// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intake.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DetectionBox _$DetectionBoxFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DetectionBox', json, ($checkedConvert) {
      final val = DetectionBox(
        x: $checkedConvert('x', (v) => (v as num).toInt()),
        y: $checkedConvert('y', (v) => (v as num).toInt()),
        width: $checkedConvert('width', (v) => (v as num).toInt()),
        height: $checkedConvert('height', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$DetectionBoxToJson(DetectionBox instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
    };

DetectionProposal _$DetectionProposalFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DetectionProposal', json, ($checkedConvert) {
      final val = DetectionProposal(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        category: $checkedConvert('category', (v) => v as String),
        colors: $checkedConvert(
          'colors',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
        boundingBox: $checkedConvert(
          'boundingBox',
          (v) => DetectionBox.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$DetectionProposalToJson(DetectionProposal instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': instance.category,
      'colors': instance.colors,
      'boundingBox': instance.boundingBox.toJson(),
    };

IntakeChoice _$IntakeChoiceFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('IntakeChoice', json, ($checkedConvert) {
  final val = IntakeChoice(
    itemKey: $checkedConvert('itemKey', (v) => v as String),
    generationKey: $checkedConvert('generationKey', (v) => v as String),
    proposal: $checkedConvert(
      'proposal',
      (v) => v == null
          ? null
          : DetectionProposal.fromJson(v as Map<String, dynamic>),
    ),
    metadata: $checkedConvert(
      'metadata',
      (v) =>
          v == null ? null : ItemMetadata.fromJson(v as Map<String, dynamic>),
    ),
    selected: $checkedConvert('selected', (v) => v as bool? ?? true),
    ownership: $checkedConvert('ownership', (v) => v as String? ?? 'owning'),
    itemId: $checkedConvert('itemId', (v) => v as String?),
    enqueued: $checkedConvert('enqueued', (v) => v as bool? ?? false),
    command: $checkedConvert('command', (v) => v as Map<String, dynamic>?),
  );
  return val;
});

Map<String, dynamic> _$IntakeChoiceToJson(IntakeChoice instance) =>
    <String, dynamic>{
      'itemKey': instance.itemKey,
      'generationKey': instance.generationKey,
      'proposal': instance.proposal?.toJson(),
      'metadata': instance.metadata?.toJson(),
      'selected': instance.selected,
      'ownership': instance.ownership,
      'itemId': instance.itemId,
      'enqueued': instance.enqueued,
      'command': instance.command,
    };

IntakeDraft _$IntakeDraftFromJson(Map<String, dynamic> json) => $checkedCreate(
  'IntakeDraft',
  json,
  ($checkedConvert) {
    final val = IntakeDraft(
      id: $checkedConvert('id', (v) => v as String),
      filePath: $checkedConvert('filePath', (v) => v as String),
      width: $checkedConvert('width', (v) => (v as num).toInt()),
      height: $checkedConvert('height', (v) => (v as num).toInt()),
      completionKey: $checkedConvert('completionKey', (v) => v as String),
      detectionKey: $checkedConvert('detectionKey', (v) => v as String),
      phase: $checkedConvert(
        'phase',
        (v) => $enumDecodeNullable(_$DraftPhaseEnumMap, v) ?? DraftPhase.local,
      ),
      sourceId: $checkedConvert('sourceId', (v) => v as String?),
      intent: $checkedConvert('intent', (v) => v as Map<String, dynamic>?),
      failure: $checkedConvert('failure', (v) => v as String?),
      ownership: $checkedConvert('ownership', (v) => v as String? ?? 'owning'),
      quality: $checkedConvert('quality', (v) => v as String? ?? 'low'),
      choices: $checkedConvert(
        'choices',
        (v) => (v as List<dynamic>?)
            ?.map((e) => IntakeChoice.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
    return val;
  },
);

Map<String, dynamic> _$IntakeDraftToJson(IntakeDraft instance) =>
    <String, dynamic>{
      'id': instance.id,
      'filePath': instance.filePath,
      'width': instance.width,
      'height': instance.height,
      'completionKey': instance.completionKey,
      'detectionKey': instance.detectionKey,
      'phase': _$DraftPhaseEnumMap[instance.phase]!,
      'sourceId': instance.sourceId,
      'intent': instance.intent,
      'failure': instance.failure,
      'ownership': instance.ownership,
      'quality': instance.quality,
      'choices': instance.choices.map((e) => e.toJson()).toList(),
    };

const _$DraftPhaseEnumMap = {
  DraftPhase.local: 'local',
  DraftPhase.uploading: 'uploading',
  DraftPhase.uploaded: 'uploaded',
  DraftPhase.detecting: 'detecting',
  DraftPhase.ready: 'ready',
  DraftPhase.manual: 'manual',
  DraftPhase.saving: 'saving',
  DraftPhase.finished: 'finished',
  DraftPhase.discarded: 'discarded',
};
