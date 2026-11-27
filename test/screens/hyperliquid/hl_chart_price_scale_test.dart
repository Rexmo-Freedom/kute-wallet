// The Advanced chart's price scale (hl_charts.dart, _HlPriceScalePainter
// and _HlPriceLinesPainter): its horizontal price lines across the plot
// and their labels down the right, on by default in every chart type,
// with no indicator pane, one or two, the crosshair up or not, at the
// desk (1440, 1100) and in a phone's editor (390). A gold market's
// "4,120.0" fits the tag column whole (the column was sized for the
// price's 10.5 px pill and lost every 12 px label by 0.7 px). No label
// covers another or the latest price's tag. The rail's Price scale
// button switches lines and labels off and on again for every market
// (HlChartLayout.priceScale, the 'settings' box), the latest price's tag
// staying put. Real Inter, as the app draws it.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart'
    show HlRailButton;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';
import '../../helpers/hl_price_scale_probe.dart';
import '../../helpers/render_png.dart';

Future<void> _pumpChart(
  WidgetTester tester, {
  required double width,
  HlChartStyle style = HlChartStyle.candles,
  Set<String> indicators = const {'vol', 'atr'},
  bool priceScale = true,
  bool dark = false,
  double base = 4123.4,
}) async {
  const height = 860.0;
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final desk = width >= KuteLayout.expandedMinWidth;
  await tester.pumpWidget(ScreenUtilInit(
    // As the app: the phone design below 600, the window itself above.
    designSize: KuteLayout.designSizeFor(Size(width, height)),
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (_, __) => MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height - 40,
          child: HlCandlestickChart(
            marketKey: 'hl:perp:xyz:GOLD',
            candles: goldCandles(base: base),
            isLive: true,
            style: style,
            showVolume: indicators.contains('vol'),
            indicators: indicators,
            drawingMode: true,
            desk: desk,
            fillHeight: true,
            showSummary: false,
            priceScale: priceScale,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void expectScaleClear(WidgetTester tester, {required String reason}) {
  final labels = scaleLabels(tester);
  expect(labels.length, greaterThanOrEqualTo(3),
      reason: '$reason: the scale writes ${labels.length} labels');
  final lines = priceLines(tester);
  expect(lines.length, greaterThanOrEqualTo(3),
      reason: '$reason: ${lines.length} price lines');
  final tag = lastPriceTag(tester);
  for (var i = 0; i < labels.length; i++) {
    expect(labels[i].overlaps(tag), isFalse,
        reason: '$reason: ${labels[i]} covers the price tag $tag');
    // Past the end of the price lines: in the column.
    expect(labels[i].left, greaterThanOrEqualTo(lines.first.$2.dx),
        reason: '$reason: a label runs into the plot');
    for (var j = i + 1; j < labels.length; j++) {
      expect(labels[i].overlaps(labels[j]), isFalse,
          reason: '$reason: ${labels[i]} and ${labels[j]} overlap');
    }
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('on by default', () {
    for (final width in [1440.0, 1100.0, 390.0]) {
      for (final style in HlChartStyle.values) {
        for (final panes in [<String>{}, {'vol'}, {'vol', 'atr'}]) {
          for (final dark in [false, true]) {
            testWidgets(
                '$width ${style.name} $panes ${dark ? 'dark' : 'light'}: '
                'price lines and labels, none over another or the price tag',
                (tester) async {
              await tester.runAsync(loadRenderFonts);
              await _pumpChart(tester,
                  width: width, style: style, indicators: panes, dark: dark);
              expect(tester.takeException(), isNull);
              expectScaleClear(tester,
                  reason: '$width ${style.name} $panes');
            });
          }
        }
      }
    }

    for (final base in [880.0, 98123.0, 0.4123]) {
      testWidgets('other price sizes ($base) keep their labels',
          (tester) async {
        await tester.runAsync(loadRenderFonts);
        await _pumpChart(tester, width: 1440, base: base);
        expectScaleClear(tester, reason: '$base');
      });
    }

    testWidgets('the crosshair up: the scale stays, the tags apart',
        (tester) async {
      await tester.runAsync(loadRenderFonts);
      await _pumpChart(tester, width: 1440);
      final plot =
          tester.getRect(hlLayerFinder('_HlCandlePainter'));
      final mouse =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: plot.center + const Offset(0, -60));
      await mouse.moveTo(plot.center + const Offset(0, -40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(paintedBy(tester, '_HlCrosshairPillsPainter').texts, isNotEmpty,
          reason: 'the crosshair is up');
      expectScaleClear(tester, reason: 'crosshair');
    });
  });

  group('off', () {
    for (final style in [HlChartStyle.candles, HlChartStyle.line]) {
      for (final width in [1440.0, 390.0]) {
        testWidgets(
            '$width ${style.name}: no price lines, no labels, the price tag '
            'stays', (tester) async {
          await tester.runAsync(loadRenderFonts);
          await _pumpChart(tester, width: width, style: style);
          // The time axis' dates (widgets, unlike the painted scale).
          final dates = find.byType(Text).evaluate().length;
          await _pumpChart(tester,
              width: width, style: style, priceScale: false);
          expect(hlLayerFinder('_HlPriceScalePainter'), findsNothing);
          expect(hlLayerFinder('_HlPriceLinesPainter'), findsNothing);
          final tag = lastPriceTag(tester);
          final tagText = paintedBy(tester, '_HlCandlePainter')
              .texts
              .where((t) => tag.inflate(1).contains(t.center));
          expect(tagText, isNotEmpty, reason: 'the price tag lost its price');
          // The time axis is untouched.
          expect(find.byType(Text).evaluate().length, dates);
        });
      }
    }

    testWidgets('outside the editor the chart is as before (no price lines)',
        (tester) async {
      await tester.runAsync(loadRenderFonts);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HlCandlestickChart(
              candles: goldCandles(),
              height: 300,
              style: HlChartStyle.candles,
              cleanView: true,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hlLayerFinder('_HlPriceLinesPainter'), findsNothing);
      expect(hlLayerFinder('_HlPriceScalePainter'), findsOneWidget);
    });
  });

  group('the setting', () {
    late Directory dir;
    late Box<dynamic> box;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kute-price-scale-');
      Hive.init(dir.path);
      box = await Hive.openBox('settings');
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('on by default, saved with the layout, read back', () async {
      var container = ProviderContainer();
      expect(container.read(hlChartLayoutProvider).priceScale, isTrue);
      container.read(hlChartLayoutProvider.notifier).setStyle('candles');
      container.read(hlChartLayoutProvider.notifier).setPriceScale(false);
      // The first read's migration of older builds' boxes saves too.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(box.get('hlChartLayoutPriceScale'), isFalse);
      expect(box.get('hlChartLayoutStyle'), 'candles');
      container.dispose();
      container = ProviderContainer();
      expect(container.read(hlChartLayoutProvider).priceScale, isFalse);
      expect(container.read(hlChartLayoutProvider).style, 'candles');
      container.dispose();
      // A layout an older build saved (no price scale yet): on.
      await box.delete('hlChartLayoutPriceScale');
      container = ProviderContainer();
      expect(container.read(hlChartLayoutProvider).priceScale, isTrue);
      container.dispose();
    });
  });

  group('the rail button', () {
    for (final size in [const Size(390, 844), const Size(800, 1000)]) {
      testWidgets(
          '${size.width}: selected while on; a tap turns the price lines and '
          'labels off for every market (the saved layout), another back on', (tester) async {
        await pumpHlEditSheet(tester,
            width: size.width, height: size.height, candles: goldCandles());
        await enterHlEdit(tester);
        final button =
            find.byKey(const ValueKey('hl-chart-rail-price-scale'));
        expect(button, findsOneWidget);
        // Under the groups, past the divider, above the "…" button.
        final more = find.byKey(const ValueKey('hl-chart-rail-more'));
        final text = find.byKey(const ValueKey('hl-chart-rail-text'));
        expect(tester.getCenter(button).dy,
            greaterThan(tester.getCenter(text).dy));
        expect(tester.getCenter(button).dy,
            lessThan(tester.getCenter(more).dy));
        HlRailButton rail() => tester.widget<HlRailButton>(
            find.descendant(of: button, matching: find.byType(HlRailButton)));
        HlCandlestickChart chart() =>
            tester.widget<HlCandlestickChart>(find.byType(HlCandlestickChart));
        expect(rail().selected, isTrue);
        expect(rail().label, 'Price scale');
        expect(chart().priceScale, isTrue);
        expect(scaleLabels(tester), isNotEmpty);
        expect(priceLines(tester), isNotEmpty);

        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final c = hlEditContainer(tester);
        expect(c.read(hlChartLayoutProvider).priceScale, isFalse);
        expect(rail().selected, isFalse);
        expect(chart().priceScale, isFalse);
        expect(hlLayerFinder('_HlPriceScalePainter'), findsNothing);
        expect(hlLayerFinder('_HlPriceLinesPainter'), findsNothing);
        lastPriceTag(tester);
        // The market's own chart settings are not where it lives.
        expect(
            c.read(hlChartPreferencesProvider(hlEditBtcKey)).logScale, isFalse);

        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(c.read(hlChartLayoutProvider).priceScale, isTrue);
        expect(rail().selected, isTrue);
        expect(scaleLabels(tester), isNotEmpty);
        expect(priceLines(tester), isNotEmpty);
      });
    }
  });
}
