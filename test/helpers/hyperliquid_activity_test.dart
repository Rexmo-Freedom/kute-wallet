import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';

HlFill fill(String id, double before, double size, String side, int time) =>
    HlFill.fromJson({
      'coin': 'BTC',
      'tid': id,
      'oid': 10,
      'hash': 'same-order',
      'time': time,
      'startPosition': '$before',
      'sz': '$size',
      'px': '60000',
      'side': side,
      'closedPnl': '0',
      'fee': '0',
    });
void main() {
  test('same-order executions remain distinct, live duplicates replace history',
      () {
    final entry = fill('1', 0, 1, 'B', 10);
    final exit = fill('2', 1, 1, 'A', 20);
    final rows = mergeHlFills([entry, exit], [exit]);
    expect(rows.length, 2);
    expect(rows.last.tradeId, '1');
    expect(rows.first.tradeId, '2');
  });
  test('activity distinguishes opening, increasing, reducing and reversing',
      () {
    expect(hlFillAction(fill('1', 0, 1, 'B', 1)), 'Opened position');
    expect(hlFillAction(fill('2', 1, 1, 'B', 2)), 'Added to position');
    expect(hlFillAction(fill('3', 2, 1, 'A', 3)), 'Reduced position');
    expect(hlFillAction(fill('4', 1, 1, 'A', 4)), 'Closed position');
    expect(hlFillAction(fill('5', 1, 2, 'A', 5)), 'Reversed position');
    expect(hlFillAction(fill('6', -1, 1, 'A', 6)), 'Added to position');
  });
  test('a fill speaks in the position\'s words, never buy or sell', () {
    final l = l10nForLanguage('en');
    // The founder's screenshot: a short that bought back read "Bought".
    final closeShort = fill('1', -0.008, 0.008, 'B', 1);
    expect(hlFillEffect(closeShort), (kind: HlFillKind.closed, long: false));
    expect(hlFillHeadline(closeShort, '0.008 OAI', l), 'Closed short 0.008 OAI');
    expect(hlFillHeadline(fill('2', 0, 1, 'A', 2), '1 OAI', l),
        'Opened short 1 OAI');
    expect(hlFillHeadline(fill('3', 0, 1, 'B', 3), '1 OAI', l),
        'Opened long 1 OAI');
    expect(hlFillHeadline(fill('4', -1, 1, 'A', 4), '1 OAI', l),
        'Added to short 1 OAI');
    expect(hlFillHeadline(fill('5', 2, 1, 'A', 5), '1 OAI', l),
        'Reduced long 1 OAI');
    expect(hlFillHeadline(fill('6', 1, 1, 'A', 6), '1 OAI', l),
        'Closed long 1 OAI');
    expect(hlFillHeadline(fill('7', 1, 2, 'A', 7), '2 OAI', l),
        'Flipped to short 2 OAI');
    expect(hlFillHeadline(fill('8', -1, 2, 'B', 8), '2 OAI', l),
        'Flipped to long 2 OAI');
    // Without the position it met, the venue's direction word decides.
    final byDir = HlFill.fromJson({
      'coin': 'OAI',
      'tid': '9',
      'oid': 9,
      'hash': 'h',
      'time': 9,
      'sz': '1',
      'px': '1400',
      'side': 'B',
      'dir': 'Close Short',
      'closedPnl': '0',
      'fee': '0',
    });
    expect(hlFillEffect(byDir), (kind: HlFillKind.closed, long: false));
    // A spot token is bought and sold, plainly.
    final spot = HlFill.fromJson({
      'coin': '@142',
      'tid': '10',
      'oid': 10,
      'hash': 'h',
      'time': 10,
      'sz': '3',
      'px': '20',
      'side': 'B',
      'closedPnl': '0',
      'fee': '0',
    });
    expect(hlFillHeadline(spot, '3 HYPE', l), 'Bought 3 HYPE');
    // Closing is neither bullish nor bearish: it reads neutral.
    const up = Color(0xFF00FF00), down = Color(0xFFFF0000), n = Color(0xFF888888);
    expect(hlFillTone(closeShort, up: up, down: down, neutral: n), n);
    expect(hlFillTone(fill('2', 0, 1, 'A', 2), up: up, down: down, neutral: n),
        down);
    expect(hlFillTone(fill('3', 0, 1, 'B', 3), up: up, down: down, neutral: n),
        up);
  });
  tradingStatsTests();
}

/// A perp fill with its accounting: [before] the position it met, [size]
/// and [side] what it did, [pnl] what closing realised, [fee] the
/// exchange fee, at [time] (epoch ms).
HlFill perpFill(String id, String coin, double before, double size,
        String side, int time,
        {double px = 100, double pnl = 0, double fee = 0}) =>
    HlFill.fromJson({
      'coin': coin,
      'tid': id,
      'oid': int.parse(id),
      'hash': 'h$id',
      'time': time,
      'startPosition': '$before',
      'sz': '$size',
      'px': '$px',
      'side': side,
      'closedPnl': '$pnl',
      'fee': '$fee',
      'feeToken': 'USDC',
      'dir': before == 0
          ? (side == 'B' ? 'Open Long' : 'Open Short')
          : (side == 'B' ? 'Close Short' : 'Close Long'),
    });

void tradingStatsTests() {
  const day = 86400000;
  final now = DateTime.utc(2026, 10, 6).millisecondsSinceEpoch;
  // Two trades on ETH: one closed flat a day ago (+12 gross, 1.5 of
  // fees), one still open; a BTC trade opened before the fills begin and
  // closed in them, a liquidated SOL trade, and a spot buy.
  final fills = [
    // ETH round trip: 2 opened 10 days ago at 100, closed in two fills.
    perpFill('1', 'ETH', 0, 2, 'B', now - 10 * day, fee: 0.5),
    perpFill('2', 'ETH', 2, 1, 'A', now - 1 * day, px: 106, pnl: 6, fee: 0.5),
    perpFill('3', 'ETH', 1, 1, 'A', now - 1 * day + 1,
        px: 106, pnl: 6, fee: 0.5),
    // ETH again, open now.
    perpFill('4', 'ETH', 0, 1, 'B', now - 3600000, fee: 0.25),
    // BTC: opened before the fills begin, closed 3 days ago for +40.
    perpFill('5', 'BTC', 0.5, 0.5, 'A', now - 3 * day,
        px: 60000, pnl: 40, fee: 3),
    // SOL: liquidated.
    HlFill.fromJson({
      'coin': 'SOL',
      'tid': '6',
      'oid': 6,
      'hash': 'h6',
      'time': now - 2 * day,
      'startPosition': '10',
      'sz': '10',
      'px': '20',
      'side': 'A',
      'closedPnl': '-50',
      'fee': '1',
      'feeToken': 'USDC',
      'dir': 'Close Long',
      'liquidation': {'liquidatedUser': 'x'},
    }),
    // A spot buy: notional and a fill, no trade.
    perpFill('7', '@1', 0, 2, 'B', now - 5 * day, px: 50, fee: 0.1),
  ];

  group('trading range stats', () {
    test(
        'all time: every fill, the notional and closing net of fees', () {
      final stats = TradingBook(fills: fills).statsSince(null)!;
      expect(stats.count, 7);
      // 2×100 + 106 + 106 + 100 + 0.5×60000 + 10×20 + 2×50.
      expect(stats.volumeUsd, closeTo(30812, 1e-9));
      // 6 + 6 + 40 − 50 − (0.5 + 0.5 + 0.5 + 0.25 + 3 + 1 + 0.1).
      expect(stats.realizedUsd, closeTo(-3.85, 1e-9));
    });

    test('a range counts the fills in it', () {
      final since =
          DateTime.fromMillisecondsSinceEpoch(now - 2 * day, isUtc: true);
      final stats = TradingBook(fills: fills).statsSince(since)!;
      // The two ETH closes, the ETH open and the SOL liquidation.
      expect(stats.count, 4);
      expect(stats.volumeUsd, closeTo(106 + 106 + 100 + 200, 1e-9));
      // The ETH open's fee of ten days ago is outside the range.
      expect(stats.realizedUsd, closeTo(12 - 50 - 1.0 - 0.25 - 1, 1e-9));
      final hour = TradingBook(fills: fills).statsSince(
          DateTime.fromMillisecondsSinceEpoch(now - 3600000 - 1,
              isUtc: true))!;
      expect(hour.count, 1);
    });

    test('a cut list answers only ranges it reaches back to', () {
      final book = TradingBook(fills: fills, complete: false);
      expect(book.coversFrom,
          DateTime.fromMillisecondsSinceEpoch(now - 10 * day, isUtc: true));
      expect(book.statsSince(null), isNull);
      expect(
          book.statsSince(
              DateTime.fromMillisecondsSinceEpoch(now - 30 * day, isUtc: true)),
          isNull);
      expect(
          book
              .statsSince(DateTime.fromMillisecondsSinceEpoch(now - 7 * day,
                  isUtc: true))!
              .count,
          6);
      expect(const TradingBook(fills: []).statsSince(null)!.count, 0);
    });
  });
}
