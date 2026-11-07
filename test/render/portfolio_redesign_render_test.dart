// The redesigned Portfolio screen (7 November 2026), by eye: every tab
// (Positions, P&L, Activity) in light and dark, with positions and a gain,
// with nothing at all, and with a loss. Written only when asked:
//
//   PORTFOLIO_REDESIGN_RENDER=<dir> flutter test test/render/portfolio_redesign_render_test.dart
//
// The real Inter face; 390 wide at 3x, tall enough for each tab's list.
// <case>_<tab>_<theme>.png: case gain | empty | loss, tab positions | pnl
// | activity, theme light | dark; and gain_<tab>_light_<lang>.png in the
// long locales (de, fi, hu) at 375 pt.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/models/polymarket_model.dart'
    show Activity, PolymarketPricePoint;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/open_pnl_history_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/portfolio_screen.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/portfolio_overrides.dart';

final _dir = Platform.environment['PORTFOLIO_REDESIGN_RENDER'];

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();
  @override
  Future<void> preview() async {}
  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// The live prices, quiet: no socket, the prices given.
class _Prices extends LivePriceNotifier {
  _Prices(this.prices);
  final Map<String, double> prices;
  @override
  LivePriceState build() => LivePriceState(live: true, prices: prices);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void subscribeTokens(List<String> tokenIds) {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokenIds) {}
  @override
  void unregisterCardTokens(List<String> tokenIds) {}
  @override
  void removeTokens(List<String> tokenIds) {}
  @override
  void unsubscribeAll() {}
}

enum _Case { gain, empty, loss }

HlPerpPosition _perp(String coin, double szi, double entry, double pnl) =>
    HlPerpPosition(
        coin: coin,
        szi: szi,
        entryPx: entry,
        positionValue: (szi * entry).abs() + pnl,
        unrealizedPnl: pnl,
        returnOnEquity: pnl / 40,
        liquidationPx: null,
        marginUsed: 40 + pnl,
        leverageType: 'isolated',
        leverageValue: 1,
        maxLeverage: 10);

PolymarketPosition _poly(String token, String q, String outcome, double size,
        double avg, double price) =>
    PolymarketPosition(
        marketId: token,
        marketQuestion: q,
        outcome: outcome,
        size: size,
        avgPrice: avg,
        currentPrice: price,
        pnl: 0,
        pnlPercent: 0,
        isResolved: false,
        tokenId: token);

/// A smooth price around [base], one candle a step.
OpenPnlSources _sources(DateTime now, {required bool falling}) =>
    OpenPnlSources(
      activity: (_) async => const [],
      candles: (_, wire, interval, window) async {
        final step = switch (interval) {
          '15m' => const Duration(minutes: 15),
          '1h' => const Duration(hours: 1),
          _ => const Duration(days: 1),
        };
        final base = wire == 'BTC' ? 60000.0 : 240.0;
        final out = <HyperliquidCandle>[];
        final n = window.inMinutes ~/ step.inMinutes;
        var i = 0;
        for (var t = now.subtract(window); t.isBefore(now); t = t.add(step)) {
          final f = n == 0 ? 0.0 : i / n;
          final drift = (falling ? -0.04 : 0.03) * f;
          final px = base * (1 + drift + 0.001 * ((i * 7) % 5 - 2));
          out.add(HyperliquidCandle(
              openTime: t,
              closeTime: t.add(step),
              open: px,
              high: px,
              low: px,
              close: px,
              volume: 1));
          i++;
        }
        return out;
      },
      polyHistory: (_, token, interval) async {
        final out = <PolymarketPricePoint>[];
        var i = 0;
        for (var t = now.subtract(const Duration(days: 40));
            t.isBefore(now);
            t = t.add(const Duration(hours: 6))) {
          out.add(PolymarketPricePoint(
              timestamp: t,
              price: (falling ? 0.5 - i * 0.0007 : 0.3 + i * 0.0005)
                  .clamp(0.05, 0.95)));
          i++;
        }
        return out;
      },
    );

HlFill _fill(String coin, DateTime at,
        {required String side,
        required double sz,
        required double px,
        required double start,
        double closedPnl = 0,
        required int oid,
        required String dir}) =>
    HlFill(
      coin: coin,
      px: px,
      sz: sz,
      side: side,
      time: at.millisecondsSinceEpoch,
      closedPnl: closedPnl,
      fee: 0.02,
      feeToken: 'USDC',
      oid: oid,
      hash: '0x$oid',
      dir: dir,
      cloid: null,
      startPosition: start,
    );

PolymarketTransaction _bet(String id, DateTime at,
        {required String type,
        required String side,
        required double usdc,
        required String title,
        required String outcome}) =>
    PolymarketTransaction(
      id: id,
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0x$id',
        type: type,
        size: usdc * 2,
        usdcSize: usdc,
        transactionHash: '0x$id',
        side: side,
        asset: id,
        outcomeIndex: 0,
        title: title,
        outcome: outcome,
        eventSlug: '',
      ),
    );

List<Override> _caseOverrides(_Case c, DateTime now) {
  final utc = now.toUtc();
  PortfolioPerformance perf(List<(int, double)> points, String source,
          {PredictionsBook? book}) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(
                  timestamp: utc.subtract(Duration(days: days)), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          realizedPnlUsd: points.last.$2,
          openPnlUsd: 0,
          asOf: utc.subtract(Duration(days: points.last.$1)),
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time',
          predictions: book);
  if (c == _Case.empty) {
    return [
      ...portfolioOverrides(),
      polymarketActivePositionsProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWithValue(const []),
      oneBalanceProvider.overrideWith((ref) => const OneBalanceState(
            dollarsUsd: 25.68,
            investingKnown: true,
            predictionsKnown: true,
          )),
      livePriceProvider.overrideWith(() => _Prices(const {})),
    ];
  }
  final gain = c == _Case.gain;
  final perps = gain
      ? [_perp('BTC', 0.001, 60000, 1.20), _perp('ANTH', -0.5, 240, 0.84)]
      : [_perp('BTC', 0.001, 60000, -1.62), _perp('ANTH', -0.5, 240, -0.71)];
  final predictions = gain
      ? [
          _poly('fed-no', 'Fed cuts rates in December?', 'No', 10, 0.5, 0.61),
          _poly('lakers-yes', 'Will the Lakers win the 2026 NBA Finals?',
              'Yes', 4, 0.25, 0.3),
        ]
      : [
          _poly('fed-no', 'Fed cuts rates in December?', 'No', 10, 0.5, 0.388),
          _poly('lakers-yes', 'Will the Lakers win the 2026 NBA Finals?',
              'Yes', 4, 0.25, 0.21),
        ];
  final closed = PredictionsBook(records: [
    PredictionRecord(
      tokenId: 'rain-yes',
      conditionId: '0xrain',
      open: false,
      redeemable: false,
      size: 0,
      totalSize: 10,
      avgPrice: 0.5,
      entryCostUsd: 0,
      currentPrice: 1,
      realizedPnlUsd: gain ? 5 : -5,
      unrealizedPnlUsd: 0,
      firstEntryAt: utc.subtract(const Duration(days: 12)),
      lastEventAt: utc.subtract(const Duration(days: 3)),
      title: 'Will it rain in London tomorrow?',
      outcome: 'Yes',
    ),
  ]);
  final fills = [
    _fill('ETH', now.subtract(const Duration(days: 2)),
        side: 'A',
        sz: 0.01,
        px: gain ? 3120 : 2880,
        start: 0.01,
        closedPnl: gain ? 1.20 : -1.20,
        oid: 11,
        dir: 'Close Long'),
    _fill('ETH', now.subtract(const Duration(days: 9)),
        side: 'B', sz: 0.01, px: 3000, start: 0, oid: 10, dir: 'Open Long'),
    _fill('BTC', now.subtract(const Duration(days: 20)),
        side: 'B', sz: 0.001, px: 60000, start: 0, oid: 12, dir: 'Open Long'),
    _fill('ANTH', now.subtract(const Duration(days: 25)),
        side: 'A', sz: 0.5, px: 240, start: 0, oid: 13, dir: 'Open Short'),
  ];
  final history = Transaction(
    bitcoinTransactions: const [],
    sparkTransactions: const [],
    sparkUnclaimedDeposits: const [],
    polymarketTransactions: [
      _bet('rain-buy', now.subtract(const Duration(days: 12)),
          type: 'TRADE',
          side: 'BUY',
          usdc: 5,
          title: 'Will it rain in London tomorrow?',
          outcome: 'Yes'),
      _bet('rain-redeem', now.subtract(const Duration(days: 3)),
          type: 'REDEEM',
          side: '',
          usdc: gain ? 10 : 0,
          title: 'Will it rain in London tomorrow?',
          outcome: 'Yes'),
      _bet('fed-buy', now.subtract(const Duration(days: 5)),
          type: 'TRADE',
          side: 'BUY',
          usdc: 5,
          title: 'Fed cuts rates in December?',
          outcome: 'No'),
    ],
  );
  return [
    ...portfolioOverrides(
        trading: HyperliquidTradingState(isInitialized: true, positions: perps),
        history: history,
        openPnlSources: _sources(now, falling: !gain)),
    for (final coin in const ['BTC', 'ANTH', 'ETH']) ...[
      hyperliquidLiveMidProvider(coin).overrideWith((_) => null),
      hyperliquidAccountMarketProvider(coin).overrideWith((_) => null),
    ],
    polymarketActivePositionsProvider.overrideWith((_) => predictions),
    livePriceProvider.overrideWith(() => _Prices(
        {for (final p in predictions) p.tokenId!: p.currentPrice})),
    hyperliquidActivityFillsProvider.overrideWithValue(fills),
    oneBalanceProvider.overrideWith((ref) => OneBalanceState(
          dollarsUsd: 12.4,
          investedUsd: gain ? 87.12 : 79.64,
          investedByVenue: {
            OneBalanceVenue.investing: gain ? 80.42 : 77.3,
            OneBalanceVenue.predictions: gain ? 6.7 : 2.34,
          },
          investingKnown: true,
          predictionsKnown: true,
          venueCash: const {
            OneBalanceVenue.investing: 3.1,
            OneBalanceVenue.predictions: 0.6,
          },
        )),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => perf(
            gain
                ? [
                    (60, 0),
                    (48, 0.3),
                    (36, -0.4),
                    (24, 0.4),
                    (18, -0.3),
                    (12, 0.9),
                    (6, 1.4),
                    (1, 2.04)
                  ]
                : [(30, 0), (24, -0.3), (18, 0.2), (12, -1.1), (6, -2.4), (1, -3.53)],
            'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async => perf(
            gain
                ? [(14, 0), (10, 1.2), (3, 5.0), (1, 5.81)]
                : [(14, 0), (10, -1.2), (3, -5.0), (1, -6.66)],
            'Polymarket',
            book: closed)),
    hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
    hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
  ];
}

Future<void> _font() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
    ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  SalSpriteCache.debugSetManifest(
      jsonDecode(await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>);
  for (final clip in ['idle', 'curious', 'think', 'happy']) {
    await SalSpriteCache.clip(clip, 3);
  }
}

Future<void> _write(WidgetTester tester, Finder boundary, String name) async {
  final render = tester.renderObject(boundary) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data;
  });
  File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final (c, dark, lang, width) in [
    for (final c in _Case.values)
      for (final dark in const [false, true]) (c, dark, 'en', 390.0),
    // The long locales at 375 pt: every line on one line.
    for (final lang in const ['de', 'fi', 'hu']) (_Case.gain, false, lang, 375.0),
  ]) {
    {
      final theme = dark ? 'dark' : 'light';
      final tag = lang == 'en' ? theme : '${theme}_$lang';
      testWidgets('${c.name}, $tag: positions, P&L and activity',
          (tester) async {
        Directory(_dir!).createSync(recursive: true);
        await tester.runAsync(_font);
        addTearDown(() => SalSpriteCache.debugSetManifest(null));
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = Size(width, 1400) * 3;
        addTearDown(tester.view.reset);
        final now = DateTime.now();
        final screen = GlobalKey();
        final base = dark ? buildDarkTheme() : buildLightTheme();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            ..._caseOverrides(c, now),
            currentBtcUsdProvider.overrideWithValue(100000),
            settingsProvider.overrideWith((_) => SettingsModel(Settings(
                currency: 'USD',
                language: lang,
                btcFormat: 'sats',
                backup: false,
                biometricsEnabled: false,
                bitcoinElectrumNode: '',
                nodeType: '',
                reviewDone: true,
                activeWalletId: 'spending',
                wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
            usdBalanceUnknownProvider.overrideWithValue(false),
            venueSweeperProvider.overrideWith(_Sweeper.new),
            portfolioSectionProvider
                .overrideWith((_) => PortfolioSection.balances),
          ],
          child: RepaintBoundary(
            key: screen,
            child: ScreenUtilInit(
              designSize: const Size(430, 932),
              builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(lang),
                theme: base.copyWith(
                    textTheme: base.textTheme.apply(fontFamily: 'Inter')),
                builder: withKuteShellBar,
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const PortfolioScreen(),
              ),
            ),
          ),
        ));
        await _frames(tester);
        expect(tester.takeException(), isNull);
        await _write(tester, find.byKey(screen), '${c.name}_positions_$tag');
        await tester
            .tap(find.byKey(const ValueKey('portfolio-section-pill-charts')));
        await _frames(tester);
        expect(tester.takeException(), isNull);
        await _write(tester, find.byKey(screen), '${c.name}_pnl_$tag');
        await tester
            .tap(find.byKey(const ValueKey('portfolio-section-pill-activity')));
        await _frames(tester);
        expect(tester.takeException(), isNull);
        await _write(tester, find.byKey(screen), '${c.name}_activity_$tag');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }, skip: _dir == null);
    }
  }
}
