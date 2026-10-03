import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/about_section.dart';
import 'package:form_mobile/features/settings/account_section.dart';
import 'package:form_mobile/features/settings/cache_section.dart';
import 'package:form_mobile/features/settings/character/character_section.dart';
import 'package:form_mobile/features/settings/cost_section.dart';
import 'package:form_mobile/features/settings/credit_wallet.dart';
import 'package:form_mobile/features/settings/feed_weights_section.dart';
import 'package:form_mobile/features/settings/language_section.dart';
import 'package:form_mobile/features/settings/quality_section.dart';
import 'package:form_mobile/features/settings/reset_section.dart';
import 'package:form_mobile/features/settings/setting_row.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/server_info.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _sectionGap = SizedBox(height: 20);

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
      backgroundColor: FormTokens.paper,
      extendBodyBehindAppBar: true,
      appBar: const FormScrollEdge(),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            FormTokens.gutter,
            MediaQuery.paddingOf(context).top,
            FormTokens.gutter,
            FormTokens.gutter + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            FormWordmark(title: context.tr(LocaleKeys.appName)),
            // Same offsets as the wardrobe hero, so wordmark and title stay
            // put when switching tabs.
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 22),
              child: Text(
                context.tr(LocaleKeys.settings_heroTitle),
                style: FormTokens.display.copyWith(fontSize: 36),
              ),
            ),
            const CreditWallet(),
            const CharacterSection(),
            _sectionGap,
            const CostSection(),
            _SectionTitle(context.tr(LocaleKeys.settings_groupPreferences)),
            const LanguageSection(),
            _sectionGap,
            const QualitySection(),
            _SectionTitle(context.tr(LocaleKeys.settings_groupData)),
            FormPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingRow(
                    label: context.tr(LocaleKeys.settings_archive),
                    value: archivedCount > 0 ? '$archivedCount' : null,
                    onTap: () => context.push('/settings/archive'),
                  ),
                  const SettingDivider(),
                  const CacheRow(),
                ],
              ),
            ),
            _SectionTitle(context.tr(LocaleKeys.settings_groupAbout)),
            const AboutSection(),
            _SectionTitle(context.tr(LocaleKeys.auth_accountTitle)),
            const AccountSection(),
            if (kDebugMode) ...[
              _SectionTitle(context.tr(LocaleKeys.settings_debugTitle)),
              const FeedWeightsSection(),
              _sectionGap,
              OutlinedButton(
                onPressed: () => context.push('/onboarding'),
                child: Text(context.tr(LocaleKeys.settings_replayOnboarding)),
              ),
              _sectionGap,
              const ResetSection(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sans heading that opens a group of panels, with more room above than below.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 32, 4, 10),
    child: Text(
      text,
      style: FormTokens.body.copyWith(
        color: FormTokens.muted,
        fontWeight: FontWeight.w600,
      ),
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
      extendBodyBehindAppBar: true,
      appBar: FormPageHeader(title: context.tr(LocaleKeys.serverDetails)),
      body: Builder(
        builder: (context) => ListView(
          padding:
              const EdgeInsets.all(
                FormTokens.gutter,
              ).add(
                EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top,
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
              ),
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
      ),
    );
  }
}
