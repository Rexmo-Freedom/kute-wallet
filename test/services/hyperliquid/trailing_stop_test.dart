import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/services/hyperliquid/trailing_stop_guard.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const market = HlMarket(
    coin: 'BTC',
    wireCoin: 'BTC',
    assetId: 0,
    kind: HlMarketKind.perp,
    szDecimals: 5,
    maxLeverage: 40,
    onlyIsolated: false,
    markPx: 65000,
    midPx: 65000,
    prevDayPx: 64000,
    dayNtlVlm: 1000000);
const trail = HlTrailingStop(retracement: 1.5);
final key = EthPrivateKey.fromHex('0x${'11' * 32}');

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-trailing-test');
    Hive.init(directory.path);
  });
  tearDown(() async {
    await Hive.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  HyperliquidExchangeService service(
          Future<http.Response> Function(http.Request) respond) =>
      HyperliquidExchangeService(
          credentials: key,
          walletAddress: key.address.hex,
          httpClient: MockClient(respond));
  Future<HlOrderResult> place(HyperliquidExchangeService exchange) =>
      exchange.placeTrailingStopOrder(
          market: market,
          isBuy: false,
          size: .001,
          trail: trail,
          referencePrice: 65000,
          reduceOnly: true);

  test(
      'native payload binds percent distance, side, size and explicit activation null',
      () {
    final action = trail.action(
        market: market, isBuy: false, size: '.001', reduceOnly: true);
    expect(action.keys, [
      'type',
      'asset',
      'isBuy',
      'sz',
      'reduceOnly',
      'retracement',
      'activationPx'
    ]);
    expect(action['retracement'], {'pct': '1.5000%'});
    expect(action['activationPx'], isNull);
    expect(action.containsKey('builder'), isFalse);
    expect(action.containsKey('cloid'), isFalse);
    final fixed = const HlTrailingStop(
            retracement: 250, percent: false, activationPrice: 70000)
        .action(market: market, isBuy: false, size: '.001', reduceOnly: true);
    expect(fixed['retracement'], {'px': '250'});
    expect(fixed['activationPx'], '70000');
  });
  test('activation direction and non-finite distances fail before submission',
      () {
    for (final value in [0.0, -1.0, double.nan, double.infinity, 100.0]) {
      expect(
          () => HlTrailingStop(retracement: value)
              .validate(market: market, isBuy: false, referencePrice: 65000),
          throwsArgumentError);
    }
    expect(
        () => const HlTrailingStop(retracement: 1, activationPrice: 64000)
            .validate(market: market, isBuy: false, referencePrice: 65000),
        throwsArgumentError);
    expect(
        () => const HlTrailingStop(retracement: 1, activationPrice: 66000)
            .validate(market: market, isBuy: true, referencePrice: 65000),
        throwsArgumentError);
  });
  test('acknowledged native submission is resting, never a fill', () async {
    var calls = 0;
    final result = await place(service((request) async {
      calls++;
      final body = jsonDecode(request.body);
      expect(body['action']['type'], 'trailingStop');
      expect(body['action']['sz'], '0.001');
      expect(body['signature'], isA<Map>());
      return http.Response(
          '{"status":"ok","response":{"type":"default"}}', 200);
    }));
    expect(calls, 1);
    expect(result.kind, HlOrderResultKind.resting);
    expect(result.filledSz, 0);
  });
  test('lost response stays blocked across service and storage restart',
      () async {
    var calls = 0;
    final exchange = service((_) async {
      calls++;
      throw TimeoutException('lost response');
    });
    await expectLater(
        place(exchange), throwsA(isA<PendingTrailingStopException>()));
    await Hive.close();
    Hive.init(directory.path);
    await expectLater(place(service((_) async {
      calls++;
      return http.Response('{}', 200);
    })), throwsA(isA<PendingTrailingStopException>()));
    expect(calls, 1);
  });
  test('unexpected or nested-error acknowledgements block a second send',
      () async {
    var calls = 0;
    final exchange = service((_) async {
      calls++;
      return http.Response(
          '{"status":"ok","response":{"type":"trailingStop",'
          '"data":{"status":{"error":"unrecognized status"}}}}',
          200);
    });
    await expectLater(
        place(exchange), throwsA(isA<PendingTrailingStopException>()));
    await expectLater(
        place(exchange), throwsA(isA<PendingTrailingStopException>()));
    expect(calls, 1);
  });
  test(
      'final wallet check stops transport and leaves a safe fresh review possible',
      () async {
    var calls = 0;
    final exchange = service((_) async {
      calls++;
      return http.Response(
          '{"status":"ok","response":{"type":"default"}}', 200);
    });
    await expectLater(
        exchange.placeTrailingStopOrder(
            market: market,
            isBuy: false,
            size: .001,
            trail: trail,
            referencePrice: 65000,
            reduceOnly: true,
            beforeSend: () => throw StateError('wallet changed')),
        throwsStateError);
    expect(calls, 0);
    await place(exchange);
    expect(calls, 1);
  });

  test('nonce rejection is never automatically retried', () async {
    var calls = 0;
    await expectLater(place(service((_) async {
      calls++;
      return http.Response(
          '{"status":"err","response":"Invalid nonce: nonce too low"}', 200);
    })), throwsA(isA<HyperliquidRejectedException>()));
    expect(calls, 1);
  });
  test('Ledger checks the paired account after approval and before HTTP',
      () async {
    // The executor only accepts a 0x-prefixed paired address; `hex` from
    // this key type has no prefix.
    var posts = 0;
    var prompts = 0;
    final executor = LedgerHyperliquidExecutor(
        walletId: 'ledger',
        pairedAddress: key.address.hexWith0x,
        signer: EvmExternalSigner(
            address: key.address.hexWith0x,
            sign: (request) async {
              prompts++;
              return key.signToSignature(request.digest);
            }),
        store: LedgerSubmittedActionStore(),
        geoAllowed: () => true,
        gate: (_) => true,
        httpClient: MockClient((_) async {
          posts++;
          return http.Response(
              '{"status":"ok","response":{"type":"default"}}', 200);
        }));
    final intent = LedgerHyperliquidIntents.trailingStop(
        walletId: 'ledger',
        account: key.address.hexWith0x,
        market: market,
        isBuy: false,
        size: .001,
        trail: trail,
        reduceOnly: true,
        summary: const {});
    await expectLater(
        executor.placeTrailingStop(intent,
            market: market,
            trail: trail,
            size: .001,
            referencePrice: 65000,
            beforeSend: () => throw StateError('paired account changed')),
        throwsA(isA<LedgerSubmissionUnknownException>()));
    expect(prompts, 1);
    expect(posts, 0);
  });

  test(
      'Ledger review hash changes with trail and remains an opaque, gated L1 action',
      () {
    intent(HlTrailingStop value) => LedgerHyperliquidIntents.trailingStop(
        walletId: 'ledger',
        account: key.address.hex,
        market: market,
        isBuy: false,
        size: .001,
        trail: value,
        reduceOnly: true,
        summary: const {});
    final original = intent(trail);
    expect(original.paramsHash,
        isNot(intent(const HlTrailingStop(retracement: 2)).paramsHash));
    expect(
        original.paramsHash,
        isNot(intent(
                const HlTrailingStop(retracement: 1.5, activationPrice: 70000))
            .paramsHash));
    expect(LedgerHyperliquidExecutor.isReducingOrder(original), isTrue);
    final action = trail.action(
        market: market, isBuy: false, size: '.001', reduceOnly: true);
    expect(hyperliquidL1ActionKind(action), LedgerActionKind.hlTrailingStop);
    expect(classifyLedgerAction(LedgerActionKind.hlTrailingStop).gate,
        LedgerReleaseGate.flagO1);
  });
}
