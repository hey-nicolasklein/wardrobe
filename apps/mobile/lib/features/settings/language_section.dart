import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';

class LanguageSection extends StatelessWidget {
  const LanguageSection({super.key});

  @override
  Widget build(BuildContext context) => FormPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.language),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        FormChoiceChips(
          options: {
            'de': context.tr(LocaleKeys.german),
            'en': context.tr(LocaleKeys.english),
          },
          selected: context.watch<LanguageCubit>().state,
          onSelected: (value) async {
            try {
              await context.read<LanguageCubit>().select(value);
            } on Exception {
              if (context.mounted) {
                showFormToast(context, context.tr(LocaleKeys.languageFailed));
              }
            }
          },
        ),
      ],
    ),
  );
}
