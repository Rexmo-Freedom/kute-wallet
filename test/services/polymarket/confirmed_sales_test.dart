// A Predictions sale against the Data API's lagging reads
// (confirmed_sales.dart), and the Portfolio's P&L against the same lag.
//
// Founder report (2026-11-01, live account): $4.24 on No (4.99 shares at
// ~85¢) in "Will Alexandria Ocasio-Cortez win the 2028 Democratic
// presidential nomination?", then sold ("Sold · No +$4.14"). The Portfolio
// kept listing the prediction as open, with a ~99% chance, and showed more
// profit than he made, until the Data API caught up.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/services/polymarket/confirmed_sales.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

const _wallet = '0x00000000000000000000000000000000000000aa';
const _no = 'aoc-no';
const _other = 'other-token';

Position _row(String token, double size,
        {double price = .85, double avg = .85, bool redeemable = false}) =>
    Position(
      proxyWallet: _wallet,
      asset: token,
      conditionId: '0xc0nd-$token',
      size: size,
      avgPrice: avg,
      initialValue: size * avg,
      currentValue: size * price,
      cashPnl: size * (price - avg),
      percentPnl: avg > 0 ? (price / avg - 1) * 100 : 0,
      totalBought: size,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: price,
      redeemable: redeemable,
      title: 'Will Alexandria Ocasio-Cortez win the 2028 Democratic '
          'presidential nomination?',
      slug: 'aoc-2028',
      eventSlug: 'democratic-presidential-nominee-2028',
      outcome: 'No',
      outcomeIndex: 1,
      oppositeOutcome: 'Yes',
      oppositeAsset: 'aoc-yes',
    );

final _soldAt = DateTime.utc(2026, 11, 1, 12);

PolymarketConfirmedSale _sale({
  double sold = 4.99,
  double held = 4.99,
  double? proceeds = 4.14,
  double? cost = 4.24,
}) =>
    newConfirmedSale(
      wallet: _wallet,
      tokenId: _no,
      soldShares: sold,
      heldShares: held,
      now: _soldAt,
      proceedsUsd: proceeds,
      costUsd: cost,
    )!;

PredictionRecord _record(String token,
        {bool open = true,
        bool redeemable = false,
        double size = 0,
        double entryCost = 0,
        double price = 0,
        double realized = 0,
        double unrealized = 0,
        DateTime? lastEvent}) =>
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
      lastEventAt: lastEvent,
    );

/// The series as the account read it before the bet (nothing made yet),
/// with [book] as its positions.
PortfolioPerformance _series(PredictionsBook book) => PortfolioPerformance(
      points: [
        PortfolioPnlPoint(timestamp: DateTime.utc(2026, 11, 1), pnlUsd: 0,
            realizedPnlUsd: 0, openPnlUsd: 0),
      ],
      totalPnlUsd: 0,
      realizedPnlUsd: 0,
      openPnlUsd: 0,
      asOf: DateTime.utc(2026, 11, 1),
      otherPnlUsd: 0,
      sourceLabel: 'Polymarket',
      basisLabel: 'Economic P&L',
      coverageLabel: 'All time',
    ).withPredictions(book);

void main() {
  group('the positions list after a filled sale', () {
    test('a sale of all of it drops every pre-sale row, read after read',
        () {
      final sales = [_sale()];
      // The read right after the fill still has the pre-sale row; one read
      // later it is gone; the next (another node of the Data API) brings
      // it back, now marked at a resolved-looking 99¢.
      final reads = [
        [_row(_no, 4.99), _row(_other, 10)],
        [_row(_other, 10)],
        [_row(_no, 4.99, price: .99), _row(_other, 10)],
      ];
      for (final read in reads) {
        final shown = applyConfirmedSales(read, sales);
        expect(shown.map((p) => p.asset), [_other]);
      }
    });

    test('Sell Max leaves dust: the sale closes the position', () {
      final sale = _sale(sold: 4.96);
      expect(sale.closesPosition, isTrue);
      expect(sale.remainingShares, 0);
      expect(applyConfirmedSales([_row(_no, 4.99)], [sale]), isEmpty);
    });

    test('a partial sale shrinks a stale row to what is left', () {
      final sale = _sale(sold: 2, held: 4.99, proceeds: 1.66, cost: 1.7);
      final shown = applyConfirmedSales([_row(_no, 4.99)], [sale]);
      expect(shown.single.size, closeTo(2.99, 1e-9));
      expect(shown.single.initialValue, closeTo(2.99 * .85, 1e-9));
      expect(shown.single.avgPrice, .85);
      // A read that already shows the sale is left as it is.
      final caughtUp = _row(_no, 2.99);
      expect(identical(applyConfirmedSales([caughtUp], [sale]).single,
          caughtUp), isTrue);
    });

    test('a row larger than the pre-sale holding has new shares and stands',
        () {
      final bigger = _row(_no, 9.99);
      expect(applyConfirmedSales([bigger], [_sale()]).single, same(bigger));
    });

    test('a sale is held for its window and for its wallet only', () {
      final sale = _sale();
      expect(liveConfirmedSales([sale], _wallet.toUpperCase(),
          _soldAt.add(const Duration(minutes: 9))), [sale]);
      expect(liveConfirmedSales(
          [sale], _wallet, _soldAt.add(const Duration(minutes: 11))), isEmpty);
      expect(liveConfirmedSales([sale], '0xbb', _soldAt), isEmpty);
      expect(liveConfirmedSales([sale], null, _soldAt), isEmpty);
    });
  });

  group('the P&L after a filled sale', () {
    // Before the sale: $4.24 for 4.99 shares of No.
    final preSale = _record(_no, size: 4.99, entryCost: 4.24, price: .85);
    final held = _record(_other, size: 10, entryCost: 5, price: .5);

    test(
        'the founder\'s case: a pre-sale row at 99¢ counts only the realised '
        'loss of the sale', () {
      // Without the sale, the stale row is valued at the live 99¢ as open
      // profit: +0.70, where the sale realised -0.10.
      final stale = _series(PredictionsBook(records: [preSale, held]))
          .withLivePredictions(const {_no: .99, _other: .5});
      expect(stale.totalPnlUsd, closeTo(4.99 * .99 - 4.24, 1e-9));

      final book = bookWithConfirmedSales(
          PredictionsBook(records: [preSale, held]), [_sale()]);
      final data =
          _series(book).withLivePredictions(const {_no: .99, _other: .5});
      expect(data.realizedPnlUsd, closeTo(4.14 - 4.24, 1e-9));
      expect(data.openPnlUsd, closeTo(0, 1e-9));
      expect(data.totalPnlUsd, closeTo(-0.10, 1e-9));
      // The sold token is closed, never open.
      final no = book.records.singleWhere((r) => r.tokenId == _no);
      expect(no.open, isFalse);
      expect(no.size, 0);
    });

    test('a partial sale: the shares sold realised, the rest open', () {
      final book = bookWithConfirmedSales(PredictionsBook(records: [preSale]),
          [_sale(sold: 2, proceeds: 1.66, cost: 2 * 4.24 / 4.99)]);
      final data = _series(book).withLivePredictions(const {_no: .9});
      final soldCost = 4.24 * 2 / 4.99;
      expect(data.realizedPnlUsd, closeTo(1.66 - soldCost, 1e-9));
      expect(data.openPnlUsd, closeTo(2.99 * .9 - (4.24 - soldCost), 1e-9));
    });

    test('a token listed both open (pre-sale) and closed counts once', () {
      final closed = _record(_no,
          open: false,
          realized: -0.10,
          lastEvent: DateTime.utc(2026, 11, 1, 12, 0, 5));
      final openStale = _record(_no,
          size: 4.99,
          entryCost: 4.24,
          price: .99,
          lastEvent: DateTime.utc(2026, 11, 1, 11, 58));
      final data = _series(PredictionsBook(records: [openStale, closed]))
          .withLivePredictions(const {_no: .99});
      expect(data.realizedPnlUsd, closeTo(-0.10, 1e-9));
      expect(data.openPnlUsd, 0);
      // And with the sale recorded too: still once.
      final book = bookWithConfirmedSales(
          PredictionsBook(records: [openStale, closed]), [_sale()]);
      final held = _series(book).withLivePredictions(const {_no: .99});
      expect(held.realizedPnlUsd, closeTo(-0.10, 1e-9));
      expect(held.openPnlUsd, 0);
    });

    test('a sale the book does not list yet still realises its loss', () {
      final book =
          bookWithConfirmedSales(PredictionsBook(records: [held]), [_sale()]);
      final data = _series(book).withLivePredictions(const {_other: .5});
      expect(data.realizedPnlUsd, closeTo(-0.10, 1e-9));
      expect(data.openPnlUsd, closeTo(0, 1e-9));
    });

    test('a book that already shows the sale is left as the venue said', () {
      final caughtUp = PredictionsBook(records: [
        _record(_no, open: false, realized: -0.10),
        held,
      ]);
      expect(identical(bookWithConfirmedSales(caughtUp, [_sale()]), caughtUp),
          isTrue);
    });

    test('without the venue\'s proceeds the shares sold count in neither', () {
      final book = bookWithConfirmedSales(
          PredictionsBook(records: [preSale]), [_sale(proceeds: null)]);
      final data = _series(book).withLivePredictions(const {_no: .99});
      expect(data.realizedPnlUsd, 0);
      expect(data.openPnlUsd, 0);
    });

    test('a dust remainder is closed: never valued at a price', () {
      final dust = _record(_no,
          size: 0.004, entryCost: 0.0034, price: .99, realized: -0.10);
      final data = _series(PredictionsBook(records: [dust]))
          .withLivePredictions(const {_no: .99});
      expect(data.realizedPnlUsd, closeTo(-0.10, 1e-9));
      expect(data.openPnlUsd, 0);
    });

    test('a resolved market\'s sold position is never open at 99¢', () {
      // Sold before the result; the market then resolved and the Data API
      // still lists the pre-sale row at 99¢ (not redeemable for us).
      final resolvedStale =
          _record(_no, size: 4.99, entryCost: 4.24, price: .99);
      final book = bookWithConfirmedSales(
          PredictionsBook(records: [resolvedStale]), [_sale()]);
      final data = _series(book).withLivePredictions(const {});
      expect(data.openPnlUsd, 0);
      expect(data.realizedPnlUsd, closeTo(-0.10, 1e-9));
    });
  });
}
