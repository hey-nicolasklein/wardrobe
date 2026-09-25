import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/features/wardrobe/item_cubit.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
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

  Future<void> _openEdit(
    BuildContext context,
    ItemCubit cubit,
    WardrobeItem item,
  ) async {
    final changes = await showFormSheet<ItemEdit>(
      context: context,
      builder: (sheetContext) => FormSheet(
        title: context.tr(LocaleKeys.editItem),
        child: _EditItem(item: item),
      ),
    );
    if (changes != null && context.mounted) {
      await cubit.edit(changes);
    }
  }

  Future<void> _openGenerate(
    BuildContext context,
    ItemCubit cubit,
    ItemDetail detail,
  ) async {
    final hasShelf = detail.currentImage != null;
    final command = await showFormSheet<ItemCommand>(
      context: context,
      builder: (sheetContext) => FormSheet(
        title: context.tr(
          hasShelf ? LocaleKeys.improveImage : LocaleKeys.generateImage,
        ),
        child: _GenerateItem(detail: detail),
      ),
    );
    if (command != null && context.mounted) {
      await cubit.execute(command);
    }
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
        final title = context.tr(LocaleKeys.itemDetails);
        return Scaffold(
          backgroundColor: FormTokens.paper,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(title),
            actions: [
              IconButton(
                onPressed: () => context.pop(),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                style: IconButton.styleFrom(
                  backgroundColor: FormTokens.field,
                ),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: detail == null
              ? Center(
                  child: state.busy
                      ? const CircularProgressIndicator(color: FormTokens.green)
                      : Text(
                          context.tr(LocaleKeys.unavailable),
                          style: FormTokens.body,
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    FormTokens.gutter,
                    8,
                    FormTokens.gutter,
                    32,
                  ),
                  children: [
                    if (state.stale || !online)
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
                          text: context.tr(LocaleKeys.itemActionFailed),
                          error: true,
                        ),
                      ),
                    if (state.pending != null && !state.busy)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FilledButton.tonal(
                          onPressed: online && state.canMutate
                              ? () => cubit.execute(state.pending!)
                              : null,
                          child: Text(context.tr(LocaleKeys.retryCommand)),
                        ),
                      ),
                    // Keyed so notices appearing above it after a refresh do
                    // not rebuild the gallery and replay its image entrances.
                    BlocBuilder<FeedCubit, FeedState>(
                      key: const ValueKey('gallery'),
                      builder: (context, feedState) => _ItemGallery(
                        detail: detail,
                        looks: readyLooksForItem(
                          detail.wardrobeItem.id,
                          (feedState.looks ?? []).map(
                            (record) => record.look,
                          ),
                        ),
                        online: online && !state.stale,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.tr(
                        'categories.${detail.wardrobeItem.metadata.category}',
                      ),
                      style: FormTokens.eyebrow,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail.wardrobeItem.metadata.name,
                      style: FormTokens.heading,
                    ),
                    if (detail.wardrobeItem.metadata.colors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final color
                                in detail.wardrobeItem.metadata.colors)
                              _ItemColorSwatch(label: color),
                          ],
                        ),
                      ),
                    if (detail.wardrobeItem.status != 'ready')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          context.tr(
                            'itemStatus.'
                            '${detail.wardrobeItem.status.replaceAll(
                              '-',
                              '_',
                            )}',
                          ),
                          style: FormTokens.small,
                        ),
                      ),
                    const SizedBox(height: 18),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail.wardrobeItem.state == 'archived')
                          _FactRow(
                            label: context.tr(LocaleKeys.collectionState),
                            value: context.tr('collection.archived'),
                          )
                        else
                          FormCollectionToggle(
                            selected: detail.wardrobeItem.state,
                            labels: {
                              'owning': context.tr('collection.owning'),
                              'wanting': context.tr('collection.wanting'),
                            },
                            onSelected: enabled ? cubit.move : null,
                          ),
                        if (detail.wardrobeItem.metadata.notes != null)
                          _FactRow(
                            label: context.tr(LocaleKeys.notes),
                            value: detail.wardrobeItem.metadata.notes!,
                          ),
                      ],
                    ),
                    if (detail.generating)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: FormPanel(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2, right: 12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: FormTokens.green,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr(
                                        LocaleKeys.generationRunning,
                                      ),
                                      style: FormTokens.body.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      context.tr(
                                        LocaleKeys.generationRefresh,
                                      ),
                                      style: FormTokens.small,
                                    ),
                                    TextButton(
                                      onPressed: state.busy
                                          ? null
                                          : cubit.refresh,
                                      child: Text(
                                        context.tr(LocaleKeys.refresh),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (detail.generationAttempts.firstOrNull?.state ==
                        'failed')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FormNotice(
                          text: context.tr(LocaleKeys.generationFailed),
                          error: true,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: enabled
                            ? () => _openEdit(
                                context,
                                cubit,
                                detail.wardrobeItem,
                              )
                            : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: FormTokens.field,
                          foregroundColor: FormTokens.green,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              FormTokens.cardRadius,
                            ),
                          ),
                        ),
                        child: Text(context.tr(LocaleKeys.editItem)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: enabled
                            ? () => openLookComposer(
                                context,
                                itemIds: [detail.wardrobeItem.id],
                              )
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: FormTokens.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              FormTokens.cardRadius,
                            ),
                          ),
                        ),
                        child: Text(context.tr(LocaleKeys.inspireItem)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: online && state.canGenerate
                            ? () => _openGenerate(context, cubit, detail)
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: FormTokens.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              FormTokens.cardRadius,
                            ),
                          ),
                        ),
                        child: Text(
                          context.tr(
                            detail.currentImage == null
                                ? LocaleKeys.generateImage
                                : LocaleKeys.improveImage,
                          ),
                        ),
                      ),
                    ),
                    const _FormRule(),
                    Text(
                      context.tr(LocaleKeys.imageVersions),
                      style: FormTokens.body.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(LocaleKeys.generationExplanation),
                      style: FormTokens.small,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 188,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        itemCount: detail.shelfImageVersions.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _VersionAddTile(
                              label: context.tr(
                                detail.currentImage == null
                                    ? LocaleKeys.generateImage
                                    : LocaleKeys.improveImage,
                              ),
                              onTap: online && state.canGenerate
                                  ? () => _openGenerate(context, cubit, detail)
                                  : null,
                            );
                          }
                          final version = detail.shelfImageVersions[index - 1];
                          final current =
                              version.id ==
                              detail.wardrobeItem.currentShelfImageVersionId;
                          return _VersionTile(
                            version: version,
                            current: current,
                            online: online,
                            canRestore: state.canRestore(version.id),
                            onRestore: () => cubit.restore(version.id),
                          );
                        },
                      ),
                    ),
                    const _FormRule(),
                    if (detail.wardrobeItem.state == 'archived') ...[
                      for (final target in ['owning', 'wanting'])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: enabled
                                  ? () => cubit.move(target)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: FormTokens.field,
                                foregroundColor: FormTokens.green,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    FormTokens.cardRadius,
                                  ),
                                ),
                              ),
                              child: Text(
                                context.tr(
                                  LocaleKeys.restoreTo,
                                  namedArgs: {
                                    'state': context.tr('collection.$target'),
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: enabled
                                ? () => cubit.move('archived')
                                : null,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: FormTokens.field,
                              foregroundColor: FormTokens.green,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  FormTokens.cardRadius,
                                ),
                              ),
                            ),
                            child: Text(context.tr(LocaleKeys.archiveItem)),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: enabled
                          ? () async {
                              final confirmed = await confirmFormAction(
                                context: context,
                                title: context.tr(LocaleKeys.deleteItem),
                                message: context.tr(
                                  LocaleKeys.deleteItemConfirm,
                                ),
                                confirmLabel: context.tr(
                                  LocaleKeys.deleteItem,
                                ),
                              );
                              if (confirmed && context.mounted) {
                                await cubit.delete();
                              }
                            }
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: FormTokens.green,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: Text(context.tr(LocaleKeys.deleteItem)),
                    ),
                  ],
                ),
        );
      },
    ),
  );
}

/// Horizontal strip of every image of an item: the current shelf image, the
/// original source photo, then the generated looks it appears in.
class _ItemGallery extends StatelessWidget {
  const _ItemGallery({
    required this.detail,
    required this.looks,
    required this.online,
  });
  final ItemDetail detail;
  final List<Look> looks;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final tiles =
        <({String identity, String? previewPath, BoxFit fit, String caption})>[
          if (detail.currentImage != null)
            (
              identity: detail.currentImage!.transparentAssetId,
              previewPath: null,
              fit: BoxFit.contain,
              caption: context.tr(LocaleKeys.currentImage),
            ),
          (
            identity: detail.sourcePhoto.assetId,
            previewPath: null,
            fit: BoxFit.cover,
            caption: context.tr(LocaleKeys.sourcePhoto),
          ),
          for (final look in looks)
            if (look.assetId != null)
              (
                identity: look.assetId!,
                previewPath: 'v1/assets/${look.assetId!}/content',
                fit: BoxFit.cover,
                caption: context.tr(
                  LocaleKeys.generatedLookCaption,
                  namedArgs: {'date': lookDateText(context, look.createdAt)},
                ),
              ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth * 0.8;
        return SizedBox(
          height: tileWidth * 5 / 4 + 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final tile = tiles[index];
              final entrance = index == 0 && detail.currentImage != null
                  ? MediaEntrance.shelf
                  : MediaEntrance.fade;
              return SizedBox(
                key: ValueKey(tile.identity),
                width: tileWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormImageCard(
                      aspectRatio: 4 / 5,
                      child: CachedMedia(
                        identity: tile.identity,
                        previewPath: tile.previewPath,
                        fit: tile.fit,
                        online: online,
                        entrance: entrance,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tile.caption,
                      style: FormTokens.small,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: FormTokens.small.copyWith(
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: FormTokens.body.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FormRule extends StatelessWidget {
  const _FormRule();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 25),
    child: Divider(color: FormTokens.line, height: 1, thickness: 1),
  );
}

class _ItemColorSwatch extends StatelessWidget {
  const _ItemColorSwatch({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: FormTokens.colorForName(label),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1F4D5545)),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: FormTokens.small.copyWith(color: FormTokens.ink)),
    ],
  );
}

class _VersionAddTile extends StatelessWidget {
  const _VersionAddTile({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: SizedBox(
      width: 128,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: FormTokens.line),
                ),
                child: const Icon(Icons.add, color: FormTokens.green, size: 26),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FormTokens.small.copyWith(color: FormTokens.ink),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.current,
    required this.online,
    required this.canRestore,
    required this.onRestore,
  });

  final ShelfImageVersion version;
  final bool current;
  final bool online;
  final bool canRestore;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final actionLabel = context.tr(
      current ? LocaleKeys.currentImage : LocaleKeys.restoreImage,
    );
    return Semantics(
      button: true,
      selected: current,
      enabled: canRestore,
      label: actionLabel,
      child: SizedBox(
        width: 128,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canRestore ? onRestore : null,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ColoredBox(
                        color: FormTokens.field,
                        child: SizedBox(
                          height: 140,
                          width: 128,
                          child: CachedMedia(
                            identity: version.transparentAssetId,
                            online: online,
                            entrance: MediaEntrance.fade,
                          ),
                        ),
                      ),
                    ),
                    if (current)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: FormTokens.green,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    if (version.quality == 'high')
                      Positioned(
                        top: 6,
                        left: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xCCFFFFFF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              'HQ',
                              style: FormTokens.small.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: FormTokens.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  [
                    DateFormat.yMd(context.locale.languageCode).format(
                      version.keptAt,
                    ),
                    context.tr('quality.${version.quality}'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FormTokens.small.copyWith(
                    color: current ? FormTokens.green : FormTokens.ink,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                Text(
                  actionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FormTokens.small.copyWith(
                    color: current ? FormTokens.green : FormTokens.muted,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
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
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetField(
          label: context.tr(LocaleKeys.itemName),
          child: TextFormField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(counterText: ''),
            validator: (v) => !ItemMetadata.validName(v ?? '')
                ? context.tr(LocaleKeys.requiredField)
                : null,
          ),
        ),
        _SheetField(
          label: context.tr(LocaleKeys.category),
          child: FormField<String>(
            initialValue: _category,
            validator: (value) => value == null
                ? context.tr(LocaleKeys.chooseSupportedCategory)
                : null,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in supportedCategories)
                      FormPill(
                        label: context.tr('categories.$c'),
                        selected: field.value == c,
                        onTap: () {
                          field.didChange(c);
                          setState(() => _category = c);
                        },
                      ),
                  ],
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      field.errorText!,
                      style: FormTokens.small.copyWith(
                        color: FormTokens.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _SheetField(
          label: context.tr(LocaleKeys.itemColors),
          child: TextFormField(
            controller: _colors,
            validator: (v) => ItemEdit.validColors(v ?? '')
                ? null
                : context.tr(LocaleKeys.invalidColors),
          ),
        ),
        _SheetField(
          label: context.tr(LocaleKeys.notes),
          child: TextFormField(
            controller: _notes,
            maxLength: 2000,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(counterText: ''),
          ),
        ),
        _SheetField(
          label: context.tr(LocaleKeys.collectionState),
          child: FormChoiceChips(
            options: {
              for (final value in editableCollections(widget.item.state))
                value: context.tr('collection.$value'),
            },
            selected: _state,
            onSelected: (value) => setState(() => _state = value),
          ),
        ),
        const SizedBox(height: 8),
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
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: FormTokens.green,
          ),
          child: Text(context.tr(LocaleKeys.save)),
        ),
        TextButton(
          onPressed: () => context.pop(),
          child: Text(context.tr(LocaleKeys.cancel)),
        ),
      ],
    ),
  );
}

/// Captioned field in a sheet form, spaced evenly from the next one.
class _SheetField extends StatelessWidget {
  const _SheetField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: FormTokens.small),
        const SizedBox(height: 7),
        child,
      ],
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
  var _loadedDefault = false;
  final _feedback = TextEditingController();
  final Set<String> _suggestions = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedDefault) {
      _quality = context.read<QualityCubit>().state.wardrobe;
      _loadedDefault = true;
    }
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasShelf = widget.detail.currentImage != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.generationExplanation),
          style: FormTokens.body,
        ),
        if (hasShelf) ...[
          const SizedBox(height: 20),
          Text(
            context.tr(LocaleKeys.customFeedback),
            style: FormTokens.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in ['proportions', 'color', 'details'])
                _FeedbackChip(
                  label: context.tr('feedback.$suggestion'),
                  selected: _suggestions.contains(suggestion),
                  onTap: () => setState(() {
                    if (_suggestions.contains(suggestion)) {
                      _suggestions.remove(suggestion);
                    } else {
                      _suggestions.add(suggestion);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
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
        const SizedBox(height: 20),
        Text(
          context.tr('quality.low'),
          style: FormTokens.body.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 9),
        FormChoiceChips(
          options: {
            for (final quality in qualities)
              quality: context.tr('quality.$quality'),
          },
          selected: _quality,
          onSelected: (value) => setState(() => _quality = value),
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
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: FormTokens.green,
          ),
          child: Text(context.tr(LocaleKeys.requestPaidImage)),
        ),
        TextButton(
          onPressed: () => context.pop(),
          child: Text(context.tr(LocaleKeys.cancel)),
        ),
      ],
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  const _FeedbackChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? FormTokens.green : const Color(0xFFEEEDE7),
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: FormTokens.body.copyWith(
            fontSize: 12,
            color: selected ? Colors.white : FormTokens.ink,
          ),
        ),
      ),
    ),
  );
}
