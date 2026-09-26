import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';
import 'package:form_mobile/features/onboarding/onboarding_steps.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/preferences_repository.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// First-run walkthrough: shows a lively wardrobe and feed made of bundled
/// demo pieces, explains what FORM can and cannot do, and leads into the
/// character collage and the first intake. Replayable from Settings.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _count = 6;
  final _pages = PageController();
  int _index = 0;
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final piece in onboardingPieces) {
      unawaited(precacheImage(AssetImage(piece.asset), context));
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish(String? location) async {
    await context.read<PreferencesRepository>().setOnboardingSeen();
    if (!mounted) return;
    if (location == null && context.canPop()) {
      context.pop();
    } else {
      context.go(location ?? '/feed');
    }
  }

  void _next() => unawaited(
    _pages.nextPage(
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 520),
      curve: FormTokens.easeOut,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FormTokens.paper,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FormTokens.gutter, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: _Progress(pages: _pages, count: _count),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: _index == _count - 1 ? 0 : 1,
                  duration: FormTokens.quick,
                  child: TextButton(
                    onPressed: _index == _count - 1
                        ? null
                        : () => unawaited(_finish(null)),
                    child: Text(context.tr(LocaleKeys.onboarding_skip)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (index) {
                unawaited(HapticFeedback.selectionClick());
                setState(() => _index = index);
              },
              children: [
                const _WelcomeStep(),
                OnboardingWardrobeStep(active: _index == 1),
                const OnboardingQuizStep(),
                const OnboardingFeedStep(),
                OnboardingCollageStep(active: _index == 4),
                _FinaleStep(onExplore: () => unawaited(_finish('/feed'))),
              ],
            ),
          ),
          // Stays the same height on every step: resizing the page view
          // mid-swipe makes it jump pages.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FormTokens.gutter,
              8,
              FormTokens.gutter,
              12,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _index == _count - 1
                    ? () => unawaited(_finish('/wardrobe/intake'))
                    : _next,
                child: AnimatedSwitcher(
                  duration: FormTokens.quick,
                  child: Text(
                    key: ValueKey(_index == 0 || _index == _count - 1),
                    context.tr(switch (_index) {
                      0 => LocaleKeys.onboarding_welcomeStart,
                      const (_count - 1) => LocaleKeys.onboarding_finaleAdd,
                      _ => LocaleKeys.onboarding_next,
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Segments follow the page position continuously, so they track a swipe
/// in both directions: the current one widens, visited ones fill in.
class _Progress extends StatelessWidget {
  const _Progress({required this.pages, required this.count});
  final PageController pages;
  final int count;

  static const _gap = 5.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: pages,
      builder: (context, _) {
        final page = pages.hasClients && pages.position.haveDimensions
            ? pages.page ?? 0
            : pages.initialPage.toDouble();
        // Every segment has one share; the current page gets two more.
        final unit = (constraints.maxWidth - _gap * (count - 1)) / (count + 2);
        return Row(
          spacing: _gap,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: unit * (1 + 2 * max(0, 1 - (page - i).abs())),
                height: 5,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    FormTokens.line,
                    FormTokens.green,
                    (page - i + 1).clamp(0, 1),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  // Piece, centre x as a fraction of the stage width, top edge as a fraction
  // of the height left free, size as a fraction of the width, resting angle
  // in degrees.
  static const _cloud = [
    ('sunglasses', .50, .10, .22, -5.0),
    ('jersey', .79, .24, .30, 8.0),
    ('leather-jacket', .24, .28, .36, -9.0),
    ('ring', .54, .38, .13, 10.0),
    ('balloon-pants', .50, .64, .32, -3.0),
    ('maroon-sneaker', .83, .60, .26, 12.0),
    ('teddy-coat', .17, .72, .28, 6.0),
    ('high-top', .78, .90, .22, -8.0),
    ('glasses', .27, .95, .20, 4.0),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: FormTokens.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (index, (id, x, y, size, angle)) in _cloud.indexed)
                    Positioned(
                      left: x * width - size * width / 2,
                      top: y * (height - size * width),
                      width: size * width,
                      height: size * width,
                      child: FloatingPiece(
                        piece: onboardingPiece(id),
                        angle: angle,
                        delay: Duration(milliseconds: 90 * index),
                        phase: index * 0.7,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        FormReveal(
          child: Text(
            context.tr(LocaleKeys.onboarding_welcomeEyebrow).toUpperCase(),
            style: FormTokens.eyebrow,
          ),
        ),
        const SizedBox(height: 8),
        FormReveal(
          delay: const Duration(milliseconds: 120),
          child: Text(
            context.tr(LocaleKeys.onboarding_welcomeTitle),
            style: FormTokens.display.copyWith(fontSize: 38),
          ),
        ),
        const SizedBox(height: 10),
        FormReveal(
          delay: const Duration(milliseconds: 240),
          child: Text(
            context.tr(LocaleKeys.onboarding_welcomeBody),
            style: FormTokens.body.copyWith(color: FormTokens.muted),
          ),
        ),
        const SizedBox(height: 10),
        FormReveal(
          delay: const Duration(milliseconds: 900),
          child: Text(
            context.tr(LocaleKeys.onboarding_welcomeHint),
            style: FormTokens.small.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      ],
    ),
  );
}

class _FinaleStep extends StatefulWidget {
  const _FinaleStep({required this.onExplore});
  final VoidCallback onExplore;

  @override
  State<_FinaleStep> createState() => _FinaleStepState();
}

class _FinaleStepState extends State<_FinaleStep> {
  static const _shown = 12;
  static const _max = 60.0;
  double _pieces = 20;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toLanguageTag();
    final visible = (_pieces / _max * _shown).ceil();
    final owned = onboardingPieces
        .where((piece) => piece.state == 'owning')
        .toList();
    return OnboardingStepLayout(
      eyebrow: context.tr(LocaleKeys.onboarding_finaleEyebrow),
      title: context.tr(LocaleKeys.onboarding_finaleTitle),
      body: context.tr(LocaleKeys.onboarding_finaleBody),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _shown; i++)
                    AnimatedScale(
                      scale: i < visible ? 1 : 0,
                      duration: Duration(milliseconds: 380 + 30 * (i % 4)),
                      curve: i < visible ? FormTokens.pop : FormTokens.easeOut,
                      child: SizedBox.square(
                        dimension: 74,
                        child: Transform.rotate(
                          angle: (i.isEven ? -1 : 1) * (4 + i % 3) * pi / 180,
                          child: OnboardingPieceImage(
                            piece: owned[i % owned.length],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: estimatedLooks(_pieces.round()).toDouble()),
            duration: const Duration(milliseconds: 650),
            curve: FormTokens.easeOut,
            builder: (context, value, _) => Text(
              NumberFormat.decimalPattern(locale).format(value.round()),
              style: FormTokens.display.copyWith(
                fontSize: 52,
                color: FormTokens.green,
                fontFeatures: FormTokens.numerals.fontFeatures,
              ),
            ),
          ),
          Text(
            context.tr(LocaleKeys.onboarding_finaleLooks),
            style: FormTokens.small,
          ),
          Slider(
            value: _pieces,
            min: 5,
            max: _max,
            divisions: 11,
            label: context.tr(
              LocaleKeys.onboarding_finalePieces,
              namedArgs: {'count': '${_pieces.round()}'},
            ),
            onChanged: (value) {
              if (value.round() != _pieces.round()) {
                unawaited(HapticFeedback.selectionClick());
              }
              setState(() => _pieces = value);
            },
          ),
          Text(
            context.tr(
              LocaleKeys.onboarding_finalePieces,
              namedArgs: {'count': '${_pieces.round()}'},
            ),
            style: FormTokens.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Text(
            context.tr(LocaleKeys.onboarding_finaleTip),
            textAlign: TextAlign.center,
            style: FormTokens.small,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: widget.onExplore,
            child: Text(context.tr(LocaleKeys.onboarding_finaleExplore)),
          ),
        ],
      ),
    );
  }
}
