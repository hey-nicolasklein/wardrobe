// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'look.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LookConcept _$LookConceptFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LookConcept', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['activity', 'scene', 'framing', 'mood'],
      );
      final val = LookConcept(
        activity: $checkedConvert('activity', (v) => v as String),
        scene: $checkedConvert('scene', (v) => v as String),
        framing: $checkedConvert('framing', (v) => v as String),
        mood: $checkedConvert('mood', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$LookConceptToJson(LookConcept instance) =>
    <String, dynamic>{
      'activity': instance.activity,
      'scene': instance.scene,
      'framing': instance.framing,
      'mood': instance.mood,
    };

Look _$LookFromJson(Map<String, dynamic> json) => $checkedCreate('Look', json, (
  $checkedConvert,
) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'state',
      'assetId',
      'wardrobeItemIds',
      'characterSheetId',
      'parentLookId',
      'concept',
      'model',
      'quality',
      'size',
      'providerRequestId',
      'costMicrounits',
      'failureCategory',
      'createdAt',
      'finishedAt',
    ],
  );
  final val = Look(
    id: $checkedConvert('id', (v) => v as String),
    state: $checkedConvert('state', (v) => v as String),
    assetId: $checkedConvert('assetId', (v) => v as String?),
    wardrobeItemIds: $checkedConvert(
      'wardrobeItemIds',
      (v) => (v as List<dynamic>).map((e) => e as String).toList(),
    ),
    characterSheetId: $checkedConvert('characterSheetId', (v) => v as String),
    parentLookId: $checkedConvert('parentLookId', (v) => v as String?),
    concept: $checkedConvert(
      'concept',
      (v) => v == null ? null : LookConcept.fromJson(v as Map<String, dynamic>),
    ),
    model: $checkedConvert('model', (v) => v as String),
    quality: $checkedConvert('quality', (v) => v as String),
    size: $checkedConvert('size', (v) => v as String),
    providerRequestId: $checkedConvert(
      'providerRequestId',
      (v) => v as String?,
    ),
    costMicrounits: $checkedConvert(
      'costMicrounits',
      (v) => (v as num?)?.toInt(),
    ),
    failureCategory: $checkedConvert('failureCategory', (v) => v as String?),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    finishedAt: $checkedConvert(
      'finishedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
  );
  return val;
});

Map<String, dynamic> _$LookToJson(Look instance) => <String, dynamic>{
  'id': instance.id,
  'state': instance.state,
  'assetId': instance.assetId,
  'wardrobeItemIds': instance.wardrobeItemIds,
  'characterSheetId': instance.characterSheetId,
  'parentLookId': instance.parentLookId,
  'concept': instance.concept?.toJson(),
  'model': instance.model,
  'quality': instance.quality,
  'size': instance.size,
  'providerRequestId': instance.providerRequestId,
  'costMicrounits': instance.costMicrounits,
  'failureCategory': instance.failureCategory,
  'createdAt': instance.createdAt.toIso8601String(),
  'finishedAt': instance.finishedAt?.toIso8601String(),
};

CharacterSheet _$CharacterSheetFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CharacterSheet', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'state',
      'referenceAssetIds',
      'note',
      'assetId',
      'active',
      'model',
      'quality',
      'size',
      'providerRequestId',
      'costMicrounits',
      'failureCategory',
      'createdAt',
      'finishedAt',
    ],
  );
  final val = CharacterSheet(
    id: $checkedConvert('id', (v) => v as String),
    state: $checkedConvert('state', (v) => v as String),
    referenceAssetIds: $checkedConvert(
      'referenceAssetIds',
      (v) => (v as List<dynamic>).map((e) => e as String).toList(),
    ),
    note: $checkedConvert('note', (v) => v as String?),
    assetId: $checkedConvert('assetId', (v) => v as String?),
    active: $checkedConvert('active', (v) => v as bool),
    model: $checkedConvert('model', (v) => v as String),
    quality: $checkedConvert('quality', (v) => v as String),
    size: $checkedConvert('size', (v) => v as String),
    providerRequestId: $checkedConvert(
      'providerRequestId',
      (v) => v as String?,
    ),
    costMicrounits: $checkedConvert(
      'costMicrounits',
      (v) => (v as num?)?.toInt(),
    ),
    failureCategory: $checkedConvert('failureCategory', (v) => v as String?),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    finishedAt: $checkedConvert(
      'finishedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
  );
  return val;
});

Map<String, dynamic> _$CharacterSheetToJson(CharacterSheet instance) =>
    <String, dynamic>{
      'id': instance.id,
      'state': instance.state,
      'referenceAssetIds': instance.referenceAssetIds,
      'note': instance.note,
      'assetId': instance.assetId,
      'active': instance.active,
      'model': instance.model,
      'quality': instance.quality,
      'size': instance.size,
      'providerRequestId': instance.providerRequestId,
      'costMicrounits': instance.costMicrounits,
      'failureCategory': instance.failureCategory,
      'createdAt': instance.createdAt.toIso8601String(),
      'finishedAt': instance.finishedAt?.toIso8601String(),
    };
