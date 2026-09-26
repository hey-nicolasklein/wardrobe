import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/collection_counts_cubit.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/auth/sign_in_page.dart';
import 'package:form_mobile/features/intake/intake_bloc.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';

class ConnectionGate extends StatelessWidget {
  const ConnectionGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ConnectionCubit, ConnectionStatus>(
    builder: (context, status) {
      final (title, body) = switch (status) {
        ConnectionStatus.checking => (LocaleKeys.checking, null),
        ConnectionStatus.unavailable => (
          LocaleKeys.unavailable,
          LocaleKeys.unavailableBody,
        ),
        ConnectionStatus.missingSession => (
          LocaleKeys.missingSession,
          LocaleKeys.missingSessionBody,
        ),
        ConnectionStatus.incompatible => (
          LocaleKeys.incompatible,
          LocaleKeys.incompatibleBody,
        ),
        ConnectionStatus.rejected => (
          LocaleKeys.rejected,
          LocaleKeys.rejectedBody,
        ),
        ConnectionStatus.configurationRequired => (
          LocaleKeys.configurationRequired,
          LocaleKeys.configurationRequiredBody,
        ),
        ConnectionStatus.ready => (LocaleKeys.connected, null),
      };
      final hasCache =
          context.watch<IntakeBloc>().state.drafts.isNotEmpty ||
          context.watch<WardrobeCubit>().state.items != null ||
          context.watch<CollectionCountsCubit>().state.values.any(
            (value) => value.value != null,
          );
      final showShell =
          status == ConnectionStatus.ready ||
          (hasCache &&
              (status == ConnectionStatus.checking ||
                  status == ConnectionStatus.unavailable));
      return Stack(
        children: [
          Offstage(offstage: !showShell, child: child),
          if (status == ConnectionStatus.missingSession)
            const SignInPage()
          else if (!showShell)
            Scaffold(
              appBar: FormPageHeader(
                title: context.tr(LocaleKeys.appName),
                wordmark: true,
              ),
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(FormTokens.gutter),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (status == ConnectionStatus.checking)
                          const CircularProgressIndicator.adaptive()
                        else
                          const Icon(
                            Icons.cloud_off_outlined,
                            size: 45,
                            color: FormTokens.emptyIcon,
                          ),
                        const SizedBox(height: 24),
                        Text(
                          context.tr(title),
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        if (body != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            context.tr(body),
                            style: FormTokens.body.copyWith(
                              color: FormTokens.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          if (status != ConnectionStatus.configurationRequired)
                            FilledButton(
                              onPressed: context.read<ConnectionCubit>().check,
                              child: Text(context.tr(LocaleKeys.retry)),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
