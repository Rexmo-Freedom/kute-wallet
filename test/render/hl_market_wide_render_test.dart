// A look by eye at the Investing market page in the wide layouts
// (kute_layout.dart): EXPANDED's two panes (the market on the left, the
// order ticket open in place on the right), MEDIUM's centred column and
// the phone as before; a perp and a spot token, with and without what is
// held, light and dark. Written only when asked: HL_WIDE_RENDER=<dir>.
//   HL_WIDE_RENDER=<dir> flutter test test/render/hl_market_wide_render_test.dart
//
// Without the variable it still runs one EXPANDED pump and checks the
// ticket is in place, the bar is away, and nothing overflows.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlCandlestickChart;
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart'
    show KuteScrubCard;
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart'
    show KuteChartDrawingsPainter;
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlTrade;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_hyperliquid_move_rail.dart';
import '../helpers/fake_swap_orders.dart';
import '../helpers/hl_chart_edit_harness.dart' show hlEditCandles;
import '../helpers/shell_bar_harness.dart';

final _dir = Platform.environment['HL_WIDE_RENDER'];

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
  openInterest: 25000,
  funding: 0.0000125,
);

const _hype = HlMarket(
  coin: 'HYPE',
  wireCoin: '@107',
  assetId: 10107,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 4.2e7,
);

const _held = HlPerpPosition(
  coin: 'BTC',
  szi: 0.002,
  entryPx: 64000,
  positionValue: 132,
  unrealizedPnl: 4,
  returnOnEquity: 0.03,
  liquidationPx: null,
  marginUsed: 128,
  leverageType: 'isolated',
  leverageValue: 1,
  maxLeverage: 40,
);

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() =>
      const HlLivePriceState(mids: {'BTC': 66000, 'HYPE': 66000});
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

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.state0);
  final HyperliquidTradingState state0;
  @override
  Future<HyperliquidTradingState> build() async => state0;
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 500,
        withdrawable: 500,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      );
}

class _Funded extends FundedOrdersNotifier {
  @override
  List<FundedOrderRecord> build() => const [];
}

HlOrderBookState _book(double mid) {
  final r = math.Random(7);
  return HlOrderBookState(
    isConnected: true,
    bids: [
      for (var i = 0; i < 12; i++)
        HlL2Level(px: mid - 1 - i * 2, sz: 0.2 + r.nextDouble() * 2, n: 3)
    ],
    asks: [
      for (var i = 0; i < 12; i++)
        HlL2Level(px: mid + 1 + i * 2, sz: 0.2 + r.nextDouble() * 2, n: 3)
    ],
    recentTrades: [
      for (var i = 0; i < 10; i++)
        HlTrade(
            coin: 'BTC',
            side: i.isEven ? 'B' : 'A',
            px: mid + (i - 5),
            sz: 0.01 + i * 0.003,
            time: DateTime(2026, 11, 24, 12, 0, 50 - i * 4)
                .millisecondsSinceEpoch,
            hash: 'h$i'),
    ],
  );
}

late FakeHyperliquidMoveRail _rail;

Future<void> _fonts() async {
  for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
    final inter = FontLoader(family);
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  }
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _pump(WidgetTester tester,
    {required Size size,
    required bool dark,
    required HlMarket market,
    bool held = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final positions = held && !market.isSpot ? const [_held] : <HlPerpPosition>[];
  final spot = held && market.isSpot
      ? const [HlSpotBalance(coin: 'HYPE', total: 3.5, hold: 0, entryNtl: 120)]
      : const <HlSpotBalance>[];
  final theme = dark ? buildDarkTheme() : buildLightTheme();
  final tape = hlEditCandles(count: 160);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: false,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      hyperliquidAccountMarketProvider(market.coin)
          .overrideWith((_) => market),
      hyperliquidExactMarketProvider.overrideWith((ref, key) => market),
      hyperliquidSpotMarketsProvider.overrideWith((ref) async => [_hype]),
      hyperliquidActiveAssetCtxProvider
          .overrideWith((ref, wire) => const Stream.empty()),
      hyperliquidOrderbookProvider
          .overrideWith((ref, wire) => Stream.value(_book(66000))),
      hyperliquidPerpPositionsProvider.overrideWith((_) => positions),
      hyperliquidSpotBalancesProvider.overrideWith((_) => spot),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidTradingProvider.overrideWith(() => _Trading(
          HyperliquidTradingState(
              isInitialized: true,
              positions: positions,
              spotBalances: spot))),
      hyperliquidLiveCandlesProvider.overrideWith(
          (ref, key) => Stream.value(HlLiveCandlesState(candles: tape))),
      hyperliquidDailyCandlesProvider
          .overrideWith((ref, wire) async => const []),
      hyperliquidTradeFlowProvider.overrideWith(
          (ref, coin) => Stream.value(const HlTradeFlowState())),
      aiEnabledProvider.overrideWith((ref) async => false),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => 0),
      hyperliquidMoveRailProvider.overrideWithValue(_rail),
      fundedOrdersProvider.overrideWith(_Funded.new),
    ],
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: shellBarObservers(),
        builder: shellBarBuilder,
        home: HlMarketDetailSheet(market: market),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size,
        pixelRatio: view.size.width > 1000 ? 1.25 : 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    Hive.init(Directory.systemTemp.createTempSync('hl-wide').path);
    // Open before any test's fake clock: the chart editor's drawings and
    // preferences read them.
    await Hive.openBox<String>('hl_chart_drawings');
    await Hive.openBox<String>('hl_chart_preferences');
    await _fonts();
  });
  setUp(() {
    OpenOnce.reset();
    _rail = FakeHyperliquidMoveRail();
    _rail.quote = const VenueMoveQuote(
        arrivingUsd: 0,
        feeUsd: 0.02,
        fixedCostUsd: 1,
        minUsd: 0.8,
        maxUsd: 107600);
  });
  tearDown(() => _rail.creditedController.close());

  testWidgets('EXPANDED: the ticket in place, the bar away, keys type',
      (tester) async {
    await _pump(tester,
        size: const Size(1440, 900), dark: false, market: _btc, held: true);
    expect(tester.takeException(), isNull);
    final slip = find.byType(HlOrderSlipSheet);
    expect(slip, findsOneWidget);
    expect(tester.widget<HlOrderSlipSheet>(slip).embedded, isTrue);
    expect(find.byKey(const ValueKey('order-slip-in-place-primary')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('kute-bar-trade-invest')), findsNothing);
    expect(find.byKey(const ValueKey('hl-pane-position-BTC')), findsOneWidget);
    // The pane is the right column, phone wide.
    final pane = tester.getRect(find.byKey(const ValueKey('hl-ticket-pane')));
    expect(pane.width, KuteLayout.paneWidth);
    expect(pane.right, lessThanOrEqualTo(1440 - KuteLayout.paneGap + 0.5));
    // A hardware key types the amount, as the keypad would.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    final pad = tester.widget<AmountKeypad>(find.byType(AmountKeypad));
    expect(pad.value, '12');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(tester.widget<AmountKeypad>(find.byType(AmountKeypad)).value, '1');
    await _unmount(tester);
  });

  // THE POINTER KIND DECIDES (founder, 25 November 2026: a plain mouse
  // drag drew a grey measuring box): a plain drag pans with any pointer,
  // the measuring box comes only from a Shift-drag with a mouse, hovering
  // a mouse shows the crosshair, and the wheel zooms the chart instead of
  // scrolling the page.
  Finder measureBox() => find.byWidgetPredicate((w) =>
      w is CustomPaint && w.painter is KuteChartDrawingsPainter);

  Future<Offset> chartCentre(WidgetTester tester) async {
    await _pump(tester,
        size: const Size(1440, 900), dark: false, market: _btc);
    return tester.getCenter(find.byType(HlCandlestickChart).first) -
        const Offset(60, 40);
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('a plain ${kind.name} drag pans, never measures',
        (tester) async {
      final at = await chartCentre(tester);
      final g = await tester.startGesture(at, kind: kind);
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(-20, 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(measureBox(), findsNothing);
      await g.up();
      await tester.pump();
      expect(measureBox(), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets('a Shift-drag with a mouse measures, gone on release',
      (tester) async {
    final at = await chartCentre(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-20, 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(measureBox(), findsOneWidget);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(measureBox(), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a Shift-drag with a finger is a plain drag', (tester) async {
    final at = await chartCentre(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final g = await tester.startGesture(at, kind: PointerDeviceKind.touch);
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-20, 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(measureBox(), findsNothing);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await _unmount(tester);
  });

  testWidgets('hovering a mouse shows the crosshair; leaving hides it',
      (tester) async {
    final at = await chartCentre(tester);
    expect(find.byType(KuteScrubCard), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    await mouse.moveTo(at + const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(KuteScrubCard), findsOneWidget);
    await mouse.moveTo(const Offset(1430, 890));
    // The crosshair fades out (120ms) and leaves the tree.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(KuteScrubCard), findsNothing);
    await mouse.removePointer();
    await _unmount(tester);
  });

  testWidgets('the wheel over the chart zooms; the page does not scroll',
      (tester) async {
    final at = await chartCentre(tester);
    final scrollable = tester.state<ScrollableState>(find
        .ancestor(
            of: find.byType(HlCandlestickChart).first,
            matching: find.byType(Scrollable))
        .first);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scrollable.position.pixels, 0);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  // "Data here seems too compressed" (founder, 25 November 2026): no stat
  // label is ever cut on the wide page.
  for (final size in const [Size(1440, 900), Size(1180, 820), Size(1000, 700)]) {
    testWidgets('no stat label cut at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await _pump(tester, size: size, dark: false, market: _btc, held: true);
      final tiles = find.byKey(const ValueKey('hl-stats-tiles'));
      expect(tiles, findsOneWidget);
      final texts = find.descendant(of: tiles, matching: find.byType(RichText));
      expect(texts, findsWidgets);
      for (final e in texts.evaluate()) {
        final p = e.renderObject! as RenderParagraph;
        expect(p.didExceedMaxLines, isFalse,
            reason: (p.text as TextSpan).toPlainText());
      }
      await _unmount(tester);
    });
  }

  // THE ADVANCED CHART EDITOR on a laptop (founder, 25 November 2026:
  // "even now it looks bad"): the whole window, the interval pills in the
  // header, a roomy rail with tooltips, no tap hint for a mouse, a real
  // price scale; keys: Escape, Delete, Cmd/Ctrl+Z.
  Future<void> openEditor(WidgetTester tester, Size size, bool dark) async {
    await _pump(tester, size: size, dark: dark, market: _btc, held: true);
    await tester.tap(find.byKey(const ValueKey('hl-advanced-chart')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final tape = hlEditCandles(count: 160);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HlMarketDetailSheet)));
    // The drawings load from Hive first (real IO): let it finish.
    container.read(hlChartDrawingsProvider(hlChartDrawingMarketKey(_btc)));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    {
      container
        .read(hlChartDrawingsProvider(hlChartDrawingMarketKey(_btc)).notifier)
        .add(ChartDrawing(
          id: 'trend-1',
          tool: ChartDrawingTool.trendline,
          points: [
            ChartDrawingPoint(
                timeMs: tape[95].openTime.millisecondsSinceEpoch,
                price: tape[95].low),
            ChartDrawingPoint(
                timeMs: tape[150].openTime.millisecondsSinceEpoch,
                price: tape[150].high),
          ],
        ));
    }
    // Until the drawing is in (the add waits on that load too).
    for (var i = 0;
        i < 60 &&
            container
                .read(hlChartDrawingsProvider(hlChartDrawingMarketKey(_btc)))
                .isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the editor on EXPANDED: whole window, pills, keys',
      (tester) async {
    await openEditor(tester, const Size(1440, 900), false);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('hl-chart-edit-top-bar-wide')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('hl-chart-edit-interval-row')),
        findsOneWidget);
    final rail = tester.getRect(find.byKey(const ValueKey('hl-chart-tool-rail')));
    expect(rail.width, 52);
    expect(rail.left, lessThan(40));
    // The hint never shows below the window's bottom edge.
    final hint = find.byKey(const ValueKey('hl-chart-edit-hint'));
    if (hint.evaluate().isNotEmpty) {
      expect(tester.getRect(hint).bottom, lessThanOrEqualTo(900));
    }
    // Arm a tool, Escape puts it down.
    await tester.tap(find.byKey(const ValueKey('hl-chart-rail-trendline')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // Cmd+Z undoes the drawing added, Shift+Cmd+Z brings it back.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HlMarketDetailSheet)));
    List<ChartDrawing> drawings() => container
        .read(hlChartDrawingsProvider(hlChartDrawingMarketKey(_btc)));
    expect(drawings(), hasLength(1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(drawings(), isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(drawings(), hasLength(1));
    // Delete removes the selected drawing (the toolbar's Delete).
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final (label, size) in [
    ('1440x900', const Size(1440, 900)),
    ('1920x1080', const Size(1920, 1080)),
    ('1100x700', const Size(1100, 700)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('render: editor $label $mode', skip: _dir == null,
          (tester) async {
        await openEditor(tester, size, dark);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'hl_editor_${label}_$mode');
        await _unmount(tester);
      });
    }
  }

  for (final (label, size) in [
    ('1440x900', const Size(1440, 900)),
    ('1180x820', const Size(1180, 820)),
    ('1920x1080', const Size(1920, 1080)),
    ('1000x700', const Size(1000, 700)),
    ('820x1180', const Size(820, 1180)),
    ('430x932', const Size(430, 932)),
  ]) {
    for (final dark in [false, true]) {
      for (final (kind, market, held) in [
        ('perp', _btc, false),
        ('perp_held', _btc, true),
        ('spot', _hype, false),
        ('spot_held', _hype, true),
      ]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('render: $label $mode $kind', skip: _dir == null,
            (tester) async {
          await _pump(tester,
              size: size, dark: dark, market: market, held: held);
          expect(tester.takeException(), isNull);
          await _shoot(tester, 'hl_market_${label}_${mode}_$kind');
          // EXPANDED: the area under the chart (stats, book, trades),
          // scrolled down.
          final about = find.byKey(const ValueKey('hl-about-in-place'));
          if (about.evaluate().isNotEmpty) {
            final scrollable = tester.state<ScrollableState>(find
                .ancestor(of: about, matching: find.byType(Scrollable))
                .first);
            scrollable.position
                .jumpTo(scrollable.position.maxScrollExtent);
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            await _shoot(tester, 'hl_market_${label}_${mode}_${kind}_below');
          }
          await _unmount(tester);
        });
      }
    }
  }
}
