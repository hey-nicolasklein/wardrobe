import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

class FormPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const FormPageHeader({
    required this.title,
    this.action,
    this.subtitle,
    this.wordmark = false,
    super.key,
  });
  final String title;
  final Widget? action;
  final String? subtitle;
  final bool wordmark;

  @override
  Size get preferredSize => Size.fromHeight(wordmark ? 72 : 96);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: preferredSize.height,
    titleSpacing: FormTokens.gutter,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: wordmark ? FormTokens.wordmark : FormTokens.heading),
        if (subtitle != null) Text(subtitle!, style: FormTokens.small),
      ],
    ),
    actions: [
      if (action != null)
        Padding(
          padding: const EdgeInsets.only(right: FormTokens.gutter),
          child: action,
        ),
    ],
  );
}

class FormTabBar extends StatelessWidget {
  const FormTabBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.labels,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: FormTokens.paper,
      border: Border(top: BorderSide(color: FormTokens.line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == selectedIndex,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: i == selectedIndex
                          ? FormTokens.green
                          : FormTokens.muted,
                      minimumSize: const Size(44, 49),
                      padding: const EdgeInsets.all(4),
                    ),
                    onPressed: () => onSelected(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FormIcon(
                          FormIconName.values[i],
                          color: i == selectedIndex
                              ? FormTokens.green
                              : FormTokens.muted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == selectedIndex
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class FormEmptyState extends StatelessWidget {
  const FormEmptyState({
    required this.title,
    this.message,
    this.icon = Icons.checkroom_outlined,
    this.action,
    super.key,
  });
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 45, color: FormTokens.emptyIcon),
        const SizedBox(height: 20),
        Text(title, style: FormTokens.heading, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: FormTokens.body.copyWith(color: FormTokens.muted),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class FormNotice extends StatelessWidget {
  const FormNotice({required this.text, this.error = false, super.key});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    decoration: BoxDecoration(
      color: error ? FormTokens.dangerTint : FormTokens.field,
      borderRadius: BorderRadius.circular(FormTokens.inputRadius),
    ),
    child: Text(
      text,
      style: FormTokens.small.copyWith(
        color: error ? FormTokens.danger : FormTokens.noteInk,
      ),
    ),
  );
}

class FormPanel extends StatelessWidget {
  const FormPanel({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(21),
    decoration: BoxDecoration(
      color: FormTokens.surface,
      border: Border.all(color: FormTokens.line),
      borderRadius: BorderRadius.circular(FormTokens.panelRadius),
    ),
    child: child,
  );
}

class FormImageCard extends StatelessWidget {
  const FormImageCard({
    required this.child,
    this.aspectRatio = 0.75,
    super.key,
  });
  final Widget child;
  final double aspectRatio;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(FormTokens.cardRadius),
    child: AspectRatio(
      aspectRatio: aspectRatio,
      child: ColoredBox(color: FormTokens.field, child: child),
    ),
  );
}

class FormSearchField extends StatelessWidget {
  const FormSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
    super.key,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      fillColor: FormTokens.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FormTokens.inputRadius),
        borderSide: BorderSide.none,
      ),
      prefixIcon: const Icon(Icons.search, size: 19),
      suffixIcon: onClear == null
          ? null
          : IconButton(
              onPressed: onClear,
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.close, size: 19),
            ),
    ),
  );
}

class FormChoiceChips extends StatelessWidget {
  const FormChoiceChips({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String>? onSelected;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FormTokens.field,
      borderRadius: BorderRadius.circular(FormTokens.cardRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                selected: entry.key == selected,
                child: TextButton(
                  onPressed: onSelected == null
                      ? null
                      : () => onSelected!(entry.key),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 9,
                    ),
                    minimumSize: const Size(44, 42),
                    backgroundColor: entry.key == selected
                        ? FormTokens.green
                        : Colors.transparent,
                    foregroundColor: entry.key == selected
                        ? Colors.white
                        : FormTokens.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: Text(entry.value, textAlign: TextAlign.center),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<T?> showFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: AnimationStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FormTokens.sheetDuration,
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FormTokens.sheetDuration,
  ),
  builder: builder,
);

class FormSheet extends StatelessWidget {
  const FormSheet({required this.title, required this.child, super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight =
        (MediaQuery.sizeOf(context).height * 0.92 - viewInsets.top).clamp(
          240.0,
          double.infinity,
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FormTokens.gutter,
        8,
        FormTokens.gutter,
        25 + viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => context.pop(),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: FormTokens.field,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmFormAction({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: Text(dialogContext.tr(LocaleKeys.cancel)),
          ),
          TextButton(
            onPressed: () => dialogContext.pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;
