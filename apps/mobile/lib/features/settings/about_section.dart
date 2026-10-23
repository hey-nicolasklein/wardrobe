import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/app_info.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/features/settings/setting_row.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// The public privacy policy, served by nginx on the production host.
/// The same URL is entered in App Store Connect.
final Uri privacyPolicyUrl = Uri.parse(
  'https://stargate.stork-platy.ts.net:8443/privacy.html',
);

/// App version, the connection state and the privacy policy. Server,
/// environment and contract details live one tap deeper on the server page.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();
    final status = context.watch<ConnectionCubit>().state;
    const version = '${AppInfo.version} (${AppInfo.buildNumber})';
    return SettingGroup([
      SettingRow(
        label: context.tr(LocaleKeys.settings_appVersion),
        value: config.flavor == 'production'
            ? version
            : '$version · ${context.tr(LocaleKeys.development)}',
      ),
      SettingRow(
        label: context.tr(LocaleKeys.server),
        value: context.tr(switch (status) {
          ConnectionStatus.ready => LocaleKeys.connected,
          ConnectionStatus.checking => LocaleKeys.checking,
          _ => LocaleKeys.unavailable,
        }),
        onTap: () => context.push('/settings/server'),
      ),
      SettingRow(
        label: context.tr(LocaleKeys.settings_privacy),
        onTap: () => unawaited(
          launchUrl(privacyPolicyUrl, mode: LaunchMode.inAppBrowserView),
        ),
      ),
    ]);
  }
}
