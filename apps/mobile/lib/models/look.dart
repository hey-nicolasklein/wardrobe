import 'package:json_annotation/json_annotation.dart';

part 'look.g.dart';

const lookStates = ['queued', 'planning', 'generating', 'ready', 'failed'];
const lookOccasions = ['night-out', 'party', 'business', 'casual'];

/// Output sizes the server has produced. Feed images moved to 768x960; older
/// looks keep 1024x1280.
const lookSizes = ['1024x1280', '768x960'];

@JsonSerializable(checked: true, explicitToJson: true)
class LookConcept {
  const LookConcept({
    required this.activity,
    required this.scene,
    required this.framing,
    required this.mood,
    this.shot,
  });

  factory LookConcept.fromJson(Map<String, dynamic> json) {
    final value = _$LookConceptFromJson(json);
    if (!['full-body', 'three-quarter'].contains(value.framing)) {
      throw const FormatException('Invalid framing');
    }
    return value;
  }

  @JsonKey(required: true)
  final String activity;
  @JsonKey(required: true)
  final String scene;
  @JsonKey(required: true)
  final String framing;
  @JsonKey(required: true)
  final String mood;

  /// The camera setup the planner picked, e.g. `street-low-wide`. Null for
  /// looks planned before shot types existed.
  @JsonKey(includeIfNull: false)
  final String? shot;

  Map<String, dynamic> toJson() => _$LookConceptToJson(this);
}

/// How an inspiration look was requested, as the composer offered it.
@JsonSerializable(checked: true, explicitToJson: true)
class LookSettings {
  const LookSettings({
    required this.occasion,
    required this.style,
    required this.completion,
    required this.categories,
  });

  factory LookSettings.fromJson(Map<String, dynamic> json) =>
      _$LookSettingsFromJson(json);

  @JsonKey(required: true)
  final String? occasion;
  @JsonKey(required: true)
  final String style;
  @JsonKey(required: true)
  final String completion;
  @JsonKey(required: true)
  final List<String> categories;

  Map<String, dynamic> toJson() => _$LookSettingsToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class Look {
  const Look({
    required this.id,
    required this.state,
    required this.assetId,
    required this.wardrobeItemIds,
    required this.characterSheetId,
    required this.parentLookId,
    required this.concept,
    required this.model,
    required this.quality,
    required this.size,
    required this.providerRequestId,
    required this.costMicrounits,
    required this.failureCategory,
    required this.createdAt,
    required this.finishedAt,
    this.baseAssetId,
    this.feedAssetId,
    this.settings,
    this.liked = false,
  });

  factory Look.fromJson(Map<String, dynamic> json) {
    final value = _$LookFromJson(json);
    if (value.id.isEmpty ||
        !lookStates.contains(value.state) ||
        !lookSizes.contains(value.size) ||
        !['low', 'medium', 'high'].contains(value.quality)) {
      throw const FormatException('Invalid look');
    }
    return value;
  }

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String state;
  @JsonKey(required: true)
  final String? assetId;

  /// A smaller WebP of [assetId] for cards. Missing on looks cached before
  /// the API sent it.
  @JsonKey(includeIfNull: false)
  final String? feedAssetId;
  @JsonKey(required: true)
  final List<String> wardrobeItemIds;
  @JsonKey(required: true)
  final String characterSheetId;
  @JsonKey(required: true)
  final String? parentLookId;
  @JsonKey(required: true)
  final LookConcept? concept;
  @JsonKey(required: true)
  final String model;
  @JsonKey(required: true)
  final String quality;
  @JsonKey(required: true)
  final String size;
  @JsonKey(required: true)
  final String? providerRequestId;
  @JsonKey(required: true)
  final int? costMicrounits;
  @JsonKey(required: true)
  final String? failureCategory;
  @JsonKey(required: true)
  final DateTime createdAt;
  @JsonKey(required: true)
  final DateTime? finishedAt;

  /// The user's own photo a try-on was made from. Null for inspiration looks
  /// and for looks cached before try-ons existed.
  @JsonKey(includeIfNull: false)
  final String? baseAssetId;
  bool get isTryOn => baseAssetId != null;

  /// The composer choices behind this look. Null for try-ons, unknown
  /// requests, and looks cached before settings were reported.
  @JsonKey(includeIfNull: false)
  final LookSettings? settings;

  /// Hearted by the user. Stored on the server, where hearts weight the shot
  /// types of future looks. Absent in looks cached before that.
  @JsonKey(defaultValue: false)
  final bool liked;

  bool get isReady => state == 'ready';
  bool get isActive => ['queued', 'planning', 'generating'].contains(state);

  String? get cardAssetId => feedAssetId ?? assetId;

  Map<String, dynamic> toJson() => _$LookToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class CharacterSheet {
  const CharacterSheet({
    required this.id,
    required this.state,
    required this.referenceAssetIds,
    required this.note,
    required this.assetId,
    required this.active,
    required this.model,
    required this.quality,
    required this.size,
    required this.providerRequestId,
    required this.costMicrounits,
    required this.failureCategory,
    required this.createdAt,
    required this.finishedAt,
  });

  factory CharacterSheet.fromJson(Map<String, dynamic> json) {
    final value = _$CharacterSheetFromJson(json);
    if (value.id.isEmpty ||
        !['queued', 'processing', 'ready', 'failed'].contains(value.state) ||
        value.quality != 'high' ||
        value.size != '864x1536' ||
        value.referenceAssetIds.isEmpty ||
        value.referenceAssetIds.length > 4 ||
        value.referenceAssetIds.any((id) => id.isEmpty) ||
        (value.note?.length ?? 0) > 1000 ||
        (value.costMicrounits ?? 0) < 0) {
      throw const FormatException('Invalid character sheet');
    }
    return value;
  }

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String state;
  @JsonKey(required: true)
  final List<String> referenceAssetIds;
  @JsonKey(required: true)
  final String? note;
  @JsonKey(required: true)
  final String? assetId;
  @JsonKey(required: true)
  final bool active;
  @JsonKey(required: true)
  final String model;
  @JsonKey(required: true)
  final String quality;
  @JsonKey(required: true)
  final String size;
  @JsonKey(required: true)
  final String? providerRequestId;
  @JsonKey(required: true)
  final int? costMicrounits;
  @JsonKey(required: true)
  final String? failureCategory;
  @JsonKey(required: true)
  final DateTime createdAt;
  @JsonKey(required: true)
  final DateTime? finishedAt;

  bool get isActiveReady => active && state == 'ready';
  bool get isPending => state == 'queued' || state == 'processing';
  bool get canActivate => !active && state == 'ready';
  bool get canReplace => state == 'ready' && assetId != null;
  bool get canDelete => !active && (state == 'ready' || state == 'failed');

  Map<String, dynamic> toJson() => _$CharacterSheetToJson(this);
}
