import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/portfolio_performance.dart';

PortfolioPnlPoint point(String date, double pnl,
        {double? realized, double? open}) =>
    PortfolioPnlPoint(
      timestamp: DateTime.parse(date),
      pnlUsd: pnl,
      realizedPnlUsd: realized,
      openPnlUsd: open,
    );

void main() {
  test('daily PnL uses the last observation on consecutive UTC dates', () {
    final points = [
      point('2026-09-18T18:30:00Z', 110, realized: 55, open: 40),
      point('2026-09-17T12:00:00Z', 70, realized: 30, open: 20),
      point('2026-09-17T23:30:00Z', 100, realized: 40, open: 50),
      point('2026-09-18T04:00:00Z', 120, realized: 45, open: 70),
      point('2026-09-19T11:00:00Z', 90, realized: 60, open: 20),
    ];
    final data = PortfolioPerformance(
        points: points,
        sourceLabel: 'Venue',
        basisLabel: 'Published P&L',
        coverageLabel: 'All time');
    expect(data.dailyPnl.map((p) => p.pnlUsd), [10, -20]);
    expect(data.dailyPnl.map((p) => p.realizedPnlUsd), [15, 5]);
    expect(data.dailyPnl.map((p) => p.openPnlUsd), [-10, -20]);
    expect(data.dailyPnl.first.timestamp, points.first.timestamp);
    expect(data.dailyPnl.last.timestamp, points.last.timestamp);
  });

  test('first day and missing dates do not invent daily gains or zeroes', () {
    final daily = dailyPortfolioPnl([
      point('2026-09-14T23:00:00Z', 100),
      point('2026-09-16T23:00:00Z', 500),
      point('2026-09-17T23:00:00Z', 500),
      point('2026-09-19T23:00:00Z', 600),
    ]);
    expect(daily, hasLength(1));
    expect(daily.single.pnlUsd, 0); // Both actual observations are equal.
    expect(daily.single.timestamp, DateTime.utc(2026, 9, 17, 23));
    expect(daily.single.realizedPnlUsd, isNull);
    expect(dailyPortfolioPnl([]), isEmpty);
    expect(dailyPortfolioPnl([point('2026-09-19T23:00:00Z', 50)]), isEmpty);
  });

  test('days follow UTC and optional metrics require both observations', () {
    final daily = dailyPortfolioPnl([
      point('2026-09-17T23:30:00-02:00', 50, realized: 40),
      point('2026-09-19T03:00:00+02:00', 70, open: 20),
    ]);
    expect(daily.single.pnlUsd, 20);
    expect(daily.single.realizedPnlUsd, isNull);
    expect(daily.single.openPnlUsd, isNull);
  });

  test('daily calculations reject nonfinite inputs and overflowing differences',
      () {
    expect(() => dailyPortfolioPnl([point('2026-09-17T00:00:00Z', double.nan)]),
        throwsFormatException);
    expect(
        () => dailyPortfolioPnl(
            [point('2026-09-17T00:00:00Z', 0, open: double.infinity)]),
        throwsFormatException);
    expect(
        () => dailyPortfolioPnl([
              point('2026-09-17T00:00:00Z', -1.7e308),
              point('2026-09-18T00:00:00Z', 1.7e308),
            ]),
        throwsFormatException);
  });

  group('current Predictions figures', () {
    PredictionRecord record(String token,
            {bool open = true,
            bool redeemable = false,
            double size = 0,
            double entryCost = 0,
            double price = 0,
            double realized = 0,
            double unrealized = 0,
            DateTime? entered}) =>
        PredictionRecord(
            tokenId: token,
            open: open,
            redeemable: redeemable,
            size: size,
            totalSize: size,
            avgPrice: size == 0 ? 0 : entryCost / size,
            entryCostUsd: entryCost,
            currentPrice: price,
            realizedPnlUsd: realized,
            unrealizedPnlUsd: unrealized,
            firstEntryAt: entered);

    // Series snapshot at 00:00: 10 realised (which already counts the
    // resolved-unclaimed loss below), 2 open, 1 of rebates.
    PortfolioPerformance series(PredictionsBook book) => PortfolioPerformance(
            points: [
              point('2026-10-05T00:00:00Z', 13, realized: 11, open: 2),
            ],
            totalPnlUsd: 13,
            realizedPnlUsd: 11,
            openPnlUsd: 2,
            asOf: DateTime.utc(2026, 10, 5),
            otherPnlUsd: 1,
            sourceLabel: 'Polymarket',
            basisLabel: 'Economic P&L',
            coverageLabel: 'All time')
        .withPredictions(book);

    final records = [
      // Closed: sold and claimed.
      record('won', open: false, realized: 15),
      record('sold', open: false, realized: -2),
      // Resolved, not claimed: a 3 loss, counted once as realised.
      record('lost', redeemable: true, size: 6, entryCost: 3, unrealized: -3),
      // Live: 10 shares bought for 4, 1 realised on a partial sell.
      record('live', size: 10, entryCost: 4, price: .5, realized: 1,
          unrealized: 1),
    ];

    test('are rebuilt from the positions, each counted once', () {
      final data = series(PredictionsBook(records: records))
          .withLivePredictions(const {'live': .7},
              at: DateTime.utc(2026, 10, 5, 12));
      // 15 − 2 − 3 + 1 realised, + 1 other.
      expect(data.realizedPnlUsd, closeTo(12, 1e-9));
      // 10 × 0.70 − 4 at the live price.
      expect(data.openPnlUsd, closeTo(3, 1e-9));
      expect(data.totalPnlUsd, closeTo(15, 1e-9));
      expect(data.points.last.pnlUsd, data.totalPnlUsd);
      expect(data.points, hasLength(2));
    });

    test('fall back to the Data API price without a live one', () {
      final data = series(PredictionsBook(records: records))
          .withLivePredictions(const {}, at: DateTime.utc(2026, 10, 5, 12));
      expect(data.openPnlUsd, closeTo(1, 1e-9));
    });

    test('a cut list keeps the series realised figure, plus what is new', () {
      final data = series(PredictionsBook(
          records: [
            ...records,
            record('today', open: false, realized: 4,
                entered: DateTime.utc(2026, 10, 5, 9)),
          ],
          complete: false,
          coversFrom: DateTime.utc(2026, 9)))
          .withLivePredictions(const {}, at: DateTime.utc(2026, 10, 5, 12));
      expect(data.realizedPnlUsd, closeTo(15, 1e-9));
      expect(data.openPnlUsd, closeTo(1, 1e-9));
    });

    test('Investing has no positions and is left as published', () {
      const hl = PortfolioPerformance(
          points: [],
          sourceLabel: 'Hyperliquid',
          basisLabel: 'P&L',
          coverageLabel: 'All time');
      expect(identical(hl.withLivePredictions(const {}), hl), isTrue);
    });
  });

  group('range view', () {
    final data = PortfolioPerformance(
        points: [
          point('2026-09-10T00:00:00Z', 5, realized: 5),
          point('2026-09-20T00:00:00Z', 8, realized: 6),
          point('2026-09-28T00:00:00Z', 12, realized: 9),
          point('2026-10-05T10:00:00Z', 7, realized: 4),
        ],
        sourceLabel: 'Venue',
        basisLabel: 'P&L',
        coverageLabel: 'All time');

    test('starts at the last observation at or before the range', () {
      final week = data.rangeView(const Duration(days: 7));
      expect(week.start, DateTime.utc(2026, 9, 28, 10));
      expect(week.points.map((p) => p.pnlUsd), [12, 7]);
      expect(week.changeUsd, -5);
      expect(week.realizedChangeUsd, -5);
      final month = data.rangeView(const Duration(days: 30));
      expect(month.points.map((p) => p.pnlUsd), [0, 5, 8, 12, 7]);
      expect(month.changeUsd, 7);
    });

    test('all time starts from zero and ends on the headline', () {
      final all = data.rangeView(null);
      expect(all.points.first.pnlUsd, 0);
      expect(all.points.first.timestamp, DateTime.utc(2026, 9, 9));
      expect(all.points.last.pnlUsd, 7);
      expect(all.changeUsd, 7);
      expect(all.start, isNull);
      expect(const PortfolioPerformance(
              points: [],
              sourceLabel: 'Venue',
              basisLabel: 'P&L',
              coverageLabel: 'None')
          .rangeView(null)
          .points, isEmpty);
    });
  });
}
