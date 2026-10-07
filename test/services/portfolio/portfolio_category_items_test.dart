import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/portfolio/portfolio_category_drill.dart';
import 'package:kute/services/portfolio/portfolio_categories.dart';
import 'package:kute/services/portfolio/portfolio_category_items.dart';
import 'package:kute/theme/app_theme.dart';

PredictionRecord _record(String token,
        {String event = '',
        String slug = '',
        String market = '',
        String title = '',
        bool open = false,
        bool redeemable = false,
        double size = 0,
        double totalSize = 10,
        double avgPrice = .5,
        double price = 0,
        double realized = 0,
        double unrealized = 0}) =>
    PredictionRecord(
        tokenId: token,
        open: open,
        redeemable: redeemable,
        size: size,
        totalSize: totalSize,
        avgPrice: avgPrice,
        entryCostUsd: size * avgPrice,
        currentPrice: price,
        realizedPnlUsd: realized,
        unrealizedPnlUsd: unrealized,
        conditionId: market,
        title: title,
        slug: slug,
        eventSlug: event);

HlFill _fill(int id, double before, double size, String side,
        {double px = 100,
        double pnl = 0,
        double fee = 1,
        bool position = true}) =>
    HlFill.fromJson({
      'coin': 'ETH',
      'tid': '$id',
      'oid': id,
      'hash': 'h$id',
      'time': id * 1000,
      if (position) 'startPosition': '$before',
      'sz': '$size',
      'px': '$px',
      'side': side,
      'closedPnl': '$pnl',
      'fee': '$fee',
      'feeToken': 'USDC',
      'dir': '',
    });

void main() {
  group('Predictions events', () {
    test(
        'records group by event (else market slug, condition, token), '
        'largest first; nothing worth nothing', () {
      final items = predictionEventItems([
        _record('a', event: 'e1', title: 'A', totalSize: 10),
        _record('b', event: 'e1', title: 'B', totalSize: 30),
        _record('c', slug: 'm2', title: 'C', totalSize: 60),
        _record('d', market: '0xd', title: 'D', totalSize: 4),
        _record('e', title: 'E', totalSize: 0),
      ], (r) => r.stakeUsd);
      expect([for (final i in items) i.key], ['m2', 'e1', '0xd']);
      expect([for (final i in items) i.value], [30, 20, 2]);
      // Within an event, the largest record first; the title is its.
      expect([for (final r in items[1].records) r.tokenId], ['b', 'a']);
      expect(items[1].title, 'B');
    });

    test('a position\'s result, by the Activity\'s rule', () {
      expect(predictionLineResult(_record('o', open: true, size: 1)),
          PredictionLineResult.open);
      // Held while the market resolved: priced 1 won, 0 lost.
      expect(
          predictionLineResult(
              _record('r', open: true, redeemable: true, size: 10, price: 1)),
          PredictionLineResult.won);
      expect(
          predictionLineResult(
              _record('r', open: true, redeemable: true, size: 10, price: 0)),
          PredictionLineResult.lost);
      // Resolved but priced at neither: price alone never decides it.
      expect(
          predictionLineResult(_record('r',
              open: true, redeemable: true, size: 10, price: .6)),
          PredictionLineResult.open);
      // Dust a sale left on a resolved market is no result.
      expect(
          predictionLineResult(_record('r',
              open: true, redeemable: true, size: .004, price: 0)),
          PredictionLineResult.sold);
      // 10 shares at 0.50, claimed at 1: +5.
      expect(predictionLineResult(_record('w', price: 1, realized: 5)),
          PredictionLineResult.won);
      // All 5 put in lost.
      expect(predictionLineResult(_record('l', realized: -5)),
          PredictionLineResult.lost);
      // Sold at 0.70: +2, whatever the market did after.
      expect(predictionLineResult(_record('s', price: 1, realized: 2)),
          PredictionLineResult.sold);
      // Sold at 0.90 before the side lost: sold, not lost.
      expect(predictionLineResult(_record('s', price: 0, realized: 4)),
          PredictionLineResult.sold);
      // Left while the market still traded.
      expect(predictionLineResult(_record('s', price: .4, realized: -1)),
          PredictionLineResult.sold);
      expect(
          predictionLineRealizedUsd(_record('r',
              open: true, redeemable: true, realized: -1, unrealized: 6)),
          5);
    });
  });

  group('Investing round trips', () {
    test(
        'flat to flat, net of fees; a reversal closes the trip; the '
        'open one last; newest first', () {
      final trips = tradingRoundTrips([
        _fill(1, 0, 1, 'B', pnl: 0),
        _fill(2, 1, 1, 'A', px: 110, pnl: 10),
        // Short 2, then a buy of 3 reverses to long 1.
        _fill(3, 0, 2, 'A'),
        _fill(4, -2, 3, 'B', px: 90, pnl: 20),
        _fill(5, 1, 0.5, 'A', pnl: 1),
      ]);
      expect(trips.length, 3);
      final [open, short, long] = trips;
      expect(long.long, isTrue);
      expect(long.closedAt, 2000);
      expect(long.realizedUsd, 8);
      expect(long.volumeUsd, 210);
      expect(short.long, isFalse);
      expect(short.closedAt, 4000);
      expect(short.realizedUsd, 18);
      expect(open.open, isTrue);
      expect(open.long, isTrue);
      expect(open.realizedUsd, 0);
      // Every fill's P&L and fee in exactly one trip.
      expect(trips.fold<double>(0, (s, t) => s + t.realizedUsd), 26);
    });

    test('a fill that does not say its position is a trip of its own', () {
      final trips = tradingRoundTrips([
        _fill(1, 0, 1, 'B', position: false),
        _fill(2, 0, 1, 'A', pnl: 3, position: false),
      ]);
      expect(trips.length, 2);
      expect(trips.every((t) => !t.open), isTrue);
    });

    test('coins by amount, largest first', () {
      final items = tradingCoinItems<(String, double)>(
          [('BTC', 5), ('ETH', 9), ('BTC', 6), ('SOL', 0)],
          coinOf: (e) => e.$1, amount: (e) => e.$2);
      expect([for (final i in items) i.coin], ['BTC', 'ETH']);
      expect(items.first.value, 11);
    });
  });

  test('a category falls in its own slice, else Other', () {
    final slices = categorySlices({
      'a': 50,
      'b': 40,
      'c': 30,
      'd': 20,
      'e': 10,
      'f': 5,
      'g': 1,
      kPortfolioOtherCategory: 1,
    });
    String label(String k) => k;
    expect(categorySliceKeyOf('a', slices, label), 'a');
    expect(categorySliceKeyOf('g', slices, label), kPortfolioOtherCategory);
    expect(categorySliceKeyOf(kPortfolioOtherCategory, slices, label),
        kPortfolioOtherCategory);
  });

  testWidgets('ten items, then See all; ten lines, then See all',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CategoryDrillList(
                params: const {},
                items: [
                  for (var i = 0; i < 12; i++)
                    CategoryDrillItem(
                      key: 'i$i',
                      leading: const SizedBox(),
                      title: Text('Item $i'),
                      share: '',
                      amount: '\$$i',
                      lines: () => [
                        for (var j = 0; j < 12; j++)
                          CategoryDrillLine(
                              key: 'i$i-l$j',
                              kind: 'open',
                              title: 'Line $j',
                              caption: '',
                              figure: '\$$j'),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Item 9'), findsOneWidget);
    expect(find.text('Item 10'), findsNothing);
    await tester
        .ensureVisible(find.byKey(const ValueKey('category-drill-see-all')));
    await tester.tap(find.byKey(const ValueKey('category-drill-see-all')));
    await tester.pumpAndSettle();
    expect(find.text('Item 11'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-drill-see-all')), findsNothing);

    await tester.ensureVisible(find.text('Item 0'));
    await tester.tap(find.text('Item 0'));
    await tester.pumpAndSettle();
    expect(find.text('Line 9'), findsOneWidget);
    expect(find.text('Line 10'), findsNothing);
    await tester.ensureVisible(
        find.byKey(const ValueKey('category-drill-lines-see-all-i0')));
    await tester
        .tap(find.byKey(const ValueKey('category-drill-lines-see-all-i0')));
    await tester.pumpAndSettle();
    expect(find.text('Line 11'), findsOneWidget);
  });
}
