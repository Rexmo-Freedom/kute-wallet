// The venue ownership link: a challenge from the backend, signed verbatim
// with EIP-191 by the account's own key, once per account. Terminal
// results are recorded in secure storage; analytics carry venue + result
// only.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_owner_link_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

import '../helpers/runtime_policy_fixture.dart';

final _key = EthPrivateKey.fromHex(
    '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318');
final _address = _key.address.hexWith0x.toLowerCase();
const _deposit = '0x00000000000000000000000000000000000000aa';

String _challenge(String venue) =>
    'kute-$venue-owner-v1|$_address|user:42|nonce123|1700000000|1700000300';

EthSignature _parse(String hex) {
  final bytes = <int>[
    for (var i = 2; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16)
  ];
  BigInt big(List<int> b) =>
      b.fold(BigInt.zero, (acc, x) => (acc << 8) | BigInt.from(x));
  return EthSignature(
      big(bytes.sublist(0, 32)), big(bytes.sublist(32, 64)), bytes[64]);
}

void main() {
  final events = <(String, Map<String, Object>?)>[];
  final requests = <http.Request>[];

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken =
        '${base64Url.encode(utf8.encode('account-a|0|9999999999'))}.sig';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    FlutterSecureStorage.setMockInitialValues({});
    VenueOwnerLinkService.resetForTest();
    events.clear();
    requests.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    AffiliateService.debugSessionToken = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    VenueOwnerLinkService.resetForTest();
  });

  /// Answers the challenge route with [challenge] and the link route with
  /// [link]; records every request.
  MockClient backend({
    required http.Response Function(Map<String, dynamic>) challenge,
    http.Response Function(Map<String, dynamic>)? link,
  }) =>
      MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/api/v1/venue-owner/challenge') {
          return challenge(body);
        }
        if (request.url.path == '/api/v1/venue-owner' && link != null) {
          return link(body);
        }
        throw StateError('unexpected ${request.url}');
      });

  List<Map<String, Object>?> linkEvents() => [
        for (final e in events)
          if (e.$1 == 'venue_account_link_result') e.$2
      ];

  test('personal_sign recovers to the key address with v in {27, 28}',
      () async {
    const message = 'kute-hyperliquid-owner-v1|0xabc|user:1|n|1|2';
    final hex = await VenueOwnerLinkService.personalSign(message, _key);
    expect(hex, matches(RegExp(r'^0x[0-9a-f]{130}$')));
    final sig = _parse(hex);
    expect(sig.v, anyOf(27, 28));
    final digest =
        personalMessageDigest(Uint8List.fromList(utf8.encode(message)));
    expect(recoverSignerAddress(digest, sig), _address);
  });

  test('hyperliquid: signs the challenge verbatim and records the link',
      () async {
    final challenge = _challenge('hyperliquid');
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(
              challenge: (body) {
                expect(body, {'venue': 'hyperliquid', 'address': _address});
                return http.Response(
                    jsonEncode({'challenge': challenge, 'expires_at': 1}), 200);
              },
              link: (body) {
                expect(body['venue'], 'hyperliquid');
                expect(body['address'], _address);
                expect(body.containsKey('trading_address'), isFalse);
                expect(body['challenge'], challenge);
                final digest = personalMessageDigest(
                    Uint8List.fromList(utf8.encode(challenge)));
                expect(
                    recoverSignerAddress(
                        digest, _parse(body['signature'] as String)),
                    _address);
                return http.Response(
                    jsonEncode({
                      'linked': true,
                      'venue': 'hyperliquid',
                      'already_linked': false
                    }),
                    200);
              },
            ));
    expect(result, VenueOwnerLinkResult.linked);
    expect(
        requests
            .every((r) => r.headers['Authorization']!.startsWith('Bearer ')),
        isTrue);
    expect(
        await secureStorage.read(
            key: 'kute_venue_owner_v1:hyperliquid:$_address'),
        'linked');
    expect(linkEvents(), [
      {'venue': 'hyperliquid', 'result': 'linked'}
    ]);
  });

  test('polymarket sends the trading wallet and marks it linked', () async {
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.polymarket,
            key: _key,
            tradingAddress: _deposit.toUpperCase().replaceFirst('0X', '0x')),
        () => backend(
              challenge: (body) {
                expect(body['trading_address'], _deposit);
                return http.Response(
                    jsonEncode({'challenge': _challenge('polymarket')}), 200);
              },
              link: (body) {
                expect(body['trading_address'], _deposit);
                return http.Response(
                    jsonEncode({'linked': true, 'already_linked': true}), 200);
              },
            ));
    expect(result, VenueOwnerLinkResult.alreadyLinked);
    expect(await VenueOwnerLinkService.isPolymarketLinked(_address), isTrue);
    expect(await VenueOwnerLinkService.isPolymarketLinked(_deposit), isTrue);
    expect(linkEvents(), [
      {'venue': 'polymarket', 'result': 'already_linked'}
    ]);
  });

  test('already_linked on the challenge records success without signing',
      () async {
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(
            challenge: (_) =>
                http.Response(jsonEncode({'already_linked': true}), 200)));
    expect(result, VenueOwnerLinkResult.alreadyLinked);
    expect(requests, hasLength(1));
    expect(
        await secureStorage.read(
            key: 'kute_venue_owner_v1:hyperliquid:$_address'),
        'linked');
  });

  test('a recorded link short-circuits without any request or event', () async {
    FlutterSecureStorage.setMockInitialValues(
        {'kute_venue_owner_v1:hyperliquid:$_address': 'linked'});
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => MockClient((_) async => throw StateError('must not send')));
    expect(result, VenueOwnerLinkResult.skipped);
    expect(linkEvents(), isEmpty);
  });

  test('409 is terminal: recorded as conflict and never retried', () async {
    final first = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(
            challenge: (_) => http.Response(
                jsonEncode({'error': 'venue_account_linked_elsewhere'}), 409)));
    expect(first, VenueOwnerLinkResult.conflict);
    expect(
        await secureStorage.read(
            key: 'kute_venue_owner_v1:hyperliquid:$_address'),
        'conflict');

    // A new app session still sends nothing.
    VenueOwnerLinkService.resetForTest();
    final again = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => MockClient((_) async => throw StateError('must not send')));
    expect(again, VenueOwnerLinkResult.skipped);
    expect(linkEvents(), [
      {'venue': 'hyperliquid', 'result': 'conflict'}
    ]);
  });

  test('409 on the link route is terminal too', () async {
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(
            challenge: (_) => http.Response(
                jsonEncode({'challenge': _challenge('hyperliquid')}), 200),
            link: (_) => http.Response('{}', 409)));
    expect(result, VenueOwnerLinkResult.conflict);
  });

  test('a 5xx fails once per session and retries next session', () async {
    var calls = 0;
    Future<VenueOwnerLinkResult> run() => http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(challenge: (_) {
              calls++;
              return http.Response('{}', 503);
            }));
    expect(await run(), VenueOwnerLinkResult.failed);
    expect(await run(), VenueOwnerLinkResult.skipped);
    expect(calls, 1);
    VenueOwnerLinkService.resetForTest(); // next app session
    expect(await run(), VenueOwnerLinkResult.failed);
    expect(calls, 2);
    expect(
        await secureStorage.read(
            key: 'kute_venue_owner_v1:hyperliquid:$_address'),
        isNull);
  });

  test('concurrent calls share one attempt', () async {
    final gate = Completer<void>();
    var calls = 0;
    await http.runWithClient(() async {
      final a = VenueOwnerLinkService.link(
          venue: VenueOwnerLinkService.hyperliquid, key: _key);
      final b = VenueOwnerLinkService.link(
          venue: VenueOwnerLinkService.hyperliquid, key: _key);
      gate.complete();
      expect(await a, VenueOwnerLinkResult.alreadyLinked);
      expect(await b, VenueOwnerLinkResult.alreadyLinked);
    },
        () => MockClient((_) async {
              calls++;
              await gate.future;
              return http.Response(jsonEncode({'already_linked': true}), 200);
            }));
    expect(calls, 1);
    expect(linkEvents(), hasLength(1));
  });

  test('an expired challenge is retried once with a fresh one', () async {
    var challenges = 0;
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(
            challenge: (_) {
              challenges++;
              return http.Response(
                  jsonEncode({'challenge': _challenge('hyperliquid')}), 200);
            },
            link: (_) => challenges == 1
                ? http.Response(jsonEncode({'error': 'challenge_expired'}), 400)
                : http.Response(jsonEncode({'linked': true}), 200)));
    expect(result, VenueOwnerLinkResult.linked);
    expect(challenges, 2);
    expect(linkEvents(), hasLength(1));
  });

  test('400 rejections stop after a few sessions', () async {
    var calls = 0;
    for (var session = 0; session < 5; session++) {
      VenueOwnerLinkService.resetForTest();
      await http.runWithClient(
          () => VenueOwnerLinkService.link(
              venue: VenueOwnerLinkService.hyperliquid, key: _key),
          () => backend(challenge: (_) {
                calls++;
                return http.Response(
                    jsonEncode({'error': 'invalid_request'}), 400);
              }));
    }
    expect(calls, 3);
  });

  test('a challenge for another account or venue is never signed', () async {
    final result = await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => backend(
            challenge: (_) => http.Response(
                jsonEncode({'challenge': _challenge('polymarket')}), 200)));
    expect(result, VenueOwnerLinkResult.failed);
    expect(requests, hasLength(1));
  });

  test('tracked params carry venue and result only, no address or secrets',
      () async {
    final challenge = _challenge('polymarket');
    String? signature;
    await http.runWithClient(
        () => VenueOwnerLinkService.link(
            venue: VenueOwnerLinkService.polymarket,
            key: _key,
            tradingAddress: _deposit),
        () => backend(
              challenge: (_) =>
                  http.Response(jsonEncode({'challenge': challenge}), 200),
              link: (body) {
                signature = body['signature'] as String;
                return http.Response(jsonEncode({'linked': true}), 200);
              },
            ));
    final params = linkEvents();
    expect(params, hasLength(1));
    expect(params.single!.keys.toSet(), {'venue', 'result'});
    final flat = params.single.toString().toLowerCase();
    for (final secret in [
      _address,
      _deposit,
      signature!,
      challenge,
      'nonce123',
      'user:42'
    ]) {
      expect(flat, isNot(contains(secret.toLowerCase())));
    }
  });

  test('a network failure never throws to the caller', () async {
    await http.runWithClient(
        () => VenueOwnerLinkService.ensureLinked(
            venue: VenueOwnerLinkService.hyperliquid, key: _key),
        () => MockClient((_) async => throw http.ClientException('offline')));
    expect(linkEvents(), [
      {'venue': 'hyperliquid', 'result': 'failed'}
    ]);
  });
}
