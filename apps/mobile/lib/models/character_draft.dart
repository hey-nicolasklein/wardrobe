import 'package:form_mobile/features/settings/character/collage_geometry.dart';
import 'package:json_annotation/json_annotation.dart';

part 'character_draft.g.dart';

@JsonSerializable(explicitToJson: true)
class CharacterPhoto {
  CharacterPhoto({
    required this.path,
    required this.width,
    required this.height,
    this.crop = const PhotoCrop(),
  });
  factory CharacterPhoto.fromJson(Map<String, dynamic> json) =>
      _$CharacterPhotoFromJson(json);
  final String path;
  final int width;
  final int height;
  PhotoCrop crop;
  Map<String, dynamic> toJson() => _$CharacterPhotoToJson(this);
}

@JsonSerializable(explicitToJson: true)
class CharacterDraft {
  CharacterDraft({
    required this.id,
    required this.photos,
    required this.creationKey,
    required this.completionKey,
    this.note = '',
    this.previewPath,
    this.intent,
    this.assetId,
    this.createdId,
    this.locked = false,
  });
  factory CharacterDraft.fromJson(Map<String, dynamic> json) =>
      _$CharacterDraftFromJson(json);
  final String id;
  final List<CharacterPhoto> photos;
  String creationKey;
  String completionKey;
  String note;
  String? previewPath;
  Map<String, dynamic>? intent;
  String? assetId;
  String? createdId;
  bool locked;
  Map<String, dynamic> toJson() => _$CharacterDraftToJson(this);
}
