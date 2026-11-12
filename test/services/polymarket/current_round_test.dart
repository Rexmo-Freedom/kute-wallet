// The next round of a crypto Up-or-Down series, for the slip's Retry
// after a funded bet on a short round landed too late (founder, 23
// October 2026): resolved from the series, never the old market's id,
// never the round that ended and never the round in play (founder, 12
// November 2026: people bet only on the next round).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart' show Btc5MinEvent;
import 'package:kute/services/polymarket/current_round.dart';

Btc5MinEvent _round(String slug, DateTime end,
        {bool closed = false, bool active = true, String? up = 'up'}) =>
    Btc5MinEvent(
      slug: slug,
      title: 'Bitcoin Up or Down',
      endDate: end,
      upPrice: 0.5,
      downPrice: 0.5,
      upTokenId: up == null ? null : '$up-$slug',
      downTokenId: 'down-$slug',
      conditionId: 'cond-$slug',
      closed: closed,
      active: active,
    );

void main() {
  // 12:07:30 UTC: the 12:05 window is in play, 12:10 is next.
  final now = DateTime.utc(2026, 10, 23, 12, 7, 30);
  int epoch(int h, int m) =>
      DateTime.utc(2026, 10, 23, h, m).millisecondsSinceEpoch ~/ 1000;
  final ended = 'btc-updown-5m-${epoch(12, 0)}';
  final current = 'btc-updown-5m-${epoch(12, 5)}';
  final next = 'btc-updown-5m-${epoch(12, 10)}';

  test('the series of a round with a slug per window', () {
    expect(polyRoundSeriesOf(ended), (asset: 'btc', minutes: 5));
    expect(polyRoundSeriesOf('eth-updown-15m-1791152100'),
        (asset: 'eth', minutes: 15));
    expect(polyRoundSeriesOf('btc-updown-4h-1791144000'), isNull);
    expect(
        polyRoundSeriesOf('bitcoin-up-or-down-october-4-2026-6pm-et'), isNull);
    expect(polyRoundSeriesOf('will-it-rain'), isNull);
    expect(polyRoundSeriesOf(null), isNull);
  });

  test('the window after the one that holds now, read by the series, not '
      'the old id, never the round in play', () async {
    final asked = <(String, int, int)>[];
    final round = await resolveNextPolyRound((asset, start, minutes) async {
      asked.add((asset, start, minutes));
      return _round(
          '$asset-updown-${minutes}m-$start',
          DateTime.fromMillisecondsSinceEpoch((start + 300) * 1000,
              isUtc: true));
    }, ended, now: now);
    expect(round!.slug, next);
    expect(round.upTokenId, 'up-$next');
    expect(asked, [('btc', epoch(12, 10), 5)]);
  });

  test('the next window shut or not listed: nothing, never the one in play',
      () async {
    final round = await resolveNextPolyRound((asset, start, minutes) async {
      final slug = '$asset-updown-${minutes}m-$start';
      if (slug == current) {
        return _round(slug, DateTime.utc(2026, 10, 23, 12, 10));
      }
      return _round(slug, DateTime.utc(2026, 10, 23, 12, 15), closed: true);
    }, ended, now: now);
    expect(round, isNull);
  });

  test(
      'never the round that ended, one past its end, or one without '
      'both sides', () async {
    // The bet's own round is the window in play: the next one answers.
    final skipped = await resolveNextPolyRound(
        (asset, start, minutes) async => _round(
            '$asset-updown-${minutes}m-$start',
            DateTime.utc(2026, 10, 23, 12, 15)),
        current,
        now: now);
    expect(skipped!.slug, next);
    // The bet's own round is the next one: never itself.
    expect(
        await resolveNextPolyRound(
            (asset, start, minutes) async => _round(
                '$asset-updown-${minutes}m-$start',
                DateTime.utc(2026, 10, 23, 12, 15)),
            next,
            now: now),
        isNull);
    final none = await resolveNextPolyRound(
        (asset, start, minutes) async => _round(
            '$asset-updown-${minutes}m-$start',
            DateTime.utc(2026, 10, 23, 12, 15),
            up: start == epoch(12, 5) ? 'up' : null),
        ended,
        now: now);
    expect(none, isNull);
  });

  test('nothing for a market that is not a round, or when nothing answers',
      () async {
    var reads = 0;
    expect(
        await resolveNextPolyRound((a, s, m) async {
          reads++;
          return null;
        }, 'will-it-rain', now: now),
        isNull);
    expect(reads, 0);
    expect(
        await resolveNextPolyRound(
            (a, s, m) async => throw Exception('offline'), ended,
            now: now),
        isNull);
  });
}
