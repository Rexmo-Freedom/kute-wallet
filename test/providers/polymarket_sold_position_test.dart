// A sold prediction through the real trading notifier, the positions
// providers and the Portfolio's P&L provider, with the Data API's lagging
// reads played by hand.
//
// Founder report (2026-11-01, live account): $4.24 on No (4.99 shares at
// ~85¢), then sold ("Sold · No +$4.14"). The Portfolio still listed the
// prediction as open with a ~99% chance, and its P&L showed more profit
// than he made, until the Data API caught up. Cause: the sell sheet
// confirms a sale by the positions read no longer listing the row; the
// optimistic removal then found no row and recorded nothing, and the old
// marker ended on the first read without the row anyway, so the next
// lagging read put the pre-sale row back as open, valued at its live price.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider, polymarketClaimablePositionsProvider,
        polymarketResolvedPositionsProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Position;

const _wallet = '0x00000000000000000000000000000000000000aa';
const _no = 'aoc-no';

class _Pm extends PolymarketTradingNotifier {
  _Pm(this._state);

  final PolymarketTradingState _state;

  @override
  Future<PolymarketTradingState> build() async => _state;
}

Position _row(double size, {double price = .85, bool redeemable = false}) =>
    Position(
      proxyWallet: _wallet,
      asset: _no,
      conditionId: '0xc0nd',
      size: size,
      avgPrice: .85,
      initialValue: size * .85,
      currentValue: size * price,
      cashPnl: size * (price - .85),
      percentPnl: (price / .85 - 1) * 100,
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

PolymarketTradingState _state(List<Position> positions) =>
    PolymarketTradingState(
      isAuthenticated: true,
      usdcBalance: 10,
      openPositions: positions,
      walletAddress: '0x00000000000000000000000000000000000000ee',
      proxyWalletAddress: _wallet,
    );

const _predictions =
    PortfolioPerformanceRequest(venue: PortfolioPerformanceVenue.predictions);

/// The Data API's book as read before the sale: the bet open, nothing
/// realised yet.
final _bookBeforeSale = PortfolioPerformance(
  points: [
    PortfolioPnlPoint(
        timestamp: DateTime.utc(2026, 11, 1),
        pnlUsd: 0,
        realizedPnlUsd: 0,
        openPnlUsd: 0),
  ],
  totalPnlUsd: 0,
  realizedPnlUsd: 0,
  openPnlUsd: 0,
  asOf: DateTime.utc(2026, 11, 1),
  otherPnlUsd: 0,
  sourceLabel: 'Polymarket',
  basisLabel: 'Economic P&L',
  coverageLabel: 'All time',
  predictions: const PredictionsBook(records: [
    PredictionRecord(
      tokenId: _no,
      open: true,
      redeemable: false,
      size: 4.99,
      totalSize: 4.99,
      avgPrice: 4.24 / 4.99,
      entryCostUsd: 4.24,
      currentPrice: .85,
      realizedPnlUsd: 0,
      unrealizedPnlUsd: 0,
    ),
  ]),
);

ProviderContainer _container(List<Position> positions) => ProviderContainer(
      overrides: [
        polymarketTradingProvider.overrideWith(() => _Pm(_state(positions))),
        portfolioPerformanceProvider
            .overrideWith((ref, request) async => _bookBeforeSale),
      ],
    );

PolymarketTradingNotifier _notifier(ProviderContainer c) =>
    c.read(polymarketTradingProvider.notifier);

void main() {
  test(
      'buy, sell, then lagging reads: the sold prediction is never open '
      'again and the P&L is the realised loss only', () async {
    final c = _container([_row(4.99)]);
    addTearDown(c.dispose);
    await c.read(polymarketTradingProvider.future);
    c.listen(polymarketActivePositionsProvider, (_, __) {});
    expect(c.read(polymarketActivePositionsProvider), hasLength(1));

    _notifier(c).markSoldOptimistically(
        tokenId: _no, sharesSold: 4.99, heldShares: 4.99, proceedsUsd: 4.14);
    expect(c.read(polymarketActivePositionsProvider), isEmpty);

    // The Data API before it catches up: the pre-sale row, then no row,
    // then the pre-sale row again at a resolved-looking 99¢.
    for (final read in [
      [_row(4.99)],
      <Position>[],
      [_row(4.99, price: .99)],
    ]) {
      _notifier(c).debugApplyPositionsRead(read);
      expect(c.read(polymarketActivePositionsProvider), isEmpty);
      expect(c.read(polymarketClaimablePositionsProvider), isEmpty);
      expect(c.read(polymarketTradingProvider).requireValue.openPositions,
          isEmpty);
    }

    // The P&L, from the book read before the sale, at a live 99¢.
    c.listen(portfolioPerformanceDisplayProvider(_predictions), (_, __) {});
    await c.read(portfolioPerformanceProvider(_predictions).future);
    final shown = c
        .read(portfolioPerformanceDisplayProvider(_predictions))
        .requireValue
        .withLivePredictions(const {_no: .99});
    expect(shown.realizedPnlUsd, closeTo(4.14 - 4.24, 1e-9));
    expect(shown.openPnlUsd, closeTo(0, 1e-9));
    expect(shown.totalPnlUsd, closeTo(-0.10, 1e-9));
  });

  test(
      'a sale confirmed by the row disappearing is still held against a '
      'later lagging read', () async {
    final c = _container([_row(4.99)]);
    addTearDown(c.dispose);
    await c.read(polymarketTradingProvider.future);
    c.listen(polymarketActivePositionsProvider, (_, __) {});

    // The sheet's position-moved check saw the row gone before the
    // receipt: the state no longer lists it when the sale is recorded.
    _notifier(c).debugApplyPositionsRead(const []);
    _notifier(c).markSoldOptimistically(
        tokenId: _no, sharesSold: 4.99, heldShares: 4.99, proceedsUsd: 4.14);
    expect(c.read(polymarketTradingProvider).requireValue.confirmedSales,
        hasLength(1));

    _notifier(c).debugApplyPositionsRead([_row(4.99)]);
    expect(c.read(polymarketActivePositionsProvider), isEmpty);
  });

  test('a partial sale leaves the rest open, a stale read does not restore it',
      () async {
    final c = _container([_row(4.99)]);
    addTearDown(c.dispose);
    await c.read(polymarketTradingProvider.future);
    c.listen(polymarketActivePositionsProvider, (_, __) {});

    _notifier(c).markSoldOptimistically(
        tokenId: _no, sharesSold: 2, heldShares: 4.99, proceedsUsd: 1.66);
    _notifier(c).debugApplyPositionsRead([_row(4.99)]);
    final open = c.read(polymarketActivePositionsProvider);
    expect(open.single.size, closeTo(2.99, 1e-9));
  });

  test('a dust remainder is never listed, open or resolved', () async {
    final c = _container([_row(0.004, price: .99), _row(0.004, price: 1,
        redeemable: true)]);
    addTearDown(c.dispose);
    await c.read(polymarketTradingProvider.future);
    expect(c.read(polymarketActivePositionsProvider), isEmpty);
    expect(c.read(polymarketClaimablePositionsProvider), isEmpty);
    expect(c.read(polymarketResolvedPositionsProvider), isEmpty);
  });

  test('a new buy of the sold token shows again at once', () async {
    final c = _container([_row(4.99)]);
    addTearDown(c.dispose);
    await c.read(polymarketTradingProvider.future);
    c.listen(polymarketActivePositionsProvider, (_, __) {});

    _notifier(c).markSoldOptimistically(
        tokenId: _no, sharesSold: 4.99, heldShares: 4.99, proceedsUsd: 4.14);
    _notifier(c).notePendingFill(
        key: 'rebuy', tokenId: _no, shares: 3, costUsd: 2.55);
    expect(c.read(polymarketTradingProvider).requireValue.confirmedSales,
        isEmpty);
    _notifier(c).debugApplyPositionsRead([_row(3)]);
    expect(c.read(polymarketActivePositionsProvider).single.size, 3);
  });
}
