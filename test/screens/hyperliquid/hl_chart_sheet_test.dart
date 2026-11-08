// The Hyperliquid chart's one picker sheet (hl_chart_sheet.dart), opened
// by the chart's one button on the market chart and in the Advanced top
// bar alike: chart types and the curated indicators as big square cards,
// two to a row, grouped (Chart type · Trend · Momentum · Volatility ·
// Volume); four indicators fit on the price and two below it (one more
// turns the oldest of its kind off, with a toast); an indicator that is
// on has a tune button to its settings; Reset puts back Line, Volume
// and every default. The Advanced chart reads TradingView style: an
// O H L C legend with the price indicators' values, labelled panes, the
// crosshair's axis pills and a Log switch in the axes' corner.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';

Finder _card(String style) => find.byKey(ValueKey('hl-chart-style-$style'));
Finder _ind(String key) => find.byKey(ValueKey('hl-chart-indicator-$key'));
Finder _tune(String key) =>
    find.byKey(ValueKey('hl-chart-indicator-settings-$key'));
const _sheet = ValueKey('hl-chart-sheet');

bool _picked(WidgetTester tester, String style) => tester
    .widget<Semantics>(
        find.ancestor(of: _card(style), matching: find.byType(Semantics)).first)
    .properties
    .selected!;

ChartPreferences _prefs(WidgetTester tester) =>
    hlEditContainer(tester).read(hlChartPreferencesProvider(hlEditBtcKey));

Set<String> _on(WidgetTester tester) => _prefs(tester).indicators;

String _style(WidgetTester tester) =>
    hlEditContainer(tester).read(hlChartLayoutProvider).style;

bool _barHidden(WidgetTester tester) {
  final top = kuteBarTop(hlEditContainer(tester).read(kuteBarContextProvider));
  return top?.hidden ?? false;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-close')).last);
  await _settle(tester);
}

Future<void> _tapCard(WidgetTester tester, Finder card) async {
  await tester.ensureVisible(card);
  await tester.pump();
  await tester.tap(card);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _seed(WidgetTester tester, List<String> keys) {
  hlEditContainer(tester)
      .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
      .setIndicators(keys);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('every language', () {
    setUpAll(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          final file = File('lib/assets/fonts/Inter-$f.ttf');
          if (file.existsSync()) {
            inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
          }
        }
        await inter.load();
      }
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
          '${locale.languageCode}: the new squares\' lines fit their card at '
          '375', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(375, 812) * 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              locale: locale,
              theme: buildLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: HlChartSheet(
                    market: hlEditBtc,
                    marketKey: hlEditBtcKey,
                    candles: hlEditCandles(),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        var checked = 0;
        for (final key in const [
          'hl-chart-indicator-ichi',
          'hl-chart-indicator-pp',
          'hl-chart-indicator-adx',
          'hl-chart-log-card',
          'hl-chart-your-trades-card',
        ]) {
          for (final p in tester.renderObjectList<RenderParagraph>(
              find.descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(RichText)))) {
            checked++;
            expect(p.didExceedMaxLines, isFalse,
                reason: '$key: "${p.text.toPlainText()}" does not fit');
          }
        }
        expect(checked, 10);
      });
    }
  });

  group('chart types', () {
    test('Line, Candles, Area, Heikin Ashi, Hollow and Baseline; bars opens '
        'as candles', () {
      expect(HlChartStyle.picker, [
        HlChartStyle.line,
        HlChartStyle.candles,
        HlChartStyle.area,
        HlChartStyle.heikinAshi,
        HlChartStyle.hollow,
        HlChartStyle.baseline,
      ]);
      expect(HlChartStyle.fromName('hollow'), HlChartStyle.hollow);
      expect(HlChartStyle.fromName('bars'), HlChartStyle.candles);
      expect(HlChartStyle.fromName('heikinAshi'), HlChartStyle.heikinAshi);
      expect(HlChartStyle.fromName('baseline'), HlChartStyle.baseline);
      expect(HlChartStyle.fromName(null), HlChartStyle.area);
      for (final s in HlChartStyle.values) {
        expect(HlChartStyle.picker, contains(s.offered));
      }
    });
  });

  group('the curated indicators', () {
    test('fifteen, grouped, with TradingView\'s defaults', () {
      expect(kHlIndicatorCatalog, hasLength(15));
      final byGroup = {
        for (final g in HlIndGroup.values)
          g: [
            for (final s in kHlIndicatorCatalog)
              if (s.group == g) hlIndTitle(s.key, s.defaults),
          ],
      };
      expect(byGroup, {
        HlIndGroup.trend: [
          'EMA 9 21',
          'SMA 50 200',
          'VWAP',
          'Supertrend 10 3',
          'Ichimoku 9 26 52 26',
          'Pivots',
        ],
        HlIndGroup.momentum: [
          'RSI 14',
          'MACD 12 26 9',
          'Stoch RSI 14 14 3 3',
          'ADX 14 14',
        ],
        HlIndGroup.volatility: ['BB 20 2', 'ATR 14'],
        HlIndGroup.volume: ['Vol', 'OBV', 'VP 24'],
      });
      expect(ChartPreferencesNotifier.shownIndicators,
          {...kHlIndicatorKeys, kHlLayerMyTradesOff});
      expect(kHlDefaultIndicators, {'vol'});
    });

    test('two panes below the chart: a third replaces the oldest', () {
      var r = hlToggleIndicator(['vol'], 'rsi');
      expect(r.next, ['vol', 'rsi']);
      r = hlToggleIndicator(r.next, 'macd');
      expect(r.next, ['vol', 'rsi', 'macd']);
      expect(r.replaced, isNull);
      r = hlToggleIndicator(r.next, 'obv');
      expect(r.next, ['vol', 'macd', 'obv']);
      expect(r.replaced, 'rsi');
      // Off is plain off.
      r = hlToggleIndicator(r.next, 'macd');
      expect(r.next, ['vol', 'obv']);
      expect(r.replaced, isNull);
    });

    test('four on the price: a fifth replaces the oldest; Volume never '
        'counts', () {
      var next = <String>['vol'];
      for (final k in ['ema', 'ma', 'vwap', 'bb']) {
        final r = hlToggleIndicator(next, k);
        expect(r.replaced, isNull);
        next = r.next;
      }
      final r = hlToggleIndicator(next, 'vp');
      expect(r.replaced, 'ema');
      expect(r.next, ['vol', 'ma', 'vwap', 'bb', 'vp']);
    });

    test('the new ones keep the limits: Ichimoku and Pivots on the price, ADX '
        'below it', () {
      expect(hlIndSpec('ichi')!.place, HlIndPlace.price);
      expect(hlIndSpec('pp')!.place, HlIndPlace.price);
      expect(hlIndSpec('adx')!.place, HlIndPlace.pane);
      expect(kHlMaxPriceIndicators, 4);
      expect(kHlMaxPanes, 2);
      var on = <String>['vol', 'ema', 'bb', 'st', 'ichi'];
      final fifth = hlToggleIndicator(on, 'pp');
      expect(fifth.replaced, 'ema');
      expect(fifth.next, ['vol', 'bb', 'st', 'ichi', 'pp']);
      on = ['vol', 'rsi', 'macd'];
      final third = hlToggleIndicator(on, 'adx');
      expect(third.replaced, 'rsi');
      expect(third.next, ['vol', 'macd', 'adx']);
    });

    test('settings are clamped to their range and grid', () {
      expect(hlIndParams('rsi', const {}), [14]);
      expect(hlIndParams('rsi', {'rsi': [1]}), [2]);
      expect(hlIndParams('rsi', {'rsi': [999]}), [100]);
      expect(hlIndParams('bb', {'bb': [20, 2.3]}), [20, 2.5]);
      expect(hlIndParams('st', {'st': [7]}), [7, 3]);
      expect(hlIndParams('vp', {'vp': [26]}), [28]);
      expect(hlParamText(2.5), '2.5');
      expect(hlParamText(3.0), '3');
    });

    test('preferences store only what differs from the defaults', () {
      const prefs = ChartPreferences(
        indicators: {'vol', 'rsi'},
        params: {
          'rsi': [21],
        },
        logScale: true,
      );
      expect(prefs.toJson(), {
        'indicators': ['vol', 'rsi'],
        'snap': true,
        'params': {
          'rsi': [21],
        },
        'log': true,
      });
      expect(const ChartPreferences().toJson().keys, ['indicators', 'snap']);
    });
  });

  group('the Chart sheet', () {
    testWidgets(
        'one button opens it: grouped square cards, no switches, the bar '
        'hidden while it is up', (tester) async {
      await pumpHlEditSheet(tester);
      expect(_barHidden(tester), isFalse);
      await _openSheet(tester);

      expect(find.byKey(_sheet), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
      // The groups, top to bottom.
      final groups = [
        'type',
        for (final g in HlIndGroup.values) g.name,
      ];
      final ys = <double>[];
      for (final g in groups) {
        final label = find.byKey(ValueKey('hl-chart-group-$g'));
        await tester.ensureVisible(label);
        await tester.pump();
        ys.add(tester.getTopLeft(label).dy);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('hl-chart-group-type')));
      await tester.pump();
      expect(find.text('Chart type'), findsOneWidget);
      for (final s in [
        'line',
        'candles',
        'area',
        'heikinAshi',
        'hollow',
        'baseline',
      ]) {
        expect(_card(s), findsOneWidget);
      }
      expect(_card('bars'), findsNothing);
      expect(find.text('Hollow candles'), findsOneWidget);
      expect(find.text('Baseline'), findsOneWidget);
      // Two to a row, square-ish and big.
      final line = tester.getRect(_card('line'));
      final candles = tester.getRect(_card('candles'));
      expect(candles.top, line.top);
      expect(candles.left, greaterThan(line.right));
      expect(line.width, greaterThan(150));
      expect(line.height, greaterThanOrEqualTo(100));
      expect(find.byType(Switch), findsNothing);
      for (final s in kHlIndicatorCatalog) {
        expect(_ind(s.key), findsOneWidget, reason: s.key);
      }
      final ema = tester.getRect(_ind('ema'));
      final sma = tester.getRect(_ind('ma'));
      expect(sma.top, ema.top);
      expect(ema.height, greaterThanOrEqualTo(100));
      expect(find.text('Short-term trend, quick to turn'), findsOneWidget);

      expect(_barHidden(tester), isTrue);
      await _close(tester);
      expect(find.byKey(_sheet), findsNothing);
      expect(_barHidden(tester), isFalse);
    });

    testWidgets('a chart type applies at once and keeps the sheet up',
        (tester) async {
      await pumpHlEditSheet(tester);
      await _openSheet(tester);
      expect(_picked(tester, 'line'), isTrue);
      await _tapCard(tester, _card('heikinAshi'));
      expect(_style(tester), 'heikinAshi');
      expect(_picked(tester, 'heikinAshi'), isTrue);
      expect(_picked(tester, 'line'), isFalse);
      expect(find.byKey(_sheet), findsOneWidget);
    });

    testWidgets('Hollow candles and Baseline apply and stay saved, by name',
        (tester) async {
      await pumpHlEditSheet(tester);
      await _openSheet(tester);
      await _tapCard(tester, _card('hollow'));
      expect(_style(tester), 'hollow');
      expect(_picked(tester, 'hollow'), isTrue);
      expect(
          tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart))
              .style,
          HlChartStyle.hollow);
      await _tapCard(tester, _card('baseline'));
      expect(_style(tester), 'baseline');
      final chart =
          tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart));
      expect(chart.style, HlChartStyle.baseline);
      // No position: the level is the first bar on screen.
      expect(chart.baselinePrice, isNull);
    });

    testWidgets('Baseline sits on the open position\'s entry', (tester) async {
      await pumpHlEditSheet(tester, positions: [
        HlPerpPosition(
          coin: 'BTC',
          szi: 0.5,
          entryPx: 64000,
          positionValue: 33000,
          unrealizedPnl: 1000,
          returnOnEquity: 0.03,
          liquidationPx: null,
          marginUsed: 3300,
          leverageType: 'cross',
          leverageValue: 10,
          maxLeverage: 40,
        ),
      ]);
      expect(
          tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart))
              .baselinePrice,
          64000);
    });

    testWidgets(
        'a third pane turns the oldest off with a toast; Volume stays; '
        'Reset puts back Line, Volume and the defaults', (tester) async {
      await pumpHlEditSheet(tester);
      await _openSheet(tester);
      expect(_on(tester), {'vol'});

      await _tapCard(tester, _ind('rsi'));
      await _tapCard(tester, _ind('macd'));
      expect(_on(tester), {'vol', 'rsi', 'macd'});
      await _tapCard(tester, _ind('atr'));
      expect(_on(tester), {'vol', 'macd', 'atr'});
      expect(find.text('RSI is off: two fit below the chart'), findsOneWidget);

      await _tapCard(tester, _card('area'));
      expect(_style(tester), 'area');
      hlEditContainer(tester)
          .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
          .setParams('macd', [8, 21, 5]);
      await tester.pump();
      expect(_prefs(tester).params, {
        'macd': [8, 21, 5],
      });

      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-reset')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_on(tester), {'vol'});
      expect(_prefs(tester).params, isEmpty);
      expect(_style(tester), kHlDefaultChartStyle);
      // Let the toast run out.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'an indicator that is on has a tune button: its settings step and '
        'reset', (tester) async {
      await pumpHlEditSheet(tester);
      await _openSheet(tester);
      expect(_tune('rsi'), findsNothing);
      await _tapCard(tester, _ind('rsi'));
      expect(_tune('rsi'), findsOneWidget);
      // OBV has no settings: no tune button even when on.
      await _tapCard(tester, _ind('obv'));
      expect(_tune('obv'), findsNothing);

      await tester.ensureVisible(_tune('rsi'));
      await tester.pump();
      await tester.tap(_tune('rsi'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-indicator-settings-rsi')),
          findsOneWidget);
      expect(find.text('RSI settings'), findsOneWidget);
      expect(find.text('Length'), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('hl-indicator-value-length')))
              .data,
          '14');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('hl-indicator-step-length-up')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_prefs(tester).params, {
        'rsi': [17],
      });
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('hl-indicator-value-length')))
              .data,
          '17');
      await tester.tap(find.byKey(const ValueKey('hl-indicator-settings-reset')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_prefs(tester).params, isEmpty);
      await tester
          .tap(find.byKey(const ValueKey('hl-indicator-settings-close')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-indicator-settings-rsi')),
          findsNothing);
      expect(find.byKey(_sheet), findsOneWidget);
    });
  });

  group('the Advanced chart', () {
    testWidgets(
        'one chart button in its top bar opens the whole sheet (no separate '
        'style and indicator buttons)', (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      expect(find.byIcon(Icons.functions_rounded), findsNothing);
      expect(find.byTooltip('Indicators'), findsNothing);
      expect(find.byTooltip('Chart style'), findsNothing);
      final button = find.byKey(const ValueKey('hl-chart-edit-sheet-button'));
      expect(button, findsOneWidget);
      // The market chart's button's look: its style glyph and a chevron.
      expect(
          find.descendant(
              of: button, matching: find.byIcon(Icons.expand_more_rounded)),
          findsOneWidget);
      await tester.tap(button);
      await _settle(tester);
      expect(find.byKey(_sheet), findsOneWidget);
      expect(_card('line'), findsOneWidget);
      expect(_ind('ema'), findsOneWidget);
      expect(_barHidden(tester), isTrue);
    });

    testWidgets(
        'an O H L C legend with the price indicators\' values, a labelled '
        'pane per oscillator, and the crosshair\'s axis pills',
        (tester) async {
      await pumpHlEditSheet(tester);
      _seed(tester, ['vol', 'ema', 'st', 'rsi', 'macd']);
      await tester.pump();
      await enterHlEdit(tester);

      String text(String key) => tester
          .widget<Text>(find.byKey(ValueKey(key)))
          .textSpan!
          .toPlainText();
      expect(text('hl-chart-ohlc'),
          matches(RegExp(r'^O [\d,.]+  H [\d,.]+  L [\d,.]+  C [\d,.]+  '
              r'[+−][\d.]+%  Vol [\d.]+k?  $')));
      expect(text('hl-chart-legend-ema'),
          matches(RegExp(r'^EMA 9 21  [\d,.]+  [\d,.]+$')));
      expect(text('hl-chart-legend-st'),
          matches(RegExp(r'^Supertrend 10 3  [\d,.]+$')));
      expect(find.byKey(const ValueKey('hl-chart-pane-label-RSI 14')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('hl-chart-pane-label-MACD 12 26 9')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('hl-chart-pane-hairline')),
          findsNWidgets(2));

      // Cursor in hand: a long press shows the crosshair's axis pills and
      // the legend follows the bar under the finger.
      final before = text('hl-chart-ohlc');
      expect(
          find.byKey(const ValueKey('hl-chart-crosshair-pills')), findsNothing);
      final plot = find.byKey(const ValueKey('hl-chart-overlay-legend'));
      final center = tester.getTopLeft(plot) + const Offset(60, 120);
      final g = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('hl-chart-crosshair-pills')),
          findsOneWidget);
      expect(text('hl-chart-ohlc'), isNot(before));
      await g.up();
      await tester.pump();
      expect(
          find.byKey(const ValueKey('hl-chart-crosshair-pills')), findsNothing);
      expect(text('hl-chart-ohlc'), before);
    });

    testWidgets('the axes\' corner switches the price axis to log',
        (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      final toggle = find.byKey(const ValueKey('hl-chart-log-toggle'));
      expect(toggle, findsOneWidget);
      expect(_prefs(tester).logScale, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_prefs(tester).logScale, isTrue);
      expect(
          tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart))
              .logScale,
          isTrue);
    });

    testWidgets(
        'the Log scale square switches this market\'s axis alone, and Reset '
        'puts it back', (tester) async {
      await pumpHlEditSheet(tester);
      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
      await _settle(tester);
      final card = find.byKey(const ValueKey('hl-chart-log-card'));
      await tester.ensureVisible(card);
      await _settle(tester);
      expect(
          find.descendant(of: card, matching: find.text('Log scale')),
          findsOneWidget);
      await tester.tap(card);
      await _settle(tester);
      expect(_prefs(tester).logScale, isTrue);
      expect(
          tester
              .widget<Semantics>(find
                  .ancestor(of: card, matching: find.byType(Semantics))
                  .first)
              .properties
              .toggled,
          isTrue);
      expect(
          hlEditContainer(tester)
              .read(hlChartPreferencesProvider('hl:perp::ETH'))
              .logScale,
          isFalse);
      expect(_prefs(tester).toJson()['log'], true);

      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-reset')));
      await _settle(tester);
      expect(_prefs(tester).logScale, isFalse);
      expect(_prefs(tester).toJson().containsKey('log'), isFalse);
    });

    testWidgets(
        'Your trades is on by default, per market, with its own markers; off '
        'hands the chart none, and Reset puts it back', (tester) async {
      final fill = HlFill(
        coin: 'BTC',
        px: 64000,
        sz: 1,
        side: 'B',
        time: hlEditCandles()[100].openTime.millisecondsSinceEpoch + 1000,
        closedPnl: 0,
        fee: 0,
        feeToken: 'USDC',
        oid: 1,
        hash: 'a',
        dir: 'Open Long',
        cloid: null,
        tradeId: 'a',
      );
      HlCandlestickChart chart() =>
          tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart));
      await pumpHlEditSheet(tester, fills: [fill]);
      expect(chart().fills, [fill]);

      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
      await _settle(tester);
      final card = find.byKey(const ValueKey('hl-chart-your-trades-card'));
      await tester.ensureVisible(card);
      await _settle(tester);
      expect(find.descendant(of: card, matching: find.text('Your trades')),
          findsOneWidget);
      await tester.tap(card);
      await _settle(tester);
      expect(chart().fills, isEmpty);
      expect(_on(tester), contains(kHlLayerMyTradesOff));
      // Not an indicator: never in the frame, never counted in the limits.
      expect(hlIndSpec(kHlLayerMyTradesOff), isNull);
      expect(
          hlEditContainer(tester)
              .read(hlChartPreferencesProvider('hl:perp::ETH'))
              .indicators,
          isNot(contains(kHlLayerMyTradesOff)));
      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-reset')));
      await _settle(tester);
      expect(chart().fills, [fill]);
      expect(_on(tester), {'vol'});
    });

    testWidgets(
        'Pivots read real daily candles: P in the legend, and nothing until '
        'they have arrived', (tester) async {
      final start = hlEditCandles().first.openTime;
      await pumpHlEditSheet(tester, daily: [
        for (var d = -2; d < 8; d++)
          HyperliquidCandle(
            openTime: start.add(Duration(days: d)),
            closeTime: start.add(Duration(days: d + 1)),
            open: 64000,
            high: 65000,
            low: 63000,
            close: 64500,
            volume: 100,
          ),
      ]);
      _seed(tester, ['vol', 'pp']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await enterHlEdit(tester);
      final row = find.byKey(const ValueKey('hl-chart-legend-pp'));
      expect(row, findsOneWidget);
      // (65000 + 63000 + 64500) / 3, and only P is written.
      final text = tester.widget<Text>(row).textSpan!.toPlainText();
      expect(text, contains('Pivots'));
      expect(text, contains('64,167'));
      expect(text.split(RegExp(r'\s\s+')), hasLength(2));
    });

    testWidgets('volume profile draws on the price and names its POC',
        (tester) async {
      await pumpHlEditSheet(tester);
      _seed(tester, ['vol', 'vp']);
      await tester.pump();
      await enterHlEdit(tester);
      expect(find.byKey(const ValueKey('hl-chart-volume-profile')),
          findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('hl-chart-legend-vp')))
              .textSpan!
              .toPlainText(),
          matches(RegExp(r'^VP 24  POC [\d,.]+$')));
    });
  });
}
