// The open positions' P&L over time (models/open_pnl_history.dart): each
// position from its own entry (its fills or trades), 0 before it was
// opened, a short's sign, the sum laid on the Balance charts' grid ending
// on the sum now, the ranges clipping it and the range it opens on.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidCandle;
import 'package:kute/models/open_pnl_history.dart';
import 'package:kute/models/portfolio_performance.dart'
    show PortfolioPnlPoint, PredictionRecord;
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

final _now = DateTime(2026, 11, 6, 12);

DateTime _ago(Duration d) => _now.subtract(d);

HlFill _fill(String coin, Duration ago,
        {required bool buy,
        required double sz,
        required double px,
        double? start}) =>
    HlFill(
      coin: coin,
      px: px,
      sz: sz,
      side: buy ? 'B' : 'A',
      time: _ago(ago).millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: ago.inMinutes,
      hash: '0x$coin${ago.inMinutes}',
      dir: '',
      cloid: null,
      startPosition: start,
    );

Activity _trade(String token, Duration ago,
        {required String side, required double size, required double price}) =>
    Activity(
      proxyWallet: '0xself',
      timestamp: _ago(ago).millisecondsSinceEpoch ~/ 1000,
      conditionId: '0xc',
      type: 'TRADE',
      size: size,
      usdcSize: size * price,
      transactionHash: '0x${ago.inMinutes}',
      price: price,
      asset: token,
      side: side,
    );

/// Hourly prices over [days] ending now: [at] gives each one's price.
List<OpenPnlPrice> _hourly(int days, double Function(DateTime) at) => [
      for (var h = days * 24; h >= 0; h--)
        (_ago(Duration(hours: h)), at(_ago(Duration(hours: h)))),
    ];

void main() {
  group('a Hyperliquid perp from its fills', () {
    test(
        'from the fill that opened it: an increase moves the average entry, '
        'a reduction keeps it, the last stretch is the position as the '
        'venue reports it', () {
      final steps = hlPerpOpenSteps(
        coin: 'BTC',
        szi: 0.15,
        entryPx: 61000,
        fills: [
          // An older position, closed: not the one held now.
          _fill('BTC', const Duration(days: 20),
              buy: true, sz: 0.1, px: 50000, start: 0),
          _fill('BTC', const Duration(days: 18),
              buy: false, sz: 0.1, px: 52000, start: 0.1),
          // Another market's fills are not this position's.
          _fill('ETH', const Duration(days: 9),
              buy: true, sz: 1, px: 3000, start: 0),
          // The open, an increase, a reduction.
          _fill('BTC', const Duration(days: 10),
              buy: true, sz: 0.1, px: 60000, start: 0),
          _fill('BTC', const Duration(days: 5),
              buy: true, sz: 0.1, px: 63000, start: 0.1),
          _fill('BTC', const Duration(days: 2),
              buy: false, sz: 0.05, px: 64000, start: 0.2),
        ],
      )!;
      expect(steps.map((s) => s.at),
          [for (final d in [10, 5, 2]) _ago(Duration(days: d))]);
      expect(steps[0].qty, 0.1);
      expect(steps[0].entry, 60000);
      expect(steps[1].qty, closeTo(0.2, 1e-12));
      expect(steps[1].entry, closeTo(61500, 1e-6));
      // The last stretch: the venue's own size and entry.
      expect(steps[2].qty, 0.15);
      expect(steps[2].entry, 61000);
    });

    test('a short: its quantity is negative, so a fall is its gain', () {
      final steps = hlPerpOpenSteps(
        coin: 'ETH',
        szi: -2,
        entryPx: 3000,
        fills: [
          _fill('ETH', const Duration(days: 3),
              buy: false, sz: 2, px: 3000, start: 0),
        ],
      )!;
      final leg = OpenPnlLeg(
          key: openPnlKeyPerp('ETH'),
          steps: steps,
          prices: [
            (_ago(const Duration(days: 2)), 2900.0),
            (_ago(const Duration(days: 1)), 3100.0),
          ]);
      expect(leg.valueAt(_ago(const Duration(days: 2))), closeTo(200, 1e-9));
      expect(leg.valueAt(_ago(const Duration(days: 1))), closeTo(-200, 1e-9));
    });

    test('a flip opens the position held now at the flipping fill', () {
      final steps = hlPerpOpenSteps(
        coin: 'SOL',
        szi: -5,
        entryPx: 150,
        fills: [
          _fill('SOL', const Duration(days: 4),
              buy: true, sz: 5, px: 140, start: 0),
          // Long 5 to short 5 in one fill.
          _fill('SOL', const Duration(days: 1),
              buy: false, sz: 10, px: 150, start: 5),
        ],
      )!;
      expect(steps.single.at, _ago(const Duration(days: 1)));
      expect(steps.single.qty, -5);
    });

    test('no fill that opened it (older than the fills kept): not charted',
        () {
      expect(
          hlPerpOpenSteps(
            coin: 'BTC',
            szi: 0.2,
            entryPx: 60000,
            fills: [
              _fill('BTC', const Duration(days: 1),
                  buy: true, sz: 0.1, px: 62000, start: 0.1),
            ],
          ),
          isNull);
      expect(
          hlPerpOpenSteps(
              coin: 'BTC', szi: 0.2, entryPx: 60000, fills: const []),
          isNull);
    });
  });

  group('a Polymarket position from its trades', () {
    test(
        'from the first buy after the holding was last empty, the average '
        'price moving on each buy; the last stretch is the Data API\'s', () {
      final steps = polyOpenSteps(
        tokenId: 'yes',
        size: 15,
        avgPrice: 0.45,
        activities: [
          _trade('yes', const Duration(days: 30),
              side: 'BUY', size: 10, price: 0.2),
          _trade('yes', const Duration(days: 25),
              side: 'SELL', size: 10, price: 0.3),
          _trade('yes', const Duration(days: 8),
              side: 'BUY', size: 10, price: 0.4),
          _trade('other', const Duration(days: 7),
              side: 'BUY', size: 99, price: 0.9),
          _trade('yes', const Duration(days: 6),
              side: 'BUY', size: 10, price: 0.6),
          _trade('yes', const Duration(days: 3),
              side: 'SELL', size: 5, price: 0.7),
        ],
      )!;
      expect(steps.map((s) => s.at),
          [for (final d in [8, 6, 3]) _ago(Duration(days: d))]);
      expect(steps[0].qty, 10);
      expect(steps[0].entry, closeTo(0.4, 1e-12));
      expect(steps[1].qty, 20);
      expect(steps[1].entry, closeTo(0.5, 1e-12));
      expect(steps[2].qty, 15);
      expect(steps[2].entry, 0.45);
    });

    test('a history that does not add up to the shares held: no steps', () {
      expect(
          polyOpenSteps(
            tokenId: 'yes',
            size: 40,
            avgPrice: 0.45,
            activities: [
              _trade('yes', const Duration(days: 2),
                  side: 'BUY', size: 10, price: 0.4),
            ],
          ),
          isNull);
    });
  });

  group('the sum', () {
    // A long BTC perp opened 20 days ago (0.1 at 60,000) and a prediction
    // bought 5 days ago (10 shares at 0.40); BTC rises 100 an hour, the
    // prediction's price 0.01 a day.
    final btc = OpenPnlLeg(
      key: openPnlKeyPerp('BTC'),
      steps: [OpenPnlStep(_ago(const Duration(days: 20)), 0.1, 60000)],
      prices: _hourly(
          30,
          (t) =>
              60000 +
              100 *
                  t
                      .difference(_ago(const Duration(days: 20)))
                      .inHours
                      .toDouble()),
    );
    final yes = OpenPnlLeg(
      key: 'pm:yes',
      steps: [OpenPnlStep(_ago(const Duration(days: 5)), 10, 0.4)],
      prices: _hourly(
          10,
          (t) =>
              0.4 +
              0.01 *
                  t.difference(_ago(const Duration(days: 5))).inHours / 24),
    );
    final legs = [btc, yes];

    test('a position opened mid-range adds nothing before its entry', () {
      final before = _ago(const Duration(days: 6));
      expect(yes.valueAt(before), 0);
      expect(openPnlValueAt(legs, before), btc.valueAt(before));
      final after = _ago(const Duration(days: 4));
      expect(yes.valueAt(after), closeTo(10 * 0.01, 1e-9));
      expect(openPnlValueAt(legs, after),
          closeTo(btc.valueAt(after) + yes.valueAt(after), 1e-9));
      // Nothing before the oldest open.
      expect(openPnlValueAt(legs, _ago(const Duration(days: 25))), 0);
    });

    test('the changes are the legs added at each moment', () {
      final changes = openPnlChanges(legs, _now);
      expect(changes.first.$1, _ago(const Duration(days: 20)));
      for (final (t, v) in changes) {
        expect(v, closeTo(openPnlValueAt(legs, t), 1e-6), reason: '$t');
      }
      expect(changes.last.$1, _now);
    });

    test(
        'the grid: from a lead-in at 0 before the oldest open, every point '
        'the sum then, the last the sum now', () {
      final series = openPnlSeries(legs, _now)!;
      expect(series.times.first.isBefore(_ago(const Duration(days: 20))),
          isTrue);
      expect(series.values.first, 0);
      expect(series.values.last, closeTo(openPnlValueAt(legs, _now), 1e-9));
      expect(series.times.last, _now);
      for (var i = 0; i < series.length; i += 97) {
        expect(series.values[i],
            closeTo(openPnlValueAt(legs, series.times[i]), 1e-6),
            reason: '${series.times[i]}');
      }
      expect(openPnlSeries(const [], _now), isNull);
    });

    test(
        'the ranges clip it, ending now; it opens on the shortest that '
        'covers the oldest entry', () {
      final series = openPnlSeries(legs, _now)!;
      final week = kuteTrendWindow(series, series.spanFor(BalanceRange.week));
      expect(week.times.first.isBefore(_ago(const Duration(days: 7))),
          isFalse);
      expect(week.times.first.isAfter(_ago(const Duration(days: 7, hours: 1))),
          isTrue);
      expect(week.values.last, series.values.last);
      // A week's window starts where the line was then, not at 0.
      expect(week.values.first, greaterThan(0));
      final all = kuteTrendWindow(series, series.spanFor(BalanceRange.all));
      expect(all.times.first, series.times.first);
      expect(all.values.first, 0);
      // The oldest entry 20 days back: a month covers it.
      expect(openPnlDefaultRange(_ago(const Duration(days: 20)), _now),
          BalanceRange.month);
      expect(openPnlDefaultRange(_ago(const Duration(days: 3)), _now),
          BalanceRange.week);
      expect(openPnlDefaultRange(_ago(const Duration(days: 60)), _now),
          BalanceRange.threeMonths);
      expect(openPnlDefaultRange(_ago(const Duration(days: 400)), _now),
          BalanceRange.all);
    });
  });

  test('candles read as prices: the first open, then each close', () {
    final open = _ago(const Duration(hours: 2));
    final prices = openPnlCandlePrices([
      HyperliquidCandle(
          openTime: open,
          closeTime: open.add(const Duration(hours: 1)),
          open: 100,
          high: 110,
          low: 90,
          close: 105,
          volume: 1),
      HyperliquidCandle(
          openTime: open.add(const Duration(hours: 1)),
          // Still running.
          closeTime: _now.add(const Duration(minutes: 30)),
          open: 105,
          high: 120,
          low: 100,
          close: 118,
          volume: 1),
    ], _now);
    expect(prices, [
      (open, 100.0),
      (open.add(const Duration(hours: 1)), 105.0),
      (_now, 118.0),
    ]);
    // A finer recent history laid over a coarse one's end.
    expect(
        openPnlMergePrices(
            [(_ago(const Duration(days: 3)), 1.0), (_ago(const Duration(days: 1)), 2.0)],
            [(_ago(const Duration(days: 2)), 3.0)]),
        [(_ago(const Duration(days: 3)), 1.0), (_ago(const Duration(days: 2)), 3.0)]);
  });

  group('the whole P&L history (the P&L and Activity heroes)', () {
    test(
        'a perp\'s whole history from its fills: the average moving on an '
        'increase, a reduction realising (price − entry) on what it closes, '
        'a flip closing one side and opening the other, every dollar fee out '
        'of the realised; flat between', () {
      HlFill fee(HlFill f, double fee) => HlFill(
          coin: f.coin,
          px: f.px,
          sz: f.sz,
          side: f.side,
          time: f.time,
          closedPnl: 0,
          fee: fee,
          feeToken: 'USDC',
          oid: f.oid,
          hash: f.hash,
          dir: f.dir,
          cloid: null,
          startPosition: f.startPosition);
      final fills = [
        // Long 1 at 100, then 1 more at 110 (average 105).
        fee(_fill('ETH', const Duration(days: 10), buy: true, sz: 1, px: 100,
            start: 0), 0.1),
        _fill('ETH', const Duration(days: 9), buy: true, sz: 1, px: 110,
            start: 1),
        // Half sold at 115: +10 realised, the average kept.
        _fill('ETH', const Duration(days: 8), buy: false, sz: 1, px: 115,
            start: 2),
        // Flipped: 3 sold at 95: the long's 1 closes (−10), short 2 at 95.
        _fill('ETH', const Duration(days: 7), buy: false, sz: 3, px: 95,
            start: 1),
        // Closed at 90: +10.
        _fill('ETH', const Duration(days: 6), buy: true, sz: 2, px: 90,
            start: -2),
      ];
      final h = hlPerpHistory(coin: 'ETH', fills: fills)!;
      expect(h.assumedEntry, isFalse);
      expect(h.steps, [
        OpenPnlStep(_ago(const Duration(days: 10)), 1, 100),
        OpenPnlStep(_ago(const Duration(days: 9)), 2, 105),
        OpenPnlStep(_ago(const Duration(days: 8)), 1, 105),
        OpenPnlStep(_ago(const Duration(days: 7)), -2, 95),
        OpenPnlStep(_ago(const Duration(days: 6)), 0, 0),
      ]);
      final realised = [for (final r in h.realised) r.$2];
      expect(realised[0], closeTo(-0.1, 1e-9));
      expect(realised[1], closeTo(-0.1, 1e-9));
      expect(realised[2], closeTo(9.9, 1e-9));
      expect(realised[3], closeTo(-0.1, 1e-9));
      expect(realised[4], closeTo(9.9, 1e-9));
      // Marked between fills, flat after: the leg at a moment.
      final leg = OpenPnlLeg(
          key: openPnlKeyPerp('ETH'),
          steps: h.steps,
          prices: _hourly(12, (_) => 100),
          realised: h.realised);
      expect(leg.valueAt(_ago(const Duration(days: 11))), 0);
      // Long 2 at 105 marked at 100: −10, the fee paid.
      expect(leg.valueAt(_ago(const Duration(days: 8, hours: 12))),
          closeTo(-10.1, 1e-9));
      // Short 2 at 95 marked at 100: −10, after −0.1 realised.
      expect(leg.valueAt(_ago(const Duration(days: 6, hours: 12))),
          closeTo(-10.1, 1e-9));
      expect(leg.valueAt(_now), closeTo(9.9, 1e-9));
    });

    test(
        'held now: the last stretch is the venue\'s own size and entry; '
        'held before the first fill read: marked from that fill\'s price', () {
      final open = hlPerpHistory(
          coin: 'BTC',
          fills: [
            _fill('BTC', const Duration(days: 3), buy: true, sz: 0.1, px: 60000,
                start: 0),
          ],
          szi: 0.1,
          entryPx: 60010)!;
      expect(open.steps.single, OpenPnlStep(_ago(const Duration(days: 3)), 0.1, 60010));
      final older = hlPerpHistory(
          coin: 'BTC',
          fills: [
            // 0.2 held before this, its entry unknown: reduced at 61,000.
            _fill('BTC', const Duration(days: 3), buy: false, sz: 0.1,
                px: 61000, start: 0.2),
          ],
          szi: 0.1,
          entryPx: 58000)!;
      expect(older.assumedEntry, isTrue);
      // Its moves from the mark on: nothing realised selling at the mark,
      // and the stretch kept on the mark, never the venue's older entry.
      expect(older.realised.single.$2, 0);
      expect(older.steps.single, OpenPnlStep(_ago(const Duration(days: 3)), 0.1, 61000));
      expect(hlPerpHistory(coin: 'SOL', fills: const []), isNull);
    });

    test('spot pairs: the venue\'s closedPnl less dollar fees, by pair', () {
      HlFill spot(String coin, Duration ago, double closed, double fee,
              String token) =>
          HlFill(
              coin: coin,
              px: 1,
              sz: 10,
              side: closed == 0 ? 'B' : 'A',
              time: _ago(ago).millisecondsSinceEpoch,
              closedPnl: closed,
              fee: fee,
              feeToken: token,
              oid: ago.inMinutes,
              hash: '0x$coin${ago.inMinutes}',
              dir: closed == 0 ? 'Buy' : 'Sell',
              cloid: null);
      final r = hlSpotRealised([
        // A buy's fee is in the token bought: not dollars.
        spot('@107', const Duration(days: 4), 0, 0.01, 'HYPE'),
        spot('@107', const Duration(days: 2), 5, 0.2, 'USDC'),
        spot('PURR/USDC', const Duration(days: 1), -1, 0.1, 'USDC'),
        // A perp fill is no spot pair's.
        _fill('BTC', const Duration(days: 1), buy: true, sz: 1, px: 1),
      ]);
      expect(r.keys.toSet(), {'@107', 'PURR/USDC'});
      expect(r['@107']!.single.$2, closeTo(4.8, 1e-9));
      expect(r['PURR/USDC']!.single.$2, closeTo(-1.1, 1e-9));
    });

    test(
        'predictions: each one\'s realised P&L as Polymarket books it, at '
        'its last event; nothing realised or no moment: none', () {
      PredictionRecord rec(String token,
              {bool open = false,
              bool redeemable = false,
              double realised = 0,
              double unrealised = 0,
              Duration? last}) =>
          PredictionRecord(
              tokenId: token,
              open: open,
              redeemable: redeemable,
              size: open ? 10 : 0,
              totalSize: 10,
              avgPrice: 0.5,
              entryCostUsd: open ? 5 : 0,
              currentPrice: 0.6,
              realizedPnlUsd: realised,
              unrealizedPnlUsd: unrealised,
              lastEventAt: last == null ? null : _ago(last));
      final legs = polyRealisedLegs([
        rec('won', realised: 3, last: const Duration(days: 2)),
        // Resolved, waiting to be claimed: its payout.
        rec('claim',
            open: true,
            redeemable: true,
            realised: -1,
            unrealised: 5,
            last: const Duration(days: 1)),
        // Open, part sold: what it realised so far.
        rec('part', open: true, realised: 0.5, last: const Duration(hours: 5)),
        rec('nothing', open: true, last: const Duration(hours: 1)),
        rec('when', realised: 2),
      ]);
      expect([for (final l in legs) l.key], [
        openPnlKeyRealised('pm:won'),
        openPnlKeyRealised('pm:claim'),
        openPnlKeyRealised('pm:part'),
      ]);
      expect([for (final l in legs) l.realised.single.$2], [3, 4, 0.5]);
      expect(legs.first.realised.single.$1, _ago(const Duration(days: 2)));
    });

    test(
        'the venue\'s own P&L under the legs: at each of its observations '
        'the line is the venue\'s figure, what the legs do not carry held to '
        'the next; with no legs, the venue\'s line', () {
      final leg = OpenPnlLeg(
          key: 'x',
          steps: const [],
          prices: const [],
          realised: [(_ago(const Duration(days: 5)), 10.0)]);
      PortfolioPnlPoint at(Duration d, double v) =>
          PortfolioPnlPoint(timestamp: _ago(d), pnlUsd: v);
      final points = [
        at(const Duration(days: 30), 0),
        at(const Duration(days: 20), 1),
        at(const Duration(days: 3), 11.5),
        at(const Duration(days: 1), 11.5),
      ];
      final venue = openPnlVenueLeg('venue:trading', points, [leg])!;
      // Leading zero left out; unchanged moves left out.
      expect(venue.realised, [
        (_ago(const Duration(days: 20)), 1.0),
        (_ago(const Duration(days: 3)), 1.5),
      ]);
      final legs = [leg, venue];
      for (final p in points.skip(1)) {
        expect(openPnlValueAt(legs, p.timestamp), closeTo(p.pnlUsd, 1e-9));
      }
      // Between observations the legs move it.
      expect(openPnlValueAt(legs, _ago(const Duration(days: 4))), 11);
      final alone = openPnlVenueLeg('venue:trading', points, const [])!;
      expect([for (final r in alone.realised) r.$2], [1, 11.5]);
      expect(openPnlVenueLeg('v', [at(const Duration(days: 2), 0)], const []),
          isNull);
    });

    test(
        'every range its own reach: a range older than the line is laid '
        'again from its own start, zero before; ALL the whole line', () {
      final legs = [
        OpenPnlLeg(
            key: 'a',
            steps: [OpenPnlStep(_ago(const Duration(days: 2)), 1, 10)],
            prices: _hourly(3, (_) => 12)),
      ];
      final changes = openPnlChanges(legs, _now);
      final series = openPnlSeries(legs, _now)!;
      final firsts = <DateTime>{};
      for (final r in BalanceRange.values) {
        final w = openPnlRangeWindow(
            series: series, changes: changes, now: _now, range: r);
        expect(w.values.last, closeTo(2, 1e-9), reason: r.label);
        firsts.add(w.times.first);
        if (r.duration case final back?) {
          expect(w.times.first, _now.subtract(back), reason: r.label);
          expect(w.values.first, 0, reason: r.label);
        } else {
          expect(w.times.first, series.times.first);
        }
      }
      expect(firsts, hasLength(BalanceRange.values.length));
      // A range inside the line is its window, nothing laid again.
      final long = [
        OpenPnlLeg(
            key: 'b',
            steps: [OpenPnlStep(_ago(const Duration(days: 40)), 1, 10)],
            prices: _hourly(41, (_) => 12)),
      ];
      final longSeries = openPnlSeries(long, _now)!;
      final week = openPnlRangeWindow(
          series: longSeries,
          changes: openPnlChanges(long, _now),
          now: _now,
          range: BalanceRange.week);
      final clipped =
          kuteTrendWindow(longSeries, longSeries.spanFor(BalanceRange.week));
      expect(week.values, clipped.values);
      expect(week.times, clipped.times);
    });
  });
}
