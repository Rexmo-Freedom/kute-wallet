import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:web3dart/web3dart.dart'
    show ecRecover, publicKeyToAddress, MsgSignature;
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const _source = '0x1111111111111111111111111111111111111111';
const _target = '0x2222222222222222222222222222222222222222';
const _hash =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherHash =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _nonce = 1780000000000;

Map<String, dynamic> _update(
        {String hash = _hash,
        int time = _nonce + 20,
        String token = 'USDC',
        String source = _source,
        String target = _target,
        String amount = '12.12345678'}) =>
    {
      'hash': hash,
      'time': time,
      'delta': {
        'type': 'spotTransfer',
        'token': token,
        'user': source,
        'destination': target,
        'amount': amount,
      }
    };

void main() {
  T noRead<T>(ProviderListenable<T> _) =>
      throw StateError('Must not read a wallet');

  test('retired Arbitrum pairs cannot resolve an Investing account', () {
    for (final deposit in [true, false]) {
      final route = RouteKey(
          fromChain: deposit ? 'spark' : 'arbitrum',
          fromAsset: deposit ? 'BTC' : 'USDC',
          toChain: deposit ? 'arbitrum' : 'spark',
          toAsset: deposit ? 'USDC' : 'BTC');
      expect(
          () => checkSettlementAccountPair(
              route: route,
              source: deposit
                  ? SettlementAccountKind.sparkHot
                  : SettlementAccountKind.hlHot,
              destination: deposit
                  ? SettlementAccountKind.hlHot
                  : SettlementAccountKind.sparkHot),
          throwsA(isA<WalletGuardException>()));
    }
    expect(
        () => checkSettlementAccountPair(
            route: kSparkToHypercoreRoute,
            source: SettlementAccountKind.sparkHot,
            destination: SettlementAccountKind.hlHot),
        returnsNormally);
  });

  test('native route flag and pause block before a wallet or funds are touched',
      () async {
    final disabled = SparkHypercoreFundingService(noRead, enabled: false);
    expect(await disabled.tryDirect(deposit: true), isFalse);
    await expectLater(
        disabled.depositFromSpark(
            asset: SparkFundingAsset.bitcoin,
            amountBaseUnits: BigInt.from(10000)),
        throwsA(isA<HypercoreFundingUnavailable>()));
    final paused = SparkHypercoreFundingService(noRead,
        pausePolicy: RoutePausePolicy(readFlag: (_) async => true));
    await expectLater(
        paused.ensureAvailable(deposit: true),
        throwsA(isA<HypercoreFundingUnavailable>().having((e) => e.reason,
            'reason', HypercoreFundingUnavailableReason.paused)));
  });

  test(
      'native funding uses spendable spot cash, excluding held USDC and other assets',
      () {
    const spot = [
      HlSpotBalance(coin: 'USDC', total: 20, hold: 4),
      HlSpotBalance(coin: 'HYPE', total: 100, hold: 0)
    ];
    expect(hypercoreAvailableUsdc(5, spot), 21);
    expect(
        hypercorePerpFundingAmount(
            requiredUsd: 12, perpAvailable: 5, spot: spot),
        7);
    expect(
        hypercorePerpFundingAmount(
            requiredUsd: 50, perpAvailable: 5, spot: spot),
        16);
    expect(
        hypercorePerpFundingAmount(
            requiredUsd: 2, perpAvailable: 5, spot: spot),
        0);
  });

  test('native funding pins its spending wallet before availability awaits',
      () async {
    Settings settingsFor(String id) => Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: true,
          biometricsEnabled: true,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [
            WalletConfig(id: id, name: 'Spending'),
            WalletConfig(id: 'ledger', name: 'Ledger', isHardware: true),
          ],
          activeWalletId: 'ledger',
        );
    var settings = settingsFor('original');
    T read<T>(ProviderListenable<T> provider) {
      if (identical(provider, settingsProvider)) return settings as T;
      throw StateError('Address or funding read after wallet changed');
    }

    final service = SparkHypercoreFundingService(read,
        pausePolicy: RoutePausePolicy(readFlag: (_) async {
      settings = settingsFor('replacement');
      return false;
    }));
    await expectLater(
        service.depositFromSpark(
            asset: SparkFundingAsset.bitcoin,
            amountBaseUnits: BigInt.from(10000)),
        throwsA(isA<WalletGuardException>()
            .having((e) => e.field, 'changed owner', 'wallet')));
  });

  test('native USDC wire preserves all 8 decimals without double rounding', () {
    expect(hypercoreUsdcWire(BigInt.from(1212345678)), '12.12345678');
    expect(hypercoreUsdcWire(BigInt.one), '0.00000001');
    expect(() => hypercoreUsdcWire(BigInt.zero), throwsArgumentError);
  });

  test('perpetuals funding rejects sub-micro dust and preserves catalog scale',
      () {
    expect(hypercorePerpUsdcWire(BigInt.from(1605000000)), '16.050000');
    expect(() => hypercorePerpUsdcWire(BigInt.from(1605000001)),
        throwsArgumentError);
    expect(usesHypercorePerpFunding('hypercore_to_spark_perps_v2'), isTrue);
    expect(usesHypercorePerpFunding('hypercore_to_spark_v1'), isFalse);
    expect(usesHypercorePerpFunding(null), isFalse);
  });

  test('perpetuals funding proof rejects spot sends and checks original nonce',
      () async {
    var wrongNonce = false;
    final units = BigInt.from(1605000000);
    final event = {
      'hash': _hash,
      'time': _nonce + 20,
      'delta': {
        'type': 'internalTransfer',
        'usdc': '16.05',
        'user': _source,
        'destination': _target,
        'fee': '0.0'
      }
    };
    expect(
        matchHypercorePerpTransfer(
            updates: [_update(amount: '16.05')],
            source: _source,
            destination: _target,
            amountBaseUnits: units,
            nonce: _nonce),
        isNull);
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      if (body['type'] == 'userNonFundingLedgerUpdates') {
        return http.Response(jsonEncode([event]), 200);
      }
      return http.Response(
          jsonEncode({
            'type': 'txDetails',
            'tx': {
              'hash': _hash,
              'user': _source,
              'error': null,
              'action': {
                'type': 'usdSend',
                'destination': _target,
                'amount': '16.050000',
                'time': wrongNonce ? _nonce + 1 : _nonce
              }
            }
          }),
          200);
    });
    addTearDown(client.close);
    Future<String?> proof() => readHypercorePerpTransferHash(
        source: _source,
        destination: _target,
        amountBaseUnits: units,
        nonce: _nonce,
        client: client);
    expect(await proof(), _hash);
    wrongNonce = true;
    expect(await proof(), isNull);
  });

  test('native USDC signing identity is verified independently of route ID',
      () async {
    expect(orchestraHypercoreUsdcId, '0x00000000000000000000000000000000');
    expect(hypercoreUsdcToken, 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054');
    final token = <String, Object>{
      'name': 'USDC',
      'index': 0,
      'weiDecimals': 8,
      'tokenId': '0x6d1e7cde53ba9467b783cb7c530ce054', // gitleaks:allow (public HyperCore token id)
      'isCanonical': true,
    };
    final client = MockClient((request) async {
      expect(jsonDecode(request.body), {'type': 'spotMeta'});
      return http.Response(
          jsonEncode({
            'tokens': [token]
          }),
          200);
    });
    await verifyHypercoreUsdcMetadata(client: client);
    for (final mismatch in [
      {'tokenId': orchestraHypercoreUsdcId},
      {'weiDecimals': 6},
      {'isCanonical': false},
      {'index': 1},
    ]) {
      expect(
          isCanonicalHypercoreUsdcMetadata({
            'tokens': [
              {...token, ...mismatch}
            ]
          }),
          isFalse);
    }
    expect(
        isCanonicalHypercoreUsdcMetadata({
          'tokens': [token, token]
        }),
        isFalse);
    token['tokenId'] = orchestraHypercoreUsdcId;
    await expectLater(
        verifyHypercoreUsdcMetadata(client: client), throwsStateError);
    client.close();
  });

  String? match(List<Map<String, dynamic>> updates) =>
      matchHypercoreSpotTransfer(
          updates: updates,
          source: _source,
          destination: _target,
          amountBaseUnits: BigInt.from(1212345678),
          nonce: _nonce);

  test(
      'native proof matches only exact account, destination, token, amount and time',
      () {
    expect(match([_update()]), _hash);
    for (final other in [
      _update(source: _target),
      _update(target: _source),
      _update(token: 'USDT'),
      _update(amount: '12.12345677'),
      _update(time: _nonce - 1),
      _update(time: _nonce + 120001),
    ]) {
      expect(match([other]), isNull);
    }
    expect(match([_update(), _update(hash: _otherHash)]), isNull);
    expect(match([_update(), _update()]), _hash);
  });

  test('uncertain native funding blocks a repeated withdrawal', () {
    final now = DateTime.fromMillisecondsSinceEpoch(_nonce);
    final operation = SettlementOperation(
      operationId: 'native',
      walletId: 'wallet',
      accountKind: SettlementAccountKind.hlHot,
      flow: SettlementFlow.investingToSparkDirect,
      route: kHypercoreToSparkRoute,
      amountInBaseUnits: '1212345678',
      stage: SettlementStage.fundingUnknown,
      funding: const SettlementFunding(
          kind: SettlementFundingKind.hyperliquid, hlNonce: _nonce),
      createdAt: now,
      updatedAt: now,
      quote: SettlementQuoteTerms(
          quoteId: 'quote',
          depositAddress: _target,
          amountIn: '1212345678',
          estimatedOut: '15000',
          feeBps: 10,
          expiresAt: now.add(const Duration(minutes: 2))),
    );
    expect(operation.toReconcileState().hasFundingProof, isFalse);
    expect(
        operation
            .copyWith(funding: operation.funding!.copyWith(evmTxHash: _hash))
            .toReconcileState()
            .hasFundingProof,
        isTrue);
  });

  test('proof lookup tolerates clock skew but verifies the exact signed nonce',
      () async {
    var wrongNonce = false;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path == '/info') {
        expect(body['startTime'], _nonce - 120000);
        return http.Response(jsonEncode([_update(time: _nonce - 10000)]), 200);
      }
      expect(request.url.host, 'rpc.hyperliquid.xyz');
      expect(body['hash'], _hash);
      return http.Response(
          jsonEncode({
            'type': 'txDetails',
            'tx': {
              'hash': _hash,
              'user': _source,
              'error': null,
              'action': {
                'type': 'spotSend',
                'time': wrongNonce ? _nonce - 1 : _nonce,
                'token': hypercoreUsdcToken,
                'destination': _target,
                'amount': '12.12345678'
              }
            }
          }),
          200);
    });
    Future<String?> read() => readHypercoreSpotTransferHash(
        source: _source,
        destination: _target,
        amountBaseUnits: BigInt.from(1212345678),
        nonce: _nonce,
        client: client);
    expect(await read(), _hash);
    wrongNonce = true;
    expect(await read(), isNull);
    client.close();
  });

  test('an unreachable or undocumented explorer leaves the ledger proof standing',
      () async {
    // txDetails is undocumented: it may veto a candidate when it answers in
    // the known shape, but an outage or an unknown shape is not a rejection.
    (int, Object) answer = (500, {'error': 'unavailable'});
    final client = MockClient((request) async {
      if (request.url.path == '/info') {
        return http.Response(jsonEncode([_update(time: _nonce + 5)]), 200);
      }
      return http.Response(jsonEncode(answer.$2), answer.$1);
    });
    addTearDown(client.close);
    Future<String?> read() => readHypercoreSpotTransferHash(
        source: _source,
        destination: _target,
        amountBaseUnits: BigInt.from(1212345678),
        nonce: _nonce,
        client: client);
    expect(await read(), _hash, reason: 'explorer down');
    answer = (200, {'type': 'something-else'});
    expect(await read(), _hash, reason: 'unknown shape');
    answer = (
      200,
      {
        'type': 'txDetails',
        'tx': {'hash': _hash, 'user': _source, 'error': 'reverted'}
      }
    );
    expect(await read(), isNull, reason: 'a known-shape contradiction vetoes');
    expect(
        await explorerVerdict(() async => throw StateError('down'), (_) => true),
        isNull);
  });

  test('spotSend persists its nonce before posting and never retries rejection',
      () async {
    final key = EthPrivateKey.fromHex(
        '0123456789012345678901234567890101234567890123456789012345678901');
    var persisted = false;
    var posts = 0;
    final client = MockClient((request) async {
      posts++;
      expect(persisted, isTrue);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final action = body['action'] as Map<String, dynamic>;
      expect(action['type'], 'spotSend');
      expect(action['destination'], _target);
      expect(action['token'], hypercoreUsdcToken);
      expect(action['amount'], '12.12345678');
      expect(action['time'], body['nonce']);
      expect(action['hyperliquidChain'], 'Mainnet');
      expect(body['signature'], containsPair('v', anyOf(27, 28)));
      // Recover over the protocol's independently specified field list. This
      // catches a wrong primary type/domain/field order, even if JSON is right.
      final digest = userSignedActionDigest(
        primaryType: 'HyperliquidTransaction:SpotSend',
        fields: const [
          (name: 'hyperliquidChain', type: 'string'),
          (name: 'destination', type: 'string'),
          (name: 'token', type: 'string'),
          (name: 'amount', type: 'string'),
          (name: 'time', type: 'uint64'),
        ],
        message: action,
      );
      final signature = body['signature'] as Map<String, dynamic>;
      final pubkey = ecRecover(
          digest,
          MsgSignature(
              BigInt.parse((signature['r'] as String).substring(2), radix: 16),
              BigInt.parse((signature['s'] as String).substring(2), radix: 16),
              signature['v'] as int));
      final recovered =
          '0x${publicKeyToAddress(pubkey).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      expect(recovered, key.address.hexEip55.toLowerCase());
      return http.Response(
          jsonEncode({'status': 'err', 'response': 'Invalid nonce'}), 200);
    });
    final exchange = HyperliquidExchangeService(
        credentials: key,
        walletAddress: key.address.hexEip55,
        httpClient: client,
        onBeforePost: (post) async {
          persisted = true;
        });
    await expectLater(
        exchange.spotSend(
            destination: _target,
            token: hypercoreUsdcToken,
            amount: '12.12345678'),
        throwsA(isA<HyperliquidRejectedException>()));
    expect(posts, 1);
    client.close();
  });
  test('usdSend persists its nonce before posting and never retries rejection',
      () async {
    final key = EthPrivateKey.fromHex(
        '0123456789012345678901234567890101234567890123456789012345678901');
    var persisted = false;
    var posts = 0;
    final client = MockClient((request) async {
      posts++;
      expect(persisted, isTrue);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final action = body['action'] as Map<String, dynamic>;
      expect(action['type'], 'usdSend');
      expect(action['destination'], _target);
      expect(action.containsKey('token'), isFalse);
      expect(body.containsKey('expiresAfter'), isFalse);
      expect(action['amount'], '12.123456');
      expect(action['time'], body['nonce']);
      expect(action['hyperliquidChain'], 'Mainnet');
      expect(body['signature'], containsPair('v', anyOf(27, 28)));
      // Recover over the protocol's independently specified field list. This
      // catches a wrong primary type/domain/field order, even if JSON is right.
      final digest = userSignedActionDigest(
        primaryType: 'HyperliquidTransaction:UsdSend',
        fields: const [
          (name: 'hyperliquidChain', type: 'string'),
          (name: 'destination', type: 'string'),
          (name: 'amount', type: 'string'),
          (name: 'time', type: 'uint64'),
        ],
        message: action,
      );
      final signature = body['signature'] as Map<String, dynamic>;
      final pubkey = ecRecover(
          digest,
          MsgSignature(
              BigInt.parse((signature['r'] as String).substring(2), radix: 16),
              BigInt.parse((signature['s'] as String).substring(2), radix: 16),
              signature['v'] as int));
      final recovered =
          '0x${publicKeyToAddress(pubkey).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      expect(recovered, key.address.hexEip55.toLowerCase());
      return http.Response(
          jsonEncode({'status': 'err', 'response': 'Invalid nonce'}), 200);
    });
    final exchange = HyperliquidExchangeService(
        credentials: key,
        walletAddress: key.address.hexEip55,
        httpClient: client,
        onBeforePost: (post) async {
          persisted = true;
        });
    await expectLater(
        exchange.usdSend(destination: _target, amount: '12.123456'),
        throwsA(isA<HyperliquidRejectedException>()));
    expect(posts, 1);
    client.close();
  });
  for (final internal in [false, true]) {
    test(
        'final dispatch guard blocks ${internal ? 'internal' : 'external'} POST after async hooks',
        () async {
      final key =
          EthPrivateKey.fromHex(BigInt.one.toRadixString(16).padLeft(64, '0'));
      var ready = true;
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return http.Response('{"status":"ok","response":{}}', 200);
      });
      addTearDown(client.close);
      final exchange = HyperliquidExchangeService(
        credentials: key,
        walletAddress: key.address.hexEip55,
        httpClient: client,
        allowNonceRetry: false,
        onBeforePost: (_) async {
          await Future<void>.value();
          ready = false;
        },
      );
      void guard() {
        if (!ready) throw StateError('quote expired or wallet changed');
      }

      await expectLater(
        internal
            ? exchange.usdClassTransfer(
                amount: 1, toPerp: false, beforeSend: guard)
            : exchange.spotSend(
                destination: _target,
                token: hypercoreUsdcToken,
                amount: '2.90000000',
                beforeSend: guard),
        throwsStateError,
      );
      expect(posts, 0);
    });
  }
}
