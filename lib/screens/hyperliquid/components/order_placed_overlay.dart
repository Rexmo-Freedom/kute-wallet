import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
// lib/screens/hyperliquid/components/order_placed_overlay.dart
//
// Confirmation shown after an Investing order fills. The order slip
// captures the root navigator BEFORE popping its sheets, then calls
// [pushHlOrderPlacedOverlay] with the actual fill from the exchange.

import 'package:flutter/material.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';

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
    return KuteConfirmation(
      message: context.l10n.confirmationOrderFilled,
      showCloseButton: true,
      buttonText: context.l10n.investingViewPositions,
      onDone: () {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(MaterialPageRoute(
            builder: (_) => const OpenInvestmentsScreen(
                product: InvestmentsProduct.trading)));
      },
      detail: context.l10n.investingBalanceUpdating,
      receipt: TradeReceipt(
          leading: HlCoinIcon(
              coin: HlMarket.baseCoin(coin),
              wireCoin: market?.wireCoin ?? coin,
              iconUrl: market?.iconUrl,
              category: market?.category),
          title: HlMarket.baseCoin(coin),
          subtitle: isSpot
              ? (isLong
                  ? context.l10n.investingBought
                  : context.l10n.investingSold)
              : effectLabel ??
                  '${isLong ? context.l10n.longLabel : context.l10n.shortLabel} · $leverage×',
          rows: {
            context.l10n.amount: '${formatHlSize(sizeFilled)} $coin',
            context.l10n.price2:
                formatHlPrice(avgPx, decimalCap: market?.pxDecimalCap),
            isSpot || exits ? context.l10n.total : context.l10n.chartPositionSize:
                formatHlUsd(notionalUsd),
            if (exits && pnl != null)
              l10n.portfolioStatRealized:
                  '${pnl >= 0 ? '+' : '−'}${formatHlUsd(pnl.abs())}',
          }),
    );
  }
}

/// An accepted order can still be unfilled. Keep that distinction explicit
/// while using the same confirmation and receipt as other money actions.
class HlOrderAcceptedOverlay extends StatelessWidget {
  const HlOrderAcceptedOverlay({
    super.key,
    required this.coin,
    this.market,
    required this.amount,
    this.isClose = false,
  });

  final String coin;
  final HlMarket? market;
  final String amount;
  final bool isClose;

  @override
  Widget build(BuildContext context) => KuteConfirmation(
        message: isClose
            ? context.l10n.investingCloseOrderAccepted
            : context.l10n.investingOrderAccepted,
        detail: context.l10n.investingOrderPendingFill,
        showCloseButton: true,
        onDone: () => Navigator.of(context).pop(),
        receipt: TradeReceipt(
          leading: HlCoinIcon(
              coin: HlMarket.baseCoin(coin),
              wireCoin: market?.wireCoin ?? coin,
              iconUrl: market?.iconUrl,
              category: market?.category),
          title: HlMarket.baseCoin(coin),
          rows: {context.l10n.amount: amount},
        ),
      );
}
