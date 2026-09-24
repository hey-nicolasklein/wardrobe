import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/settings/settings_page.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_page.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/foundation_page.dart';
import 'package:go_router/go_router.dart';

GoRouter createRouter() => GoRouter(
  initialLocation: '/feed',
  overridePlatformDefaultLocation: true,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(index),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.auto_awesome_outlined),
              label: context.tr(LocaleKeys.feed),
            ),
            NavigationDestination(
              icon: const Icon(Icons.checkroom_outlined),
              label: context.tr(LocaleKeys.wardrobe),
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              label: context.tr(LocaleKeys.settings),
            ),
          ],
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/feed',
              builder: (_, _) => const FeedPage(),
              routes: [
                GoRoute(
                  path: 'status',
                  builder: (_, _) => const DataStatusPage(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/wardrobe',
              builder: (_, _) => const WardrobePage(),
              routes: [
                GoRoute(
                  path: 'status',
                  builder: (_, _) => const DataStatusPage(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsPage(),
              routes: [
                GoRoute(path: 'server', builder: (_, _) => const ServerPage()),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
