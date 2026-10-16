// The Predictions cash read: pUSD, USDC.e and native USDC balances of the
// deposit wallet in ONE JSON-RPC batch request per poll, over the shared
// per-host client, instead of a fresh Web3 + HTTP client and three calls.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';

const _owner = '0x1111111111111111111111111111111111111111';
const _usdcE = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174';
const _pusd = '0xc011a7e12a19f7b1f670d46f03b03f3342e82dfb';
const _usdc = '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359';

String _hex(int microUsd) =>
    '0x${BigInt.from(microUsd).toRadixString(16).padLeft(64, '0')}';

void main() {
  test('the breakdown is one batch request with the three balanceOf calls',
      () async {
    final requests = <http.Request>[];
    final model = PolymarketModel()
      ..debugRpcClient = MockClient((request) async {
        requests.add(request);
        final batch = jsonDecode(request.body) as List;
        final answers = <Map<String, Object>>[];
        for (final call in batch.cast<Map<String, dynamic>>()) {
          final to =
              ((call['params'] as List)[0] as Map)['to'].toString().toLowerCase();
          final value = switch (to) {
            _usdcE => _hex(1500000), // $1.50
            _pusd => _hex(42000000), // $42
            _usdc => _hex(250000), // $0.25
            _ => '0x',
          };
          answers.add({'jsonrpc': '2.0', 'id': call['id'] as int, 'result': value});
        }
        return http.Response(jsonEncode(answers), 200,
            headers: {'content-type': 'application/json'});
      });

    final breakdown = await model.getOnChainStablesBreakdown(_owner);

    expect(requests, hasLength(1), reason: 'one request per poll');
    final req = requests.single;
    expect(req.method, 'POST');
    expect(req.headers['content-type'], startsWith('application/json'));
    final batch = jsonDecode(req.body) as List;
    expect(batch, hasLength(3));
    final selector = '0x70a08231${_owner.substring(2).padLeft(64, '0')}';
    final targets = <String>[];
    for (final call in batch.cast<Map<String, dynamic>>()) {
      expect(call['jsonrpc'], '2.0');
      expect(call['method'], 'eth_call');
      final params = call['params'] as List;
      expect(params[1], 'latest');
      final tx = params[0] as Map;
      expect((tx['data'] as String).toLowerCase(), selector);
      targets.add(tx['to'].toString().toLowerCase());
    }
    expect(targets, containsAll([_usdcE, _pusd, _usdc]));
    expect(breakdown.usdcE, closeTo(1.5, 1e-9));
    expect(breakdown.pusd, closeTo(42, 1e-9));
    expect(breakdown.usdc, closeTo(0.25, 1e-9));
    expect(breakdown.total, closeTo(43.75, 1e-9));
  });

  test('the summed balance uses the same single batch', () async {
    var requests = 0;
    final model = PolymarketModel()
      ..debugRpcClient = MockClient((request) async {
        requests++;
        final batch = jsonDecode(request.body) as List;
        return http.Response(
            jsonEncode([
              for (final call in batch.cast<Map<String, dynamic>>())
                {'jsonrpc': '2.0', 'id': call['id'], 'result': _hex(1000000)},
            ]),
            200);
      });
    final total = await model.getOnChainUsdcBalance(_owner);
    expect(requests, 1);
    expect(total, closeTo(3.0, 1e-9));
  });

  test('a failing server is skipped and the next one answers', () async {
    final hosts = <String>[];
    final model = PolymarketModel()
      ..debugRpcClient = MockClient((request) async {
        hosts.add(request.url.host);
        if (hosts.length == 1) return http.Response('bad gateway', 502);
        final batch = jsonDecode(request.body) as List;
        return http.Response(
            jsonEncode([
              for (final call in batch.cast<Map<String, dynamic>>())
                {'jsonrpc': '2.0', 'id': call['id'], 'result': '0x'},
            ]),
            200);
      });
    final breakdown = await model.getOnChainStablesBreakdown(_owner);
    expect(hosts, hasLength(2));
    expect(hosts[0], isNot(hosts[1]));
    expect(breakdown.total, 0);
  });

  test('an RPC error entry fails the server over instead of reading zero',
      () async {
    var requests = 0;
    final model = PolymarketModel()
      ..debugRpcClient = MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response(
              jsonEncode([
                {'jsonrpc': '2.0', 'id': 1, 'result': _hex(5000000)},
                {
                  'jsonrpc': '2.0',
                  'id': 2,
                  'error': {'code': -32000, 'message': 'execution reverted'}
                },
                {'jsonrpc': '2.0', 'id': 3, 'result': '0x'},
              ]),
              200);
        }
        final batch = jsonDecode(request.body) as List;
        return http.Response(
            jsonEncode([
              for (final call in batch.cast<Map<String, dynamic>>())
                {'jsonrpc': '2.0', 'id': call['id'], 'result': _hex(7000000)},
            ]),
            200);
      });
    final breakdown = await model.getOnChainStablesBreakdown(_owner);
    expect(requests, 2);
    expect(breakdown.pusd, closeTo(7, 1e-9));
  });
}
