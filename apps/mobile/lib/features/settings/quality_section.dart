import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/widgets/form_components.dart';

class QualitySection extends StatelessWidget {
  const QualitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final qualities = context.watch<QualityCubit>().state;
    final cubit = context.read<QualityCubit>();
    return FormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(LocaleKeys.settings_qualityTitle),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(LocaleKeys.settings_qualityBody),
            style: FormTokens.small,
          ),
          const SizedBox(height: 16),
          _QualityRow(
            label: context.tr(LocaleKeys.feed),
            selected: qualities.feed,
            onSelected: cubit.setFeed,
          ),
          const SizedBox(height: 16),
          _QualityRow(
            label: context.tr(LocaleKeys.visual_wardrobeTab),
            selected: qualities.wardrobe,
            onSelected: cubit.setWardrobe,
          ),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: FormTokens.body.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 9),
      FormChoiceChips(
        options: {
          for (final quality in qualities)
            quality: context.tr('quality.$quality'),
        },
        selected: selected,
        onSelected: onSelected,
      ),
    ],
  );
}
