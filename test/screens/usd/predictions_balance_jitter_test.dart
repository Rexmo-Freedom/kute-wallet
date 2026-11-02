// The Predictions browse does not jump when the balance changes (founder,
// 2 November 2026: "the Predictions screen jitters sometimes when the
// balance changes").
//
// The cause: the Investments header's height is MEASURED from the hero
// (the total and the line under it), and the hero grows a line per money
// movement while an order or a deposit is on its way ("Placing $5 on
// Yes · Lakers", "Moving $5 from Dollars", "Incoming $20") and shrinks
// back when it lands. With the page scrolled (the header collapsed to its
// compact bar) the outer scroll stayed at the old collapse range while the
// range grew with the hero, so the header re-expanded by the new lines'
// height: the compact bar half faded, a slice of the hero showed and the
// list under it slid down, then back up when the lines left. Collapsed,
// the header now stays collapsed through a resize (the outer scroll moves
// with the range), so the list does not move.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';
import 'investments_harness.dart'
    show
        InvestmentsTestPolicy,
        RecordingRefresh,
        RecordingRewardsApi,
        kEarnOff,
        kInvestmentsTestBalance;

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void registerCardTokens(List<String> tokens) {}
  @override
  void unregisterCardTokens(List<String> tokens) {}
}

class _Odds extends CryptoLiveOddsNotifier {
  @override
  Map<String, CryptoLiveOdds> build() => const {};
  @override
  void watch(String token) {}
  @override
  void unwatch(String token) {}
}

/// No round: the 5m card keeps its skeleton, the list is what scrolls.
class _NoRound extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) =>
      Completer<CryptoPredictState>().future;
}

/// Twelve plain markets, enough to scroll a phone's height.
class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => PolyFeedState(
        done: true,
        events: [
          for (var i = 0; i < 12; i++)
            PolymarketEvent(
              id: 'm$i',
              slug: 'market-$i',
              title: 'Market number $i resolves Yes?',
              volume: 1e6 * (12 - i),
              liquidity: 1e5,
              category: 'politics',
              conditionId: 'm$i',
              endDate: DateTime(2026, 12, 31),
              outcomes: const [
                PolymarketOutcome(name: 'Yes', price: 0.6),
                PolymarketOutcome(name: 'No', price: 0.4),
              ],
            ),
        ],
      );
}

/// The balance the test changes under the page.
final _balance =
    StateProvider<OneBalanceState>((_) => kInvestmentsTestBalance);

/// Money on its way: two in-flight lines under the total.
const _moving = OneBalanceState(
  dollarsUsd: 25,
  investedUsd: 0,
  investingKnown: true,
  predictionsKnown: true,
  inFlight: [InFlightMove(kind: InFlightKind.incomingDollars, usd: 20)],
  waiting: {OneBalanceVenue.predictions: 5},
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final policy = InvestmentsTestPolicy(kEarnOff, browsePredictions: true);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(dollars: 25),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      oneBalanceProvider.overrideWith((ref) => ref.watch(_balance)),
      usdBalanceProvider.overrideWithValue(25),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      usdRewardsApiProvider.overrideWithValue(RecordingRewardsApi()),
      aiEnabledProvider.overrideWith((_) async => true),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidPerpCoreMarketsProvider
          .overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      polyBrowseFeedProvider.overrideWith(_Feed.new),
      cryptoPredictProvider.overrideWith(_NoRound.new),
      cryptoPredictWindowsProvider.overrideWith((_, __) async => [5]),
      cryptoRecentResultsProvider.overrideWith((_, __) async => const []),
      cryptoLiveOddsProvider.overrideWith(_Odds.new),
      livePriceProvider.overrideWith(_Prices.new),
      refreshEverythingProvider.overrideWith(RecordingRefresh.new),
      investmentsTabProvider.overrideWith((_) => InvestmentsTab.predictions),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Inter',
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UsdAccountScreen(),
      ),
    ),
  ));
  await _frames(tester);
  return ProviderScope.containerOf(
      tester.element(find.byType(UsdAccountScreen)));
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Where a market row sits on screen, frame by frame.
double _rowTop(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title).first).dy;

final _compactTotal = find.byKey(const ValueKey('investments-compact-total'));

/// The compact bar's opacity: 1 when the header is fully collapsed.
double _compactOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
        find.ancestor(of: _compactTotal, matching: find.byType(Opacity)).first)
    .opacity;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'scrolled, money on its way and landing moves nothing: the compact '
      'bar stays, the rows stay put, frame by frame', (tester) async {
    final container = await _pump(tester);
    // Scroll into the list: the header collapses to the compact bar.
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
    await _frames(tester);
    expect(_compactTotal, findsOneWidget);
    expect(_compactOpacity(tester), 1);
    const row = 'Market number 6 resolves Yes?';
    expect(find.text(row), findsWidgets);
    final top = _rowTop(tester, row);

    // Money on its way: the hero (offstage) grows two lines.
    container.read(_balance.notifier).state = _moving;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_rowTop(tester, row), top, reason: 'frame $i after the lines');
      expect(_compactOpacity(tester), 1);
    }
    // And lands: the lines go, the total moves.
    container.read(_balance.notifier).state = const OneBalanceState(
        dollarsUsd: 20,
        investedUsd: 5,
        investingKnown: true,
        predictionsKnown: true);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_rowTop(tester, row), top, reason: 'frame $i after landing');
      expect(_compactOpacity(tester), 1);
    }
    expect(tester.widget<Text>(_compactTotal).data, r'$25.00');

    // Back at the top the hero carries the lines again in full.
    container.read(_balance.notifier).state = _moving;
    await _frames(tester, 3);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, 2000));
    await _frames(tester, 10);
    expect(find.text(r'Incoming $20.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets(
      'at the top, a total that ticks keeps the hero\'s height: the rows '
      'do not move', (tester) async {
    final container = await _pump(tester);
    const row = 'Market number 0 resolves Yes?';
    final top = _rowTop(tester, row);
    for (final usd in [25.01, 9.99, 10.0, 1234.56, 99999.99, 7.0]) {
      container.read(_balance.notifier).state = OneBalanceState(
          dollarsUsd: usd,
          investedUsd: usd / 3,
          investingKnown: true,
          predictionsKnown: true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(_rowTop(tester, row), top, reason: '\$$usd, frame $i');
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });
}
