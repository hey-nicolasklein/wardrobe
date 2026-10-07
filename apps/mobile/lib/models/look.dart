import 'package:json_annotation/json_annotation.dart';

part 'look.g.dart';

const lookStates = [
  'queued',
  'planning',
  'proposed',
  'generating',
  'ready',
  'failed',
];
const lookOccasions = ['night-out', 'party', 'business', 'casual'];

/// What a look is made of. Every look is a combination of pieces; a `photo`
/// look adds a real photo the user wore it in, `try-on` and `inspiration` an
/// AI image.
const lookKinds = ['combination', 'photo', 'inspiration', 'try-on'];

/// A piece detected on a photo look. [wardrobeItemId] is set once it was
/// added to the wardrobe.
@JsonSerializable(checked: true, includeIfNull: false)
class LookFoundPiece {
  const LookFoundPiece({
    required this.id,
    required this.name,
    required this.category,
    required this.colors,
    this.boundingBox,
    this.wardrobeItemId,
    this.added = false,
  });

  factory LookFoundPiece.fromJson(Map<String, dynamic> json) =>
      _$LookFoundPieceFromJson(json);

  @JsonKey(required: true)
  final String id;
  @JsonKey(required: true)
  final String name;
  @JsonKey(required: true)
  final String category;
  @JsonKey(defaultValue: <String>[])
  final List<String> colors;

  /// Where the piece sits on the photo, in its 0–1000 frame.
  final LookBox? boundingBox;

  /// The wardrobe piece the user said this is, on this look.
  final String? wardrobeItemId;

  /// The linked piece was created from this one, so it can be taken out of
  /// the wardrobe again from here.
  @JsonKey(defaultValue: false)
  final bool added;

  Map<String, dynamic> toJson() => _$LookFoundPieceToJson(this);
}

/// Output sizes the server has produced. Feed images moved to 768x960; older
/// looks keep 1024x1280.
/// What background analysis found about a photo look's photo as a whole.
@JsonSerializable(checked: true, explicitToJson: true)
class LookPhoto {
  const LookPhoto({required this.source, this.outfitBox});

  factory LookPhoto.fromJson(Map<String, dynamic> json) =>
      _$LookPhotoFromJson(json);

  /// `personal` for a photo of the user, `reference` for someone else's,
  /// such as a shop screenshot or street style.
  @JsonKey(required: true)
  final String source;

  /// The outfit as a whole, in the 0–1000 frame of the photo. Cards crop to
  /// it so prices and app controls on screenshots stay out.
  @JsonKey(includeIfNull: false)
  final LookBox? outfitBox;

  bool get isReference => source == 'reference';

  Map<String, dynamic> toJson() => _$LookPhotoToJson(this);
}

/// A box in the photo's normalised 0–1000 frame.
@JsonSerializable(checked: true)
class LookBox {
  const LookBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory LookBox.fromJson(Map<String, dynamic> json) =>
      _$LookBoxFromJson(json);

  final int x;
  final int y;
  final int width;
  final int height;

  Map<String, dynamic> toJson() => _$LookBoxToJson(this);
}

const lookSizes = ['1024x1280', '768x960'];

/// Why a proposal was suggested. [kind] is one of `new-piece`,
/// `never-styled`, `rarely-styled` (with [itemId]), `your-pick` (with
/// [itemIds]), `occasion` (with [occasion]) or `fresh`. Unknown kinds are
/// skipped by the UI.
@JsonSerializable(checked: true, includeIfNull: false)
class LookReason {
  const LookReason({
    required this.kind,
    this.itemId,
    this.itemIds = const [],
    this.occasion,
  });

  factory LookReason.fromJson(Map<String, dynamic> json) =>
      _$LookReasonFromJson(json);

  @JsonKey(required: true)
  final String kind;
  final String? itemId;
  @JsonKey(defaultValue: <String>[])
  final List<String> itemIds;
  final String? occasion;

  Map<String, dynamic> toJson() => _$LookReasonToJson(this);
}

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
    this.kind = 'inspiration',
    this.sourcePhotoId,
    this.found,
    this.photo,
    this.baseAssetId,
    this.feedAssetId,
    this.settings,
    this.liked = false,
    this.reasons,
  });

  factory Look.fromJson(Map<String, dynamic> json) {
    final value = _$LookFromJson(json);
    if (value.id.isEmpty ||
        !lookKinds.contains(value.kind) ||
        !lookStates.contains(value.state) ||
        !lookSizes.contains(value.size) ||
        !['low', 'medium', 'high'].contains(value.quality)) {
      throw const FormatException('Invalid look');
    }
    return value;
  }

  @JsonKey(required: true)
  final String id;

  /// One of [lookKinds]. Looks cached before kinds existed were all
  /// generated; [Look.fromJson] callers normalise them, see
  /// `normalizeLookJson`.
  @JsonKey(defaultValue: 'inspiration')
  final String kind;
  @JsonKey(required: true)
  final String state;
  @JsonKey(required: true)
  final String? assetId;

  /// The photo a photo look was uploaded as.
  @JsonKey(includeIfNull: false)
  final String? sourcePhotoId;

  /// The pieces detected on a photo look. Null while it is still analysed
  /// and for every other kind.
  @JsonKey(includeIfNull: false)
  final List<LookFoundPiece>? found;

  /// Photo looks, once analysed: whose photo it is and where the outfit is.
  @JsonKey(includeIfNull: false)
  final LookPhoto? photo;

  /// A photo of someone else: its new pieces go to Wanting.
  bool get isReference => photo?.isReference ?? false;

  /// A smaller WebP of [assetId] for cards. Missing on looks cached before
  /// the API sent it.
  @JsonKey(includeIfNull: false)
  final String? feedAssetId;
  @JsonKey(required: true)
  final List<String> wardrobeItemIds;

  /// Only inspirations are made from a character sheet.
  @JsonKey(required: true)
  final String? characterSheetId;
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
  bool get isTryOn => kind == 'try-on' || baseAssetId != null;

  /// Saved pieces without an image of its own: shown laid out flat.
  bool get isCombination => kind == 'combination';
  bool get isPhoto => kind == 'photo';

  /// Made of the user's own pieces, so AI images can be put on top of it.
  bool get isBase => isCombination || isPhoto;

  /// Made by the image model, so it can fail, be retried or upgraded.
  bool get isGenerated => kind == 'inspiration' || kind == 'try-on';

  /// A photo look whose pieces are still being detected.
  bool get isAnalysing => isPhoto && found == null;

  /// The composer choices behind this look. Null for try-ons, unknown
  /// requests, and looks cached before settings were reported.
  @JsonKey(includeIfNull: false)
  final LookSettings? settings;

  /// Hearted by the user. Stored on the server, where hearts weight the shot
  /// types of future looks. Absent in looks cached before that.
  @JsonKey(defaultValue: false)
  final bool liked;

  /// Why a proposal was suggested. Null for every other look.
  @JsonKey(includeIfNull: false)
  final List<LookReason>? reasons;

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
