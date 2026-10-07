// A prediction's result comes from its resolved market: a lost one is
// never claimed, so the venue's history alone never says it lost.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/prediction_results.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart'
    show Activity, ClosedPosition, Position;
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/screens/shared/activity_row_copy.dart';

final _en = l10nForLanguage('en');

const _round = 'Bitcoin Up or Down - October 5, 7:00AM-7:05AM ET';
const _cid = '0xround';
const _up = 'tok-up';
const _betAt = 1759662180; // the Up prediction, 12:03

Activity _trade(String side,
        {required double usdc,
        required double size,
        int at = _betAt,
        String cid = _cid,
        String token = _up}) =>
    Activity(
      proxyWallet: '0xsafe',
      timestamp: at,
      conditionId: cid,
      type: 'TRADE',
      size: size,
      usdcSize: usdc,
      transactionHash: '0x$side$at',
      asset: token,
      side: side,
      outcomeIndex: 0,
      title: _round,
      outcome: 'Up',
    );

Position _held({
  required double curPrice,
  required double size,
  required double cost,
  bool redeemable = true,
  String cid = _cid,
  String token = _up,
  String? endDate = '2026-10-05T11:05:00Z',
}) =>
    Position(
      proxyWallet: '0xsafe',
      asset: token,
      conditionId: cid,
      size: size,
      avgPrice: cost / size,
      initialValue: cost,
      currentValue: size * curPrice,
      cashPnl: size * curPrice - cost,
      percentPnl: 0,
      totalBought: size,
      realizedPnl: 0,
      percentRealizedPnl: 0,
      curPrice: curPrice,
      redeemable: redeemable,
      title: _round,
      slug: 'btc-updown-5m',
      eventSlug: '',
      outcome: 'Up',
      outcomeIndex: 0,
      oppositeOutcome: 'Down',
      oppositeAsset: 'tok-down',
      endDate: endDate,
    );

ClosedPosition _settled({
  required bool won,
  required double size,
  required double avgPrice,
  required double realized,
  DateTime? resolvedAt,
}) =>
    ClosedPosition(
      proxyWallet: '0xsafe',
      asset: _up,
      conditionId: _cid,
      size: size,
      avgPrice: avgPrice,
      initialValue: size * avgPrice,
      payout: size * avgPrice + realized,
      cashPnl: realized,
      percentPnl: 0,
      title: _round,
      slug: 'btc-updown-5m',
      eventSlug: '',
      outcome: 'Up',
      outcomeIndex: 0,
      won: won,
      resolutionDate: resolvedAt,
    );

final _now = DateTime.utc(2026, 10, 7);

void main() {
  group('a lost prediction', () {
    // The owner's Bitcoin 7:00–7:05 Up bet: $3.21 staked, lost, never
    // claimed. Its only record is the buy.
    final buy = _trade('BUY', usdc: 3.21, size: 6.3);

    test('held while its market resolved against it reads Lost, −stake', () {
      final results = predictionResults(
        open: [_held(curPrice: 0, size: 6.3, cost: 3.21)],
        closed: const [],
        history: [buy],
        now: _now,
      );
      expect(results, hasLength(1));
      final r = results.single;
      expect(r.won, isFalse);
      expect(r.stakeUsd, closeTo(3.21, 1e-9));
      expect(r.payoutUsd, 0);
      expect(r.claimable, isFalse);
      // Dated at the resolution, after the bet it settles.
      expect(r.activity.timestamp, greaterThan(_betAt));
      expect(r.activity.timestampDate.toUtc(),
          DateTime.utc(2026, 10, 5, 11, 5));
      expect(r.activity.transactionHash, isEmpty);

      final copy = predictionRowCopy(_en, r.activity, time: '12:05');
      expect(copy.title, 'Lost · Up');
      expect(copy.subtitle, 'Bitcoin 7:00–7:05 · 12:05');
      final f = predictionRowFigures(r.activity, [buy],
          flow: copy.flow, result: r);
      expect(f.amount, closeTo(3.21, 1e-9));
      expect(f.flow, ActivityFlow.moneyOut);
      expect(f.settled, isTrue);
      expect(f.pnl, isNull);
    });

    test('settled on the closed list (no claim, no redeem) reads Lost too',
        () {
      final results = predictionResults(
        open: const [],
        closed: [
          _settled(
              won: false,
              size: 6.3,
              avgPrice: 3.21 / 6.3,
              realized: -3.21,
              resolvedAt: DateTime.utc(2026, 10, 5, 11, 5)),
        ],
        history: [buy],
        now: _now,
      );
      expect(results.single.won, isFalse);
      expect(results.single.stakeUsd, closeTo(3.21, 1e-9));
    });

    test('a market still trading near zero is not lost', () {
      expect(
          predictionResults(
            open: [
              _held(curPrice: 0.004, size: 6.3, cost: 3.21, redeemable: false)
            ],
            closed: const [],
            history: [buy],
            now: _now,
          ),
          isEmpty);
    });

    test('a market with a claim in the history has its result there', () {
      final cleared = Activity(
        proxyWallet: '0xsafe',
        timestamp: _betAt + 600,
        conditionId: _cid,
        type: 'REDEEM',
        size: 6.3,
        usdcSize: 0,
        transactionHash: '0xredeem',
        title: _round,
        outcome: 'Up',
      );
      expect(
          predictionResults(
            open: [_held(curPrice: 0, size: 6.3, cost: 3.21)],
            closed: const [],
            history: [buy, cleared],
            now: _now,
          ),
          isEmpty);
    });

    test('dust left by a sale is never a loss', () {
      expect(
          predictionResults(
            open: [_held(curPrice: 0, size: 0.004, cost: 0.002)],
            closed: const [],
            history: [buy],
            now: _now,
          ),
          isEmpty);
    });
  });

  group('a won prediction', () {
    final buy = _trade('BUY', usdc: 3, size: 5);

    test('not claimed yet reads Won with the payout, its profit, and Claim',
        () {
      final r = predictionResults(
        open: [_held(curPrice: 1, size: 5, cost: 3)],
        closed: const [],
        history: [buy],
        now: _now,
      ).single;
      expect(r.won, isTrue);
      expect(r.payoutUsd, 5);
      expect(r.pnlUsd, closeTo(2, 1e-9));
      expect(r.claimable, isTrue);
      final copy = predictionRowCopy(_en, r.activity, time: '12:05');
      expect(copy.title, 'Won · Up');
      final f = predictionRowFigures(r.activity, [buy],
          flow: copy.flow, result: r);
      expect(f.amount, 5);
      expect(f.flow, ActivityFlow.moneyIn);
      expect(f.pnl, closeTo(2, 1e-9));
      expect(f.settled, isTrue);
    });

    test('a claim on its way is still a win, no longer claimable', () {
      final r = predictionResults(
        open: [_held(curPrice: 1, size: 5, cost: 3)],
        closed: const [],
        history: [buy],
        clearing: {_cid},
        now: _now,
      ).single;
      expect(r.won, isTrue);
      expect(r.claimable, isFalse);
    });

    test('claimed: the venue\'s own Won row, nothing added', () {
      expect(
          predictionResults(
            open: const [],
            closed: [
              _settled(won: true, size: 5, avgPrice: 0.6, realized: 2),
            ],
            history: [buy],
            now: _now,
          ),
          isEmpty);
    });
  });

  group('agrees with the Statistics realised P&L', () {
    test('a lost held prediction counts −stake', () {
      final position = _held(curPrice: 0, size: 6.3, cost: 3.21);
      final r = predictionResults(
              open: [position],
              closed: const [],
              history: [_trade('BUY', usdc: 3.21, size: 6.3)],
              now: _now)
          .single;
      final record = PredictionRecord(
        tokenId: _up,
        open: true,
        redeemable: true,
        size: position.size,
        totalSize: position.totalBought,
        avgPrice: position.avgPrice,
        entryCostUsd: position.initialValue,
        currentPrice: 0,
        realizedPnlUsd: 0,
        unrealizedPnlUsd: position.cashPnl,
      );
      expect(record.decidedPnlUsd, closeTo(-r.stakeUsd, 1e-9));
      expect(record.decidedPnlUsd, closeTo(r.pnlUsd, 1e-9));
    });

    test('a won held prediction counts its profit', () {
      final position = _held(curPrice: 1, size: 5, cost: 3);
      final r = predictionResults(
              open: [position],
              closed: const [],
              history: [_trade('BUY', usdc: 3, size: 5)],
              now: _now)
          .single;
      final record = PredictionRecord(
        tokenId: _up,
        open: true,
        redeemable: true,
        size: 5,
        totalSize: 5,
        avgPrice: 0.6,
        entryCostUsd: 3,
        currentPrice: 1,
        realizedPnlUsd: 0,
        unrealizedPnlUsd: position.cashPnl,
      );
      expect(record.decidedPnlUsd, closeTo(r.pnlUsd, 1e-9));
    });

    test('part sold, the rest lost: the Sold row and the Lost row add up',
        () {
      // 10 shares at 50¢; 4 sold at 40¢ ($1.60), 6 held to a loss.
      final buy = _trade('BUY', usdc: 5, size: 10);
      final sell =
          _trade('SELL', usdc: 1.6, size: 4, at: _betAt + 60);
      const realized = 1.6 - 5.0; // the venue's realised P&L
      final r = predictionResults(
        open: const [],
        closed: [
          _settled(won: false, size: 10, avgPrice: 0.5, realized: realized),
        ],
        history: [buy, sell],
        now: _now,
      ).single;
      expect(r.stakeUsd, closeTo(3, 1e-9));
      final salePnl = predictionSalePnl([buy, sell], sell)!;
      expect(salePnl - r.stakeUsd, closeTo(realized, 1e-9));
    });
  });
}
