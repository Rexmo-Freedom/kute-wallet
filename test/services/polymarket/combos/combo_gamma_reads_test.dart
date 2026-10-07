// Combo eligibility and leg token reads go to Gamma `GET /markets/keyset`
// (`{markets: [...], next_cursor}`); the offset `GET /markets` list
// answered `deprecation: true` with a 2026-05-01 sunset. Fixtures are live
// `/markets/keyset` responses read on 2026-10-07 for three markets of
// cs2-ts7-m80-2026-10-07 (map 1 already closed), trimmed to the keys read.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/combos/combo_service.dart';

String _fixture(String name) =>
    File('test/fixtures/polymarket_gamma/$name').readAsStringSync();

const _map1 = '5393036'; // closed
const _map2 = '5393037';
const _map3 = '5393038';
const _cond1 =
    '0x1e02c6b041a1aa53c58dd34497265cdaf1b160ca4a2316d2d91ba7e078a4a741';
const _cond2 =
    '0x0d6c75dfdba2dfa11911cc13b28f829431cebaa523950c2bfd70d88d08619efb';
const _cond3 =
    '0x15057051e306c463c2f6ad84f834547e7b5a6ef4dad4b1f303a49f595fd5b9c8';

void main() {
  group('fetchEligibility', () {
    test('asks /markets/keyset by condition id and parses the envelope',
        () async {
      final seen = <Uri>[];
      final out =
          await PolymarketComboService(client: MockClient((request) async {
        seen.add(request.url);
        return http.Response(
            _fixture('markets_keyset_condition_ids.json'), 200);
      })).fetchEligibility([_cond1, _cond2.toUpperCase(), _cond3]);

      expect(seen, hasLength(1));
      expect(seen.single.host, 'gamma-api.polymarket.com');
      expect(seen.single.path, '/markets/keyset');
      expect(seen.single.queryParametersAll['condition_ids'],
          [_cond1, _cond2, _cond3]);
      expect(seen.single.queryParameters['limit'], '3');
      expect(seen.single.queryParameters.containsKey('closed'), isFalse);

      // Map 1 is closed, so the live list leaves it out (as before).
      expect(out.keys, unorderedEquals([_cond2, _cond3]));
      final e = out[_cond2]!;
      expect(e.status, 'enabled');
      expect(e.positionIds, hasLength(2));
      expect(e.clobTokenIds, hasLength(2));
      expect(e.clobTokenIds.first, startsWith('3105266120559700445386'));
      expect(e.outcomes, ['Spirit', 'M80']);
    });

    test('follows next_cursor to the end', () async {
      final full = jsonDecode(_fixture('markets_keyset_condition_ids.json'))
          as Map<String, dynamic>;
      final rows = full['markets'] as List;
      final seen = <Uri>[];
      // limit=1 (one id asked): a full page with a cursor asks again.
      final paged =
          await PolymarketComboService(client: MockClient((request) async {
        seen.add(request.url);
        final after = request.url.queryParameters['after_cursor'];
        return http.Response(
            jsonEncode(after == null
                ? {'markets': rows.take(1).toList(), 'next_cursor': 'c1'}
                : {'markets': rows.skip(1).toList()}),
            200);
      })).fetchEligibility([_cond2]);
      expect(seen, hasLength(2));
      expect(seen.last.queryParameters['after_cursor'], 'c1');
      expect(paged.keys, unorderedEquals([_cond2, _cond3]));
    });

    test('a failed read throws', () async {
      final svc = PolymarketComboService(
          client: MockClient((_) async => http.Response('down', 503)));
      expect(
          svc.fetchEligibility([_cond2]), throwsA(isA<http.ClientException>()));
      final bare = PolymarketComboService(
          client: MockClient((_) async => http.Response('[]', 200)));
      expect(bare.fetchEligibility([_cond2]),
          throwsA(isA<http.ClientException>()));
    });

    test('asks at most 20 ids per request', () async {
      final seen = <Uri>[];
      await PolymarketComboService(client: MockClient((request) async {
        seen.add(request.url);
        return http.Response('{"markets":[]}', 200);
      })).fetchEligibility([for (var i = 0; i < 45; i++) '0x$i']);
      expect(seen.map((u) => u.queryParametersAll['condition_ids']!.length),
          [20, 20, 5]);
      expect(seen.map((u) => u.queryParameters['limit']), ['20', '20', '5']);
    });
  });

  group('fetchClobTokens', () {
    test('asks the live list, then closed=true for the legs still missing',
        () async {
      final seen = <Uri>[];
      final out =
          await PolymarketComboService(client: MockClient((request) async {
        seen.add(request.url);
        final closed = request.url.queryParameters['closed'] == 'true';
        return http.Response(
            _fixture(closed
                ? 'markets_keyset_id_closed.json'
                : 'markets_keyset_id_open.json'),
            200);
      })).fetchClobTokens([_map1, _map2, _map3]);

      expect(seen, hasLength(2));
      expect(seen.first.path, '/markets/keyset');
      expect(seen.first.queryParametersAll['id'], [_map1, _map2, _map3]);
      expect(seen.first.queryParameters.containsKey('closed'), isFalse);
      expect(seen.last.queryParametersAll['id'], [_map1]);
      expect(seen.last.queryParameters['closed'], 'true');
      expect(seen.last.queryParameters['limit'], '1');

      expect(out.keys, unorderedEquals([_map1, _map2, _map3]));
      expect(out[_map1]!.first, startsWith('2098721504819567007745'));
      expect(out[_map2]!.first, startsWith('3105266120559700445386'));
      expect(out[_map3], hasLength(2));
    });

    test('skips the closed read when every leg is live', () async {
      final seen = <Uri>[];
      await PolymarketComboService(client: MockClient((request) async {
        seen.add(request.url);
        return http.Response(_fixture('markets_keyset_id_open.json'), 200);
      })).fetchClobTokens([_map2, _map3]);
      expect(seen, hasLength(1));
    });

    test('a failed read is skipped, the closed read still runs', () async {
      final out =
          await PolymarketComboService(client: MockClient((request) async {
        if (request.url.queryParameters['closed'] == 'true') {
          return http.Response(_fixture('markets_keyset_id_closed.json'), 200);
        }
        return http.Response('down', 503);
      })).fetchClobTokens([_map1, _map2]);
      expect(out.keys, [_map1]);
    });
  });
}
