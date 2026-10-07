import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/found_pieces.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';

/// Found pieces on [look]'s photo that still want a decision: not linked to
/// a wardrobe piece yet and not waved off. Empty while the photo is analysed.
List<LookFoundPiece> openFoundPieces(Look look, FeedState state) => [
  for (final piece in look.found ?? const <LookFoundPiece>[])
    if (!state.dismissedFound.contains(piece.id) &&
        linkedFoundItem(piece, look, state.itemsById) == null)
      piece,
];

/// Whether background analysis found something on [look] the user has not
/// reviewed yet. Lights the card's discovery dot.
bool hasDiscovery(Look look, FeedState state) =>
    look.isPhoto && openFoundPieces(look, state).isNotEmpty;

/// What a look's card shows above its pieces, in priority order: the user's
/// own photo, an AI image (try-ons before inspirations, newest first), the
/// cropped reference photo, else the flat lay.
sealed class LookCover {
  const LookCover();
}

class PhotoCover extends LookCover {
  const PhotoCover(this.record, {this.crop});
  final CachedLook record;

  /// The outfit box on someone else's photo, so shop chrome stays out.
  final LookBox? crop;
}

class FlatCover extends LookCover {
  const FlatCover();
}

LookCover lookCover(CachedLook record, FeedState state) {
  final look = record.look;
  if (look.isPhoto && !look.isReference && look.cardAssetId != null) {
    return PhotoCover(record);
  }
  final images = [
    for (final image in state.imagesOf(look.id))
      if (image.look.isReady && image.look.cardAssetId != null) image,
  ];
  if (images.where((i) => i.look.isTryOn).firstOrNull ?? images.firstOrNull
      case final image?) {
    return PhotoCover(image);
  }
  // Generated looks without a base only have their own image.
  if (look.isGenerated && look.cardAssetId != null) return PhotoCover(record);
  if (look.isReference && look.cardAssetId != null) {
    return PhotoCover(record, crop: look.photo?.outfitBox);
  }
  return const FlatCover();
}

/// One look in the Looks grid. Every card has the same frame, whatever it
/// shows: a 4:5 cover. The pieces are in the flat lay or on the look's
/// page. Small counters tell what hangs under it, and a dot lights up when
/// FORM found something on its photo to review.
class LookTile extends StatelessWidget {
  const LookTile({
    required this.record,
    required this.state,
    required this.onTap,
    this.index = 0,
    super.key,
  });

  final CachedLook record;
  final FeedState state;
  final VoidCallback onTap;

  /// Position in the grid, staggers the entrance.
  final int index;

  @override
  Widget build(BuildContext context) {
    final look = record.look;
    final online = state.online && !state.stale;
    final garments = lookGarments(
      look,
      state.itemsById,
      pendingItemIds: state.pendingStarts[look.id],
    );
    final images = state.imagesOf(look.id);
    final tryOns = images.where((i) => i.look.isTryOn).length;
    final inspirations = images.length - tryOns;
    final photos = look.isPhoto ? 1 : 0;
    final cover = lookCover(record, state);
    final discovery = hasDiscovery(look, state);
    final analysing = look.isAnalysing;
    final worn = state.pendingWorn.containsKey(look.id);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + 50 * index.clamp(0, 8)),
      curve: FormTokens.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 18),
          child: child,
        ),
      ),
      child: Semantics(
        button: true,
        label: [
          ...garments.map((g) => g.item?.metadata.name).nonNulls,
          if (look.isReference) context.tr(LocaleKeys.looksReference),
          if (analysing) context.tr(LocaleKeys.looksAnalysing),
          if (discovery) context.tr(LocaleKeys.looksDiscovery),
        ].join(', '),
        child: GestureDetector(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: FormTokens.surface,
              borderRadius: BorderRadius.circular(FormTokens.cardRadius + 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1426351D),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    FormTokens.cardRadius - 2,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      switch (cover) {
                        PhotoCover(:final record, :final crop) => ColoredBox(
                          color: FormTokens.lookStage,
                          child: crop == null
                              ? CachedMedia(
                                  identity: record.look.cardAssetId!,
                                  previewPath: record.previewPath(
                                    record.look.cardAssetId!,
                                  ),
                                  online: online,
                                  fit: BoxFit.cover,
                                  entrance: MediaEntrance.fade,
                                )
                              : CroppedPhoto(
                                  identity: record.look.cardAssetId!,
                                  previewPath: record.previewPath(
                                    record.look.cardAssetId!,
                                  ),
                                  box: crop,
                                  online: online,
                                ),
                        ),
                        FlatCover() => ColoredBox(
                          color: FormTokens.flatLayPaper,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Center(
                              child: FlatLayBoard(
                                garments: garments,
                                online: online,
                              ),
                            ),
                          ),
                        ),
                      },
                      if (analysing || worn)
                        const DevelopingSheen(active: true),
                      if (look.isReference)
                        const Positioned(
                          top: 8,
                          left: 8,
                          child: _ReferenceMark(),
                        ),
                      if (discovery)
                        const Positioned(
                          top: 9,
                          right: 9,
                          child: DiscoveryDot(),
                        ),
                      if (photos + tryOns + inspirations > 0)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _Counters(
                            photos: photos,
                            tryOns: tryOns,
                            inspirations: inspirations,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A local photo on its way to becoming a look, in the same frame as a
/// [LookTile] so the grid does not jump when it arrives.
class PendingLookTile extends StatelessWidget {
  const PendingLookTile({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.tr(LocaleKeys.looksUploading),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: FormTokens.surface,
        borderRadius: BorderRadius.circular(FormTokens.cardRadius + 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FormTokens.cardRadius - 2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 0.55,
                  child: Image.file(File(path), fit: BoxFit.cover),
                ),
                const DevelopingSheen(active: true),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// What hangs under a look: own photos, try-ons and inspirations.
class _Counters extends StatelessWidget {
  const _Counters({
    required this.photos,
    required this.tryOns,
    required this.inspirations,
  });

  final int photos;
  final int tryOns;
  final int inspirations;

  @override
  Widget build(BuildContext context) {
    Widget counter(IconData icon, int count) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Icon(icon, size: 12, color: FormTokens.ink),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FormTokens.ink,
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(FormTokens.chipRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 7,
          children: [
            if (photos > 0) counter(Icons.photo_camera_outlined, photos),
            if (tryOns > 0) counter(Icons.person_outline, tryOns),
            if (inspirations > 0)
              counter(Icons.auto_awesome_outlined, inspirations),
          ],
        ),
      ),
    );
  }
}

/// The small marker on someone else's photo.
class _ReferenceMark extends StatelessWidget {
  const _ReferenceMark();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FormTokens.ink.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(FormTokens.chipRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          const Icon(Icons.bookmark_outline, size: 11, color: Colors.white),
          Text(
            context.tr(LocaleKeys.looksReference),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The only accent on a card: FORM found something on the photo that the
/// user has not looked at yet. Breathes softly.
class DiscoveryDot extends StatefulWidget {
  const DiscoveryDot({this.size = 12, super.key});

  final double size;

  @override
  State<DiscoveryDot> createState() => _DiscoveryDotState();
}

class _DiscoveryDotState extends State<DiscoveryDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final t = _controller.value;
      return SizedBox.square(
        dimension: widget.size * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size * (1 + t),
              height: widget.size * (1 + t),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FormTokens.liked.withValues(alpha: 0.45 * (1 - t)),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FormTokens.liked,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Loads a cached photo and reports its pixel size once decoded, for
/// overlays and crops that need to know where the photo's pixels land.
class LoadedPhoto extends StatefulWidget {
  const LoadedPhoto({
    required this.identity,
    required this.previewPath,
    required this.online,
    required this.builder,
    super.key,
  });

  final String identity;
  final String previewPath;
  final bool online;

  /// The size is null until the image is decoded.
  final Widget Function(BuildContext context, File file, Size? size) builder;

  @override
  State<LoadedPhoto> createState() => _LoadedPhotoState();
}

class _LoadedPhotoState extends State<LoadedPhoto> {
  File? _file;
  Size? _size;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(LoadedPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) unawaited(_load());
  }

  Future<void> _load() async {
    final file = await context.read<MediaRepository>().load(
      widget.identity,
      previewPath: widget.previewPath,
      online: widget.online,
    );
    if (!mounted || file == null) return;
    _detach();
    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    });
    stream.addListener(listener);
    setState(() {
      _file = file;
      _size = null;
      _stream = stream;
      _listener = listener;
    });
  }

  void _detach() {
    if (_listener case final listener?) _stream?.removeListener(listener);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_file) {
    final file? => widget.builder(context, file, _size),
    null => const SizedBox.expand(),
  };
}

/// Where a photo of [image] size lands in [frame] with `BoxFit.cover`: the
/// scale and the offset of its top-left corner.
({double scale, Offset offset}) coverFit(Size frame, Size image) {
  final scale = math.max(
    frame.width / image.width,
    frame.height / image.height,
  );
  return (
    scale: scale,
    offset: Offset(
      (frame.width - image.width * scale) / 2,
      (frame.height - image.height * scale) / 2,
    ),
  );
}

/// [box] (normalised 0–1000 on a photo of [image] size) in [frame] pixels,
/// when the photo covers the frame.
Rect boxInFrame(LookBox box, Size frame, Size image) {
  final fit = coverFit(frame, image);
  return Rect.fromLTWH(
    fit.offset.dx + box.x / 1000 * image.width * fit.scale,
    fit.offset.dy + box.y / 1000 * image.height * fit.scale,
    box.width / 1000 * image.width * fit.scale,
    box.height / 1000 * image.height * fit.scale,
  );
}

/// A photo cropped to [box] (normalised 0–1000) and scaled so the whole
/// outfit fits its frame. Falls back to a plain cover crop until the image
/// size is known.
class CroppedPhoto extends StatelessWidget {
  const CroppedPhoto({
    required this.identity,
    required this.previewPath,
    required this.box,
    required this.online,
    super.key,
  });

  final String identity;
  final String previewPath;
  final LookBox box;
  final bool online;

  @override
  Widget build(BuildContext context) => LoadedPhoto(
    identity: identity,
    previewPath: previewPath,
    online: online,
    builder: (context, file, image) {
      if (image == null) return Image.file(file, fit: BoxFit.cover);
      return LayoutBuilder(
        builder: (context, constraints) {
          final frame = constraints.biggest;
          final outfit = Rect.fromLTWH(
            box.x / 1000 * image.width,
            box.y / 1000 * image.height,
            box.width / 1000 * image.width,
            box.height / 1000 * image.height,
          );
          // The whole outfit fits with a little air, and the photo always
          // covers the frame.
          final scale = math.max(
            math.min(
                  frame.width / outfit.width,
                  frame.height / outfit.height,
                ) *
                0.94,
            coverFit(frame, image).scale,
          );
          final drawn = image * scale;
          final left = (frame.width / 2 - outfit.center.dx * scale).clamp(
            frame.width - drawn.width,
            0.0,
          );
          final top = (frame.height / 2 - outfit.center.dy * scale).clamp(
            frame.height - drawn.height,
            0.0,
          );
          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: drawn.width,
                  height: drawn.height,
                  child: Image.file(file, fit: BoxFit.fill),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
