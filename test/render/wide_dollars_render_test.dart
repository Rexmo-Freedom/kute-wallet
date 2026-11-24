// On demand: the Dollars page at the four sizes of the wide layouts
// (kute_layout.dart): 1440x900 and 1180x820 (EXPANDED, two panes),
// 820x1180 (MEDIUM, one centred column) and 430x932 (a phone, as before),
// light and dark, on each pill (Overview, Investing, Predictions), with
// open positions, Investing's markets and a Predictions list.
//
//   flutter test test/render/wide_dollars_render_test.dart \
//     --dart-define=WIDE_DOLLARS_RENDER_OUT=<dir>
//
// Without the define the file does nothing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/open_pnl_history_provider.dart'
    show OpenPnlSources;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart'
    show HlIconAvailability;
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../screens/hyperliquid/hl_market_map_fixture.dart';
import '../screens/usd/investments_harness.dart';

const _out = String.fromEnvironment('WIDE_DOLLARS_RENDER_OUT');
final _shotKey = GlobalKey();

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

PolymarketEvent _event(String id, String title, double yes,
        {String category = 'politics'}) =>
    PolymarketEvent(
      id: id,
      slug: id,
      title: title,
      volume: 1000000,
      liquidity: 500000,
      category: category,
      conditionId: 'c-$id',
      outcomes: [
        PolymarketOutcome(name: 'Yes', price: yes),
        PolymarketOutcome(name: 'No', price: 1 - yes),
      ],
    );

PolymarketEvent _multi(String id, String title, List<(String, double)> o) =>
    PolymarketEvent(
      id: id,
      slug: id,
      title: title,
      volume: 3000000,
      liquidity: 900000,
      category: 'politics',
      conditionId: 'c-$id',
      outcomes: [
        for (final (name, p) in o)
          PolymarketOutcome(
              name: name, price: p, tokenId: 't-$id-$name', gammaMarketId: id),
      ],
    );

final _events = [
  _event('fed', 'Will the Fed cut rates in December?', 0.62),
  _event('apple', 'Will Apple be the largest company in 2026?', 0.38),
  _event('btc', 'Will Bitcoin reach \$150k this year?', 0.21),
  _event('gpt', 'Will OpenAI release GPT-6 before July?', 0.44),
  _event('rain', 'Will it rain in Lisbon on Christmas Day?', 0.31),
  _multi('nyc', 'New York City mayoral election winner', [
    ('Zohran Mamdani', 0.71),
    ('Andrew Cuomo', 0.18),
    ('Curtis Sliwa', 0.06),
  ]),
  _event('eth', 'Will Ethereum flip \$5,000 in December?', 0.17),
  _event('tesla', 'Will Tesla deliver 500k cars this quarter?', 0.55),
  _event('gold', 'Will gold close the year above \$4,500?', 0.48),
  _event('spacex', 'Will SpaceX land Starship on Mars by 2027?', 0.04),
  _multi('ucl', 'Champions League winner', [
    ('Real Madrid', 0.24),
    ('Manchester City', 0.19),
    ('Arsenal', 0.15),
    ('Bayern Munich', 0.12),
  ]),
  _event('recession', 'US recession in 2026?', 0.27),
  _event('ai', 'Will an AI win a gold medal at the IMO?', 0.66),
  _event('oil', 'Will oil trade below \$60 in January?', 0.35),
  _event('nvda', 'Will Nvidia close the year as the largest company?', 0.58),
  _event('tiktok', 'Will TikTok be banned in the US this year?', 0.09),
];

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(events: _events, done: true);
}

HlPerpPosition _perp(String coin, double pnl) => HlPerpPosition(
    coin: coin,
    szi: 1,
    entryPx: 100,
    positionValue: 100 + pnl,
    unrealizedPnl: pnl,
    returnOnEquity: pnl / 50,
    liquidationPx: null,
    marginUsed: 50,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

HlFill _opened(String coin, DateTime now) => HlFill(
      coin: coin,
      px: 100,
      sz: 1,
      side: 'B',
      time: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: coin.hashCode,
      hash: '0xopen-$coin',
      dir: 'Open Long',
      cloid: null,
      startPosition: 0,
    );

Future<void> _render(WidgetTester tester, String name,
    {required Size size,
    required String pill,
    bool dark = false,
    bool positions = true}) async {
  final now = DateTime.now();
  const coins = ['BTC', 'ETH', 'SOL', 'HYPE'];
  final theme = dark ? buildDarkTheme() : buildLightTheme();
  await pumpInvestments(tester,
      browseInvesting: true,
      browsePredictions: true,
      dark: dark,
      size: size,
      designSize: KuteLayout.designSizeFor(size),
      child: RepaintBoundary(
        key: _shotKey,
        child: Theme(
          data: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
          child: const Scaffold(body: UsdAccountScreen()),
        ),
      ),
      openPnlSources: OpenPnlSources(
        activity: (_) async => const [],
        candles: (_, wire, interval, window) async => [
          for (var t = now.subtract(window);
              t.isBefore(now);
              t = t.add(const Duration(hours: 4)))
            HyperliquidCandle(
                openTime: t,
                closeTime: t.add(const Duration(hours: 4)),
                open: 103,
                high: 103,
                low: 103,
                close: 103,
                volume: 1),
        ],
        polyHistory: (_, __, ___) async => null,
      ),
      overrides: [
        hyperliquidBrowseUniverseProvider
            .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
        hyperliquidPerpMarketsProvider
            .overrideWith((_) async => hlMarketMapFixture),
        hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidSparklineStoreProvider.overrideWithValue(
            HlSparklineStore(fetch: (_) async => const [100, 101, 99, 102])),
        polyBrowseFeedProvider.overrideWith(_Feed.new),
        sportsLiveProvider.overrideWith(_Sports.new),
        if (positions)
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
                  HyperliquidTradingState(isInitialized: true, positions: [
                for (final (i, c) in coins.indexed)
                  _perp(c, i.isEven ? 3 : -1.5),
              ], recentFills: [
                for (final c in coins) _opened(c, now)
              ]))),
      ]);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (pill != 'Overview') {
    await tapPill(tester, pill);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    final text = '$e'.split('\n').first;
    if (!text.contains('MissingPlugin') && !text.contains('HTTP')) {
      // ignore: avoid_print
      print('RENDER problem ($name): $text');
    }
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $_out/$name.png');
  await unmountInvestments(tester);
}

void main() {
  if (_out.isEmpty) {
    test('Wide Dollars render', () {},
        skip: 'on demand: --dart-define=WIDE_DOLLARS_RENDER_OUT=<dir>');
    return;
  }

  // Every logo known, so the squares draw (no logo is fetched here).
  setUp(() => HlIconAvailability.debugEveryLogoKnown = true);
  tearDown(() => HlIconAvailability.debugEveryLogoKnown = false);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  const sizes = {
    '1440x900': Size(1440, 900),
    '1180x820': Size(1180, 820),
    '820x1180': Size(820, 1180),
    '430x932': Size(430, 932),
  };
  final only = const String.fromEnvironment('WIDE_DOLLARS_ONLY');
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final MapEntry(key: tag, value: size) in sizes.entries) {
      for (final pill in ['Overview', 'Investing', 'Predictions']) {
        final name = '${tag}_${pill.toLowerCase()}_$mode';
        if (only.isNotEmpty && !name.contains(only)) continue;
        testWidgets(
            name,
            (tester) =>
                _render(tester, name, size: size, pill: pill, dark: dark));
      }
      final empty = '${tag}_overview_empty_$mode';
      if (only.isEmpty || empty.contains(only)) {
        testWidgets(
            empty,
            (tester) => _render(tester, empty,
                size: size, pill: 'Overview', dark: dark, positions: false));
      }
    }
  }
}
