// End-to-end check of creating and viewing looks against a running local API.
//
// Needs `npm run dev:api` and `npm run dev:worker` with `DEV_SIGN_IN=true`, and
// `npm run dev:seed` so the dev account has pieces. Run from apps/mobile:
//
//   fvm flutter test integration_test/looks_flow_test.dart \
//     -d <simulator> --flavor development \
//     --dart-define-from-file .env.simulator.json
//
// It signs in as dev@form.local and saves one free combination from the
// swipe deck. It never starts a paid image.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/fitting_room_card.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_tile.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/main.dart' as app;
import 'package:form_mobile/widgets/form_components.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a look from the deck is saved, listed and opens laid flat', (
    tester,
  ) async {
    await app.main();
    // A fresh install opens with onboarding and, once signed out, sign-in.
    // Step through whichever shows until the tab bar is there.
    final gates = [
      LocaleKeys.onboarding_skip,
      LocaleKeys.onboarding_finaleExplore,
      LocaleKeys.auth_devAction,
    ];
    for (var i = 0; i < 6 && !_visible(LocaleKeys.feed.tr()); i++) {
      await _pumpUntil(
        tester,
        () =>
            _visible(LocaleKeys.feed.tr()) ||
            gates.any((g) => _visible(g.tr())),
        'onboarding, sign-in or the tab bar',
      );
      final gate = gates.where((g) => _visible(g.tr())).firstOrNull;
      if (gate != null && !_visible(LocaleKeys.feed.tr())) {
        await tester.tap(find.text(gate.tr()).first);
      }
    }
    await _pumpUntil(
      tester,
      () => _visible(LocaleKeys.feed.tr()),
      'the tab bar after onboarding and sign-in',
    );

    await tester.tap(find.text(LocaleKeys.feed.tr()).last);
    final feed = tester
        .element(find.text(LocaleKeys.feed.tr()).last)
        .read<FeedCubit>();
    await _pumpUntil(
      tester,
      () => feed.state.looks != null && !feed.state.loading,
      'looks to load',
    );
    final before = {
      for (final record in feed.state.archive)
        if (record.look.isCombination) record.look.id,
    };

    // Looks without an image are listed, laid out flat.
    if (before.isNotEmpty) {
      await _openAllLooks(tester);
      expect(
        find.descendant(
          of: find.byType(LookTile),
          matching: find.byType(FlatLayBoard),
        ),
        findsWidgets,
      );
      await _back(tester);
    }

    // Create look: skip both steps, save the first proposal.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is FormAddButton && w.label == LocaleKeys.createLook.tr(),
      ),
    );
    await _pumpUntil(
      tester,
      () => _visible(LocaleKeys.createSkip.tr()),
      'the occasion step',
    );
    await tester.tap(find.text(LocaleKeys.createSkip.tr()));
    await _pumpUntil(
      tester,
      () => _visible(LocaleKeys.createShowAll.tr()),
      'the pieces step',
    );
    await tester.tap(find.text(LocaleKeys.createShowAll.tr()));
    await _pumpUntil(
      tester,
      _canSave,
      'a planned proposal',
      timeout: const Duration(seconds: 90),
    );
    await tester.tap(_saveAction);
    await _pumpUntil(
      tester,
      () => feed.state.archive.any(
        (r) => r.look.isCombination && !before.contains(r.look.id),
      ),
      'the saved combination in the Looks archive',
    );
    final created = feed.state.archive.firstWhere(
      (r) => r.look.isCombination && !before.contains(r.look.id),
    );
    expect(created.look.assetId, isNull);
    await tester.tap(find.text(LocaleKeys.proposalsDone.tr()).first);
    await _settle(tester);

    // The new look is a card in the grid and opens laid flat, with both paid
    // images offered on its page.
    await _openAllLooks(tester);
    final tile = find.byWidgetPredicate(
      (w) => w is LookTile && w.record.look.id == created.look.id,
    );
    await _pumpUntil(tester, () => tile.evaluate().isNotEmpty, 'its card');
    expect(
      find.descendant(of: tile, matching: find.byType(FlatLayBoard)),
      findsOneWidget,
    );
    await tester.tap(tile);
    await _pumpUntil(
      tester,
      () => find.byType(FittingRoomCard).evaluate().isNotEmpty,
      'the look page',
    );
    expect(find.text(LocaleKeys.lookTryOn.tr()), findsWidgets);
    expect(find.text(LocaleKeys.lookInspiration.tr()), findsWidgets);
  });
}

bool _visible(String text) => find.text(text).evaluate().isNotEmpty;

/// The deck's save button: the filled round icon above "Save".
final Finder _saveAction = find.widgetWithIcon(
  IconButton,
  Icons.bookmark_add_outlined,
);

bool _canSave() => _saveAction.evaluate().any(
  (e) => (e.widget as IconButton).onPressed != null,
);

Future<void> _openAllLooks(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => _visible(LocaleKeys.stackAll.tr()),
    'the "all looks" stack',
  );
  await tester.tap(find.text(LocaleKeys.stackAll.tr()).first);
  await _pumpUntil(
    tester,
    () => find.byType(LookTile).evaluate().isNotEmpty,
    'the looks grid',
  );
}

/// Pops the top route, like the system back gesture.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

/// The feed animates forever (sheens, fans), so pumpAndSettle never returns.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .nonNulls
          .take(30);
      fail('Timed out waiting for $what. On screen: ${texts.join(' | ')}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await _settle(tester);
}
