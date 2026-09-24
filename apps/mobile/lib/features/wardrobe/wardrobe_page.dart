import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:go_router/go_router.dart';

class WardrobePage extends StatefulWidget {
  const WardrobePage({this.archived = false, super.key});
  final bool archived;

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  final _search = TextEditingController();
  bool get archived => widget.archived;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      final items = filter.apply(
        state.items ?? [],
        archived: archived,
        categoryLabels: {
          for (final c in categories) c: context.tr('categories.$c'),
        },
      );
      final count = (state.items ?? [])
          .where((r) => (r.item.state == 'archived') == archived)
          .length;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            context.tr(archived ? LocaleKeys.archive : LocaleKeys.wardrobe),
          ),
          actions: [
            IconButton(
              tooltip: context.tr(LocaleKeys.refresh),
              onPressed: cubit.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: cubit.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.list(
                  children: [
                    if (state.loading) const LinearProgressIndicator(),
                    if (state.stale)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(context.tr(LocaleKeys.wardrobeStale)),
                      ),
                    if (state.failure != null)
                      Text(context.tr(LocaleKeys.wardrobeRefreshFailed)),
                    Text(
                      context.tr(
                        LocaleKeys.itemCount,
                        namedArgs: {
                          'shown': '${items.length}',
                          'total': '$count',
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _search,
                      decoration: InputDecoration(
                        labelText: context.tr(LocaleKeys.search),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: filter.query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () =>
                                    cubit.filter(filter.copyWith(query: '')),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      onChanged: (value) =>
                          cubit.filter(filter.copyWith(query: value)),
                    ),
                    if (!archived)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SegmentedButton<String>(
                          segments: [
                            for (final value in ['all', 'owning', 'wanting'])
                              ButtonSegment(
                                value: value,
                                label: Text(context.tr('collection.$value')),
                              ),
                          ],
                          selected: {filter.state},
                          onSelectionChanged: (values) => cubit.filter(
                            filter.copyWith(state: values.single),
                          ),
                        ),
                      ),
                    ExpansionTile(
                      title: Text(context.tr(LocaleKeys.filters)),
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final category in categories)
                              FilterChip(
                                label: Text(context.tr('categories.$category')),
                                selected: filter.categories.contains(category),
                                onSelected: (selected) => cubit.filter(
                                  filter.copyWith(
                                    categories: {...filter.categories}
                                      ..toggle(category, selected: selected),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final color in colorPatterns.keys)
                              FilterChip(
                                label: Text(context.tr('colorFamilies.$color')),
                                selected: filter.colors.contains(color),
                                onSelected: (selected) => cubit.filter(
                                  filter.copyWith(
                                    colors: {...filter.colors}
                                      ..toggle(color, selected: selected),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final category in filter.categories)
                          InputChip(
                            label: Text(context.tr('categories.$category')),
                            onDeleted: () => cubit.filter(
                              filter.copyWith(
                                categories: {...filter.categories}
                                  ..remove(category),
                              ),
                            ),
                          ),
                        for (final color in filter.colors)
                          InputChip(
                            label: Text(context.tr('colorFamilies.$color')),
                            onDeleted: () => cubit.filter(
                              filter.copyWith(
                                colors: {...filter.colors}..remove(color),
                              ),
                            ),
                          ),
                        if (filter.isFiltered)
                          ActionChip(
                            label: Text(context.tr(LocaleKeys.resetFilters)),
                            onPressed: () =>
                                cubit.filter(const WardrobeFilter()),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      context.tr(
                        state.items == null
                            ? (state.loading
                                  ? LocaleKeys.checking
                                  : LocaleKeys.unavailable)
                            : filter.isFiltered
                            ? LocaleKeys.filteredEmpty
                            : LocaleKeys.wardrobeEmpty,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          childAspectRatio: .68,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final record = items[index];
                      final status = record.item.status.replaceAll('-', '_');
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => context.push(
                            archived
                                ? '/settings/archive/items/${record.item.id}'
                                : '/wardrobe/items/${record.item.id}',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: CachedMedia(
                                  identity: record.thumbnailIdentity,
                                  previewPath: record.thumbnailPath,
                                  online: !state.stale,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.item.metadata.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      context.tr(
                                        'collection.${record.item.state}',
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                    if (record.item.status != 'ready')
                                      Text(
                                        context.tr(
                                          'itemStatus.$status',
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
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
