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
              const SizedBox(height: 10),
              Text(
                context.tr('lookStyle.$style').toUpperCase(),
                style: FormTokens.eyebrow,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final shot in shots.where((s) => s['style'] == style))
                    _ShotChip(
                      shot: shot,
                      busy: _busy.contains(shot['shot']),
                      onTap: () => unawaited(
                        _setVisible(
                          shot['shot'] as String,
                          visible: shot['hidden'] as bool,
                        ),
                      ),
                    ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

/// One shot type as a pill: its chance of being drawn next, tinted by that
/// chance, and its hearts. Tapping hides or shows it; a long press explains the
/// weight behind the number.
class _ShotChip extends StatelessWidget {
  const _ShotChip({
    required this.shot,
    required this.busy,
    required this.onTap,
  });

  final Map<String, dynamic> shot;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = shot['shot'] as String;
    final likes = (shot['likes'] as num).toInt();
    final hidden = shot['hidden'] as bool;
    final chance = (shot['chance'] as num).toDouble();
    final weight = NumberFormat.decimalPatternDigits(
      locale: context.locale.toString(),
      decimalDigits: 2,
    ).format((shot['weight'] as num).toDouble());
    final details = [
      context.tr(LocaleKeys.feedWeights_weight, namedArgs: {'value': weight}),
      if (shot['recent'] == true) context.tr(LocaleKeys.feedWeights_recent),
    ].join(' · ');
    final ink = hidden ? FormTokens.muted : FormTokens.ink;
    return Tooltip(
      message: details,
      triggerMode: TooltipTriggerMode.longPress,
      child: Semantics(
        button: true,
        toggled: !hidden,
        child: GestureDetector(
          onTap: busy ? null : onTap,
          child: AnimatedContainer(
            duration: FormTokens.quick,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hidden
                  ? Colors.transparent
                  : Color.lerp(
                      FormTokens.pill,
                      FormTokens.selectedTint,
                      (chance * 2.5).clamp(0, 1),
                    ),
              borderRadius: BorderRadius.circular(FormTokens.chipRadius),
              border: Border.all(
                color: hidden ? FormTokens.line : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hidden) ...[
                  const Icon(
                    Icons.visibility_off_outlined,
                    size: 14,
                    color: FormTokens.muted,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  context.tr('lookShot.$id'),
                  style: TextStyle(
                    fontSize: 13,
                    color: ink,
                    decoration: hidden ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (!hidden) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${(chance * 100).round()} %',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FormTokens.green,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (likes > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '♥ $likes',
                    style: const TextStyle(
                      fontSize: 12,
                      color: FormTokens.liked,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
