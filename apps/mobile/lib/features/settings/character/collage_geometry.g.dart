// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collage_geometry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PhotoCrop _$PhotoCropFromJson(Map<String, dynamic> json) => PhotoCrop(
  zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
  x: (json['x'] as num?)?.toDouble() ?? 0.5,
  y: (json['y'] as num?)?.toDouble() ?? 0.5,
);

Map<String, dynamic> _$PhotoCropToJson(PhotoCrop instance) => <String, dynamic>{
  'zoom': instance.zoom,
  'x': instance.x,
  'y': instance.y,
};
