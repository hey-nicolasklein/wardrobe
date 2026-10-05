import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_stacks.dart';
import 'package:form_mobile/features/feed/occasion_tile.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/photo_preparation.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

/// The PWA's look composer (`openLookComposer`), shown as a sheet route.
class LookComposerPage extends StatelessWidget {
  const LookComposerPage({
    this.preselectedIds = const [],
    this.tryOn = false,
    this.occasion,
    this.from,
    super.key,
  });

  final List<String> preselectedIds;
  final bool tryOn;

  /// Preselects an occasion, e.g. when started from a feed shelf.
  final String? occasion;

  /// An earlier look whose pieces and settings the composer starts with.
  final Look? from;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = ComposerCubit(
        context.read<LookRepository>(),
        preselectedIds: preselectedIds,
        defaultQuality: context.read<QualityCubit>().state.feed,
        defaultStyle: context.read<QualityCubit>().state.lookStyle,
        tryOn: tryOn,
        from: from,
      );
      if (occasion != null) cubit.setOccasion(occasion);
      return cubit;
    },
    child: const _ComposerView(),
  );
}

class _ComposerView extends StatefulWidget {
  const _ComposerView();

  @override
  State<_ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<_ComposerView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onState(BuildContext context, ComposerState state) {
    if (_search.text != state.query) _search.text = state.query;
    if (state.proposed) {
      context.go(
        '/feed/proposals?quality=${state.quality}',
        extra: context.read<ComposerCubit>().command().body,
      );
    }
    if (state.createdLookId != null) {
      // The new look develops on top of the All looks pile.
      context.go('/feed');
      showFormToast(context, context.tr(LocaleKeys.lookCreating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wardrobe = context.watch<WardrobeCubit>().state;
    final connected =
        context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
    final eligible = eligibleComposerItems(wardrobe.items ?? []);
    return BlocConsumer<ComposerCubit, ComposerState>(
      listenWhen: (previous, next) =>
          previous.query != next.query ||
          previous.createdLookId != next.createdLookId ||
          previous.proposed != next.proposed,
      listener: _onState,
      builder: (context, state) {
        final cubit = context.read<ComposerCubit>();
        final selected = state.selectedItems(eligible);
        return PopScope(
          // Back from the flat-lay preview returns to the picker first.
          canPop: !state.previewExpanded,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.closePreview();
          },
          child: FormSheet(
            title: context.tr(
              state.tryOn
                  ? LocaleKeys.composerTryOnTitle
                  : LocaleKeys.createLook,
            ),
            leading: state.previewExpanded
                ? IconButton(
                    onPressed: cubit.closePreview,
                    tooltip: context.tr(LocaleKeys.composerBack),
                    style: IconButton.styleFrom(
                      backgroundColor: FormTokens.field,
                    ),
                    icon: const FormIcon(FormIconName.arrow, size: 20),
                  )
                : null,
            // The flat lay fits the sheet instead of scrolling.
            scrollable: !state.previewExpanded,
            footer: _ComposerFooter(
              state: state,
              selected: selected,
              online: !wardrobe.stale,
              connected: connected,
            ),
            slivers: state.previewExpanded
                ? null
                : [
                    _ComposerPicker(
                      state: state,
                      eligible: eligible,
                      search: _search,
                      online: !wardrobe.stale,
                    ),
                  ],
            child: state.previewExpanded
                ? _ComposerPreview(state: state, selected: selected)
                : null,
          ),
        );
      },
    );
  }
}

class _ComposerPicker extends StatelessWidget {
  const _ComposerPicker({
    required this.state,
    required this.eligible,
    required this.search,
    required this.online,
  });

  final ComposerState state;
  final List<WardrobeItem> eligible;
  final TextEditingController search;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final visible = state.visible(eligible);
    final available = [
      for (final category in categories)
        if (eligible.any((item) => item.metadata.category == category))
          category,
    ];
    final colors = [
      for (final family in FormTokens.colorSwatches.keys)
        if (family != 'other' &&
            eligible.any(
              (item) => item.metadata.colors.any(
                (color) => colorFamilies(color).contains(family),
              ),
            ))
          family,
    ];
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.tryOn)
                _TryOnBases(state: state, online: online)
              else ...[
                Text(
                  context.tr(LocaleKeys.composerOccasionLabel),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _OccasionPresets(selected: state.occasion),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr(LocaleKeys.composerPickerTitle),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: FormTokens.ink,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: context.tr(LocaleKeys.composerSelectedOnly),
                    // Ghost button like the PWA, tinted only while the filter
                    // is on.
                    child: Semantics(
                      selected: state.selectedOnly,
                      child: TextButton.icon(
                        onPressed: cubit.toggleSelectedOnly,
                        icon: state.selectedIds.isEmpty
                            ? null
                            : const FormIcon(FormIconName.check, size: 18),
                        label: Text(
                          context.tr(
                            LocaleKeys.composerSelectedCount,
                            namedArgs: {'count': '${state.selectedIds.length}'},
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: FormTokens.ink,
                          backgroundColor: state.selectedOnly
                              ? FormTokens.selectedTint
                              : Colors.transparent,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FormSearchField(
                controller: search,
                hint: context.tr(LocaleKeys.composerSearchHint),
                onChanged: cubit.setQuery,
                onClear: state.query.isEmpty ? null : () => cubit.setQuery(''),
              ),
            ],
          ),
        ),
        // The category pills stay reachable while scrolling the grid.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedPills(
            // Pills running past the right edge fade out instead of being
            // cut off.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.85, 1],
              ).createShader(bounds),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in [null, ...available])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FormPill(
                          label: category == null
                              ? context.tr(LocaleKeys.composerFilterAll)
                              : context.tr('categories.$category'),
                          selected:
                              !state.selectedOnly &&
                              state.itemCategory == category,
                          onTap: () => cubit.setItemCategory(category),
                        ),
                      ),
                    for (final family in colors)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FormPill(
                          leading: ColorDot(
                            color: FormTokens.colorSwatches[family],
                            size: 14,
                          ),
                          label: context.tr('colorFamilies.$family'),
                          selected:
                              !state.selectedOnly && state.itemColor == family,
                          onTap: () => cubit.setItemColor(family),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: _PickerEmpty(state: state, noEligible: eligible.isEmpty),
          )
        else
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 18,
              crossAxisSpacing: 12,
              childAspectRatio: 0.6,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final item = visible[index];
              return _SelectItem(
                item: item,
                selected: state.selectedIds.contains(item.id),
                online: online,
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  cubit.toggleItem(item.id);
                },
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        if (!state.tryOn)
          SliverToBoxAdapter(child: _CategoryOptions(state: state)),
      ],
    );
  }
}

/// Why the picker grid is empty, with a way back to all pieces when a
/// search, category or the selection filter hides them.
class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.state, required this.noEligible});

  final ComposerState state;
  final bool noEligible;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final nothingSelected = state.selectedOnly && state.selectedIds.isEmpty;
    final (title, message) = noEligible
        ? (LocaleKeys.composerNoEligible, LocaleKeys.composerNoEligibleBody)
        : nothingSelected
        ? (LocaleKeys.composerNothingSelected, null)
        : (LocaleKeys.composerEmpty, LocaleKeys.composerEmptyBody);
    return FormEmptyState(
      title: context.tr(title),
      message: message == null ? null : context.tr(message),
      icon: noEligible ? Icons.checkroom_outlined : Icons.search_off_rounded,
      action: noEligible
          ? null
          : OutlinedButton(
              // Also leaves the selection filter.
              onPressed: () => cubit
                ..setQuery('')
                ..setItemCategory(null),
              child: Text(
                context.tr(
                  nothingSelected
                      ? LocaleKeys.composerShowAll
                      : LocaleKeys.resetFilters,
                ),
              ),
            ),
    );
  }
}

/// Pins the composer's category pills below the sheet title. Once items
/// scroll beneath, a short paper fade separates them from the pills.
class _PinnedPills extends SliverPersistentHeaderDelegate {
  const _PinnedPills({required this.child});

  final Widget child;

  static const _pills = 44.0;
  static const _padding = 8.0;
  static const _fade = 12.0;

  @override
  double get minExtent => _pills + 2 * _padding;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Stack(
    clipBehavior: Clip.none,
    children: [
      // Reaches slightly above the header so items scrolling under it can't
      // peek through a sub-pixel gap at the top edge.
      Positioned(
        left: 0,
        right: 0,
        top: -2,
        bottom: 0,
        child: ColoredBox(
          color: FormTokens.paper,
          child: Padding(
            padding: const EdgeInsets.only(top: _padding + 2, bottom: _padding),
            child: child,
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: -_fade,
        height: _fade,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: shrinkOffset > 0 || overlapsContent ? 1 : 0,
            duration: FormTokens.quick,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [FormTokens.paper, Color(0x00F6F5F1)],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  bool shouldRebuild(_PinnedPills oldDelegate) => oldDelegate.child != child;
}

class _OccasionPresets extends StatelessWidget {
  const _OccasionPresets({required this.selected});

  final String? selected;

  // One scrolling row of chips keeps full labels in every language. The row
  // bleeds into the sheet gutters and fades out there on both sides, so chips
  // line up with the content at rest but never end in a hard cut.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gutter = FormTokens.gutter;
      final width = constraints.maxWidth + 2 * gutter;
      final edge = gutter / width;
      // IntrinsicHeight gives the OverflowBox a bounded height inside the
      // sheet's unbounded column.
      return IntrinsicHeight(
        child: OverflowBox(
          minWidth: width,
          maxWidth: width,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: const [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, edge, 1 - edge, 1],
            ).createShader(bounds),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: gutter),
              child: Row(
                children: [
                  for (final (index, preset) in occasionPresets.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    _preset(context, preset),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _preset(
    BuildContext context,
    ({String? value, FormIconName icon, String label}) preset,
  ) => OccasionTile(
    icon: preset.icon,
    label: context.tr(preset.label),
    colors: FormTokens.occasions[preset.value ?? '']!,
    selected: preset.value == selected,
    compact: true,
    onTap: () {
      unawaited(HapticFeedback.selectionClick());
      context.read<ComposerCubit>().setOccasion(preset.value);
    },
  );
}

class _SelectItem extends StatelessWidget {
  const _SelectItem({
    required this.item,
    required this.selected,
    required this.online,
    required this.onTap,
  });

  static const TextStyle titleStyle = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: FormTokens.ink,
  );
  static const double titleHeight = 11 * 1.3 * 2;

  final WardrobeItem item;
  final bool selected;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.metadata.name,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = math.min(
                  constraints.maxHeight,
                  width * 4 / 3,
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected
                                ? FormTokens.selectedTint
                                : FormTokens.field,
                            borderRadius: BorderRadius.circular(
                              FormTokens.inputRadius,
                            ),
                          ),
                          child: CachedMedia(
                            identity: item.previewIdentity,
                            previewPath: item.previewPath,
                            online: online,
                          ),
                        ),
                        Positioned(
                          top: 7,
                          right: 7,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            reverseDuration: const Duration(
                              milliseconds: 240,
                            ),
                            transitionBuilder: _checkTransition,
                            child: selected
                                ? const _CheckBadge()
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: SizedBox(
              height: _SelectItem.titleHeight,
              width: double.infinity,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  item.metadata.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _SelectItem.titleStyle,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Eases the check badge in with a slight twist and lets it sink out with a
/// soft fade. Outgoing children run the animation in reverse (1 → 0).
Widget _checkTransition(Widget child, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        if (animation.status == AnimationStatus.reverse) {
          final t = Curves.easeIn.transform(animation.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 4),
              child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
            ),
          );
        }
        final t = Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.rotate(
            angle: (1 - t) * -0.35,
            child: Transform.scale(
              scale: 0.5 + 0.5 * Curves.easeOutBack.transform(animation.value),
              child: child,
            ),
          ),
        );
      },
    );

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: FormTokens.checkBadge,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: FormTokens.flatLayInk.withValues(alpha: 0.07),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: const FormIcon(
      FormIconName.check,
      size: 14,
      color: FormTokens.checkInk,
    ),
  );
}

class _CategoryOptions extends StatefulWidget {
  const _CategoryOptions({required this.state});

  final ComposerState state;

  @override
  State<_CategoryOptions> createState() => _CategoryOptionsState();
}

class _CategoryOptionsState extends State<_CategoryOptions> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<ComposerCubit>();
    // Required categories only apply while completing from the wardrobe.
    if (!state.completeWithWardrobe) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FormTokens.surface,
        border: Border.all(color: FormTokens.line),
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const FormIcon(FormIconName.filter, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(LocaleKeys.composerCategoriesTitle),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(_open ? '−' : '+'),
                    ],
                  ),
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in categories)
                      FormPill(
                        label: context.tr('categories.$category'),
                        selected: state.categories.contains(category),
                        onTap: () => cubit.toggleCategory(category),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How the rest of the outfit is filled, pinned in the footer next to the
/// picked pieces it depends on. `selected` needs pieces from one body zone.
class _CompletionChoice extends StatelessWidget {
  const _CompletionChoice({
    required this.completion,
    required this.canFrameOnly,
  });

  final String completion;
  final bool canFrameOnly;

  static Widget _icon(String completion, Color color) => switch (completion) {
    'wardrobe' => FormIcon(FormIconName.closet, size: 17, color: color),
    'model' => Icon(Icons.auto_awesome_outlined, size: 16, color: color),
    _ => Icon(Icons.crop_free_rounded, size: 17, color: color),
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final blocked = completion == 'selected' && !canFrameOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.composerCompleteTitle),
          style: FormTokens.eyebrow,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (index, option) in lookCompletions.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: _CompletionPill(
                  label: context.tr('lookCompletion.$option'),
                  icon: (color) => _icon(option, color),
                  selected: option == completion,
                  enabled:
                      option != 'selected' ||
                      canFrameOnly ||
                      completion == 'selected',
                  onTap: () {
                    if (option != completion) {
                      unawaited(HapticFeedback.selectionClick());
                    }
                    cubit.setCompletion(option);
                  },
                ),
              ),
            ],
          ],
        ),
        AnimatedSize(
          duration: FormTokens.quick,
          alignment: Alignment.topCenter,
          child: blocked
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(LocaleKeys.composerCompleteHelpUnframable),
                    style: FormTokens.small.copyWith(
                      color: FormTokens.danger,
                      height: 1.4,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CompletionPill extends StatelessWidget {
  const _CompletionPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final Widget Function(Color color) icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : FormTokens.ink;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: AnimatedOpacity(
        duration: FormTokens.quick,
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(FormTokens.chipRadius),
            child: AnimatedContainer(
              duration: FormTokens.quick,
              curve: Curves.easeOut,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: selected ? FormTokens.green : FormTokens.pill,
                borderRadius: BorderRadius.circular(FormTokens.chipRadius),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon(foreground),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's own photos for a try-on: a tile to add one, then the photos
/// earlier try-ons used. Picking the same photo again keeps results comparable.
class _TryOnBases extends StatelessWidget {
  const _TryOnBases({required this.state, required this.online});

  final ComposerState state;
  final bool online;

  static const _height = 150.0;

  Future<void> _add(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;
    await context.read<ComposerCubit>().addBase(() async {
      final prepared = await PhotoPreparation().prepare(picked.path);
      return compute(cropToLookFormat, prepared.bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.composerTryOnPhotos),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(context.tr(LocaleKeys.composerTryOnHint), style: FormTokens.small),
        const SizedBox(height: 12),
        SizedBox(
          height: _height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _BaseTile(
                selected: false,
                onTap: state.uploadingBase || !online
                    ? null
                    : () => unawaited(_add(context)),
                child: ColoredBox(
                  color: FormTokens.uploadTint,
                  child: Center(
                    child: state.uploadingBase
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_a_photo_outlined,
                                color: FormTokens.green,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.tr(LocaleKeys.composerTryOnAddPhoto),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: FormTokens.green,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              for (final assetId in state.tryOnBases)
                _BaseTile(
                  key: ValueKey(assetId),
                  selected: assetId == state.baseAssetId,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    cubit.selectBase(assetId);
                  },
                  child: CachedMedia(
                    identity: assetId,
                    previewPath: 'v1/assets/$assetId/content',
                    online: online,
                    fit: BoxFit.cover,
                    entrance: MediaEntrance.fade,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BaseTile extends StatelessWidget {
  const _BaseTile({
    required this.selected,
    required this.onTap,
    required this.child,
    super.key,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: FormTokens.quick,
          width: _TryOnBases._height * 4 / 5,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? FormTokens.green : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                if (selected)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: FormTokens.green,
                      child: Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({required this.state, required this.selected});

  final ComposerState state;
  final List<WardrobeItem> selected;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final piece = selected
        .where((item) => item.id == state.selectedPieceId)
        .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                composerSummaryText(context, state),
                style: FormTokens.small.copyWith(color: FormTokens.ink),
              ),
            ),
            if (selected.isNotEmpty)
              TextButton(
                onPressed: cubit.reset,
                child: Text(context.tr(LocaleKeys.composerReset)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (selected.isEmpty) ...[
          Text(
            context.tr(LocaleKeys.composerPreviewEmpty),
            style: FormTokens.body,
          ),
          Text(
            context.tr(LocaleKeys.composerPreviewEmptyHint),
            style: FormTokens.small,
          ),
        ] else
          // Shrinks the board to the height left over on short screens.
          Flexible(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: FlatLayBoard(
                garments: [
                  for (final item in selected)
                    LookGarment(id: item.id, item: item),
                ],
                online: true,
                selectedId: state.selectedPieceId,
                onGarmentTap: cubit.selectPiece,
              ),
            ),
          ),
        if (selected.isNotEmpty && !state.tryOn) ...[
          const SizedBox(height: 16),
          _CompletionChoice(
            completion: state.completion,
            canFrameOnly: canFrameOnly(
              selected.map((item) => item.metadata.category),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Fixed height, so the hint and a highlighted piece swap without
        // moving the sheet footer.
        SizedBox(
          height: 52,
          child: Align(
            alignment: Alignment.centerLeft,
            child: piece == null
                ? Text(
                    context.tr(LocaleKeys.composerPieceHint),
                    style: FormTokens.small,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              piece.metadata.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FormTokens.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              context.tr(
                                'categories.${piece.metadata.category}',
                              ),
                              style: FormTokens.small,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => cubit.toggleItem(piece.id),
                        child: Text(context.tr(LocaleKeys.composerRemovePiece)),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ComposerFooter extends StatelessWidget {
  const _ComposerFooter({
    required this.state,
    required this.selected,
    required this.online,
    required this.connected,
  });

  final ComposerState state;
  final List<WardrobeItem> selected;
  final bool online;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    final frameable = canFrameOnly(
      selected.map((item) => item.metadata.category),
    );
    final credits = context.watch<CreditsCubit>().state;
    // Why the action is disabled, so a grey button never goes unexplained.
    final blocked = !connected
        ? LocaleKeys.composerBlockedOffline
        : state.tryOn && state.baseAssetId == null
        ? LocaleKeys.composerBlockedPhoto
        : state.tryOn && selected.isEmpty
        ? LocaleKeys.composerBlockedPieces
        : !state.tryOn && state.completion == 'selected' && !frameable
        ? LocaleKeys.composerBlockedFrame
        : credits != null && credits.metered && credits.looksLeft == 0
        ? LocaleKeys.composerBlockedCredits
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked != null && !state.previewExpanded) ...[
          Text(
            context.tr(blocked),
            style: FormTokens.small.copyWith(color: FormTokens.danger),
          ),
          const SizedBox(height: 10),
        ],
        // Toasts would land behind the sheet, so problems show inline here.
        if (state.failure != null || state.limitReached) ...[
          FormNotice(
            text: state.limitReached
                ? context.tr(LocaleKeys.composerLimit)
                : apiFailureText(context, state.failure!),
            error: state.failure != null,
          ),
          const SizedBox(height: 12),
        ],
        // With nothing picked, the line says what FORM will do instead.
        if (selected.isEmpty && !state.previewExpanded && blocked == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              composerSummaryText(context, state),
              style: FormTokens.small.copyWith(color: FormTokens.ink),
            ),
          ),
        // The selection shares the row with the action, so picking pieces
        // never grows the footer over the grid.
        Row(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: _TrayGarment.curve,
              child: selected.isNotEmpty && !state.previewExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _Tray(selected: selected, online: online),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: FilledButton(
                onPressed: state.submitting || blocked != null
                    ? null
                    : () => unawaited(cubit.submit()),
                child: state.submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    // Stays on one line beside the tray. Long labels shrink.
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        // Proposing is free; the cost shows on each proposal.
                        child: Text(
                          state.tryOn
                              ? lookCostLabel(
                                  context,
                                  context.tr(LocaleKeys.composerTryOnAction),
                                  context.watch<CreditsCubit>().state,
                                )
                              : context.tr(LocaleKeys.composerProposeAction),
                          maxLines: 1,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The selection as overlapping thumbnails beside the action. Tapping opens
/// the flat-lay preview, where the outfit's rest is chosen.
class _Tray extends StatelessWidget {
  const _Tray({required this.selected, required this.online});

  static const _thumb = 44.0;
  static const _step = 24.0;
  static const _maxShown = 3;

  final List<WardrobeItem> selected;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final shown = selected.take(_maxShown).toList();
    final more = selected.length - shown.length;
    final width = _thumb + (shown.length - 1) * _step;
    return Semantics(
      button: true,
      label: context.tr(
        LocaleKeys.composerTrayLabel,
        namedArgs: {'count': '${selected.length}'},
      ),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.read<ComposerCubit>().openPreview(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: _TrayGarment.duration,
                curve: _TrayGarment.curve,
                width: width,
                height: _thumb,
                child: Stack(
                  // Entering pieces start 14px low and must stay visible.
                  clipBehavior: Clip.none,
                  children: [
                    for (final (index, item) in shown.indexed)
                      AnimatedPositioned(
                        key: ValueKey(item.id),
                        duration: _TrayGarment.duration,
                        curve: _TrayGarment.curve,
                        left: index * _step,
                        top: 0,
                        width: _thumb,
                        height: _thumb,
                        child: _TrayGarment(
                          item: item,
                          online: online,
                          delay: index * 35,
                        ),
                      ),
                  ],
                ),
              ),
              if (more > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+$more',
                  style: const TextStyle(fontSize: 12, color: FormTokens.muted),
                ),
              ],
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: FormTokens.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tray piece that rises into place when it first appears, like the PWA's
/// entrance: up 14px, from 88% scale and transparent.
class _TrayGarment extends StatefulWidget {
  const _TrayGarment({
    required this.item,
    required this.online,
    required this.delay,
  });

  static const duration = Duration(milliseconds: 420);
  static const curve = Cubic(0.22, 1, 0.36, 1);

  final WardrobeItem item;
  final bool online;
  final int delay;

  @override
  State<_TrayGarment> createState() => _TrayGarmentState();
}

class _TrayGarmentState extends State<_TrayGarment>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: _TrayGarment.duration,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: _TrayGarment.curve,
  );
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted || _delay != null) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _delay = Timer(
        Duration(milliseconds: widget.delay),
        () => unawaited(_controller.forward()),
      );
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, child) {
      final t = _progress.value;
      return Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
        ),
      );
    },
    // The paper border separates overlapping thumbnails.
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FormTokens.field,
        border: Border.all(color: FormTokens.paper, width: 2),
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
      ),
      child: CachedMedia(
        identity: widget.item.previewIdentity,
        previewPath: widget.item.previewPath,
        online: widget.online,
      ),
    ),
  );
}
