import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_theme.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/features/feed/create_look_page.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_page.dart';
import 'package:form_mobile/features/feed/look_composer_page.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/intake/intake_page.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_page.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

import 'support/wardrobe_fixtures.dart';

class _Localization extends LocalizationsDelegate<Localization> {
  const _Localization();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'de';

  @override
  Future<Localization> load(Locale locale) {
    Localization.load(
      locale,
      translations: Translations(
        jsonDecode(File('assets/translations/de.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
    return SynchronousFuture(Localization.instance);
  }

  @override
  bool shouldReload(_Localization old) => false;
}

class _Wardrobe extends Cubit<WardrobeState> implements WardrobeCubit {
  _Wardrobe(super.initialState);
  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
  }

  void show(WardrobeState next) => emit(next);

  @override
  void filter(WardrobeFilter filter) =>
      emit(WardrobeState(items: state.items, filter: filter, stale: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Intake extends Cubit<IntakeState> implements IntakeBloc {
  _Intake() : super(const IntakeState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements MediaRepository {
  @override
  Future<File?> load(
    String identity, {
    String? previewPath,
    bool online = true,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Feed extends Cubit<FeedState> implements FeedCubit {
  _Feed(super.initialState);
  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection extends Cubit<ConnectionStatus> implements ConnectionCubit {
  _Connection() : super(ConnectionStatus.ready);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Quality extends Cubit<QualityPreferences> implements QualityCubit {
  _Quality() : super(const QualityPreferences(feed: 'low', wardrobe: 'low'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credits extends Cubit<Credits?> implements CreditsCubit {
  _Credits() : super(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Looks implements LookRepository {
  final proposalBodies = <Map<String, dynamic>>[];

  @override
  Future<List<String>> tryOnBases() async => [];

  @override
  Future<void> propose(
    Map<String, dynamic> body, {
    int count = 3,
    bool append = false,
    List<String> excludedItemIds = const [],
    List<String> discardLookIds = const [],
  }) async {
    proposalBodies.add(body);
    throw const FormApiException(ApiFailure.unavailable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CachedItem _piece({
  String id = 'wardrobe-item-0001',
  String state = 'owning',
  String category = 'top',
  bool ready = true,
  String status = 'ready',
}) {
  final json = itemJson(id: id, state: state);
  (json['metadata'] as Map<String, dynamic>)['category'] = category;
  json['status'] = status;
  if (!ready) json['currentShelfImageVersionId'] = null;
  return CachedItem(WardrobeItem.fromJson(json), null);
}

const _delegates = <LocalizationsDelegate<dynamic>>[
  _Localization(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  Future<void> wardrobe(
    WidgetTester tester, {
    WardrobeFilter filter = const WardrobeFilter(),
    bool archived = false,
    bool loading = false,
    GoRouter? router,
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = _Wardrobe(
      WardrobeState(
        items: loading ? null : [],
        filter: filter,
        loading: loading,
        stale: false,
      ),
    );
    final intake = _Intake();
    addTearDown(cubit.close);
    addTearDown(intake.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<WardrobeCubit>.value(value: cubit),
          BlocProvider<IntakeBloc>.value(value: intake),
        ],
        child: router != null
            ? MaterialApp.router(
                routerConfig: router,
                theme: formTheme(),
                locale: const Locale('de'),
                localizationsDelegates: _delegates,
                supportedLocales: const [Locale('de')],
              )
            : MaterialApp(
                theme: formTheme(),
                locale: const Locale('de'),
                localizationsDelegates: _delegates,
                supportedLocales: const [Locale('de')],
                home: WardrobePage(archived: archived),
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (scope, title, action) in [
    (
      'all',
      'Dein Schrank wartet auf sein erstes Stück.',
      'Erste Stücke hinzufügen',
    ),
    ('owning', 'Was trägst du am liebsten?', 'Erste Stücke hinzufügen'),
    ('wanting', 'Was fehlt dir noch?', 'Wunschstück hinzufügen'),
  ]) {
    testWidgets('$scope invites adding and hides finding tools', (
      tester,
    ) async {
      await wardrobe(tester, filter: WardrobeFilter(state: scope));
      expect(find.text(title), findsOneWidget);
      expect(find.text(action), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FormAddButton), findsNothing);
      expect(find.text('Keine passenden Stücke.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wishlist invitation passes a validated intake preference', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/wardrobe',
      routes: [
        GoRoute(path: '/wardrobe', builder: (_, _) => const WardrobePage()),
        GoRoute(
          path: '/wardrobe/intake',
          builder: (_, state) => Scaffold(
            body: Text(
              IntakePage(
                ownership: state.uri.queryParameters['state'],
              ).ownership,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await wardrobe(
      tester,
      filter: const WardrobeFilter(state: 'wanting'),
      router: router,
    );
    await tester.tap(find.text('Wunschstück hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('wanting'), findsOneWidget);
    expect(const IntakePage(ownership: 'archived').ownership, 'owning');
  });

  testWidgets('real filters offer reset and preserve collection', (
    tester,
  ) async {
    await wardrobe(
      tester,
      filter: const WardrobeFilter(state: 'wanting', query: 'coat'),
    );
    expect(find.text('Keine passenden Stücke.'), findsOneWidget);
    await tester.tap(find.text('Filter zurücksetzen'));
    await tester.pumpAndSettle();
    expect(find.text('Was fehlt dir noch?'), findsOneWidget);
  });

  testWidgets('archive explains restoration with a back header and no tools', (
    tester,
  ) async {
    await wardrobe(tester, archived: true);
    expect(find.byType(FormPageHeader), findsOneWidget);
    expect(find.text('Hier ist es aufgeräumt.'), findsOneWidget);
    expect(find.textContaining('jederzeit zurückholen'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('0 von 0'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('initial wardrobe loading shows skeletons', (tester) async {
    await wardrobe(tester, loading: true);
    expect(find.byType(FormPieceSkeletons), findsOneWidget);
    expect(find.byType(FormEmptyState), findsNothing);
  });

  Future<(_Wardrobe, _Feed)> lookSurface(
    WidgetTester tester,
    Widget page,
    List<CachedItem> items, {
    bool feedLoading = false,
    WardrobeState? wardrobeState,
    FeedState? feedState,
    _Looks? lookRepository,
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = _Wardrobe(
      wardrobeState ?? WardrobeState(items: items, stale: false),
    );
    final feed = _Feed(
      feedState ?? FeedState(looks: feedLoading ? null : [], stale: false),
    );
    final connection = _Connection();
    final quality = _Quality();
    final credits = _Credits();
    addTearDown(quality.close);
    addTearDown(credits.close);
    addTearDown(cubit.close);
    addTearDown(feed.close);
    addTearDown(connection.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<MediaRepository>.value(value: _Media()),
          RepositoryProvider<LookRepository>.value(
            value: lookRepository ?? _Looks(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<WardrobeCubit>.value(value: cubit),
            BlocProvider<FeedCubit>.value(value: feed),
            BlocProvider<ConnectionCubit>.value(value: connection),
            BlocProvider<QualityCubit>.value(value: quality),
            BlocProvider<CreditsCubit>.value(value: credits),
          ],
          child: MaterialApp(
            theme: formTheme(),
            locale: const Locale('de'),
            supportedLocales: const [Locale('de')],
            localizationsDelegates: _delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(body: page),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (cubit, feed);
  }

  for (final state in ['owning', 'wanting']) {
    testWidgets('$state without a core guides selection before proposals', (
      tester,
    ) async {
      await lookSurface(tester, const CreateLookPage(), [_piece(state: state)]);
      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Vorschläge zeigen'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('Wähle ein Stück aus.'), findsOneWidget);
      expect(find.text('Stück hinzufügen'), findsOneWidget);
      // A selected wishlist piece also bypasses the automatic-core rule.
      await tester.tap(find.bySemanticsLabel('Linen shirt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Wähle ein Stück aus.'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final state in ['owning', 'wanting']) {
    testWidgets(
      'composer guides $state without a core and permits explicit categories',
      (tester) async {
        await lookSurface(tester, const LookComposerPage(), [
          _piece(state: state),
        ]);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.textContaining('Wähle ein Stück aus.'), findsOneWidget);
        expect(find.text('Stück hinzufügen'), findsOneWidget);
        final context = tester.element(find.text('Stück hinzufügen'));
        final composer = context.read<ComposerCubit>()..toggleCategory('top');
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        expect(find.textContaining('Wähle ein Stück aus.'), findsNothing);
        composer.toggleCategory('dress');
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(
          find.textContaining('Für eine gewählte Kategorie'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pending preselection shows preparation despite another ready piece',
    (tester) async {
      final looks = _Looks();
      await lookSurface(tester, const CreateLookPage(itemIds: ['pending']), [
        _piece(id: 'ready', category: 'dress'),
        _piece(id: 'pending', ready: false, status: 'generating'),
      ], lookRepository: looks);
      expect(
        find.text('Deine Stücke bekommen ihren Auftritt.'),
        findsOneWidget,
      );
      expect(find.text('Vorschläge zeigen'), findsNothing);
      expect(looks.proposalBodies, isEmpty);
    },
  );

  testWidgets('unavailable deep-link selections are dropped before proposing', (
    tester,
  ) async {
    final looks = _Looks();
    await lookSurface(
      tester,
      const CreateLookPage(itemIds: ['archived', 'deleted']),
      [
        _piece(id: 'ready', category: 'dress'),
        _piece(id: 'archived', state: 'archived'),
      ],
      lookRepository: looks,
    );
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorschläge zeigen'));
    await tester.pumpAndSettle();
    expect(looks.proposalBodies.single['exactItemIds'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a selection that loses eligibility cannot bypass the guard', (
    tester,
  ) async {
    final looks = _Looks();
    final (wardrobe, _) = await lookSurface(
      tester,
      const CreateLookPage(itemIds: ['top']),
      [
        _piece(id: 'top'),
      ],
      lookRepository: looks,
    );
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    wardrobe.show(WardrobeState(items: [_piece(id: 'other')]));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.textContaining('Wähle ein Stück aus.'), findsOneWidget);
    expect(looks.proposalBodies, isEmpty);
  });

  for (final (name, wardrobeState, feedState) in [
    (
      'failed wardrobe',
      const WardrobeState(failure: ApiFailure.unavailable),
      const FeedState(looks: [], stale: false),
    ),
    (
      'offline without a snapshot',
      const WardrobeState(),
      const FeedState(looks: [], online: false),
    ),
  ]) {
    testWidgets(
      'Looks with $name shows unavailable and refresh retries both loads',
      (tester) async {
        final (wardrobe, feed) = await lookSurface(
          tester,
          const FeedPage(),
          [],
          wardrobeState: wardrobeState,
          feedState: feedState,
        );
        expect(find.text('Server nicht erreichbar'), findsOneWidget);
        expect(find.text('Erste Stücke hinzufügen'), findsNothing);
        expect(find.byType(FormEmptyState), findsNothing);
        expect(find.bySemanticsLabel('Looks werden geladen'), findsNothing);
        final refresh = tester.widget<CupertinoSliverRefreshControl>(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
        );
        await refresh.onRefresh!();
        expect(wardrobe.refreshes, 1);
        expect(feed.refreshes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Looks waits for the first online wardrobe load', (tester) async {
    await lookSurface(
      tester,
      const FeedPage(),
      [],
      wardrobeState: const WardrobeState(loading: true),
    );
    expect(find.byType(FormEmptyState), findsNothing);
    expect(find.byType(FormNotice), findsNothing);
    expect(find.bySemanticsLabel('Looks werden geladen'), findsOneWidget);
  });

  testWidgets('an owned dress permits proposals without selecting a piece', (
    tester,
  ) async {
    await lookSurface(tester, const CreateLookPage(), [
      _piece(category: 'dress'),
    ]);
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('Wähle ein Stück aus.'), findsNothing);
  });

  for (final (name, page) in <(String, Widget)>[
    ('create', const CreateLookPage()),
    ('composer', const LookComposerPage()),
    ('looks', const FeedPage()),
  ]) {
    for (final status in ['generating', 'failed']) {
      testWidgets(
        '$name with $status catalog images offers preparation, not intake',
        (tester) async {
          await lookSurface(tester, page, [
            _piece(ready: false, status: status),
          ]);
          expect(
            find.text('Deine Stücke bekommen ihren Auftritt.'),
            findsOneWidget,
          );
          expect(find.text('Zum Schrank'), findsOneWidget);
          expect(find.text('Erste Stücke hinzufügen'), findsNothing);
          expect(find.byType(FormAddButton), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('empty Looks hides the header add button', (tester) async {
    await lookSurface(tester, const FeedPage(), []);
    expect(find.byType(FormAddButton), findsNothing);
    expect(find.text('Erste Stücke hinzufügen'), findsOneWidget);
  });

  testWidgets('loading Looks hides the header add button', (tester) async {
    await lookSurface(tester, const FeedPage(), [], feedLoading: true);
    expect(find.byType(FormAddButton), findsNothing);
    expect(find.byType(FormEmptyState), findsNothing);
  });

  testWidgets(
    'create look without owned pieces offers intake before any proposal',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = _Wardrobe(const WardrobeState(items: [], stale: false));
      addTearDown(cubit.close);
      final router = GoRouter(
        initialLocation: '/feed/create',
        routes: [
          GoRoute(
            path: '/feed/create',
            builder: (_, _) => const CreateLookPage(),
          ),
          GoRoute(
            path: '/wardrobe/intake',
            builder: (_, _) => const Scaffold(body: Text('Intake reached')),
          ),
        ],
      );
      addTearDown(router.dispose);
      // No LookRepository is supplied. The empty branch cannot make proposals.
      await tester.pumpWidget(
        BlocProvider<WardrobeCubit>.value(
          value: cubit,
          child: MaterialApp.router(
            routerConfig: router,
            theme: formTheme(),
            locale: const Locale('de'),
            supportedLocales: const [Locale('de')],
            localizationsDelegates: _delegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deine Stücke. Neue Ideen.'), findsOneWidget);
      expect(find.text('Vorschläge zeigen'), findsNothing);
      await tester.tap(find.text('Erste Stücke hinzufügen'));
      await tester.pumpAndSettle();
      expect(find.text('Intake reached'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
