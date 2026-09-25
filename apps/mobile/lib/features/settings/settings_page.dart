import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/app_info_section.dart';
import 'package:form_mobile/features/settings/cache_section.dart';
import 'package:form_mobile/features/settings/character/character_section.dart';
import 'package:form_mobile/features/settings/cost_section.dart';
import 'package:form_mobile/features/settings/quality_section.dart';
import 'package:form_mobile/features/settings/reset_section.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/server_info.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final archivedCount =
        context
            .watch<WardrobeCubit>()
            .state
            .items
            ?.where((item) => item.item.state == 'archived')
            .length ??
        0;
    return Scaffold(
      appBar: FormPageHeader(title: context.tr(LocaleKeys.settings)),
      body: ListView(
        padding: const EdgeInsets.all(FormTokens.gutter),
        children: [
          Text(
            context.tr(LocaleKeys.settings_heroEyebrow),
            style: FormTokens.eyebrow,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(LocaleKeys.settings_heroTitle),
            style: FormTokens.display.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(LocaleKeys.settings_heroSubtitle),
            style: FormTokens.small,
          ),
          const SizedBox(height: 20),
          const CharacterSection(),
          const SizedBox(height: 20),
          const CostSection(),
          const SizedBox(height: 20),
          const QualitySection(),
          const SizedBox(height: 20),
          const AppInfoSection(),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.push('/settings/archive'),
            child: Text(
              context.tr(
                LocaleKeys.settings_openArchive,
                namedArgs: {'count': '$archivedCount'},
              ),
            ),
          ),
          const SizedBox(height: 20),
          const CacheSection(),
          const SizedBox(height: 20),
          const ResetSection(),
          const SizedBox(height: 24),
          Text(
            context.tr(LocaleKeys.settings_footer),
            textAlign: TextAlign.center,
            style: FormTokens.small.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();
    final status = context.watch<ConnectionCubit>().state;
    return Scaffold(
      appBar: FormPageHeader(title: context.tr(LocaleKeys.serverDetails)),
      body: ListView(
        padding: const EdgeInsets.all(FormTokens.gutter),
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
