// The real `branta` package behind BrantaPayeeService, offline: Branta's
// own published staging sample codes (developer.branta.pro, Send →
// Staging) against the registry's recorded answers
// (test/fixtures/branta/staging_payments.json, fetched 12 November 2026).
//
// Checks the whole chain Send relies on, per rail: on-chain bitcoin, a
// Lightning invoice, USDC and USDT on Polygon (`pol:`), the swapped-address
// warning, and the privacy model: what reaches Branta is the encrypted
// id (or the invoice encrypted under its own hash), never the address,
// the invoice or the secret; a bare address sends nothing at all.

import 'dart:convert';
import 'dart:io';

import 'package:branta/branta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/branta/branta_payee_service.dart';

const _btcAddr = 'bc1qgw3dzmhnyvcswc9r0v0z0ajtp8ulm4nuyeahwr';
const _btcSecret = '05eb145d-b5cb-452a-9256-0bdfd9a15ffa';
const _btcCode = 'bitcoin:$_btcAddr?branta_id=6SpYCe23r79x0t8rNvmjWqhrg8hen4xz'
    '%2FYSXhNJ9HLSYrTRPnm%2BSwAuf6NOKobnwE%2B3MQBNkyTnCtIWpKKX2E9ZUWVedig%3D%3D'
    '&branta_secret=$_btcSecret';

/// Branta's Tampered sample: the Not found address with the params of the
/// bitcoin sample.
const _swapped = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
const _tamperedCode = 'bitcoin:$_swapped?branta_id=6SpYCe23r79x0t8rNvmjWqhrg8hen4xz'
    '%2FYSXhNJ9HLSYrTRPnm%2BSwAuf6NOKobnwE%2B3MQBNkyTnCtIWpKKX2E9ZUWVedig%3D%3D'
    '&branta_secret=$_btcSecret';

const _usdcAddr = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';
const _usdcCode = 'pol:$_usdcAddr?value=50&user=send&currency=USD'
    '&branta_id=8rnGGWZcg%2Fg3He1OK6yZ6OLOEyusldwIDaoPImRzWjoUGguyXKotuF8ZlGbCZN9TRqx3PdXjvHDdwffdVvIZxmZ00xJvxA%3D%3D'
    '&branta_secret=0515039f-2c31-4467-b62a-4e919079a44e';

const _usdtAddr = '0x278297528c32eCa01295B0d2135984d3442ec963';
const _usdtCode = 'pol:$_usdtAddr?value=50&user=send&currency=USD'
    '&branta_id=4WYE9J4TjNitdX7AL%2Fw7frpYdKGwSKHCS5zpFXl%2FlQGwpsQi4%2Fgv5MxgujPFzYMbIKqg2rtyYGpzJCllEA6Qudbi7lLkiA%3D%3D'
    '&branta_secret=c0fab1ee-1526-4efa-b991-9ee138a44cd2';

const _invoice =
    'lnbc10u1p4w23tzpp50uc6g4020tt3ffp5xfpp83k0lcv2spytpymuupqrnsj0eth8jqgsd'
    'qhgfexzmn5vys8xarpva5kuecxq97zvuqsp5tj2a5fd84lhdddzfqz2lwmjqg7n9gp28yy5'
    'vtqd78muyzdt5tmsq9qypsqqcqpf6yv66fkcq609xzk0fcqx82hd7fsjhwrzj8xmq743v5l'
    'rtssrj95r94hyeumqeejgqvtxqy7ks7ec0uc5lc5zxg240xtwgzjtwkmh3aqqm8gyny';

void main() {
  late Map<String, dynamic> fixtures;
  final requests = <Uri>[];
  late BrantaService sdk;
  late BrantaPayeeService service;

  setUpAll(() {
    fixtures = jsonDecode(
            File('test/fixtures/branta/staging_payments.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  setUp(() {
    requests.clear();
    // The registry: a lookup value that is a recorded payment's own
    // (encrypted) destination answers with it; anything else is a 404.
    final client = MockClient((request) async {
      requests.add(request.url);
      final value = request.url.pathSegments.last;
      for (final payments in fixtures.values) {
        final list = payments as List;
        final first = (list.first as Map)['destinations'] as List;
        if ((first.first as Map)['value'] == value) {
          return http.Response(jsonEncode(list), 200,
              headers: {'content-type': 'application/json'});
        }
      }
      return http.Response('', 404);
    });
    sdk = BrantaService(
        environment: BrantaEnvironment.staging, httpClient: client);
    service = BrantaPayeeService(verifier: sdk.verify);
  });

  /// No request carried any of [secrets] (case-insensitive).
  void expectNothingLeaked(List<String> secrets) {
    for (final uri in requests) {
      final sent = Uri.decodeFull(uri.toString()).toLowerCase();
      for (final s in secrets) {
        expect(sent.contains(s.toLowerCase()), isFalse,
            reason: 'a lookup carried "$s": $uri');
      }
    }
  }

  test('on-chain bitcoin: the payee, looked up by the encrypted id only',
      () async {
    service.noteInput(_btcCode);
    final payee = await service.lookup(_btcAddr, BrantaRail.bitcoinOnchain);
    expect(payee?.verified, isTrue);
    expect(payee?.name, 'Branta');
    expect(payee?.logoUrl,
        startsWith('https://staging.guardrail.branta.pro/'));
    expect(requests, hasLength(1));
    expect(requests.single.host, 'staging.guardrail.branta.pro');
    expectNothingLeaked([_btcAddr, _btcSecret]);
    // Paid on Lightning instead, the same code names nobody.
    expect(await service.lookup(_btcAddr, BrantaRail.lightning), isNull);
  });

  test('a swapped address: the warning, never a payee', () async {
    service.noteInput(_tamperedCode);
    final payee = await service.lookup(_swapped, BrantaRail.bitcoinOnchain);
    expect(payee, const BrantaPayee.tampered());
    expectNothingLeaked([_swapped, _btcSecret]);
  });

  test('Lightning: the bare invoice, sent only encrypted under its own hash',
      () async {
    final payee = await service.lookup(_invoice, BrantaRail.lightning);
    expect(payee?.verified, isTrue);
    expect(payee?.name, 'Branta');
    expect(requests, hasLength(1));
    expectNothingLeaked([_invoice.substring(0, 40)]);
  });

  test('USDC on Polygon: the payee only when paid as USDC on Polygon',
      () async {
    service.noteInput(_usdcCode);
    final payee = await service.lookup(_usdcAddr, BrantaRail.usdcPolygon);
    expect(payee?.verified, isTrue);
    expect(payee?.name, 'Branta');
    expect(await service.lookup(_usdcAddr, BrantaRail.usdtPolygon), isNull);
    expectNothingLeaked([_usdcAddr, '0515039f-2c31-4467-b62a-4e919079a44e']);
  });

  test('USDT on Polygon: the payee only when paid as USDT on Polygon',
      () async {
    service.noteInput(_usdtCode);
    expect((await service.lookup(_usdtAddr, BrantaRail.usdtPolygon))?.name,
        'Branta');
    expect(await service.lookup(_usdtAddr, BrantaRail.usdcPolygon), isNull);
    expectNothingLeaked([_usdtAddr, 'c0fab1ee-1526-4efa-b991-9ee138a44cd2']);
  });

  test('a bare address or a bare 0x reaches Branta not at all', () async {
    expect(await service.lookup(_btcAddr, BrantaRail.bitcoinOnchain), isNull);
    expect(await service.lookup(_usdcAddr, BrantaRail.usdcPolygon), isNull);
    expect(requests, isEmpty);
    // Even straight through the package.
    expect((await sdk.verify(_btcAddr)).status, VerifyStatus.unknown);
    expect((await sdk.verify(_usdcAddr)).status, VerifyStatus.unknown);
    expect(requests, isEmpty);
  });
}
