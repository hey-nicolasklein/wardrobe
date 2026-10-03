import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/reset_section.dart';
import 'package:form_mobile/features/settings/setting_row.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/auth_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/api_error_message.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// Sign-out and account deletion. Hidden until a session token exists.
/// Deletion is the last row on the page and blocks while the request runs.
class AccountSection extends StatefulWidget {
  const AccountSection({super.key});

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    if (!context.read<AuthRepository>().isSignedIn) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingGroup([
          SettingRow(
            label: context.tr(LocaleKeys.auth_signOut),
            onTap: _busy ? null : () => unawaited(_signOut()),
            chevron: false,
          ),
          SettingRow(
            label: context.tr(LocaleKeys.auth_deleteAccount),
            color: _busy ? FormTokens.muted : FormTokens.danger,
            onTap: _busy ? null : () => unawaited(_delete()),
            chevron: false,
            value: _busy ? context.tr(LocaleKeys.auth_deleting) : null,
          ),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 10),
          FormNotice(text: _error!, error: true),
        ],
      ],
    );
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await context.read<AuthRepository>().signOut();
    if (mounted) await _leave();
  }

  Future<void> _delete() async {
    if (context.read<ConnectionCubit>().state != ConnectionStatus.ready) {
      setState(() => _error = context.tr(LocaleKeys.auth_deleteOffline));
      return;
    }
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.auth_deleteTitle),
      message: context.tr(LocaleKeys.auth_deleteBody),
      confirmLabel: context.tr(LocaleKeys.auth_deleteConfirm),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthRepository>().deleteAccount();
    } on FormApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = localizedApiError(context, error);
        });
      }
      return;
    }
    if (mounted) await _leave();
  }

  // Checking first moves the gate to the sign-in page, so clearing the cache
  // does not try to refresh against a session that no longer exists.
  Future<void> _leave() async {
    await context.read<ConnectionCubit>().check();
    if (mounted) await clearAccountState(context);
  }
}
