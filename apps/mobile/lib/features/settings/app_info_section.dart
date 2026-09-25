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
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr(LocaleKeys.server)),
            subtitle: Text(config.apiUri?.toString() ?? '—'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/server'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr(LocaleKeys.settings_appVersion)),
            subtitle: Text(
              '${AppInfo.version} (${AppInfo.buildNumber}) · '
              '${context.tr(
                config.flavor == 'production'
                    ? LocaleKeys.production
                    : LocaleKeys.development,
              )}',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr(LocaleKeys.contract)),
            subtitle: const Text('${ServerInfo.supportedContractVersion}'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              status == ConnectionStatus.ready
                  ? Icons.check_circle_outline
                  : Icons.cloud_off_outlined,
            ),
            title: Text(
              context.tr(switch (status) {
                ConnectionStatus.ready => LocaleKeys.connected,
                ConnectionStatus.checking => LocaleKeys.checking,
                _ => LocaleKeys.unavailable,
              }),
            ),
            trailing: IconButton(
              tooltip: context.tr(LocaleKeys.retry),
              onPressed: context.read<ConnectionCubit>().check,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child:
        child ??
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: FormTokens.body)),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.end,
                  style: FormTokens.small,
                ),
              ),
          ],
        ),
  );
}
