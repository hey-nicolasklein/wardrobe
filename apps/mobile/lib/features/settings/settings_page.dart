import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/about_section.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/features/settings/character/character_presentation.dart';
import 'package:form_mobile/features/settings/credit_wallet.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/features/settings/setting_row.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/server_info.dart';
import 'package:form_mobile/repository/auth_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// The Settings tab: credits up top, then short groups of rows that each
/// open a subpage (see [SettingsSubpage]).
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
    final character = context.watch<CharacterCubit>().state.current;
    final language = context.watch<LanguageCubit>().state;
    final signedIn = context.read<AuthRepository>().isSignedIn;
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
                context.tr(LocaleKeys.settings_title),
                style: FormTokens.display.copyWith(fontSize: 36),
              ),
            ),
            CreditWallet(onTap: () => context.push('/settings/credits')),
            _SectionTitle(context.tr(LocaleKeys.settings_groupPreferences)),
            SettingGroup([
              SettingRow(
                label: context.tr(LocaleKeys.character_reference),
                value: character == null
                    ? null
                    : characterStatus(context, character),
                onTap: () => context.push('/settings/character'),
              ),
              SettingRow(
                label: context.tr(LocaleKeys.language),
                value: context.tr(
                  language == 'en' ? LocaleKeys.english : LocaleKeys.german,
                ),
                onTap: () => context.push('/settings/language'),
              ),
              SettingRow(
                label: context.tr(LocaleKeys.settings_qualityTitle),
                onTap: () => context.push('/settings/quality'),
              ),
            ]),
            _SectionTitle(context.tr(LocaleKeys.settings_groupData)),
            SettingGroup([
              SettingRow(
                label: context.tr(LocaleKeys.settings_archive),
                value: archivedCount > 0 ? '$archivedCount' : null,
                onTap: () => context.push('/settings/archive'),
              ),
              SettingRow(
                label: context.tr(LocaleKeys.settings_storage),
                onTap: () => context.push('/settings/storage'),
              ),
            ]),
            _SectionTitle(context.tr(LocaleKeys.settings_groupAbout)),
            const AboutSection(),
            if (signedIn || kDebugMode) ...[
              const SizedBox(height: 32),
              SettingGroup([
                if (signedIn)
                  SettingRow(
                    label: context.tr(LocaleKeys.auth_accountTitle),
                    onTap: () => context.push('/settings/account'),
                  ),
                if (kDebugMode)
                  SettingRow(
                    label: context.tr(LocaleKeys.settings_debugTitle),
                    onTap: () => context.push('/settings/debug'),
                  ),
              ]),
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

/// A page one level below Settings: serif title in the header and the
/// [children] stacked with the usual gap between panels.
class SettingsSubpage extends StatelessWidget {
  const SettingsSubpage({
    required this.title,
    required this.children,
    super.key,
  });

  /// Locale key of the header title.
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FormTokens.paper,
    extendBodyBehindAppBar: true,
    appBar: FormPageHeader(title: context.tr(title)),
    body: Builder(
      builder: (context) => ListView(
        padding: EdgeInsets.fromLTRB(
          FormTokens.gutter,
          MediaQuery.paddingOf(context).top + 12,
          FormTokens.gutter,
          FormTokens.gutter + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(height: 20),
            child,
          ],
        ],
      ),
    ),
  );
}

/// Explains what a subpage holds, below its last panel.
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(text, style: FormTokens.small),
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
