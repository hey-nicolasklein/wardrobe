import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/feed/look_composer_page.dart';
import 'package:form_mobile/features/feed/look_proposals_page.dart';
import 'package:form_mobile/features/intake/intake_page.dart';
import 'package:form_mobile/features/onboarding/onboarding_page.dart';
import 'package:form_mobile/features/settings/character/character_detail_page.dart';
import 'package:form_mobile/features/settings/character/character_section.dart';
import 'package:form_mobile/features/settings/character/character_setup_page.dart';
import 'package:form_mobile/features/settings/settings_page.dart';
import 'package:form_mobile/features/settings/settings_subpages.dart';
import 'package:form_mobile/features/wardrobe/item_page.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_page.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/navigation/tab_reselect.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/foundation_page.dart';
import 'package:go_router/go_router.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final List<GlobalKey<NavigatorState>> _branchNavigatorKeys = List.generate(
  3,
  (_) => GlobalKey<NavigatorState>(),
);

GoRouter createRouter({bool onboarding = false}) {
  final reselect = TabReselect();
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: onboarding ? '/onboarding' : '/feed',
    overridePlatformDefaultLocation: true,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BlocListener<FeedCubit, FeedState>(
          listener: (context, feed) => _announceFinishedLooks(context, shell),
          listenWhen: (previous, next) {
            _finished = _finishedLooks(previous, next);
            return _finished.isNotEmpty;
          },
          child: Scaffold(
            // Lets content scroll under the translucent tab bar.
            extendBody: true,
            body: shell,
            bottomNavigationBar: FormTabBar(
              selectedIndex: shell.currentIndex,
              // Points back to Looks while a look develops there.
              badged: {
                if (context.select<FeedCubit, bool>(
                  (cubit) =>
                      cubit.state.looks?.any((r) => r.look.isActive) ?? false,
                ))
                  0,
              },
              onSelected: (index) {
                if (index != shell.currentIndex) {
                  shell.goBranch(index);
                  return;
                }
                // Re-tapping the active tab steps back one page per tap.
                // On the tab's first page it scrolls to the top instead.
                final branch = _branchNavigatorKeys[index].currentState;
                if (branch != null && branch.canPop()) {
                  unawaited(branch.maybePop());
                } else {
                  reselect.reselect(index);
                }
              },
              labels: [
                context.tr(LocaleKeys.feed),
                context.tr(LocaleKeys.visual_wardrobeTab),
                context.tr(LocaleKeys.settings_title),
              ],
            ),
          ),
        ),
        branches: [
          StatefulShellBranch(
            navigatorKey: _branchNavigatorKeys[0],
            routes: [
              GoRoute(
                path: '/feed',
                builder: (_, _) => TabScrollToTop(
                  reselect: reselect,
                  index: 0,
                  child: const FeedPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'composer',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (_, state) => FormSheetPage(
                      key: state.pageKey,
                      // The composer holds a lot, so it opens nearly full
                      // height.
                      maxExtent: 0.985,
                      child: LookComposerPage(
                        preselectedIds:
                            state.uri.queryParametersAll['item'] ?? const [],
                        tryOn: state.uri.queryParameters['mode'] == 'try-on',
                        occasion: state.uri.queryParameters['occasion'],
                        from: state.extra as Look?,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'proposals',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (_, state) => FormSheetPage(
                      key: state.pageKey,
                      maxExtent: 0.985,
                      child: LookProposalsPage(
                        quality: state.uri.queryParameters['quality'] ?? 'low',
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
            navigatorKey: _branchNavigatorKeys[1],
            routes: [
              GoRoute(
                path: '/wardrobe',
                builder: (_, _) => TabScrollToTop(
                  reselect: reselect,
                  index: 1,
                  child: const WardrobePage(),
                ),
                routes: [
                  GoRoute(
                    path: 'intake',
                    builder: (_, _) => const IntakePage(),
                  ),
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
            navigatorKey: _branchNavigatorKeys[2],
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => TabScrollToTop(
                  reselect: reselect,
                  index: 2,
                  child: const SettingsPage(),
                ),
                routes: [
                  ...settingsSubpageRoutes,
                  GoRoute(
                    path: 'server',
                    builder: (_, _) => const ServerPage(),
                  ),
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
                      child: CharacterDetailPage(
                        id: state.pathParameters['id']!,
                      ),
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
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingPage(),
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : FormTokens.sheetDuration,
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.04, end: 1).animate(
                CurvedAnimation(parent: animation, curve: FormTokens.easeOut),
              ),
              child: child,
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'character-setup',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (_, state) => FormSheetPage(
              key: state.pageKey,
              child: const CharacterSetupPage(),
            ),
          ),
        ],
      ),
    ],
  );
}

class FormSheetPage extends Page<void> {
  const FormSheetPage({
    required this.child,
    this.maxExtent = formSheetExtent,
    super.key,
  });
  final Widget child;
  final double maxExtent;

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
    builder: (_) => formSheetDraggableWrapper(child, maxExtent: maxExtent),
  );
}

var _finished = <Look>[];

/// Looks that stopped developing between [previous] and [next].
List<Look> _finishedLooks(FeedState previous, FeedState next) {
  final active = {
    for (final record in previous.looks ?? const <CachedLook>[])
      if (record.look.isActive) record.look.id,
  };
  return [
    for (final record in next.looks ?? const <CachedLook>[])
      if (active.contains(record.look.id) && !record.look.isActive) record.look,
  ];
}

/// Tells the user a look finished while they were outside Looks, with a way
/// back to it. On the Looks tab the pile itself shows the change.
void _announceFinishedLooks(
  BuildContext context,
  StatefulNavigationShell shell,
) {
  if (shell.currentIndex == 0) return;
  final failed = _finished.any((look) => look.state == 'failed');
  showFormToast(
    context,
    context.tr(
      failed ? LocaleKeys.lookFailedNotice : LocaleKeys.lookReadyNotice,
    ),
    action: context.tr(LocaleKeys.lookView),
    onAction: () => shell.goBranch(0),
  );
}
