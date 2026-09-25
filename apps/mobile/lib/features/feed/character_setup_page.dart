import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';

class CharacterSetupPage extends StatelessWidget {
  const CharacterSetupPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: FormPageHeader(
      title: context.tr(LocaleKeys.feedCharacterSetupTitle),
    ),
    body: Padding(
      padding: const EdgeInsets.all(FormTokens.gutter),
      child: FormEmptyState(
        title: context.tr(LocaleKeys.feedCharacterSetupTitle),
        message: context.tr(LocaleKeys.feedCharacterSetupBody),
        icon: Icons.person_outline,
      ),
    ),
  );
}
