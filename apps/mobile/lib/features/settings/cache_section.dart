import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/features/settings/setting_row.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// Row that clears downloaded images after a confirm. The dialog explains
/// what stays, so the row itself carries no description.
class CacheRow extends StatelessWidget {
  const CacheRow({super.key});

  @override
  Widget build(BuildContext context) => SettingRow(
    label: context.tr(LocaleKeys.settings_cacheTitle),
    onTap: () => _confirmClear(context),
  );

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.settings_cacheConfirmTitle),
      message: context.tr(LocaleKeys.settings_cacheConfirmBody),
      confirmLabel: context.tr(LocaleKeys.settings_cacheConfirmAction),
    );
    if (!confirmed || !context.mounted) return;
    await context.read<MediaRepository>().clearDownloaded();
    if (context.mounted) {
      showFormToast(context, context.tr(LocaleKeys.settings_cacheCleared));
    }
  }
}
