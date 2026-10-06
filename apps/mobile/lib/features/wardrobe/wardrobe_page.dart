import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class WardrobePage extends StatefulWidget {
  const WardrobePage({this.archived = false, super.key});
  final bool archived;

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// Height of the tab bar under the find bar. The shell drops it from the
  /// padding while the keyboard is up, so the last value seen without the
  /// keyboard is kept.
  double _tabBarInset = 0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
  }

  bool get archived => widget.archived;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    if (View.of(context).viewInsets.bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      // Let the keyboard slide away first, so it and the sheet don't move
      // the find bar at the same time.
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
    }
    return showFormSheet<void>(
      context: context,
      builder: (_) => BlocBuilder<WardrobeCubit, WardrobeState>(
        builder: (context, state) {
          final filter = state.filter;
          final cubit = context.read<WardrobeCubit>();
          final records = state.items ?? [];
          return FormSheet(
            title: context.tr(LocaleKeys.filters),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(LocaleKeys.season), style: FormTokens.small),
                const SizedBox(height: 8),
                _TraitOptions(
                  records: records,
                  archived: archived,
                  options: (traits) => [traits.warmth],
                  order: warmths,
                  selected: filter.seasons,
                  label: (warmth) => context.tr('seasons.$warmth'),
                  onChanged: (seasons) =>
                      cubit.filter(filter.copyWith(seasons: seasons)),
                ),
                Text(context.tr(LocaleKeys.category), style: FormTokens.small),
                const SizedBox(height: 8),
                _CategoryOptions(
                  records: records,
                  filter: filter,
                  archived: archived,
                  onChanged: cubit.filter,
                ),
                Text(
                  context.tr(LocaleKeys.visual_colorFilter),
                  style: FormTokens.small,
                ),
                const SizedBox(height: 8),
                _ColorOptions(
                  records: records,
                  filter: filter,
                  archived: archived,
                  onChanged: cubit.filter,
                ),
                Text(context.tr(LocaleKeys.brand), style: FormTokens.small),
                const SizedBox(height: 8),
                _TraitOptions(
                  records: records,
                  archived: archived,
                  options: (traits) => [?traits.brand],
                  selected: filter.brands,
                  label: (brand) => brand,
                  onChanged: (brands) =>
                      cubit.filter(filter.copyWith(brands: brands)),
                ),
                // Always laid out, only disabled, so the sheet keeps its
                // height when the first filter is picked.
                TextButton(
                  onPressed: filter.chipCount == 0
                      ? null
                      : () => cubit.filter(
                          filter.copyWith(
                            categories: {},
                            colors: {},
                            seasons: {},
                            brands: {},
                          ),
                        ),
                  style: TextButton.styleFrom(
                    foregroundColor: FormTokens.green,
                    disabledForegroundColor: FormTokens.toggleOff,
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(context.tr(LocaleKeys.resetFilters)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Keeps the find bar just above whichever is taller, the tab bar or the
  /// keyboard. The shell lifts the body's bottom edge to the keyboard frame
  /// by frame, so the bar follows it smoothly in both directions.
  double _findBarBottom(BuildContext context) {
    final view = View.of(context);
    final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
    if (keyboard == 0) _tabBarInset = MediaQuery.paddingOf(context).bottom;
    return math.max(_tabBarInset - keyboard, 0) + _FindBar.gap;
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<WardrobeCubit, WardrobeState>(
    builder: (context, state) {
      final cubit = context.read<WardrobeCubit>();
      final filter = state.filter;
      if (_search.text != filter.query) {
        _search.value = TextEditingValue(
          text: filter.query,
          selection: TextSelection.collapsed(offset: filter.query.length),
        );
      }
      final categoryLabels = {
        for (final c in categories) c: context.tr('categories.$c'),
      };
      final items = filter.apply(
        state.items ?? [],
        archived: archived,
        categoryLabels: categoryLabels,
      );
      final count = (state.items ?? [])
          .where((r) => (r.item.state == 'archived') == archived)
          .length;

      return Scaffold(
        backgroundColor: FormTokens.paper,
        extendBodyBehindAppBar: true,
        appBar: const FormScrollEdge(),
        body: Stack(
          children: [
            RefreshIndicator(
              edgeOffset: MediaQuery.paddingOf(context).top,
              onRefresh: cubit.refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverSafeArea(
                    left: false,
                    right: false,
                    bottom: false,
                    sliver: SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        FormTokens.gutter,
                        0,
                        FormTokens.gutter,
                        16,
                      ),
                      sliver: SliverList.list(
                        children: [
                          FormWordmark(
                            title: context.tr(LocaleKeys.appName),
                          ),
                          if (state.noticeKey case final notice?)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: FormNotice(
                                text: context.tr(notice),
                                error: state.failure != null,
                              ),
                            ),
                          _WardrobeHero(
                            archived: archived,
                            totalCount: count,
                            onAdd: archived
                                ? null
                                : () => context.push('/wardrobe/intake'),
                          ),
                          if (!archived)
                            _CollectionTabs(
                              selected: filter.state,
                              counts: {
                                'all': count,
                                for (final kind in const ['owning', 'wanting'])
                                  kind: (state.items ?? [])
                                      .where((r) => r.item.state == kind)
                                      .length,
                              },
                              options: {
                                'all': context.tr(LocaleKeys.collection_all),
                                'owning': context.tr(
                                  LocaleKeys.collection_owning,
                                ),
                                'wanting': context.tr(
                                  LocaleKeys.collection_wanting,
                                ),
                              },
                              onSelected: (value) => cubit.filter(
                                filter.copyWith(state: value),
                              ),
                            ),
                          if (filter.chipCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final category in filter.categories)
                                    _ActiveFilterChip(
                                      label: context.tr(
                                        'categories.$category',
                                      ),
                                      onRemove: () => cubit.filter(
                                        filter.copyWith(
                                          categories: {...filter.categories}
                                            ..remove(category),
                                        ),
                                      ),
                                    ),
                                  for (final color in filter.colors)
                                    _ActiveFilterChip(
                                      label: context.tr(
                                        'colorFamilies.$color',
                                      ),
                                      swatch: FormTokens.colorSwatches[color],
                                      onRemove: () => cubit.filter(
                                        filter.copyWith(
                                          colors: {...filter.colors}
                                            ..remove(color),
                                        ),
                                      ),
                                    ),
                                  for (final season in filter.seasons)
                                    _ActiveFilterChip(
                                      label: context.tr('seasons.$season'),
                                      onRemove: () => cubit.filter(
                                        filter.copyWith(
                                          seasons: {...filter.seasons}
                                            ..remove(season),
                                        ),
                                      ),
                                    ),
                                  for (final brand in filter.brands)
                                    _ActiveFilterChip(
                                      label: brand,
                                      onRemove: () => cubit.filter(
                                        filter.copyWith(
                                          brands: {...filter.brands}
                                            ..remove(brand),
                                        ),
                                      ),
                                    ),
                                  if (filter.isFiltered)
                                    TextButton(
                                      onPressed: () => cubit.filter(
                                        const WardrobeFilter(),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: FormTokens.green,
                                        minimumSize: const Size(44, 44),
                                      ),
                                      child: Text(
                                        context.tr(LocaleKeys.resetFilters),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          // The hero already states the total, so the count
                          // only appears once a filter narrows the grid.
                          if (state.items != null &&
                              items.isNotEmpty &&
                              (filter.query.isNotEmpty || filter.chipCount > 0))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 17),
                              child: Text(
                                context.tr(
                                  LocaleKeys.itemCount,
                                  namedArgs: {
                                    'shown': '${items.length}',
                                    'total': '$count',
                                  },
                                ),
                                style: FormTokens.small.merge(
                                  FormTokens.numerals.copyWith(
                                    color: FormTokens.noteInk,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FormEmptyState(
                        title: context.tr(
                          state.items == null
                              ? (state.loading
                                    ? LocaleKeys.checking
                                    : state.failureKey)
                              : filter.isFiltered
                              ? LocaleKeys.filteredEmpty
                              : LocaleKeys.wardrobeEmpty,
                        ),
                        action:
                            state.items != null &&
                                !filter.isFiltered &&
                                !archived &&
                                !state.loading
                            ? FilledButton(
                                onPressed: () =>
                                    context.push('/wardrobe/intake'),
                                child: Text(
                                  context.tr(LocaleKeys.intake_title),
                                ),
                              )
                            : null,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        FormTokens.gutter,
                        0,
                        FormTokens.gutter,
                        24,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 13,
                              mainAxisSpacing: 22,
                              childAspectRatio: 0.6,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final record = items[index];
                          final item = record.item;
                          final status = item.status.replaceAll('-', '_');
                          final category =
                              'categories.${item.metadata.category}';
                          return Semantics(
                            button: true,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => context.push(
                                  archived
                                      ? '/settings/archive/items/${item.id}'
                                      : '/wardrobe/items/${item.id}',
                                ),
                                borderRadius: BorderRadius.circular(
                                  FormTokens.cardRadius,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      FormTokens.cardRadius,
                                                    ),
                                                child: _TileMedia(
                                                  record: record,
                                                  tint: FormTokens.tileTint(
                                                    item.id,
                                                    item.metadata.colors,
                                                  ),
                                                  online: !state.stale,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.metadata.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: FormTokens.body.copyWith(
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr(category),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: FormTokens.small.copyWith(
                                        color: FormTokens.noteInk,
                                      ),
                                    ),
                                    // Generating and failed show on the tile.
                                    if (!const {
                                      'ready',
                                      'queued',
                                      'generating',
                                      'failed',
                                    }.contains(item.status))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                        ),
                                        child: Text(
                                          context.tr('itemStatus.$status'),
                                          style: FormTokens.small.copyWith(
                                            color: FormTokens.noteInk,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  // Clears the translucent tab bar and the find bar.
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height:
                          MediaQuery.paddingOf(context).bottom +
                          _FindBar.height,
                    ),
                  ),
                ],
              ),
            ),
            // While typing, a tap anywhere behind the keyboard only closes
            // it, instead of also opening the piece underneath.
            if (_searchFocus.hasFocus)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _searchFocus.unfocus,
                ),
              ),
            _FindBar(
              controller: _search,
              focusNode: _searchFocus,
              bottom: _findBarBottom(context),
              hint: context.tr(LocaleKeys.visual_searchHint),
              activeFilters: filter.chipCount,
              onChanged: (value) => cubit.filter(filter.copyWith(query: value)),
              onFilters: _openFilterSheet,
            ),
          ],
        ),
      );
    },
  );
}

/// Category or color values ([kind]) that still match items under the other
/// filters, so no chip leads to an empty grid.
Set<String> _availableOptions(
  List<CachedItem> records,
  WardrobeFilter filter,
  String kind, {
  required bool archived,
}) {
  return records
      .where((record) {
        final item = record.item;
        return (item.state == 'archived') == archived &&
            (archived || filter.state == 'all' || item.state == filter.state) &&
            filter.matchesTraits(item) &&
            (kind == 'color'
                ? filter.categories.isEmpty ||
                      filter.categories.contains(item.metadata.category)
                : filter.colors.isEmpty ||
                      item.metadata.colors.any(
                        (c) => colorFamilies(
                          c,
                        ).intersection(filter.colors).isNotEmpty,
                      ));
      })
      .expand<String>((record) {
        if (kind == 'color') {
          return record.item.metadata.colors.expand(colorFamilies);
        }
        return [record.item.metadata.category];
      })
      .toSet();
}

/// Round filter button that turns green and shows how many category and
/// color filters are on.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final int active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr(LocaleKeys.filters),
    value: active == 0 ? null : '$active',
    child: Material(
      color: active == 0 ? Colors.transparent : FormTokens.green,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: active == 0
                ? const Icon(Icons.tune, size: 21, color: FormTokens.ink)
                : Text(
                    '$active',
                    style: FormTokens.numerals.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: FormTokens.surface,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Serif headline with the tagline beneath it and the add button aligned to
/// its baseline. The archive shows its item count in place of the tagline.
class _WardrobeHero extends StatelessWidget {
  const _WardrobeHero({
    required this.archived,
    required this.totalCount,
    this.onAdd,
  });

  final bool archived;
  final int totalCount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 4, bottom: archived ? 22 : 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                archived
                    ? context.tr(LocaleKeys.archive)
                    : context.tr(LocaleKeys.visual_wardrobeHeading),
                style: FormTokens.display.copyWith(fontSize: 36),
              ),
              if (archived) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    LocaleKeys.itemCount,
                    namedArgs: {
                      'shown': '$totalCount',
                      'total': '$totalCount',
                    },
                  ),
                  style: FormTokens.body.copyWith(color: FormTokens.noteInk),
                ),
              ],
            ],
          ),
        ),
        if (onAdd != null) ...[
          const SizedBox(width: 15),
          FormAddButton(
            label: context.tr(LocaleKeys.intake_title),
            onPressed: onAdd!,
          ),
        ],
      ],
    ),
  );
}

/// Owning and Wanting as quiet text tabs under the headline, each with its
/// piece count. The active one is set in ink with a forest underline.
class _CollectionTabs extends StatelessWidget {
  const _CollectionTabs({
    required this.options,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final Map<String, String> options;
  final Map<String, int> counts;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final style = FormTokens.body.copyWith(fontSize: 15);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          for (final entry in options.entries)
            Semantics(
              button: true,
              selected: entry.key == selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (entry.key == selected) return;
                  unawaited(HapticFeedback.selectionClick());
                  onSelected(entry.key);
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: SizedBox(
                    height: 44,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Regular and semibold crossfade on top of each
                        // other. The semibold copy sizes the stack, so the
                        // weight change never reflows the row.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Stack(
                              children: [
                                AnimatedOpacity(
                                  duration: duration,
                                  curve: FormTokens.easeOut,
                                  opacity: entry.key == selected ? 1 : 0,
                                  child: Text(
                                    entry.value,
                                    style: style.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: FormTokens.ink,
                                    ),
                                  ),
                                ),
                                AnimatedOpacity(
                                  duration: duration,
                                  curve: FormTokens.easeOut,
                                  opacity: entry.key == selected ? 0 : 1,
                                  child: Text(
                                    entry.value,
                                    style: style.copyWith(
                                      color: FormTokens.noteInk,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${counts[entry.key] ?? 0}',
                              style: FormTokens.small.merge(
                                FormTokens.numerals.copyWith(
                                  color: FormTokens.noteInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        AnimatedContainer(
                          duration: duration,
                          curve: FormTokens.easeOut,
                          height: 2,
                          width: entry.key == selected ? 18 : 0,
                          decoration: BoxDecoration(
                            color: FormTokens.green,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Search and filters in the thumb zone, floating above the tab bar like
/// search in iOS's own apps. Rises with the keyboard while typing.
class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.controller,
    required this.focusNode,
    required this.bottom,
    required this.hint,
    required this.activeFilters,
    required this.onChanged,
    required this.onFilters,
  });

  /// Space the bar takes above the tab bar, for content to clear.
  static const double height = 48 + 2 * gap;
  static const gap = 10.0;

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Distance from the body's bottom edge, see `_findBarBottom`.
  final double bottom;
  final String hint;
  final int activeFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 14,
      right: 14,
      bottom: bottom,
      child: Row(
        children: [
          Expanded(
            child: _Frosted(
              radius: FormTokens.chipRadius,
              child: SizedBox(
                height: 48,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    style: FormTokens.body.copyWith(fontSize: 16),
                    cursorColor: FormTokens.green,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: FormTokens.body.copyWith(
                        fontSize: 16,
                        color: FormTokens.noteInk,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 20,
                        color: FormTokens.ink,
                      ),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).deleteButtonTooltip,
                              onPressed: () {
                                controller.clear();
                                onChanged('');
                              },
                              icon: const Icon(
                                Icons.cancel,
                                size: 18,
                                color: FormTokens.muted,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Frosted(
            radius: 24,
            child: _FilterButton(active: activeFilters, onTap: onFilters),
          ),
        ],
      ),
    );
  }
}

/// Frosted paper like the tab bar, lifted off the grid it floats over.
class _Frosted extends StatelessWidget {
  const _Frosted({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x141D281C),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FormTokens.paper.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: FormTokens.line),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Every category in the collection. Ones that no item matches under the
/// color filter stay in place, dimmed, so picking a filter never reflows the
/// chips.
class _CategoryOptions extends StatelessWidget {
  const _CategoryOptions({
    required this.records,
    required this.filter,
    required this.archived,
    required this.onChanged,
  });

  final List<CachedItem> records;
  final WardrobeFilter filter;
  final bool archived;
  final ValueChanged<WardrobeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = _availableOptions(
      records,
      filter.copyWith(colors: {}),
      'category',
      archived: archived,
    );
    final matching = _availableOptions(
      records,
      filter,
      'category',
      archived: archived,
    );
    return _FilterOptionWrap(
      children: [
        for (final category in categories)
          if (shown.contains(category) || filter.categories.contains(category))
            _WardrobeFilterChip(
              label: context.tr('categories.$category'),
              selected: filter.categories.contains(category),
              enabled:
                  matching.contains(category) ||
                  filter.categories.contains(category),
              onTap: () => onChanged(
                filter.copyWith(
                  categories: {...filter.categories}
                    ..toggle(
                      category,
                      selected: !filter.categories.contains(category),
                    ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Every color family in the collection, dimmed like [_CategoryOptions]
/// when the category filter leaves no match.
class _ColorOptions extends StatelessWidget {
  const _ColorOptions({
    required this.records,
    required this.filter,
    required this.archived,
    required this.onChanged,
  });

  final List<CachedItem> records;
  final WardrobeFilter filter;
  final bool archived;
  final ValueChanged<WardrobeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = _availableOptions(
      records,
      filter.copyWith(categories: {}),
      'color',
      archived: archived,
    );
    final matching = _availableOptions(
      records,
      filter,
      'color',
      archived: archived,
    );
    return _FilterOptionWrap(
      children: [
        for (final color in colorPatterns.keys)
          if (shown.contains(color) || filter.colors.contains(color))
            _WardrobeFilterChip(
              label: context.tr('colorFamilies.$color'),
              swatch: FormTokens.colorSwatches[color],
              selected: filter.colors.contains(color),
              enabled:
                  matching.contains(color) || filter.colors.contains(color),
              onTap: () => onChanged(
                filter.copyWith(
                  colors: {...filter.colors}
                    ..toggle(color, selected: !filter.colors.contains(color)),
                ),
              ),
            ),
      ],
    );
  }
}

/// Season or brand chips for the values present among tagged pieces.
/// Untagged pieces contribute nothing here but still show under every filter.
class _TraitOptions extends StatelessWidget {
  const _TraitOptions({
    required this.records,
    required this.archived,
    required this.options,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.order,
  });

  final List<CachedItem> records;
  final bool archived;
  final Iterable<String> Function(ItemTraits traits) options;
  final Set<String> selected;
  final String Function(String value) label;
  final ValueChanged<Set<String>> onChanged;

  /// Fixed display order. Alphabetical when null.
  final List<String>? order;

  @override
  Widget build(BuildContext context) {
    final present = {
      for (final record in records)
        if ((record.item.state == 'archived') == archived)
          if (record.item.traits case final traits?) ...options(traits),
      ...selected,
    };
    final values =
        order?.where(present.contains).toList() ?? (present.toList()..sort());
    if (values.isEmpty) return const SizedBox(height: 16);
    return _FilterOptionWrap(
      children: [
        for (final value in values)
          _WardrobeFilterChip(
            label: label(value),
            selected: selected.contains(value),
            onTap: () => onChanged(
              {...selected}..toggle(value, selected: !selected.contains(value)),
            ),
          ),
      ],
    );
  }
}

class _FilterOptionWrap extends StatelessWidget {
  const _FilterOptionWrap({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );
}

class _WardrobeFilterChip extends StatelessWidget {
  const _WardrobeFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.swatch,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? swatch;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final background = selected ? FormTokens.green : FormTokens.surface;
    final foreground = selected ? FormTokens.surface : FormTokens.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.4,
        duration: FormTokens.quick,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FormTokens.chipRadius),
            side: BorderSide(
              color: selected ? FormTokens.green : FormTokens.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (swatch != null) ...[
                    ExcludeSemantics(child: _ColorSwatch(color: swatch!)),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: FormTokens.body.copyWith(
                      fontSize: 13,
                      color: foreground,
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
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.label,
    required this.onRemove,
    this.swatch,
  });

  final String label;
  final VoidCallback onRemove;
  final Color? swatch;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: FormTokens.field,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormTokens.chipRadius),
        side: const BorderSide(color: FormTokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swatch != null) ...[
                ExcludeSemantics(child: _ColorSwatch(color: swatch!)),
                const SizedBox(width: 7),
              ],
              Text(label, style: FormTokens.body.copyWith(fontSize: 13)),
              const SizedBox(width: 7),
              const Icon(Icons.close, size: 16, color: FormTokens.noteInk),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x1F4D5545)),
      boxShadow: const [
        BoxShadow(color: Color(0x4DFFFFFF), spreadRadius: -1),
      ],
    ),
  );
}

/// The grid tile's image area. Crossfades from the ripple to the image, which
/// fades in again once its first frame decodes.
class _TileMedia extends StatelessWidget {
  const _TileMedia({
    required this.record,
    required this.tint,
    required this.online,
  });

  final CachedItem record;
  final Color tint;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final item = record.item;
    final status = item.status.replaceAll('-', '_');
    final generating = const {'queued', 'generating'}.contains(item.status);
    return ColoredBox(
      color: tint,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: FormTokens.easeOut,
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, ?current],
            ),
            child: generating
                ? _GeneratingTile(
                    key: const ValueKey('generating'),
                    label: context.tr('itemStatus.$status'),
                  )
                : CachedMedia(
                    key: const ValueKey('image'),
                    identity: record.thumbnailIdentity,
                    previewPath: record.thumbnailPath,
                    online: online,
                    entrance: MediaEntrance.fade,
                  ),
          ),
          if (item.status == 'failed')
            Positioned(
              left: 8,
              bottom: 8,
              child: _StatusBadge(label: context.tr('itemStatus.$status')),
            ),
        ],
      ),
    );
  }
}

/// Placeholder while the catalog image is generated: soft rings ripple out
/// from the centre. Holds still when the system asks for reduced motion.
class _GeneratingTile extends StatefulWidget {
  const _GeneratingTile({required this.label, super.key});
  final String label;

  @override
  State<_GeneratingTile> createState() => _GeneratingTileState();
}

class _GeneratingTileState extends State<_GeneratingTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.35;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEEF0EA), Color(0xFFE2E6DE)],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _RipplePainter(_controller)),
        Align(
          alignment: const Alignment(0, 0.55),
          child: Text(
            widget.label,
            style: FormTokens.small.copyWith(color: FormTokens.noteInk),
          ),
        ),
      ],
    ),
  );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.progress) : super(repaint: progress);
  final Animation<double> progress;

  static const _rings = 3;
  static const _color = Color(0xFF78906E);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide * 0.42;
    for (var i = 0; i < _rings; i++) {
      final t = (progress.value + i / _rings) % 1;
      final eased = Curves.easeOutCubic.transform(t);
      final opacity = (1 - t) * (1 - t) * 0.5;
      canvas
        ..drawCircle(
          center,
          maxRadius * eased,
          Paint()..color = _color.withValues(alpha: opacity * 0.18),
        )
        ..drawCircle(
          center,
          maxRadius * eased,
          Paint()
            ..color = _color.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
    }
    canvas.drawCircle(
      center,
      4,
      Paint()..color = _color.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xCCFFFFFF),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: FormTokens.small.copyWith(
          fontSize: 10,
          color: FormTokens.ink,
        ),
      ),
    ),
  );
}

extension on Set<String> {
  void toggle(String value, {required bool selected}) {
    if (selected) {
      add(value);
    } else {
      remove(value);
    }
  }
}
