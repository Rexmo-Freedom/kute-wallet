import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

final _key = EthPrivateKey.fromHex(
    '0x0123456789012345678901234567890101234567890123456789012345678901');
final _address = _key.address.hexEip55;
const _cloid = '0x0123456789abcdef0123456789abcdef';

class _Harness {
  _Harness({
    required FutureOr<http.Response> Function(
            Map<String, dynamic> body, Uri url)
        respond,
    bool geo = true,
    bool trading = true,
    bool withdrawals = true,
    bool Function(LedgerActionKind kind)? gate,
    Future<void> Function(LedgerActionIntent)? checkCapability,
  }) {
    store = LedgerSubmittedActionStore(
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000));
    signer = EvmExternalSigner(
      address: _address,
      sign: (request) async {
        prompts.add(request);
        return _key.signToSignature(request.digest);
      },
    );
    executor = LedgerHyperliquidExecutor(
      walletId: 'ledger-1',
      pairedAddress: _address,
      signer: signer,
      store: store,
      geoAllowed: () => geo,
      checkCapability: checkCapability,
      tradingEnabled: () => trading,
      withdrawalsEnabled: () => withdrawals,
      gate: gate ?? (_) => true,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        return respond(body, request.url);
      }),
    );
  }

  late final LedgerSubmittedActionStore store;
  late final EvmExternalSigner signer;
  late final LedgerHyperliquidExecutor executor;
  final prompts = <EvmSigningRequest>[];
  final requests = <Map<String, dynamic>>[];
}

http.Response _ok([Object? data]) => http.Response(
    jsonEncode({
      'status': 'ok',
      'response': {'type': 'default', 'data': data},
    }),
    200);

LedgerActionIntent _transfer({String walletId = 'ledger-1'}) =>
    LedgerHyperliquidIntents.usdClassTransfer(
      walletId: walletId,
      account: _address,
      amount: '10.5',
      toPerp: true,
      summary: const {'amount': '10.50 USDC', 'direction': 'Spot to perps'},
    );

LedgerActionIntent _order({int assetId = 0, bool isBuy = true}) =>
    LedgerHyperliquidIntents.order(
      walletId: 'ledger-1',
      account: _address,
      assetId: assetId,
      coin: 'BTC',
      isBuy: isBuy,
      px: '65000',
      sz: '0.001',
      tif: 'Gtc',
      reduceOnly: false,
      cloid: _cloid,
      summary: const {'market': 'BTC', 'side': 'Buy'},
    );

LedgerActionIntent _nativeSend() => LedgerHyperliquidIntents.usdSend(
      walletId: 'ledger-1',
      account: _address,
      destination: '0x${'12' * 20}',
      amountBaseUnits: BigInt.from(1234567800),
      quoteId: 'withdraw-quote',
      summary: const {'Amount': '12.345678 USDC'},
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ledger_hl_executor');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('runtime policy rejection happens before any Ledger prompt or POST',
      () async {
    final h = _Harness(
        respond: (_, __) => _ok(),
        checkCapability: (_) async => throw StateError('country_blocked'));
    await expectLater(h.executor.placeOrder(_order()), throwsStateError);
    expect(h.prompts, isEmpty);
    expect(h.requests, isEmpty);
  });

  test('cancellation retains access when new trading is region-blocked',
      () async {
    final checked = <LedgerActionKind>[];
    final h = _Harness(
        // A cancellation only counts with the venue's own cancel
        // acknowledgement (8902431d), not a generic ok.
        respond: (_, __) => http.Response(
            jsonEncode({
              'status': 'ok',
              'response': {
                'type': 'cancel',
                'data': {
                  'statuses': ['success']
                }
              }
            }),
            200),
        geo: false,
        trading: false,
        checkCapability: (intent) async => checked.add(intent.kind));
    final cancel = LedgerHyperliquidIntents.cancel(
        walletId: 'ledger-1',
        account: _address,
        assetId: 0,
        coin: 'BTC',
        oid: 123,
        summary: const {'Action': 'Cancel'});
    await h.executor.cancelOrder(cancel);
    // Runtime policy is checked before the prompt and again after device
    // approval, right before the POST (5adad7b9); both allow a cancel.
    expect(checked, [LedgerActionKind.hlCancel, LedgerActionKind.hlCancel]);
    expect(h.prompts, hasLength(1));
    expect(h.requests, hasLength(1));
  });

  test('spot sells retain exit access but a new spot buy is blocked', () async {
    final h = _Harness(
        geo: false,
        trading: false,
        respond: (_, __) => http.Response(
            jsonEncode({
              'status': 'ok',
              'response': {
                'type': 'order',
                'data': {
                  'statuses': [
                    {
                      'resting': {'oid': 1}
                    }
                  ]
                }
              }
            }),
            200));
    await h.executor.placeOrder(_order(assetId: 10001, isBuy: false));
    expect(h.prompts, hasLength(1));
    await expectLater(h.executor.placeOrder(_order(assetId: 10001)),
        throwsA(isA<LedgerHyperliquidGeoBlockedException>()));
    expect(h.prompts, hasLength(1));
  });

  test('happy path: one prompt, chain 0xa4b1, record written before the POST',
      () async {
    late _Harness h;
    h = _Harness(respond: (body, url) async {
      final record = await h.store.get('ledger-1', 'hl-${body['nonce']}');
      expect(record, isNotNull, reason: 'record must exist before the POST');
      expect(record!.stage, LedgerSubmissionStage.submitting);
      expect(body['action']['signatureChainId'], '0xa4b1');
      expect(body['action']['amount'], '10.5');
      return _ok();
    });
    await h.executor.usdClassTransfer(_transfer());
    expect(h.prompts, hasLength(1));
    expect(h.prompts.single.kind, LedgerActionKind.hlUsdClassTransfer);
    final records = await h.store.forWallet('ledger-1');
    expect(records.single.stage, LedgerSubmissionStage.accepted);
    expect(records.single.paramsHash, _transfer().paramsHash);
  });

  test('a nonce rejection gives one prompt and a typed error', () async {
    final h = _Harness(
        respond: (_, __) => http.Response(
            jsonEncode({'status': 'err', 'response': 'Invalid nonce: too old'}),
            200));
    await expectLater(h.executor.usdClassTransfer(_transfer()),
        throwsA(isA<HyperliquidNonceRejectedException>()));
    expect(h.prompts, hasLength(1));
    expect(h.requests, hasLength(1));
    final records = await h.store.forWallet('ledger-1');
    expect(records.single.stage, LedgerSubmissionStage.rejected);
  });

  test('native withdrawal persists exact nonce before one device-signed POST',
      () async {
    int? persistedNonce;
    late _Harness h;
    h = _Harness(respond: (body, _) async {
      expect(persistedNonce, body['nonce']);
      expect(body['action']['destination'], '0x${'12' * 20}');
      expect(body['action'].containsKey('token'), isFalse);
      expect(body['action']['type'], 'usdSend');
      expect(body['action']['amount'], '12.345678');
      expect(body['action']['signatureChainId'], '0xa4b1');
      expect((await h.store.get('ledger-1', 'hl-$persistedNonce'))!.kind,
          'hlUsdSend');
      return _ok();
    });
    final intent = _nativeSend();
    final nonce = await h.executor
        .usdSend(intent, onBeforeSend: (value) async => persistedNonce = value);
    expect(nonce, persistedNonce);
    expect(h.prompts.single.kind, LedgerActionKind.hlUsdSend);
    expect(h.requests, hasLength(1));
    expect(intent.toSensitiveIntent().requiresStepUp, isTrue);
    expect(intent.toSensitiveIntent().amountMax, BigInt.from(1234567800));
    expect(intent.toSensitiveIntent().limits['quoteId'], 'withdraw-quote');
  });

  test(
      'withdrawal preparation remains enabled when new investments are disabled',
      () async {
    final h =
        _Harness(trading: false, withdrawals: true, respond: (_, __) => _ok());
    final preparation = LedgerHyperliquidIntents.usdClassTransfer(
        walletId: 'ledger-1',
        account: _address,
        amount: '2',
        toPerp: true,
        withdrawalQuoteId: 'withdraw-quote',
        summary: const {});
    await h.executor.usdClassTransfer(preparation);
    expect(h.requests, hasLength(1));
    expect(h.requests.single['action']['toPerp'], isTrue);
  });

  test('failed pre-POST quote check prevents native withdrawal submission',
      () async {
    final h = _Harness(respond: (_, __) => _ok());
    await expectLater(
      h.executor.usdSend(_nativeSend(),
          onBeforeSend: (_) async => throw StateError('quote expired')),
      throwsStateError,
    );
    expect(h.prompts, hasLength(1));
    expect(h.requests, isEmpty);
    expect(await h.store.forWallet('ledger-1'), isEmpty);
  });

  test('native send timeout retains nonce and never prompts or posts twice',
      () async {
    final h = _Harness(respond: (_, __) => throw TimeoutException('offline'));
    int? persistedNonce;
    await expectLater(
        h.executor.usdSend(_nativeSend(),
            onBeforeSend: (nonce) async => persistedNonce = nonce),
        throwsA(isA<LedgerSubmissionUnknownException>()));
    expect(h.prompts, hasLength(1));
    expect(h.requests, hasLength(1));
    final record = await h.store.get('ledger-1', 'hl-$persistedNonce');
    expect(record!.nonce, persistedNonce);
    expect(record.stage, LedgerSubmissionStage.submittedUnknown);
  });

  test('an intent hash mismatch is refused before any prompt', () async {
    final h = _Harness(respond: (_, __) => _ok());
    final good = _transfer();
    final tampered = LedgerActionIntent.restore(
      walletId: good.walletId,
      kind: good.kind,
      params: {...good.params, 'amount': '1000'},
      summary: good.summary,
      paramsHash: good.paramsHash,
      createdAtMs: good.createdAtMs,
      sensitive: good.sensitive,
    );
    await expectLater(h.executor.usdClassTransfer(tampered),
        throwsA(isA<LedgerIntentMismatchException>()));
    await expectLater(h.executor.usdClassTransfer(_transfer(walletId: 'other')),
        throwsA(isA<LedgerIntentMismatchException>()));
    await expectLater(h.executor.cancelOrder(_transfer()),
        throwsA(isA<LedgerIntentMismatchException>()));
    expect(h.prompts, isEmpty);
    expect(h.requests, isEmpty);
  });

  test('a POST timeout gives submittedUnknown and reconcile never re-signs',
      () async {
    var infoCalls = 0;
    final h = _Harness(respond: (body, url) async {
      if (url.path.endsWith('/info')) {
        infoCalls++;
        expect(body['type'], 'orderStatus');
        expect(body['oid'], _cloid);
        expect(body['user'], _address);
        return http.Response(
            jsonEncode({
              'status': 'order',
              'order': {
                'order': {'oid': 42},
                'status': 'open',
              },
            }),
            200);
      }
      throw TimeoutException('exchange stalled');
    });

    Object? error;
    try {
      await h.executor.placeOrder(_order());
    } catch (e) {
      error = e;
    }
    expect(error, isA<LedgerSubmissionUnknownException>());
    final id = (error as LedgerSubmissionUnknownException).recordId;
    final record = await h.store.get('ledger-1', id);
    expect(record!.stage, LedgerSubmissionStage.submittedUnknown);
    expect(record.cloid, _cloid);
    expect(h.prompts, hasLength(1));

    final outcome = await h.executor.reconcile(id);
    expect(outcome, LedgerReconcileOutcome.confirmed);
    expect(infoCalls, 1);
    expect(h.prompts, hasLength(1), reason: 'reconcile never signs');
    expect(h.requests.where((b) => b.containsKey('signature')), hasLength(1));
    final confirmed = await h.store.get('ledger-1', id);
    expect(confirmed!.stage, LedgerSubmissionStage.confirmed);
    expect(confirmed.oid, 42);
  });

  test('native withdrawals respect their own switch when trading is paused',
      () async {
    final h = _Harness(respond: (_, __) => _ok(), trading: false);
    await h.executor.usdSend(_nativeSend(), onBeforeSend: (_) async {});
    await h.executor.usdClassTransfer(LedgerHyperliquidIntents.usdClassTransfer(
      walletId: 'ledger-1',
      account: _address,
      amount: '1',
      toPerp: false,
      summary: const {'Action': 'Prepare withdrawal'},
    ));
    await expectLater(h.executor.placeOrder(_order()),
        throwsA(isA<LedgerHyperliquidDisabledException>()));
    expect(h.prompts, hasLength(2));
    final paused = _Harness(respond: (_, __) => _ok(), withdrawals: false);
    await expectLater(
        paused.executor.usdSend(_nativeSend(), onBeforeSend: (_) async {}),
        throwsA(isA<LedgerHyperliquidDisabledException>()));
    expect(paused.prompts, isEmpty);
  });

  test('the geo gate blocks before any prompt', () async {
    final h = _Harness(respond: (_, __) => _ok(), geo: false);
    await expectLater(h.executor.usdClassTransfer(_transfer()),
        throwsA(isA<LedgerHyperliquidGeoBlockedException>()));
    expect(h.prompts, isEmpty);
  });

  test('opaque actions stay blocked by the default gate (O1 flag off)',
      () async {
    final h = _Harness(
        respond: (_, __) => _ok(),
        gate: (kind) =>
            isLedgerActionAllowed(kind, opaqueHyperliquidEnabled: false));
    await expectLater(h.executor.placeOrder(_order()),
        throwsA(isA<LedgerActionBlockedException>()));
    expect(h.prompts, isEmpty);
    // Readable transfers stay allowed.
    await h.executor.usdClassTransfer(_transfer());
    expect(h.prompts, hasLength(1));
  });

  test('a second action while one is in flight is busy', () async {
    final release = Completer<http.Response>();
    final h = _Harness(respond: (_, __) => release.future);
    final first = h.executor.usdClassTransfer(_transfer());
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        h.executor.usdClassTransfer(_transfer()), throwsA(anything));
    release.complete(_ok());
    await first;
    expect(h.prompts, hasLength(1));
  });

  test('the executor has no withdrawal or key parameter', () {
    final source =
        File('lib/services/hardware/ledger/ledger_hyperliquid_executor.dart')
            .readAsStringSync();
    expect(source.contains('withdraw3('), isFalse);
    expect(source.contains('credentials:'), isFalse);
    expect(source.contains('privateKey'), isFalse);
  });

  test('the hot service keeps its default chain and retry', () {
    final service =
        HyperliquidExchangeService(credentials: _key, walletAddress: _address);
    expect(service.allowNonceRetry, isTrue);
    expect(service.signatureChainId, isNull);
    expect(
      () => HyperliquidExchangeService(
          externalSigner: EvmExternalSigner(
              address: '0x${'11' * 20}',
              sign: (_) => throw UnimplementedError()),
          walletAddress: _address),
      throwsArgumentError,
    );
  });

  test('intents produce a stable Phase 1b digest', () {
    final a = _transfer();
    final b = _transfer();
    expect(a.paramsHash, b.paramsHash);
    expect(a.toSensitiveIntent().digest, b.toSensitiveIntent().digest);
    expect(a.toSensitiveIntent().amountMax, BigInt.from(10500000));
    expect(a.toSensitiveIntent().requiresStepUp, isFalse);
    expect(_order().toSensitiveIntent().requiresStepUp, isTrue);
    // 65000 * 0.001 = 65 USDC.
    expect(_order().toSensitiveIntent().amountMax, BigInt.from(65000000));
  });
}
