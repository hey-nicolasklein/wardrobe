import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_info.dart';
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
  String? _expandedFilter;
  bool _searchExpanded = false;

  bool get archived => widget.archived;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Color _photoTint(String id) {
    var sum = 0;
    for (final code in id.codeUnits) {
      sum = (sum + code) % 3;
    }
    return switch (sum) {
      1 => const Color(0xFFEBE7E0),
      2 => const Color(0xFFE5E9E6),
      _ => FormTokens.field,
    };
  }

  Set<String> _availableOptions(
    List<CachedItem> records,
    WardrobeFilter filter,
    String kind,
  ) {
    return records
        .where((record) {
          final item = record.item;
          return (item.state == 'archived') == archived &&
              (archived ||
                  filter.state == 'all' ||
                  item.state == filter.state) &&
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
      if (filter.query.isNotEmpty) {
        _searchExpanded = true;
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
      final records = state.items ?? [];
      final availableCategories = _availableOptions(
        records,
        filter,
        'category',
      );
      final availableColors = _availableOptions(records, filter, 'color');
      final colorFilterLabel = context.tr(LocaleKeys.visual_colorFilter);

      return Scaffold(
        backgroundColor: FormTokens.paper,
        extendBodyBehindAppBar: true,
        appBar: const FormScrollEdge(),
        body: Builder(
          builder: (context) => RefreshIndicator(
            edgeOffset: MediaQuery.paddingOf(context).top,
            onRefresh: cubit.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                          action: Text(
                            '${AppInfo.version} (${AppInfo.buildNumber})',
                            style: FormTokens.small.copyWith(
                              color: FormTokens.muted,
                            ),
                          ),
                        ),
                        if (state.loading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(
                              color: FormTokens.green,
                              backgroundColor: FormTokens.line,
                            ),
                          ),
                        if (state.stale && state.items != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FormNotice(
                              text: context.tr(LocaleKeys.wardrobeStale),
                            ),
                          ),
                        if (state.failure != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FormNotice(
                              text: context.tr(state.failureKey),
                              error: true,
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
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: FormChoiceChips(
                              options: {
                                'all': context.tr(LocaleKeys.collection_all),
                                'owning': context.tr(
                                  LocaleKeys.collection_owning,
                                ),
                                'wanting': context.tr(
                                  LocaleKeys.collection_wanting,
                                ),
                              },
                              selected: filter.state,
                              onSelected: (value) =>
                                  cubit.filter(filter.copyWith(state: value)),
                            ),
                          ),
                        _WardrobeFilterBar(
                          categoryLabel:
                              context.tr(LocaleKeys.category) +
                              (filter.categories.isEmpty
                                  ? ''
                                  : ' · ${filter.categories.length}'),
                          colorLabel:
                              colorFilterLabel +
                              (filter.colors.isEmpty
                                  ? ''
                                  : ' · ${filter.colors.length}'),
                          categoryExpanded: _expandedFilter == 'category',
                          colorExpanded: _expandedFilter == 'color',
                          searchExpanded:
                              _searchExpanded || filter.query.isNotEmpty,
                          onCategory: () => setState(
                            () =>
                                _expandedFilter = _expandedFilter == 'category'
                                ? null
                                : 'category',
                          ),
                          onColor: () => setState(
                            () => _expandedFilter = _expandedFilter == 'color'
                                ? null
                                : 'color',
                          ),
                          onToggleSearch: () => setState(() {
                            _searchExpanded =
                                !(_searchExpanded || filter.query.isNotEmpty);
                            if (!_searchExpanded) {
                              cubit.filter(filter.copyWith(query: ''));
                            }
                          }),
                        ),
                        if (_expandedFilter == 'category')
                          _FilterOptionWrap(
                            children: [
                              for (final category in categories)
                                if (availableCategories.contains(category))
                                  _WardrobeFilterChip(
                                    label: context.tr('categories.$category'),
                                    selected: filter.categories.contains(
                                      category,
                                    ),
                                    onTap: () => cubit.filter(
                                      filter.copyWith(
                                        categories: {...filter.categories}
                                          ..toggle(
                                            category,
                                            selected: !filter.categories
                                                .contains(
                                                  category,
                                                ),
                                          ),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        if (_expandedFilter == 'color')
                          _FilterOptionWrap(
                            children: [
                              for (final color in colorPatterns.keys)
                                if (availableColors.contains(color))
                                  _WardrobeFilterChip(
                                    label: context.tr('colorFamilies.$color'),
                                    swatch: FormTokens.colorSwatches[color],
                                    selected: filter.colors.contains(color),
                                    onTap: () => cubit.filter(
                                      filter.copyWith(
                                        colors: {...filter.colors}
                                          ..toggle(
                                            color,
                                            selected: !filter.colors.contains(
                                              color,
                                            ),
                                          ),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        if (_searchExpanded || filter.query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: FormSearchField(
                              controller: _search,
                              hint: context.tr(LocaleKeys.visual_searchHint),
                              onChanged: (value) =>
                                  cubit.filter(filter.copyWith(query: value)),
                              onClear: () =>
                                  cubit.filter(filter.copyWith(query: '')),
                            ),
                          ),
                        if (filter.categories.isNotEmpty ||
                            filter.colors.isNotEmpty ||
                            filter.query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final category in filter.categories)
                                  _ActiveFilterChip(
                                    label: context.tr('categories.$category'),
                                    onRemove: () => cubit.filter(
                                      filter.copyWith(
                                        categories: {...filter.categories}
                                          ..remove(category),
                                      ),
                                    ),
                                  ),
                                for (final color in filter.colors)
                                  _ActiveFilterChip(
                                    label: context.tr('colorFamilies.$color'),
                                    swatch: FormTokens.colorSwatches[color],
                                    onRemove: () => cubit.filter(
                                      filter.copyWith(
                                        colors: {...filter.colors}
                                          ..remove(color),
                                      ),
                                    ),
                                  ),
                                if (filter.isFiltered)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _searchExpanded = false;
                                        _expandedFilter = null;
                                      });
                                      cubit.filter(const WardrobeFilter());
                                    },
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
                        if (state.items != null && items.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 17),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    context.tr(
                                      LocaleKeys.itemCount,
                                      namedArgs: {
                                        'shown': '${items.length}',
                                        'total': '$count',
                                      },
                                    ),
                                    style: FormTokens.small.merge(
                                      FormTokens.numerals,
                                    ),
                                  ),
                                ),
                                Text(
                                  context.tr(LocaleKeys.visual_recentFirst),
                                  style: FormTokens.small,
                                ),
                              ],
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
                              onPressed: () => context.push('/wardrobe/intake'),
                              child: Text(context.tr(LocaleKeys.intake_title)),
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
                            childAspectRatio: 0.54,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final record = items[index];
                        final item = record.item;
                        final status = item.status.replaceAll('-', '_');
                        final generating = const {
                          'queued',
                          'generating',
                        }.contains(item.status);
                        final failed = item.status == 'failed';
                        return Material(
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 3 / 4,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        FormTokens.cardRadius,
                                      ),
                                      child: ColoredBox(
                                        color: _photoTint(item.id),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (!generating)
                                              CachedMedia(
                                                identity:
                                                    record.thumbnailIdentity,
                                                previewPath:
                                                    record.thumbnailPath,
                                                online: !state.stale,
                                              ),
                                            if (generating)
                                              _GeneratingTile(
                                                label: context.tr(
                                                  'itemStatus.$status',
                                                ),
                                              ),
                                            if (failed)
                                              Positioned(
                                                left: 8,
                                                bottom: 8,
                                                child: _StatusBadge(
                                                  label: context.tr(
                                                    'itemStatus.$status',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 14 * 1.35 * 2,
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      item.metadata.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: FormTokens.body.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr(
                                    'categories.${item.metadata.category}',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FormTokens.small.copyWith(
                                    fontSize: 11,
                                  ),
                                ),
                                if (item.status != 'ready' &&
                                    !generating &&
                                    !failed)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      context.tr('itemStatus.$status'),
                                      style: FormTokens.small.copyWith(
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                // Clears the translucent tab bar.
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

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
  Widget build(BuildContext context) => FormHero(
    eyebrow: archived
        ? context.tr(LocaleKeys.archive)
        : context.tr(LocaleKeys.visual_wardrobeEyebrow),
    title: archived
        ? context.tr(LocaleKeys.archive)
        : context.tr(LocaleKeys.visual_wardrobeHeading),
    body: archived
        ? context.tr(
            LocaleKeys.itemCount,
            namedArgs: {'shown': '$totalCount', 'total': '$totalCount'},
          )
        : context.tr(
            LocaleKeys.visual_collectedCount,
            namedArgs: {'count': '$totalCount'},
          ),
    addLabel: context.tr(LocaleKeys.intake_title),
    onAdd: onAdd,
  );
}

class _WardrobeFilterBar extends StatelessWidget {
  const _WardrobeFilterBar({
    required this.categoryLabel,
    required this.colorLabel,
    required this.categoryExpanded,
    required this.colorExpanded,
    required this.searchExpanded,
    required this.onCategory,
    required this.onColor,
    required this.onToggleSearch,
  });

  final String categoryLabel;
  final String colorLabel;
  final bool categoryExpanded;
  final bool colorExpanded;
  final bool searchExpanded;
  final VoidCallback onCategory;
  final VoidCallback onColor;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        _WardrobeFilterChip(
          label: '$categoryLabel ${categoryExpanded ? '▴' : '▾'}',
          selected: categoryExpanded,
          onTap: onCategory,
        ),
        const SizedBox(width: 8),
        _WardrobeFilterChip(
          label: '$colorLabel ${colorExpanded ? '▴' : '▾'}',
          selected: colorExpanded,
          onTap: onColor,
        ),
        const Spacer(),
        Semantics(
          button: true,
          selected: searchExpanded,
          label: context.tr(LocaleKeys.visual_searchHint),
          child: Material(
            color: FormTokens.green,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggleSearch,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  searchExpanded ? Icons.close : Icons.search,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final background = selected ? FormTokens.green : FormTokens.surface;
    final foreground = selected ? Colors.white : FormTokens.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swatch != null) ...[
                ExcludeSemantics(child: _ColorSwatch(color: swatch!)),
                const SizedBox(width: 7),
              ],
              Text(label, style: FormTokens.body.copyWith(fontSize: 13)),
              const SizedBox(width: 7),
              const Icon(Icons.close, size: 14, color: FormTokens.muted),
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

class _GeneratingTile extends StatelessWidget {
  const _GeneratingTile({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEEF0EA), Color(0xFFE2E6DE)],
      ),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF78906E),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, style: FormTokens.small.copyWith(fontSize: 11)),
        ],
      ),
    ),
  );
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
