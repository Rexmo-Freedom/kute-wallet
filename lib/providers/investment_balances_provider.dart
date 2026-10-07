import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/hyperliquid_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

/// Available is spendable cash. Portfolio is money committed to investments,
/// including order reservations; the two do not double-count one another.
/// Null amounts mean required reads/prices are not yet available.
class InvestmentBalances {
  final double? available;
  final double? portfolio;
  final double? total;
  final double? positions;
  final double? committed;
  final bool hasPortfolioContent;

  const InvestmentBalances({
    this.available,
    this.portfolio,
    this.total,
    this.positions,
    this.committed,
    this.hasPortfolioContent = false,
  });
}

InvestmentBalances hyperliquidInvestmentBalances({
  required HyperliquidTradingState state,
  required Map<String, double> spotPrices,
  bool hasHistory = false,
}) {
  var spotAvailable = 0.0;
  var spotInvested = 0.0;
  var missingPrice = false;
  var hasSpotHolding = false;
  for (final holding in state.spotBalances) {
    if (holding.coin == 'USDC') {
      spotAvailable += holding.available;
      spotInvested +=
          (holding.total - holding.available).clamp(0, double.infinity);
    } else if (holding.total > 0) {
      hasSpotHolding = true;
      final price = spotPrices[holding.coin];
      if (price == null || !price.isFinite || price <= 0) {
        missingPrice = true;
      } else {
        spotInvested += holding.total * price;
      }
    }
  }
  final available = state.withdrawable + spotAvailable;
  // Equity already includes P&L; notional positionValue would overstate this
  // by leverage. Held spot USDC remains in Portfolio until the order releases it.
  final committedPerpEquity =
      (state.perpEquity - state.withdrawable).clamp(0.0, double.infinity);
  final portfolio =
      missingPrice ? null : committedPerpEquity + spotInvested;
  return InvestmentBalances(
    available:
        available.isFinite ? available.clamp(0.0, double.infinity) : null,
    portfolio: portfolio?.isFinite == true ? portfolio : null,
    total: portfolio?.isFinite == true && available.isFinite
        ? portfolio! + available
        : null,
    hasPortfolioContent: state.positions.isNotEmpty ||
        state.openOrders.isNotEmpty ||
        state.runningTwaps.any((twap) => !twap.expired) ||
        state.recentFills.isNotEmpty ||
        hasHistory ||
        hasSpotHolding,
  );
}

/// [comboValueUsd] is the account's combos (parlays): open combos at
/// their ESTIMATE (product of the legs' prices) plus claimable payouts.
/// Combos are Positions Framework tokens, never in [state]'s CLOB
/// positions, so adding them here counts nothing twice.
InvestmentBalances polymarketInvestmentBalances({
  required PolymarketTradingState state,
  required List<Order>? orders,
  bool hasHistory = false,
  double comboValueUsd = 0,
  bool hasCombos = false,
}) {
  var reserved = 0.0;
  var complete = orders != null && state.usdcBalance.isFinite;
  for (final order in orders ?? const <Order>[]) {
    if (order.side.toUpperCase() != 'BUY') continue;
    final original = double.tryParse(order.originalSize);
    final matched = double.tryParse(order.sizeMatched);
    final price = double.tryParse(order.price);
    if (original == null ||
        matched == null ||
        price == null ||
        !original.isFinite ||
        !matched.isFinite ||
        !price.isFinite ||
        original < 0 ||
        matched < 0 ||
        price < 0 ||
        price > 1) {
      complete = false;
      continue;
    }
    reserved += (original - matched).clamp(0.0, double.infinity) * price;
  }
  final cash = state.usdcBalance.isFinite
      ? state.usdcBalance.clamp(0.0, double.infinity)
      : 0.0;
  final heldCash = reserved.clamp(0.0, cash);
  var positions = 0.0;
  var positionsComplete = true;
  for (final position in state.openPositions) {
    if (!position.currentValue.isFinite) {
      positionsComplete = false;
      complete = false;
    } else {
      positions += position.currentValue.clamp(0.0, double.infinity);
    }
  }
  if (comboValueUsd.isFinite && comboValueUsd > 0) {
    positions += comboValueUsd;
  }
  complete = complete && reserved.isFinite && positions.isFinite;
  return InvestmentBalances(
    available: complete ? cash - heldCash : null,
    portfolio: complete ? positions + heldCash : null,
    total: state.usdcBalance.isFinite && positionsComplete && positions.isFinite
        ? cash + positions
        : null,
    positions: positionsComplete && positions.isFinite ? positions : null,
    committed: complete ? heldCash : null,
    hasPortfolioContent: state.openPositions.isNotEmpty ||
        (orders?.isNotEmpty ?? false) ||
        state.closedPositions.isNotEmpty ||
        hasCombos ||
        hasHistory,
  );
}

final investmentBalancesProvider = Provider.autoDispose
    .family<InvestmentBalances, InvestmentsProduct>((ref, product) {
  if (product == InvestmentsProduct.trading) {
    final account = ref.watch(hyperliquidTradingProvider).valueOrNull;
    if (account == null || !account.isInitialized) {
      return const InvestmentBalances();
    }
    final spot = ref.watch(hyperliquidSpotTickersProvider).valueOrNull;
    final hasHistory = account.recentFills.isNotEmpty ||
        (ref.watch(hyperliquidUserFillsProvider).valueOrNull?.isNotEmpty ??
            false);
    return hyperliquidInvestmentBalances(
      state: account,
      spotPrices: spot == null
          ? const {}
          : {
              for (final ticker in spot.tickers.entries)
                ticker.key: ticker.value.markPrice
            },
      hasHistory: hasHistory,
    );
  }
  final account = ref.watch(polymarketTradingProvider).valueOrNull;
  if (account == null || !account.isAuthenticated) {
    return const InvestmentBalances();
  }
  final orders = ref.watch(polymarketOpenOrdersProvider).valueOrNull;
  final hasHistory =
      ref.watch(_predictionsPortfolioHistoryProvider).valueOrNull ?? false;
  final combos = ref.watch(polymarketCombosProvider).valueOrNull;
  return polymarketInvestmentBalances(
      state: account,
      orders: orders,
      hasHistory: hasHistory,
      comboValueUsd: combos?.valueUsd ?? 0,
      hasCombos: combos?.positions.isNotEmpty ?? false);
});

/// Only the address changes this historical-presence lookup. Price ticks must
/// not turn a visibility check into a fresh activity API call on every rebuild.
final _predictionsPortfolioHistoryProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final address = ref.watch(polymarketTradingProvider
      .select((state) => state.valueOrNull?.proxyWalletAddress));
  if (address == null || address.isEmpty) return false;
  final activity = await ref.read(polymarketActivityProvider.future);
  return activity.any((entry) => const {'TRADE', 'REDEEM', 'MERGE', 'SPLIT'}
      .contains(entry.type.toUpperCase()));
});
