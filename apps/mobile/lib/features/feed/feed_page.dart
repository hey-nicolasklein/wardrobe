import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/collection_sheet.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/fitting_room_card.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/features/feed/look_collections_cubit.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/features/feed/look_stacks.dart';
import 'package:form_mobile/features/feed/look_stages.dart';
import 'package:form_mobile/features/feed/occasion_tile.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/repository/look_collection_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/look_output_service.dart';
import 'package:form_mobile/utils/idempotency_key.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// Opens the look composer, or character-reference setup when no active
/// reference exists yet. [itemIds] preselects pieces; [tryOn] starts in
/// try-on mode and [occasion] preselects an occasion. [from] starts with an
/// earlier look's pieces and settings instead.
void openLookComposer(
  BuildContext context, {
  List<String> itemIds = const [],
  bool tryOn = false,
  String? occasion,
  Look? from,
}) {
  if (context.read<FeedCubit>().state.hasActiveCharacterReference == false) {
    unawaited(context.push('/feed/character-setup'));
    return;
  }
  final query = [
    ...itemIds.map((id) => 'item=${Uri.encodeComponent(id)}'),
    if (tryOn) 'mode=try-on',
    if (occasion != null) 'occasion=${Uri.encodeComponent(occasion)}',
  ].join('&');
  unawaited(
    context.push(
      query.isEmpty ? '/feed/composer' : '/feed/composer?$query',
      extra: from,
    ),
  );
}

/// Opens [stack]'s looks to leaf through, from anywhere in the app.
void openLookStack(BuildContext context, LookStack stack) =>
    const FeedPage()._openStack(context, stack);

/// Lifecycle and connection changes reach [FeedCubit] through `FormApp`.
class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<FeedCubit, FeedState>(
    builder: (context, state) {
      final cubit = context.read<FeedCubit>();
      final looks = state.looks ?? [];

      // Before the first sync settles, no looks means "not loaded yet", not
      // an empty feed.
      final loading =
          state.looks == null && state.online && state.failure == null;
      final bottomInset = MediaQuery.paddingOf(context).bottom;
      return Scaffold(
        backgroundColor: FormTokens.paper,
        extendBodyBehindAppBar: true,
        // Look photos set the status bar style themselves, see
        // MediaStatusBarRegion; everything else keeps dark icons.
        appBar: const FormScrollEdge(adaptive: true),
        body: AnnotatedRegion(
          value: SystemUiOverlayStyle.dark,
          child: Stack(
            children: [
              CustomScrollView(
                // The iOS refresh control needs overscroll on every platform.
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverSafeArea(
                    left: false,
                    right: false,
                    bottom: false,
                    sliver: CupertinoSliverRefreshControl(
                      onRefresh: cubit.refresh,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      FormTokens.gutter,
                      0,
                      FormTokens.gutter,
                      6,
                    ),
                    sliver: SliverList.list(
                      children: [
                        FormWordmark(title: context.tr(LocaleKeys.appName)),
                        // The cloud carries the create action once there are
                        // enough pieces to fill it.
                        _LooksHeader(
                          onCreate:
                              looks.isEmpty ||
                                  loading ||
                                  _cloudItems(state).length >= _cloudMinimum
                              ? null
                              : () => openLookComposer(context),
                        ),
                        if (state.stale && !state.online && state.looks != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FormNotice(
                              text: context.tr(LocaleKeys.feedStale),
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
                      ],
                    ),
                  ),
                  if (loading)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FormTokens.gutter,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Semantics(
                          label: context.tr(LocaleKeys.feedLoading),
                          excludeSemantics: true,
                          child: const Column(
                            spacing: 16,
                            children: [
                              _LookCardSkeleton(),
                              _LookCardSkeleton(),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (looks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FormEmptyState(
                        title: context.tr(LocaleKeys.feedEmptyTitle),
                        message: context.tr(
                          state.hasActiveCharacterReference == false
                              ? LocaleKeys.feedEmptyWithoutSheet
                              : LocaleKeys.feedEmptyWithSheet,
                        ),
                        action: FilledButton(
                          onPressed: () => openLookComposer(context),
                          child: Text(
                            context.tr(
                              state.hasActiveCharacterReference == false
                                  ? LocaleKeys.feedCharacterSetup
                                  : LocaleKeys.feedFirstLook,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._overview(context, state),
                  // Clears the translucent tab bar.
                  SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  static const _cloudMinimum = 6;

  /// Up to 18 pieces with a catalog image for the create cloud, in a fixed
  /// shuffled order so the cloud does not reshuffle on every rebuild.
  static List<WardrobeItem> _cloudItems(FeedState state) {
    final items = [
      for (final item in state.itemsById.values)
        if (item.state != 'archived' && item.currentShelfImageVersionId != null)
          item,
    ]..sort((a, b) => a.id.hashCode.compareTo(b.id.hashCode));
    return items.take(18).toList();
  }

  /// The newest finished try-on, shown as the user's figure on the worn
  /// stage.
  static ({String identity, String previewPath})? _figure(FeedState state) {
    for (final record in _stackLooks(state, const TryOnStack())) {
      if (record.look.assetId case final assetId?) {
        return (identity: assetId, previewPath: record.previewPath(assetId));
      }
    }
    return null;
  }

  static List<CachedLook> _stackLooks(
    FeedState state,
    LookStack stack, [
    List<LookCollection> collections = const [],
  ]) => [
    for (final record in state.looks ?? const <CachedLook>[])
      if (inLookStack(
        stack,
        record.look,
        itemsById: state.itemsById,
        saved: state.saved[record.look.id] ?? false,
        collections: {for (final c in collections) c.id: c.lookIds},
      ))
        record,
  ];

  /// The stacks to choose from: every look, the occasions, the user's
  /// Sammlungen with saved looks and try-ons, then one stack per piece and
  /// per colour.
  List<Widget> _overview(BuildContext context, FeedState state) {
    final looks = state.looks ?? const <CachedLook>[];
    final userCollections = context.watch<LookCollectionsCubit>().state;
    final online = state.online;
    final width = MediaQuery.sizeOf(context).width;
    final collections = [
      for (final stack in const [SavedStack(), TryOnStack()])
        if (_stackLooks(state, stack) case final looks when looks.isNotEmpty)
          (stack, looks),
    ];
    final pieces = pieceStacks(looks, state.itemsById).take(16).toList();
    final colors = colorStacks(looks, state.itemsById);
    var index = 0;

    Widget labelled(
      String title,
      int count,
      Widget pile, {
      double labelOpacity = 1,
    }) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        pile,
        const SizedBox(height: 10),
        Opacity(
          opacity: labelOpacity,
          child: Column(
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FormTokens.ink,
                ),
              ),
              Text(_countText(context, count), style: FormTokens.small),
            ],
          ),
        ),
      ],
    );

    Widget row({required double height, required List<Widget> children}) =>
        SliverToBoxAdapter(
          child: SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(
                horizontal: FormTokens.gutter,
              ),
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        );

    final heroPhoto = Size(width * 0.42, width * 0.42 * 5 / 4);
    final cloudItems = _cloudItems(state);
    return [
      SliverScrollProgress(
        distance: heroPhoto.height,
        builder: (context, progress) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: StackPressable(
            index: index++,
            semanticLabel: context.tr(LocaleKeys.stackAll),
            onTap: () => _openStack(context, const AllLooksStack()),
            // Pulling down opens the fan wider; scrolling away gathers the
            // prints into a pile that lifts off a little slower than the
            // page. The label fades before the sinking pile reaches it.
            builder: (context, spread) {
              final pull = (-progress).clamp(0.0, 2.0);
              final away = progress.clamp(0.0, 1.0);
              return labelled(
                context.tr(LocaleKeys.stackAll),
                looks.length,
                labelOpacity: (1 - away * 4).clamp(0.0, 1.0),
                Transform.translate(
                  offset: Offset(0, away * heroPhoto.height * 0.35),
                  child: Transform.scale(
                    scale: 1 + pull * 0.08 - away * 0.1,
                    child: Transform.rotate(
                      angle: away * -0.06,
                      child: PhotoFan(
                        looks: looks,
                        online: online,
                        photoSize: heroPhoto,
                        spread: spread * (1 + pull * 0.9) * (1 - away * 0.75),
                        angle: 0.09,
                        offset: 0.42,
                        // New looks develop on top of this pile, wherever
                        // they were started. Their pieces rise onto the print.
                        developingFace: (record) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: FlatLayBoard(
                            garments: _garments(state, record.look),
                            online: online,
                            arrive: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      if (cloudItems.length >= _cloudMinimum)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            FormTokens.gutter,
            20,
            FormTokens.gutter,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: LookStages(
              items: cloudItems,
              figure: _figure(state),
              online: online,
              flatLabel: context.tr(LocaleKeys.createLook),
              wornLabel: context.tr(LocaleKeys.composerTryOnAction),
              onFlat: () => openLookComposer(context),
              onWorn: () => openLookComposer(context, tryOn: true),
            ),
          ),
        ),
      _SectionTitle(context.tr(LocaleKeys.stackSectionOccasions)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: FormTokens.gutter),
        sliver: SliverToBoxAdapter(
          child: Row(
            spacing: 10,
            children: [
              for (final preset in occasionPresets)
                Expanded(
                  child: _occasionTile(context, state, preset.value),
                ),
            ],
          ),
        ),
      ),
      _SectionTitle(context.tr(LocaleKeys.stackSectionCollections)),
      row(
        height: 176,
        children: [
          for (final collection in userCollections)
            _collectionStack(
              context,
              state,
              collection,
              _stackLooks(state, CollectionStack(collection.id), [collection]),
              index: index++,
              labelled: labelled,
            ),
          for (final (stack, stackLooks) in collections)
            StackPressable(
              index: index++,
              semanticLabel: _stackTitle(context, state, stack),
              onTap: () => _openStack(context, stack),
              builder: (context, spread) => labelled(
                _stackTitle(context, state, stack),
                stackLooks.length,
                PhotoFan(
                  looks: stackLooks,
                  online: online,
                  photoSize: const Size(80, 100),
                  spread: spread,
                  angle: 0.14,
                  offset: 0.34,
                ),
              ),
            ),
          const _NewCollectionTile(),
        ],
      ),
      if (pieces.isNotEmpty) ...[
        _SectionTitle(context.tr(LocaleKeys.stackSectionPieces)),
        row(
          height: 186,
          children: [
            for (final (item, stackLooks) in pieces)
              SizedBox(
                width: 132,
                child: StackPressable(
                  index: index++,
                  semanticLabel: item.metadata.name,
                  onTap: () => _openStack(context, PieceStack(item.id)),
                  builder: (context, spread) => labelled(
                    item.metadata.name,
                    stackLooks.length,
                    PiecePile(
                      item: item,
                      looks: stackLooks,
                      online: online,
                      spread: spread,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      if (colors.isNotEmpty) ...[
        _SectionTitle(context.tr(LocaleKeys.stackSectionColors)),
        row(
          height: 170,
          children: [
            for (final (family, stackLooks) in colors)
              SizedBox(
                width: 116,
                child: StackPressable(
                  index: index++,
                  semanticLabel: context.tr('colorFamilies.$family'),
                  onTap: () => _openStack(context, ColorStack(family)),
                  builder: (context, spread) => labelled(
                    context.tr('colorFamilies.$family'),
                    stackLooks.length,
                    ColorPile(
                      family: family,
                      looks: stackLooks,
                      online: online,
                      spread: spread,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// An occasion card. It plays its icon animation first, then opens the
  /// occasion's stack, or the composer for that occasion while it is empty.
  Widget _occasionTile(BuildContext context, FeedState state, String? value) {
    final preset = occasionPresets.firstWhere((p) => p.value == value);
    final count = _stackLooks(state, OccasionStack(value)).length;
    return OccasionTile(
      icon: preset.icon,
      label: context.tr(preset.label),
      colors: FormTokens.occasions[value ?? '']!,
      selected: false,
      caption: count == 0
          ? context.tr(LocaleKeys.stackNew)
          : _countText(context, count),
      onTap: () => Future<void>.delayed(
        const Duration(milliseconds: 320),
        () {
          if (!context.mounted) return;
          if (count == 0) {
            openLookComposer(context, occasion: value);
          } else {
            _openStack(context, OccasionStack(value));
          }
        },
      ),
    );
  }

  static LookCollection? _collection(BuildContext context, String id) => context
      .read<LookCollectionsCubit>()
      .state
      .where((c) => c.id == id)
      .firstOrNull;

  /// A Sammlung on the overview. Empty ones show their emoji and wait for
  /// looks. Holding one offers to delete it.
  Widget _collectionStack(
    BuildContext context,
    FeedState state,
    LookCollection collection,
    List<CachedLook> looks, {
    required int index,
    required Widget Function(String, int, Widget) labelled,
  }) {
    final title = '${collection.emoji} ${collection.name}';
    return GestureDetector(
      onLongPress: () => confirmRemoveCollection(context, collection),
      child: StackPressable(
        index: index,
        semanticLabel: title,
        onTap: () => looks.isEmpty
            ? showFormToast(context, context.tr(LocaleKeys.collectionEmpty))
            : _openStack(context, CollectionStack(collection.id)),
        builder: (context, spread) => labelled(
          title,
          looks.length,
          looks.isEmpty
              ? _EmptyCollection(emoji: collection.emoji, spread: spread)
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PhotoFan(
                      looks: looks,
                      online: state.online,
                      photoSize: const Size(80, 100),
                      spread: spread,
                      angle: 0.14,
                      offset: 0.34,
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Text(
                        collection.emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static String _countText(BuildContext context, int count) => context.tr(
    count == 1 ? LocaleKeys.stackCountOne : LocaleKeys.stackCountMany,
    namedArgs: {'count': '$count'},
  );

  static String _stackTitle(
    BuildContext context,
    FeedState state,
    LookStack stack,
  ) => switch (stack) {
    AllLooksStack() => context.tr(LocaleKeys.stackAll),
    OccasionStack(:final occasion) => context.tr(
      occasionPresets.firstWhere((p) => p.value == occasion).label,
    ),
    TryOnStack() => context.tr(LocaleKeys.stackTryOn),
    SavedStack() => context.tr(LocaleKeys.stackSaved),
    CollectionStack(:final collectionId) => switch (_collection(
      context,
      collectionId,
    )) {
      final c? => '${c.emoji} ${c.name}',
      null => '',
    },
    PieceStack(:final itemId) => state.itemsById[itemId]?.metadata.name ?? '',
    ColorStack(:final family) => context.tr('colorFamilies.$family'),
  };

  /// What "+ New" starts inside [stack]: the composer with the stack's
  /// occasion, piece or try-on mode. Saved looks and colours have no
  /// natural starting point, so they get none.
  static VoidCallback? _createIn(BuildContext context, LookStack stack) =>
      switch (stack) {
        AllLooksStack() => () => openLookComposer(context),
        OccasionStack(:final occasion) => () => openLookComposer(
          context,
          occasion: occasion,
        ),
        TryOnStack() => () => openLookComposer(context, tryOn: true),
        PieceStack(:final itemId) => () => openLookComposer(
          context,
          itemIds: [itemId],
        ),
        SavedStack() || ColorStack() || CollectionStack() => null,
      };

  void _openStack(BuildContext context, LookStack stack) {
    unawaited(
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 460),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, _, _) => _StackPage(
            stack: stack,
            looksOf: _stackLooks,
            titleOf: _stackTitle,
            createIn: _createIn,
            cardBuilder: _lookCard,
          ),
          transitionsBuilder: (_, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: FormTokens.easeOut,
              reverseCurve: Curves.easeIn,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _lookCard(BuildContext context, FeedState state, CachedLook record) {
    final cubit = context.read<FeedCubit>();
    if (fittingRoomApplies(record)) {
      return FittingRoomCard(
        key: ValueKey('fitting-${record.look.id}'),
        record: record,
        state: state,
        garments: _garments(state, record.look),
        online: state.online && !state.stale,
        onMenu: () => _openLookMenu(context, record.look),
        onOpenStack: (stack) => _openStack(context, stack),
      );
    }
    return LookCard(
      key: ValueKey(record.look.id),
      record: record,
      state: state,
      garments: _garments(state, record.look),
      online: state.online && !state.stale,
      onRetry: () => runFeedAction(
        context,
        () => cubit.retryLook(record.look.id),
      ),
      onDelete: () => _confirmDelete(context, record.look.id),
      onShare: (origin) => _share(context, state, record.look, origin),
      onMenu: () => _openLookMenu(context, record.look),
    );
  }

  static List<LookGarment> _garments(FeedState state, Look look) =>
      lookGarments(
        look,
        state.itemsById,
        pendingItemIds: state.pendingStarts[look.id],
      );

  /// Shares whichever representation the card currently shows.
  Future<void> _share(
    BuildContext context,
    FeedState state,
    Look look,
    Rect origin,
  ) {
    final output = context.read<LookOutputService>();
    final garments = _garments(state, look);
    final flat = state.views[look.id] == LookFeedView.flat;
    return runFeedAction(
      context,
      () => flat
          ? output.shareFlatLay(
              look,
              garments,
              flatLayLabels(context, look, garments.length),
              caption: lookCaption(look),
              origin: origin,
            )
          : output.shareWorn(
              look,
              caption: lookCaption(look),
              origin: origin,
            ),
    );
  }

  /// The look's actions, grouped by what they cost: paid generations with
  /// their price, free saves, details, and delete on its own. Anything that
  /// needs the server is disabled offline with a reason; saves work from the
  /// media cache.
  Future<void> _openLookMenu(BuildContext context, Look look) async {
    final cubit = context.read<FeedCubit>();
    final online = cubit.state.online;
    final output = context.read<LookOutputService>();
    final garments = _garments(cubit.state, look);
    final credits = context.read<CreditsCubit>().state;
    final cost = credits?.metered == false
        ? null
        : context.tr(
            LocaleKeys.lookCostBadge,
            namedArgs: {'cost': '$lookCreditCost'},
          );
    final offline = online ? null : context.tr(LocaleKeys.lookNeedsConnection);
    final saved = cubit.state.saved[look.id] ?? false;
    // Actions run on the page context, which outlives the closed sheet.
    void run(
      BuildContext sheetContext,
      Future<void> Function() action, {
      String? success,
    }) {
      Navigator.pop(sheetContext);
      unawaited(runFeedAction(context, action, success: success));
    }

    // Paid actions close the menu and ask once more, with the cost in view.
    void confirm(
      BuildContext sheetContext, {
      required String title,
      required String body,
      required LookCommand Function(String idempotencyKey) command,
    }) {
      Navigator.pop(sheetContext);
      unawaited(
        _confirmPaidLook(
          context,
          look,
          title: title,
          body: body,
          command: command,
        ),
      );
    }

    await showFormSheet<void>(
      context: context,
      builder: (sheetContext) => FormSheet(
        title: context.tr(LocaleKeys.lookMenuTitle),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            _MenuGroup(
              children: [
                if (look.isTryOn)
                  _MenuRow(
                    label: context.tr(LocaleKeys.tryOnAgain),
                    cost: cost,
                    disabledReason: offline,
                    onTap: () => confirm(
                      sheetContext,
                      title: context.tr(LocaleKeys.tryOnAgain),
                      body: context.tr(LocaleKeys.tryOnAgainBody),
                      command: (key) => LookCommand.create(
                        exactItemIds: look.wardrobeItemIds,
                        categories: const [],
                        occasion: null,
                        baseAssetId: look.baseAssetId,
                        quality: look.quality,
                        idempotencyKey: key,
                      ),
                    ),
                  ),
                if (!look.isTryOn)
                  _MenuRow(
                    label: context.tr(LocaleKeys.lookVary),
                    cost: cost,
                    disabledReason: offline,
                    onTap: () => confirm(
                      sheetContext,
                      title: context.tr(LocaleKeys.lookVary),
                      body: context.tr(LocaleKeys.lookVaryBody),
                      command: (key) => LookCommand.create(
                        exactItemIds: const [],
                        categories: const [],
                        occasion: null,
                        parentLookId: look.id,
                        idempotencyKey: key,
                      ),
                    ),
                  ),
                if (!look.isTryOn && look.concept != null)
                  _MenuRow(
                    label: context.tr(LocaleKeys.lookReshoot),
                    cost: cost,
                    disabledReason: offline,
                    onTap: () => confirm(
                      sheetContext,
                      title: context.tr(LocaleKeys.lookReshoot),
                      body: context.tr(LocaleKeys.lookReshootBody),
                      command: (key) => LookCommand.create(
                        exactItemIds: const [],
                        categories: const [],
                        occasion: null,
                        parentLookId: look.id,
                        reshoot: true,
                        quality: look.quality,
                        idempotencyKey: key,
                      ),
                    ),
                  ),
                if (look.quality != 'high' && !look.isTryOn)
                  _MenuRow(
                    label: context.tr(LocaleKeys.lookUpgrade),
                    cost: cost,
                    disabledReason: offline,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_upgradeLook(context, look));
                    },
                  ),
                // Try-on starts from a finished look, so the composer never
                // has to ask which kind of look to make.
                if (!look.isTryOn)
                  _MenuRow(
                    label: context.tr(LocaleKeys.lookTryOn),
                    cost: cost,
                    disabledReason: offline,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      openLookComposer(
                        context,
                        itemIds: look.wardrobeItemIds
                            .take(maxComposerPieces)
                            .toList(),
                        tryOn: true,
                      );
                    },
                  ),
                _MenuRow(
                  label: context.tr(LocaleKeys.lookCombine),
                  disabledReason: offline,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    openLookComposer(context, from: look);
                  },
                ),
              ],
            ),
            _MenuGroup(
              children: [
                _MenuRow(
                  label: context.tr(
                    saved ? LocaleKeys.lookUnsave : LocaleKeys.lookSave,
                  ),
                  disabledReason: offline,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(cubit.toggleMark(look.id, liked: false));
                  },
                ),
                _MenuRow(
                  label: context.tr(LocaleKeys.lookShare),
                  onTap: () {
                    // Phones ignore the anchor; it only places the iPad
                    // popover, so the screen centre is enough.
                    final origin = Rect.fromCenter(
                      center: MediaQuery.sizeOf(context).center(Offset.zero),
                      width: 1,
                      height: 1,
                    );
                    Navigator.pop(sheetContext);
                    unawaited(_share(context, cubit.state, look, origin));
                  },
                ),
                _MenuRow(
                  label: context.tr(LocaleKeys.lookDownloadWorn),
                  onTap: () => run(
                    sheetContext,
                    () => output.saveWorn(look),
                    success: context.tr(LocaleKeys.lookSavedToPhotos),
                  ),
                ),
                _MenuRow(
                  label: context.tr(LocaleKeys.lookDownloadFlat),
                  onTap: () => run(
                    sheetContext,
                    () => output.saveFlatLay(
                      look,
                      garments,
                      flatLayLabels(context, look, garments.length),
                    ),
                    success: context.tr(LocaleKeys.lookSavedToPhotos),
                  ),
                ),
                _MenuRow(
                  label: context.tr(LocaleKeys.lookDetails),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showLookDetails(context, look);
                  },
                ),
              ],
            ),
            _MenuGroup(
              children: [
                _MenuRow(
                  label: context.tr(LocaleKeys.lookDelete),
                  danger: true,
                  disabledReason: offline,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_confirmDelete(context, look.id));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLookDetails(BuildContext context, Look look) {
    final itemsById = context.read<FeedCubit>().state.itemsById;
    unawaited(
      showFormSheet<void>(
        context: context,
        builder: (_) => FormSheet(
          title: context.tr(LocaleKeys.lookDetailsTitle),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: context.tr(LocaleKeys.lookConcept),
                value: lookCaption(look).isEmpty ? '–' : lookCaption(look),
              ),
              if (look.concept?.shot case final shot?)
                _ShotDetail(
                  shot: shot,
                  looks: context.read<FeedCubit>().lookRepository,
                ),
              _DetailRow(
                label: context.tr(LocaleKeys.lookCreated),
                value: DateFormat.yMd(
                  context.locale.toString(),
                ).add_Hm().format(look.createdAt.toLocal()),
              ),
              _DetailRow(
                label: context.tr(LocaleKeys.lookModel),
                value: '${look.model} · ${look.quality} · ${look.size}',
              ),
              _DetailRow(
                label: context.tr(LocaleKeys.lookCharacterReference),
                value: look.characterSheetId,
              ),
              _DetailRow(
                label: context.tr(LocaleKeys.lookPieces),
                value: look.wardrobeItemIds
                    .map((id) => itemsById[id]?.metadata.name ?? id)
                    .join(', '),
              ),
              if (look.costMicrounits != null)
                _DetailRow(
                  label: context.tr(LocaleKeys.lookImageCost),
                  value: context.tr(
                    LocaleKeys.lookImageCostValue,
                    namedArgs: {
                      // Microunits of a dollar shown in cents, as in the PWA.
                      'value': NumberFormat.decimalPatternDigits(
                        locale: context.locale.toString(),
                        decimalDigits: 2,
                      ).format(look.costMicrounits! / 10000),
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _upgradeLook(BuildContext context, Look look) async {
    final qualities = higherQualities(look.quality);
    if (qualities.isEmpty) return;
    var selected = qualities.first;
    await _confirmPaidLook(
      context,
      look,
      title: context.tr(LocaleKeys.lookUpgradeTitle),
      body: context.tr(LocaleKeys.lookUpgradeBody),
      options: (setSheetState) => FormChoiceChips(
        options: {
          for (final quality in qualities)
            quality: context.tr('quality.$quality'),
        },
        selected: selected,
        onSelected: (value) => setSheetState(() => selected = value),
      ),
      command: (key) => LookCommand.create(
        exactItemIds: const [],
        categories: const [],
        occasion: null,
        parentLookId: look.id,
        preserveComposition: true,
        quality: selected,
        idempotencyKey: key,
      ),
    );
  }

  /// Confirms a paid generation based on [look]: what happens, what it costs
  /// and what is left afterwards. [options] sits between the explanation and
  /// the cost, e.g. a quality choice. The sheet passes one idempotency key to
  /// [command], so a retried confirm cannot charge twice.
  Future<void> _confirmPaidLook(
    BuildContext context,
    Look look, {
    required String title,
    required String body,
    required LookCommand Function(String idempotencyKey) command,
    Widget Function(StateSetter setSheetState)? options,
  }) async {
    final credits = context.read<CreditsCubit>();
    unawaited(credits.refresh());
    final key = newIdempotencyKey();
    await showFormSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => FormSheet(
          title: title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(body, style: FormTokens.body),
              if (options != null) ...[
                const SizedBox(height: 16),
                options(setSheetState),
              ],
              const SizedBox(height: 16),
              BlocBuilder<CreditsCubit, Credits?>(
                bloc: credits,
                builder: (_, balance) {
                  final metered = balance?.metered ?? false;
                  final short = metered && balance!.balance < lookCreditCost;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      if (short) ...[
                        Text(
                          context.tr(LocaleKeys.credits_empty),
                          style: FormTokens.body.copyWith(
                            color: FormTokens.danger,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            context.go('/settings');
                          },
                          child: Text(context.tr(LocaleKeys.lookSeeCredits)),
                        ),
                      ] else if (metered)
                        Text(
                          context.tr(
                            LocaleKeys.lookCostBalance,
                            namedArgs: {
                              'left': '${balance!.balance - lookCreditCost}',
                            },
                          ),
                          style: FormTokens.small.copyWith(
                            color: FormTokens.noteInk,
                          ),
                        ),
                      FilledButton(
                        onPressed: short
                            ? null
                            : () {
                                Navigator.pop(sheetContext);
                                unawaited(
                                  runFeedAction(
                                    context,
                                    () => context.read<FeedCubit>().createLook(
                                      command(key),
                                      look.wardrobeItemIds,
                                    ),
                                    success: context.tr(
                                      LocaleKeys.lookCreating,
                                    ),
                                    successAction: context.tr(
                                      LocaleKeys.lookView,
                                    ),
                                    onAction: () => openLookStack(
                                      context,
                                      const AllLooksStack(),
                                    ),
                                  ),
                                );
                              },
                        child: Text(
                          lookCostLabel(
                            context,
                            context.tr(LocaleKeys.lookConfirmCreate),
                            balance,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String lookId) async {
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.lookDeleteConfirmTitle),
      message: context.tr(LocaleKeys.lookDeleteConfirmBody),
      confirmLabel: context.tr(LocaleKeys.lookDeleteConfirm),
    );
    if (confirmed && context.mounted) {
      await runFeedAction(
        context,
        () => context.read<FeedCubit>().deleteLook(lookId),
      );
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FormTokens.small),
        const SizedBox(height: 4),
        Text(value, style: FormTokens.body),
      ],
    ),
  );
}

/// The shot type a look was photographed with, and a switch to see less of
/// it. Hidden shot types are left out when the next looks are planned.
class _ShotDetail extends StatefulWidget {
  const _ShotDetail({required this.shot, required this.looks});

  final String shot;
  final LookRepository looks;

  @override
  State<_ShotDetail> createState() => _ShotDetailState();
}

class _ShotDetailState extends State<_ShotDetail> {
  bool? _hidden;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final hidden = await widget.looks.hiddenShots();
      if (mounted) setState(() => _hidden = hidden.contains(widget.shot));
    } on FormApiException {
      // Without the preference the row still shows the shot type.
    }
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final hidden = await widget.looks.setShotHidden(
        widget.shot,
        hidden: !_hidden!,
      );
      if (mounted) setState(() => _hidden = hidden.contains(widget.shot));
    } on FormApiException {
      // The switch keeps its last known state.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = 'lookShot.${widget.shot}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(
          label: context.tr(LocaleKeys.lookShotLabel),
          // Unknown ids come from a newer server; show them raw.
          value: context.tr(label) == label ? widget.shot : context.tr(label),
        ),
        if (_hidden != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: Icon(
                _hidden!
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              label: Text(
                context.tr(
                  _hidden! ? LocaleKeys.lookShotShow : LocaleKeys.lookShotHide,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Stands in for look cards until the first sync, so a cold start shows the
/// feed's shape instead of flashing the empty state. Matches [LookCard]'s
/// header strip, 4:5 stage and footer.
class _LookCardSkeleton extends StatelessWidget {
  const _LookCardSkeleton();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: const ColoredBox(
      color: FormTokens.chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 64),
          AspectRatio(
            aspectRatio: 4 / 5,
            child: ColoredBox(color: FormTokens.lookStage),
          ),
          SizedBox(height: 96),
        ],
      ),
    ),
  );
}

/// A white, rounded group of [_MenuRow]s separated by hairlines.
class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: FormTokens.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FormTokens.cardRadius),
    ),
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              color: FormTokens.line,
            ),
          child,
        ],
      ],
    ),
  );
}

/// One action in a [_MenuGroup]. [cost] shows as a coin-tinted badge;
/// [disabledReason] disables the row and says why below the label.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.onTap,
    this.cost,
    this.disabledReason,
    this.danger = false,
  });
  final String label;
  final VoidCallback onTap;
  final String? cost;
  final String? disabledReason;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = disabledReason == null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: FormTokens.body.copyWith(
                            fontSize: 15,
                            height: 1.3,
                            color: danger ? FormTokens.danger : FormTokens.ink,
                          ),
                        ),
                        if (disabledReason case final reason?)
                          Text(reason, style: FormTokens.small),
                      ],
                    ),
                  ),
                  if (cost case final cost?)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: FormTokens.coinTint,
                        borderRadius: BorderRadius.circular(
                          FormTokens.chipRadius,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          cost,
                          style: FormTokens.small.copyWith(
                            color: FormTokens.coinInk,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
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

/// The page title with the create button beside it.
class _LooksHeader extends StatelessWidget {
  const _LooksHeader({required this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              context.tr(LocaleKeys.feed),
              style: FormTokens.display.copyWith(fontSize: 36),
            ),
          ),
        ),
        if (onCreate case final onCreate?) ...[
          const SizedBox(width: 15),
          FormAddButton(
            label: context.tr(LocaleKeys.createLook),
            onPressed: onCreate,
          ),
        ],
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      FormTokens.gutter + 2,
      30,
      FormTokens.gutter,
      14,
    ),
    sliver: SliverToBoxAdapter(
      child: Semantics(
        header: true,
        child: Text(text, style: FormTokens.heading.copyWith(fontSize: 21)),
      ),
    ),
  );
}

/// One stack's looks to leaf through, with "+ New" for that mission. It
/// follows the feed, so new and changed looks show up live, and closes once
/// the stack is empty.
class _StackPage extends StatefulWidget {
  const _StackPage({
    required this.stack,
    required this.looksOf,
    required this.titleOf,
    required this.createIn,
    required this.cardBuilder,
  });

  final LookStack stack;
  final List<CachedLook> Function(FeedState, LookStack, List<LookCollection>)
  looksOf;
  final String Function(BuildContext, FeedState, LookStack) titleOf;
  final VoidCallback? Function(BuildContext, LookStack) createIn;
  final Widget Function(BuildContext, FeedState, CachedLook) cardBuilder;

  static const headerHeight = 68.0;

  @override
  State<_StackPage> createState() => _StackPageState();
}

class _StackPageState extends State<_StackPage> {
  var _index = 0;
  var _closing = false;

  @override
  Widget build(BuildContext context) => BlocBuilder<FeedCubit, FeedState>(
    builder: (context, state) {
      final looks = widget.looksOf(
        state,
        widget.stack,
        context.watch<LookCollectionsCubit>().state,
      );
      if (looks.isEmpty && !_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      final index = looks.isEmpty ? 0 : math.min(_index, looks.length - 1);
      final create = widget.createIn(context, widget.stack);
      return Scaffold(
        backgroundColor: FormTokens.paper,
        // The cards scroll under the frosted header.
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(_StackPage.headerHeight),
          child: AnnotatedRegion(
            value: SystemUiOverlayStyle.dark,
            child: FormFrostedBar(
              border: const Border(bottom: BorderSide(color: FormTokens.line)),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    4,
                    4,
                    FormTokens.gutter,
                    8,
                  ),
                  child: SizedBox(
                    height: _StackPage.headerHeight - 12,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).backButtonTooltip,
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: FormTokens.ink,
                          ),
                        ),
                        if (_origin(state) case final origin?)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: origin,
                          ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.titleOf(context, state, widget.stack),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FormTokens.heading.copyWith(
                                  fontSize: 23,
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: FormTokens.quick,
                                child: Text(
                                  looks.isEmpty
                                      ? ''
                                      : '${index + 1} / ${looks.length}',
                                  key: ValueKey('$index/${looks.length}'),
                                  style: FormTokens.small.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (create != null) _NewPill(onPressed: create),
                        if (widget.stack case CollectionStack(
                          :final collectionId,
                        ))
                          IconButton(
                            tooltip: context.tr(LocaleKeys.collectionRemove),
                            onPressed: () async {
                              final collection = FeedPage._collection(
                                context,
                                collectionId,
                              );
                              if (collection == null) return;
                              final removed = await confirmRemoveCollection(
                                context,
                                collection,
                              );
                              if (removed && context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: FormTokens.ink,
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
        body: AnnotatedRegion(
          value: SystemUiOverlayStyle.dark,
          child: Column(
            children: [
              Expanded(
                child: Builder(
                  builder: (context) => LookPager(
                    // Below the header, which the scaffold adds to the top
                    // padding.
                    topInset: MediaQuery.paddingOf(context).top + 12,
                    itemCount: looks.length,
                    itemBuilder: (context, i) =>
                        widget.cardBuilder(context, state, looks[i]),
                    onPage: (value) => setState(() => _index = value),
                    onDismiss: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
            ],
          ),
        ),
      );
    },
  );

  /// What the stack was gathered from, beside its title: the piece's image
  /// or the colour's swatch. Other stacks are named well enough by title.
  Widget? _origin(FeedState state) => switch (widget.stack) {
    PieceStack(:final itemId) => switch (state.itemsById[itemId]) {
      final item? => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 50,
          child: ColoredBox(
            color: FormTokens.tileTint(item.id, item.metadata.colors),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: CachedMedia(
                identity: item.previewIdentity,
                previewPath: item.previewPath,
                online: state.online && !state.stale,
              ),
            ),
          ),
        ),
      ),
      null => null,
    },
    ColorStack(:final family) => ColorDot(
      color: colorFamilySwatches[family],
      size: 34,
    ),
    _ => null,
  };
}

/// "+ New" in a stack's header, in the selected tint.
class _NewPill extends StatelessWidget {
  const _NewPill({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr(LocaleKeys.createLook),
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        onPressed();
      },
      child: SizedBox(
        height: 44,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: FormTokens.selectedTint,
              borderRadius: BorderRadius.circular(FormTokens.chipRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  const Icon(Icons.add, size: 18, color: FormTokens.green),
                  Text(
                    context.tr(LocaleKeys.stackNew),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FormTokens.green,
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

/// A Sammlung without looks yet: its emoji on a dashed card that lifts a
/// little while held.
class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.emoji, required this.spread});
  final String emoji;
  final double spread;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: (spread - 1).clamp(0.0, 1.0) * -0.08,
    child: Container(
      width: 80,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FormTokens.selectedTint,
        borderRadius: BorderRadius.circular(FormTokens.cardRadius),
        border: Border.all(color: FormTokens.uploadLine),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 36)),
    ),
  );
}

/// The last tile in Sammlungen. Opens the sheet to start a new one.
class _NewCollectionTile extends StatelessWidget {
  const _NewCollectionTile();

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr(LocaleKeys.collectionNew),
    excludeSemantics: true,
    child: GestureDetector(
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        unawaited(showCollectionSheet(context));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FormTokens.cardRadius),
              border: Border.all(color: FormTokens.uploadLine, width: 1.5),
            ),
            child: const Icon(Icons.add, size: 30, color: FormTokens.green),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(LocaleKeys.collectionNew),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FormTokens.green,
            ),
          ),
        ],
      ),
    ),
  );
}
