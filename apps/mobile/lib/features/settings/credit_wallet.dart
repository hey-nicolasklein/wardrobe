import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/repository/credits_repository.dart';

/// The credit balance as a small wallet: a coin that flips whenever the
/// balance changes (or on tap, which also refreshes) and a number that
/// counts to the new value. Hidden until a balance is known.
class CreditWallet extends StatelessWidget {
  const CreditWallet({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<CreditsCubit, Credits?>(
    builder: (context, credits) => AnimatedSize(
      duration: FormTokens.sheetDuration,
      curve: FormTokens.easeOut,
      alignment: Alignment.topCenter,
      child: credits == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _Wallet(credits),
            ),
    ),
  );
}

class _Wallet extends StatefulWidget {
  const _Wallet(this.credits);

  final Credits credits;

  @override
  State<_Wallet> createState() => _WalletState();
}

class _WalletState extends State<_Wallet> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _spin());
  }

  @override
  void didUpdateWidget(_Wallet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.credits.balance != widget.credits.balance) _spin();
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _spin() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    unawaited(_flip.forward(from: 0));
  }

  void _tap() {
    unawaited(HapticFeedback.lightImpact());
    _spin();
    unawaited(context.read<CreditsCubit>().refresh());
  }

  @override
  Widget build(BuildContext context) {
    final credits = widget.credits;
    final empty = credits.metered && credits.looksLeft == 0;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: empty
              ? const [FormTokens.surface, FormTokens.dangerTint]
              : const [FormTokens.surface, FormTokens.coinTint],
        ),
        border: Border.all(color: FormTokens.line),
        borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  button: true,
                  label: context.tr(LocaleKeys.credits_refresh),
                  child: GestureDetector(
                    onTap: _tap,
                    child: AnimatedBuilder(
                      animation: _flip,
                      builder: (context, child) => Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0015)
                          ..rotateY(
                            FormTokens.easeOut.transform(_flip.value) *
                                4 *
                                math.pi,
                          ),
                        child: child,
                      ),
                      child: const _Coin(),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(LocaleKeys.credits_title).toUpperCase(),
                        style: FormTokens.eyebrow,
                      ),
                      const SizedBox(height: 6),
                      if (credits.metered)
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: credits.balance.toDouble(),
                          ),
                          duration: animate
                              ? const Duration(milliseconds: 900)
                              : Duration.zero,
                          curve: FormTokens.easeOut,
                          builder: (context, value, _) => Text(
                            '${value.round()}',
                            style: FormTokens.display
                                .copyWith(
                                  height: 1,
                                  color: empty
                                      ? FormTokens.danger
                                      : FormTokens.ink,
                                )
                                .merge(FormTokens.numerals),
                          ),
                        )
                      else
                        Text(
                          '∞',
                          style: FormTokens.display.copyWith(height: 1),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!credits.metered)
              Text(
                context.tr(LocaleKeys.credits_unlimited),
                style: FormTokens.small,
              )
            else if (empty)
              Text(
                context.tr(LocaleKeys.credits_empty),
                style: FormTokens.body.copyWith(color: FormTokens.danger),
              )
            else ...[
              Text(
                context.tr(LocaleKeys.credits_enoughFor),
                style: FormTokens.small,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(
                    icon: Icons.auto_awesome,
                    label: context.tr(
                      credits.looksLeft == 1
                          ? LocaleKeys.credits_lookOne
                          : LocaleKeys.credits_lookMany,
                      namedArgs: {'count': '${credits.looksLeft}'},
                    ),
                    colors: FormTokens.lookStyles['auto']!,
                  ),
                  _Pill(
                    icon: Icons.checkroom,
                    label: context.tr(
                      credits.shelfImagesLeft == 1
                          ? LocaleKeys.credits_shelfImageOne
                          : LocaleKeys.credits_shelfImageMany,
                      namedArgs: {'count': '${credits.shelfImagesLeft}'},
                    ),
                    colors: FormTokens.lookStyles['candid']!,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A gold coin stamped with the FORM initial.
class _Coin extends StatelessWidget {
  const _Coin();

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-0.35, -0.45),
        radius: 0.95,
        colors: [FormTokens.coinShine, FormTokens.coinFace, FormTokens.coinRim],
        stops: [0, 0.55, 1],
      ),
      boxShadow: [
        BoxShadow(
          color: FormTokens.coinRim.withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    padding: const EdgeInsets.all(6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: FormTokens.coinInk.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          'F',
          style: FormTokens.heading.copyWith(
            fontSize: 26,
            height: 1,
            color: FormTokens.coinInk,
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.colors});

  final IconData icon;
  final String label;
  final ({Color ink, Color tint}) colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: colors.tint,
      borderRadius: BorderRadius.circular(FormTokens.chipRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.ink),
        const SizedBox(width: 5),
        Text(
          label,
          style: FormTokens.small.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}
