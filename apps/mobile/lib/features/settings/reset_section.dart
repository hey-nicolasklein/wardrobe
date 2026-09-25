import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/collection_counts_cubit.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/features/settings/reset_confirmation.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/account_cache_repository.dart';
import 'package:form_mobile/repository/collection_counts_repository.dart';
import 'package:form_mobile/repository/personal_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/api_error_message.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class ResetSection extends StatelessWidget {
  const ResetSection({super.key});

  @override
  Widget build(BuildContext context) => FormPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.settings_resetTitle),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(LocaleKeys.settings_resetBody),
          style: FormTokens.small,
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: FormTokens.dangerTint,
            foregroundColor: FormTokens.ink,
          ),
          onPressed: () => _openResetSheet(context),
          child: Text(context.tr(LocaleKeys.settings_resetAction)),
        ),
      ],
    ),
  );

  Future<void> _openResetSheet(BuildContext context) async {
    if (context.read<ConnectionCubit>().state != ConnectionStatus.ready) {
      showFormToast(context, context.tr(LocaleKeys.settings_resetOffline));
      return;
    }
    await showFormSheet<void>(
      context: context,
      builder: (_) => FormSheet(
        title: context.tr(LocaleKeys.settings_resetSheetTitle),
        child: _ResetSheet(onSuccess: () => _afterReset(context)),
      ),
    );
  }

  Future<void> _afterReset(BuildContext context) async {
    final accountCache = context.read<AccountCacheRepository>();
    await accountCache.clearAfterReset();
    if (!context.mounted) return;
    context.read<IntakeBloc>().add(const IntakeEvent(IntakeAction.restore));
    await Future.wait([
      context.read<WardrobeCubit>().loadCache(),
      context.read<FeedCubit>().loadCache(),
      context.read<CharacterCubit>().loadCache(),
      context.read<CollectionCountsCubit>().loadCache(),
    ]);
    if (!context.mounted) return;
    final connection = context.read<ConnectionCubit>().state;
    if (connection == ConnectionStatus.ready) {
      await Future.wait([
        context.read<CollectionCountsCubit>().refresh(Collection.feed),
        context.read<CollectionCountsCubit>().refresh(Collection.wardrobe),
        context.read<FeedCubit>().refresh(),
        context.read<WardrobeCubit>().refresh(),
        context.read<CharacterCubit>().refresh(),
      ]);
    }
    if (!context.mounted) return;
    showFormToast(context, context.tr(LocaleKeys.settings_resetDone));
    context.go('/feed');
  }
}

class _ResetSheet extends StatefulWidget {
  const _ResetSheet({required this.onSuccess});

  final Future<void> Function() onSuccess;

  @override
  State<_ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends State<_ResetSheet> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final language = context.locale.languageCode;
    if (!matchesResetPhrase(language, _controller.text)) {
      setState(
        () => _error = context.tr(
          LocaleKeys.settings_resetPhraseMismatch,
          namedArgs: {'phrase': requiredResetPhrase(language)},
        ),
      );
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await context.read<PersonalRepository>().resetWardrobe();
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onSuccess();
    } on FormApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = localizedApiError(context, error);
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = context.tr(LocaleKeys.settings_resetFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.locale.languageCode;
    final phrase = requiredResetPhrase(language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(LocaleKeys.settings_resetSheetHeading),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(LocaleKeys.settings_resetSheetBody),
          style: FormTokens.body,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: context.tr(
              LocaleKeys.settings_resetPhraseLabel,
              namedArgs: {'phrase': phrase},
            ),
            hintText: phrase,
            errorText: _error,
          ),
          onSubmitted: (_) => unawaited(_submit()),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: FormTokens.dangerTint,
            foregroundColor: FormTokens.ink,
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _submitting ? null : () => unawaited(_submit()),
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.tr(LocaleKeys.settings_resetConfirm)),
        ),
      ],
    );
  }
}
