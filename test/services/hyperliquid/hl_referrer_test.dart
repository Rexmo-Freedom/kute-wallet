// Kute as the Hyperliquid referrer of the hot Investing account: set once,
// silently, only when the backend publishes a code, the policy allows
// `hyperliquid.trade` and `hyperliquid.referrer` and the venue shows no
// referrer. A failure never
// blocks and never loops; only a network failure (or an account the venue
// does not know yet) is tried again in a later session.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hardware/evm_signer.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_referral_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;
import 'package:web3dart/web3dart.dart'
    show MsgSignature, ecRecover, publicKeyToAddress;

const _user = '0x42187A0F42088287EbFE8c20BB7adF111e93c381';
const _builder = '0x1111111111111111111111111111111111111111';

class _FakeExchange implements HyperliquidExchangeService {
  _FakeExchange({this.signer, this.onSet});

  final EvmExternalSigner? signer;
  final Future<void> Function()? onSet;
  final codes = <String>[];

  @override
  String get walletAddress => _user;

  @override
  EvmExternalSigner? get externalSigner => signer;

  @override
  Future<void> setReferrer({required String code}) async {
    codes.add(code);
    await onSet?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final events = <(String, Map<String, Object>?)>[];
  var referralQueries = 0;
  var builderHits = 0;

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    HyperliquidFundingService.resetBuilderCacheForTest();
    HyperliquidReferralService.resetForTest();
    FlutterSecureStorage.setMockInitialValues({});
    events.clear();
    referralQueries = 0;
    builderHits = 0;
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    HyperliquidFundingService.resetBuilderCacheForTest();
    HyperliquidReferralService.resetForTest();
  });

  /// [code] is what the backend publishes; null leaves the key out.
  /// [referredBy] is the venue's `referral` answer; [infoDown] makes the
  /// venue unreachable.
  MockClient backend({
    String? code,
    bool builderConfigured = true,
    Map<String, dynamic>? referredBy,
    bool infoDown = false,
  }) =>
      MockClient((req) async {
        if (req.url.path == '/api/v1/hl/builder') {
          builderHits++;
          final body = {
            if (builderConfigured) ...{
              'builderAddress': _builder,
              'defaultFeeTenthsBp': 10,
              'maxFeeRate': '0.01%',
            },
            if (code != null) 'referralCode': code,
          };
          return http.Response(jsonEncode(body), builderConfigured ? 200 : 404);
        }
        if (req.url.toString() == HyperliquidConstants.infoUri.toString()) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['type'], 'referral');
          referralQueries++;
          if (infoDown) throw http.ClientException('connection refused');
          return http.Response(
              jsonEncode({'referredBy': referredBy, 'cumVlm': '0.0'}), 200);
        }
        return http.Response('not found', 404);
      });

  /// [denied] lists the capabilities the policy refuses.
  Future<HlReferrerOutcome> ensure(_FakeExchange exchange, MockClient client,
          {Set<String> denied = const {}}) =>
      http.runWithClient(
        () => HyperliquidReferralService.ensureReferrerSet(
          exchange: exchange,
          allows: (id) => !denied.contains(id),
        ),
        () => client,
      );

  List<Map<String, Object>?> referrerEvents() => [
        for (final e in events)
          if (e.$1 == 'hl_referrer_set') e.$2
      ];

  /// A new app session: the in-memory guard is gone, storage stays.
  void newSession() {
    HyperliquidReferralService.resetForTest();
    HyperliquidFundingService.resetBuilderCacheForTest();
  }

  group('referral code from the backend', () {
    Future<String?> codeFrom(MockClient client) => http.runWithClient(
        HyperliquidFundingService.getReferralCode, () => client);

    test('a well-formed code is read alongside the builder', () async {
      expect(await codeFrom(backend(code: 'KUTE2026')), 'KUTE2026');
    });

    test('also read when no builder is configured (404)', () async {
      expect(await codeFrom(backend(code: 'KUTE', builderConfigured: false)),
          'KUTE');
    });

    test('empty, absent or malformed means none', () async {
      for (final code in [null, '', 'kute', 'KU TE', 'A' * 21, 'KUTE!']) {
        HyperliquidFundingService.resetBuilderCacheForTest();
        expect(await codeFrom(backend(code: code)), isNull, reason: '$code');
      }
    });
  });

  test('sets the referrer when a code is configured and none is set', () async {
    final exchange = _FakeExchange();
    final client = backend(code: 'KUTE');

    expect(await ensure(exchange, client), HlReferrerOutcome.ok);
    expect(exchange.codes, ['KUTE']);
    expect(referrerEvents(), [
      {'result': 'ok'}
    ]);

    // Once per account: neither this session nor the next asks again.
    expect(await ensure(exchange, client), HlReferrerOutcome.skipped);
    newSession();
    expect(await ensure(exchange, client), HlReferrerOutcome.skipped);
    expect(exchange.codes, ['KUTE']);
    expect(referralQueries, 1);
  });

  test('skipped when the account already has a referrer', () async {
    final exchange = _FakeExchange();
    final client = backend(code: 'KUTE', referredBy: {
      'referrer': '0x3333333333333333333333333333333333333333',
      'code': 'OTHER',
    });

    expect(await ensure(exchange, client), HlReferrerOutcome.alreadySet);
    expect(exchange.codes, isEmpty);
    expect(referrerEvents(), [
      {'result': 'already_set'}
    ]);
    newSession();
    expect(await ensure(exchange, client), HlReferrerOutcome.skipped);
    expect(referralQueries, 1);
  });

  test('off by default: no code published means nothing is sent', () async {
    final exchange = _FakeExchange();
    for (final code in [null, '']) {
      newSession();
      expect(await ensure(exchange, backend(code: code)),
          HlReferrerOutcome.skipped);
    }
    expect(exchange.codes, isEmpty);
    expect(referralQueries, 0);
    expect(referrerEvents(), isEmpty);

    // Publishing a code later switches it on.
    newSession();
    expect(await ensure(exchange, backend(code: 'KUTE')), HlReferrerOutcome.ok);
    expect(exchange.codes, ['KUTE']);
  });

  test('skipped when hyperliquid.trade is denied', () async {
    final exchange = _FakeExchange();
    expect(
        await ensure(exchange, backend(code: 'KUTE'),
            denied: {'hyperliquid.trade'}),
        HlReferrerOutcome.skipped);
    expect(exchange.codes, isEmpty);
    expect(builderHits, 0);
    expect(referralQueries, 0);
    expect(referrerEvents(), isEmpty);
  });

  test('skipped where hyperliquid.referrer is denied, then set once allowed',
      () async {
    final exchange = _FakeExchange();
    final client = backend(code: 'KUTE');
    expect(await ensure(exchange, client, denied: {'hyperliquid.referrer'}),
        HlReferrerOutcome.skipped);
    expect(exchange.codes, isEmpty);
    expect(builderHits, 0);
    expect(referralQueries, 0);
    expect(referrerEvents(), isEmpty);

    // A denial records nothing: a later policy that allows it still sets.
    newSession();
    expect(await ensure(exchange, client), HlReferrerOutcome.ok);
    expect(exchange.codes, ['KUTE']);
  });

  test('an unreachable policy denies the referrer: nothing is sent', () async {
    // hyperliquid.referrer is not in the offline table, so with no policy
    // loaded it is denied.
    expect(
        kOfflineAllowedCapabilities, isNot(contains('hyperliquid.referrer')));
    final policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async => http.Response('down', 503)),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => null,
      appVersion: () async => '2.0.4',
    );
    addTearDown(policy.dispose);
    expect(await policy.refresh(), isFalse);
    final exchange = _FakeExchange();
    expect(
        await http.runWithClient(
            () => HyperliquidReferralService.ensureReferrerSet(
                exchange: exchange, allows: policy.allows),
            () => backend(code: 'KUTE')),
        HlReferrerOutcome.skipped);
    expect(exchange.codes, isEmpty);
    expect(referralQueries, 0);
  });

  test('skipped for a Ledger signer', () async {
    final exchange = _FakeExchange(
        signer: EvmExternalSigner(
            address: _user,
            sign: (_) async => throw StateError('never signs')));
    expect(await ensure(exchange, backend(code: 'KUTE')),
        HlReferrerOutcome.skipped);
    expect(exchange.codes, isEmpty);
    expect(referralQueries, 0);
  });

  test('a rejection is recorded as failed, never thrown and never retried',
      () async {
    final exchange = _FakeExchange(
        onSet: () async =>
            throw const HyperliquidRejectedException('Cannot set referrer'));
    final client = backend(code: 'KUTE');

    expect(await ensure(exchange, client), HlReferrerOutcome.failed);
    expect(referrerEvents(), [
      {'result': 'failed'}
    ]);
    for (var i = 0; i < 3; i++) {
      expect(await ensure(exchange, client), HlReferrerOutcome.skipped);
      newSession();
    }
    expect(exchange.codes, ['KUTE']);
  });

  test('a venue "already" answer counts as already set', () async {
    final exchange = _FakeExchange(
        onSet: () async =>
            throw const HyperliquidRejectedException('Referrer already set'));
    expect(await ensure(exchange, backend(code: 'KUTE')),
        HlReferrerOutcome.alreadySet);
    expect(referrerEvents(), [
      {'result': 'already_set'}
    ]);
  });

  test('a network failure waits for the next session, once per session',
      () async {
    var fail = true;
    final exchange = _FakeExchange(onSet: () async {
      if (fail) throw http.ClientException('connection refused');
    });
    final client = backend(code: 'KUTE');

    expect(await ensure(exchange, client), HlReferrerOutcome.retryLater);
    expect(await ensure(exchange, client), HlReferrerOutcome.skipped);
    expect(exchange.codes, ['KUTE']);
    expect(referrerEvents(), isEmpty);

    newSession();
    fail = false;
    expect(await ensure(exchange, client), HlReferrerOutcome.ok);
    expect(exchange.codes, ['KUTE', 'KUTE']);
  });

  test('an unreachable referral lookup sends nothing and waits', () async {
    final exchange = _FakeExchange();
    expect(await ensure(exchange, backend(code: 'KUTE', infoDown: true)),
        HlReferrerOutcome.retryLater);
    expect(await ensure(exchange, backend(code: 'KUTE')),
        HlReferrerOutcome.skipped);
    expect(exchange.codes, isEmpty);
  });

  test('an account the venue does not know yet may be asked again', () async {
    var exists = false;
    final exchange = _FakeExchange(onSet: () async {
      if (!exists) {
        throw const HyperliquidSignatureRejectedException(
            'User or API Wallet does not exist.');
      }
    });
    final client = backend(code: 'KUTE');

    expect(await ensure(exchange, client), HlReferrerOutcome.retryLater);
    exists = true;
    expect(await ensure(exchange, client), HlReferrerOutcome.ok);
    expect(referrerEvents(), [
      {'result': 'ok'}
    ]);
  });

  test('the posted action is the SDK shape, signed by the account key',
      () async {
    final key = EthPrivateKey.fromHex(
        '0x0123456789012345678901234567890101234567890123456789012345678901');
    final signer = key.address.hexEip55.toLowerCase();
    Map<String, dynamic>? posted;
    final service = HyperliquidExchangeService(
      credentials: key,
      walletAddress: key.address.hexEip55,
      httpClient: MockClient((request) async {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'status': 'ok',
              'response': {'type': 'default'}
            }),
            200);
      }),
    );

    await service.setReferrer(code: 'KUTE');

    final body = posted!;
    // Exchange.set_referrer: {"type": "setReferrer", "code": code}, in
    // that key order (msgpack hashes the order), no vault.
    expect(jsonEncode(body['action']), '{"type":"setReferrer","code":"KUTE"}');
    expect(body['vaultAddress'], isNull);

    final connectionId = actionHash(
        action: body['action'] as Map<String, dynamic>,
        nonce: body['nonce'] as int);
    final digest = l1ActionDigest(
        connectionId: connectionId, isMainnet: HyperliquidConstants.isMainnet);
    final sig = body['signature'] as Map<String, dynamic>;
    final pub = ecRecover(
        Uint8List.fromList(digest),
        MsgSignature(
          BigInt.parse((sig['r'] as String).substring(2), radix: 16),
          BigInt.parse((sig['s'] as String).substring(2), radix: 16),
          sig['v'] as int,
        ));
    final recovered =
        '0x${publicKeyToAddress(pub).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    expect(recovered, signer);
  });
}
