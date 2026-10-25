import 'package:kute/models/hyperliquid_market.dart';
// lib/screens/hyperliquid/components/order_placed_overlay.dart
//
// Result sheet shown after an Investing order fills. The order slip
// captures the root navigator BEFORE popping its sheets, then calls
// [pushHlOrderPlacedOverlay] with the actual fill from the exchange.

import 'package:flutter/material.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show openInvestmentsOrders, openInvestmentsPositions;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';

/// Push the order-filled confirmation using a pre-captured
/// [NavigatorState]. Capture `Navigator.of(context, rootNavigator: true)`
/// before popping the slip, then call this after.
void pushHlOrderPlacedOverlay({
  required NavigatorState navigator,
  required String coin,
  HlMarket? market,
  required bool isLong,
  required int leverage,
  required bool isSpot,
  required double sizeFilled,
  required double avgPx,
  required double notionalUsd,
  HlPositionPlan? positionPlan,
  double? realizedPnl,
}) {
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: HlOrderPlacedOverlay(
      coin: coin,
      market: market,
      isLong: isLong,
      leverage: leverage,
      isSpot: isSpot,
      sizeFilled: sizeFilled,
      avgPx: avgPx,
      notionalUsd: notionalUsd,
      positionPlan: positionPlan,
      realizedPnl: realizedPnl,
    ),
  );
}

/// The receipt chip for a perp fill against a position already held,
/// from [plan] sized on the fill ([hlPositionPlan] with the filled size):
/// "Added to long", "Reduced long · 0.05 BTC" (what is left), "Closed
/// long", "Flipped to short · 0.05 BTC" (the new position). Null for an
/// open, which keeps "Long · 3×".
String? hlFillEffectLabel(
    AppLocalizations l10n, HlPositionPlan? plan, String coin) {
  if (plan == null || plan.position == null) return null;
  switch (plan.effect) {
    case HlPositionEffect.open:
      return null;
    case HlPositionEffect.add:
      return l10n.hlReceiptAddedTo(plan.heldSide);
    case HlPositionEffect.reduce:
      return l10n.hlReceiptReduced(
          plan.heldSide, formatHlSize(plan.remaining), coin);
    case HlPositionEffect.close:
      return l10n.hlReceiptClosed(plan.heldSide);
    case HlPositionEffect.flip:
      return l10n.hlReceiptFlipped(
          plan.heldLong ? 'short' : 'long', formatHlSize(plan.remainder), coin);
  }
}

/// What the fills realised, net of their fees (closedPnl − fee, as the
/// Statistics realised P&L counts it). Null unless [fills] are the whole
/// of [sizeFilled]: a partial set would understate it.
double? hlRealizedFromFills(Iterable<HlFill> fills, double sizeFilled) {
  if (sizeFilled <= 0) return null;
  var size = 0.0;
  var pnl = 0.0;
  for (final f in fills) {
    if (!f.closedPnl.isFinite || !f.fee.isFinite) return null;
    size += f.sz;
    pnl += f.closedPnl - f.fee;
  }
  if ((size - sizeFilled).abs() > 1e-9 * (1 + sizeFilled)) return null;
  return pnl;
}

class HlOrderPlacedOverlay extends StatelessWidget {
  final String coin;
  final HlMarket? market;
  final bool isLong;
  final int leverage;
  final bool isSpot;
  final double sizeFilled;
  final double avgPx;
  final double notionalUsd;

  /// The position held before the fill, sized on the fill. Null or an
  /// open keeps the opened-order receipt.
  final HlPositionPlan? positionPlan;

  /// Realised P&L net of fees, when the fills behind it are all in hand.
  final double? realizedPnl;

  const HlOrderPlacedOverlay({
    super.key,
    required this.coin,
    this.market,
    required this.isLong,
    required this.leverage,
    required this.isSpot,
    required this.sizeFilled,
    required this.avgPx,
    required this.notionalUsd,
    this.positionPlan,
    this.realizedPnl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final effect = isSpot ? null : positionPlan?.effect;
    final effectLabel =
        isSpot ? null : hlFillEffectLabel(l10n, positionPlan, coin);
    // A fill that reduces, closes or flips a position is valued as a total,
    // not as the position's size, and says what it realised.
    final exits = effect == HlPositionEffect.reduce ||
        effect == HlPositionEffect.close ||
        effect == HlPositionEffect.flip;
    final pnl = realizedPnl;
    final base = HlMarket.baseCoin(coin);
    final side = isSpot
        ? (isLong ? l10n.investingBought : l10n.investingSold)
        : (isLong ? l10n.longLabel : l10n.shortLabel);
    // The hero: what the fill was worth. An open or an add says the side
    // and the margin it took ("Long $12.00"), a spot fill its total, an
    // exit the total it closed.
    final amount = exits
        ? formatHlUsd(notionalUsd)
        : l10n.slipCtaSideAmount(
            side,
            formatHlUsd(isSpot || leverage <= 0
                ? notionalUsd
                : notionalUsd / leverage));
    return KuteConfirmation(
      message: l10n.confirmationOrderFilled,
      amount: amount,
      // The effect on a position already held ("Reduced long · 0.05 BTC",
      // "Closed long"); the coin itself for an open. The Amount row
      // carries the coin either way.
      contextLine: effectLabel ?? base,
      rows: {
        l10n.amount: '${formatHlSize(sizeFilled)} $coin',
        l10n.price2: formatHlPrice(avgPx, decimalCap: market?.pxDecimalCap),
        if (!isSpot && !exits) ...{
          l10n.chartPositionSize: formatHlUsd(notionalUsd),
          l10n.chartLeverage: '$leverage×',
        },
        if (exits && pnl != null)
          l10n.portfolioStatRealized:
              '${pnl >= 0 ? '+' : '−'}${formatHlUsd(pnl.abs())}',
      },
      detail: l10n.investingBalanceUpdating,
      onDone: () => Navigator.of(context).pop(),
      secondaryButtonText: l10n.investingViewPositions,
      onSecondary: () {
        final nav = Navigator.of(context);
        nav.pop();
        // What the account holds now: the Investments tab's Positions.
        openInvestmentsPositions(nav.context);
      },
    );
  }
}

/// An accepted order can still be unfilled. Keep that distinction explicit
/// while using the same confirmation and receipt as other money actions.
/// Under Done, "View orders" opens the Investments Portfolio on P&L
/// charts, where the order rests ([viewOrders]: the spending account's
/// slips; a Ledger's orders are not on that tab).
class HlOrderAcceptedOverlay extends StatelessWidget {
  const HlOrderAcceptedOverlay({
    super.key,
    required this.coin,
    this.market,
    required this.amount,
    this.isClose = false,
    this.viewOrders = false,
  });

  final String coin;
  final HlMarket? market;
  final String amount;
  final bool isClose;
  final bool viewOrders;

  @override
  Widget build(BuildContext context) => KuteConfirmation(
        tone: KuteConfirmationTone.pending,
        message: isClose
            ? context.l10n.investingCloseOrderAccepted
            : context.l10n.investingOrderAccepted,
        amount: amount,
        contextLine: HlMarket.baseCoin(coin),
        detail: context.l10n.investingOrderPendingFill,
        onDone: () => Navigator.of(context).pop(),
        secondaryButtonText:
            viewOrders ? context.l10n.investingViewOrders : null,
        onSecondary: viewOrders
            ? () {
                final nav = Navigator.of(context);
                nav.pop();
                openInvestmentsOrders(nav.context,
                    product: 'investing',
                    orderKind: isClose ? 'close' : 'open');
              }
            : null,
      );
}
