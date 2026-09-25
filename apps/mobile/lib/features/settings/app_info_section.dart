import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/app_info.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/server_info.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class AppInfoSection extends StatelessWidget {
  const AppInfoSection({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();
    final status = context.watch<ConnectionCubit>().state;
    final flavor = config.flavor == 'production'
        ? LocaleKeys.production
        : LocaleKeys.development;
    return FormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(LocaleKeys.settings_appTitle),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(LocaleKeys.settings_appBody),
            style: FormTokens.small,
          ),
          const SizedBox(height: 16),
          _SettingRow(
            label: context.tr(LocaleKeys.language),
            child: FormChoiceChips(
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr(LocaleKeys.languageFailed)),
                      ),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 14),
          _SettingRow(
            label: context.tr(LocaleKeys.settings_access),
            value: context.tr(LocaleKeys.settings_accessValue),
          ),
          _SettingRow(
            label: context.tr(LocaleKeys.settings_signIn),
            value: context.tr(LocaleKeys.settings_signInValue),
          ),
          _SettingRow(
            label: context.tr(LocaleKeys.settings_storage),
            value: context.tr(LocaleKeys.settings_storageValue),
          ),
          _SettingRow(
            label: context.tr(LocaleKeys.server),
            value: config.apiUri?.authority ?? '—',
            onTap: () => context.push('/settings/server'),
          ),
          _SettingRow(
            label: context.tr(LocaleKeys.settings_appVersion),
            value:
                '${AppInfo.version} (${AppInfo.buildNumber}) · '
                '${context.tr(flavor)}',
          ),
          _SettingRow(
            label: context.tr(LocaleKeys.contract),
            value: '${ServerInfo.supportedContractVersion}',
          ),
          Row(
            children: [
              Icon(
                status == ConnectionStatus.ready
                    ? Icons.check_circle_outline
                    : Icons.cloud_off_outlined,
                size: 18,
                color: status == ConnectionStatus.ready
                    ? FormTokens.green
                    : FormTokens.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(switch (status) {
                    ConnectionStatus.ready => LocaleKeys.connected,
                    ConnectionStatus.checking => LocaleKeys.checking,
                    _ => LocaleKeys.unavailable,
                  }),
                  style: FormTokens.body,
                ),
              ),
              IconButton(
                tooltip: context.tr(LocaleKeys.retry),
                color: FormTokens.green,
                onPressed: context.read<ConnectionCubit>().check,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Label on the left, muted value hugging the right edge. With [onTap] the
/// row becomes tappable and shows a chevron.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    this.value,
    this.child,
    this.onTap,
  });

  final String label;
  final String? value;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (child != null) {
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: child);
    }
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: FormTokens.body),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value ?? '',
              textAlign: TextAlign.end,
              style: FormTokens.small,
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: FormTokens.muted,
              ),
            ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
