import 'package:flutter/widgets.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/screens/polymarket/components/polymarket_error_copy.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_order.dart';

/// What to tell the user when a combo quote, placement, close or claim
/// fails. [selling] picks the no-buyers line for a close.
String comboErrorCopy(BuildContext context, Object error,
    {bool selling = false}) {
  final l10n = context.l10n;
  return switch (error) {
    ComboNoQuoteException() => selling ? l10n.comboNoBuyers : l10n.comboNoPrice,
    ComboStillSettling() => l10n.comboStillSettling,
    ComboQuoteChanged() => l10n.comboPriceChanged,
    ComboQuoteMismatch() => l10n.comboPriceChanged,
    ComboRfqException(:final isRateLimited) when isRateLimited =>
      l10n.comboTooManyPrices,
    ComboRfqException(:final isExpired) when isExpired =>
      l10n.comboPriceChanged,
    ComboRfqException() => l10n.comboPriceFailed,
    _ => polymarketErrorCopy(context, error),
  };
}

/// "2.34x" for a payout multiplier.
String comboMultiplierText(double m) =>
    m >= 100 ? '${m.toStringAsFixed(0)}x' : '${m.toStringAsFixed(2)}x';
