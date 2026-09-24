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
  final resized = img.copyResize(upright, width: width, height: height);
  return PreparedPhoto(img.encodeJpg(resized, quality: 92), width, height);
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
