import 'dart:math';

import 'package:json_annotation/json_annotation.dart';

part 'collage_geometry.g.dart';

const collageWidth = 864;
const collageHeight = 1536;

typedef CollageTile = ({int left, int top, int width, int height});
typedef CropBounds = ({double x, double y, double width, double height});

List<CollageTile> collageLayout(int count) => switch (count) {
  1 => [(left: 0, top: 0, width: 864, height: 1536)],
  2 => [
    for (var i = 0; i < 2; i++)
      (left: 0, top: i * 768, width: 864, height: 768),
  ],
  3 => [
    (left: 0, top: 0, width: 864, height: 768),
    (left: 0, top: 768, width: 432, height: 768),
    (left: 432, top: 768, width: 432, height: 768),
  ],
  4 => [
    for (var i = 0; i < 4; i++)
      (left: i % 2 * 432, top: i ~/ 2 * 768, width: 432, height: 768),
  ],
  _ => throw const FormatException('character.photoCount'),
};

@JsonSerializable()
class PhotoCrop {
  const PhotoCrop({this.zoom = 1, this.x = 0.5, this.y = 0.5});
  factory PhotoCrop.fromJson(Map<String, dynamic> json) =>
      _$PhotoCropFromJson(json);
  final double zoom;
  final double x;
  final double y;

  Map<String, dynamic> toJson() => _$PhotoCropToJson(this);

  PhotoCrop withZoom(double value) =>
      PhotoCrop(zoom: value.clamp(1, 6), x: x, y: y);

  CropBounds bounds(int width, int height, CollageTile tile) {
    final scale =
        max(tile.width / width, tile.height / height) * zoom.clamp(1, 6);
    final w = tile.width / scale;
    final h = tile.height / scale;
    return (
      x: (width - w) * x.clamp(0, 1),
      y: (height - h) * y.clamp(0, 1),
      width: w,
      height: h,
    );
  }

  bool lowResolution(int width, int height, CollageTile tile) {
    final b = bounds(width, height, tile);
    return b.width < tile.width || b.height < tile.height;
  }

  PhotoCrop pan(int width, int height, CollageTile tile, double dx, double dy) {
    final b = bounds(width, height, tile);
    return PhotoCrop(
      zoom: zoom,
      x: width > b.width
          ? (x - dx * b.width / (width - b.width)).clamp(0, 1)
          : 0.5,
      y: height > b.height
          ? (y - dy * b.height / (height - b.height)).clamp(0, 1)
          : 0.5,
    );
  }
}
