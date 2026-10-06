import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/app_config.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/auth_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/api_error_message.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// Shown by the connection gate when the server wants a session. The first
/// screen offers Apple and Google. `DEV_MODE` adds a one-tap sign-in with the
/// configured dev account, and debug builds add a password-free developer
/// sign-in so simulators skip Apple and Google. Email with password lives on
/// its own page behind a link.
///
/// The gate sits above the router's Navigator, so this page brings its own.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler(
    onPopWithResult: (_) => _navigator.currentState?.maybePop(),
    child: Navigator(
      key: _navigator,
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(builder: (_) => const _ProviderSignIn()),
      ],
    ),
  );
}

/// Shared busy and error handling for both sign-in screens.
mixin _SignInRunner<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function(AuthRepository auth) signIn) async {
    // Read before awaiting: the resume check fired when the Apple or Google
    // sheet closes can swap this page out, and the session check must still
    // run.
    final connection = context.read<ConnectionCubit>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await signIn(context.read<AuthRepository>());
      await connection.check();
    } on SignInCancelled {
      // Closing the sheet is a choice, not a failure.
    } on FormApiException catch (e) {
      if (mounted) setState(() => error = localizedApiError(context, e));
    } on Exception {
      if (mounted) setState(() => error = context.tr(LocaleKeys.auth_failed));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget errorText() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(
      error!,
      style: FormTokens.small.copyWith(color: FormTokens.danger),
      textAlign: TextAlign.center,
    ),
  );
}

class _ProviderSignIn extends StatefulWidget {
  const _ProviderSignIn();

  @override
  State<_ProviderSignIn> createState() => _ProviderSignInState();
}

class _ProviderSignInState extends State<_ProviderSignIn>
    with _SignInRunner<_ProviderSignIn> {
  static const _debugEmail = 'dev@form.local';

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthRepository>();
    final config = context.read<AppConfig>();
    return Scaffold(
      appBar: FormPageHeader(
        title: context.tr(LocaleKeys.appName),
        wordmark: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FormTokens.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(LocaleKeys.auth_title),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                context.tr(LocaleKeys.auth_body),
                style: FormTokens.body.copyWith(color: FormTokens.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (auth.appleAvailable)
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => unawaited(run((a) => a.signInWithApple())),
                  icon: const Icon(Icons.apple),
                  label: Text(context.tr(LocaleKeys.auth_apple)),
                ),
              if (auth.googleAvailable) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(run((a) => a.signInWithGoogle())),
                  child: Text(context.tr(LocaleKeys.auth_google)),
                ),
              ],
              if (config.devSignIn) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(
                          run(
                            (a) => a.signInWithPassword(
                              config.devEmail,
                              config.devPassword,
                            ),
                          ),
                        ),
                  child: Text(context.tr(LocaleKeys.auth_devAccountAction)),
                ),
              ],
              if (kDebugMode) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(
                          run((a) => a.signInForDevelopment(_debugEmail)),
                        ),
                  child: Text(context.tr(LocaleKeys.auth_devAction)),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy
                    ? null
                    : () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _PasswordSignIn(),
                          ),
                        ),
                      ),
                child: Text(context.tr(LocaleKeys.auth_passwordLink)),
              ),
              if (error != null) errorText(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordSignIn extends StatefulWidget {
  const _PasswordSignIn();

  @override
  State<_PasswordSignIn> createState() => _PasswordSignInState();
}

class _PasswordSignInState extends State<_PasswordSignIn>
    with _SignInRunner<_PasswordSignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => unawaited(
    run((a) => a.signInWithPassword(_email.text.trim(), _password.text)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: FormPageHeader(title: context.tr(LocaleKeys.auth_emailTitle)),
    body: SafeArea(
      child: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.all(FormTokens.gutter),
          children: [
            TextField(
              controller: _email,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.auth_email),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofocus: true,
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: context.tr(LocaleKeys.auth_password),
              ),
              obscureText: true,
              textInputAction: TextInputAction.go,
              onSubmitted: busy ? null : (_) => _submit(),
              autofillHints: const [AutofillHints.password],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : _submit,
              child: Text(context.tr(LocaleKeys.auth_emailAction)),
            ),
            if (error != null) errorText(),
          ],
        ),
      ),
    ),
  );
}
