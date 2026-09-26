import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/reset_section.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/auth_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/api_error_message.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// Sign-out and account deletion. Hidden on the private deployment, which
/// opens its account without a session token.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.read<AuthRepository>().isSignedIn) {
      return const SizedBox.shrink();
    }
    return FormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(LocaleKeys.auth_accountTitle),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => unawaited(_signOut(context)),
            child: Text(context.tr(LocaleKeys.auth_signOut)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FormTokens.dangerTint,
              foregroundColor: FormTokens.ink,
            ),
            onPressed: () => unawaited(_delete(context)),
            child: Text(context.tr(LocaleKeys.auth_deleteAccount)),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await context.read<AuthRepository>().signOut();
    if (context.mounted) await _leave(context);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.auth_deleteTitle),
      message: context.tr(LocaleKeys.auth_deleteBody),
      confirmLabel: context.tr(LocaleKeys.auth_deleteConfirm),
    );
    if (!confirmed || !context.mounted) return;
    try {
      await context.read<AuthRepository>().deleteAccount();
    } on FormApiException catch (error) {
      if (context.mounted) {
        showFormToast(context, localizedApiError(context, error));
      }
      return;
    }
    if (context.mounted) await _leave(context);
  }

  // Checking first moves the gate to the sign-in page, so clearing the cache
  // does not try to refresh against a session that no longer exists.
  Future<void> _leave(BuildContext context) async {
    await context.read<ConnectionCubit>().check();
    if (context.mounted) await clearAccountState(context);
  }
}
