// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character_draft.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CharacterPhoto _$CharacterPhotoFromJson(Map<String, dynamic> json) =>
    CharacterPhoto(
      path: json['path'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      crop: json['crop'] == null
          ? const PhotoCrop()
          : PhotoCrop.fromJson(json['crop'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CharacterPhotoToJson(CharacterPhoto instance) =>
    <String, dynamic>{
      'path': instance.path,
      'width': instance.width,
      'height': instance.height,
      'crop': instance.crop.toJson(),
    };

CharacterDraft _$CharacterDraftFromJson(Map<String, dynamic> json) =>
    CharacterDraft(
      id: json['id'] as String,
      photos: (json['photos'] as List<dynamic>)
          .map((e) => CharacterPhoto.fromJson(e as Map<String, dynamic>))
          .toList(),
      creationKey: json['creationKey'] as String,
      completionKey: json['completionKey'] as String,
      note: json['note'] as String? ?? '',
      previewPath: json['previewPath'] as String?,
      intent: json['intent'] as Map<String, dynamic>?,
      assetId: json['assetId'] as String?,
      createdId: json['createdId'] as String?,
      locked: json['locked'] as bool? ?? false,
    );

Map<String, dynamic> _$CharacterDraftToJson(CharacterDraft instance) =>
    <String, dynamic>{
      'id': instance.id,
      'photos': instance.photos.map((e) => e.toJson()).toList(),
      'creationKey': instance.creationKey,
      'completionKey': instance.completionKey,
      'note': instance.note,
      'previewPath': instance.previewPath,
      'intent': instance.intent,
      'assetId': instance.assetId,
      'createdId': instance.createdId,
      'locked': instance.locked,
    };
