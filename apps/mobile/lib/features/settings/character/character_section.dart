import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/features/settings/character/character_presentation.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

class CharacterSection extends StatelessWidget {
  const CharacterSection({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CharacterCubit, CharacterState>(
        builder: (context, state) => FormPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                context.tr(LocaleKeys.character_title),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                context.tr(LocaleKeys.character_subtitle),
                style: FormTokens.small,
              ),
              CharacterNotice(state: state),
              for (final sheet in [
                ...state.pending,
                if (state.current != null) state.current!,
              ])
                CharacterCard(
                  sheet: sheet,
                  online: state.online,
                  newReference:
                      sheet.isPending && sheet.id != state.current?.id,
                ),
              if (state.current == null && !state.loading)
                Text(
                  context.tr(LocaleKeys.character_empty),
                  style: FormTokens.small,
                ),
              if (state.pastCount > 0)
                OutlinedButton(
                  onPressed: () => context.push('/settings/characters/history'),
                  child: Text(
                    context.tr(
                      LocaleKeys.character_historyCount,
                      namedArgs: {'count': '${state.pastCount}'},
                    ),
                  ),
                ),
              FilledButton(
                onPressed: state.canCreate
                    ? () => context.push('/settings/character-setup')
                    : null,
                child: Text(context.tr(LocaleKeys.character_newCollage)),
              ),
            ],
          ),
        ),
      );
}

class CharacterNotice extends StatelessWidget {
  const CharacterNotice({required this.state, super.key});
  final CharacterState state;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      if (state.loading || state.busy) const LinearProgressIndicator(),
      if (context.read<CharacterCubit>().hasPendingCommand)
        TextButton(
          onPressed: state.canMutate
              ? context.read<CharacterCubit>().retry
              : null,
          child: Text(context.tr(LocaleKeys.retryCommand)),
        ),
      if (state.error != null || !state.online || state.stale) ...[
        FormNotice(
          text: context.tr(state.error ?? LocaleKeys.character_offline),
          error: state.error != null,
        ),
        TextButton(
          onPressed: state.online && !state.loading
              ? context.read<CharacterCubit>().refresh
              : null,
          child: Text(context.tr(LocaleKeys.refresh)),
        ),
      ],
    ],
  );
}

class CharacterBadge extends StatelessWidget {
  const CharacterBadge({required this.sheet, super.key});
  final CharacterSheet sheet;
  @override
  Widget build(BuildContext context) => FormStatusBadge(
    label: characterStatus(context, sheet),
    icon: sheet.state == 'failed'
        ? FormIconName.close
        : sheet.active
        ? FormIconName.check
        : FormIconName.person,
    active: sheet.active,
    failed: sheet.state == 'failed',
  );
}

class CharacterImage extends StatelessWidget {
  const CharacterImage({required this.sheet, required this.online, super.key});
  final CharacterSheet sheet;
  final bool online;
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.tr(LocaleKeys.character_title),
    image: true,
    child: sheet.assetId != null
        ? CachedMedia(
            identity: sheet.assetId!,
            previewPath: 'v1/assets/${sheet.assetId}/content',
            online: online,
          )
        : Center(
            child: sheet.state != 'failed'
                ? const CircularProgressIndicator()
                : const FormIcon(FormIconName.close, color: FormTokens.muted),
          ),
  );
}

class CharacterCard extends StatelessWidget {
  const CharacterCard({
    required this.sheet,
    required this.online,
    this.horizontal = true,
    this.newReference = false,
    super.key,
  });
  final CharacterSheet sheet;
  final bool online;
  final bool horizontal;
  final bool newReference;
  @override
  Widget build(BuildContext context) => FormReferenceCard(
    active: sheet.active,
    pending: sheet.isPending,
    horizontal: horizontal,
    image: CharacterImage(sheet: sheet, online: online),
    onTap: () => context.push('/settings/characters/${sheet.id}'),
    copy: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        if (horizontal) CharacterBadge(sheet: sheet),
        Text(
          horizontal
              ? newReference
                    ? context.tr(LocaleKeys.character_newReference)
                    : characterTitle(context, sheet)
              : characterDate(context, sheet),
          style: FormTokens.body.copyWith(
            fontSize: horizontal ? 14 : 12,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        if (!sheet.active && horizontal)
          Text(characterDescription(context, sheet), style: FormTokens.small),
        Text(
          horizontal
              ? characterMeta(context, sheet)
              : characterStatus(context, sheet),
          style: FormTokens.small.copyWith(fontSize: 11),
        ),
      ],
    ),
  );
}

class CharacterHistory extends StatelessWidget {
  const CharacterHistory({required this.state, this.excludeId, super.key});
  final CharacterState state;
  final String? excludeId;
  @override
  Widget build(BuildContext context) {
    final sheets = state.historyExcept(excludeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(
          context.tr(LocaleKeys.character_history),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          context.tr(
            sheets.isEmpty
                ? LocaleKeys.character_noHistory
                : LocaleKeys.character_historyBody,
          ),
          style: FormTokens.small,
        ),
        if (sheets.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                for (final sheet in sheets)
                  SizedBox(
                    width: 132,
                    child: CharacterCard(
                      sheet: sheet,
                      online: state.online,
                      horizontal: false,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class CharacterHistoryPage extends StatelessWidget {
  const CharacterHistoryPage({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CharacterCubit, CharacterState>(
        builder: (context, state) => FormSheet(
          title: context.tr(LocaleKeys.character_history),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text(
                context.tr(LocaleKeys.character_historyTitle),
                style: FormTokens.heading,
              ),
              CharacterNotice(state: state),
              CharacterHistory(state: state),
            ],
          ),
        ),
      );
}
