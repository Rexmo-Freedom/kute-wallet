// lib/providers/unified_balances_provider.dart
//
// The spending account's venue money, split into "ready" (idle cash the
// sweeper brings home) and "invested" (open positions and cash held by
// resting orders), per venue, with a flag per venue saying whether the
// figures are the venue's real answer. Display and analytics only:
// nothing here moves money.
//
// The per-venue split reuses the Portfolio's own arithmetic
// ([hyperliquidInvestmentBalances] / [polymarketInvestmentBalances]),
// whose Available and Portfolio never double-count one another, so
// ready + invested is every venue dollar exactly once. The one-balance
// header counts only `invested`: ready cash is on its way back to
// Dollars and shows as in flight or waiting instead.
//
// Ported from the `unification-test` branch (2026-10) without the Home
// Cash / Invested split, which one balance replaces.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';

/// The spending account's venue money, in USD.
class UnifiedVenueBalances {
  /// Idle Hyperliquid USDC: perp withdrawable + unheld spot USDC.
  final double readyInInvestingUsd;

  /// Idle Predictions cash (pUSD / USDC on the deposit wallet), net of what
  /// resting buy orders hold.
  final double readyInPredictionsUsd;

  /// Hyperliquid money at work: committed perp equity + spot holdings + spot
  /// USDC held by orders.
  final double investedInInvestingUsd;

  /// Predictions money at work: open positions + combos + cash held by
  /// resting buy orders.
  final double investedInPredictionsUsd;

  /// Whether the Investing figures are the venue's real answer (this wallet
  /// never provisioned Hyperliquid, so both are 0, or its trading state has
  /// loaded) rather than a placeholder.
  final bool investingKnown;

  /// Whether the Predictions figures are the venue's real answer (the
  /// trading state authenticated with a known balance).
  final bool predictionsKnown;

  const UnifiedVenueBalances({
    this.readyInInvestingUsd = 0,
    this.readyInPredictionsUsd = 0,
    this.investedInInvestingUsd = 0,
    this.investedInPredictionsUsd = 0,
    this.investingKnown = false,
    this.predictionsKnown = false,
  });

  static const empty = UnifiedVenueBalances();

  double get readyUsd => readyInInvestingUsd + readyInPredictionsUsd;
  double get investedUsd => investedInInvestingUsd + investedInPredictionsUsd;
}

double _clean(double? v) => v != null && v.isFinite && v > 0 ? v : 0;

/// Venue cash and positions of the spending account.
///
/// Hyperliquid: the full trading state when this wallet has provisioned
/// Hyperliquid (the badge poll's once-flag), else the always-on coarse free
/// USDC figure. A wallet that never traded never spins up the trading stack.
/// Spot prices are read only when the account holds a non-USDC spot token.
///
/// Predictions: the trading state the Home already pre-flushes, with its own
/// open orders (no extra order poll). Before it authenticates, the cached
/// cash figure stands in and Invested waits.
final unifiedVenueBalancesProvider = Provider<UnifiedVenueBalances>((ref) {
  // Only the spending account owns venues: a Ledger, Bitcoin-only,
  // watch-only or tracked wallet (or no wallet yet) knows nothing here.
  final ownsVenues = ref.watch(
      settingsProvider.select((s) => s.activeWallet?.isSparkWallet ?? false));
  if (!ownsVenues) return UnifiedVenueBalances.empty;

  var hlReady = _clean(ref.watch(hyperliquidFreeUsdcProvider));
  var hlInvested = 0.0;
  final hlProvisioned = ref.watch(hyperliquidProvisionedProvider);
  var hlKnown = !hlProvisioned;
  if (hlProvisioned) {
    final hl = ref.watch(hyperliquidTradingProvider).valueOrNull;
    if (hl != null && hl.isInitialized) {
      final needsPrices =
          hl.spotBalances.any((b) => b.coin != 'USDC' && b.total > 0);
      final spot = needsPrices
          ? ref.watch(hyperliquidSpotTickersProvider).valueOrNull
          : null;
      final b = hyperliquidInvestmentBalances(
        state: hl,
        spotPrices: spot == null
            ? const {}
            : {
                for (final t in spot.tickers.entries) t.key: t.value.markPrice,
              },
      );
      if (b.available != null) hlReady = _clean(b.available);
      // A spot token without a price yet leaves Portfolio unknown; keep the
      // committed perp equity rather than drop the whole venue to 0.
      hlInvested = b.portfolio != null
          ? _clean(b.portfolio)
          : _clean(hl.perpEquity - hl.withdrawable);
      hlKnown = true;
    }
  }

  var pmReady = _clean(ref.watch(polymarketBalanceProvider));
  var pmInvested = 0.0;
  final pm = ref.watch(polymarketTradingProvider).valueOrNull;
  final pmKnown = pm != null && pm.isAuthenticated && pm.balanceKnown;
  if (pm != null && pm.isAuthenticated) {
    final combos = ref.watch(polymarketCombosValueProvider);
    final b = polymarketInvestmentBalances(
      state: pm,
      orders: pm.openOrders,
      comboValueUsd: combos,
    );
    if (b.available != null) {
      pmReady = _clean(b.available);
      pmInvested = _clean(b.portfolio);
    } else if (pm.balanceKnown) {
      // An order the arithmetic could not read: count all cash as ready and
      // the positions as invested, so nothing is counted twice.
      pmReady = _clean(pm.usdcBalance);
      pmInvested = _clean(b.positions);
    } else {
      // The cash read failed: it is unknown, not $0.00. Ready keeps the
      // last balance read (polymarketBalanceProvider's mirror) and the
      // venue reads as not known, so the total keeps its stale shimmer.
      pmInvested = _clean(b.positions);
    }
  }

  return UnifiedVenueBalances(
    readyInInvestingUsd: hlReady,
    readyInPredictionsUsd: pmReady,
    investedInInvestingUsd: hlInvested,
    investedInPredictionsUsd: pmInvested,
    investingKnown: hlKnown,
    predictionsKnown: pmKnown,
  );
});
