import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/collection_counts_cubit.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/cached_resource.dart';
import 'package:form_mobile/repository/collection_counts_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

class FoundationPage extends StatelessWidget {
  const FoundationPage({required this.collection, super.key});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final feed = collection == Collection.feed;
    return Scaffold(
      appBar: FormPageHeader(
        title: context.tr(LocaleKeys.appName),
        wordmark: true,
      ),
      body:
          BlocSelector<
            CollectionCountsCubit,
            Map<Collection, CachedResource<int>>,
            CachedResource<int>
          >(
            selector: (state) => state[collection]!,
            builder: (context, state) {
              final failureKey = switch (state.failure) {
                ApiFailure.missingSession => LocaleKeys.missingSession,
                ApiFailure.incompatible => LocaleKeys.incompatible,
                ApiFailure.rejected => LocaleKeys.rejected,
                _ => LocaleKeys.unavailable,
              };
              final count = state.value;
              final text = count == null
                  ? context.tr(
                      state.failure == null ? LocaleKeys.loading : failureKey,
                    )
                  : count == 0
                  ? context.tr(
                      feed ? LocaleKeys.feedEmpty : LocaleKeys.wardrobeEmpty,
                    )
                  : context.tr(
                      feed ? LocaleKeys.feedLoaded : LocaleKeys.wardrobeLoaded,
                      args: ['$count'],
                    );
              return SafeArea(
                child: RefreshIndicator.adaptive(
                  onRefresh: () async {
                    await context.read<ConnectionCubit>().check();
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(FormTokens.gutter),
                    children: [
                      if (state.refreshing) const LinearProgressIndicator(),
                      if (state.stale && count != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: FormNotice(text: context.tr(LocaleKeys.stale)),
                        ),
                      FormEmptyState(
                        title: context.tr(
                          feed
                              ? LocaleKeys.feedTitle
                              : LocaleKeys.wardrobeTitle,
                        ),
                        message: text,
                        icon: feed
                            ? Icons.auto_awesome_outlined
                            : Icons.checkroom_outlined,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr(LocaleKeys.dataStatusBody),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => context.go(
                          feed ? '/feed/status' : '/wardrobe/status',
                        ),
                        child: Text(context.tr(LocaleKeys.dataStatus)),
                      ),
                      Text(
                        context.tr(LocaleKeys.foundationNote),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}

class DataStatusPage extends StatelessWidget {
  const DataStatusPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: FormPageHeader(title: context.tr(LocaleKeys.dataStatus)),
    body: Padding(
      padding: const EdgeInsets.all(FormTokens.gutter),
      child: Text(context.tr(LocaleKeys.dataStatusBody)),
    ),
  );
}
