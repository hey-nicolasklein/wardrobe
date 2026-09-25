import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_positions.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

class LookCard extends StatelessWidget {
  const LookCard({
    required this.record,
    required this.state,
    required this.garments,
    required this.online,
    required this.onRetry,
    required this.onDelete,
    required this.onShare,
    required this.onMenu,
    super.key,
  });

  final CachedLook record;
  final FeedState state;
  final List<LookGarment> garments;
  final bool online;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  /// Shares the representation the card currently shows.
  final VoidCallback onShare;
  final VoidCallback onMenu;

  Look get look => record.look;

  @override
  Widget build(BuildContext context) {
    if (look.state == 'failed') {
      return _FailedLookCard(
        garments: garments,
        online: online,
        onRetry: onRetry,
        onDelete: onDelete,
      );
    }
    if (!look.isReady) {
      return _DevelopingLookCard(
        look: look,
        garments: garments,
        online: online,
      );
    }
    final view = state.views[look.id] ?? LookFeedView.worn;
    final revealed = state.revealed.contains(look.id);
    final liked = state.liked[look.id] ?? false;
    final saved = state.saved[look.id] ?? false;
    final positions = lookItemPositions(
      garments.map((g) => g.item?.metadata.category ?? 'top').toList(),
    );
    return FormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FormChoiceChips(
                  options: {
                    'worn': context.tr(LocaleKeys.lookViewWorn),
                    'flat': context.tr(LocaleKeys.lookViewFlat),
                  },
                  selected: view == LookFeedView.flat ? 'flat' : 'worn',
                  onSelected: (value) => context.read<FeedCubit>().setLookView(
                    look.id,
                    value == 'flat' ? LookFeedView.flat : LookFeedView.worn,
                  ),
                ),
              ),
              IconButton(
                onPressed: online ? onMenu : null,
                tooltip: context.tr(LocaleKeys.lookActions),
                icon: const FormIcon(FormIconName.more),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (view == LookFeedView.worn && look.assetId != null)
                  GestureDetector(
                    onTap: () =>
                        context.read<FeedCubit>().toggleRevealed(look.id),
                    child: CachedMedia(
                      identity: look.assetId!,
                      previewPath: record.previewPath(look.assetId!),
                      online: online,
                    ),
                  ),
                if (view == LookFeedView.flat)
                  FlatLayBoard(
                    garments: garments,
                    online: online,
                    onGarmentTap: (id) => context.push('/wardrobe/items/$id'),
                  ),
                if (view == LookFeedView.worn)
                  _WornGarments(
                    garments: garments,
                    positions: positions,
                    revealed: revealed,
                    online: online,
                    onGarmentTap: (id) => context.push('/wardrobe/items/$id'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: online
                    ? () => context.read<FeedCubit>().toggleMark(
                        look.id,
                        liked: true,
                      )
                    : null,
                tooltip: context.tr(LocaleKeys.lookLike),
                isSelected: liked,
                icon: FormIcon(
                  liked ? FormIconName.heartFilled : FormIconName.heart,
                  color: liked ? FormTokens.liked : FormTokens.ink,
                ),
              ),
              IconButton(
                onPressed: onShare,
                tooltip: context.tr(LocaleKeys.lookShare),
                icon: const FormIcon(FormIconName.share),
              ),
              const Spacer(),
              IconButton(
                onPressed: online
                    ? () => context.read<FeedCubit>().toggleMark(
                        look.id,
                        liked: false,
                      )
                    : null,
                tooltip: context.tr(LocaleKeys.lookSave),
                isSelected: saved,
                icon: FormIcon(
                  saved ? FormIconName.bookmarkFilled : FormIconName.bookmark,
                  color: FormTokens.ink,
                ),
              ),
            ],
          ),
          if (look.concept != null)
            Text(
              look.concept!.mood,
              style: FormTokens.body.copyWith(fontWeight: FontWeight.w600),
            ),
          if (lookCaption(look).isNotEmpty)
            Text(lookCaption(look), style: FormTokens.small),
          Text(lookDateText(context, look.createdAt), style: FormTokens.small),
        ],
      ),
    );
  }
}

class _FailedLookCard extends StatelessWidget {
  const _FailedLookCard({
    required this.garments,
    required this.online,
    required this.onRetry,
    required this.onDelete,
  });

  final List<LookGarment> garments;
  final bool online;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => FormPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (garments.isNotEmpty)
          FlatLayBoard(garments: garments, online: online),
        const SizedBox(height: 16),
        Text(
          context.tr(LocaleKeys.lookFailedTitle),
          style: FormTokens.heading.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(context.tr(LocaleKeys.lookFailedBody), style: FormTokens.body),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: online ? onRetry : null,
          child: Text(context.tr(LocaleKeys.lookRetry)),
        ),
        TextButton(
          onPressed: online ? onDelete : null,
          child: Text(context.tr(LocaleKeys.lookDelete)),
        ),
      ],
    ),
  );
}

class _DevelopingLookCard extends StatelessWidget {
  const _DevelopingLookCard({
    required this.look,
    required this.garments,
    required this.online,
  });

  final Look look;
  final List<LookGarment> garments;
  final bool online;

  @override
  Widget build(BuildContext context) => FormPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (garments.isNotEmpty)
          FlatLayBoard(garments: garments, online: online)
        else
          const Icon(
            Icons.checkroom_outlined,
            size: 48,
            color: FormTokens.emptyIcon,
          ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: FormTokens.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      look.state == 'generating'
                          ? LocaleKeys.lookGeneratingTitle
                          : LocaleKeys.lookPlanningTitle,
                    ),
                    style: FormTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    context.tr(
                      look.state == 'generating'
                          ? LocaleKeys.lookGeneratingBody
                          : garments.isEmpty
                          ? LocaleKeys.lookPlanningBody
                          : LocaleKeys.lookPlanningWithItems,
                    ),
                    style: FormTokens.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Veils the worn photo and moves each garment from its place on the body
/// into an inset grid, matching the PWA's `.look-items` reveal. Closing plays
/// the stagger in reverse so pieces settle back in the opposite order.
class _WornGarments extends StatefulWidget {
  const _WornGarments({
    required this.garments,
    required this.positions,
    required this.revealed,
    required this.online,
    required this.onGarmentTap,
  });

  final List<LookGarment> garments;
  final List<LookItemPosition> positions;
  final bool revealed;
  final bool online;
  final ValueChanged<String> onGarmentTap;

  @override
  State<_WornGarments> createState() => _WornGarmentsState();
}

class _WornGarmentsState extends State<_WornGarments>
    with SingleTickerProviderStateMixin {
  static const _travel = 560;
  static const _stagger = 35;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.revealed ? 1 : 0,
  );

  Duration get _duration => Duration(
    milliseconds:
        _travel + _stagger * (widget.positions.length - 1).clamp(0, 12),
  );

  @override
  void didUpdateWidget(_WornGarments oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _duration;
    if (widget.revealed != oldWidget.revealed) {
      if (widget.revealed) {
        unawaited(_controller.forward());
      } else {
        unawaited(_controller.reverse());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _curveFor(LookItemPosition position) {
    final total = _controller.duration!.inMilliseconds;
    final start = position.order * _stagger / total;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start,
        (start + _travel / total).clamp(0, 1),
        curve: FormTokens.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isDismissed) return const SizedBox.shrink();
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.white.withValues(
                      alpha: 0.76 * _controller.value.clamp(0, 1),
                    ),
                  ),
                ),
              ),
              for (var index = 0; index < widget.garments.length; index++)
                if (index < widget.positions.length)
                  _garment(
                    widget.garments[index],
                    widget.positions[index],
                    width,
                    height,
                  ),
            ],
          );
        },
      );
    },
  );

  Widget _garment(
    LookGarment garment,
    LookItemPosition position,
    double width,
    double height,
  ) {
    final t = _curveFor(position).value;
    final size = position.size / 100 * width;
    final x = lerpDouble(position.originX, position.x, t)! / 100 * width;
    final y = lerpDouble(position.originY, position.y, t)! / 100 * height;
    final item = garment.item;
    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        ignoring: !widget.revealed || item == null,
        child: Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(
            scale: lerpDouble(position.originScale, 1, t),
            child: GestureDetector(
              onTap: () => widget.onGarmentTap(garment.id),
              child: item == null
                  ? const SizedBox.shrink()
                  : CachedMedia(
                      identity: item.previewIdentity,
                      previewPath: item.previewPath,
                      online: widget.online,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
