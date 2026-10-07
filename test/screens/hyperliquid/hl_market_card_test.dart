import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/theme/app_theme.dart';

class _LivePrices extends HlLivePricesNotifier {
  _LivePrices(this.mids);
  final Map<String, double> mids;
  @override
  HlLivePriceState build() => HlLivePriceState(mids: mids);
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}

  /// A tick: the previous mids are kept, as the real notifier keeps them.
  void publish(Map<String, double> next) =>
      state = HlLivePriceState(mids: next, previousMids: state.mids);
}

HlMarket _market({
  String coin = 'BTC',
  String? wireCoin,
  HlMarketKind kind = HlMarketKind.perp,
  int maxLeverage = 40,
  double px = 85806,
  double prevDayPx = 83959,
  double dayNtlVlm = 1000000,
  String? unitAssetName,
  String category = 'crypto',
  bool isHip3 = false,
  String dex = '',
}) =>
    HlMarket(
      coin: coin,
      wireCoin: wireCoin ?? coin,
      assetId: 0,
      kind: kind,
      szDecimals: 2,
      maxLeverage: maxLeverage,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prevDayPx,
      dayNtlVlm: dayNtlVlm,
      unitAssetName: unitAssetName,
      category: category,
      isHip3: isHip3,
      dex: dex,
    );

/// Wire coins the card's sparkline store asked the venue for.
final _fetched = <String>[];

Future<void> _pump(
  WidgetTester tester,
  HlMarket market, {
  Map<String, double> mids = const {},
  List<double> closes = const [],
  VoidCallback? onTap,
  double width = 390,
  // The test font's glyphs are a full em wide, about twice the app's
  // font: 0.5 gives text the widths it has on a phone.
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _fetched.clear();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(() => _LivePrices(mids)),
      // The card's series comes from the sparkline store; its fetch
      // answers [closes] and counts what it was asked.
      hyperliquidSparklineStoreProvider.overrideWithValue(HlSparklineStore(
        fetch: (wire) async {
          _fetched.add(wire);
          return closes;
        },
      )),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [HlMarketCard(market: market, onTap: onTap)],
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

/// The price and the change are drawn digit by digit, so they are read
/// off the two [RollingNumberText]s: price first, change under it.
List<RollingNumberText> _numbers(WidgetTester tester) =>
    tester.widgetList<RollingNumberText>(find.byType(RollingNumberText)).toList();

void main() {
  testWidgets('a perp shows its name, ticker and leverage, price and change',
      (tester) async {
    final m = _market();
    await _pump(tester, m, closes: [80000, 82000, 85000]);

    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('BTC · 40x'), findsOneWidget);
    final numbers = _numbers(tester);
    expect(numbers, hasLength(2));
    expect(numbers[0].text, formatHlPrice(85806, decimalCap: m.pxDecimalCap));
    expect(numbers[1].text, '+2.2%');
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    // The price is never red or green; the change is.
    expect(numbers[0].style.color, colors.textPrimary);
    expect(numbers[1].style.color, AppColors.marketUp);
    // Nothing the old card carried: no kind badge, no volume line.
    expect(find.byType(HlKindBadge), findsNothing);
    expect(find.textContaining('volume'), findsNothing);
    // One row, not the old tall card.
    final height = tester.getSize(find.byType(HlMarketCard)).height;
    expect(height, inInclusiveRange(64, 80));
  });

  testWidgets('a falling market colours the change and the line, not the price',
      (tester) async {
    await _pump(tester, _market(px: 82824, prevDayPx: 84000),
        closes: [86000, 85000, 83000]);

    final numbers = _numbers(tester);
    expect(numbers[1].text, '−1.4%');
    expect(numbers[1].style.color, AppColors.marketDown);
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    expect(numbers[0].style.color, colors.textPrimary);
    final line = tester.widget<HlLineSparkline>(find.byType(HlLineSparkline));
    expect(line.upColor, AppColors.marketDown);
    expect(line.downColor, AppColors.marketDown);
  });

  testWidgets('the price stays the primary colour when a tick moves it',
      (tester) async {
    await _pump(tester, _market(), mids: {'BTC': 85806});
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HlMarketCard)));
    (container.read(hyperliquidLivePricesProvider.notifier) as _LivePrices)
        .publish({'BTC': 85000});
    await tester.pump();

    final numbers = _numbers(tester);
    final m = _market();
    expect(numbers[0].text, formatHlPrice(85000, decimalCap: m.pxDecimalCap));
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    expect(numbers[0].style.color, colors.textPrimary);
    await tester.pumpAndSettle();
  });

  testWidgets('a market with no known name is titled by its ticker',
      (tester) async {
    await _pump(
        tester,
        _market(
            coin: 'WHEAT',
            wireCoin: 'unit:WHEAT',
            maxLeverage: 10,
            category: 'commodities',
            isHip3: true,
            dex: 'unit',
            px: 5.42,
            prevDayPx: 5.42));

    // The ticker is the title, so the caption does not say it again.
    expect(find.text('WHEAT'), findsOneWidget);
    expect(find.text('10x'), findsOneWidget);
  });

  testWidgets('a builder-dex perp is named by its bare symbol',
      (tester) async {
    await _pump(
        tester,
        _market(
            coin: 'GOLD',
            wireCoin: 'xyz:GOLD',
            maxLeverage: 20,
            category: 'commodities',
            isHip3: true,
            dex: 'xyz',
            px: 3350,
            prevDayPx: 3300));

    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('GOLD · 20x'), findsOneWidget);
  });

  testWidgets('a spot token says Spot in the caption', (tester) async {
    await _pump(
        tester,
        _market(
            coin: 'TSLA',
            wireCoin: '@271',
            kind: HlMarketKind.spot,
            category: 'stocks',
            px: 250,
            prevDayPx: 245));

    expect(find.text('Tesla'), findsOneWidget);
    expect(find.text('TSLA · Spot'), findsOneWidget);
  });

  testWidgets('a Unit token is named after the asset it holds',
      (tester) async {
    await _pump(
        tester,
        _market(
            coin: 'UBTC',
            wireCoin: '@142',
            kind: HlMarketKind.spot,
            unitAssetName: 'Bitcoin'));

    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('UBTC · Spot'), findsOneWidget);
  });

  test('low liquidity is under \$50k traded in 24 hours', () {
    expect(_market(dayNtlVlm: 0).isLowLiquidity, isTrue);
    expect(_market(dayNtlVlm: 49999).isLowLiquidity, isTrue);
    expect(_market(dayNtlVlm: 50000).isLowLiquidity, isFalse);
    expect(_market(dayNtlVlm: 730000000).isLowLiquidity, isFalse);
  });

  HlMarket thinSpot(String coin, {double px = 100, double prevDayPx = 0}) =>
      _market(
          coin: coin,
          wireCoin: '@266',
          kind: HlMarketKind.spot,
          category: 'stocks',
          px: px,
          prevDayPx: prevDayPx,
          dayNtlVlm: 0);

  testWidgets('a thin market says so in its caption, whole, on one line',
      (tester) async {
    await _pump(tester, thinSpot('TSLA', px: 820.5), textScale: 0.5);

    expect(find.text('Tesla'), findsOneWidget);
    expect(find.text('TSLA · Spot · Low liquidity'), findsOneWidget);
    // Words in the caption line, not a badge box.
    expect(find.byType(HlMetaChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a thin market draws no sparkline and asks for no candles',
      (tester) async {
    await _pump(tester, thinSpot('GOOGL', px: 335.61),
        closes: [300, 300, 300, 335]);
    expect(find.byType(HlLineSparkline), findsNothing);
    expect(_fetched, isEmpty);
    // A traded market keeps its line, from one request.
    await _pump(tester, _market(), closes: [80000, 82000, 85000]);
    expect(find.byType(HlLineSparkline), findsOneWidget);
    expect(_fetched, ['BTC']);
    expect(find.textContaining('Low liquidity'), findsNothing);
  });

  testWidgets('a thin market with no 24h change shows the price alone',
      (tester) async {
    await _pump(tester, thinSpot('TSLA', px: 820.5));
    // The price only: no dash under it.
    final numbers = _numbers(tester);
    expect(numbers, hasLength(1));
    expect(numbers.single.text, isNot('—'));

    // A thin market that did trade keeps its change.
    await _pump(
        tester,
        _market(
            coin: 'MU',
            wireCoin: '@300',
            kind: HlMarketKind.spot,
            px: 1044.4,
            prevDayPx: 1097,
            dayNtlVlm: 1200));
    expect(_numbers(tester), hasLength(2));
    expect(_numbers(tester)[1].text, '−4.8%');
  });

  testWidgets('a market titled by its ticker does not repeat it', (tester) async {
    // MU has no name of its own: the title is the ticker, the caption is
    // what the market is.
    await _pump(
        tester,
        _market(
            coin: 'MU',
            wireCoin: '@300',
            kind: HlMarketKind.spot,
            px: 1044.4,
            prevDayPx: 1097,
            dayNtlVlm: 1200),
        textScale: 0.5);
    expect(find.text('MU'), findsOneWidget);
    expect(find.text('Spot · Low liquidity'), findsOneWidget);

    await _pump(
        tester,
        _market(
            coin: 'WHEAT',
            wireCoin: 'unit:WHEAT',
            maxLeverage: 10,
            isHip3: true,
            dex: 'unit'));
    expect(find.text('WHEAT'), findsOneWidget);
    expect(find.text('10x'), findsOneWidget);
  });

  for (final c in [
    (coin: 'MU', name: 'MU', caption: 'Spot'),
    (coin: 'CRCL', name: 'Circle', caption: 'CRCL · Spot'),
    (coin: 'TSLA', name: 'Tesla', caption: 'TSLA · Spot'),
  ]) {
    testWidgets(
        '${c.coin} thin at 375pt: nothing overflows and no ellipsis falls '
        'inside the caption', (tester) async {
      // With the widths text has on a phone: the whole caption, one line.
      await _pump(tester, thinSpot(c.coin, px: 820.5),
          width: 375, textScale: 0.5);
      expect(tester.takeException(), isNull);
      expect(find.text(c.name), findsOneWidget);
      expect(find.text('${c.caption} · Low liquidity'), findsOneWidget);

      // With text twice as wide (the largest accessibility sizes): the
      // note moves to a caption line of its own, under the first, and
      // nothing is cut in the middle.
      await _pump(tester, thinSpot(c.coin, px: 820.5), width: 375);
      expect(tester.takeException(), isNull);
      expect(find.text(c.caption), findsOneWidget);
      expect(find.text('Low liquidity'), findsOneWidget);
      final top = tester.getTopLeft(find.text(c.caption));
      final note = tester.getTopLeft(find.text('Low liquidity'));
      expect(note.dy, greaterThan(top.dy));
      expect(note.dx, top.dx);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data, isNot(contains('…')));
      }
    });
  }

  testWidgets('a normal perp at 375pt keeps its line and one-line caption',
      (tester) async {
    await _pump(tester, _market(coin: 'TSLA', wireCoin: 'xyz:TSLA', maxLeverage: 10, category: 'stocks', isHip3: true, dex: 'xyz', px: 430, prevDayPx: 425),
        closes: [420, 425, 430], width: 375);
    expect(tester.takeException(), isNull);
    expect(find.text('Tesla'), findsOneWidget);
    expect(find.text('TSLA · 10x'), findsOneWidget);
    expect(find.byType(HlLineSparkline), findsOneWidget);
    expect(_numbers(tester), hasLength(2));
  });

  testWidgets('an unknown change is a dash in the neutral colour',
      (tester) async {
    await _pump(tester, _market(prevDayPx: 0), closes: [80000, 82000]);

    final numbers = _numbers(tester);
    expect(numbers[1].text, '—');
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    expect(numbers[1].style.color, colors.textSecondary);
    final line = tester.widget<HlLineSparkline>(find.byType(HlLineSparkline));
    expect(line.upColor, colors.textSecondary);
  });

  testWidgets('without candles the sparkline space is empty, not a shimmer',
      (tester) async {
    await _pump(tester, _market());

    final line = tester.widget<HlLineSparkline>(find.byType(HlLineSparkline));
    expect(line.closes, isEmpty);
    expect(
        find.descendant(
            of: find.byType(HlLineSparkline),
            matching: find.byType(CustomPaint)),
        findsNothing);
    // The space is kept, so the prices still line up down the list.
    expect(tester.getSize(find.byType(HlLineSparkline)).width, greaterThan(50));
  });

  testWidgets('a long name ellipsizes and nothing overflows on a narrow phone',
      (tester) async {
    await _pump(
        tester,
        _market(
            coin: 'AVERYLONGTICKERNAMEFORAMARKET',
            px: 123456.78,
            prevDayPx: 120000),
        closes: [1, 2, 3],
        width: 320);

    expect(tester.takeException(), isNull);
    expect(find.byType(HlCoinIcon), findsOneWidget);
  });

  testWidgets('the whole card taps through', (tester) async {
    var taps = 0;
    await _pump(tester, _market(), onTap: () => taps++);
    await tester.tap(find.text('Bitcoin'));
    expect(taps, 1);
  });
}
