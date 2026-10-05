import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_icon.dart';

/// The Looks screen's two ways to make something: a flat stage where loose
/// pieces snap into a flat lay, and a worn stage where pieces fly onto the
/// user's own figure. Each tap previews its result before the composer opens.
class LookStages extends StatelessWidget {
  const LookStages({
    required this.items,
    required this.figure,
    required this.online,
    required this.flatLabel,
    required this.wornLabel,
    required this.onFlat,
    required this.onWorn,
    super.key,
  });

  final List<WardrobeItem> items;

  /// A full-body photo of the user, usually their latest try-on. Without one
  /// the worn stage shows an outline figure.
  final ({String identity, String previewPath})? figure;
  final bool online;
  final String flatLabel;
  final String wornLabel;
  final VoidCallback onFlat;
  final VoidCallback onWorn;

  static const stageHeight = 156.0;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      Expanded(
        child: _Stage(
          kind: _StageKind.flat,
          items: items.take(6).toList(),
          online: online,
          label: flatLabel,
          onTap: onFlat,
        ),
      ),
      Expanded(
        child: _Stage(
          kind: _StageKind.worn,
          items: items.skip(6).take(4).toList(),
          figure: figure,
          online: online,
          label: wornLabel,
          onTap: onWorn,
        ),
      ),
    ],
  );
}

enum _StageKind { flat, worn }

/// Where one piece floats at rest, as a share of the stage, and the phase of
/// its drift.
typedef _Float = ({Offset at, double size, double tilt, double phase});

class _Stage extends StatefulWidget {
  const _Stage({
    required this.kind,
    required this.items,
    required this.online,
    required this.label,
    required this.onTap,
    this.figure,
  });

  final _StageKind kind;
  final List<WardrobeItem> items;
  final ({String identity, String previewPath})? figure;
  final bool online;
  final String label;
  final VoidCallback onTap;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with TickerProviderStateMixin {
  // Seconds since the drift started, so the motion never visibly loops.
  final _drift = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(
    (elapsed) => _drift.value = elapsed.inMicroseconds / 1e6,
  );
  // 0 = pieces at rest, 1 = laid flat or worn. A press pulls them a little
  // of the way, release finishes, cancel lets them drift back.
  late final AnimationController _settle = AnimationController(vsync: this);
  bool _pressed = false;
  bool _opening = false;
  late List<_Float> _floats = _scatter();

  bool get _flat => widget.kind == _StageKind.flat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  @override
  void didUpdateWidget(_Stage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) _floats = _scatter();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _drift.dispose();
    _settle.dispose();
    super.dispose();
  }

  /// Loose resting spots. Flat pieces scatter over the whole stage, worn
  /// pieces wait beside the mirror.
  List<_Float> _scatter() {
    final random = math.Random(_flat ? 3 : 11);
    final count = widget.items.length;
    // Either side of the mirror, on clean ground.
    const edges = [
      Offset(0.14, 0.3),
      Offset(0.86, 0.34),
      Offset(0.14, 0.72),
      Offset(0.86, 0.74),
    ];
    return [
      for (var i = 0; i < count; i++)
        (
          at: _flat
              ? Offset(
                  0.16 +
                      0.68 * ((i % 3) / 2) +
                      (random.nextDouble() - 0.5) * 0.12,
                  (i < 3 ? 0.3 : 0.7) + (random.nextDouble() - 0.5) * 0.2,
                )
              : edges[i % edges.length],
          size: (_flat ? 44 : 34) + random.nextDouble() * (_flat ? 12 : 6),
          tilt: (random.nextDouble() - 0.5) * 0.8,
          phase: random.nextDouble() * 2 * math.pi,
        ),
    ];
  }

  /// Where piece [i] ends up: a tidy two-row grid for a flat lay, or a point
  /// on the body (head to feet) for a worn look.
  Offset _target(int i) {
    if (_flat) {
      return Offset(0.2 + 0.3 * (i % 3), i < 3 ? 0.3 : 0.7);
    }
    const body = [
      Offset(0.5, 0.42),
      Offset(0.5, 0.68),
      Offset(0.5, 0.9),
      Offset(0.5, 0.2),
    ];
    return body[i % body.length];
  }

  void _press() {
    if (_opening) return;
    setState(() => _pressed = true);
    unawaited(HapticFeedback.selectionClick());
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(
      _settle.animateTo(
        0.18,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _cancel() {
    if (_opening) return;
    setState(() => _pressed = false);
    unawaited(
      _settle.animateBack(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    setState(() => _pressed = false);
    unawaited(HapticFeedback.lightImpact());
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _settle.animateTo(
        1,
        duration: const Duration(milliseconds: 620),
      );
      if (!mounted) return;
      // Hold the finished preview a beat before the composer covers it.
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    widget.onTap();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _settle.value = 0;
    _opening = false;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapCancel: _cancel,
      onTap: _open,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 160),
            curve: FormTokens.easeOut,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FormTokens.panelRadius),
              child: ColoredBox(
                color: _flat ? FormTokens.flatLayPaper : FormTokens.lookStage,
                child: SizedBox(
                  height: LookStages.stageHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) => RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_drift, _settle]),
                        builder: (context, _) => _scene(constraints.biggest),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FormTokens.ink,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _scene(Size size) {
    final settle = _settle.value;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (!_flat) _mirror(size, settle),
        for (final (i, item) in widget.items.indexed)
          _piece(item, _floats[i], i, size, settle),
      ],
    );
  }

  /// An arched mirror in the middle of the worn stage. The user's photo
  /// waits in black and white and takes on colour as the pieces arrive.
  Widget _mirror(Size size, double settle) {
    final width = size.width * _mirrorWidth;
    final height = size.height * 0.86;
    final colour = Curves.easeInOut.transform(
      ((settle - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    final shape = BorderRadius.vertical(
      top: Radius.circular(width / 2),
      bottom: const Radius.circular(6),
    );
    return Positioned(
      left: (size.width - width) / 2,
      top: (size.height - height) / 2,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FormTokens.surface,
          borderRadius: shape,
          boxShadow: const [
            BoxShadow(
              color: Color(0x221D281C),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: ClipRRect(
            borderRadius: shape,
            child: ColorFiltered(
              colorFilter: _saturation(colour),
              child: _figure(),
            ),
          ),
        ),
      ),
    );
  }

  static const _mirrorWidth = 0.44;

  /// 0 = black and white, 1 = full colour.
  static ColorFilter _saturation(double amount) {
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    final k = 1 - amount;
    return ColorFilter.matrix([
      r * k + amount, g * k, b * k, 0, 0, //
      r * k, g * k + amount, b * k, 0, 0, //
      r * k, g * k, b * k + amount, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
  }

  Widget _figure() {
    if (widget.figure case final figure?) {
      return CachedMedia(
        identity: figure.identity,
        previewPath: figure.previewPath,
        online: widget.online,
        fit: BoxFit.cover,
        entrance: MediaEntrance.fade,
        placeholder: false,
      );
    }
    return const ColoredBox(
      color: FormTokens.field,
      child: Center(
        child: FormIcon(
          FormIconName.person,
          size: 40,
          color: FormTokens.emptyIcon,
        ),
      ),
    );
  }

  Widget _piece(
    WardrobeItem item,
    _Float float,
    int index,
    Size size,
    double settle,
  ) {
    // Each piece starts a little after the one before, so they land one by
    // one instead of as a block.
    final start = index * 0.09;
    final local = ((settle - start) / (1 - start * 1.4).clamp(0.3, 1.0)).clamp(
      0.0,
      1.0,
    );
    final t = (_flat ? FormTokens.pop : Curves.easeInCubic).transform(local);

    // The drift keeps its clock and only loses amplitude as a piece leaves,
    // so it eases out of the float instead of rewinding through it.
    final s = _drift.value;
    final calm = 1 - Curves.easeOut.transform(local);
    final wobble = Offset(
      math.sin(s * 0.3 + float.phase) * 4 * calm,
      math.cos(s * 0.24 + float.phase * 1.7) * 4 * calm,
    );
    final rest =
        Offset(
          float.at.dx * size.width,
          float.at.dy * size.height,
        ) +
        wobble;
    final goal = Offset(
      _target(index).dx * size.width,
      _target(index).dy * size.height,
    );
    final at = Offset.lerp(rest, goal, t)!;
    // Flat pieces settle at a common size, worn ones shrink into the body.
    final side = _flat
        ? float.size + (50 - float.size) * t
        : float.size * (1 - t * 0.7);
    final opacity = _flat ? 1.0 : 1 - Curves.easeIn.transform(local);
    final tilt =
        float.tilt * (1 - t) + math.sin(s * 0.5 + float.phase) * 0.05 * calm;

    return Positioned(
      left: at.dx - side / 2,
      top: at.dy - side / 2,
      width: side,
      height: side,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: tilt,
          child: CachedMedia(
            identity: item.previewIdentity,
            previewPath: item.previewPath,
            online: widget.online,
            entrance: MediaEntrance.fade,
            placeholder: false,
          ),
        ),
      ),
    );
  }
}
