import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlMarketDirectory;
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
  testWidgets('a perp shows its name, price and change, nothing else',
      (tester) async {
    final m = _market();
    await _pump(tester, m, closes: [80000, 82000, 85000]);

    expect(find.text('Bitcoin'), findsOneWidget);
    // One name line: no ticker sub line, never the max leverage
    // (leverage is blocked).
    expect(find.text('BTC'), findsNothing);
    expect(find.textContaining('40x'), findsNothing);
    final numbers = _numbers(tester);
    expect(numbers, hasLength(2));
    expect(numbers[0].text, formatHlListPrice(85806, decimalCap: m.pxDecimalCap));
    expect(numbers[0].text, r'$85,806.00');
    // The change reads direction as a glyph, never a sign.
    expect(numbers[1].text, '▲ 2.2%');
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    // The price is never red or green; the change is.
    expect(numbers[0].style.color, colors.textPrimary);
    expect(numbers[1].style.color, AppColors.marketUp);
    // Nothing else: no sparkline (and no candles asked for), no kind
    // badge, no volume line.
    expect(find.byType(HlLineSparkline), findsNothing);
    expect(_fetched, isEmpty);
    expect(find.byType(HlKindBadge), findsNothing);
    expect(find.textContaining('volume'), findsNothing);
    // One 56 px row.
    final height = tester.getSize(find.byType(HlMarketCard)).height;
    expect(height, moreOrLessEquals(kHlMarketRowHeight.w, epsilon: 1));
  });

  testWidgets('a falling market colours the change, not the price',
      (tester) async {
    await _pump(tester, _market(px: 82824, prevDayPx: 84000));

    final numbers = _numbers(tester);
    expect(numbers[1].text, '▼ 1.4%');
    expect(numbers[1].style.color, AppColors.marketDown);
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    expect(numbers[0].style.color, colors.textPrimary);
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
    expect(numbers[0].text, formatHlListPrice(85000, decimalCap: m.pxDecimalCap));
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

    // The name sits centred in the row.
    expect(find.text('WHEAT'), findsOneWidget);
    expect(find.textContaining('10x'), findsNothing);
    final row = tester.getCenter(find.byType(HlMarketCard)).dy;
    expect(tester.getCenter(find.text('WHEAT')).dy, closeTo(row, 1));
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
    expect(find.text('GOLD'), findsNothing);
    expect(find.textContaining('20x'), findsNothing);
  });

  testWidgets('two venues listing one symbol: the logo carries the venue',
      (tester) async {
    final a = _market(
        coin: 'ANTH',
        wireCoin: 'vntl:ANTH',
        category: 'preipo',
        isHip3: true,
        dex: 'vntl',
        px: 1805,
        prevDayPx: 1780);
    final b = _market(
        coin: 'ANTH',
        wireCoin: 'km:ANTH',
        category: 'preipo',
        isHip3: true,
        dex: 'km',
        px: 1805,
        prevDayPx: 1809);
    HlDexNames.remember('vntl', 'Ventuals');
    HlMarketDirectory.remember([a, b]);
    addTearDown(HlDexNames.debugReset);

    await _pump(tester, a);
    expect(find.text('Anthropic'), findsOneWidget);
    // No caption line; the venue's mark on the logo tells the rows apart.
    expect(find.text('ANTH · Ventuals'), findsNothing);
    expect(find.byKey(const ValueKey('hl-venue-badge')), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    await _pump(tester, b);
    expect(find.byKey(const ValueKey('hl-venue-badge')), findsOneWidget);
    // A symbol only one venue lists carries no mark.
    await _pump(tester, _market(coin: 'OAI', wireCoin: 'vntl:OAI',
        category: 'preipo', isHip3: true, dex: 'vntl', px: 1405,
        prevDayPx: 1380));
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.byKey(const ValueKey('hl-venue-badge')), findsNothing);
  });

  testWidgets('a perp sharing its symbol with a spot token wears its venue',
      (tester) async {
    final perp = _market(coin: 'ANTX', wireCoin: 'ANTX', px: 0.021,
        prevDayPx: 0.02);
    final spot = _market(coin: 'ANTX', wireCoin: '@9001',
        kind: HlMarketKind.spot, px: 0.021, prevDayPx: 0.02);
    HlMarketDirectory.remember([perp, spot]);
    await _pump(tester, perp);
    expect(find.text('H'), findsOneWidget);
    // The spot row carries no venue mark.
    await _pump(tester, spot);
    expect(find.byKey(const ValueKey('hl-venue-badge')), findsNothing);
  });

  testWidgets('a spot token has no "Spot" sub line', (tester) async {
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
    expect(find.textContaining('Spot'), findsNothing);
    expect(find.text('TSLA'), findsNothing);
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
    expect(find.textContaining('UBTC'), findsNothing);
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

  testWidgets('a thin market is the name and the price, no note',
      (tester) async {
    await _pump(tester, thinSpot('TSLA', px: 820.5), width: 375);
    expect(find.text('Tesla'), findsOneWidget);
    expect(find.textContaining('Low liquidity'), findsNothing);
    expect(find.byType(HlMetaChip), findsNothing);
    expect(find.byType(HlLineSparkline), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(_numbers(tester)[1].text, '▼ 4.8%');
  });

  testWidgets('an unknown change is a dash in the neutral colour',
      (tester) async {
    await _pump(tester, _market(prevDayPx: 0));

    final numbers = _numbers(tester);
    expect(numbers[1].text, '—');
    final colors = tester.element(find.byType(HlMarketCard)).colors;
    expect(numbers[1].style.color, colors.textSecondary);
  });

  testWidgets('text twice as wide (the largest sizes): nothing overflows',
      (tester) async {
    // The test font is about twice the app's: scale 1 is the largest
    // accessibility sizes.
    await _pump(tester, _market(), width: 375);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HlMarketCard)).height,
        greaterThanOrEqualTo(kHlMarketRowHeight.w - 0.5));
  });

  testWidgets('a long name ellipsizes and nothing overflows on a narrow phone',
      (tester) async {
    await _pump(
        tester,
        _market(
            coin: 'AVERYLONGTICKERNAMEFORAMARKET',
            px: 123456.78,
            prevDayPx: 120000),
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

  testWidgets(
      'in a group the row has no card of its own and keeps its ink; alone '
      'it is the card', (tester) async {
    await _pump(tester, _market());
    final alone = find.byType(HlMarketCard);
    final card = AppDecorations.card(tester.element(alone));
    bool hasCard() => tester
        .widgetList<Container>(
            find.descendant(of: alone, matching: find.byType(Container)))
        .any((c) => c.decoration == card);
    expect(hasCard(), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hyperliquidLivePricesProvider.overrideWith(() => _LivePrices(const {})),
        hyperliquidSparklineStoreProvider.overrideWithValue(
            HlSparklineStore(fetch: (_) async => const <double>[])),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(children: [
              HlMarketCard(market: _market(), onTap: () {}, inGroup: true),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(hasCard(), isFalse);
    for (final c in tester.widgetList<Container>(
        find.descendant(of: alone, matching: find.byType(Container)))) {
      final d = c.decoration;
      if (d is BoxDecoration) expect(d.boxShadow, isNull);
    }
    final ink = find.descendant(of: alone, matching: find.byType(InkWell));
    expect(tester.getSize(ink), tester.getSize(alone));
    expect(tester.getSize(alone).height, greaterThanOrEqualTo(44));
    // The name starts where the group's hairline does.
    expect(tester.getTopLeft(find.text('Bitcoin')).dx,
        moreOrLessEquals(hlGroupRowIndent(), epsilon: 0.5));
  });
}

