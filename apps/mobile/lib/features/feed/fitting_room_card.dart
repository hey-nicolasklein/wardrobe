import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/collection_sheet.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_actions.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/features/feed/look_collections_cubit.dart';
import 'package:form_mobile/features/wardrobe/inspire_button.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

/// Whether [record] is shown as a [FittingRoomCard]. Generated looks that
/// are still developing or failed keep `LookCard`, which animates those
/// states.
bool fittingRoomApplies(CachedLook record) =>
    record.look.isReady &&
    (record.look.assetId != null || !record.look.isGenerated);

/// One image of a look: an AI image made of it, or its pieces laid out flat.
class _Slide {
  const _Slide.flat() : record = null;
  const _Slide.image(CachedLook this.record);

  /// Null for the flat lay.
  final CachedLook? record;

  String get id => record?.look.id ?? 'flat';
}

/// A ready look: its images, tapped through like stories, its pieces as a
/// grid, and the two AI images it can get. A look is a combination of
/// pieces; try-ons and inspirations hang under it and never replace it.
class FittingRoomCard extends StatefulWidget {
  const FittingRoomCard({
    required this.record,
    required this.state,
    required this.garments,
    required this.online,
    required this.onMenu,
    this.origin,
    this.onRetry,
    super.key,
  });

  final CachedLook record;
  final FeedState state;
  final List<LookGarment> garments;
  final bool online;

  /// The filter the look was opened from. A try-on or inspiration filter
  /// opens the look on that kind of image, as its tile showed it.
  final LookStack? origin;

  /// Opens a look's actions: the image on show, or the look itself.
  final ValueChanged<Look> onMenu;

  /// Retries a failed image of a combination.
  final ValueChanged<Look>? onRetry;

  @override
  State<FittingRoomCard> createState() => _FittingRoomCardState();
}

class _FittingRoomCardState extends State<FittingRoomCard> {
  /// The slide the user tapped to. Null starts where [_startIndex] says.
  String? _slideId;

  /// Set after asking for a new image: the kind, and since when. The first
  /// image of that kind made after it comes to the front.
  (bool tryOn, DateTime since)? _awaiting;

  /// Try-ons, then inspirations, newest first within each, then the flat
  /// lay. A generated look without a base only has its own image.
  List<_Slide> _slides() {
    final look = widget.record.look;
    final images = look.isCombination
        ? widget.state.imagesOf(look.id)
        : <CachedLook>[];
    return [
      if (look.isGenerated) _Slide.image(widget.record),
      for (final image in images)
        if (image.look.isTryOn) _Slide.image(image),
      for (final image in images)
        if (!image.look.isTryOn) _Slide.image(image),
      if (widget.garments.isNotEmpty || !look.isGenerated) const _Slide.flat(),
    ];
  }

  int _startIndex(List<_Slide> slides) {
    bool kind(_Slide slide, {required bool tryOn}) =>
        switch (slide.record?.look) {
          final look? => look.isGenerated && look.isTryOn == tryOn,
          null => false,
        };
    final preferred = switch (widget.origin) {
      TryOnStack() => slides.indexWhere((s) => kind(s, tryOn: true)),
      InspirationStack() => slides.indexWhere((s) => kind(s, tryOn: false)),
      _ => -1,
    };
    return preferred < 0 ? 0 : preferred;
  }

  void _step(int delta, int count, int index) {
    final next = (index + delta).clamp(0, count - 1);
    if (next == index) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _slideId = _slides()[next].id);
  }

  Future<void> _addImage({required bool tryOn}) async {
    _awaiting = (tryOn, DateTime.now());
    await addLookImage(
      context,
      widget.record.look,
      mode: tryOn ? 'try-on' : 'inspiration',
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.record.look;
    final slides = _slides();
    if (_awaiting case (final tryOn, final since)) {
      final made = slides.where(
        (s) => switch (s.record?.look) {
          final image? =>
            image.id != look.id &&
                image.isTryOn == tryOn &&
                !image.createdAt.isBefore(since),
          null => false,
        },
      );
      if (made.firstOrNull case final slide?) {
        _slideId = slide.id;
        _awaiting = null;
      }
    }
    final picked = slides.indexWhere((s) => s.id == _slideId);
    final index = picked < 0 ? _startIndex(slides) : picked;
    final slide = slides[index];
    final images = look.isCombination
        ? widget.state.imagesOf(look.id)
        : <CachedLook>[];
    bool making({required bool tryOn}) =>
        images.any((i) => i.look.isActive && i.look.isTryOn == tryOn);
    final filed = collectionsOf(
      context.watch<LookCollectionsCubit>().state,
      look.id,
    ).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: _caption(context, slide).join(', '),
            value: '${index + 1} / ${slides.length}',
            onIncrease: index < slides.length - 1
                ? () => _step(1, slides.length, index)
                : null,
            onDecrease: index > 0
                ? () => _step(-1, slides.length, index)
                : null,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Like stories: the left third goes back, the rest forward.
                // Horizontal swipes stay with the pager between looks.
                onTapUp: slides.length < 2
                    ? null
                    : (details) => _step(
                        details.localPosition.dx < constraints.maxWidth / 3
                            ? -1
                            : 1,
                        slides.length,
                        index,
                      ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FormTokens.cardRadius),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: FormTokens.easeOut,
                      child: KeyedSubtree(
                        key: ValueKey(slide.id),
                        child: _stage(slide),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Dots(count: slides.length, index: index),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _caption(context, slide).first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FormTokens.small.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: FormTokens.noteInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _caption(context, slide).last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FormTokens.small.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.online
                    ? () => showCollectionSheet(context, lookId: look.id)
                    : null,
                tooltip: context.tr(LocaleKeys.collectionAdd),
                icon: FormIcon(
                  filed ? FormIconName.bookmarkFilled : FormIconName.bookmark,
                  size: 22,
                  color: filed ? FormTokens.green : FormTokens.ink,
                ),
              ),
              IconButton(
                onPressed: () => widget.onMenu(slide.record?.look ?? look),
                tooltip: context.tr(LocaleKeys.lookActions),
                icon: const FormIcon(FormIconName.more, size: 21),
              ),
            ],
          ),
          if (widget.garments.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PieceGrid(garments: widget.garments, online: widget.online),
          ],
          if (look.isCombination) ...[
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Expanded(
                    child: InspireButton(
                      icon: const Icon(Icons.person_outline_rounded),
                      title: context.tr(LocaleKeys.lookTryOn),
                      subtitle: context.tr(LocaleKeys.lookTryOnHint),
                      onPressed: widget.online && !making(tryOn: true)
                          ? () => unawaited(_addImage(tryOn: true))
                          : null,
                    ),
                  ),
                  Expanded(
                    child: InspireButton(
                      primary: false,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      title: context.tr(LocaleKeys.lookInspiration),
                      subtitle: context.tr(LocaleKeys.lookInspirationHint),
                      onPressed: widget.online && !making(tryOn: false)
                          ? () => unawaited(_addImage(tryOn: false))
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stage(_Slide slide) {
    final record = slide.record;
    if (record == null) {
      return _FlatStage(garments: widget.garments, online: widget.online);
    }
    if (!record.look.isReady) {
      return _ImageInProgress(
        look: record.look,
        garments: widget.garments,
        online: widget.online,
        onRetry: widget.onRetry == null
            ? null
            : () => widget.onRetry!(record.look),
      );
    }
    final assetId = record.look.cardAssetId!;
    return ColoredBox(
      color: FormTokens.lookStage,
      child: CachedMedia(
        identity: assetId,
        previewPath: record.previewPath(assetId),
        online: widget.online,
        // Fills the 2:3 stage. AI images are 4:5, so only their sides are
        // trimmed and the outfit in the middle stays whole.
        fit: BoxFit.cover,
        entrance: MediaEntrance.fade,
      ),
    );
  }

  /// What the slide shows, and a detail: who made it and when, or its state.
  List<String> _caption(BuildContext context, _Slide slide) {
    final look = slide.record?.look;
    if (look == null) {
      return [
        context.tr(LocaleKeys.lookLayerFlat),
        context.tr(LocaleKeys.lookFlatCaption),
      ];
    }
    final kind = context.tr(
      look.isTryOn
          ? LocaleKeys.lookLayerTryOn
          : LocaleKeys.lookLayerInspiration,
    );
    final detail = look.state == 'failed'
        ? context.tr(LocaleKeys.lookImageFailedShort)
        : !look.isReady
        ? context.tr(LocaleKeys.lookImageMaking)
        : context.tr(
            LocaleKeys.lookImageByAi,
            namedArgs: {'date': lookDateText(context, look.createdAt)},
          );
    return [kind, detail];
  }
}

/// Story-style dots: at most five, the one on show in forest. When more
/// images lie beyond the window, the dots at its edge shrink.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  static const _window = 5;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: 6);
    final size = count < _window ? count : _window;
    final start = (index - 2).clamp(0, count - size);
    return ExcludeSemantics(
      child: SizedBox(
        height: 6,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            for (var i = start; i < start + size; i++)
              AnimatedScale(
                duration: const Duration(milliseconds: 250),
                curve: FormTokens.easeOut,
                scale:
                    (i == start && start > 0) ||
                        (i == start + size - 1 && start + size < count)
                    ? 0.62
                    : 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == index
                        ? FormTokens.green
                        : const Color(0xFFC9CCC2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The look's pieces, four to a row, as in the wardrobe. Tapping opens one.
class _PieceGrid extends StatelessWidget {
  const _PieceGrid({required this.garments, required this.online});

  final List<LookGarment> garments;
  final bool online;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const columns = 4;
      const gap = 8.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 14,
        children: [
          for (final garment in garments)
            SizedBox(
              width: width,
              child: _PieceTile(garment: garment, online: online),
            ),
        ],
      );
    },
  );
}

class _PieceTile extends StatelessWidget {
  const _PieceTile({required this.garment, required this.online});

  final LookGarment garment;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final item = garment.item;
    return Semantics(
      button: item != null,
      label: item?.metadata.name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: item == null
            ? null
            : () {
                unawaited(HapticFeedback.selectionClick());
                unawaited(context.push('/wardrobe/items/${item.id}'));
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: item == null
                      ? FormTokens.field
                      : FormTokens.tileTint(item.id, item.metadata.colors),
                  borderRadius: BorderRadius.circular(FormTokens.inputRadius),
                ),
                child: item == null
                    ? null
                    : CachedMedia(
                        identity: item.previewIdentity,
                        previewPath: item.previewPath,
                        online: online,
                      ),
              ),
            ),
            if (item != null) ...[
              const SizedBox(height: 6),
              Text(
                item.metadata.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FormTokens.small.copyWith(
                  fontSize: 11.5,
                  height: 1.3,
                  color: FormTokens.noteInk,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The look's pieces laid out flat, on paper.
class _FlatStage extends StatelessWidget {
  const _FlatStage({required this.garments, required this.online});

  final List<LookGarment> garments;
  final bool online;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: FormTokens.flatLayPaper,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: _FlatEntrance(
          builder: (entrance) => FlatLayBoard(
            garments: garments,
            online: online,
            entrance: entrance,
          ),
          count: garments.length,
        ),
      ),
    ),
  );
}

/// Runs the pieces' rise into place once, when the flat lay first shows.
class _FlatEntrance extends StatefulWidget {
  const _FlatEntrance({required this.builder, required this.count});

  final Widget Function(Animation<double> entrance) builder;
  final int count;

  @override
  State<_FlatEntrance> createState() => _FlatEntranceState();
}

class _FlatEntranceState extends State<_FlatEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: FlatLayBoard.entranceDuration(widget.count),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

/// An image of a combination that is still being made, or failed: the
/// pieces under a drifting sheen, or a way to try again.
class _ImageInProgress extends StatelessWidget {
  const _ImageInProgress({
    required this.look,
    required this.garments,
    required this.online,
    required this.onRetry,
  });

  final Look look;
  final List<LookGarment> garments;
  final bool online;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = look.state == 'failed';
    return ColoredBox(
      color: FormTokens.lookStage,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: failed ? 0.25 : 0.45,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: FlatLayBoard(
                  garments: garments,
                  online: online,
                  arrive: true,
                ),
              ),
            ),
          ),
          if (!failed) const DevelopingSheen(active: true),
          Align(
            alignment: const Alignment(0, 0.78),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Text(
                    context.tr(
                      failed
                          ? LocaleKeys.lookImageFailed
                          : LocaleKeys.lookImageDeveloping,
                    ),
                    textAlign: TextAlign.center,
                    style: FormTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (failed && onRetry != null)
                    FilledButton(
                      onPressed: online ? onRetry : null,
                      child: Text(context.tr(LocaleKeys.retry)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
