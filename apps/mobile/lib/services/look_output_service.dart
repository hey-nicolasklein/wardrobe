import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/flat_lay_layout.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum LookOutputFailure { missingPieces, missingImage, photosDenied }

class LookOutputException implements Exception {
  const LookOutputException(this.failure);
  final LookOutputFailure failure;
}

/// Localized text printed onto an exported flat lay.
class FlatLayLabels {
  const FlatLayLabels({
    required this.heading,
    required this.moodFallback,
    required this.meta,
  });

  /// Top-right label, the PWA's "DEIN OUTFIT".
  final String heading;
  final String moodFallback;

  /// Bottom line with piece count and date.
  final String meta;
}

/// Shares a look or saves it to Photos, as the worn photo or a rendered flat
/// lay. Failures surface as [LookOutputException].
class LookOutputService {
  LookOutputService(this.media);

  final MediaRepository media;

  Future<File> _wornFile(Look look) async {
    final assetId = look.assetId;
    final file = assetId == null
        ? null
        : await media.load(assetId, previewPath: 'v1/assets/$assetId/content');
    if (file == null) {
      throw const LookOutputException(LookOutputFailure.missingImage);
    }
    return file;
  }

  Future<void> shareWorn(Look look, {required String caption}) async {
    final file = await _wornFile(look);
    await Share.shareXFiles([XFile(file.path)], text: caption);
  }

  Future<void> saveWorn(Look look) async =>
      _saveToPhotos(await _wornFile(look));

  Future<void> shareFlatLay(
    Look look,
    List<LookGarment> garments,
    FlatLayLabels labels, {
    required String caption,
  }) async {
    final file = await _flatLayFile(look, garments, labels);
    await Share.shareXFiles([XFile(file.path)], text: caption);
  }

  Future<void> saveFlatLay(
    Look look,
    List<LookGarment> garments,
    FlatLayLabels labels,
  ) async => _saveToPhotos(await _flatLayFile(look, garments, labels));

  Future<void> _saveToPhotos(File file) async {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw const LookOutputException(LookOutputFailure.photosDenied);
    }
    await Gal.putImage(file.path);
  }

  Future<File> _flatLayFile(
    Look look,
    List<LookGarment> garments,
    FlatLayLabels labels,
  ) async {
    // Like the PWA, refuse to export a flat lay that silently drops pieces.
    if (garments.isEmpty || garments.any((garment) => !garment.available)) {
      throw const LookOutputException(LookOutputFailure.missingPieces);
    }
    final bytes = await _renderFlatLay(
      look,
      [for (final garment in garments) garment.item!],
      labels,
    );
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/form-flat-lay-${look.id}.png');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Draws the PWA's 1200×1660 flat-lay export (`flatLayFile` in `app.js`).
  Future<Uint8List> _renderFlatLay(
    Look look,
    List<WardrobeItem> garments,
    FlatLayLabels labels,
  ) async {
    final layout = flatLayLayout(garments);
    final images = <ui.Image>[];
    try {
      for (final placement in layout) {
        final file = await media.load(
          placement.item.previewIdentity,
          previewPath: placement.item.previewPath,
        );
        if (file == null) {
          throw const LookOutputException(LookOutputFailure.missingImage);
        }
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        images.add((await codec.getNextFrame()).image);
      }
      const width = 1200.0;
      const height = 1660.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, width, height),
          Paint()..color = FormTokens.flatLayPaper,
        );
      TextPainter text(String value, double size, {FontWeight? weight}) =>
          TextPainter(
            text: TextSpan(
              text: value,
              style: TextStyle(
                color: FormTokens.flatLayInk,
                fontSize: size,
                fontWeight: weight,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: width - 128);
      text(
        'FORM',
        38,
        weight: FontWeight.w600,
      ).paint(canvas, const Offset(64, 40));
      final heading = text(labels.heading, 20);
      heading.paint(canvas, Offset(width - 64 - heading.width, 52));
      for (var index = 0; index < layout.length; index++) {
        final placement = layout[index];
        final image = images[index];
        final scale =
            placement.size * 11 / max(image.width, image.height).toDouble();
        canvas
          ..save()
          ..translate(50 + placement.x * 11, 130 + placement.y * 11)
          ..rotate(placement.angle * pi / 180)
          ..drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            Rect.fromCenter(
              center: Offset.zero,
              width: image.width * scale,
              height: image.height * scale,
            ),
            Paint()..filterQuality = FilterQuality.high,
          )
          ..restore();
      }
      text(
        look.concept?.mood ?? labels.moodFallback,
        28,
      ).paint(canvas, const Offset(64, 1540));
      text(labels.meta, 20).paint(canvas, const Offset(64, 1588));
      final rendered = await recorder.endRecording().toImage(
        width.toInt(),
        height.toInt(),
      );
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      return data!.buffer.asUint8List();
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }
}
