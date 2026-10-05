import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
import 'package:form_mobile/features/settings/settings_page.dart';
import 'package:form_mobile/features/settings/try_on_photos_section.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:go_router/go_router.dart';

/// The pages behind the rows on [SettingsPage], nested under `/settings`.
final settingsSubpageRoutes = <RouteBase>[
  GoRoute(
    path: 'credits',
    builder: (_, _) => const SettingsSubpage(
      title: LocaleKeys.credits_pageTitle,
      children: [CreditWallet(), CostSection()],
    ),
  ),
  GoRoute(
    path: 'character',
    builder: (_, _) => const SettingsSubpage(
      title: LocaleKeys.photosOfYou,
      children: [CharacterSection(), TryOnPhotosSection()],
    ),
  ),
  GoRoute(
    path: 'language',
    builder: (_, _) => const SettingsSubpage(
      title: LocaleKeys.language,
      children: [LanguageSection()],
    ),
  ),
  GoRoute(
    path: 'quality',
    builder: (_, _) => const SettingsSubpage(
      title: LocaleKeys.settings_qualityTitle,
      children: [QualitySection()],
    ),
  ),
  GoRoute(
    path: 'storage',
    builder: (context, _) => SettingsSubpage(
      title: LocaleKeys.settings_storage,
      children: [
        const SettingGroup([CacheRow()]),
        SettingsFootnote(context.tr(LocaleKeys.settings_storageBody)),
      ],
    ),
  ),
  GoRoute(
    path: 'account',
    builder: (_, _) => const SettingsSubpage(
      title: LocaleKeys.auth_accountTitle,
      children: [AccountSection()],
    ),
  ),
  if (kDebugMode)
    GoRoute(
      path: 'debug',
      builder: (context, _) => const SettingsSubpage(
        title: LocaleKeys.settings_debugTitle,
        children: [
          FeedWeightsSection(),
          ResetSection(),
        ],
      ),
    ),
];
