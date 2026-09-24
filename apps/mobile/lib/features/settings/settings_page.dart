import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/server_info.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr(LocaleKeys.settings))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: Text(context.tr(LocaleKeys.language)),
          trailing: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'de',
                label: Text(context.tr(LocaleKeys.german)),
              ),
              ButtonSegment(
                value: 'en',
                label: Text(context.tr(LocaleKeys.english)),
              ),
            ],
            selected: {context.watch<LanguageCubit>().state},
            onSelectionChanged: (value) async {
              try {
                await context.read<LanguageCubit>().select(value.single);
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
        const Divider(),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(context.tr(LocaleKeys.archive)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/archive'),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(context.tr(LocaleKeys.server)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/settings/server'),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr(LocaleKeys.foundationNote)),
        ),
      ],
    ),
  );
}

class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();
    final status = context.watch<ConnectionCubit>().state;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(LocaleKeys.serverDetails))),
      body: ListView(
        children: [
          ListTile(
            title: Text(context.tr(LocaleKeys.server)),
            subtitle: Text(config.apiUri?.toString() ?? ''),
          ),
          ListTile(
            title: Text(context.tr(LocaleKeys.environment)),
            subtitle: Text(
              context.tr(
                config.flavor == 'production'
                    ? LocaleKeys.production
                    : LocaleKeys.development,
              ),
            ),
          ),
          ListTile(
            title: Text(context.tr(LocaleKeys.contract)),
            subtitle: const Text('${ServerInfo.supportedContractVersion}'),
          ),
          ListTile(
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
