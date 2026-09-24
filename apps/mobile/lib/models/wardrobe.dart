import 'package:form_mobile/utils/immutable_json.dart';
import 'package:json_annotation/json_annotation.dart';

part 'wardrobe.g.dart';

const categories = [
  'top',
  'jacket',
  'pants',
  'skirt',
  'dress',
  'shoes',
  'bag',
  'hat',
  'scarf',
];
const itemStates = ['owning', 'wanting', 'archived'];
const itemStatuses = [
  'detecting',
  'reviewing-metadata',
  'queued',
  'generating',
  'needs-review',
  'ready',
  'failed',
];
const qualities = ['low', 'medium', 'high'];

@JsonSerializable(checked: true, explicitToJson: true)
class ItemMetadata {
  ItemMetadata({
    required this.name,
    required this.category,
    required List<String> colors,
    required this.notes,
  }) : colors = List.unmodifiable(colors);

  factory ItemMetadata.fromJson(Map<String, dynamic> json) {
    final value = _$ItemMetadataFromJson(json);
    if (!validName(value.name) ||
        !categories.contains(value.category) ||
        !validColors(value.colors) ||
        (value.notes?.length ?? 0) > 2000) {
      throw const FormatException('Invalid metadata');
    }
    return value;
  }

  @JsonKey(required: true)
  final String name;
  @JsonKey(required: true)
  final String category;
  @JsonKey(required: true)
  final List<String> colors;
  @JsonKey(required: true)
  final String? notes;

  static bool validName(String value) =>
      value.trim().isNotEmpty && value.length <= 80;
  static bool validColors(List<String> colors) =>
      colors.isNotEmpty &&
      colors.length <= 6 &&
      colors.every((c) => c.trim().isNotEmpty && c.length <= 32);
  Map<String, dynamic> toJson() => _$ItemMetadataToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.sourcePhotoId,
    required this.state,
    required this.status,
    required this.metadata,
    required this.currentShelfImageVersionId,
    required this.recordVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WardrobeItem.fromJson(Map<String, dynamic> json) {
    final value = _$WardrobeItemFromJson(json);
    if (value.id.isEmpty ||
        value.sourcePhotoId.isEmpty ||
        value.recordVersion < 0 ||
        !itemStates.contains(value.state) ||
        !itemStatuses.contains(value.status)) {
      throw const FormatException('Invalid item');
    }
    return value;
  }

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String sourcePhotoId;
  @JsonKey(required: true)
  final String state;
  @JsonKey(required: true)
  final String status;
  @JsonKey(required: true)
  final ItemMetadata metadata;
  @JsonKey(required: true)
  final String? currentShelfImageVersionId;
  @JsonKey(required: true)
  final int recordVersion;
  @JsonKey(required: true)
  final DateTime createdAt;
  @JsonKey(required: true)
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => _$WardrobeItemToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class SourcePhoto {
  const SourcePhoto({
    required this.id,
    required this.assetId,
    required this.createdAt,
  });

  factory SourcePhoto.fromJson(Map<String, dynamic> json) {
    final value = _$SourcePhotoFromJson(json);
    return value;
  }

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String assetId;
  @JsonKey(required: true)
  final DateTime createdAt;

  Map<String, dynamic> toJson() => _$SourcePhotoToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class ShelfImageVersion {
  const ShelfImageVersion({
    required this.id,
    required this.wardrobeItemId,
    required this.generationAttemptId,
    required this.keyedAssetId,
    required this.transparentAssetId,
    required this.quality,
    required this.size,
    required this.promptVersion,
    required this.keptAt,
  });

  factory ShelfImageVersion.fromJson(Map<String, dynamic> json) {
    final value = _$ShelfImageVersionFromJson(json);
    if (!qualities.contains(value.quality) || value.size != '816x816') {
      throw const FormatException('Invalid generation');
    }
    return value;
  }

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String wardrobeItemId;
  @JsonKey(required: true)
  final String generationAttemptId;
  @JsonKey(required: true)
  final String keyedAssetId;
  @JsonKey(required: true)
  final String transparentAssetId;
  @JsonKey(required: true)
  final String quality;
  @JsonKey(required: true)
  final String size;
  @JsonKey(required: true)
  final String promptVersion;
  @JsonKey(required: true)
  final DateTime keptAt;

  Map<String, dynamic> toJson() => _$ShelfImageVersionToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class GenerationAttempt {
  GenerationAttempt({
    required this.id,
    required this.wardrobeItemId,
    required this.sourcePhotoId,
    required this.detectionProposalId,
    required this.state,
    required this.reviewedMetadata,
    required this.model,
    required this.quality,
    required this.size,
    required this.promptVersion,
    required this.parentShelfImageVersionId,
    required this.feedback,
    required this.keyedAssetId,
    required this.transparentAssetId,
    required this.providerRequestId,
    required this.costMicrounits,
    required Map<String, dynamic>? usage,
    required Map<String, dynamic>? costBreakdown,
    required this.failureCategory,
    required this.createdAt,
    required this.finishedAt,
  }) : usage = usage == null ? null : immutableJson(usage),
       costBreakdown = costBreakdown == null
           ? null
           : immutableJson(costBreakdown);

  factory GenerationAttempt.fromJson(Map<String, dynamic> json) {
    final value = _$GenerationAttemptFromJson(json);
    if (!qualities.contains(value.quality) || value.size != '816x816') {
      throw const FormatException('Invalid generation');
    }
    if (![
      'queued',
      'processing',
      'needs-review',
      'kept',
      'rejected',
      'failed',
    ].contains(value.state)) {
      throw const FormatException('Invalid generation state');
    }
    return value;
  }

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String wardrobeItemId;
  @JsonKey(required: true)
  final String sourcePhotoId;
  @JsonKey(required: true)
  final String? detectionProposalId;
  @JsonKey(required: true)
  final String state;
  @JsonKey(required: true)
  final ItemMetadata reviewedMetadata;
  @JsonKey(required: true)
  final String model;
  @JsonKey(required: true)
  final String quality;
  @JsonKey(required: true)
  final String size;
  @JsonKey(required: true)
  final String promptVersion;
  @JsonKey(required: true)
  final String? parentShelfImageVersionId;
  @JsonKey(required: true)
  final String? feedback;
  @JsonKey(required: true)
  final String? keyedAssetId;
  @JsonKey(required: true)
  final String? transparentAssetId;
  @JsonKey(required: true)
  final String? providerRequestId;
  @JsonKey(required: true)
  final int? costMicrounits;
  @JsonKey(required: true)
  final Map<String, dynamic>? usage;
  @JsonKey(required: true)
  final Map<String, dynamic>? costBreakdown;
  @JsonKey(required: true)
  final String? failureCategory;
  @JsonKey(required: true)
  final DateTime createdAt;
  @JsonKey(required: true)
  final DateTime? finishedAt;

  Map<String, dynamic> toJson() => _$GenerationAttemptToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class ItemDetail {
  ItemDetail({
    required this.wardrobeItem,
    required this.sourcePhoto,
    required List<ShelfImageVersion> shelfImageVersions,
    required List<GenerationAttempt> generationAttempts,
  }) : shelfImageVersions = List.unmodifiable(shelfImageVersions),
       generationAttempts = List.unmodifiable(generationAttempts);

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    final value = _$ItemDetailFromJson(json);
    return value;
  }

  @JsonKey(required: true)
  final WardrobeItem wardrobeItem;
  @JsonKey(required: true)
  final SourcePhoto sourcePhoto;
  @JsonKey(required: true)
  final List<ShelfImageVersion> shelfImageVersions;
  @JsonKey(required: true)
  final List<GenerationAttempt> generationAttempts;

  Map<String, dynamic> toJson() => _$ItemDetailToJson(this);

  ShelfImageVersion? get currentImage => shelfImageVersions
      .where((v) => v.id == wardrobeItem.currentShelfImageVersionId)
      .firstOrNull;
  bool get generating => generationAttempts.any(
    (a) => a.state == 'queued' || a.state == 'processing',
  );
}
