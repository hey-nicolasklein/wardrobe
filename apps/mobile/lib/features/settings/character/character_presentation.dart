import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';

String characterStatus(BuildContext context, CharacterSheet sheet) =>
    context.tr(
      sheet.active
          ? LocaleKeys.character_active
          : sheet.state == 'failed'
          ? LocaleKeys.character_failedStatus
          : sheet.isPending
          ? LocaleKeys.character_pending
          : LocaleKeys.character_stored,
    );

String characterTitle(BuildContext context, CharacterSheet sheet) => context.tr(
  sheet.active
      ? LocaleKeys.character_activeTitle
      : LocaleKeys.character_personalTitle,
);

String characterDescription(BuildContext context, CharacterSheet sheet) =>
    context.tr(
      sheet.state == 'failed'
          ? LocaleKeys.character_failedBody
          : sheet.isPending
          ? LocaleKeys.character_pendingBody
          : sheet.active
          ? LocaleKeys.character_activeTitle
          : LocaleKeys.character_storedBody,
    );

String characterDate(
  BuildContext context,
  CharacterSheet sheet, {
  bool full = false,
}) {
  final date = DateFormat.yMd(context.locale.toString());
  return (full ? date.add_Hm() : date).format(sheet.createdAt.toLocal());
}

String characterSourceCount(BuildContext context, CharacterSheet sheet) =>
    context.tr(
      sheet.referenceAssetIds.length == 1
          ? LocaleKeys.character_onePhoto
          : LocaleKeys.character_photos,
      namedArgs: {'count': '${sheet.referenceAssetIds.length}'},
    );

String characterCreation(BuildContext context, CharacterSheet sheet) {
  final model = sheet.model == 'photo-collage-v1'
      ? context.tr(LocaleKeys.character_collage)
      : '${sheet.model} · ${context.tr(LocaleKeys.quality_high)}';
  return '$model · ${sheet.size}';
}

String characterMeta(BuildContext context, CharacterSheet sheet) =>
    '${characterSourceCount(context, sheet)} · '
    '${characterDate(context, sheet)}';
