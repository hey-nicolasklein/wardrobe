import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:form_mobile/app/form_tokens.dart';

/// Re-taps of the tab that is already selected. The shell reports them and
/// [TabScrollToTop] answers by scrolling its tab back to the top, as on iOS.
class TabReselect extends ChangeNotifier {
  int? _index;

  /// The tab that was re-tapped last.
  int? get index => _index;

  void reselect(int index) {
    _index = index;
    notifyListeners();
  }
}

/// Scrolls the route's primary scroll view to the top when tab [index] is
/// re-tapped. Wrap a tab's root page with it.
class TabScrollToTop extends StatefulWidget {
  const TabScrollToTop({
    required this.reselect,
    required this.index,
    required this.child,
    super.key,
  });

  final TabReselect reselect;
  final int index;
  final Widget child;

  @override
  State<TabScrollToTop> createState() => _TabScrollToTopState();
}

class _TabScrollToTopState extends State<TabScrollToTop> {
  @override
  void initState() {
    super.initState();
    widget.reselect.addListener(_onReselect);
  }

  @override
  void didUpdateWidget(TabScrollToTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reselect != widget.reselect) {
      oldWidget.reselect.removeListener(_onReselect);
      widget.reselect.addListener(_onReselect);
    }
  }

  @override
  void dispose() {
    widget.reselect.removeListener(_onReselect);
    super.dispose();
  }

  void _onReselect() {
    if (widget.reselect.index != widget.index) return;
    final controller = PrimaryScrollController.maybeOf(context);
    if (controller == null) return;
    final instant = MediaQuery.disableAnimationsOf(context);
    for (final position in controller.positions) {
      if (instant) {
        position.jumpTo(0);
      } else {
        unawaited(
          position.animateTo(
            0,
            duration: FormTokens.sheetDuration,
            curve: FormTokens.easeOut,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
