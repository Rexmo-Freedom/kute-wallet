// An ended position says how long its result has left when Polymarket
// publishes an expected settlement time, and keeps its generic caption
// otherwise.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/generated/app_localizations_de.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/screens/polymarket/components/position_awaiting.dart';
import 'package:kute/services/polymarket/resolution_estimate.dart';

void main() {
  group('the resolutions response', () {
    // Shape read live on 5 Oct 2026 from
    // data-api.polymarket.com/v2/resolutions?condition=…
    const proposed = {
      'data': [
        {
          'question_id': '0xb6',
          'condition_id': '0x8e',
          'status': 'proposed',
          'extended_review': false,
          'was_disputed': false,
          'new_version_q': true,
          'proposed_price': '1000000000000000000',
          'last_update_timestamp': '1791192658',
          'expected_settlement_time': '2026-10-05T11:30:58Z',
          'settlement_time_basis': 'managed_proposal_expiration',
        }
      ]
    };
    const resolvedRound = {
      'data': [
        {
          'condition_id': '0xf1',
          'status': 'resolved',
          'payouts': [1000000, 0],
          'resolution_source': 'reported',
          'resolved_at': '2026-10-05T11:30:53Z',
        }
      ]
    };

    test('a proposal carries its settlement time', () {
      expect(polyExpectedSettlementOf(proposed),
          DateTime.utc(2026, 10, 5, 11, 30, 58));
    });

    test('settled, not proposed yet, or malformed: unknown', () {
      expect(polyExpectedSettlementOf(resolvedRound), isNull);
      expect(polyExpectedSettlementOf({'data': []}), isNull);
      expect(polyExpectedSettlementOf({'data': 'x'}), isNull);
      expect(polyExpectedSettlementOf(null), isNull);
      expect(
          polyExpectedSettlementOf({
            'data': [
              {'expected_settlement_time': 'soon'}
            ]
          }),
          isNull);
    });

    test('the fetch asks for the condition and falls back to unknown',
        () async {
      Uri? asked;
      final ok = MockClient((req) async {
        asked = req.url;
        return http.Response(jsonEncode(proposed), 200);
      });
      expect(await fetchPolyExpectedSettlement('0x8e', client: ok),
          DateTime.utc(2026, 10, 5, 11, 30, 58));
      expect(asked!.path, '/v2/resolutions');
      expect(asked!.queryParameters['condition'], '0x8e');

      final down = MockClient((_) async => http.Response('nope', 503));
      expect(await fetchPolyExpectedSettlement('0x8e', client: down), isNull);
      final broken = MockClient((_) async => throw Exception('offline'));
      expect(await fetchPolyExpectedSettlement('0x8e', client: broken), isNull);
      expect(await fetchPolyExpectedSettlement(''), isNull);
    });
  });

  group('the caption', () {
    final l10n = AppLocalizationsEn();
    final now = DateTime.utc(2026, 10, 5, 12);

    String caption(PolyAwaitingResult result, Duration? left,
            {bool shortRound = false}) =>
        polyAwaitingText(l10n, result,
            shortRound: shortRound,
            settleAt: left == null ? null : now.add(left),
            now: now);

    test('minutes left, rounded up', () {
      expect(caption(PolyAwaitingResult.pending, const Duration(minutes: 11,
          seconds: 10)), 'Ended · Result in about 12 min');
      expect(caption(PolyAwaitingResult.won, const Duration(minutes: 3)),
          'You won · Ready to claim in about 3 min');
      expect(caption(PolyAwaitingResult.pending, const Duration(seconds: 61)),
          'Ended · Result in about 2 min');
    });

    test('under a minute', () {
      expect(caption(PolyAwaitingResult.pending, const Duration(seconds: 40)),
          'Ended · Result in under a minute');
      expect(caption(PolyAwaitingResult.won, const Duration(seconds: 1)),
          'You won · Ready to claim in under a minute');
    });

    test('an hour or more, in hours', () {
      expect(caption(PolyAwaitingResult.pending, const Duration(minutes: 59,
          seconds: 30)), 'Ended · Result in about 1 h');
      expect(caption(PolyAwaitingResult.won, const Duration(minutes: 110)),
          'You won · Ready to claim in about 2 h');
    });

    test('unknown or already past: the generic caption', () {
      expect(caption(PolyAwaitingResult.pending, null, shortRound: true),
          l10n.polyAwaitingResult);
      expect(caption(PolyAwaitingResult.won, null, shortRound: true),
          l10n.polyAwaitingWon);
      expect(caption(PolyAwaitingResult.pending, null),
          l10n.polyAwaitingResultSoon);
      expect(caption(PolyAwaitingResult.won, const Duration(minutes: -2)),
          l10n.polyAwaitingWonSoon);
      expect(caption(PolyAwaitingResult.pending, Duration.zero),
          l10n.polyAwaitingResultSoon);
    });

    test('a lost side says lost whatever the estimate', () {
      expect(caption(PolyAwaitingResult.lost, const Duration(minutes: 5)),
          l10n.polyAwaitingLost);
    });

    test('translated', () {
      expect(
          polyAwaitingText(AppLocalizationsDe(), PolyAwaitingResult.pending,
              shortRound: false,
              settleAt: now.add(const Duration(minutes: 7)),
              now: now),
          'Beendet · Ergebnis in etwa 7 Min.');
    });
  });
  group('a short round without a published time', () {
    final l10n = AppLocalizationsEn();
    // btc-updown-5m-1791199800 ends at 1791200100 (11:35:00 UTC).
    final end = DateTime.utc(2026, 10, 5, 11, 35);

    test('identified from its slug, 5 and 15 minute rounds only', () {
      expect(polyShortRoundEnd('btc-updown-5m-1791199800'), end);
      expect(polyShortRoundEnd('eth-updown-15m-1791199800'),
          end.add(const Duration(minutes: 10)));
      for (final slug in [
        'btc-updown-4h-1791144000',
        'bitcoin-up-or-down-october-4-2026-6pm-et',
        'bitcoin-up-or-down-on-october-5',
        'nfl-sf-sea-2026-10-05',
        '',
        null,
      ]) {
        expect(polyShortRoundEnd(slug), isNull, reason: slug);
      }
    });

    String caption(PolyAwaitingResult result, Duration sinceEnd,
            {DateTime? settleAt}) =>
        polyAwaitingText(l10n, result,
            shortRound: true,
            settleAt: settleAt,
            roundEnd: end,
            now: end.add(sinceEnd));

    test('counts from the end: about a minute, then under a minute', () {
      expect(caption(PolyAwaitingResult.pending, Duration.zero),
          'Ended · Result in about 1 min');
      expect(caption(PolyAwaitingResult.won, const Duration(seconds: 44)),
          'You won · Ready to claim in about 1 min');
      expect(caption(PolyAwaitingResult.pending, const Duration(seconds: 45)),
          'Ended · Result in under a minute');
      expect(caption(PolyAwaitingResult.won, const Duration(seconds: 149)),
          'You won · Ready to claim in under a minute');
      expect(polyShortRoundEstimating(end, end.add(const Duration(seconds: 90))),
          isTrue);
    });

    test('late: back to the generic caption after 2.5 minutes', () {
      expect(caption(PolyAwaitingResult.pending, const Duration(seconds: 150)),
          l10n.polyAwaitingResult);
      expect(caption(PolyAwaitingResult.won, const Duration(minutes: 10)),
          l10n.polyAwaitingWon);
      expect(polyShortRoundEstimating(end, end.add(kPolyShortRoundLate)),
          isFalse);
      // Before the end nothing is estimated.
      expect(polyShortRoundEstimating(end, end.subtract(const Duration(seconds: 1))),
          isFalse);
    });

    test('a lost side says lost; a published time still wins', () {
      expect(caption(PolyAwaitingResult.lost, const Duration(seconds: 10)),
          l10n.polyAwaitingLost);
      expect(
          caption(PolyAwaitingResult.pending, const Duration(seconds: 10),
              settleAt: end.add(const Duration(minutes: 7))),
          'Ended · Result in about 7 min');
    });
  });
}
