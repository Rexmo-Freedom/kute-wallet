// lib/screens/home/components/deposit/deposit_quick_amounts.dart
//
// The Move sheet's quick-amount row and the amount its button states.
// Presentation only: a dollar chip types that figure exactly as the
// keypad would, and Max is the sheet's own percent path at 100%, so no
// maximum, fee or quote is worked out here.

import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountQuickChip;

/// The dollar chips, in order. Max follows them.
const List<int> kMoveQuickAmountsUsd = [10, 25, 50];

/// The chips for one route.
///
/// A dollar-typed route gets `$10 / $25 / $50 / Max`. A route typed in
/// bitcoin keeps `25% / 50% / Max`, because a fixed dollar figure is
/// not what that keypad is counting. Max is [onPercent] at 1 either
/// way, the call the old 100% chip made.
///
/// A screen that spends outside money (Cash App, the bank rail) has no
/// balance and so no Max: it passes `withMax: false` and its own
/// currency [symbol], and gets the three fixed amounts alone.
List<AmountQuickChip> moveQuickAmountChips({
  required bool amountIsUsd,
  String symbol = '\$',
  bool withMax = true,
  required String maxLabel,
  required bool Function(int usd) exceedsAvailable,
  required void Function(int usd) onDollars,
  required void Function(double ratio, {String? chip}) onPercent,
}) =>
    [
      if (amountIsUsd)
        for (final usd in kMoveQuickAmountsUsd)
          AmountQuickChip(
            label: '$symbol$usd',
            dimmed: exceedsAvailable(usd),
            onTap: () => onDollars(usd),
          )
      else
        for (final ratio in const [0.25, 0.5])
          AmountQuickChip(
            label: '${(ratio * 100).round()}%',
            onTap: () => onPercent(ratio),
          ),
      if (withMax)
        AmountQuickChip(
          label: maxLabel,
          onTap: () => onPercent(1, chip: 'max'),
        ),
    ];

/// What a dollar chip types: the whole figure, as the keypad writes it.
String moveQuickAmountTyped(int usd) => usd.toString();

/// A dollar amount for the button: whole dollars read `$50`, anything
/// else keeps its cents (`$12.34`).
String moveButtonUsd(double usd) {
  final cents = (usd * 100).round();
  return cents % 100 == 0
      ? '\$${cents ~/ 100}'
      : '\$${(cents / 100).toStringAsFixed(2)}';
}
