import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/overview_cubit.dart';
import 'package:form_mobile/app/safe_bloc_observer.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/repository/overview_repository.dart';
import 'package:form_mobile/repository/preferences_repository.dart';
import 'package:form_mobile/repository/server_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/initial_language.dart';

Future<void> main() async {
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

  final overviewRepository = OverviewRepository(
    database,
    api,
    uri?.toString() ?? '',
  );
  final overview = OverviewCubit(overviewRepository);
  await overview.loadCache();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OverviewRepository>.value(value: overviewRepository),
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
          BlocProvider(create: (_) => overview),
          BlocProvider(create: (_) => LanguageCubit(preferences, language)),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('de'), Locale('en')],
          fallbackLocale: const Locale('de'),
          startLocale: Locale(language),
          saveLocale: false,
          path: 'assets/translations',
          child: const FormApp(),
        ),
      ),
    ),
  );
}
