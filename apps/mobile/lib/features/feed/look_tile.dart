import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';

/// What a look's card shows, in priority order: an AI image (try-ons before
/// inspirations, newest first), else the flat lay.
sealed class LookCover {
  const LookCover();
}

class PhotoCover extends LookCover {
  const PhotoCover(this.record);
  final CachedLook record;
}

class FlatCover extends LookCover {
  const FlatCover();
}

LookCover lookCover(CachedLook record, FeedState state) {
  final look = record.look;
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
  return const FlatCover();
}

/// One look in the Looks grid. Every card has the same frame, whatever it
/// shows: a 4:5 cover. The pieces are in the flat lay or on the look's
/// page. Small counters tell which images hang under it.
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
    final cover = lookCover(record, state);
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
        label: garments.map((g) => g.item?.metadata.name).nonNulls.join(', '),
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
                        PhotoCover(:final record) => ColoredBox(
                          color: FormTokens.lookStage,
                          child: CachedMedia(
                            identity: record.look.cardAssetId!,
                            previewPath: record.previewPath(
                              record.look.cardAssetId!,
                            ),
                            online: online,
                            fit: BoxFit.cover,
                            entrance: MediaEntrance.fade,
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
                      if (tryOns + inspirations > 0)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _Counters(
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

/// What hangs under a look: try-ons and inspirations.
class _Counters extends StatelessWidget {
  const _Counters({required this.tryOns, required this.inspirations});

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
            if (tryOns > 0) counter(Icons.person_outline, tryOns),
            if (inspirations > 0)
              counter(Icons.auto_awesome_outlined, inspirations),
          ],
        ),
      ),
    );
  }
}
