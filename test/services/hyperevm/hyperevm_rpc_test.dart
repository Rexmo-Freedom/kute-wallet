import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart';

const _owner = '0x1111111111111111111111111111111111111111';
const _a = 'https://a.example/evm';
const _b = 'https://b.example/evm';
const _c = 'https://c.example/evm';

/// Answers a JSON-RPC batch the way a healthy HyperEVM node does.
http.Response _healthy(http.Request request, {String chain = '0x3e7'}) {
  final calls = jsonDecode(request.body) as List;
  return http.Response(
      jsonEncode([
        for (final c in calls)
          {
            'jsonrpc': '2.0',
            'id': c['id'],
            'result': switch (c['method']) {
              'eth_chainId' => chain,
              'eth_getBalance' => '0xde0b6b3a7640000',
              'eth_call' =>
                '0x${BigInt.from(12500000).toRadixString(16).padLeft(64, '0')}',
              'eth_getTransactionCount' =>
                (c['params'] as List)[1] == 'pending' ? '0x8' : '0x7',
              'eth_gasPrice' => '0x8ffd4a8',
              'eth_sendRawTransaction' => '0xabc',
              _ => null,
            }
          }
      ]),
      200);
}

void main() {
  test('reads an account in one batch after the chain check', () async {
    var requests = 0;
    final rpc = HyperEvmRpc(
        endpoints: const [_a],
        client: MockClient((r) async {
          requests++;
          return _healthy(r);
        }));
    final account = await rpc.account(_owner);
    expect(account.hypeWei, BigInt.parse('1000000000000000000'));
    expect(account.usdcMicros, BigInt.from(12500000));
    expect(account.latestNonce, 7);
    expect(account.pendingNonce, 8);
    expect(account.hasPendingTransaction, isTrue);
    expect(account.gasPriceWei, BigInt.from(0x8ffd4a8));
    expect(requests, 1, reason: 'chain check rides in the same batch');
    // The chain is verified once per endpoint.
    await rpc.usdcBalance(_owner);
    expect(rpc.callsSentTo(_a), 6 + 1);
  });

  test('a 429 cools the endpoint down and the request moves on', () async {
    final hits = <String>[];
    var now = DateTime(2026, 10, 12, 12);
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        clock: () => now,
        client: MockClient((r) async {
          hits.add(r.url.toString());
          if (r.url.toString() == _a) {
            return http.Response('slow down', 429,
                headers: {'retry-after': '20'});
          }
          return _healthy(r);
        }));
    expect(await rpc.usdcBalance(_owner), BigInt.from(12500000));
    expect(hits, [_a, _b]);
    // Still cooling: A is not asked again.
    await rpc.hypeBalance(_owner);
    expect(hits, [_a, _b, _b]);
    // After Retry-After, A is asked first again (and, still limited,
    // hands over to B).
    now = now.add(const Duration(seconds: 21));
    await rpc.gasPrice();
    expect(hits.sublist(3), [_a, _b]);
  });

  test('5xx, timeouts and JSON-RPC rate-limit errors fail over', () async {
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b, _c],
        requestTimeout: const Duration(milliseconds: 50),
        client: MockClient((r) async {
          switch (r.url.toString()) {
            case _a:
              return http.Response('bad gateway', 502);
            case _b:
              final calls = jsonDecode(r.body) as List;
              return http.Response(
                  jsonEncode([
                    for (final c in calls)
                      c['method'] == 'eth_chainId'
                          ? {'jsonrpc': '2.0', 'id': c['id'], 'result': '0x3e7'}
                          : {
                              'jsonrpc': '2.0',
                              'id': c['id'],
                              'error': {
                                'code': -32005,
                                'message': 'rate limit exceeded'
                              }
                            }
                  ]),
                  200);
            default:
              return _healthy(r);
          }
        }));
    expect(await rpc.gasPrice(), BigInt.from(0x8ffd4a8));
  });

  test('a stalled endpoint times out and the next answers', () async {
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((r) async {
          if (r.url.toString() == _a) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          return _healthy(r);
        }));
    expect(await rpc.nonce(_owner), 7);
  });

  test('an endpoint on the wrong chain is never used', () async {
    final hits = <String>[];
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        client: MockClient((r) async {
          hits.add(r.url.toString());
          return r.url.toString() == _a
              ? _healthy(r, chain: '0x1')
              : _healthy(r);
        }));
    await rpc.gasPrice();
    await rpc.gasPrice();
    expect(hits, [_a, _b, _b]);
  });

  test('no answer anywhere throws: a failure is never an empty balance',
      () async {
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        client: MockClient((_) async => http.Response('down', 503)));
    await expectLater(
        rpc.usdcBalance(_owner), throwsA(isA<HyperEvmRpcException>()));
  });

  test('every endpoint rate limited reports busy', () async {
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        client: MockClient((_) async => http.Response('', 429)));
    await expectLater(
        rpc.usdcBalance(_owner),
        throwsA(isA<HyperEvmRpcException>()
            .having((e) => e.busy, 'busy', isTrue)));
    // Both cooling: nothing is sent at all.
    await expectLater(
        rpc.usdcBalance(_owner),
        throwsA(isA<HyperEvmRpcException>()
            .having((e) => e.busy, 'busy', isTrue)));
  });

  test('the per-minute budget moves calls to the next endpoint', () async {
    final hits = <String>[];
    var now = DateTime(2026, 10, 12, 12);
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        clock: () => now,
        maxCallsPerMinute: 4,
        client: MockClient((r) async {
          hits.add(r.url.toString());
          return _healthy(r);
        }));
    await rpc.gasPrice(); // 2 calls on A (chain check + call)
    await rpc.nonce(_owner); // 3
    await rpc.hypeBalance(_owner); // 4
    await rpc.gasPrice(); // over budget on A: B
    expect(hits, [_a, _a, _a, _b]);
    now = now.add(const Duration(seconds: 61));
    await rpc.gasPrice();
    expect(hits.last, _a);
  });

  test('identical reads in flight share one request', () async {
    var requests = 0;
    final gate = Completer<void>();
    final rpc = HyperEvmRpc(
        endpoints: const [_a],
        client: MockClient((r) async {
          requests++;
          await gate.future;
          return _healthy(r);
        }));
    final first = rpc.usdcBalance(_owner);
    final second = rpc.usdcBalance(_owner);
    gate.complete();
    expect(await first, await second);
    expect(requests, 1);
  });

  test('a node refusing a call is not retried elsewhere', () async {
    final hits = <String>[];
    final rpc = HyperEvmRpc(
        endpoints: const [_a, _b],
        client: MockClient((r) async {
          hits.add(r.url.toString());
          final calls = jsonDecode(r.body) as List;
          return http.Response(
              jsonEncode([
                for (final c in calls)
                  c['method'] == 'eth_chainId'
                      ? {'jsonrpc': '2.0', 'id': c['id'], 'result': '0x3e7'}
                      : {
                          'jsonrpc': '2.0',
                          'id': c['id'],
                          'error': {'code': 3, 'message': 'execution reverted'}
                        }
              ]),
              200);
        }));
    await expectLater(
        rpc.estimateGas(from: _owner, to: _owner, data: '0x'),
        throwsA(isA<HyperEvmRpcException>()
            .having((e) => e.isNodeError, 'node error', isTrue)));
    expect(hits, [_a]);
  });

  test('broadcast: already known counts as accepted, silence is uncertain',
      () async {
    final known = HyperEvmRpc(
        endpoints: const [_a],
        client: MockClient((r) async {
          final calls = jsonDecode(r.body) as List;
          return http.Response(
              jsonEncode([
                for (final c in calls)
                  c['method'] == 'eth_chainId'
                      ? {'jsonrpc': '2.0', 'id': c['id'], 'result': '0x3e7'}
                      : {
                          'jsonrpc': '2.0',
                          'id': c['id'],
                          'error': {'code': -32000, 'message': 'already known'}
                        }
              ]),
              200);
        }));
    await known.sendRawTransaction('0x02', hash: '0xhash');
    final silent = HyperEvmRpc(
        endpoints: const [_a, _b],
        client: MockClient((_) async => http.Response('', 504)));
    await expectLater(silent.sendRawTransaction('0x02', hash: '0xhash'),
        throwsA(isA<HyperEvmBroadcastUncertain>()));
  });
}
