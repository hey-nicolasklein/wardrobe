import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/services/look_output_service.dart';
import 'package:form_mobile/utils/idempotency_key.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// Opens the look composer, or character-reference setup when no active
/// reference exists yet. [itemIds] preselects pieces.
void openLookComposer(
  BuildContext context, {
  List<String> itemIds = const [],
}) {
  if (context.read<FeedCubit>().state.hasActiveCharacterReference == false) {
    unawaited(context.push('/feed/character-setup'));
    return;
  }
  final query = itemIds
      .map((id) => 'item=${Uri.encodeComponent(id)}')
      .join('&');
  unawaited(
    context.push(query.isEmpty ? '/feed/composer' : '/feed/composer?$query'),
  );
}

/// Lifecycle and connection changes reach [FeedCubit] through `FormApp`.
class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<FeedCubit, FeedState>(
    builder: (context, state) {
      final cubit = context.read<FeedCubit>();
      final looks = state.looks ?? [];
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: FormTokens.gutter,
                    ),
                    sliver: SliverList.list(
                      children: [
                        FormWordmark(title: context.tr(LocaleKeys.appName)),
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
                        FormHero(
                          eyebrow: context.tr(LocaleKeys.feedHeroEyebrow),
                          title: context.tr(LocaleKeys.feedHeroTitle),
                          body: context.tr(LocaleKeys.feedHeroBody),
                          addLabel: context.tr(LocaleKeys.createLook),
                          onAdd: () => openLookComposer(context),
                        ),
                      ],
                    ),
                  ),
                ),
                if (looks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: FormEmptyState(
                      title: context.tr(LocaleKeys.feedEmptyTitle),
                      message: context.tr(
                        state.hasActiveCharacterReference == false
                            ? LocaleKeys.feedEmptyWithoutSheet
                            : LocaleKeys.feedEmptyWithSheet,
                      ),
                      icon: Icons.auto_awesome_outlined,
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
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      FormTokens.gutter,
                      0,
                      FormTokens.gutter,
                      24,
                    ),
                    sliver: SliverList.separated(
                      itemCount: looks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final record = looks[index];
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
                          onDelete: () =>
                              _confirmDelete(context, record.look.id),
                          onShare: (origin) =>
                              _share(context, state, record.look, origin),
                          onMenu: () => _openLookMenu(context, record.look),
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

  Future<void> _openLookMenu(BuildContext context, Look look) async {
    final cubit = context.read<FeedCubit>();
    if (!cubit.state.online) return;
    final output = context.read<LookOutputService>();
    final garments = _garments(cubit.state, look);
    // Actions run on the page context, which outlives the closed sheet.
    void run(
      BuildContext sheetContext,
      Future<void> Function() action, {
      String? success,
    }) {
      Navigator.pop(sheetContext);
      unawaited(runFeedAction(context, action, success: success));
    }

    await showFormSheet<void>(
      context: context,
      builder: (sheetContext) => FormSheet(
        title: context.tr(LocaleKeys.lookMenuTitle),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(
              context.tr(LocaleKeys.lookMenuPrompt),
              style: FormTokens.heading.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            if (look.quality != 'high')
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(_upgradeLook(context, look));
                },
                child: Text(context.tr(LocaleKeys.lookUpgrade)),
              ),
            OutlinedButton(
              onPressed: () => run(
                sheetContext,
                () => cubit.createLook(
                  LookCommand.create(
                    exactItemIds: const [],
                    categories: const [],
                    occasion: null,
                    completeWithWardrobe: true,
                    parentLookId: look.id,
                  ),
                  look.wardrobeItemIds,
                ),
                success: context.tr(LocaleKeys.lookCreating),
              ),
              child: Text(context.tr(LocaleKeys.lookVary)),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                openLookComposer(context, itemIds: look.wardrobeItemIds);
              },
              child: Text(context.tr(LocaleKeys.lookCombine)),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showLookDetails(context, look);
              },
              child: Text(context.tr(LocaleKeys.lookDetails)),
            ),
            OutlinedButton(
              onPressed: () => run(
                sheetContext,
                () => output.saveWorn(look),
                success: context.tr(LocaleKeys.lookSavedToPhotos),
              ),
              child: Text(context.tr(LocaleKeys.lookDownloadWorn)),
            ),
            OutlinedButton(
              onPressed: () => run(
                sheetContext,
                () => output.saveFlatLay(
                  look,
                  garments,
                  flatLayLabels(context, look, garments.length),
                ),
                success: context.tr(LocaleKeys.lookSavedToPhotos),
              ),
              child: Text(context.tr(LocaleKeys.lookDownloadFlat)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_confirmDelete(context, look.id));
              },
              style: TextButton.styleFrom(foregroundColor: FormTokens.danger),
              child: Text(context.tr(LocaleKeys.lookDelete)),
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
    // One key per upgrade sheet, so a retried confirm cannot charge twice.
    final key = newIdempotencyKey();
    await showFormSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => FormSheet(
          title: context.tr(LocaleKeys.lookUpgradeTitle),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(LocaleKeys.lookUpgradeBody),
                style: FormTokens.body,
              ),
              const SizedBox(height: 16),
              FormChoiceChips(
                options: {
                  for (final quality in qualities)
                    quality: context.tr('quality.$quality'),
                },
                selected: selected,
                onSelected: (value) => setSheetState(() => selected = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    runFeedAction(
                      context,
                      () => context.read<FeedCubit>().createLook(
                        LookCommand.create(
                          exactItemIds: const [],
                          categories: const [],
                          occasion: null,
                          completeWithWardrobe: true,
                          parentLookId: look.id,
                          preserveComposition: true,
                          quality: selected,
                          idempotencyKey: key,
                        ),
                        look.wardrobeItemIds,
                      ),
                      success: context.tr(LocaleKeys.lookCreating),
                    ),
                  );
                },
                child: Text(context.tr(LocaleKeys.lookUpgradeConfirm)),
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
        Text(label.toUpperCase(), style: FormTokens.small),
        const SizedBox(height: 4),
        Text(value, style: FormTokens.body),
      ],
    ),
  );
}
