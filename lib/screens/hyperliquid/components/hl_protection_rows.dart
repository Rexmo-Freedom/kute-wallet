// lib/screens/hyperliquid/components/hl_protection_rows.dart
//
// The stop losses, take profits and trailing stops resting on one
// position, as plain rows on the app's rows card (position_rows_card.dart):
// the kind on the left, the trigger price and the size on the right. A
// tap offers the Orders sheet's own cancel, behind the app's confirm
// sheet. The spending account only: a Ledger's orders are not on it.
// Drawn under the position page's tiles (hl_position_detail_sheet.dart)
// and under the wide market page's position row (market_detail_sheet.dart),
// so the protection is visible as words, not only as chart lines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart'
    show hlCancelOneOrder, showHlOrderConfirm;
import 'package:kute/screens/shared/position_rows_card.dart';

/// The spending account's resting orders as last read, watched, without
/// starting the trading notifier from here (it is alive wherever there is
/// a position to protect; a page drawn without it lists nothing).
List<HlOpenOrder> hlWatchOpenOrders(WidgetRef ref) =>
    ref.exists(hyperliquidTradingProvider)
        ? ref.watch(hyperliquidTradingProvider).valueOrNull?.openOrders ??
            const <HlOpenOrder>[]
        : const <HlOpenOrder>[];

/// [hlWatchOpenOrders], read once (outside build).
List<HlOpenOrder> hlReadOpenOrders(WidgetRef ref) =>
    ref.exists(hyperliquidTradingProvider)
        ? ref.read(hyperliquidTradingProvider).valueOrNull?.openOrders ??
            const <HlOpenOrder>[]
        : const <HlOpenOrder>[];

/// The kind of protective order [o] is, in the app's words.
String hlProtectionKind(AppLocalizations l10n, HlOpenOrder o) {
  if (o.isTrailingStop) return l10n.investingTrailingStop;
  return o.tpsl == 'tp' ? l10n.hlTakeProfit : l10n.hlStopLoss;
}

/// Its trigger price and size ("$61,200 · 0.5 BTC"); a trailing stop has
/// no fixed price, a whole-position TP/SL no fixed size.
String hlProtectionValue(HlOpenOrder o, {required String coin, int? pxCap}) {
  final parts = <String>[
    if (!o.isTrailingStop)
      formatHlPrice(o.triggerPx ?? o.limitPx, decimalCap: pxCap),
    if (o.sz > 0) '${formatHlSize(o.sz)} $coin',
  ];
  return parts.join(' · ');
}

class HlProtectionRows extends ConsumerWidget {
  const HlProtectionRows({
    super.key,
    required this.coin,
    this.market,
    this.atSide,
    this.padding = EdgeInsets.zero,
  });

  /// Room around the card when it is drawn (none when there is no card).
  final EdgeInsetsGeometry padding;

  /// The position's wire coin.
  final String coin;
  final HlMarket? market;

  /// Opens what a tap opens the way the page opens its forms (the side
  /// panel on EXPANDED); as it is when null.
  final void Function(VoidCallback open)? atSide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched outright: this card sits on pages whose chart watches the
    // same state.
    final rows = hlProtectiveOrdersFor(
        ref.watch(hyperliquidTradingProvider).valueOrNull?.openOrders ??
            const <HlOpenOrder>[],
        coin);
    if (rows.isEmpty) return const SizedBox.shrink();
    final display = market?.coin ?? HlMarket.baseCoin(coin);
    final card = PositionRowsCard(
      key: const ValueKey('hl-position-protection'),
      rows: [
        for (final o in rows)
          PositionRow(
            hlProtectionKind(context.l10n, o),
            hlProtectionValue(o,
                coin: display, pxCap: market?.pxDecimalCap),
            key: ValueKey('hl-protection-${o.oid}'),
            onTap: () => _offerCancel(context, ref, o, display),
          ),
      ],
    );
    return Padding(padding: padding, child: card);
  }

  void _offerCancel(
      BuildContext context, WidgetRef ref, HlOpenOrder o, String display) {
    final l10n = context.l10n;
    Future<void> run() async {
      final ok = await showHlOrderConfirm(
        context,
        title: l10n.hlProtectCancelOrderTitle,
        subtitle: '${hlProtectionKind(l10n, o)} · '
            '${hlProtectionValue(o, coin: display, pxCap: market?.pxDecimalCap)}',
        cta: l10n.ledgerCancelOrderSummary,
      );
      if (!ok || !context.mounted) return;
      await hlCancelOneOrder(context, ref, o);
    }

    final side = atSide;
    if (side != null) {
      side(() => run());
    } else {
      run();
    }
  }
}
