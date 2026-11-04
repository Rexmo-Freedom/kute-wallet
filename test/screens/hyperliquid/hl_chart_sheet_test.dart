// The Hyperliquid chart's one picker sheet (hl_chart_sheet.dart): three
// style cards (Line, Candles, Area) with a removed style opening as its
// closest one, six indicator rows with switches in the founder's order,
// at most two panes below the chart (a third replaces the oldest, with a
// toast), Reset back to Line + Volume, and the floating bar hidden while
// the sheet is up. The Advanced editor's style and Σ buttons open one
// half each; its crosshair shows axis pills and its overlays a legend.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';

import '../../helpers/hl_chart_edit_harness.dart';

Finder _card(String style) => find.byKey(ValueKey('hl-chart-style-$style'));
Finder _row(String key) => find.byKey(ValueKey('hl-chart-indicator-$key'));

bool _picked(WidgetTester tester, String style) => tester
    .widget<Semantics>(
        find.ancestor(of: _card(style), matching: find.byType(Semantics)).first)
    .properties
    .selected!;

Set<String> _on(WidgetTester tester) => hlEditContainer(tester)
    .read(hlChartPreferencesProvider(hlEditBtcKey))
    .indicators;

String _style(WidgetTester tester) =>
    hlEditContainer(tester).read(hlChartLayoutProvider).style;

bool _barHidden(WidgetTester tester) {
  final top = kuteBarTop(hlEditContainer(tester).read(kuteBarContextProvider));
  return top?.hidden ?? false;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-close')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapRow(WidgetTester tester, String key) async {
  await tester.tap(_row(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('styles', () {
    test('three are offered; a removed one opens as its closest', () {
      expect(HlChartStyle.picker,
          [HlChartStyle.line, HlChartStyle.candles, HlChartStyle.area]);
      expect(HlChartStyle.fromName('hollow'), HlChartStyle.candles);
      expect(HlChartStyle.fromName('bars'), HlChartStyle.candles);
      expect(HlChartStyle.fromName('heikinAshi'), HlChartStyle.candles);
      expect(HlChartStyle.fromName('baseline'), HlChartStyle.area);
      expect(HlChartStyle.fromName('line'), HlChartStyle.line);
      expect(HlChartStyle.fromName('candles'), HlChartStyle.candles);
      expect(HlChartStyle.fromName(null), HlChartStyle.area);
      for (final s in HlChartStyle.values) {
        expect(HlChartStyle.picker, contains(s.offered));
      }
    });
  });

  group('the two-pane rule', () {
    test('a third pane below the chart replaces the oldest', () {
      var r = hlToggleSheetIndicator(['vol'], 'rsi');
      expect(r.next, ['vol', 'rsi']);
      expect(r.replaced, isNull);
      r = hlToggleSheetIndicator(r.next, 'macd');
      expect(r.next, ['rsi', 'macd']);
      expect(r.replaced, 'vol');
      // Overlays on the price never count.
      r = hlToggleSheetIndicator(r.next, 'ema');
      expect(r.next, ['rsi', 'macd', 'ema']);
      expect(r.replaced, isNull);
      // Off is plain off.
      r = hlToggleSheetIndicator(r.next, 'rsi');
      expect(r.next, ['macd', 'ema']);
      expect(r.replaced, isNull);
    });

    test('the sheet lists six, in the founder\'s order', () {
      expect(kHlSheetIndicators, ['vol', 'ema', 'bb', 'rsi', 'macd', 'vwap']);
      expect(
          ChartPreferencesNotifier.shownIndicators, kHlSheetIndicators.toSet());
      expect(kHlBelowIndicators, {'vol', 'rsi', 'macd'});
      expect(kHlDefaultIndicators, {'vol'});
    });
  });

  group('the Chart sheet', () {
    testWidgets(
        'one button opens it: three style cards, six switch rows, the bar '
        'hidden while it is up', (tester) async {
      await pumpHlEditSheet(tester);
      expect(_barHidden(tester), isFalse);
      await _openSheet(tester);

      expect(find.byKey(const ValueKey('hl-chart-sheet')), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
      for (final s in ['line', 'candles', 'area']) {
        expect(_card(s), findsOneWidget);
      }
      for (final s in ['hollow', 'bars', 'heikinAshi', 'baseline']) {
        expect(_card(s), findsNothing);
      }
      // Rows in order, each a switch; no chevrons.
      final ys = [
        for (final k in kHlSheetIndicators) tester.getTopLeft(_row(k)).dy
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.byType(Switch), findsNWidgets(6));
      expect(find.text('Moving averages'), findsOneWidget);
      expect(find.text('Whether buying or selling is overstretched'),
          findsOneWidget);
      expect(find.text('Stoch 14'), findsNothing);
      expect(find.text('MA 20/50'), findsNothing);
      // Rows are 52 px at least.
      expect(tester.getSize(_row('vol')).height, greaterThanOrEqualTo(52));

      expect(_barHidden(tester), isTrue);
      await _close(tester);
      expect(find.byKey(const ValueKey('hl-chart-sheet')), findsNothing);
      expect(_barHidden(tester), isFalse);
    });

    testWidgets('a style card applies at once and keeps the sheet up',
        (tester) async {
      await pumpHlEditSheet(tester);
      await _openSheet(tester);
      expect(_picked(tester, 'line'), isTrue);
      await tester.tap(_card('candles'));
      await tester.pump();
      expect(_style(tester), 'candles');
      expect(_picked(tester, 'candles'), isTrue);
      expect(_picked(tester, 'line'), isFalse);
      expect(find.byKey(const ValueKey('hl-chart-sheet')), findsOneWidget);
    });

    testWidgets(
        'a third pane turns the oldest off with a toast; Reset puts back '
        'Line and Volume', (tester) async {
      await pumpHlEditSheet(tester);
      await _openSheet(tester);
      expect(_on(tester), {'vol'});

      await _tapRow(tester, 'rsi');
      expect(_on(tester), {'vol', 'rsi'});
      await _tapRow(tester, 'macd');
      expect(_on(tester), {'rsi', 'macd'});
      expect(
          find.text('Volume is off: two fit below the chart'), findsOneWidget);
      await _tapRow(tester, 'ema');
      expect(_on(tester), {'rsi', 'macd', 'ema'});

      await tester.tap(_card('area'));
      await tester.pump();
      expect(_style(tester), 'area');

      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-reset')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_on(tester), {'vol'});
      expect(_style(tester), kHlDefaultChartStyle);
      // Let the toast run out.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('the Advanced editor', () {
    testWidgets('its Σ button opens the same list (no style cards)',
        (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      await tester.tap(find.byTooltip('Indicators'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('hl-chart-sheet')), findsOneWidget);
      expect(_card('line'), findsNothing);
      expect(find.byType(Switch), findsNWidgets(6));
      expect(_barHidden(tester), isTrue);
    });

    testWidgets(
        'EMA and RSI: a legend with values on the plot, a labelled pane; '
        'a long press shows the price and time pills', (tester) async {
      await pumpHlEditSheet(tester);
      hlEditContainer(tester)
          .read(hlChartPreferencesProvider(hlEditBtcKey).notifier)
          .setIndicators(['vol', 'ema', 'rsi']);
      await tester.pump();
      await enterHlEdit(tester);

      final legend = find.byKey(const ValueKey('hl-chart-overlay-legend'));
      expect(legend, findsOneWidget);
      final text = tester.widget<Text>(legend).textSpan!.toPlainText();
      expect(text, contains('EMA 9'));
      expect(text, contains('EMA 21'));
      expect(
          find.byKey(const ValueKey('hl-chart-pane-hairline')), findsOneWidget);
      final pane = find.byKey(const ValueKey('hl-chart-pane-label-RSI (14)'));
      expect(pane, findsOneWidget);
      expect(tester.widget<Text>(pane).textSpan!.toPlainText(),
          matches(RegExp(r'^RSI \(14\)  \d+(\.\d+)?$')));

      // Cursor in hand: a long press shows the crosshair's axis pills.
      expect(
          find.byKey(const ValueKey('hl-chart-crosshair-pills')), findsNothing);
      final plot = find.byKey(const ValueKey('hl-chart-overlay-legend'));
      final center = tester.getTopLeft(plot) + const Offset(120, 80);
      final g = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('hl-chart-crosshair-pills')),
          findsOneWidget);
      await g.up();
      await tester.pump();
      expect(
          find.byKey(const ValueKey('hl-chart-crosshair-pills')), findsNothing);
    });
  });
}
