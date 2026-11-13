// Render harness for the Portfolio's Positions pill as the Dollars Activity
// tab's squares (founder, 8 November 2026): Investing and Predictions
// together, odd counts (the last one the full-width compact card), a long
// title, a bet on its way, a combo at its estimate, a settled prediction
// and a settled combo behind "See all", balances hidden, the skeleton of a
// first load, nothing open at one venue, light and dark, at 320 and 375, in
// English and in German; open predictions with their chance bar (founder, 8
// November 2026) on the squares and on the lone full-width card, the window's
// name holding its time range on one line. Writes PNGs, the page tall enough
// to hold it all.
//
// Not part of the normal suite; it only runs when asked:
//
//   flutter test test/audit/positions_pill_squares_render_test.dart \
//     --dart-define=POSITIONS_SQUARES_OUT=/tmp/positions-squares

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart'
    show PolymarketEvent, PolymarketOutcome;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        polymarketClaimablePositionsProvider;
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart';

const _out = String.fromEnvironment('POSITIONS_SQUARES_OUT');
const _key = ValueKey('shot');
const _dpr = 2.0;

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();

  @override
  Future<void> preview() async {}

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
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

ComboLeg _leg(int i, String status, double price) => ComboLeg(
    index: i,
    positionId: '$i',
    outcomeIndex: 0,
    outcomeLabel: 'Yes',
    status: status,
    currentPrice: price,
    title: 'Leg $i',
    question: 'Leg $i?');

ComboPosition _combo(String id, {required List<ComboLeg> legs, bool redeem = false}) =>
    ComboPosition(
        conditionId: id,
        positionId: id,
        outcomeIndex: 0,
        shares: 40,
        entryAvgPrice: 0.25,
        stakeUsd: 10,
        entryFeesUsd: 0,
        realizedPayoutUsd: 0,
        status: redeem ? 'RESOLVED' : 'OPEN',
        redeemable: redeem,
        legsTotal: legs.length,
        legsResolved: 0,
        legsPending: legs.length,
        legs: legs);

class _Combos extends PolymarketCombosNotifier {
  @override
  Future<PolymarketCombosState> build() async => PolymarketCombosState(
        positions: [
          _combo('open', legs: [_leg(0, 'OPEN', 0.6), _leg(1, 'OPEN', 0.5)]),
          _combo('won',
              redeem: true,
              legs: [_leg(0, 'RESOLVED_WIN', 1), _leg(1, 'RESOLVED_WIN', 1)]),
        ],
      );
}

const _btc = HlPerpPosition(
    coin: 'BTC',
    szi: 0.0125,
    entryPx: 90120,
    positionValue: 1168.75,
    unrealizedPnl: 42.25,
    returnOnEquity: 0.0375,
    liquidationPx: null,
    marginUsed: 1126.5,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 40);

const _nvda = HlPerpPosition(
    coin: 'xyz:NVDA',
    szi: -3,
    entryPx: 182.4,
    positionValue: 558.3,
    unrealizedPnl: -11.1,
    returnOnEquity: -0.0203,
    liquidationPx: 360.2,
    marginUsed: 547.2,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 10);

const _gold = HlPerpPosition(
    coin: 'GOLD',
    szi: 0.5,
    entryPx: 2400,
    positionValue: 1200,
    unrealizedPnl: 0,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 1200,
    leverageType: 'isolated',
    leverageValue: 1,
    maxLeverage: 10);

HlMarket _perp(String coin, String wire, double mid,
        {String category = 'crypto', bool hip3 = false}) =>
    HlMarket(
        coin: coin,
        wireCoin: wire,
        assetId: 1,
        kind: HlMarketKind.perp,
        szDecimals: 4,
        maxLeverage: 10,
        onlyIsolated: false,
        markPx: mid,
        midPx: mid,
        prevDayPx: mid,
        dayNtlVlm: 1e6,
        category: category,
        dex: hip3 ? 'xyz' : '',
        isHip3: hip3);

PolymarketPosition _poly(String id, String question, String outcome,
        {double size = 2,
        double avg = 0.53,
        double now = 0.49,
        bool resolved = false,
        bool won = false,
        String? slug}) =>
    PolymarketPosition(
        marketId: id,
        marketQuestion: question,
        outcome: outcome,
        size: size,
        avgPrice: avg,
        currentPrice: now,
        pnl: 0,
        pnlPercent: 0,
        isResolved: resolved,
        won: won,
        tokenId: '$id-token',
        eventSlug: slug);

final _open = [
  _poly('sun', 'Will Sunderland AFC win on 2026-11-08?', 'Yes', slug: 'sun-che'),
  _poly('btc', 'Bitcoin Up or Down', 'Down', avg: 0.45, now: 0.49),
  _poly(
      'dem',
      'Democratic Presidential Nominee 2028: will Gavin Newsom be the nominee '
          'at the convention in Chicago?',
      'No',
      size: 21,
      avg: 0.512,
      now: 0.5131),
  _poly(
      'fed',
      'Will the Federal Reserve cut interest rates by more than fifty basis '
          'points at the December 2026 meeting?',
      'Yes',
      size: 12,
      avg: 0.2,
      now: 0.31),
];

/// The window of the founder's screenshot, far enough ahead to be open.
final String _windowSlug =
    'btc-updown-5m-${DateTime(2030, 1, 7, 16, 40).millisecondsSinceEpoch ~/ 1000}';

/// The founder's lone card: "BTC up or down · 16:40–16:45", Down.
PolymarketPosition _window({double now = 0.26}) => _poly(
    'win', 'Bitcoin Up or Down', 'Down',
    size: 12, avg: 0.21, now: now, slug: _windowSlug);

final PolymarketEvent _sunderland = PolymarketEvent(
  id: 'sun-che',
  slug: 'sun-che',
  title: 'Sunderland AFC vs. Chelsea FC',
  volume: 1e6,
  liquidity: 1e5,
  category: 'sports',
  conditionId: 'sun',
  outcomes: const [
    PolymarketOutcome(
        name: 'Sunderland AFC',
        price: 0.4,
        conditionId: 'sun',
        tokenId: 'sun-token',
        noTokenId: 'sun-no'),
    PolymarketOutcome(
        name: 'Chelsea FC',
        price: 0.4,
        conditionId: 'che',
        tokenId: 'che-yes',
        noTokenId: 'che-no'),
  ],
);

final _settled = [
  _poly('f1', 'Who will finish higher: Verstappen or Hadjar?', 'Verstappen',
      size: 6, avg: 0.55, now: 1, resolved: true, won: true),
  _poly('rm', 'Will Real Madrid CF win on 2026-10-25?', 'No',
      size: 10, avg: 0.4, now: 0, resolved: true),
];

final _placing = PlacingBet(
  placementId: 'p1',
  tokenId: 'new-token',
  marketQuestion: 'Will it rain tomorrow?',
  outcomeName: 'Yes',
  amount: 5,
  shares: 10,
  avgPrice: 0.5,
  status: PlacingBetStatus.placing,
  startedAt: DateTime(2026, 11, 8),
);

const _state = OneBalanceState(
  investedUsd: 2950,
  investedByVenue: {
    OneBalanceVenue.investing: 2900,
    OneBalanceVenue.predictions: 50,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {OneBalanceVenue.investing: 17.21},
);

List<Override> _held({
  List<HlPerpPosition> perps = const [_btc, _nvda, _gold],
  bool placing = true,
  bool combos = true,
}) =>
    [
      ...portfolioOverrides(
          trading:
              HyperliquidTradingState(isInitialized: true, positions: perps),
          placing: [if (placing) _placing]),
      if (combos) polymarketCombosProvider.overrideWith(_Combos.new),
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      hyperliquidLiveMidProvider('xyz:NVDA').overrideWith((_) => null),
      hyperliquidLiveMidProvider('GOLD').overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [
            _perp('BTC', 'BTC', 93500),
            _perp('NVDA', 'xyz:NVDA', 186.1, category: 'stocks', hip3: true),
            _perp('GOLD', 'GOLD', 2400, category: 'commodities'),
          ]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      polymarketActivePositionsProvider.overrideWith((_) => _open),
      polymarketClaimablePositionsProvider.overrideWith((_) => _settled),
      livePriceProvider.overrideWith(_Prices.new),
      polyPositionEventProvider('sun-che').overrideWith((_) => _sunderland),
      polyPositionEventProvider(_windowSlug).overrideWith((_) => null),
    ];

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required double width,
  required double phoneHeight,
  bool dark = false,
  String locale = 'en',
  bool hidden = false,
  bool expand = false,
  double textScale = 1,
  bool use24h = false,
  double pageHeight = 1500,
  List<Override>? held,
  OneBalanceState state = _state,
}) async {
  // The soft shadow as the app paints it, not the test's solid one.
  debugDisableShadows = false;
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = Size(width, pageHeight) * _dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: locale,
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          balancePrivacy: hidden ? 1 : 0))),
      oneBalanceProvider.overrideWith((ref) => state),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      ...(held ?? _held()),
    ],
    child: ScreenUtilInit(
      // A phone's own scale on a page tall enough to hold everything.
      designSize: Size(430, 932 * pageHeight / phoneHeight),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(locale),
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(
                    textScaler: TextScaler.linear(textScale),
                    alwaysUse24HourFormat: use24h),
            child: child!),
        home: RepaintBoundary(
          key: _key,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.colors.background,
              body: DecoratedBox(
                decoration: AppDecorations.screenGradient(context),
                child: Material(
                    color: Colors.transparent,
                    child: ProviderScope(
                      overrides: [
                        portfolioSectionProvider
                            .overrideWith((_) => PortfolioSection.balances)
                      ],
                      child: InvestmentsPortfolio(onSection: (_) {}),
                    )),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (expand) {
    await tester.tap(
        find.byKey(const ValueKey('portfolio-balance-predictions-see-all')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await tester.pump(const Duration(seconds: 1));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: _dpr)))!;
  await _png(tester, image, name);
  expect(tester.takeException(), isNull, reason: name);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  debugDisableShadows = true;
}

Future<void> _png(WidgetTester tester, ui.Image image, String name) =>
    tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

void main() {
  if (_out.isEmpty) {
    test('positions pill squares render', () {},
        skip: 'on demand: --dart-define=POSITIONS_SQUARES_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  for (final (width, phone) in [(375.0, 812.0), (320.0, 693.0)]) {
    final w = width.round();
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('$w $mode', (tester) async {
        await _shoot(tester, 'both_${w}_$mode',
            width: width, phoneHeight: phone, dark: dark);
        await _shoot(tester, 'expanded_${w}_$mode',
            width: width, phoneHeight: phone, dark: dark, expand: true);
        await _shoot(tester, 'hidden_${w}_$mode',
            width: width,
            phoneHeight: phone,
            dark: dark,
            hidden: true,
            expand: true);
      });
    }
    testWidgets('$w German', (tester) async {
      await _shoot(tester, 'german_${w}_light',
          width: width, phoneHeight: phone, locale: 'de', expand: true);
    });
    testWidgets('$w 150% text', (tester) async {
      await _shoot(tester, 'text150_${w}_light',
          width: width,
          phoneHeight: phone,
          textScale: 1.5,
          expand: true,
          pageHeight: 2200);
    });
  }

  testWidgets('even, a lone position, nothing open at a venue',
      (tester) async {
    await _shoot(tester, 'even_375_light',
        width: 375,
        phoneHeight: 812,
        held: _held(perps: const [_btc, _nvda], placing: false, combos: false));
    await _shoot(tester, 'lone_investing_375_light',
        width: 375,
        phoneHeight: 812,
        held: [
          ..._held(perps: const [_gold], placing: false, combos: false),
          polymarketActivePositionsProvider.overrideWith((_) => const []),
          polymarketClaimablePositionsProvider.overrideWith((_) => const []),
        ],
        state: const OneBalanceState(
          investedUsd: 1200,
          investedByVenue: {OneBalanceVenue.investing: 1200},
          investingKnown: true,
          predictionsKnown: true,
        ));
    await _shoot(tester, 'settled_only_375_light',
        width: 375,
        phoneHeight: 812,
        held: [
          ..._held(perps: const [], placing: false, combos: false),
          polymarketActivePositionsProvider.overrideWith((_) => const []),
        ],
        state: const OneBalanceState(
          investedUsd: 6,
          investedByVenue: {OneBalanceVenue.predictions: 6},
          investingKnown: true,
          predictionsKnown: true,
        ));
  });

  // The chance bar: the lone full-width card, two squares with the window's
  // name and a long title, each with a settled one behind "See all".
  for (final (width, phone) in [(375.0, 812.0), (320.0, 693.0)]) {
    final w = width.round();
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('chance bar $w $mode', (tester) async {
        List<Override> only(List<PolymarketPosition> open) => [
              ..._held(perps: const [], placing: false, combos: false),
              polymarketActivePositionsProvider.overrideWith((_) => open),
            ];
        const state = OneBalanceState(
          investedUsd: 50,
          investedByVenue: {OneBalanceVenue.predictions: 50},
          investingKnown: true,
          predictionsKnown: true,
        );
        await _shoot(tester, 'bar_lone_${w}_$mode',
            width: width,
            phoneHeight: phone,
            dark: dark,
            state: state,
            held: only([_window()]));
        // The screenshot's own "16:40–16:45", its widest clock.
        await _shoot(tester, 'bar_lone_24h_${w}_$mode',
            width: width,
            phoneHeight: phone,
            dark: dark,
            use24h: true,
            state: state,
            held: only([_window()]));
        await _shoot(tester, 'bar_squares_${w}_$mode',
            width: width,
            phoneHeight: phone,
            dark: dark,
            state: state,
            expand: true,
            held: only([_window(), _open[2], _open[3]]));
        await _shoot(tester, 'bar_squares_24h_${w}_$mode',
            width: width,
            phoneHeight: phone,
            dark: dark,
            use24h: true,
            state: state,
            held: only([_window(), _open[2]]));
        await _shoot(tester, 'bar_hidden_${w}_$mode',
            width: width,
            phoneHeight: phone,
            dark: dark,
            hidden: true,
            state: state,
            held: only([_window(), _open[3], _open[0]]));
      });
    }
  }

  testWidgets('first load', (tester) async {
    await _shoot(tester, 'first_load_375_light',
        width: 375,
        phoneHeight: 812,
        held: [
          ..._held(),
          hyperliquidDisplayTradingProvider.overrideWith(
              (_) => const AsyncLoading<HyperliquidTradingState>()),
        ],
        state: const OneBalanceState(
            venueCash: {OneBalanceVenue.investing: 17.21}));
  });
}
