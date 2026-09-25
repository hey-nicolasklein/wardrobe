import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';

class CacheSection extends StatelessWidget {
  const CacheSection({super.key});

  @override
  Widget build(BuildContext context) => FormPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.settings_cacheTitle),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(LocaleKeys.settings_cacheBody),
          style: FormTokens.small,
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => _confirmClear(context),
          child: Text(context.tr(LocaleKeys.settings_cacheAction)),
        ),
      ],
    ),
  );

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(context.tr(LocaleKeys.settings_cacheConfirmTitle)),
        content: Text(context.tr(LocaleKeys.settings_cacheConfirmBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(LocaleKeys.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(LocaleKeys.settings_cacheConfirmAction)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<MediaRepository>().clearDownloaded();
    if (context.mounted) {
      showFormToast(context, context.tr(LocaleKeys.settings_cacheCleared));
    }
  }
}
