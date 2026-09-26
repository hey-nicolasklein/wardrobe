import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/auth_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/api_error_message.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// Shown by the connection gate when the server wants a session. Debug builds
/// add a password-free developer sign-in so simulators skip Apple and Google.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _devEmail = TextEditingController(text: 'dev@form.local');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _devEmail.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthRepository auth) signIn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signIn(context.read<AuthRepository>());
      if (!mounted) return;
      await context.read<ConnectionCubit>().check();
    } on SignInCancelled {
      // Closing the sheet is a choice, not a failure.
    } on FormApiException catch (error) {
      if (mounted) setState(() => _error = localizedApiError(context, error));
    } on Exception {
      if (mounted) setState(() => _error = context.tr(LocaleKeys.auth_failed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthRepository>();
    return Scaffold(
      appBar: FormPageHeader(
        title: context.tr(LocaleKeys.appName),
        wordmark: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FormTokens.gutter),
          children: [
            const SizedBox(height: 40),
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
                onPressed: _busy
                    ? null
                    : () => unawaited(_run((a) => a.signInWithApple())),
                icon: const Icon(Icons.apple),
                label: Text(context.tr(LocaleKeys.auth_apple)),
              ),
            if (auth.googleAvailable) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_run((a) => a.signInWithGoogle())),
                child: Text(context.tr(LocaleKeys.auth_google)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: FormTokens.small.copyWith(color: FormTokens.danger),
                textAlign: TextAlign.center,
              ),
            ],
            if (kDebugMode) ...[
              const SizedBox(height: 40),
              Text(
                context.tr(LocaleKeys.auth_devTitle),
                style: FormTokens.small,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _devEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _run(
                          (a) => a.signInForDevelopment(_devEmail.text.trim()),
                        ),
                      ),
                child: Text(context.tr(LocaleKeys.auth_devAction)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
