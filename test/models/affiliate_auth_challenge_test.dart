import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _pubkey =
    '02a1633cafcc01ebfb6d78e39f687a1f0995c62fc95f51ead10a02ee0be551b5dc';
const _otherPubkey =
    '03b1633cafcc01ebfb6d78e39f687a1f0995c62fc95f51ead10a02ee0be551b5dc';
final _nonce = 'ab' * 32;
final _signature = 'cd' * 65;

String _sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final signed = <String>[];
  final events = <(String, Map<String, Object>?)>[];
  final requests = <http.Request>[];

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    FlutterSecureStorage.setMockInitialValues({});
    signed.clear();
    events.clear();
    requests.clear();
    AppsFlyerService.clearCapturedReferrer();
    WalletIdentityService.debugBind(
      pubkey: _pubkey,
      signer: (message) async {
        signed.add(message);
        return _signature;
      },
    );
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    WalletIdentityService.debugBind(pubkey: null);
    TrackingService.debugTrackObserver = null;
  });

  String challengeFor(String pubkey, {required int expiresInSeconds}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'kute-auth-v2|$pubkey|$_nonce|$now|${now + expiresInSeconds}';
  }

  Future<Map<String, dynamic>?> auth({
    required http.Response Function() challengeResponse,
    int walletStatus = 401,
    String? referrer,
  }) =>
      http.runWithClient(
        () => AffiliateService.authWallet(
          paykuteAddress: 'alice@paykute.com',
          referredByCode: referrer,
        ),
        () => MockClient((req) async {
          requests.add(req);
          if (req.url.path == '/api/v1/affiliate/auth/challenge') {
            return challengeResponse();
          }
          if (req.url.path == '/api/v1/affiliate/auth/wallet') {
            return http.Response('{"error":"invalid signature"}', walletStatus);
          }
          return http.Response('not found', 404);
        }),
      );

  List<String> paths() => requests.map((r) => r.url.path).toList();

  Map<String, dynamic> walletBody() => jsonDecode(requests
      .singleWhere((r) => r.url.path == '/api/v1/affiliate/auth/wallet')
      .body) as Map<String, dynamic>;

  test('v2: signs the server challenge bound to the exact posted body',
      () async {
    final challenge = challengeFor(_pubkey, expiresInSeconds: 300);
    await auth(
      referrer: 'FRIEND7',
      challengeResponse: () =>
          http.Response(jsonEncode({'challenge': challenge}), 200),
    );

    expect(paths(), [
      '/api/v1/affiliate/auth/challenge',
      '/api/v1/affiliate/auth/wallet',
    ]);
    expect(jsonDecode(requests.first.body), {'pubkey': _pubkey});

    final body = walletBody();
    final canonical = [
      body['paykute_address'] ?? '',
      body['referred_by_code'] ?? '',
      body['appsflyer_id'] ?? '',
      body['af_platform'] ?? '',
    ].join('\n');
    expect(body['paykute_address'], 'alice@paykute.com');
    expect(body['referred_by_code'], 'FRIEND7');
    expect(body['challenge'], '$challenge|${_sha256Hex(canonical)}');
    expect(body['pubkey'], _pubkey);
    expect(body['signature'], _signature);
    expect(signed, [body['challenge']]);
    expect(
        events.where((e) => e.$1 == 'wallet_auth_challenge').map((e) => e.$2),
        [
          {'mode': 'v2'}
        ]);
  });

  test('the digest changes when a bound field changes', () {
    final a = WalletIdentityService.canonicalAuthBodyDigest(
        paykuteAddress: 'alice@paykute.com');
    final b = WalletIdentityService.canonicalAuthBodyDigest(
        paykuteAddress: 'mallory@paykute.com');
    final c = WalletIdentityService.canonicalAuthBodyDigest(
        paykuteAddress: 'alice@paykute.com', referredByCode: 'X');
    expect(a, _sha256Hex('alice@paykute.com\n\n\n'));
    expect({a, b, c}, hasLength(3));
  });

  test('a challenge for another pubkey is refused and nothing is signed',
      () async {
    final result = await auth(
      challengeResponse: () => http.Response(
          jsonEncode({
            'challenge': challengeFor(_otherPubkey, expiresInSeconds: 300)
          }),
          200),
    );
    expect(result, isNull);
    expect(signed, isEmpty);
    expect(paths(), ['/api/v1/affiliate/auth/challenge']);
  });

  test('an expired challenge is refused and nothing is signed', () async {
    final result = await auth(
      challengeResponse: () => http.Response(
          jsonEncode({'challenge': challengeFor(_pubkey, expiresInSeconds: -1)}),
          200),
    );
    expect(result, isNull);
    expect(signed, isEmpty);
    expect(paths(), ['/api/v1/affiliate/auth/challenge']);
  });

  group('device clock skew', () {
    final issued = DateTime.utc(2026, 9, 15, 12);
    final issuedUnix = issued.millisecondsSinceEpoch ~/ 1000;
    String challenge({int lifetime = 300}) =>
        'kute-auth-v2|$_pubkey|$_nonce|$issuedUnix|${issuedUnix + lifetime}';

    test('a clock up to 5 minutes past expiry still signs', () async {
      final r = await WalletIdentityService.buildAuthChallengeV2(challenge(),
          bodyDigest: _sha256Hex('x'),
          now: issued.add(const Duration(minutes: 9, seconds: 59)));
      expect(r, isNotEmpty);
    });

    test('a clock more than 5 minutes past expiry refuses', () async {
      final r = await WalletIdentityService.buildAuthChallengeV2(challenge(),
          bodyDigest: _sha256Hex('x'),
          now: issued.add(const Duration(minutes: 10)));
      expect(r, isEmpty);
    });

    test('a validity window over 10 minutes is refused', () async {
      final r = await WalletIdentityService.buildAuthChallengeV2(
          challenge(lifetime: 601),
          bodyDigest: _sha256Hex('x'),
          now: issued);
      expect(r, isEmpty);
    });
  });

  test('a malformed challenge is refused', () {
    return Future.wait([
      for (final bad in [
        'kute-auth|$_pubkey|$_nonce|1',
        'kute-auth-v2|$_pubkey|short|1|9999999999',
        'kute-auth-v2|$_pubkey|$_nonce|10|5',
      ])
        WalletIdentityService.buildAuthChallengeV2(bad,
                bodyDigest: _sha256Hex('x'))
            .then((r) => expect(r, isEmpty, reason: bad)),
    ]).then((_) => expect(signed, isEmpty));
  });

  for (final status in [404, 405]) {
    test('$status on the challenge route is an error, never a legacy challenge',
        () async {
      final result = await auth(challengeResponse: () => http.Response('', status));
      expect(result, isNull);
      expect(signed, isEmpty);
      expect(paths(), ['/api/v1/affiliate/auth/challenge']);
      expect(events.where((e) => e.$1 == 'wallet_auth_challenge'), isEmpty);
    });
  }

  test('no legacy kute-auth challenge format remains in the app', () {
    final legacy = RegExp(r"kute-auth\|");
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => legacy.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty);
  });

  test('other challenge failures do not fall back to legacy', () async {
    final result = await auth(
        challengeResponse: () => http.Response('{"error":"x"}', 500));
    expect(result, isNull);
    expect(signed, isEmpty);
    expect(paths(), ['/api/v1/affiliate/auth/challenge']);
  });

  test('a 401 from auth/wallet does not loop', () async {
    final result = await auth(
      challengeResponse: () => http.Response(
          jsonEncode({'challenge': challengeFor(_pubkey, expiresInSeconds: 300)}),
          200),
    );
    expect(result, isNull);
    expect(paths().where((p) => p.endsWith('/auth/wallet')), hasLength(1));
    expect(paths().where((p) => p.endsWith('/auth/challenge')), hasLength(1));
  });
}
