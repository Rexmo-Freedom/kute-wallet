// On demand: the Dollars Overview on a laptop (the Open profits hero
// beside the "Open positions" column of desk cards, dollars_activity_tab
// .dart) with none, one, two and four open positions (an Investing long,
// an Investing short, a Predictions position), at 1000x700, 1100x760,
// 1440x900, 1920x1080 and 2400x1200, the phone (430x932) and MEDIUM
// (820x1180) as they were, and Investing / Predictions with the same
// column, light and dark.
//
//   flutter test test/render/desk_overview_render_test.dart \
//     --dart-define=DESK_OVERVIEW_RENDER_OUT=<dir> \
//     [--dart-define=DESK_OVERVIEW_ONLY=<regex>]
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
import 'package:kute/providers/polymarket_card_spark_provider.dart'
    show polyCardSparkStoreProvider;
import 'package:kute/services/polymarket/poly_card_spark_store.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart'
    show HlIconAvailability;
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../screens/hyperliquid/hl_market_map_fixture.dart';
import '../screens/usd/investments_harness.dart';

const _out = String.fromEnvironment('DESK_OVERVIEW_RENDER_OUT');
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


HlPerpPosition _perp(String coin, double szi, double pnl) => HlPerpPosition(
    coin: coin,
    szi: szi,
    entryPx: 100,
    positionValue: 100 + pnl,
    unrealizedPnl: pnl,
    returnOnEquity: pnl / 50,
    liquidationPx: null,
    marginUsed: 50,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

HlFill _opened(HlPerpPosition p, DateTime now) => HlFill(
      coin: p.coin,
      px: 100,
      sz: p.szi.abs(),
      side: p.szi > 0 ? 'B' : 'A',
      time: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: p.coin.hashCode,
      hash: '0xopen-${p.coin}',
      dir: p.szi > 0 ? 'Open Long' : 'Open Short',
      cloid: null,
      startPosition: 0,
    );

/// A wandering series ending on [end].
List<double> _walk(double end, int seed, {int n = 60, double step = 0.02}) {
  var x = seed;
  final out = <double>[];
  var v = end;
  for (var i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    v = v * (1 + ((x % 1000) / 1000 - 0.5) * step);
    out.add(v);
  }
  return out.reversed.toList();
}

const _poly = PolymarketPosition(
  marketId: 'c-fed',
  marketQuestion: 'Will the Fed cut rates in December?',
  outcome: 'Yes',
  size: 20,
  avgPrice: 0.48,
  currentPrice: 0.62,
  pnl: 2.8,
  pnlPercent: 29,
  isResolved: false,
  tokenId: 'fed-yes',
  eventSlug: 'fed',
);

/// The open book of [count]: none; an Investing short; a long and a
/// short; a long, a short, a prediction and a long.
({List<HlPerpPosition> perps, List<PolymarketPosition> polys}) _book(
        int count) =>
    switch (count) {
      0 => (perps: const [], polys: const []),
      1 => (perps: [_perp('BTC', -0.065, 0.66)], polys: const []),
      2 => (
          perps: [_perp('ETH', 0.4, 3.1), _perp('BTC', -0.065, -1.2)],
          polys: const []
        ),
      _ => (
          perps: [
            _perp('ETH', 0.4, 3.1),
            _perp('BTC', -0.065, -1.2),
            _perp('SOL', 2, 0.9),
          ],
          polys: const [_poly]
        ),
    };

Future<void> _render(WidgetTester tester, String name,
    {required Size size,
    required String section,
    bool dark = false,
    int positions = 1}) async {
  final now = DateTime.now();
  final book = _book(positions);
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
          child: const Scaffold(
            body: Stack(children: [
              Positioned.fill(child: UsdAccountScreen()),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: KuteTopNavBar(activeTab: ActiveNavTab.usd),
              ),
            ]),
          ),
        ),
      ),
      openPnlSources: OpenPnlSources(
        activity: (_) async => const [],
        candles: (_, wire, interval, window) async {
          final closes = _walk(103, wire.hashCode, n: 42, step: 0.05);
          final start = now.subtract(window);
          final span = window.inMinutes ~/ closes.length;
          return [
            for (final (i, v) in closes.indexed)
              HyperliquidCandle(
                  openTime: start.add(Duration(minutes: span * i)),
                  closeTime: start.add(Duration(minutes: span * (i + 1))),
                  open: v,
                  high: v,
                  low: v,
                  close: v,
                  volume: 1),
          ];
        },
        polyHistory: (_, __, ___) async => null,
      ),
      overrides: [
        hyperliquidBrowseUniverseProvider
            .overrideWithValue(AsyncValue.data(hlMarketMapFixture)),
        hyperliquidPerpMarketsProvider
            .overrideWith((_) async => hlMarketMapFixture),
        hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
            fetch: (wire) async => _walk(100, wire.hashCode, step: 0.06))),
        polyCardSparkStoreProvider.overrideWith((ref) {
          final store = PolyCardSparkStore(fetch: (token, interval) async {
            final start = now.subtract(const Duration(days: 7));
            return [
              for (final (i, v) in _walk(0.62, token.hashCode, n: 48,
                      step: 0.08)
                  .indexed)
                PolymarketPricePoint(
                    timestamp: start.add(Duration(hours: 3 * i)),
                    price: v.clamp(0.01, 0.99)),
            ];
          });
          ref.onDispose(store.dispose);
          return store;
        }),
        polyBrowseFeedProvider.overrideWith(_Feed.new),
        sportsLiveProvider.overrideWith(_Sports.new),
        if (book.perps.isNotEmpty)
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
              HyperliquidTradingState(
                  isInitialized: true,
                  positions: book.perps,
                  recentFills: [
                    for (final p in book.perps) _opened(p, now)
                  ]))),
        if (book.polys.isNotEmpty)
          polymarketActivePositionsProvider.overrideWithValue(book.polys),
      ]);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (section != 'activity') {
    final navItem = find.byKey(ValueKey('dollars-desk-nav-$section'));
    if (navItem.evaluate().isNotEmpty) {
      await tester.tap(navItem);
    } else {
      await tapPill(
          tester, section == 'investing' ? 'Investing' : 'Predictions');
    }
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
  await tester.pump(const Duration(seconds: 31));
}

void main() {
  if (_out.isEmpty) {
    test('Desk Overview render', () {},
        skip: 'on demand: --dart-define=DESK_OVERVIEW_RENDER_OUT=<dir>');
    return;
  }

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
    '1000x700': Size(1000, 700),
    '1100x760': Size(1100, 760),
    '1440x900': Size(1440, 900),
    '1920x1080': Size(1920, 1080),
    '2400x1200': Size(2400, 1200),
    '910x700': Size(910, 700),
    '820x1180': Size(820, 1180),
    '430x932': Size(430, 932),
  };
  const sections = ['activity', 'investing', 'predictions'];
  const counts = [0, 1, 2, 4];
  final only = const String.fromEnvironment('DESK_OVERVIEW_ONLY');
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final MapEntry(key: tag, value: size) in sizes.entries) {
      for (final section in sections) {
        for (final n in counts) {
          final what = section == 'activity' ? 'overview' : section;
          final name = '${tag}_${what}_${n}_$mode';
          if (only.isNotEmpty && !RegExp(only).hasMatch(name)) continue;
          testWidgets(
              name,
              (tester) => _render(tester, name,
                  size: size, section: section, dark: dark, positions: n));
        }
      }
    }
  }
}
