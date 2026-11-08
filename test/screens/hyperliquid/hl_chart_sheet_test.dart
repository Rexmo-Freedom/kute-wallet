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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';

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

  group('chart types', () {
    test('Line, Candles, Area and Heikin Ashi; a removed one opens as its '
        'closest', () {
      expect(HlChartStyle.picker, [
        HlChartStyle.line,
        HlChartStyle.candles,
        HlChartStyle.area,
        HlChartStyle.heikinAshi,
      ]);
      expect(HlChartStyle.fromName('hollow'), HlChartStyle.candles);
      expect(HlChartStyle.fromName('bars'), HlChartStyle.candles);
      expect(HlChartStyle.fromName('heikinAshi'), HlChartStyle.heikinAshi);
      expect(HlChartStyle.fromName('baseline'), HlChartStyle.area);
      expect(HlChartStyle.fromName(null), HlChartStyle.area);
      for (final s in HlChartStyle.values) {
        expect(HlChartStyle.picker, contains(s.offered));
      }
    });
  });

  group('the curated indicators', () {
    test('a dozen, grouped, with TradingView\'s defaults', () {
      final byGroup = {
        for (final g in HlIndGroup.values)
          g: [
            for (final s in kHlIndicatorCatalog)
              if (s.group == g) hlIndTitle(s.key, s.defaults),
          ],
      };
      expect(byGroup, {
        HlIndGroup.trend: ['EMA 9 21', 'SMA 50 200', 'VWAP', 'Supertrend 10 3'],
        HlIndGroup.momentum: ['RSI 14', 'MACD 12 26 9', 'Stoch RSI 14 14 3 3'],
        HlIndGroup.volatility: ['BB 20 2', 'ATR 14'],
        HlIndGroup.volume: ['Vol', 'OBV', 'VP 24'],
      });
      expect(ChartPreferencesNotifier.shownIndicators, kHlIndicatorKeys);
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
      for (final s in ['line', 'candles', 'area', 'heikinAshi']) {
        expect(_card(s), findsOneWidget);
      }
      for (final s in ['hollow', 'bars', 'baseline']) {
        expect(_card(s), findsNothing);
      }
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
