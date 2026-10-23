import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';

class WardrobeEmptyState extends StatelessWidget {
  const WardrobeEmptyState({
    required this.filter,
    required this.archived,
    required this.onAdd,
    required this.onReset,
    super.key,
  });

  final WardrobeFilter filter;
  final bool archived;
  final VoidCallback onAdd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (filter.isFiltered) {
      return FormEmptyState(
        title: context.tr(LocaleKeys.filteredEmpty),
        icon: Icons.search_rounded,
        action: OutlinedButton(
          onPressed: onReset,
          child: Text(context.tr(LocaleKeys.resetFilters)),
        ),
      );
    }
    final (title, body, scene) = archived
        ? (
            LocaleKeys.archiveEmptyTitle,
            LocaleKeys.archiveEmptyBody,
            FormEmptyScene.archive,
          )
        : switch (filter.state) {
            'owning' => (
              LocaleKeys.wardrobeOwningEmpty,
              LocaleKeys.wardrobeOwningEmptyBody,
              FormEmptyScene.owning,
            ),
            'wanting' => (
              LocaleKeys.wardrobeWantingEmpty,
              LocaleKeys.wardrobeWantingEmptyBody,
              FormEmptyScene.wishlist,
            ),
            _ => (
              LocaleKeys.wardrobeEmpty,
              LocaleKeys.wardrobeEmptyBody,
              FormEmptyScene.wardrobe,
            ),
          };
    return FormEmptyState(
      title: context.tr(title),
      message: context.tr(body),
      scene: scene,
      action: archived
          ? null
          : FilledButton(
              onPressed: onAdd,
              child: Text(
                context.tr(
                  filter.state == 'wanting'
                      ? LocaleKeys.wardrobeWantingAdd
                      : LocaleKeys.wardrobeFirstAdd,
                ),
              ),
            ),
    );
  }
}
