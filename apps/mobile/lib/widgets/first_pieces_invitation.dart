import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class FirstPiecesInvitation extends StatelessWidget {
  const FirstPiecesInvitation({super.key});

  @override
  Widget build(BuildContext context) => FormEmptyState(
    title: context.tr(LocaleKeys.looksFirstTitle),
    message: context.tr(LocaleKeys.looksFirstBody),
    scene: FormEmptyScene.looks,
    action: FilledButton(
      onPressed: () => context.pushReplacement('/wardrobe/intake'),
      child: Text(context.tr(LocaleKeys.wardrobeFirstAdd)),
    ),
  );
}
