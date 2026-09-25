import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/settings/cost_cubit.dart';
import 'package:form_mobile/features/settings/cost_display.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/generation_cost_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_cost_gauge.dart';

/// Drop into Settings under bootstrap's optional FormApi provider. The section
/// owns and disposes its Cubit, while the app retains ownership of the API.
class CostSection extends StatelessWidget {
  const CostSection({this.repository, super.key});

  final GenerationCostRepository? repository;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final cubit = CostCubit(
        repository ?? GenerationCostRepository(context.read<FormApi?>()),
      );
      unawaited(cubit.refresh());
      return cubit;
    },
    child: const _CostSectionBody(),
  );
}

class _CostSectionBody extends StatelessWidget {
  const _CostSectionBody();

  @override
  Widget build(BuildContext context) => BlocBuilder<CostCubit, CostState>(
    builder: (context, state) {
      final cubit = context.read<CostCubit>();
      return FormPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(LocaleKeys.costs_title),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: context.tr(LocaleKeys.costs_previousWeek),
                  onPressed: state.loading ? null : cubit.previousWeek,
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
                Expanded(
                  child: Semantics(
                    button: !state.isCurrentWeek,
                    label: context.tr(LocaleKeys.costs_thisWeek),
                    child: InkWell(
                      onTap: state.loading || state.isCurrentWeek
                          ? null
                          : cubit.goToCurrentWeek,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                state.isCurrentWeek
                                    ? context.tr(LocaleKeys.costs_thisWeek)
                                    : state.week.label(
                                        context.locale.toString(),
                                      ),
                                textAlign: TextAlign.center,
                                style: FormTokens.body.merge(
                                  FormTokens.numerals,
                                ),
                              ),
                            ),
                            if (state.loading) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: context.tr(
                                    LocaleKeys.costs_loading,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr(LocaleKeys.costs_nextWeek),
                  onPressed: state.loading || !state.canGoNext
                      ? null
                      : cubit.nextWeek,
                  disabledColor: FormTokens.ink.withValues(alpha: 0.25),
                  icon: const Icon(Icons.arrow_forward, size: 20),
                ),
              ],
            ),
            if (state.failure != null) ...[
              FormNotice(
                text: apiFailureText(context, state.failure!),
                error: true,
              ),
              TextButton(
                onPressed: cubit.refresh,
                child: Text(context.tr(LocaleKeys.costs_retry)),
              ),
            ] else if (state.costs != null)
              Opacity(
                opacity: state.loading ? 0.55 : 1,
                child: _CostFigures(
                  key: ValueKey(state.presentationGeneration),
                  display: CostDisplay(state.costs!),
                ),
              )
            else if (state.loading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: context.tr(LocaleKeys.costs_loading),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _CostFigures extends StatelessWidget {
  const _CostFigures({required this.display, super.key});

  final CostDisplay display;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        FormCostGauge(
          values: display.parts.map((part) => part.microunits).toList(),
          total: costMoney(display.totalMicrounits, locale),
          label: context.tr(LocaleKeys.costs_total),
        ),
        const SizedBox(height: 20),
        for (final part in display.parts) _CostLegendRow(part: part),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(LocaleKeys.costs_average),
                  style: FormTokens.body,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                costMoney(display.averageMicrounits, locale),
                style: FormTokens.body.merge(FormTokens.numerals),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CostLegendRow extends StatelessWidget {
  const _CostLegendRow({required this.part});

  final CostPart part;

  @override
  Widget build(BuildContext context) {
    final (label, note, color) = switch (part.source) {
      CostSource.looks => (
        LocaleKeys.costs_looks,
        LocaleKeys.costs_completed,
        costLooksColor,
      ),
      CostSource.wardrobe => (
        LocaleKeys.costs_wardrobe,
        part.count == 1
            ? LocaleKeys.costs_imageOne
            : LocaleKeys.costs_imageMany,
        costWardrobeColor,
      ),
      CostSource.detection => (
        LocaleKeys.costs_detection,
        part.count == 1
            ? LocaleKeys.costs_photoOne
            : LocaleKeys.costs_photoMany,
        costDetectionColor,
      ),
    };
    final small = FormTokens.small.copyWith(fontSize: 11, height: 1.4);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FormTokens.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(label), style: FormTokens.body),
                const SizedBox(height: 4),
                Text(
                  context.tr(note, namedArgs: {'count': '${part.count}'}),
                  style: small,
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                costMoney(part.microunits, context.locale.toString()),
                style: FormTokens.body.merge(FormTokens.numerals),
              ),
              const SizedBox(height: 4),
              Text(
                part.share == null
                    ? context.tr(LocaleKeys.costs_noShare)
                    : context.tr(
                        LocaleKeys.costs_share,
                        namedArgs: {'percent': '${part.share}'},
                      ),
                style: small.merge(FormTokens.numerals),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
