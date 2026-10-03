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

/// The credit balance as a quiet panel: a stamped coin that turns over
/// whenever the balance changes, the balance in serif counting to its new
/// value, and what it still buys. With [onTap] the panel links on, like a
/// settings row. Hidden until a balance is known.
class CreditWallet extends StatelessWidget {
  const CreditWallet({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => BlocBuilder<CreditsCubit, Credits?>(
    builder: (context, credits) => AnimatedSize(
      duration: FormTokens.sheetDuration,
      curve: FormTokens.easeOut,
      alignment: Alignment.topCenter,
      child: credits == null
          ? const SizedBox(width: double.infinity)
          : _Wallet(credits, onTap: onTap),
    ),
  );
}

class _Wallet extends StatefulWidget {
  const _Wallet(this.credits, {this.onTap});

  final Credits credits;
  final VoidCallback? onTap;

  @override
  State<_Wallet> createState() => _WalletState();
}

class _WalletState extends State<_Wallet> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
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
    _turn.dispose();
    super.dispose();
  }

  void _spin() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    unawaited(_turn.forward(from: 0));
  }

  void _tap() {
    unawaited(HapticFeedback.selectionClick());
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final credits = widget.credits;
    final empty = credits.metered && credits.looksLeft == 0;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final panel = Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _turn,
            builder: (context, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateY(
                  FormTokens.easeOut.transform(_turn.value) * 2 * math.pi,
                ),
              child: child,
            ),
            child: _Coin(empty: empty),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (credits.metered)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: credits.balance.toDouble()),
                    duration: animate
                        ? const Duration(milliseconds: 760)
                        : Duration.zero,
                    curve: FormTokens.easeOut,
                    builder: (context, value, _) => Text(
                      context.tr(
                        value.round() == 1
                            ? LocaleKeys.credits_balanceOne
                            : LocaleKeys.credits_balanceMany,
                        namedArgs: {'count': '${value.round()}'},
                      ),
                      style: FormTokens.heading
                          .copyWith(
                            fontSize: 24,
                            height: 1.15,
                            color: empty ? FormTokens.danger : FormTokens.ink,
                          )
                          .merge(FormTokens.numerals),
                    ),
                  )
                else
                  Text(
                    context.tr(LocaleKeys.credits_unlimitedTitle),
                    style: FormTokens.heading.copyWith(
                      fontSize: 24,
                      height: 1.15,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  !credits.metered
                      ? context.tr(LocaleKeys.credits_unlimited)
                      : empty
                      ? context.tr(LocaleKeys.credits_empty)
                      : context.tr(
                          LocaleKeys.credits_enoughFor,
                          namedArgs: {
                            'looks': context.tr(
                              credits.looksLeft == 1
                                  ? LocaleKeys.credits_lookOne
                                  : LocaleKeys.credits_lookMany,
                              namedArgs: {'count': '${credits.looksLeft}'},
                            ),
                            'images': context.tr(
                              credits.shelfImagesLeft == 1
                                  ? LocaleKeys.credits_shelfImageOne
                                  : LocaleKeys.credits_shelfImageMany,
                              namedArgs: {
                                'count': '${credits.shelfImagesLeft}',
                              },
                            ),
                          },
                        ),
                  style: FormTokens.small.copyWith(
                    color: empty ? FormTokens.danger : null,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: FormTokens.muted,
              ),
            ),
        ],
      ),
    );
    return Material(
      color: FormTokens.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: FormTokens.line),
        borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.onTap == null ? panel : InkWell(onTap: _tap, child: panel),
    );
  }
}

/// A flat coin pressed into the paper: a pale gold disc with a fine rim
/// and the FORM initial, no shine or glow. Turns brick when empty.
class _Coin extends StatelessWidget {
  const _Coin({required this.empty});

  final bool empty;

  @override
  Widget build(BuildContext context) {
    final ink = empty ? FormTokens.danger : FormTokens.coinInk;
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: empty ? FormTokens.dangerTint : FormTokens.coinTint,
        border: Border.all(
          color: empty
              ? FormTokens.danger.withValues(alpha: 0.4)
              : FormTokens.coinRim,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ink.withValues(alpha: 0.22)),
        ),
        child: Center(
          child: Text(
            'F',
            style: FormTokens.heading.copyWith(
              fontSize: 19,
              height: 1,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}
