// Price lines on the Investing chart (hl_price_lines_*.dart,
// hl_price_line_cards.dart): the rail's tool sets a line on this device, a
// tap on the line removes it after asking, the Chart sheet lists them in its
// own cards, and a crossing is marked with the quiet snack bar. There is no
// notification: no string here may suggest one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/models/hl_price_line.dart';
import 'package:kute/providers/hl_price_lines_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_price_line_cards.dart';
import 'package:kute/screens/hyperliquid/components/hl_price_lines_chart.dart';
import 'package:kute/screens/hyperliquid/components/hl_price_lines_host.dart';
import 'package:kute/screens/shared/charts/kute_chart_drawings.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';

Finder get _bells => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is HlPriceLineBellsPainter);

Finder get _drawingsLayer => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KuteChartDrawingsPainter);

Offset _screenAt(WidgetTester tester, double price, {double dx = 120}) {
  final painter = tester.widget<CustomPaint>(_drawingsLayer.first).painter
      as KuteChartDrawingsPainter;
  final geom = painter.resolveGeometry(tester.getSize(_drawingsLayer.first))!;
  return tester.getTopLeft(_drawingsLayer.first) +
      Offset(dx, geom.yForPrice(price));
}

HlPriceLinesNotifier _lines(WidgetTester tester) =>
    hlEditContainer(tester).read(hlPriceLinesProvider.notifier);

List<HlPriceLine> _saved(WidgetTester tester) =>
    hlEditContainer(tester).read(hlPriceLinesProvider);

void _seed(WidgetTester tester, double level) => _lines(tester).add(
    market: hlEditBtc, marketKey: hlEditBtcKey, level: level, reference: 66000);

Future<void> _open(WidgetTester tester) async {
  await pumpHlEditSheet(tester);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('on the chart', () {
    testWidgets('the rail tool sits by Level and sets a line, not a drawing',
        (tester) async {
      await _open(tester);
      await enterHlEdit(tester);
      final level =
          tester.getTopLeft(find.byKey(const ValueKey('hl-chart-rail-level')));
      final tool = find.byKey(const ValueKey('hl-chart-rail-priceLine'));
      expect(tester.getTopLeft(tool).dy, greaterThan(level.dy));
      expect(tester.getTopLeft(tool).dx, level.dx);

      // A first line mounts the layer the tap is measured against.
      _seed(tester, 65000);
      await _settle(tester);
      await tester.tap(tool);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(_screenAt(tester, 64500));
      await tester.pump();

      expect(hlEditDrawings(tester), isEmpty);
      expect(_saved(tester), hasLength(2));
      final placed = _saved(tester).last;
      expect(placed.coin, 'BTC');
      expect(placed.marketKey, hlEditBtcKey);
      expect(placed.level, lessThan(66000));
      // Below the live 66,000: it waits for a fall.
      expect(placed.direction, HlPriceLineDirection.below);
      expect(placed.isReached, isFalse);
      // One line per pick: the rail is back on Cursor.
      expect(find.byKey(const ValueKey('hl-drawing-toolbar')), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('shows on the plain chart, with its price tag', (tester) async {
      await _open(tester);
      expect(_bells, findsNothing);
      _seed(tester, 65000);
      await _settle(tester);
      expect(_bells, findsOneWidget);
      expect(
          find.byWidgetPredicate((w) =>
              w is CustomPaint && w.painter is KuteDrawingPriceTagsPainter),
          findsOneWidget);
      final painted = (tester.widget<CustomPaint>(_drawingsLayer).painter
              as KuteChartDrawingsPainter)
          .drawings
          .single;
      expect(painted.tool, ChartDrawingTool.priceLine);
      expect(painted.dashed, isTrue);
      // The drawings' neutral colour while waiting, like any level.
      expect(painted.colorValue, isNull);
    });

    testWidgets('reached: the line goes to the quiet colour', (tester) async {
      await _open(tester);
      _seed(tester, 65000);
      await _settle(tester);
      _lines(tester).applyLiveTicks({'BTC': 64900}, (c) => c);
      await _settle(tester);
      final painted = (tester.widget<CustomPaint>(_drawingsLayer).painter
              as KuteChartDrawingsPainter)
          .drawings
          .single;
      expect(painted.colorValue, isNotNull);
      expect(_saved(tester).single.isReached, isTrue);
    });

    testWidgets('a tap on the line asks, then removes; cancel keeps it',
        (tester) async {
      await _open(tester);
      _seed(tester, 65000);
      await _settle(tester);

      await tester.tapAt(_screenAt(tester, 65000));
      await _settle(tester);
      final l10n = AppLocalizations.of(tester.element(_drawingsLayer));
      expect(find.text(l10n.chartPriceLineRemoveTitle), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await _settle(tester);
      expect(_saved(tester), hasLength(1));

      await tester.tapAt(_screenAt(tester, 65000));
      await _settle(tester);
      await tester
          .tap(find.byKey(const ValueKey('hl-price-line-remove-confirm')));
      await _settle(tester);
      expect(_saved(tester), isEmpty);
      expect(_bells, findsNothing);
    });

    testWidgets('a tap away from the line leaves it alone', (tester) async {
      await _open(tester);
      _seed(tester, 65000);
      await _settle(tester);
      await tester.tapAt(_screenAt(tester, 64000));
      await _settle(tester);
      expect(_saved(tester), hasLength(1));
      expect(find.byKey(const ValueKey('hl-price-line-remove-confirm')),
          findsNothing);
    });
  });

  group('in the Chart sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-button')));
      await _settle(tester);
    }

    testWidgets('lists this market only, in the sheet\'s square cards',
        (tester) async {
      await _open(tester);
      _seed(tester, 65000);
      _seed(tester, 64000);
      await _settle(tester);
      await openSheet(tester);

      expect(find.byKey(const ValueKey('hl-chart-group-price-lines')),
          findsOneWidget);
      expect(find.byType(HlPriceLineCard), findsNWidgets(2));
      expect(find.byType(HlPriceLineNewCard), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(HlPriceLineCard).first,
              matching: find.byType(HlSquareBox)),
          findsOneWidget);
    });

    testWidgets('a card\'s button removes the line, Reset does not',
        (tester) async {
      await _open(tester);
      _seed(tester, 65000);
      _seed(tester, 64000);
      await _settle(tester);
      await openSheet(tester);
      final first = _saved(tester).first;

      await tester.tap(find.byKey(const ValueKey('hl-chart-style-candles')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('hl-chart-sheet-reset')));
      await _settle(tester);
      expect(_saved(tester), hasLength(2));

      final remove =
          find.byKey(ValueKey('hl-chart-price-line-remove-${first.id}'));
      await tester.ensureVisible(remove);
      await _settle(tester);
      await tester.tap(remove);
      await _settle(tester);
      expect(_saved(tester).map((l) => l.id), isNot(contains(first.id)));
      expect(find.byType(HlPriceLineCard), findsOneWidget);
    });

    testWidgets('a new line closes the sheet with the tool in hand',
        (tester) async {
      await _open(tester);
      _seed(tester, 65000);
      await _settle(tester);
      await openSheet(tester);
      final add = find.byKey(const ValueKey('hl-chart-price-line-new'));
      await tester.ensureVisible(add);
      await _settle(tester);
      await tester.tap(add);
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-chart-sheet')), findsNothing);
      await tester.tapAt(_screenAt(tester, 64500));
      await _settle(tester);
      expect(_saved(tester), hasLength(2));
      expect(hlEditDrawings(tester), isEmpty);
    });
  });

  group('the quiet snack bar', () {
    late BuildContext ctx;
    late WidgetRef widgetRef;
    late ProviderContainer container;

    Future<void> app(WidgetTester tester) async {
      container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(builder: (context, ref, _) {
                ctx = context;
                widgetRef = ref;
                return const HlPriceLinesHost();
              }),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('says a crossing once, and nothing on load or removal',
        (tester) async {
      await app(tester);
      final notifier = container.read(hlPriceLinesProvider.notifier);
      notifier.add(
          market: hlEditBtc,
          marketKey: hlEditBtcKey,
          level: 65000,
          reference: 66000);
      await tester.pump();
      expect(find.textContaining('reached'), findsNothing);

      notifier.applyLiveTicks({'BTC': 64900}, (c) => c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BTC reached \$65,000'), findsOneWidget);

      // The Sal toast flies in, waits its 3 s, then flies out: frame by
      // frame, as on a phone. After that a second "reached" could only be a
      // second notice.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      notifier.applyLiveTicks({'BTC': 64000}, (c) => c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('reached'), findsNothing);

      notifier.remove(container.read(hlPriceLinesProvider).single.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('reached'), findsNothing);
      await finish(tester);
    });

    testWidgets('several at once take turns', (tester) async {
      await app(tester);
      final notifier = container.read(hlPriceLinesProvider.notifier);
      for (final level in [65000.0, 64000.0]) {
        notifier.add(
            market: hlEditBtc,
            marketKey: hlEditBtcKey,
            level: level,
            reference: 66000);
      }
      notifier.applyLiveTicks({'BTC': 63000}, (c) => c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BTC reached \$65,000'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BTC reached \$64,000'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a level at the price or far away is refused plainly',
        (tester) async {
      await app(tester);
      expect(
          hlPlacePriceLine(ctx, widgetRef,
              market: hlEditBtc,
              marketKey: hlEditBtcKey,
              level: 66000,
              reference: 66000),
          isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('That is the price now'), findsOneWidget);
      expect(
          hlPlacePriceLine(ctx, widgetRef,
              market: hlEditBtc,
              marketKey: hlEditBtcKey,
              level: 900000,
              reference: 66000),
          isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('too far'), findsOneWidget);
      expect(container.read(hlPriceLinesProvider), isEmpty);
      await finish(tester);
    });
  });

  group('the live feed', () {
    test('its frames mark a line, for the market it prices', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(hyperliquidLivePricesProvider, (_, __) {});
      addTearDown(sub.close);
      final feed = container.read(hyperliquidLivePricesProvider.notifier);
      final lines = container.read(hlPriceLinesProvider.notifier);
      lines.add(
          market: hlEditBtc,
          marketKey: hlEditBtcKey,
          level: 65000,
          reference: 66000);

      feed.debugCommitTick('BTC', 65500);
      expect(container.read(hlPriceLinesProvider).single.isReached, isFalse);
      feed.debugCommitTick('ETH', 1);
      expect(container.read(hlPriceLinesProvider).single.isReached, isFalse);
      feed.debugCommitTick('BTC', 64999);
      expect(container.read(hlPriceLinesProvider).single.isReached, isTrue);
    });

    test('a price remembered from before the line never marks it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(hyperliquidLivePricesProvider, (_, __) {});
      addTearDown(sub.close);
      final feed = container.read(hyperliquidLivePricesProvider.notifier);
      feed.debugCommitTick('BTC', 64000);
      container.read(hlPriceLinesProvider.notifier).add(
          market: hlEditBtc,
          marketKey: hlEditBtcKey,
          level: 65000,
          reference: 66000);
      // Another coin's frame carries no new BTC price.
      feed.debugCommitTick('ETH', 1);
      expect(container.read(hlPriceLinesProvider).single.isReached, isFalse);
    });
  });

  test('the copy never promises a notification, in any language', () {
    const keys = [
      'chartToolPriceLine',
      'chartPriceLines',
      'chartPriceLineNew',
      'chartPriceLineNewNote',
      'chartPriceLineAbove',
      'chartPriceLineBelow',
      'chartPriceLineReachedOn',
      'chartPriceLineReachedToast',
      'chartPriceLineLimit',
      'chartPriceLineAtPrice',
      'chartPriceLineTooFar',
      'chartPriceLineRemoveTitle',
      'chartPriceLineRemoveBody',
      'chartPriceLineRemoveCta',
    ];
    final banned = RegExp(
        r'notif|alert|push|benachrichtig|ilmoitu|powiadom|értesít|通知|アラート',
        caseSensitive: false);
    final files = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();
    expect(files, hasLength(23));
    for (final file in files) {
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final key in keys) {
        expect(arb[key], isA<String>(), reason: '$key in ${file.path}');
        expect(banned.hasMatch(arb[key] as String), isFalse,
            reason: '$key in ${file.path}');
      }
    }
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    expect(en['chartPriceLineNewNote'], contains('open'));
  });
}
