// Offline providers for widget tests that mount the one Portfolio screen
// (OpenInvestmentsScreen): both venues' books, the dollar balance and
// which venues the account has, without a network or a Hive box.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/address_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/address_provider.dart'
    show initialAddressesProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPortfolioEventsPrefetchProvider;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:money2/money2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import 'fake_swap_orders.dart';

class PortfolioTestTrading extends HyperliquidTradingNotifier {
  PortfolioTestTrading([this.initial = const HyperliquidTradingState()]);
  final HyperliquidTradingState initial;

  @override
  Future<HyperliquidTradingState> build() async => initial;
}

class _Poly extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState();
}

class _Combos extends PolymarketCombosNotifier {
  @override
  Future<PolymarketCombosState> build() async => const PolymarketCombosState();
}

class _Placing extends PlacingPolymarketBetNotifier {
  _Placing(this.initial);
  final List<PlacingBet> initial;

  @override
  List<PlacingBet> build() => initial;
}

/// An empty Investing account (the Statistics tab reads it alongside the
/// trading state), without the venue or the conversion store.
class PortfolioTestAccount extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
      accountValue: 0,
      withdrawable: 0,
      totalMarginUsed: 0,
      positions: [],
      spotBalances: []);
}

/// The spending account's transaction cache, seeded in memory.
class PortfolioTestTransactionCache extends WalletTransactionCacheNotifier {
  PortfolioTestTransactionCache(Map<String, Transaction> seed) {
    state = seed;
  }
}

const kPortfolioBothVenues = PortfolioVenues(trading: true, predictions: true);

/// Nothing charted yet, for either venue's Statistics.
const kPortfolioNoPerformance = PortfolioPerformance(
    points: [],
    sourceLabel: '',
    basisLabel: 'P&L',
    coverageLabel: 'No observations');

/// [btcUsd] is the price of one bitcoin in dollars.
List<Override> portfolioOverrides({
  HyperliquidTradingState trading = const HyperliquidTradingState(),
  List<PlacingBet> placing = const [],
  PortfolioVenues venues = kPortfolioBothVenues,
  double dollars = 42.5,
  double btcUsd = 100000,

  /// False when the test overrides the trade notifications itself.
  bool notifications = true,

  /// The spending account's history (the Activity tab's rows).
  Transaction? history,
}) =>
    [
      hyperliquidTradingProvider
          .overrideWith(() => PortfolioTestTrading(trading)),
      hyperliquidUserFillsProvider.overrideWith((_) async => []),
      polymarketTradingProvider.overrideWith(_Poly.new),
      // The Orders tab reads both venues: no Predictions orders, and no
      // poll timer left pending at the end of a test.
      polymarketOpenOrdersProvider
          .overrideWith((_) => Stream.value(const <Order>[])),
      polymarketCombosProvider.overrideWith(_Combos.new),
      placingPolymarketBetProvider.overrideWith(() => _Placing(placing)),
      polyPortfolioEventsPrefetchProvider.overrideWith((_) {}),
      if (notifications)
        tradeNotificationsProvider.overrideWith((_) => Stream.value([])),
      portfolioVenuesProvider.overrideWithValue(venues),
      usdBalanceProvider.overrideWithValue(dollars),
      // Statistics: nothing charted, an empty account, no conversion store
      // (which would open a Hive box), no network.
      hyperliquidAccountProvider.overrideWith(PortfolioTestAccount.new),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      for (final venue in PortfolioPerformanceVenue.values)
        portfolioPerformanceProvider(PortfolioPerformanceRequest(venue: venue))
            .overrideWith((_) async => kPortfolioNoPerformance),
      // Activity: the account's own history, in memory, and the addresses
      // its rows are judged against.
      walletTransactionCacheProvider.overrideWith((_) =>
          PortfolioTestTransactionCache(
              {if (history != null) 'spending': history})),
      initialAddressesProvider.overrideWith((_) async =>
          Address(bitcoinAddressIndex: 0, bitcoinAddress: 'bc1qself')),
      sparkSelfAddressProvider.overrideWith((_) async => 'sp1self'),
      selectedCurrencyProvider('USD').overrideWith(
          (_) => Money.fromNumWithCurrency(btcUsd, AppCurrencies.usd)),
    ];
