import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/features/settings/character/character_presentation.dart';
import 'package:form_mobile/features/settings/character/character_section.dart';
import 'package:form_mobile/features/settings/cost_display.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class CharacterDetailPage extends StatelessWidget {
  const CharacterDetailPage({required this.id, super.key});
  final String id;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CharacterCubit, CharacterState>(
    builder: (context, state) {
      final sheet = state.find(id);
      final cubit = context.read<CharacterCubit>();
      return FormSheet(
        title: context.tr(LocaleKeys.character_reference),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            CharacterNotice(state: state),
            if (sheet == null)
              Text(context.tr(LocaleKeys.character_missing))
            else ...[
              CharacterBadge(sheet: sheet),
              Text(characterTitle(context, sheet), style: FormTokens.heading),
              if (!sheet.active)
                Text(
                  characterDescription(context, sheet),
                  style: FormTokens.body,
                ),
              FormReferenceImage(
                child: CharacterImage(sheet: sheet, online: state.online),
              ),
              Text(
                context.tr(LocaleKeys.character_about),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FormFact(
                label: context.tr(LocaleKeys.lookCreated),
                value: characterDate(context, sheet, full: true),
              ),
              FormFact(
                label: context.tr(LocaleKeys.character_sourcePhotos),
                value: '${sheet.referenceAssetIds.length}',
              ),
              FormFact(
                label: context.tr(LocaleKeys.character_creation),
                value: characterCreation(context, sheet),
              ),
              if (sheet.note != null)
                FormFact(
                  label: context.tr(LocaleKeys.character_noteLabel),
                  value: sheet.note!,
                ),
              if (sheet.costMicrounits != null)
                FormFact(
                  label: context.tr(LocaleKeys.character_cost),
                  value: costMoney(
                    sheet.costMicrounits!,
                    context.locale.toString(),
                  ),
                ),
              if (sheet.failureCategory != null)
                FormFact(
                  label: context.tr(LocaleKeys.character_failureCategory),
                  value: sheet.failureCategory!,
                ),
              if (sheet.canActivate)
                FilledButton(
                  onPressed: cubit.canActivate(sheet)
                      ? () => cubit.activate(id)
                      : null,
                  child: Text(context.tr(LocaleKeys.character_activate)),
                ),
              if (sheet.canReplace)
                OutlinedButton(
                  onPressed: state.canMutate
                      ? () => context.push('/settings/character-setup')
                      : null,
                  child: Text(context.tr(LocaleKeys.character_replace)),
                ),
              if (sheet.canDelete)
                TextButton(
                  onPressed: cubit.canDelete(sheet)
                      ? () async {
                          final confirmed = await confirmFormAction(
                            context: context,
                            title: context.tr(LocaleKeys.character_delete),
                            message: context.tr(
                              LocaleKeys.character_deleteBody,
                            ),
                            confirmLabel: context.tr(LocaleKeys.deleteItem),
                          );
                          if (!confirmed) return;
                          await cubit.delete(id);
                          if (context.mounted && cubit.state.find(id) == null) {
                            showFormToast(
                              context,
                              context.tr(LocaleKeys.character_deleted),
                            );
                            context.pop();
                          }
                        }
                      : null,
                  child: Text(context.tr(LocaleKeys.character_delete)),
                ),
              CharacterHistory(state: state, excludeId: id),
            ],
          ],
        ),
      );
    },
  );
}
