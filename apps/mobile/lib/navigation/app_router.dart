import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/feed/look_composer_page.dart';
import 'package:form_mobile/features/intake/intake_page.dart';
import 'package:form_mobile/features/settings/character/character_detail_page.dart';
import 'package:form_mobile/features/settings/character/character_section.dart';
import 'package:form_mobile/features/settings/character/character_setup_page.dart';
import 'package:form_mobile/features/settings/settings_page.dart';
import 'package:form_mobile/features/wardrobe/item_page.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_page.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/foundation_page.dart';
import 'package:go_router/go_router.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter() => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/feed',
  overridePlatformDefaultLocation: true,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => Scaffold(
        // Lets content scroll under the translucent tab bar.
        extendBody: true,
        body: shell,
        bottomNavigationBar: FormTabBar(
          selectedIndex: shell.currentIndex,
          onSelected: (index) => shell.goBranch(index),
          labels: [
            context.tr(LocaleKeys.feed),
            context.tr(LocaleKeys.visual_wardrobeTab),
            context.tr(LocaleKeys.settings_title),
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
                  path: 'composer',
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (_, state) => FormSheetPage(
                    key: state.pageKey,
                    child: LookComposerPage(
                      preselectedIds:
                          state.uri.queryParametersAll['item'] ?? const [],
                    ),
                  ),
                ),
                GoRoute(
                  path: 'character-setup',
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (_, state) => FormSheetPage(
                    key: state.pageKey,
                    child: const CharacterSetupPage(fromFeed: true),
                  ),
                ),
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
                GoRoute(path: 'intake', builder: (_, _) => const IntakePage()),
                GoRoute(
                  path: 'items/:id',
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (_, state) => FormSheetPage(
                    key: state.pageKey,
                    child: ItemPage(id: state.pathParameters['id']!),
                  ),
                ),
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
                GoRoute(
                  path: 'character-setup',
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (_, state) => FormSheetPage(
                    key: state.pageKey,
                    child: const CharacterSetupPage(),
                  ),
                ),
                GoRoute(
                  path: 'characters/history',
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (_, state) => FormSheetPage(
                    key: state.pageKey,
                    child: const CharacterHistoryPage(),
                  ),
                ),
                GoRoute(
                  path: 'characters/:id',
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (_, state) => FormSheetPage(
                    key: state.pageKey,
                    child: CharacterDetailPage(id: state.pathParameters['id']!),
                  ),
                ),
                GoRoute(
                  path: 'archive',
                  builder: (_, _) => const WardrobePage(archived: true),
                  routes: [
                    GoRoute(
                      path: 'items/:id',
                      parentNavigatorKey: _rootNavigatorKey,
                      pageBuilder: (_, state) => FormSheetPage(
                        key: state.pageKey,
                        child: ItemPage(id: state.pathParameters['id']!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

class FormSheetPage extends Page<void> {
  const FormSheetPage({required this.child, super.key});
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => ModalBottomSheetRoute<void>(
    settings: this,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: AnimationStyle(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FormTokens.sheetDuration,
      reverseDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FormTokens.sheetDuration,
    ),
    builder: (_) => formSheetDraggableWrapper(child),
  );
}
