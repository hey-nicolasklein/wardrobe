import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/features/wardrobe/item_cubit.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:go_router/go_router.dart';

class ItemPage extends StatelessWidget {
  const ItemPage({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = ItemCubit(context.read<WardrobeRepository>(), id);
      unawaited(
        cubit.load(
          online:
              context.read<ConnectionCubit>().state == ConnectionStatus.ready,
        ),
      );
      return cubit;
    },
    child: const _ItemView(),
  );
}

class _ItemView extends StatefulWidget {
  const _ItemView();
  @override
  State<_ItemView> createState() => _ItemViewState();
}

class _ItemViewState extends State<_ItemView> {
  late final AppLifecycleListener _lifecycle;
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => context.read<ItemCubit>().setForeground(
        foreground: state == AppLifecycleState.resumed,
      ),
      onResume: () {
        if (context.read<ConnectionCubit>().state == ConnectionStatus.ready) {
          unawaited(context.read<ItemCubit>().refresh());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocListener<ConnectionCubit, ConnectionStatus>(
    listener: (context, status) {
      final cubit = context.read<ItemCubit>();
      if (status == ConnectionStatus.ready) {
        unawaited(cubit.refresh());
      } else if (status != ConnectionStatus.checking) {
        cubit.markUnavailable();
      }
    },
    child: BlocConsumer<ItemCubit, ItemState>(
      listener: (context, state) {
        if (state.deleted) context.pop();
      },
      builder: (context, state) {
        final cubit = context.read<ItemCubit>();
        final detail = state.detail;
        final online =
            context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
        final enabled = online && state.canStartCommand;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              detail?.wardrobeItem.metadata.name ??
                  context.tr(LocaleKeys.itemDetails),
            ),
            actions: [
              IconButton(
                tooltip: context.tr(LocaleKeys.refresh),
                onPressed: state.busy ? null : cubit.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: detail == null
              ? Center(
                  child: state.busy
                      ? const CircularProgressIndicator.adaptive()
                      : Text(context.tr(LocaleKeys.unavailable)),
                )
              : RefreshIndicator(
                  onRefresh: cubit.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (state.busy) const LinearProgressIndicator(),
                      if (state.stale || !online)
                        Text(context.tr(LocaleKeys.wardrobeStale)),
                      if (state.failure != null)
                        Text(context.tr(LocaleKeys.itemActionFailed)),
                      if (state.pending != null && !state.busy)
                        FilledButton.tonal(
                          onPressed: online && state.canMutate
                              ? () => cubit.execute(state.pending!)
                              : null,
                          child: Text(context.tr(LocaleKeys.retryCommand)),
                        ),
                      if (detail.currentImage != null)
                        SizedBox(
                          height: 320,
                          child: CachedMedia(
                            identity: detail.currentImage!.transparentAssetId,
                            online: online && !state.stale,
                          ),
                        ),
                      Text(
                        context.tr(
                          'categories.${detail.wardrobeItem.metadata.category}',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(detail.wardrobeItem.metadata.colors.join(', ')),
                      Text(
                        context.tr('collection.${detail.wardrobeItem.state}'),
                      ),
                      if (detail.wardrobeItem.metadata.notes != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(detail.wardrobeItem.metadata.notes!),
                        ),
                      Text(
                        context.tr(
                          'itemStatus.'
                          "${detail.wardrobeItem.status.replaceAll('-', '_')}",
                        ),
                      ),
                      if (detail.generating)
                        ListTile(
                          leading: const CircularProgressIndicator.adaptive(),
                          title: Text(context.tr(LocaleKeys.generationRunning)),
                          subtitle: Text(
                            context.tr(LocaleKeys.generationRefresh),
                          ),
                        ),
                      if (detail.generationAttempts.firstOrNull?.state ==
                          'failed')
                        Text(context.tr(LocaleKeys.generationFailed)),
                      FilledButton.tonal(
                        onPressed: enabled
                            ? () async {
                                final changes =
                                    await showModalBottomSheet<ItemEdit>(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      builder: (_) =>
                                          _EditItem(item: detail.wardrobeItem),
                                    );
                                if (changes != null && context.mounted) {
                                  await cubit.edit(changes);
                                }
                              }
                            : null,
                        child: Text(context.tr(LocaleKeys.editItem)),
                      ),
                      FilledButton(
                        onPressed: online && state.canGenerate
                            ? () async {
                                final command =
                                    await showModalBottomSheet<ItemCommand>(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      builder: (_) =>
                                          _GenerateItem(detail: detail),
                                    );
                                if (command != null && context.mounted) {
                                  await cubit.execute(command);
                                }
                              }
                            : null,
                        child: Text(
                          context.tr(
                            detail.currentImage == null
                                ? LocaleKeys.generateImage
                                : LocaleKeys.improveImage,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr(LocaleKeys.sourcePhoto),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(
                        height: 280,
                        child: CachedMedia(
                          identity: detail.sourcePhoto.assetId,
                          online: online && !state.stale,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr(LocaleKeys.imageVersions),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final version in detail.shelfImageVersions)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 180,
                                  child: CachedMedia(
                                    identity: version.transparentAssetId,
                                    online: online && !state.stale,
                                  ),
                                ),
                                Text(
                                  [
                                    DateFormat.yMMMd(
                                      context.locale.languageCode,
                                    ).format(version.keptAt),
                                    context.tr('quality.${version.quality}'),
                                  ].join(' · '),
                                ),
                                TextButton(
                                  onPressed:
                                      online && state.canRestore(version.id)
                                      ? () => cubit.restore(version.id)
                                      : null,
                                  child: Text(
                                    context.tr(
                                      version.id ==
                                              detail
                                                  .wardrobeItem
                                                  .currentShelfImageVersionId
                                          ? LocaleKeys.currentImage
                                          : LocaleKeys.restoreImage,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(),
                      if (detail.wardrobeItem.state == 'archived') ...[
                        for (final target in ['owning', 'wanting'])
                          TextButton(
                            onPressed: enabled
                                ? () => cubit.move(target)
                                : null,
                            child: Text(
                              context.tr(
                                LocaleKeys.restoreTo,
                                namedArgs: {
                                  'state': context.tr('collection.$target'),
                                },
                              ),
                            ),
                          ),
                      ] else
                        TextButton(
                          onPressed: enabled
                              ? () => cubit.move('archived')
                              : null,
                          child: Text(context.tr(LocaleKeys.archiveItem)),
                        ),
                      TextButton(
                        onPressed: enabled
                            ? () async {
                                final confirmed =
                                    await showAdaptiveDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) =>
                                          AlertDialog.adaptive(
                                            title: Text(
                                              context.tr(LocaleKeys.deleteItem),
                                            ),
                                            content: Text(
                                              context.tr(
                                                LocaleKeys.deleteItemConfirm,
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    dialogContext.pop(false),
                                                child: Text(
                                                  context.tr(LocaleKeys.cancel),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    dialogContext.pop(true),
                                                child: Text(
                                                  context.tr(
                                                    LocaleKeys.deleteItem,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                    );
                                if ((confirmed ?? false) && context.mounted) {
                                  await cubit.delete();
                                }
                              }
                            : null,
                        child: Text(context.tr(LocaleKeys.deleteItem)),
                      ),
                    ],
                  ),
                ),
        );
      },
    ),
  );
}

class _EditItem extends StatefulWidget {
  const _EditItem({required this.item});
  final WardrobeItem item;
  @override
  State<_EditItem> createState() => _EditItemState();
}

class _EditItemState extends State<_EditItem> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item.metadata.name);
  late final _colors = TextEditingController(
    text: widget.item.metadata.colors.join(', '),
  );
  late final _notes = TextEditingController(text: widget.item.metadata.notes);
  late String? _category =
      supportedCategories.contains(widget.item.metadata.category)
      ? widget.item.metadata.category
      : null;
  late String _state = widget.item.state;
  @override
  void dispose() {
    _name.dispose();
    _colors.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(LocaleKeys.editItem),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextFormField(
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.itemName),
              ),
              validator: (v) => !ItemMetadata.validName(v ?? '')
                  ? context.tr(LocaleKeys.requiredField)
                  : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _category,
              validator: (value) => value == null
                  ? context.tr(LocaleKeys.chooseSupportedCategory)
                  : null,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.category),
              ),
              items: [
                for (final c in supportedCategories)
                  DropdownMenuItem(
                    value: c,
                    child: Text(context.tr('categories.$c')),
                  ),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            TextFormField(
              controller: _colors,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.itemColors),
              ),
              validator: (v) => ItemEdit.validColors(v ?? '')
                  ? null
                  : context.tr(LocaleKeys.invalidColors),
            ),
            TextFormField(
              controller: _notes,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.notes),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _state,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.collectionState),
              ),
              items: [
                for (final s in itemStates)
                  DropdownMenuItem(
                    value: s,
                    child: Text(context.tr('collection.$s')),
                  ),
              ],
              onChanged: (v) => setState(() => _state = v!),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  context.pop(
                    ItemEdit(
                      name: _name.text,
                      category: _category!,
                      colors: _colors.text,
                      notes: _notes.text,
                      state: _state,
                    ),
                  );
                }
              },
              child: Text(context.tr(LocaleKeys.save)),
            ),
            TextButton(
              onPressed: () => context.pop(),
              child: Text(context.tr(LocaleKeys.cancel)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GenerateItem extends StatefulWidget {
  const _GenerateItem({required this.detail});
  final ItemDetail detail;
  @override
  State<_GenerateItem> createState() => _GenerateItemState();
}

class _GenerateItemState extends State<_GenerateItem> {
  String _quality = 'low';
  final _feedback = TextEditingController();
  final Set<String> _suggestions = {};
  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.tr(LocaleKeys.generationExplanation)),
          if (widget.detail.currentImage != null) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final suggestion in ['proportions', 'color', 'details'])
                  FilterChip(
                    label: Text(context.tr('feedback.$suggestion')),
                    selected: _suggestions.contains(suggestion),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _suggestions.add(suggestion);
                      } else {
                        _suggestions.remove(suggestion);
                      }
                    }),
                  ),
              ],
            ),
            TextField(
              controller: _feedback,
              maxLength: 800,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.customFeedback),
              ),
            ),
          ],
          SegmentedButton<String>(
            segments: [
              for (final quality in qualities)
                ButtonSegment(
                  value: quality,
                  label: Text(context.tr('quality.$quality')),
                ),
            ],
            selected: {_quality},
            onSelectionChanged: (v) => setState(() => _quality = v.single),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final feedback = [
                ..._suggestions.map((s) => context.tr('feedback.$s')),
                if (_feedback.text.trim().isNotEmpty) _feedback.text.trim(),
              ].join('. ');
              context.pop(
                ItemCommand.generate(
                  widget.detail.wardrobeItem.id,
                  _quality,
                  feedback.isEmpty ? null : feedback,
                ),
              );
            },
            child: Text(context.tr(LocaleKeys.requestPaidImage)),
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: Text(context.tr(LocaleKeys.cancel)),
          ),
        ],
      ),
    ),
  );
}
