import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:intl/intl.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/activity_row_copy.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/historical_price_provider.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/bitcoin_performance_comparison.dart';
import 'package:kute/theme/app_theme.dart';

final _bitcoinComparison =
    FutureProvider.autoDispose.family<double?, HlFill>((ref, target) async {
  // The exchange does not return historical allocated margin with perp
  // fills. Notional is NOT capital invested; never pretend it is.
  final spot = target.coin.startsWith('@') || target.coin.contains('/');
  if (!spot) return null;
  final coin =
      ref.watch(hyperliquidWireToCoinMapProvider)[target.coin] ?? target.coin;
  final balances = ref.watch(hyperliquidSpotBalancesProvider);
  final mid = ref.watch(hyperliquidLiveMidProvider(coin));
  final btcNow = ref.watch(selectedCurrencyProvider('USD')).toDouble();
  final history = (await ref.watch(hyperliquidUserFillsProvider.future))
      .where((f) =>
          f.coin == target.coin && (target.isBuy || f.time <= target.time))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  await prewarmBtcPriceHistory();
  double units = 0, bitcoin = 0;
  for (final fill in history) {
    if (fill.isBuy) {
      final rate = await ref.watch(historicalBtcPriceProvider(
              DateTime.fromMillisecondsSinceEpoch(fill.time, isUtc: true))
          .future);
      if (rate == null || rate <= 0) return null;
      units += fill.sz;
      bitcoin += fill.px * fill.sz / rate;
    } else {
      if (units <= 0 || fill.sz > units + 1e-9) return null;
      final fraction = (fill.sz / units).clamp(0.0, 1.0);
      if (!target.isBuy &&
          (identical(fill, target) ||
              (fill.tradeId != null && fill.tradeId == target.tradeId))) {
        final rate = await ref.watch(historicalBtcPriceProvider(
                DateTime.fromMillisecondsSinceEpoch(fill.time, isUtc: true))
            .future);
        if (rate == null || rate <= 0 || bitcoin <= 0) return null;
        return (fill.px * fill.sz / (bitcoin * fraction * rate) - 1) * 100;
      }
      units -= fill.sz;
      bitcoin *= 1 - fraction;
    }
  }
  if (target.isBuy &&
      units > 0 &&
      bitcoin > 0 &&
      btcNow > 0 &&
      mid != null &&
      mid > 0) {
    for (final balance in balances) {
      if (balance.coin != coin) continue;
      if ((balance.total - units).abs() > 1e-6) return null;
      return (balance.total * mid / (bitcoin * btcNow) - 1) * 100;
    }
  }
  return null;
});

/// Shared portfolio activity row. Ledger callers never read the spending
/// wallet's balances or trade history for comparisons.
class HyperliquidFillActivityRow extends ConsumerWidget {
  const HyperliquidFillActivityRow(
      {super.key, required this.fill, this.compareWithSpendingWallet = false});
  final HlFill fill;
  final bool compareWithSpendingWallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _fillRow(
        context,
        ref,
        fill,
        onTap: () => showAppBottomSheet(
            context: context,
            builder: (_) => _FillDetails(
                fill: fill,
                compareWithSpendingWallet: compareWithSpendingWallet)),
      );
}

/// The activity row of [fill]. Its detail sheet opens with the same row.
Widget _fillRow(BuildContext context, WidgetRef ref, HlFill fill,
    {VoidCallback? onTap}) {
  final market = ref.watch(hyperliquidAccountMarketProvider(fill.coin));
  final coin = market?.coin ?? fill.coin;
  final symbol = hlBaseCoin(coin);
  final friendly = hlFriendlyName(symbol) ?? hlFriendlyName(coin);
  final time =
      DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(fill.time));
  final pnl = fill.closedPnl;
  return buildWalletActivityRow(
    // Round like every other row tile, the letter fallback included.
    leading: ClipOval(
      child: HlCoinIcon(
          coin: coin,
          wireCoin: market?.wireCoin ?? fill.coin,
          iconUrl: market?.iconUrl,
          category: market?.category,
          size: 44),
    ),
    title: activityRowTitle(hlFillRowTitle(fill, symbol, context.l10n)),
    subtitle: friendly == null ? time : '$friendly · $time',
    amount: formatPolyAmount(ref, fill.px * fill.sz),
    flow: hlFillFlow(fill),
    // The one figure under the amount: what closing realised, coloured.
    secondaryAmount: pnl == 0
        ? ''
        : '${pnl > 0 ? '+' : '−'}${formatPolyAmount(ref, pnl.abs())}',
    secondaryColor: pnl > 0 ? AppColors.marketUp : AppColors.marketDown,
    onTap: onTap,
  );
}

class _FillDetails extends ConsumerWidget {
  const _FillDetails(
      {required this.fill, required this.compareWithSpendingWallet});
  final bool compareWithSpendingWallet;
  final HlFill fill;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final market = ref.watch(hyperliquidAccountMarketProvider(fill.coin));
    final coin = market?.coin ?? fill.coin;
    final spot = fill.coin.startsWith('@') || fill.coin.contains('/');
    final benchmark = compareWithSpendingWallet && spot
        ? ref.watch(_bitcoinComparison(fill))
        : null;
    return AppBottomSheetContainer(
      child: SafeArea(
          top: false,
          child: SheetScrollView(
            padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 32.h),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TransactionDetailHeader(
                row: _fillRow(context, ref, fill),
                advisorSurface: 'hl_activity_detail',
              ),
              SheetDetailRow(
                  label: context.l10n.date,
                  value: activitySheetDate(
                      context, DateTime.fromMillisecondsSinceEpoch(fill.time))),
              SheetDetailRow(
                  label: context.l10n.ledgerSummaryMarket, value: hlFriendlyName(coin) ?? coin),
              SheetDetailRow(
                  label: context.l10n.amount, value: '${formatHlSize(fill.sz)} $coin'),
              SheetDetailRow(
                  label: context.l10n.fillExecutionPrice,
                  value: formatHlPrice(fill.px, decimalCap: market?.pxDecimalCap)),
              if (!spot && fill.dir.isNotEmpty)
                SheetDetailRow(
                    label: context.l10n.fillDirection,
                    value: _directionLabel(context.l10n, fill.dir)),
              // The realised P&L is the figure under the header's amount.
              MoneyFeeSummary(
                  label: fill.fee < 0
                      ? context.l10n.feeUiFeeRebate
                      : context.l10n.feeUiPaidFee,
                  bitcoinFirst: false,
                  usd: fill.feeToken == 'USDC' ? fill.fee.abs() : null,
                  state: fill.feeToken == 'USDC'
                      ? null
                      : '${fill.fee} ${fill.feeToken}',
                  note: context.l10n.feeUiIncludesAnyKuteBuilderFee),
              if (benchmark != null)
                BitcoinPerformanceComparison(
                    percent: benchmark.valueOrNull,
                    loading: benchmark.isLoading,
                    label: context.l10n.feeUiVsHoldingBitcoin,
                    unavailable: context.l10n.feeUiEntryHistoryUnavailable),
              SheetNerdDataSection(children: [
                SheetDetailRow(
                    label: context.l10n.orderId, value: '${fill.oid}', copiable: true),
                if (fill.tradeId != null)
                  SheetDetailRow(
                      label: context.l10n.fillId, value: fill.tradeId!, copiable: true),
                // The transaction hash is deliberately not shown on a
                // closed trade (owner decision).
              ]),
            ]),
          )),
    );
  }
}

/// The venue's direction words ("Open Long", "Close Short", "Long >
/// Short") in the app's language; anything else as the venue sent it.
String _directionLabel(AppLocalizations l, String dir) {
  String side(String word) => word.trim().toLowerCase() == 'short'
      ? l.shortLabel
      : l.longLabel;
  final d = dir.trim();
  final lower = d.toLowerCase();
  if (lower.startsWith('open ')) {
    return '${l.hlFillOpened} · ${side(d.substring(5))}';
  }
  if (lower.startsWith('close ')) {
    return '${l.hlFillClosed} · ${side(d.substring(6))}';
  }
  if (d.contains('>')) {
    return '${l.hlFillReversed} · ${side(d.split('>').last)}';
  }
  if (lower.contains('liquidat')) return l.hlFillLiquidated;
  if (lower == 'buy') return l.investingBought;
  if (lower == 'sell') return l.investingSold;
  return d;
}
