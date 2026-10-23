import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

const int maximumPhotoBytes = 25 * 1024 * 1024;

void validatePhotoSize(int bytes) {
  if (bytes <= 0 || bytes > maximumPhotoBytes) {
    throw const FormatException('intake.fileSize');
  }
}

(int, int) photoDimensions(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw const FormatException('intake.invalidPhoto');
  }
  final scale = min(1, 2400 / max(width, height));
  return (max(1, (width * scale).round()), max(1, (height * scale).round()));
}

class PreparedPhoto {
  const PreparedPhoto(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

PreparedPhoto? normalizePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final (width, height) = photoDimensions(upright.width, upright.height);
  final resized = trimDarkBorders(
    img.copyResize(upright, width: width, height: height),
  );
  return PreparedPhoto(
    img.encodeJpg(resized, quality: 92),
    resized.width,
    resized.height,
  );
}

/// Cuts away black bars along the edges, such as the letterbox of a video
/// still or a screenshot. A row or column counts as a bar when nearly all of
/// it is close to black. Leaves the photo whole when less than a fifth of
/// either side would remain, so dark photos stay as they are.
img.Image trimDarkBorders(img.Image image) {
  bool dark(int x, int y) {
    final p = image.getPixel(x, y);
    return max(p.r, max(p.g, p.b)) <= 24;
  }

  bool darkRow(int y) {
    var count = 0;
    var total = 0;
    for (var x = 0; x < image.width; x += 4, total++) {
      if (dark(x, y)) count++;
    }
    return count >= total * 0.98;
  }

  bool darkColumn(int x, int top, int bottom) {
    var count = 0;
    var total = 0;
    for (var y = top; y < bottom; y += 4, total++) {
      if (dark(x, y)) count++;
    }
    return count >= total * 0.98;
  }

  var top = 0;
  var bottom = image.height;
  while (top < bottom && darkRow(top)) {
    top++;
  }
  while (bottom > top && darkRow(bottom - 1)) {
    bottom--;
  }
  var left = 0;
  var right = image.width;
  while (left < right && darkColumn(left, top, bottom)) {
    left++;
  }
  while (right > left && darkColumn(right - 1, top, bottom)) {
    right--;
  }
  final width = right - left;
  final height = bottom - top;
  final untouched = width == image.width && height == image.height;
  if (untouched || width < image.width * 0.2 || height < image.height * 0.2) {
    return image;
  }
  return img.copyCrop(image, x: left, y: top, width: width, height: height);
}

class PhotoPreparation {
  Future<PreparedPhoto> prepare(String filePath) async {
    final file = File(filePath);
    validatePhotoSize(await file.length());
    final bytes = await file.readAsBytes();
    var result = await compute(normalizePhoto, bytes);
    if (result == null) {
      // Native codecs handle HEIC/HEIF before the shared final JPEG encoding.
      final png = await FlutterImageCompress.compressWithFile(
        filePath,
        minWidth: 2400,
        minHeight: 2400,
        format: CompressFormat.png,
        quality: 100,
      );
      if (png != null) result = await compute(normalizePhoto, png);
    }
    if (result == null) throw const FormatException('intake.invalidPhoto');
    return result;
  }
}

/// Center-crops a JPEG to the 4:5 look format, so a try-on keeps the photo's
/// framing instead of the image model re-framing it.
Uint8List cropToLookFormat(Uint8List jpeg) {
  final image = img.decodeJpg(jpeg)!;
  final (width, height) = image.width * 5 > image.height * 4
      ? (image.height * 4 ~/ 5, image.height)
      : (image.width, image.width * 5 ~/ 4);
  final cropped = img.copyCrop(
    image,
    x: (image.width - width) ~/ 2,
    y: (image.height - height) ~/ 2,
    width: width,
    height: height,
  );
  return img.encodeJpg(cropped, quality: 92);
}
