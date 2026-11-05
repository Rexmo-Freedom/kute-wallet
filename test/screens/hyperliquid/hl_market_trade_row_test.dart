// The Investing market page's foot (founder, 4 November 2026: "I do not
// like the Send to a friend on the top right ... It must be a floating
// button"; "On the Invest and Short ... it should be the same"): no
// pinned Invest row and no Send to a friend pill beside the price. The
// floating bar is the trade row (kute_bar_context.dart, THE TRADE ROW):
// Invest and Short in the market's colours, taps landing on each and
// running the order slip's path (hl_invest_cta_tapped, buy / sell), the
// round Sal button at the end; the page scrolls clear of it; the chart
// editor takes it away and Done brings it back.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/screens/hyperliquid/components/hl_watch_star.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';
import '../../helpers/shell_bar_harness.dart';

Finder _trade(String id) => find.byKey(ValueKey('kute-bar-trade-$id'));
final Finder _share = find.byKey(const ValueKey('kute-bar-share'));

/// Whether a tap at [finder]'s centre reaches its render box.
bool _tapLands(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == box);
}

Future<void> _pump(WidgetTester tester) async {
  installShellBar();
  await pumpHlEditSheet(tester, appBuilder: shellBarBuilder);
  await pumpBar(tester);
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(() {
    // The order slip a tap opens reads its boxes.
    Hive.init(Directory.systemTemp.createTempSync('hl-trade-row').path);
  });
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'the bar is Invest | Short with the round Sal button; nothing to '
      'share in the header or beside the price', (tester) async {
    await _pump(tester);
    expect(_trade('invest'), findsOneWidget);
    expect(_trade('short'), findsOneWidget);
    expect(_share, findsOneWidget);
    expect(find.text('Invest'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(
        (tester.widget<Container>(_trade('invest')).decoration!
                as BoxDecoration)
            .color,
        AppColors.marketUp);
    expect(
        (tester.widget<Container>(_trade('short')).decoration!
                as BoxDecoration)
            .color,
        AppColors.marketDown);
    // One row at the foot: Invest, Short, Sal.
    final invest = tester.getRect(_trade('invest'));
    final short = tester.getRect(_trade('short'));
    final share = tester.getRect(_share);
    expect(invest.right, lessThan(short.left));
    expect(short.right, lessThan(share.left));
    expect(invest.width, greaterThan(short.width));
    expect(share.bottom, greaterThan(844 - 60));
    // Nothing of the old foot or the old header pill.
    expect(find.byKey(const ValueKey('kute-sal-header-button')), findsNothing);
    expect(find.text('Send to a friend'), findsNothing);
    // The header: back, logo, title, star, with the star at the row's end.
    final header = find
        .ancestor(
            of: find.byType(KuteCircleBackButton), matching: find.byType(Row))
        .first;
    expect(find.descendant(of: header, matching: find.byType(HlWatchStar)),
        findsOneWidget);
    // The price may take the row's whole width (no pill beside it).
    final price = find.byKey(const ValueKey('hl-detail-price'));
    final fitted = find.ancestor(of: price, matching: find.byType(FittedBox));
    expect(tester.renderObject<RenderBox>(fitted.first).constraints.maxWidth,
        moreOrLessEquals(390 - 2 * 20 * 390 / 430, epsilon: 1));
    // The page's own context: a trade row, its Sal sheet the market's.
    final ctx = scopeContext(tester,
        within: find.byType(HlMarketDetailSheet));
    expect(ctx.isTrade, isTrue);
    expect(ctx.share!.barContext!.market, isTrue);
    expect(ctx.share!.brag, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final (id, side) in [('invest', 'buy'), ('short', 'sell')]) {
    testWidgets(
        'a tap lands on $id and takes the order slip\'s path ($side)',
        (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _pump(tester);
      expect(_tapLands(tester, _trade(id)), isTrue);
      expect(_tapLands(tester, _share), isTrue);
      await tester.tap(_trade(id));
      await tester.pump();
      final taps =
          events.where((e) => e.$1 == 'hl_invest_cta_tapped').toList();
      expect(taps, hasLength(1));
      expect(taps.single.$2!['side'], side);
      expect(taps.single.$2!['source'], 'market_detail');
      expect(taps.single.$2!['kind'], 'perp');
      // The slip itself is its own tests' (order_slip_*_test.dart).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('scrolled to the end, About sits above the floating row',
      (tester) async {
    await _pump(tester);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -3000));
    await tester.pump(const Duration(milliseconds: 800));
    final about = find.textContaining('About');
    expect(about, findsWidgets);
    final rowTop = tester.getRect(_trade('invest')).top;
    expect(tester.getRect(about.last).bottom, lessThan(rowTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chart editor takes the row away; Done brings it back',
      (tester) async {
    await _pump(tester);
    expect(barIsUp(tester), isTrue);
    await enterHlEdit(tester);
    await pumpBar(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(barIsUp(tester), isFalse);
    await tester.tap(find.text('Done').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await pumpBar(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(barIsUp(tester), isTrue);
    expect(_trade('invest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
