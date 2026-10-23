import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class CatalogImagesPreparation extends StatelessWidget {
  const CatalogImagesPreparation({super.key});

  @override
  Widget build(BuildContext context) => FormEmptyState(
    title: context.tr(LocaleKeys.composerNoEligible),
    message: context.tr(LocaleKeys.composerNoEligibleBody),
    scene: FormEmptyScene.looks,
    action: OutlinedButton(
      onPressed: () => context.go('/wardrobe'),
      child: Text(context.tr(LocaleKeys.looksViewWardrobe)),
    ),
  );
}
