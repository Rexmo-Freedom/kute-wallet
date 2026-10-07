import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/jade_ble_transport.dart';
import 'package:kute/services/jade_pin_auth.dart';
import 'package:kute/services/jade_rpc.dart';

void main() {
  group('Jade multipart PSBT replies', () {
    test('requests chunks two through N and preserves every signed byte',
        () async {
      final parts = [
        Uint8List.fromList([0x70, 0x73, 0x62]),
        Uint8List.fromList([0x74, 0xff, 0, 255]),
        Uint8List.fromList([128, 1])
      ];
      final requests = <Map<String, dynamic>>[];
      final rpc = JadeRpc(_Transport((request) async {
        requests.add(request);
        final sequence = request['method'] == 'sign_psbt'
            ? 1
            : (request['params'] as Map)['seqnum'] as int;
        expect(sequence, requests.length);
        if (sequence > 1) {
          expect(request['method'], 'get_extended_data');
          expect(request['params'], {
            'origid': requests.first['id'],
            'orig': 'sign_psbt',
            'seqnum': sequence,
            'seqlen': 3
          });
        }
        return {
          'id': request['id'],
          'seqnum': sequence,
          'seqlen': 3,
          'result': parts[sequence - 1]
        };
      }));

      final signed = await rpc.signPsbt(
          psbtBytes: Uint8List.fromList([1, 2]), network: 'mainnet');

      expect(signed, orderedEquals(parts.expand((part) => part)));
      expect(requests, hasLength(3));
      expect(requests.map((request) => request['id']).toSet(), hasLength(3));
    });

    test('single replies need no multipart metadata or extra request',
        () async {
      var calls = 0;
      final rpc = JadeRpc(_Transport((request) async {
        calls++;
        return {
          'id': request['id'],
          'result': [0, 128, 255]
        };
      }));

      expect(await rpc.signPsbt(psbtBytes: Uint8List(1), network: 'mainnet'),
          [0, 128, 255]);
      expect(calls, 1);
    });

    for (final fault in [
      'wrong_sequence',
      'changed_length',
      'wrong_id',
      'invalid_bytes'
    ]) {
      test('rejects $fault instead of returning a corrupted PSBT', () async {
        var calls = 0;
        final rpc = JadeRpc(_Transport((request) async {
          calls++;
          if (calls == 1) {
            return {
              'id': request['id'],
              'seqnum': 1,
              'seqlen': 2,
              'result': [1]
            };
          }
          return {
            'id': fault == 'wrong_id' ? 'other-request' : request['id'],
            'seqnum': fault == 'wrong_sequence' ? 1 : 2,
            'seqlen': fault == 'changed_length' ? 3 : 2,
            'result': fault == 'invalid_bytes' ? [256] : [2]
          };
        }));

        await expectLater(
            rpc.signPsbt(psbtBytes: Uint8List(1), network: 'mainnet'),
            throwsA(isA<JadeRpcError>()));
        expect(calls, 2);
      });
    }

    test('device errors do not expose firmware error payloads', () async {
      final rpc = JadeRpc(_Transport((request) async => {
            'id': request['id'],
            'error': {
              'code': -32000,
              'message': 'secret encrypted response',
              'data': 'secret request'
            },
          }));

      await expectLater(
          rpc.signPsbt(psbtBytes: Uint8List(1), network: 'mainnet'),
          throwsA(isA<JadeRpcError>()
              .having((error) => error.code, 'code', -32000)
              .having((error) => error.toString(), 'message',
                  isNot(contains('secret')))
              .having((error) => error.data, 'data', isNull)));
    });
  });

  group('Jade PIN HTTP relay', () {
    for (final success in [true, false]) {
      test(
          'unwraps each RPC envelope and returns final authentication $success',
          () async {
        final requests = <Map<String, dynamic>>[];
        final rpc = JadeRpc(_Transport((request) async {
          requests.add(request);
          switch (request['method']) {
            case 'auth_user':
              expect(request['params'], {'network': 'mainnet'});
              return {
                'id': request['id'],
                'result': _httpStep('first', 'handshake_init')
              };
            case 'handshake_init':
              expect(request['params'], {'encrypted_reply': 'first'});
              return {
                'id': request['id'],
                'result': _httpStep('second', 'pin')
              };
            case 'pin':
              expect(request['params'], {'encrypted_reply': 'second'});
              return {'id': request['id'], 'result': success};
            default:
              fail('Unexpected Jade RPC method');
          }
        }));
        final relayed = <String>[];
        final auth = JadePinAuth(rpc, httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.host, 'pin.example');
          final step =
              (jsonDecode(request.body) as Map)['encrypted_request'] as String;
          relayed.add(step);
          return http.Response(jsonEncode({'encrypted_reply': step}), 200);
        }));
        addTearDown(auth.dispose);

        expect(await auth.authenticate(network: 'mainnet'), success);
        expect(relayed, ['first', 'second']);
        expect(requests.map((request) => request['method']),
            ['auth_user', 'handshake_init', 'pin']);
        expect(requests.map((request) => request['id']).toSet(), hasLength(3));
      });
    }

    test('an already unlocked device needs no HTTP relay', () async {
      final rpc = JadeRpc(
          _Transport((request) async => {'id': request['id'], 'result': true}));
      final auth = JadePinAuth(rpc, httpClient: MockClient((_) async {
        fail('No HTTP request expected');
      }));
      addTearDown(auth.dispose);
      expect(await auth.authenticate(network: 'mainnet'), isTrue);
    });

    test('a malformed terminal result cannot report authentication success',
        () async {
      var calls = 0;
      final rpc = JadeRpc(_Transport((request) async => {
            'id': request['id'],
            'result':
                calls++ == 0 ? _httpStep('first', 'pin') : {'result': true},
          }));
      final auth = JadePinAuth(rpc,
          httpClient: MockClient((_) async => http.Response('{}', 200)));
      addTearDown(auth.dispose);
      expect(await auth.authenticate(network: 'mainnet'), isFalse);
    });

    test('server failures do not forward secrets to the device or error UI',
        () async {
      var calls = 0;
      final rpc = JadeRpc(_Transport((request) async {
        calls++;
        return {'id': request['id'], 'result': _httpStep('first', 'pin')};
      }));
      final auth = JadePinAuth(rpc,
          httpClient: MockClient(
              (_) async => http.Response('secret encrypted body', 500)));
      addTearDown(auth.dispose);

      await expectLater(
          auth.authenticate(network: 'mainnet'),
          throwsA(isA<Exception>().having((error) => error.toString(),
              'message', isNot(contains('secret')))));
      expect(calls, 1);
    });
  });
}

Map<String, dynamic> _httpStep(String step, String replyMethod) => {
      'http_request': {
        'params': {
          'urls': ['https://pin.example/$step'],
          'method': 'POST',
          'accept': 'json',
          'data': {'encrypted_request': step}
        },
        'on-reply': replyMethod,
      },
    };

class _Transport extends JadeBleTransport {
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) respond;
  _Transport(this.respond);

  @override
  Future<Map<String, dynamic>> exchange(Map<String, dynamic> request,
          {Duration timeout = const Duration(seconds: 30)}) =>
      respond(request);
}
