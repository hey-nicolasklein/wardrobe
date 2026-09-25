import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';
import 'package:inspire_blur/inspire_blur.dart';

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
  Size get preferredSize => Size.fromHeight(wordmark ? 56 : 76);

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: [
      const _ScrollAwareBlur(solid: true),
      AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        toolbarHeight: preferredSize.height,
        titleSpacing: FormTokens.gutter,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: wordmark ? FormTokens.wordmark : FormTokens.heading,
            ),
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
      ),
    ],
  );
}

/// App bar slot for tab pages whose [FormWordmark] scrolls with the content.
/// It takes no layout space, only the scroll edge blur. Use with
/// `extendBodyBehindAppBar`.
class FormScrollEdge extends StatelessWidget implements PreferredSizeWidget {
  const FormScrollEdge({super.key});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const AnnotatedRegion(
    value: SystemUiOverlayStyle.dark,
    // The scaffold only caps the app bar slot's height, so expand to fill it
    // instead of collapsing to zero.
    child: SizedBox.expand(
      child: Stack(clipBehavior: Clip.none, children: [_ScrollAwareBlur()]),
    ),
  );
}

/// Scroll edge behind an app bar slot. The blur covers the slot and hangs
/// [_overhang] below it, so the fade happens under the header instead of
/// across it. [solid] swaps the blur for opaque paper that stays inside the
/// slot and fades out over its bottom padding, leaving more room for content.
/// Either way it fades in once the page scrolls, keeping the content sharp at
/// rest. The parent Stack must not clip.
class _ScrollAwareBlur extends StatefulWidget {
  const _ScrollAwareBlur({this.solid = false});
  final bool solid;

  static const _overhang = 32.0;

  @override
  State<_ScrollAwareBlur> createState() => _ScrollAwareBlurState();
}

class _ScrollAwareBlurState extends State<_ScrollAwareBlur> {
  ScrollNotificationObserverState? _observer;
  double _visibility = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context)
      ?..addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  // Only the page's own vertical scroll counts, not nested carousels.
  void _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return;
    }
    final visibility =
        (notification.metrics.pixels / _ScrollAwareBlur._overhang).clamp(
          0.0,
          1.0,
        );
    if (visibility != _visibility) setState(() => _visibility = visibility);
  }

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    bottom: widget.solid ? 0 : -_ScrollAwareBlur._overhang,
    // Scales blur strength rather than using Opacity, which a backdrop blur
    // ignores (it would pop in at full strength). Linear keeps the blur
    // strong further down than the default curve.
    child: IgnorePointer(
      child: widget.solid
          ? Opacity(
              opacity: _visibility,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ColoredBox(color: FormTokens.paper)),
                  SizedBox(
                    height: 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [FormTokens.paper, Color(0x00F6F5F1)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _ScrollEdgeBlur(fadeCurve: Curves.linear, strength: _visibility),
    ),
  );
}

/// FORM wordmark row at the top of a tab's scroll content, with an optional
/// trailing [action].
class FormWordmark extends StatelessWidget {
  const FormWordmark({required this.title, this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: [
        Expanded(child: Text(title, style: FormTokens.wordmark)),
        ?action,
      ],
    ),
  );
}

/// iOS-style scroll edge: content passing under the header blurs
/// progressively towards the top and is washed with paper, fading out to
/// nothing at the bottom edge. It only shows when the scaffold uses
/// `extendBodyBehindAppBar`.
class _ScrollEdgeBlur extends StatelessWidget {
  const _ScrollEdgeBlur({
    this.fadeCurve = Curves.easeInSine,
    this.strength = 1,
  });
  final Curve fadeCurve;

  /// 0 to 1, scales both blur and tint.
  final double strength;

  @override
  Widget build(BuildContext context) => Inspire.backdropBlur(
    config: InspireBlurConfig.topToBottom(
      sigma: 12 * strength,
      fadeCurve: fadeCurve,
    ),
    child: Inspire.tint.topToBottom(
      color: FormTokens.paper,
      opacity: 0.9 * strength,
    ),
  );
}

/// Page intro shared by the feed and wardrobe tabs, matching the PWA's
/// `.hero`: eyebrow, serif headline and summary, with an optional round add
/// button aligned to the bottom edge.
class FormHero extends StatelessWidget {
  const FormHero({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.addLabel,
    this.onAdd,
    super.key,
  });
  final String eyebrow;
  final String title;
  final String body;
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 25),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: FormTokens.eyebrow),
              const SizedBox(height: 6),
              Text(title, style: FormTokens.display.copyWith(fontSize: 36)),
              const SizedBox(height: 6),
              Text(
                body,
                style: FormTokens.body.copyWith(color: FormTokens.muted),
              ),
            ],
          ),
        ),
        if (onAdd != null) ...[
          const SizedBox(width: 15),
          Semantics(
            button: true,
            label: addLabel,
            child: Material(
              color: FormTokens.green,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onAdd,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.add, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
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

  // Frosted paper: mostly opaque, with a hint of blurred content showing
  // through. Needs `extendBody` on the hosting scaffold.
  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FormTokens.paper.withValues(alpha: 0.85),
          border: const Border(top: BorderSide(color: FormTokens.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: _FormTab(
                      icon: FormIconName.values[i],
                      label: labels[i],
                      selected: i == selectedIndex,
                      onPressed: () {
                        if (i != selectedIndex) {
                          unawaited(HapticFeedback.lightImpact());
                        }
                        onSelected(i);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One tab bar entry. While held, icon and label sink slightly and fade, then
/// spring back on release in place of a ripple.
class _FormTab extends StatefulWidget {
  const _FormTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final FormIconName icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_FormTab> createState() => _FormTabState();
}

class _FormTabState extends State<_FormTab> {
  final _states = WidgetStatesController();
  var _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(() {
      final pressed = _states.value.contains(WidgetState.pressed);
      if (pressed != _pressed) setState(() => _pressed = pressed);
    });
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    selected: widget.selected,
    child: TextButton(
      statesController: _states,
      style: TextButton.styleFrom(
        foregroundColor: widget.selected ? FormTokens.green : FormTokens.muted,
        minimumSize: const Size(44, 49),
        padding: const EdgeInsets.all(4),
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.transparent,
      ),
      onPressed: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: _pressed
            ? const Duration(milliseconds: 90)
            : FormTokens.sheetDuration,
        curve: _pressed ? FormTokens.easeOut : FormTokens.pop,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.6 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 90)
              : FormTokens.quick,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FormTabIcon(widget.icon, selected: widget.selected),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Tab icon that plays a short pop each time its tab becomes selected. The
/// closet also swings like a hanger and the settings gear turns.
class _FormTabIcon extends StatefulWidget {
  const _FormTabIcon(this.name, {required this.selected});
  final FormIconName name;
  final bool selected;

  @override
  State<_FormTabIcon> createState() => _FormTabIconState();
}

class _FormTabIconState extends State<_FormTabIcon>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  // Squash, overshoot, settle.
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0.82), weight: 20),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.82,
        end: 1,
      ).chain(CurveTween(curve: FormTokens.pop)),
      weight: 80,
    ),
  ]).animate(_controller);

  // Damped back-and-forth, 0 at both ends. Drives the closet swing.
  late final Animation<double> _wobble = TweenSequence([
    TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 25),
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: -0.5), weight: 30),
    TweenSequenceItem(tween: Tween(begin: -0.5, end: 0.2), weight: 25),
    TweenSequenceItem(tween: Tween<double>(begin: 0.2, end: 0), weight: 20),
  ]).chain(CurveTween(curve: Curves.easeInOut)).animate(_controller);

  @override
  void didUpdateWidget(_FormTabIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected &&
        !oldWidget.selected &&
        !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(
      end: widget.selected ? FormTokens.green : FormTokens.muted,
    ),
    duration: FormTokens.quick,
    builder: (context, color, _) => AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: switch (widget.name) {
            FormIconName.closet => 0.3 * _wobble.value,
            FormIconName.settings => _controller.value * 1.05,
            _ => 0,
          },
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: FormIcon(widget.name, color: color),
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
  // A Material (not a decorated box) so ListTiles inside can paint their
  // tile color and ink splashes.
  Widget build(BuildContext context) => Material(
    color: FormTokens.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: FormTokens.line),
      borderRadius: BorderRadius.circular(FormTokens.panelRadius),
    ),
    child: Padding(padding: const EdgeInsets.all(21), child: child),
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

/// Segmented control whose green pill slides between options. Changing the
/// selection gives a light selection haptic.
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

  static const _slide = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    final index = keys.indexOf(selected);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _slide;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FormTokens.field,
        borderRadius: BorderRadius.circular(FormTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(
                    keys.length == 1 ? 0 : -1 + 2 * index / (keys.length - 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / keys.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: FormTokens.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final entry in options.entries)
                  Expanded(
                    child: Semantics(
                      selected: entry.key == selected,
                      child: TextButton(
                        onPressed: onSelected == null
                            ? null
                            : () {
                                if (entry.key != selected) {
                                  unawaited(HapticFeedback.selectionClick());
                                }
                                onSelected!(entry.key);
                              },
                        style: TextButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 9,
                          ),
                          minimumSize: const Size(44, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: TweenAnimationBuilder<Color?>(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          tween: ColorTween(
                            end: entry.key == selected
                                ? Colors.white
                                : FormTokens.ink,
                          ),
                          builder: (context, color, _) => Text(
                            entry.value,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: color),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
  const FormSheet({
    required this.title,
    required this.child,
    this.footer,
    super.key,
  });
  final String title;
  final Widget child;

  /// Stays pinned below the scrolling [child], like the PWA's sheet footers.
  final Widget? footer;
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
            if (footer != null) ...[
              const Divider(height: 1, color: FormTokens.line),
              Padding(padding: const EdgeInsets.only(top: 16), child: footer),
            ],
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

/// A rounded pill that toggles, like `.composer-filter-chips button`.
class FormPill extends StatelessWidget {
  const FormPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        backgroundColor: selected ? FormTokens.selectedTint : FormTokens.pill,
        foregroundColor: FormTokens.ink,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(label),
        ],
      ),
    ),
  );
}

/// A labelled on/off row with the PWA's `.state-toggle` switch.
class FormToggleRow extends StatelessWidget {
  const FormToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    enabled: onChanged != null,
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Opacity(
        opacity: onChanged == null ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: FormTokens.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 16 / 11,
                          color: FormTokens.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: FormTokens.quick,
                width: 40,
                height: 24,
                padding: const EdgeInsets.all(3),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? FormTokens.green : FormTokens.toggleOff,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 18, height: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Short feedback after an action, styled like the PWA's `#toast`.
void showFormToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FormTokens.toast,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
        ),
      ),
    );
}

class FormRadioChoices extends StatelessWidget {
  const FormRadioChoices({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: FormTokens.field,
      borderRadius: BorderRadius.circular(FormTokens.inputRadius),
    ),
    child: Row(
      children: [
        for (final option in options.entries)
          Expanded(
            child: Semantics(
              checked: option.key == selected,
              inMutuallyExclusiveGroup: true,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 7,
                  ),
                  backgroundColor: option.key == selected
                      ? Colors.white
                      : Colors.transparent,
                  foregroundColor: option.key == selected
                      ? FormTokens.green
                      : FormTokens.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onSelected == null
                    ? null
                    : () => onSelected!(option.key),
                child: Text(option.value, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    ),
  );
}

class FormCollectionToggle extends StatelessWidget {
  const FormCollectionToggle({
    required this.selected,
    required this.labels,
    required this.onSelected,
    super.key,
  });
  final String selected;
  final Map<String, String> labels;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 20),
    child: Row(
      children: [
        Expanded(child: Text(labels[selected]!, style: FormTokens.small)),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: FormTokens.field,
            border: Border.all(color: FormTokens.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              for (final entry in labels.entries)
                Semantics(
                  selected: selected == entry.key,
                  child: IconButton(
                    tooltip: entry.value,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      backgroundColor: selected == entry.key
                          ? FormTokens.green
                          : Colors.transparent,
                      foregroundColor: selected == entry.key
                          ? Colors.white
                          : FormTokens.muted,
                    ),
                    onPressed: onSelected == null
                        ? null
                        : () => onSelected!(entry.key),
                    icon: FormIcon(
                      entry.key == 'owning'
                          ? FormIconName.closet
                          : FormIconName.heart,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class FormStatusBadge extends StatelessWidget {
  const FormStatusBadge({
    required this.label,
    required this.icon,
    this.active = false,
    this.failed = false,
    super.key,
  });
  final String label;
  final FormIconName icon;
  final bool active;
  final bool failed;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: failed
            ? FormTokens.referenceFailedTint
            : active
            ? FormTokens.referenceActiveBadge
            : FormTokens.referenceBadge,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          FormIcon(
            icon,
            size: 12,
            color: failed
                ? FormTokens.referenceFailedInk
                : active
                ? FormTokens.green
                : FormTokens.referenceBadgeInk,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: failed
                  ? FormTokens.referenceFailedInk
                  : active
                  ? FormTokens.green
                  : FormTokens.referenceBadgeInk,
            ),
          ),
        ],
      ),
    ),
  );
}

class FormReferenceCard extends StatelessWidget {
  const FormReferenceCard({
    required this.image,
    required this.copy,
    required this.onTap,
    this.active = false,
    this.horizontal = true,
    this.pending = false,
    super.key,
  });
  final Widget image;
  final Widget copy;
  final VoidCallback onTap;
  final bool active;
  final bool horizontal;
  final bool pending;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: CustomPaint(
      foregroundPainter: pending ? const FormDashedBorder() : null,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: active ? FormTokens.referenceActiveTint : FormTokens.paper,
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
        ),
        foregroundDecoration: pending
            ? null
            : BoxDecoration(
                border: Border.all(
                  color: active ? FormTokens.green : FormTokens.line,
                ),
                borderRadius: BorderRadius.circular(FormTokens.cardRadius),
              ),
        child: InkWell(
          onTap: onTap,
          // Stretch needs a bounded height, and list parents give none.
          child: horizontal
              ? SizedBox(
                  height: 136,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Matches the 9:16 collage so it fills edge to edge.
                      AspectRatio(
                        aspectRatio: 9 / 16,
                        child: ColoredBox(
                          color: FormTokens.field,
                          child: image,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: copy,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: 2,
                            child: FormIcon(
                              FormIconName.arrow,
                              size: 16,
                              color: FormTokens.green,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 9 / 16,
                      child: ColoredBox(color: FormTokens.field, child: image),
                    ),
                    Padding(padding: const EdgeInsets.all(11), child: copy),
                  ],
                ),
        ),
      ),
    ),
  );
}

class FormReferenceImage extends StatelessWidget {
  const FormReferenceImage({
    required this.child,
    this.aspectRatio = 9 / 16,
    this.preview = false,
    super.key,
  });
  final Widget child;
  final double aspectRatio;
  final bool preview;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: BoxConstraints(
        maxWidth: preview ? double.infinity : 360,
        maxHeight: preview
            ? MediaQuery.sizeOf(context).height * 0.42
            : double.infinity,
      ),
      margin: const EdgeInsets.symmetric(vertical: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: FormTokens.field,
        borderRadius: BorderRadius.circular(preview ? 0 : 16),
      ),
      child: AspectRatio(aspectRatio: aspectRatio, child: child),
    ),
  );
}

class FormFact extends StatelessWidget {
  const FormFact({required this.label, required this.value, super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: FormTokens.small.copyWith(fontSize: 11, letterSpacing: 0.6),
        ),
        const SizedBox(height: 3),
        Text(value, style: FormTokens.body.copyWith(height: 1.45)),
      ],
    ),
  );
}

/// The image is positioned from source-pixel bounds supplied by the crop state.
class FormCropViewport extends StatelessWidget {
  const FormCropViewport({
    required this.image,
    required this.sourceSize,
    required this.bounds,
    required this.label,
    this.onPan,
    super.key,
  });
  final Widget image;
  final Size sourceSize;
  final Rect bounds;
  final String label;
  final void Function(double, double)? onPan;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    image: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / bounds.width;
        return GestureDetector(
          onPanUpdate: onPan == null
              ? null
              : (event) => onPan!(
                  event.delta.dx / constraints.maxWidth,
                  event.delta.dy / constraints.maxHeight,
                ),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: -bounds.left * scale,
                  top: -bounds.top * scale,
                  width: sourceSize.width * scale,
                  height: sourceSize.height * scale,
                  child: image,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Dashed rounded outline, painted as a `foregroundPainter` over a card.
class FormDashedBorder extends CustomPainter {
  const FormDashedBorder({
    this.color = FormTokens.line,
    this.radius = FormTokens.cardRadius,
  });
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 8) {
        canvas.drawPath(metric.extractPath(offset, offset + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(FormDashedBorder oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
