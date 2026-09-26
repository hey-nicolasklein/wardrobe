import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
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
class OnboardingWardrobeStep extends StatefulWidget {
  const OnboardingWardrobeStep({required this.active, super.key});

  /// Whether the step is the visible page. The scan starts on first view.
  final bool active;

  @override
  State<OnboardingWardrobeStep> createState() => _OnboardingWardrobeStepState();
}

class _OnboardingWardrobeStepState extends State<OnboardingWardrobeStep>
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
  String _collection = 'owning';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(OnboardingWardrobeStep oldWidget) {
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
    setState(() {
      _photo = (_photo + 1) % ScanStage.photos.length;
      _collection = 'owning';
    });
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
    final shelf = _collection == 'owning'
        ? pieces
        : onboardingPieces.where((piece) => piece.state == 'wanting').toList();
    return OnboardingStepLayout(
      eyebrow: context.tr(LocaleKeys.onboarding_wardrobeEyebrow),
      title: context.tr(LocaleKeys.onboarding_wardrobeTitle),
      body: context.tr(LocaleKeys.onboarding_wardrobeBody),
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
                                      LocaleKeys.onboarding_wardrobeFound,
                                      namedArgs: {'count': '${pieces.length}'},
                                    )
                                  : context.tr(
                                      LocaleKeys.onboarding_wardrobeScanning,
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
                  child: Text(context.tr(LocaleKeys.onboarding_wardrobeAgain)),
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
                key: ValueKey('$_collection$_photo'),
                spacing: FormTokens.gap,
                children: [
                  for (final (index, piece) in shelf.indexed)
                    Expanded(
                      child: _collection == 'owning'
                          ? ScaleTransition(
                              scale: _interval(
                                0.66 + index * 0.08,
                                0.9 + index * 0.08,
                              ),
                              child: _ShelfTile(piece: piece),
                            )
                          : _ShelfTile(piece: piece),
                    ),
                  for (var i = shelf.length; i < 3; i++)
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(LocaleKeys.onboarding_wardrobeToggle),
            style: FormTokens.small,
          ),
          FormCollectionToggle(
            selected: _collection,
            labels: {
              'owning': context.tr(LocaleKeys.collection_owning),
              'wanting': context.tr(LocaleKeys.collection_wanting),
            },
            onSelected: (value) => setState(() => _collection = value),
          ),
        ],
      ),
    );
  }
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.piece});
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

/// A short yes/no quiz about what FORM can and cannot do.
class OnboardingQuizStep extends StatefulWidget {
  const OnboardingQuizStep({super.key});

  @override
  State<OnboardingQuizStep> createState() => _OnboardingQuizStepState();
}

class _OnboardingQuizStepState extends State<OnboardingQuizStep> {
  // Question key, whether FORM can do it, and the piece floating on its card.
  static const _questions = [
    ('outfit', true, 'jersey'),
    ('hidden', false, 'teddy-coat'),
    ('worn', true, 'leather-jacket'),
    ('size', false, 'brown-trousers'),
    ('perfect', false, 'sunglasses'),
    ('free', false, 'ring'),
  ];
  final List<bool> _results = [];
  bool? _answer;

  int get _index => _results.length - (_answer == null ? 0 : 1);
  bool get _done => _results.length == _questions.length && _answer == null;

  void _choose(bool yes) {
    final correct = yes == _questions[_index].$2;
    unawaited(
      correct ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
    );
    setState(() {
      _answer = yes;
      _results.add(correct);
    });
  }

  void _next() => setState(() => _answer = null);

  void _restart() => setState(() {
    _results.clear();
    _answer = null;
  });

  @override
  Widget build(BuildContext context) => OnboardingStepLayout(
    eyebrow: context.tr(LocaleKeys.onboarding_quizEyebrow),
    title: context.tr(LocaleKeys.onboarding_quizTitle),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            switchInCurve: FormTokens.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: RotationTransition(
                turns: Tween<double>(begin: 0.02, end: 0).animate(animation),
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.3, 0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
            ),
            child: _done ? _score(context) : _card(context, _questions[_index]),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            for (var i = 0; i < _questions.length; i++)
              AnimatedContainer(
                duration: FormTokens.sheetDuration,
                curve: FormTokens.pop,
                width: i == _index && !_done ? 22 : 9,
                height: 9,
                decoration: BoxDecoration(
                  color: i < _results.length
                      ? (_results[i] ? FormTokens.green : FormTokens.danger)
                      : FormTokens.line,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );

  Widget _card(BuildContext context, (String, bool, String) question) {
    final (key, _, pieceId) = question;
    final answered = _answer != null;
    final correct = answered && _results.last;
    return AnimatedContainer(
      key: ValueKey(key),
      duration: FormTokens.sheetDuration,
      curve: FormTokens.easeOut,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: !answered
            ? FormTokens.surface
            : correct
            ? FormTokens.selectedTint
            : FormTokens.dangerTint,
        border: Border.all(color: FormTokens.line),
        borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_index + 1} / ${_questions.length}',
            style: FormTokens.eyebrow.merge(FormTokens.numerals),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('onboarding.questions.$key'),
            style: FormTokens.heading.copyWith(fontSize: 24, height: 1.25),
          ),
          Expanded(
            child: Center(
              child: FractionallySizedBox(
                heightFactor: 0.8,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FloatingPiece(
                    piece: onboardingPiece(pieceId),
                    angle: -6,
                    delay: const Duration(milliseconds: 200),
                    phase: _index.toDouble(),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: FormTokens.sheetDuration,
            switchInCurve: FormTokens.easeOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            ),
            child: !answered
                ? Row(
                    key: const ValueKey('ask'),
                    spacing: FormTokens.gap,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _choose(true),
                          child: Text(context.tr(LocaleKeys.onboarding_yes)),
                        ),
                      ),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _choose(false),
                          child: Text(context.tr(LocaleKeys.onboarding_no)),
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('verdict'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: [
                      Row(
                        spacing: 10,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 520),
                            curve: FormTokens.pop,
                            builder: (context, scale, child) =>
                                Transform.scale(scale: scale, child: child),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: correct
                                  ? FormTokens.green
                                  : FormTokens.danger,
                              child: FormIcon(
                                correct
                                    ? FormIconName.check
                                    : FormIconName.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            context.tr(
                              correct
                                  ? LocaleKeys.onboarding_right
                                  : LocaleKeys.onboarding_wrong,
                            ),
                            style: FormTokens.heading.copyWith(fontSize: 21),
                          ),
                          const Spacer(),
                          Text(
                            context.tr(
                              _questions[_index].$2
                                  ? LocaleKeys.onboarding_yes
                                  : LocaleKeys.onboarding_no,
                            ),
                            style: FormTokens.eyebrow,
                          ),
                        ],
                      ),
                      Text(
                        context.tr('onboarding.answers.$key'),
                        style: FormTokens.body,
                      ),
                      FilledButton(
                        onPressed: _next,
                        child: Text(
                          context.tr(
                            _results.length == _questions.length
                                ? LocaleKeys.onboarding_next
                                : LocaleKeys.onboarding_nextQuestion,
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

  Widget _score(BuildContext context) {
    final score = _results.where((correct) => correct).length;
    return Stack(
      key: const ValueKey('score'),
      alignment: Alignment.center,
      children: [
        const PieceBurst(),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 10,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 620),
              curve: FormTokens.pop,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Text(
                context.tr(
                  LocaleKeys.onboarding_score,
                  namedArgs: {
                    'score': '$score',
                    'count': '${_questions.length}',
                  },
                ),
                textAlign: TextAlign.center,
                style: FormTokens.display.copyWith(fontSize: 36),
              ),
            ),
            Text(
              context.tr(LocaleKeys.onboarding_scoreBody),
              textAlign: TextAlign.center,
              style: FormTokens.body.copyWith(color: FormTokens.muted),
            ),
            TextButton(
              onPressed: _restart,
              child: Text(context.tr(LocaleKeys.onboarding_playAgain)),
            ),
          ],
        ),
      ],
    );
  }
}

/// A playable flat lay: tap pieces to swap them in, or let FORM surprise you.
class OnboardingFeedStep extends StatefulWidget {
  const OnboardingFeedStep({super.key});

  @override
  State<OnboardingFeedStep> createState() => _OnboardingFeedStepState();
}

class _OnboardingFeedStepState extends State<OnboardingFeedStep> {
  int _seed = 3;
  late List<OnboardingPiece> _look = surpriseOnboardingLook(_seed);

  void _toggle(OnboardingPiece piece) {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _look = toggleOnboardingPiece(_look, piece));
  }

  void _surprise() {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _look = surpriseOnboardingLook(++_seed));
  }

  @override
  Widget build(BuildContext context) {
    final tray = onboardingPieces
        .where((piece) => piece.state == 'owning')
        .toList();
    return OnboardingStepLayout(
      eyebrow: context.tr(LocaleKeys.onboarding_feedEyebrow),
      title: context.tr(LocaleKeys.onboarding_feedTitle),
      body: context.tr(LocaleKeys.onboarding_feedBody),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FormTokens.panelRadius),
              child: ColoredBox(
                color: FormTokens.flatLayPaper,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_look.isEmpty)
                      Text(
                        context.tr(LocaleKeys.onboarding_feedEmptyBoard),
                        style: FormTokens.heading.copyWith(
                          fontSize: 20,
                          color: FormTokens.muted,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: FlatLayBoard(
                          garments: [for (final piece in _look) piece.garment],
                          online: false,
                          arrive: true,
                          onGarmentTap: (id) => _toggle(onboardingPiece(id)),
                          imageBuilder: (item) => OnboardingPieceImage(
                            piece: onboardingPiece(item.id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(LocaleKeys.onboarding_feedHint),
                  style: FormTokens.small,
                ),
              ),
              TextButton.icon(
                onPressed: _surprise,
                icon: const FormIcon(
                  FormIconName.shuffle,
                  size: 18,
                  color: FormTokens.green,
                ),
                label: Text(context.tr(LocaleKeys.onboarding_feedSurprise)),
              ),
            ],
          ),
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tray.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final piece = tray[index];
                final selected = _look.any((entry) => entry.id == piece.id);
                return Semantics(
                  button: true,
                  selected: selected,
                  label: context.tr('categories.${piece.category}'),
                  child: PressableGarment(
                    onTap: () => _toggle(piece),
                    child: AnimatedContainer(
                      duration: FormTokens.quick,
                      width: 64,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: selected
                            ? FormTokens.selectedTint
                            : FormTokens.surface,
                        border: Border.all(
                          color: selected ? FormTokens.green : FormTokens.line,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(
                          FormTokens.cardRadius,
                        ),
                      ),
                      child: OnboardingPieceImage(piece: piece),
                    ),
                  ),
                );
              },
            ),
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
