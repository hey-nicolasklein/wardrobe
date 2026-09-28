import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/widgets/form_components.dart';

/// Debug view of what shapes the feed: per photo style, every shot type with
/// its hearts, recent use, weight, and chance of being drawn next. Switching a
/// shot off hides it from future looks; switching it on brings it back.
class FeedWeightsSection extends StatefulWidget {
  const FeedWeightsSection({super.key});

  @override
  State<FeedWeightsSection> createState() => _FeedWeightsSectionState();
}

class _FeedWeightsSectionState extends State<FeedWeightsSection> {
  List<Map<String, dynamic>>? _shots;
  bool _failed = false;
  final _busy = <String>{};

  LookRepository get _looks => context.read<LookRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final shots = await _looks.shotWeights();
      if (mounted) {
        setState(() {
          _shots = shots;
          _failed = false;
        });
      }
    } on FormApiException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _setVisible(String shot, {required bool visible}) async {
    setState(() => _busy.add(shot));
    try {
      await _looks.setShotHidden(shot, hidden: !visible);
      await _load();
    } on FormApiException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy.remove(shot));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shots = _shots;
    return FormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(LocaleKeys.feedWeights_title),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => unawaited(_load()),
                tooltip: context.tr(LocaleKeys.feedWeights_refresh),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(LocaleKeys.feedWeights_body),
            style: FormTokens.small,
          ),
          const SizedBox(height: 12),
          if (_failed)
            FormNotice(
              text: context.tr(LocaleKeys.feedWeights_failed),
              error: true,
            )
          else if (shots == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            for (final style in lookStyles) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('lookStyle.$style').toUpperCase(),
                style: FormTokens.eyebrow,
              ),
              const SizedBox(height: 4),
              for (final shot in shots.where((s) => s['style'] == style))
                _ShotWeightRow(
                  shot: shot,
                  busy: _busy.contains(shot['shot']),
                  onVisible: (visible) => unawaited(
                    _setVisible(shot['shot'] as String, visible: visible),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _ShotWeightRow extends StatelessWidget {
  const _ShotWeightRow({
    required this.shot,
    required this.busy,
    required this.onVisible,
  });

  final Map<String, dynamic> shot;
  final bool busy;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    final id = shot['shot'] as String;
    final likes = (shot['likes'] as num).toInt();
    final hidden = shot['hidden'] as bool;
    final chance = (shot['chance'] as num).toDouble();
    final weight = (shot['weight'] as num).toDouble();
    final number = NumberFormat.decimalPatternDigits(
      locale: context.locale.toString(),
      decimalDigits: 2,
    );
    final facts = [
      context.tr(
        LocaleKeys.feedWeights_weight,
        namedArgs: {'value': number.format(weight)},
      ),
      if (likes > 0) '$likes ♥',
      if (shot['recent'] == true) context.tr(LocaleKeys.feedWeights_recent),
      if (hidden) context.tr(LocaleKeys.feedWeights_hidden),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: hidden ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('lookShot.$id'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${(chance * 100).round()} %',
                        style: const TextStyle(
                          fontSize: 14,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: chance,
                      minHeight: 6,
                      color: FormTokens.green,
                      backgroundColor: FormTokens.costTrack,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(facts.join(' · '), style: FormTokens.small),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: !hidden,
            onChanged: busy ? null : onVisible,
          ),
        ],
      ),
    );
  }
}
