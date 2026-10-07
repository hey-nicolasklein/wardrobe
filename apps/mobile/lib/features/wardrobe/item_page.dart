import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/feed/look_stacks.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/features/settings/setting_row.dart';
import 'package:form_mobile/features/wardrobe/inspire_button.dart';
import 'package:form_mobile/features/wardrobe/item_cubit.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
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

  Future<void> _openVersions(BuildContext context, ItemCubit cubit) =>
      showFormSheet<void>(
        context: context,
        builder: (sheetContext) => BlocProvider.value(
          value: cubit,
          child: FormSheet(
            title: context.tr(LocaleKeys.imageVersions),
            child: const _VersionsSheet(),
          ),
        ),
      );

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
        final archived = detail?.wardrobeItem.state == 'archived';
        final openEdit = enabled
            ? () => _openEdit(context, cubit, detail!.wardrobeItem)
            : null;
        final openGenerate = online && state.canGenerate
            ? () => _openGenerate(context, cubit, detail!)
            : null;
        return Scaffold(
          backgroundColor: FormTokens.paper,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            actions: [
              if (detail != null)
                TextButton(
                  onPressed: openEdit,
                  child: Text(context.tr(LocaleKeys.edit)),
                ),
              const SizedBox(width: 4),
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
                    if (archived)
                      _ArchivedNotice(
                        onRestore: enabled ? cubit.move : null,
                      ),
                    // Keyed so notices appearing above it after a refresh do
                    // not rebuild the gallery and replay its image entrances.
                    _ItemGallery(
                      key: const ValueKey('gallery'),
                      detail: detail,
                      online: online && !state.stale,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context
                          .tr(
                            'categories.'
                            '${detail.wardrobeItem.metadata.category}',
                          )
                          .toUpperCase(),
                      style: FormTokens.eyebrow,
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      header: true,
                      child: Text(
                        detail.wardrobeItem.metadata.name,
                        style: FormTokens.heading,
                      ),
                    ),
                    if (detail.wardrobeItem.traits case final traits?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _TraitTag(label: traits.kind, onTap: openEdit),
                            if (traits.brand case final brand?)
                              _TraitTag(label: brand, onTap: openEdit)
                            else
                              _TraitTag(
                                label: context.tr(LocaleKeys.addBrand),
                                icon: Icons.add,
                                onTap: openEdit,
                              ),
                            _TraitTag(
                              label: context.tr('seasons.${traits.warmth}'),
                              onTap: openEdit,
                            ),
                          ],
                        ),
                      ),
                    if (detail.wardrobeItem.metadata.colors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final color
                                in detail.wardrobeItem.metadata.colors)
                              _ItemColorChip(label: color),
                          ],
                        ),
                      ),
                    if (detail.wardrobeItem.status == 'reviewing-metadata')
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _Pressable(
                          onTap: openEdit,
                          label: context.tr(LocaleKeys.reviewMetadataNotice),
                          child: FormNotice(
                            text: context.tr(LocaleKeys.reviewMetadataNotice),
                          ),
                        ),
                      )
                    else if (detail.wardrobeItem.status != 'ready')
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
                    if (detail.wardrobeItem.metadata.notes != null)
                      _FactRow(
                        label: context.tr(LocaleKeys.notes),
                        value: detail.wardrobeItem.metadata.notes!,
                      ),
                    if (!archived)
                      FormCollectionToggle(
                        selected: detail.wardrobeItem.state,
                        labels: {
                          'owning': context.tr('collection.owning'),
                          'wanting': context.tr('collection.wanting'),
                        },
                        onSelected: enabled ? cubit.move : null,
                      ),
                    // The two ways to make a new look, then the piece's
                    // existing ones.
                    BlocBuilder<FeedCubit, FeedState>(
                      builder: (context, feedState) {
                        final ready = readyLooksForItem(
                          detail.wardrobeItem.id,
                          (feedState.looks ?? []).map((record) => record.look),
                        ).toSet();
                        final looks =
                            [
                              for (final record in feedState.archive)
                                if (ready.contains(record.look)) record,
                            ]..sort(
                              (a, b) =>
                                  b.look.createdAt.compareTo(a.look.createdAt),
                            );
                        final create = enabled && !archived
                            ? () => openLookComposer(
                                context,
                                itemIds: [detail.wardrobeItem.id],
                              )
                            : null;
                        final tryOn = enabled && !archived
                            ? () => openLookComposer(
                                context,
                                itemIds: [detail.wardrobeItem.id],
                                tryOn: true,
                              )
                            : null;
                        // Two separate offers, each saying what it does:
                        // a look styled around the piece, or the piece on
                        // the user's own photo.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!archived)
                              // Equal height, so the two offers read as a
                              // pair of options.
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: InspireButton(
                                        title: context.tr(
                                          LocaleKeys.inspireItem,
                                        ),
                                        subtitle: context.tr(
                                          LocaleKeys.inspireItemHint,
                                        ),
                                        onPressed: create,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: InspireButton(
                                        primary: false,
                                        icon: const Icon(
                                          Icons.person_outline_rounded,
                                        ),
                                        title: context.tr(LocaleKeys.lookTryOn),
                                        subtitle: context.tr(
                                          LocaleKeys.tryOnItemHint,
                                        ),
                                        onPressed: tryOn,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (looks.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: archived ? 0 : 14,
                                ),
                                child: _ItemLooks(
                                  looks: looks,
                                  feed: feedState,
                                  online: online && !state.stale,
                                  onOpen: () => openLookStack(
                                    context,
                                    PieceStack(detail.wardrobeItem.id),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    if (detail.generating)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: _GenerationRunning(),
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
                    SettingGroup([
                      if (!archived)
                        _OptionRow(
                          label: context.tr(
                            detail.currentImage == null
                                ? LocaleKeys.generateImage
                                : LocaleKeys.improveImage,
                          ),
                          value: _creditCost(
                            context,
                            shelfImageCreditCost,
                            context.watch<CreditsCubit>().state,
                          ),
                          onTap: openGenerate,
                        ),
                      if (detail.shelfImageVersions.length > 1)
                        _OptionRow(
                          label: context.tr(LocaleKeys.imageVersions),
                          value: '${detail.shelfImageVersions.length}',
                          onTap: () => _openVersions(context, cubit),
                        ),
                      if (!archived)
                        _OptionRow(
                          label: context.tr(LocaleKeys.archiveItem),
                          chevron: false,
                          onTap: enabled ? () => cubit.move('archived') : null,
                        ),
                      _OptionRow(
                        label: context.tr(LocaleKeys.deleteItem),
                        color: FormTokens.danger,
                        chevron: false,
                        onTap: enabled
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
                      ),
                    ]),
                  ],
                ),
        );
      },
    ),
  );
}

/// Sits at the top of an archived piece, so the way back is the first thing
/// on the page.
class _ArchivedNotice extends StatelessWidget {
  const _ArchivedNotice({required this.onRestore});
  final ValueChanged<String>? onRestore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FormTokens.field,
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            context.tr(LocaleKeys.itemArchivedNotice),
            style: FormTokens.small.copyWith(color: FormTokens.noteInk),
          ),
          AnimatedOpacity(
            opacity: onRestore == null ? 0.45 : 1,
            duration: FormTokens.quick,
            child: Row(
              spacing: FormTokens.gap,
              children: [
                for (final (target, label) in [
                  ('owning', LocaleKeys.restoreToOwning),
                  ('wanting', LocaleKeys.restoreToWanting),
                ])
                  Expanded(
                    child: FilledButton(
                      onPressed: onRestore == null
                          ? null
                          : () => onRestore!(target),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: target == 'owning'
                            ? FormTokens.green
                            : FormTokens.surface,
                        foregroundColor: target == 'owning'
                            ? FormTokens.surface
                            : FormTokens.green,
                        disabledBackgroundColor: target == 'owning'
                            ? FormTokens.green
                            : FormTokens.surface,
                        disabledForegroundColor: target == 'owning'
                            ? FormTokens.surface
                            : FormTokens.green,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        context.tr(label),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Horizontal strip of the item's own images: the current shelf image and
/// the original source photo. Its looks open from [_ItemLooks].
class _ItemGallery extends StatelessWidget {
  const _ItemGallery({
    required this.detail,
    required this.online,
    super.key,
  });
  final ItemDetail detail;
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
        ];
    // The caption line grows with the reader's text size.
    final captionHeight =
        6 +
        MediaQuery.textScalerOf(
          context,
        ).scale(FormTokens.small.fontSize! * FormTokens.small.height!);
    return LayoutBuilder(
      builder: (context, constraints) {
        // A single image takes the full width instead of leaving a gap.
        final tileWidth = tiles.length == 1
            ? constraints.maxWidth
            : constraints.maxWidth * 0.8;
        return SizedBox(
          height: tileWidth * 5 / 4 + captionHeight,
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: FormTokens.eyebrow),
          const SizedBox(height: 4),
          Text(
            value,
            style: FormTokens.body.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Colour names FORM knows are shown in the reader's language. Anything else
/// was typed or detected as is and stays untranslated.
String _colorLabel(BuildContext context, String color) {
  final family = color.trim().toLowerCase();
  return _colorFamilyKeys.contains(family)
      ? context.tr('colorFamilies.$family')
      : color;
}

final List<String> _colorFamilyKeys = FormTokens.colorSwatches.keys
    .where((key) => key != 'other')
    .toList();

/// Worker-tagged trait, such as kind, brand or season. Tapping opens the
/// edit sheet, where tags can be corrected.
class _TraitTag extends StatelessWidget {
  const _TraitTag({required this.label, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => _Pressable(
    onTap: onTap,
    label: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const ShapeDecoration(
        color: FormTokens.pill,
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: FormTokens.ink),
            const SizedBox(width: 4),
          ],
          Text(label, style: FormTokens.small),
        ],
      ),
    ),
  );
}

/// One of the piece's colours. Colours FORM can group open the looks in
/// that colour family.
class _ItemColorChip extends StatelessWidget {
  const _ItemColorChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final family = colorFamilies(label).where((f) => f != 'other').firstOrNull;
    return ColorChip(
      label: _colorLabel(context, label),
      swatch: FormTokens.colorForName(label),
      onTap: family == null
          ? null
          : () => openLookStack(context, ColorStack(family)),
    );
  }
}

/// A preview of the looks this piece appears in: the newest few fanned as
/// prints, with the count beside them. It hints rather than lists, the
/// whole tile opens the piece's stack. "+ Neu" starts another look.
class _ItemLooks extends StatelessWidget {
  const _ItemLooks({
    required this.looks,
    required this.feed,
    required this.online,
    required this.onOpen,
  });

  final List<CachedLook> looks;
  final FeedState feed;
  final bool online;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => StackPressable(
    semanticLabel: context.tr(LocaleKeys.itemLooks),
    onTap: onOpen,
    builder: (context, spread) => Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
      decoration: BoxDecoration(
        color: FormTokens.field,
        borderRadius: BorderRadius.circular(FormTokens.cardRadius),
      ),
      child: Row(
        children: [
          PhotoFan(
            looks: looks,
            feed: feed,
            online: online,
            photoSize: const Size(56, 70),
            spread: spread,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(LocaleKeys.itemLooks),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: FormTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      looks.length == 1
                          ? context.tr(LocaleKeys.lookElsewhereOne)
                          : context.tr(
                              LocaleKeys.lookElsewhereMany,
                              namedArgs: {'count': '${looks.length}'},
                            ),
                      style: FormTokens.small.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: FormTokens.muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Press feedback without ripples: the child sinks and dims while held and
/// springs back on release, with a light haptic on tap.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onTap,
    required this.label,
    required this.child,
  });
  final VoidCallback? onTap;
  final String label;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: enabled
            ? () {
                unawaited(HapticFeedback.selectionClick());
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed && animate ? 0.96 : 1,
          duration: animate ? FormTokens.quick : Duration.zero,
          curve: _pressed ? Curves.easeOut : FormTokens.pop,
          child: AnimatedOpacity(
            opacity: enabled ? (_pressed ? 0.8 : 1) : 0.45,
            duration: animate ? FormTokens.quick : Duration.zero,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// What an action costs, e.g. "1 Credit". Unmetered accounts see no price.
/// While credits are unknown the cost shows, since most accounts are metered.
String? _creditCost(BuildContext context, int cost, Credits? credits) =>
    credits?.metered == false
    ? null
    : context.tr(
        cost == 1
            ? LocaleKeys.credits_balanceOne
            : LocaleKeys.credits_balanceMany,
        namedArgs: {'count': '$cost'},
      );

/// A [SettingRow] in the item's options that dims while it cannot be used.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.onTap,
    this.value,
    this.color,
    this.chevron = true,
  });
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.45 : 1,
    child: SettingRow(
      label: label,
      value: value,
      onTap: onTap,
      color: color,
      chevron: chevron,
    ),
  );
}

class _GenerationRunning extends StatelessWidget {
  const _GenerationRunning();

  @override
  Widget build(BuildContext context) => FormPanel(
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
                context.tr(LocaleKeys.generationRunning),
                style: FormTokens.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(LocaleKeys.generationAutoRefresh),
                style: FormTokens.small,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Every catalog image the piece has had. Tapping an older one makes it the
/// current image again; the sheet stays open and follows the item's state.
class _VersionsSheet extends StatelessWidget {
  const _VersionsSheet();

  @override
  Widget build(BuildContext context) {
    final online =
        context.watch<ConnectionCubit>().state == ConnectionStatus.ready;
    return BlocBuilder<ItemCubit, ItemState>(
      builder: (context, state) {
        final detail = state.detail;
        if (detail == null) return const SizedBox.shrink();
        final cubit = context.read<ItemCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(LocaleKeys.imageVersionsHint),
              style: FormTokens.body,
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  for (final version in detail.shelfImageVersions)
                    _VersionTile(
                      version: version,
                      current:
                          version.id ==
                          detail.wardrobeItem.currentShelfImageVersionId,
                      online: online,
                      canRestore: online && state.canRestore(version.id),
                      onRestore: () => cubit.restore(version.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
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
    final meta = [
      DateFormat.yMd(context.locale.languageCode).format(version.keptAt),
      context.tr('quality.${version.quality}'),
    ].join(' · ');
    final radius = BorderRadius.circular(FormTokens.inputRadius);
    // The current image is not a disabled control, only an already chosen
    // one, so it keeps full opacity.
    final tile = SizedBox(
      width: 128,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: radius,
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
                      borderRadius: radius,
                      border: Border.all(color: FormTokens.green, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            meta,
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
    );
    final label = '$actionLabel, $meta';
    return current
        ? Semantics(
            selected: true,
            label: label,
            excludeSemantics: true,
            child: tile,
          )
        : _Pressable(
            onTap: canRestore ? onRestore : null,
            label: label,
            child: tile,
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
  late final _notes = TextEditingController(text: widget.item.metadata.notes);
  late final _kind = TextEditingController(text: widget.item.traits?.kind);
  late final _brand = TextEditingController(text: widget.item.traits?.brand);
  late String? _warmth = widget.item.traits?.warmth;

  /// Colours outside FORM's families (typed or detected names such as
  /// "burgundy") stay on offer so editing never drops them silently.
  late final List<String> _customColors = [
    for (final color in widget.item.metadata.colors)
      if (!_colorFamilyKeys.contains(color.trim().toLowerCase())) color,
  ];
  late String? _category =
      supportedCategories.contains(widget.item.metadata.category)
      ? widget.item.metadata.category
      : null;
  late String _state = widget.item.state;
  late List<String> _colors = widget.item.metadata.colors;
  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _kind.dispose();
    _brand.dispose();
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
            builder: (field) => _FieldWithError(
              error: field.errorText,
              child: Wrap(
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
            ),
          ),
        ),
        _SheetField(
          label: context.tr(LocaleKeys.itemColorsPick),
          child: FormField<List<String>>(
            initialValue: widget.item.metadata.colors,
            validator: (value) => ItemMetadata.validColors(value ?? const [])
                ? null
                : context.tr(LocaleKeys.chooseColors),
            builder: (field) {
              final selected = field.value ?? const <String>[];
              bool isSelected(String color) => selected.any(
                (c) => c.trim().toLowerCase() == color.toLowerCase(),
              );
              void toggle(String color) {
                final next = isSelected(color)
                    ? [
                        for (final c in selected)
                          if (c.trim().toLowerCase() != color.toLowerCase()) c,
                      ]
                    : [...selected, color];
                field.didChange(next);
                _colors = next;
              }

              return _FieldWithError(
                error: field.errorText,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in [..._colorFamilyKeys, ..._customColors])
                      FormPill(
                        label: _colorLabel(context, color),
                        selected: isSelected(color),
                        leading: ColorDot(
                          color: FormTokens.colorForName(color),
                          size: 14,
                        ),
                        onTap: () => toggle(color),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        // Tags exist once the worker has tagged the piece, so only then can
        // they be corrected.
        if (widget.item.traits != null) ...[
          _SheetField(
            label: context.tr(LocaleKeys.kind),
            child: TextFormField(
              controller: _kind,
              maxLength: 40,
              decoration: const InputDecoration(counterText: ''),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? context.tr(LocaleKeys.requiredField)
                  : null,
            ),
          ),
          _SheetField(
            label: context.tr(LocaleKeys.brand),
            child: TextFormField(
              controller: _brand,
              maxLength: 40,
              decoration: InputDecoration(
                counterText: '',
                hintText: context.tr(LocaleKeys.brandHint),
                suffixIcon: ListenableBuilder(
                  listenable: _brand,
                  builder: (context, _) => _brand.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: context.tr(LocaleKeys.removeBrand),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _brand.clear,
                        ),
                ),
              ),
            ),
          ),
          _SheetField(
            label: context.tr(LocaleKeys.season),
            child: FormChoiceChips(
              options: {
                for (final warmth in warmths)
                  warmth: context.tr('seasons.$warmth'),
              },
              selected: _warmth!,
              onSelected: (value) => setState(() => _warmth = value),
            ),
          ),
        ],
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
            if (!_form.currentState!.validate()) return;
            context.pop(
              ItemEdit(
                name: _name.text,
                category: _category!,
                colors: _colors.join(', '),
                notes: _notes.text,
                state: _state,
                traits: switch (widget.item.traits) {
                  final traits? => ItemTraits(
                    warmth: _warmth!,
                    kind: _kind.text.trim().toLowerCase(),
                    brand: _brand.text.trim().isEmpty
                        ? null
                        : _brand.text.trim(),
                    formality: traits.formality,
                  ),
                  null => null,
                },
              ),
            );
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
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

class _FieldWithError extends StatelessWidget {
  const _FieldWithError({required this.child, this.error});
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      child,
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error!,
            style: FormTokens.small.copyWith(color: FormTokens.danger),
          ),
        ),
    ],
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

  String? get _currentQuality => widget.detail.currentImage?.quality;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedDefault) {
      // Improving starts at the current image's quality, so a new image never
      // ends up worse by default.
      _quality = _currentQuality ?? context.read<QualityCubit>().state.wardrobe;
      unawaited(context.read<CreditsCubit>().refresh());
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
    final current = _currentQuality;
    final downgrade =
        current != null &&
        qualities.indexOf(_quality) < qualities.indexOf(current);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.generationExplanation),
          style: FormTokens.body,
        ),
        const SizedBox(height: 20),
        if (hasShelf)
          _SheetField(
            label: context.tr(LocaleKeys.improveFeedback),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final suggestion in [
                      'proportions',
                      'color',
                      'details',
                    ])
                      FormPill(
                        label: context.tr('feedback.$suggestion'),
                        selected: _suggestions.contains(suggestion),
                        onTap: () => setState(() {
                          if (!_suggestions.remove(suggestion)) {
                            _suggestions.add(suggestion);
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
                    hintText: context.tr(LocaleKeys.customFeedback),
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
        _SheetField(
          label: context.tr(LocaleKeys.imageQuality),
          child: FormChoiceChips(
            options: {
              for (final quality in qualities)
                quality: context.tr('quality.$quality'),
            },
            selected: _quality,
            onSelected: (value) => setState(() => _quality = value),
          ),
        ),
        if (downgrade)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FormNotice(
              text: context.tr(
                LocaleKeys.qualityDowngrade,
                namedArgs: {'quality': context.tr('quality.$current')},
              ),
            ),
          ),
        BlocBuilder<CreditsCubit, Credits?>(
          builder: (context, credits) {
            final metered = credits?.metered ?? false;
            final short = metered && credits!.balance < shelfImageCreditCost;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                if (short) ...[
                  Text(
                    context.tr(LocaleKeys.imageCreditsEmpty),
                    style: FormTokens.body.copyWith(color: FormTokens.danger),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      context
                        ..pop()
                        ..go('/settings');
                    },
                    child: Text(context.tr(LocaleKeys.lookSeeCredits)),
                  ),
                ] else if (metered)
                  Text(
                    context.tr(
                      LocaleKeys.lookCostBalance,
                      namedArgs: {
                        'left': '${credits!.balance - shelfImageCreditCost}',
                      },
                    ),
                    style: FormTokens.small.copyWith(color: FormTokens.noteInk),
                  ),
                FilledButton(
                  onPressed: short ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(_costLabel(context, credits)),
                ),
              ],
            );
          },
        ),
        TextButton(
          onPressed: () => context.pop(),
          child: Text(context.tr(LocaleKeys.cancel)),
        ),
      ],
    );
  }

  /// "Erstellen · 1 Credit" for metered accounts, the bare action otherwise.
  /// While credits are unknown the cost shows, since most accounts are
  /// metered.
  String _costLabel(BuildContext context, Credits? credits) {
    final action = context.tr(LocaleKeys.lookConfirmCreate);
    if (credits?.metered == false) return action;
    return context.tr(
      shelfImageCreditCost == 1
          ? LocaleKeys.imageCostActionOne
          : LocaleKeys.lookCostAction,
      namedArgs: {'action': action, 'cost': '$shelfImageCreditCost'},
    );
  }

  void _submit() {
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
  }
}
