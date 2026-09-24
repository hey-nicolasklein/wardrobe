import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/collection_counts_cubit.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/connection_gate.dart';
import 'package:form_mobile/app/form_theme.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/navigation/app_router.dart';
import 'package:form_mobile/repository/collection_counts_repository.dart';
import 'package:go_router/go_router.dart';

class FormApp extends StatefulWidget {
  const FormApp({super.key});

  @override
  State<FormApp> createState() => _FormAppState();
}

class _FormAppState extends State<FormApp> {
  final GoRouter _router = createRouter();
  late final AppLifecycleListener _lifecycle;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(context.read<ConnectionCubit>().check()),
    );
    unawaited(context.read<ConnectionCubit>().check());
  }

  Future<void> _sync(ConnectionStatus status) async {
    final collectionCounts = context.read<CollectionCountsCubit>();
    if (status == ConnectionStatus.ready) {
      final initial = !_hasLoaded;
      _hasLoaded = true;
      final path = _router.routeInformationProvider.value.uri.path;
      await Future.wait([
        if (initial || path.startsWith('/feed'))
          collectionCounts.refresh(Collection.feed),
        if (initial || path.startsWith('/wardrobe'))
          collectionCounts.refresh(Collection.wardrobe),
      ]);
    } else if (status == ConnectionStatus.unavailable) {
      collectionCounts.markUnavailable();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<LanguageCubit, String>(
    listener: (context, language) =>
        unawaited(context.setLocale(Locale(language))),
    child: BlocListener<ConnectionCubit, ConnectionStatus>(
      listener: (context, status) => unawaited(_sync(status)),
      child: MaterialApp.router(
        onGenerateTitle: (context) => context.tr(LocaleKeys.appName),
        debugShowCheckedModeBanner: false,
        theme: formTheme(),
        themeMode: ThemeMode.light,
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        routerConfig: _router,
        builder: (context, child) => ConnectionGate(child: child!),
      ),
    ),
  );
}
