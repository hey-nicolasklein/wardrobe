import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_proposals_cubit.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// Planned outfits from the composer. Nothing is rendered until the user
/// picks a proposal, so only the chosen ones cost credits.
class LookProposalsPage extends StatelessWidget {
  const LookProposalsPage({required this.quality, super.key});

  final String quality;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        LookProposalsCubit(context.read<LookRepository>(), quality: quality),
    child: const _ProposalsView(),
  );
}

class _ProposalsView extends StatelessWidget {
  const _ProposalsView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LookProposalsCubit>().state;
    final wardrobe = context.watch<WardrobeCubit>().state;
    final itemsById = <String, WardrobeItem>{
      for (final cached in wardrobe.items ?? const <CachedItem>[])
        cached.item.id: cached.item,
    };
    final proposals = [
      ...?state.proposals?.where((look) => look.state != 'failed'),
    ];
    final allFailed =
        state.proposals != null &&
        state.proposals!.isNotEmpty &&
        proposals.isEmpty;
    return FormSheet(
      title: context.tr(LocaleKeys.proposalsTitle),
      footer: FilledButton(
        onPressed: () => context.go('/feed'),
        child: Text(
          context.tr(
            state.rendered.isEmpty
                ? LocaleKeys.proposalsSkip
                : LocaleKeys.proposalsDone,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr(LocaleKeys.proposalsHint), style: FormTokens.small),
          const SizedBox(height: 16),
          if (state.failure != null) ...[
            FormNotice(
              text: apiFailureText(context, state.failure!),
              error: true,
            ),
            const SizedBox(height: 16),
          ],
          if (allFailed)
            FormNotice(
              text: context.tr(LocaleKeys.proposalsFailed),
              error: true,
            ),
          for (final look in proposals) ...[
            _ProposalCard(
              look: look,
              itemsById: itemsById,
              online: !wardrobe.stale,
              rendered: state.rendered.contains(look.id),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.look,
    required this.itemsById,
    required this.online,
    required this.rendered,
  });

  final Look look;
  final Map<String, WardrobeItem> itemsById;
  final bool online;
  final bool rendered;

  @override
  Widget build(BuildContext context) {
    final planned = look.state == 'proposed' || rendered;
    // The planner's activity alone. The scene text is meant for the image
    // model.
    final caption = look.concept?.activity ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FormTokens.flatLayPaper,
        borderRadius: BorderRadius.circular(FormTokens.cardRadius),
      ),
      child: !planned
          ? SizedBox(
              height: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr(LocaleKeys.proposalsPlanning),
                    style: FormTokens.small,
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: FlatLayBoard(
                      garments: lookGarments(look, itemsById),
                      online: online,
                    ),
                  ),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    caption,
                    style: FormTokens.small,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: rendered
                      ? null
                      : () => unawaited(
                          context.read<LookProposalsCubit>().render(look.id),
                        ),
                  child: Text(
                    rendered
                        ? context.tr(LocaleKeys.proposalsRendering)
                        : lookCostLabel(
                            context,
                            context.tr(LocaleKeys.proposalsRender),
                            context.watch<CreditsCubit>().state,
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
