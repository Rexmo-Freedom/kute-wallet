// Offline providers for widget tests that mount the one Portfolio screen
// (OpenInvestmentsScreen): both venues' books, the Wallet rows' balances
// and which venues the account has, without a network or a Hive box.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPortfolioEventsPrefetchProvider;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/portfolio/portfolio_wallet_rows.dart';
import 'package:money2/money2.dart';

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

const kPortfolioBothVenues =
    PortfolioVenues(trading: true, predictions: true, dollars: true);

/// [btcUsd] is the price of one bitcoin in dollars.
List<Override> portfolioOverrides({
  HyperliquidTradingState trading = const HyperliquidTradingState(),
  List<PlacingBet> placing = const [],
  PortfolioVenues venues = kPortfolioBothVenues,
  int sats = 250000,
  double dollars = 42.5,
  double btcUsd = 100000,

  /// False when the test overrides the trade notifications itself.
  bool notifications = true,
}) =>
    [
      hyperliquidTradingProvider
          .overrideWith(() => PortfolioTestTrading(trading)),
      hyperliquidUserFillsProvider.overrideWith((_) async => []),
      polymarketTradingProvider.overrideWith(_Poly.new),
      polymarketCombosProvider.overrideWith(_Combos.new),
      placingPolymarketBetProvider.overrideWith(() => _Placing(placing)),
      polyPortfolioEventsPrefetchProvider.overrideWith((_) {}),
      if (notifications)
        tradeNotificationsProvider.overrideWith((_) => Stream.value([])),
      portfolioVenuesProvider.overrideWithValue(venues),
      portfolioBitcoinSatsProvider.overrideWithValue(sats),
      usdBalanceProvider.overrideWithValue(dollars),
      selectedCurrencyProvider('USD').overrideWith(
          (_) => Money.fromNumWithCurrency(btcUsd, AppCurrencies.usd)),
    ];
