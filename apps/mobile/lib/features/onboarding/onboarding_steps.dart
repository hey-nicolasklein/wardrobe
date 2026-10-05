import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/occasion_tile.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';
import 'package:form_mobile/features/onboarding/scan_stage.dart';
import 'package:form_mobile/features/settings/character/character_cubit.dart';
import 'package:form_mobile/features/settings/character/character_section.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

bool _still(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Eyebrow, serif title and body above a step's interactive demo, which
/// fills the remaining height.
class OnboardingStepLayout extends StatelessWidget {
  const OnboardingStepLayout({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.body,
    super.key,
  });
  final String eyebrow;
  final String title;
  final String? body;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FormTokens.gutter,
      18,
      FormTokens.gutter,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormReveal(
          child: Text(eyebrow.toUpperCase(), style: FormTokens.eyebrow),
        ),
        const SizedBox(height: 8),
        FormReveal(
          delay: const Duration(milliseconds: 90),
          child: Text(
            title,
            style: FormTokens.display.copyWith(fontSize: 31),
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          FormReveal(
            delay: const Duration(milliseconds: 180),
            child: Text(
              body!,
              style: FormTokens.body.copyWith(color: FormTokens.muted),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: FormReveal(
            delay: const Duration(milliseconds: 260),
            child: child,
          ),
        ),
      ],
    ),
  );
}

class OnboardingPieceImage extends StatelessWidget {
  const OnboardingPieceImage({required this.piece, super.key});
  final OnboardingPiece piece;

  @override
  Widget build(BuildContext context) => Image.asset(
    piece.asset,
    fit: BoxFit.contain,
    gaplessPlayback: true,
  );
}

/// How a piece reacts to a tap, picked from its rendered size. Every piece is
/// lifted and drops back with a bounce, small ones spin on the way and middle
/// ones tip a little.
enum _Heft {
  light(lift: 26, duration: Duration(milliseconds: 760)),
  medium(lift: 20, duration: Duration(milliseconds: 790)),
  heavy(lift: 14, duration: Duration(milliseconds: 820));

  const _Heft({required this.lift, required this.duration});

  /// How far the piece is lifted, in logical pixels.
  final double lift;
  final Duration duration;

  static _Heft of(double side) => side < 80
      ? light
      : side < 110
      ? medium
      : heavy;
}

/// A piece that pops in, drifts gently and reacts to a tap according to its
/// size.
class FloatingPiece extends StatefulWidget {
  const FloatingPiece({
    required this.piece,
    required this.angle,
    required this.delay,
    required this.phase,
    super.key,
  });
  final OnboardingPiece piece;

  /// Resting angle in degrees.
  final double angle;
  final Duration delay;

  /// Offsets the drift so neighbouring pieces don't bob in sync.
  final double phase;

  @override
  State<FloatingPiece> createState() => _FloatingPieceState();
}

class _FloatingPieceState extends State<FloatingPiece>
    with TickerProviderStateMixin {
  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final _drift = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 3600 + (widget.phase * 400).round()),
  );
  late final _tapped = AnimationController(vsync: this);
  _Heft _heft = _Heft.heavy;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_still(context)) {
        _enter.value = 1;
        return;
      }
      _timer = Timer(widget.delay, () => unawaited(_enter.forward()));
      unawaited(_drift.repeat());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _drift.dispose();
    _tapped.dispose();
    super.dispose();
  }

  void _tap() {
    unawaited(
      _heft == _Heft.heavy
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.lightImpact(),
    );
    if (_still(context)) return;
    _tapped.duration = _heft.duration;
    unawaited(_tapped.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _heft = _Heft.of(constraints.biggest.shortestSide);
      return GestureDetector(
        onTap: _tap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_enter, _drift, _tapped]),
          child: OnboardingPieceImage(piece: widget.piece),
          builder: (context, child) {
            final enter = FormTokens.pop.transform(_enter.value);
            final wave = sin(2 * pi * _drift.value + widget.phase);
            final t = _tapped.value;
            // Rises quickly, then falls back and bounces on landing.
            const peak = 0.35;
            final lift =
                _heft.lift *
                (t < peak
                    ? Curves.easeOut.transform(t / peak)
                    : 1 -
                          Curves.bounceOut.transform(
                            (t - peak) / (1 - peak),
                          ));
            final turn = switch (_heft) {
              _Heft.light => 2 * pi * Curves.easeInOut.transform(t),
              // Tips by up to 12° while in the air.
              _Heft.medium => 12 * pi / 180 * lift / _heft.lift,
              _Heft.heavy => 0.0,
            };
            return Opacity(
              opacity: _enter.value.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, 7 * wave - lift),
                child: Transform.rotate(
                  angle: (widget.angle + 3 * wave) * pi / 180 + turn,
                  child: Transform.scale(scale: enter, child: child),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Pieces flying out from the centre once, as a small celebration.
class PieceBurst extends StatefulWidget {
  const PieceBurst({super.key});

  @override
  State<PieceBurst> createState() => _PieceBurstState();
}

class _PieceBurstState extends State<PieceBurst>
    with SingleTickerProviderStateMixin {
  static const _pieces = [
    'sunglasses',
    'maroon-sneaker',
    'ring',
    'jersey',
    'glasses',
    'high-top',
    'leather-jacket',
    'white-tee',
  ];
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_still(context)) unawaited(_controller.forward());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final radius = constraints.biggest.shortestSide * 0.62;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = FormTokens.easeOut.transform(_controller.value);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (final (index, id) in _pieces.indexed)
                  Transform.translate(
                    offset: Offset.fromDirection(
                      2 * pi * index / _pieces.length - pi / 2,
                      radius * t,
                    ),
                    child: Transform.rotate(
                      angle: (index.isEven ? 1 : -1) * pi * t,
                      child: Opacity(
                        opacity:
                            (1 - _controller.value) *
                            (_controller.value > 0 ? 1 : 0),
                        child: SizedBox.square(
                          dimension: 54,
                          child: OnboardingPieceImage(
                            piece: onboardingPiece(id),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

/// Plays a photo being analysed: a scan sweeps over it, each piece is
/// framed, and the pieces land on the shelf below.
class OnboardingScanStep extends StatefulWidget {
  const OnboardingScanStep({required this.active, super.key});

  /// Whether the step is the visible page. The scan starts on first view.
  final bool active;

  @override
  State<OnboardingScanStep> createState() => _OnboardingScanStepState();
}

class _OnboardingScanStepState extends State<OnboardingScanStep>
    with SingleTickerProviderStateMixin {
  late final _scan =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          unawaited(HapticFeedback.mediumImpact());
        }
      });
  int _photo = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(OnboardingScanStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_started) _play();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted) return;
    _started = true;
    if (_still(context)) {
      _scan.value = 1;
    } else {
      unawaited(_scan.forward(from: 0));
    }
  }

  void _again() {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _photo = (_photo + 1) % ScanStage.photos.length);
    _play();
  }

  Animation<double> _interval(double begin, double end, [Curve? curve]) =>
      CurvedAnimation(
        parent: _scan,
        curve: Interval(begin, min(end, 1), curve: curve ?? FormTokens.pop),
      );

  @override
  Widget build(BuildContext context) {
    final pieces = [
      for (final id in ScanStage.photos[_photo]) onboardingPiece(id),
    ];
    return OnboardingStepLayout(
      eyebrow: context.tr(LocaleKeys.onboarding_scanEyebrow),
      title: context.tr(LocaleKeys.onboarding_scanTitle),
      body: context.tr(LocaleKeys.onboarding_scanBody),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ScanStage(
              key: ValueKey(_photo),
              pieces: pieces,
              progress: _scan,
            ),
          ),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _scan,
                    builder: (context, _) {
                      final found = _scan.value >= ScanStage.scanEnd;
                      return AnimatedSwitcher(
                        duration: FormTokens.quick,
                        child: Row(
                          key: ValueKey(found),
                          spacing: 6,
                          children: [
                            if (found)
                              const FormIcon(
                                FormIconName.check,
                                size: 16,
                                color: FormTokens.green,
                              ),
                            Text(
                              found
                                  ? context.tr(
                                      LocaleKeys.onboarding_scanFound,
                                      namedArgs: {'count': '${pieces.length}'},
                                    )
                                  : context.tr(
                                      LocaleKeys.onboarding_scanScanning,
                                    ),
                              style: FormTokens.small.copyWith(
                                color: found ? FormTokens.green : null,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                TextButton(
                  onPressed: _again,
                  child: Text(context.tr(LocaleKeys.onboarding_scanAgain)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: AnimatedSwitcher(
              duration: FormTokens.sheetDuration,
              switchInCurve: FormTokens.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey(_photo),
                spacing: FormTokens.gap,
                children: [
                  for (final (index, piece) in pieces.indexed)
                    Expanded(
                      child: ScaleTransition(
                        scale: _interval(
                          0.66 + index * 0.08,
                          0.9 + index * 0.08,
                        ),
                        child: OnboardingShelfTile(piece: piece),
                      ),
                    ),
                  for (var i = pieces.length; i < 3; i++)
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// A demo piece on a white card, like a wardrobe tile.
class OnboardingShelfTile extends StatelessWidget {
  const OnboardingShelfTile({required this.piece, super.key});
  final OnboardingPiece piece;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FormTokens.surface,
      border: Border.all(color: FormTokens.line),
      borderRadius: BorderRadius.circular(FormTokens.cardRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: OnboardingPieceImage(piece: piece),
    ),
  );
}

/// A small Looks feed: pick an occasion, then say whether you would wear the
/// look to deal the next one.
class OnboardingFeedStep extends StatefulWidget {
  const OnboardingFeedStep({super.key});

  @override
  State<OnboardingFeedStep> createState() => _OnboardingFeedStepState();
}

class _OnboardingFeedStepState extends State<OnboardingFeedStep> {
  int _seed = 3;
  ({FormIconName icon, String label, String? value}) _occasion =
      occasionPresets.last;

  void _deal({bool liked = false}) {
    unawaited(
      liked ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
    );
    setState(() => _seed++);
  }

  @override
  Widget build(BuildContext context) {
    final look = surpriseOnboardingLook(_seed);
    final colors = FormTokens.occasions[_occasion.value ?? '']!;
    return OnboardingStepLayout(
      eyebrow: context.tr(LocaleKeys.onboarding_feedEyebrow),
      title: context.tr(LocaleKeys.onboarding_feedTitle),
      body: context.tr(LocaleKeys.onboarding_feedBody),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              spacing: 8,
              children: [
                for (final preset in occasionPresets)
                  OccasionTile(
                    icon: preset.icon,
                    label: context.tr(preset.label),
                    colors: FormTokens.occasions[preset.value ?? '']!,
                    selected: preset == _occasion,
                    compact: true,
                    onTap: () {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() {
                        _occasion = preset;
                        _seed++;
                      });
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: FormTokens.sheetDuration,
              switchInCurve: FormTokens.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: ClipRRect(
                key: ValueKey(_seed),
                borderRadius: BorderRadius.circular(FormTokens.panelRadius),
                child: ColoredBox(
                  color: FormTokens.flatLayPaper,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
                        child: Center(
                          child: FlatLayBoard(
                            garments: [for (final piece in look) piece.garment],
                            online: false,
                            arrive: true,
                            imageBuilder: (item) => OnboardingPieceImage(
                              piece: onboardingPiece(item.id),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.tint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Text(
                              context.tr(_occasion.label).toUpperCase(),
                              style: FormTokens.eyebrow.copyWith(
                                color: colors.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            spacing: FormTokens.gap,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deal,
                  icon: const FormIcon(FormIconName.close, size: 18),
                  label: Text(context.tr(LocaleKeys.lookNotForMe)),
                ),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _deal(liked: true),
                  icon: const FormIcon(
                    FormIconName.heart,
                    size: 18,
                    color: FormTokens.green,
                  ),
                  label: Text(context.tr(LocaleKeys.lookWouldWear)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Explains the character collage and opens the real setup. Shows the
/// collage with a small celebration once one exists.
class OnboardingCollageStep extends StatefulWidget {
  const OnboardingCollageStep({required this.active, super.key});

  /// Whether the step is the visible page. The frames deal in on first view.
  final bool active;

  @override
  State<OnboardingCollageStep> createState() => _OnboardingCollageStepState();
}

class _OnboardingCollageStepState extends State<OnboardingCollageStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _deal;

  @override
  void initState() {
    super.initState();
    _deal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
  }

  @override
  void didUpdateWidget(OnboardingCollageStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _deal.isDismissed) {
      if (_still(context)) {
        _deal.value = 1;
      } else {
        unawaited(_deal.forward());
      }
    }
  }

  @override
  void dispose() {
    _deal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CharacterCubit, CharacterState>(
        listenWhen: (previous, next) =>
            previous.current == null && next.current != null,
        listener: (_, _) => unawaited(HapticFeedback.heavyImpact()),
        builder: (context, state) {
          final sheet = state.current;
          return OnboardingStepLayout(
            eyebrow: context.tr(LocaleKeys.onboarding_collageEyebrow),
            title: context.tr(LocaleKeys.onboarding_collageTitle),
            body: context.tr(LocaleKeys.onboarding_collageBody),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: sheet == null
                          ? _frames()
                          : Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.6, end: 1),
                                  duration: const Duration(milliseconds: 700),
                                  curve: FormTokens.pop,
                                  builder: (context, scale, child) =>
                                      Transform.scale(
                                        scale: scale,
                                        child: child,
                                      ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      FormTokens.panelRadius,
                                    ),
                                    child: CharacterImage(
                                      sheet: sheet,
                                      online: state.online,
                                    ),
                                  ),
                                ),
                                const PieceBurst(),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (sheet != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8,
                    children: [
                      const FormIcon(
                        FormIconName.check,
                        size: 18,
                        color: FormTokens.green,
                      ),
                      Text(
                        context.tr(LocaleKeys.onboarding_collageDone),
                        style: FormTokens.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: FormTokens.green,
                        ),
                      ),
                    ],
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: state.canCreate
                        ? () => context.push('/onboarding/character-setup')
                        : null,
                    icon: const FormIcon(FormIconName.person, size: 18),
                    label: Text(
                      context.tr(LocaleKeys.onboarding_collageCreate),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(LocaleKeys.onboarding_collageLater),
                    textAlign: TextAlign.center,
                    style: FormTokens.small,
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          );
        },
      );

  /// Four empty photo frames dealt onto a 2×2 collage.
  Widget _frames() => LayoutBuilder(
    builder: (context, constraints) {
      final side = constraints.maxWidth;
      final cell = (side - FormTokens.gap) / 2;
      return Stack(
        children: [
          for (var i = 0; i < 4; i++)
            () {
              final animation = CurvedAnimation(
                parent: _deal,
                curve: Interval(
                  i * 0.14,
                  0.58 + i * 0.14,
                  curve: FormTokens.pop,
                ),
              );
              final left = (i % 2) * (cell + FormTokens.gap);
              final top = (i ~/ 2) * (cell + FormTokens.gap);
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final t = animation.value;
                  // Frames fly in from below the stage, tilted.
                  return Positioned(
                    left: left,
                    top: top + (1 - t) * side,
                    width: cell,
                    height: cell,
                    child: Opacity(
                      opacity: _deal.value == 0 ? 0 : 1,
                      child: Transform.rotate(
                        angle:
                            ((i.isEven ? -1 : 1) * (2 + 14 * (1 - t))) *
                            pi /
                            180,
                        child: child,
                      ),
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: FormTokens.surface,
                    border: Border.all(color: FormTokens.line),
                    borderRadius: BorderRadius.circular(FormTokens.cardRadius),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: ColoredBox(
                        color: FormTokens.lookStage,
                        child: Center(
                          child: FormIcon(
                            FormIconName.person,
                            size: i == 0 ? cell * 0.42 : cell * 0.3,
                            color: FormTokens.emptyIcon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      );
    },
  );
}
