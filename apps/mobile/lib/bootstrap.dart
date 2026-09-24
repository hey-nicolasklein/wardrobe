import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/collection_counts_cubit.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/safe_bloc_observer.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/repository/collection_counts_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/repository/preferences_repository.dart';
import 'package:form_mobile/repository/server_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/initial_language.dart';
import 'package:path_provider/path_provider.dart';

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = SafeBlocObserver();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableLevels = [];

  final config = AppConfig.fromEnvironment();
  final database = AppDatabase.open();
  final preferences = PreferencesRepository(database);
  final savedLanguage = await preferences.language();
  final deviceLanguage =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  final language = initialLanguage(
    deviceLanguage: deviceLanguage,
    savedLanguage: savedLanguage,
  );
  final uri = config.apiUri;
  final api = uri == null ? null : FormApi.connect(uri);
  final server = api == null ? null : ServerRepository(api);

  final collectionCountsRepository = CollectionCountsRepository(
    database,
    api,
    uri?.toString() ?? '',
  );
  final collectionCounts = CollectionCountsCubit(collectionCountsRepository);
  await collectionCounts.loadCache();
  final cacheDirectory = await getApplicationCacheDirectory();
  final media = MediaRepository(
    database,
    api,
    uri?.toString() ?? '',
    Directory('${cacheDirectory.path}/media'),
  );
  final wardrobeRepository = WardrobeRepository(
    database,
    api,
    uri?.toString() ?? '',
    media,
  );
  final wardrobe = WardrobeCubit(wardrobeRepository);
  await wardrobe.loadCache();
  final app = await builder();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<MediaRepository>.value(value: media),
        RepositoryProvider<WardrobeRepository>(
          create: (_) => wardrobeRepository,
          dispose: (repository) => repository.close(),
        ),
        RepositoryProvider<CollectionCountsRepository>.value(
          value: collectionCountsRepository,
        ),
        RepositoryProvider<AppConfig>.value(value: config),
        RepositoryProvider<AppDatabase>(
          create: (_) => database,
          dispose: (db) => db.close(),
        ),
        RepositoryProvider<PreferencesRepository>.value(value: preferences),
        if (api != null)
          RepositoryProvider<FormApi>(
            create: (_) => api,
            dispose: (api) => api.close(),
          ),
        if (server != null)
          RepositoryProvider<ServerRepository>.value(value: server),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ConnectionCubit(server)),
          BlocProvider(create: (_) => collectionCounts),
          BlocProvider(create: (_) => wardrobe),
          BlocProvider(create: (_) => LanguageCubit(preferences, language)),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('de'), Locale('en')],
          fallbackLocale: const Locale('de'),
          startLocale: Locale(language),
          saveLocale: false,
          path: 'assets/translations',
          child: app,
        ),
      ),
    ),
  );
}
