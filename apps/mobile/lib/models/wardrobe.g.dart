// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wardrobe.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ItemMetadata _$ItemMetadataFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ItemMetadata', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['name', 'category', 'colors', 'notes'],
      );
      final val = ItemMetadata(
        name: $checkedConvert('name', (v) => v as String),
        category: $checkedConvert('category', (v) => v as String),
        colors: $checkedConvert(
          'colors',
          (v) => (v as List<dynamic>).map((e) => e as String).toList(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ItemMetadataToJson(ItemMetadata instance) =>
    <String, dynamic>{
      'name': instance.name,
      'category': instance.category,
      'colors': instance.colors,
      'notes': instance.notes,
    };

WardrobeItem _$WardrobeItemFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('WardrobeItem', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'sourcePhotoId',
      'state',
      'status',
      'metadata',
      'currentShelfImageVersionId',
      'recordVersion',
      'createdAt',
      'updatedAt',
    ],
  );
  final val = WardrobeItem(
    id: $checkedConvert('id', (v) => v as String),
    sourcePhotoId: $checkedConvert('sourcePhotoId', (v) => v as String),
    state: $checkedConvert('state', (v) => v as String),
    status: $checkedConvert('status', (v) => v as String),
    metadata: $checkedConvert(
      'metadata',
      (v) => ItemMetadata.fromJson(v as Map<String, dynamic>),
    ),
    currentShelfImageVersionId: $checkedConvert(
      'currentShelfImageVersionId',
      (v) => v as String?,
    ),
    recordVersion: $checkedConvert('recordVersion', (v) => (v as num).toInt()),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    updatedAt: $checkedConvert('updatedAt', (v) => DateTime.parse(v as String)),
  );
  return val;
});

Map<String, dynamic> _$WardrobeItemToJson(WardrobeItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sourcePhotoId': instance.sourcePhotoId,
      'state': instance.state,
      'status': instance.status,
      'metadata': instance.metadata.toJson(),
      'currentShelfImageVersionId': instance.currentShelfImageVersionId,
      'recordVersion': instance.recordVersion,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };

SourcePhoto _$SourcePhotoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SourcePhoto', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['id', 'assetId', 'createdAt']);
      final val = SourcePhoto(
        id: $checkedConvert('id', (v) => v as String),
        assetId: $checkedConvert('assetId', (v) => v as String),
        createdAt: $checkedConvert(
          'createdAt',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$SourcePhotoToJson(SourcePhoto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'assetId': instance.assetId,
      'createdAt': instance.createdAt.toIso8601String(),
    };

ShelfImageVersion _$ShelfImageVersionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ShelfImageVersion', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'id',
          'wardrobeItemId',
          'generationAttemptId',
          'keyedAssetId',
          'transparentAssetId',
          'quality',
          'size',
          'promptVersion',
          'keptAt',
        ],
      );
      final val = ShelfImageVersion(
        id: $checkedConvert('id', (v) => v as String),
        wardrobeItemId: $checkedConvert('wardrobeItemId', (v) => v as String),
        generationAttemptId: $checkedConvert(
          'generationAttemptId',
          (v) => v as String,
        ),
        keyedAssetId: $checkedConvert('keyedAssetId', (v) => v as String),
        transparentAssetId: $checkedConvert(
          'transparentAssetId',
          (v) => v as String,
        ),
        quality: $checkedConvert('quality', (v) => v as String),
        size: $checkedConvert('size', (v) => v as String),
        promptVersion: $checkedConvert('promptVersion', (v) => v as String),
        keptAt: $checkedConvert('keptAt', (v) => DateTime.parse(v as String)),
      );
      return val;
    });

Map<String, dynamic> _$ShelfImageVersionToJson(ShelfImageVersion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'wardrobeItemId': instance.wardrobeItemId,
      'generationAttemptId': instance.generationAttemptId,
      'keyedAssetId': instance.keyedAssetId,
      'transparentAssetId': instance.transparentAssetId,
      'quality': instance.quality,
      'size': instance.size,
      'promptVersion': instance.promptVersion,
      'keptAt': instance.keptAt.toIso8601String(),
    };

GenerationAttempt _$GenerationAttemptFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GenerationAttempt', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'wardrobeItemId',
      'sourcePhotoId',
      'detectionProposalId',
      'state',
      'reviewedMetadata',
      'model',
      'quality',
      'size',
      'promptVersion',
      'parentShelfImageVersionId',
      'feedback',
      'keyedAssetId',
      'transparentAssetId',
      'providerRequestId',
      'costMicrounits',
      'usage',
      'costBreakdown',
      'failureCategory',
      'createdAt',
      'finishedAt',
    ],
  );
  final val = GenerationAttempt(
    id: $checkedConvert('id', (v) => v as String),
    wardrobeItemId: $checkedConvert('wardrobeItemId', (v) => v as String),
    sourcePhotoId: $checkedConvert('sourcePhotoId', (v) => v as String),
    detectionProposalId: $checkedConvert(
      'detectionProposalId',
      (v) => v as String?,
    ),
    state: $checkedConvert('state', (v) => v as String),
    reviewedMetadata: $checkedConvert(
      'reviewedMetadata',
      (v) => ItemMetadata.fromJson(v as Map<String, dynamic>),
    ),
    model: $checkedConvert('model', (v) => v as String),
    quality: $checkedConvert('quality', (v) => v as String),
    size: $checkedConvert('size', (v) => v as String),
    promptVersion: $checkedConvert('promptVersion', (v) => v as String),
    parentShelfImageVersionId: $checkedConvert(
      'parentShelfImageVersionId',
      (v) => v as String?,
    ),
    feedback: $checkedConvert('feedback', (v) => v as String?),
    keyedAssetId: $checkedConvert('keyedAssetId', (v) => v as String?),
    transparentAssetId: $checkedConvert(
      'transparentAssetId',
      (v) => v as String?,
    ),
    providerRequestId: $checkedConvert(
      'providerRequestId',
      (v) => v as String?,
    ),
    costMicrounits: $checkedConvert(
      'costMicrounits',
      (v) => (v as num?)?.toInt(),
    ),
    usage: $checkedConvert('usage', (v) => v as Map<String, dynamic>?),
    costBreakdown: $checkedConvert(
      'costBreakdown',
      (v) => v as Map<String, dynamic>?,
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

Map<String, dynamic> _$GenerationAttemptToJson(GenerationAttempt instance) =>
    <String, dynamic>{
      'id': instance.id,
      'wardrobeItemId': instance.wardrobeItemId,
      'sourcePhotoId': instance.sourcePhotoId,
      'detectionProposalId': instance.detectionProposalId,
      'state': instance.state,
      'reviewedMetadata': instance.reviewedMetadata.toJson(),
      'model': instance.model,
      'quality': instance.quality,
      'size': instance.size,
      'promptVersion': instance.promptVersion,
      'parentShelfImageVersionId': instance.parentShelfImageVersionId,
      'feedback': instance.feedback,
      'keyedAssetId': instance.keyedAssetId,
      'transparentAssetId': instance.transparentAssetId,
      'providerRequestId': instance.providerRequestId,
      'costMicrounits': instance.costMicrounits,
      'usage': instance.usage,
      'costBreakdown': instance.costBreakdown,
      'failureCategory': instance.failureCategory,
      'createdAt': instance.createdAt.toIso8601String(),
      'finishedAt': instance.finishedAt?.toIso8601String(),
    };

ItemDetail _$ItemDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ItemDetail', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const [
          'wardrobeItem',
          'sourcePhoto',
          'shelfImageVersions',
          'generationAttempts',
        ],
      );
      final val = ItemDetail(
        wardrobeItem: $checkedConvert(
          'wardrobeItem',
          (v) => WardrobeItem.fromJson(v as Map<String, dynamic>),
        ),
        sourcePhoto: $checkedConvert(
          'sourcePhoto',
          (v) => SourcePhoto.fromJson(v as Map<String, dynamic>),
        ),
        shelfImageVersions: $checkedConvert(
          'shelfImageVersions',
          (v) => (v as List<dynamic>)
              .map((e) => ShelfImageVersion.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        generationAttempts: $checkedConvert(
          'generationAttempts',
          (v) => (v as List<dynamic>)
              .map((e) => GenerationAttempt.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ItemDetailToJson(ItemDetail instance) =>
    <String, dynamic>{
      'wardrobeItem': instance.wardrobeItem.toJson(),
      'sourcePhoto': instance.sourcePhoto.toJson(),
      'shelfImageVersions': instance.shelfImageVersions
          .map((e) => e.toJson())
          .toList(),
      'generationAttempts': instance.generationAttempts
          .map((e) => e.toJson())
          .toList(),
    };
