// The Investing-withdrawal standing instruction the CCTP fallback pays:
// registered through Kute's backend with `kuteRoute: investing_withdrawal`,
// used only once its stored terms say `venue_withdrawal`, and never shown
// as the Dollars Receive address.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _eoa = '0x7578d21940ee6ac4f882b6d5173d26bce62f5136';
const _arbitrum = '0x1111111111111111111111111111111111111111';
const _base = '0x2222222222222222222222222222222222222222';

void main() {
  late Directory directory;
  late List<String> calls;
  late List<Map<String, dynamic>?> bodies;
  late Map<String, Map<String, dynamic>> provider;
  late String purpose;
  late Map<String, String> purposes;
  late List<String?> keys;
  late bool linked;
  late Future<bool> Function(String) originalLinked;
  late int? refuseWith;
  late Future<Map<String, dynamic>> Function(
      {required String operation,
      String? label,
      required bool Function() current,
      Map<String, dynamic>? body,
      String? idempotencyKey,
      int offset}) original;

  Future<void> usePolicy(int revision) async {
    final policy = runtimePolicyFixture(revision: revision);
    addTearDown(policy.dispose);
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
  }

  Future<StandingDepositRecord> instruction() =>
      StandingDepositStore.investingWithdrawalInstruction(
          walletId: 'a', recipient: _spark, refundAddress: _eoa,
          wanted: () => true);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('investing-withdrawal-');
    Hive.init(directory.path);
    AffiliateService.debugSessionToken = 'test-session';
    calls = [];
    bodies = [];
    provider = {};
    purpose = 'venue_withdrawal';
    purposes = {'polygon:USDC.e': 'investments_internal'};
    keys = [];
    linked = true;
    originalLinked = StandingDepositStore.polymarketLinked;
    StandingDepositStore.polymarketLinked = (_) async => linked;
    refuseWith = null;
    original = StandingDepositStore.standingRequest;
    StandingDepositStore.standingRequest = (
        {required operation,
        label,
        required current,
        body,
        idempotencyKey,
        offset = 0}) async {
      calls.add('$operation:${label?.substring(0, 1) ?? ''}');
      switch (operation) {
        case 'destinations':
          return {
            'destinations': [
              {'chain': 'spark', 'asset': 'USDB'}
            ]
          };
        case 'mine':
          return {'references': <Map<String, dynamic>>[]};
        case 'register':
          bodies.add(body);
          keys.add(idempotencyKey);
          if (refuseWith != null) {
            throw StandingRequestException(refuseWith!, 'bad request');
          }
          final revision =
              RuntimeCapabilitiesService.instance.snapshot!.revision;
          final investing = body?['kuteRoute'] == 'investing_withdrawal';
          final to = body?['destination'] as Map?;
          final key = '${to?['chain']}:${to?['asset']}';
          return provider[label!] ??= {
            'standingAddressId': 'sda_$label',
            'enabled': true,
            'addresses': {'arbitrum': _arbitrum, 'base': _base},
            'kuteFeePolicy': {
              'revision': revision,
              'purpose': investing
                  ? (purposes[key] ?? purpose)
                  : 'usdb_swap_deposit',
              'appFeeBps': investing ? 50 : 0,
            },
          };
        case 'read':
          final state = provider[label];
          if (state == null) throw const StandingRequestException(404, null);
          // A read carries no instruction and no fee terms.
          return {
            'standingAddressId': state['standingAddressId'],
            'enabled': state['enabled'],
            'addresses': state['addresses'],
          };
      }
      throw StateError('unexpected $operation');
    };
  });

  tearDown(() async {
    StandingDepositStore.standingRequest = original;
    StandingDepositStore.polymarketLinked = originalLinked;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('registers with the venue-withdrawal route and reuses verified terms',
      () async {
    await usePolicy(5);
    final record = await instruction();
    expect(StandingDepositStore.isInvestingWithdrawalLabel(record.label),
        isTrue);
    expect(StandingDepositStore.investingWithdrawalAddress(record, _spark),
        _arbitrum);
    final body = bodies.single!;
    expect(body['kuteRoute'], 'investing_withdrawal');
    expect(body['destination'],
        {'chain': 'spark', 'asset': 'USDB', 'address': _spark});
    expect(body['refundAddresses'], {'arbitrum': _eoa});
    expect(body.containsKey('feeBps'), isFalse,
        reason: 'the client never states the fee');
    expect(body.containsKey('affiliateIds'), isFalse);

    // Reused: a read, no second registration, terms kept from the
    // registration (the read has none).
    final again = await instruction();
    expect(again.label, record.label);
    expect(calls.where((c) => c.startsWith('register')), hasLength(1));
    expect(StandingDepositStore.investingWithdrawalAddress(again, _spark),
        _arbitrum);
  });

  test('a backend that does not pin the venue-withdrawal fee is refused',
      () async {
    await usePolicy(5);
    // Today's backend: `kuteRoute` is an unsupported field (400).
    refuseWith = 400;
    await expectLater(
        instruction(), throwsA(isA<InvestingWithdrawalTermsUnavailable>()));
    // A backend that pinned some other rule.
    refuseWith = null;
    purpose = 'usdb_swap_deposit';
    await expectLater(
        instruction(), throwsA(isA<InvestingWithdrawalTermsUnavailable>()));
  });

  group('one instruction per destination', () {
    const pm = '0x9999999999999999999999999999999999999999';

    Future<StandingDepositRecord> to(InvestingWithdrawalDestination d) =>
        StandingDepositStore.investingWithdrawalInstruction(
            walletId: 'a',
            recipient: d == InvestingWithdrawalDestination.predictions
                ? pm
                : _spark,
            refundAddress: _eoa,
            wanted: () => true,
            destination: d);

    test('each destination registers its own label with its own body',
        () async {
      await usePolicy(5);
      final dollars = await to(InvestingWithdrawalDestination.dollars);
      final bitcoin = await to(InvestingWithdrawalDestination.bitcoin);
      final predictions = await to(InvestingWithdrawalDestination.predictions);
      expect({dollars.label, bitcoin.label, predictions.label}, hasLength(3),
          reason: 'a label never serves a second destination (409)');
      expect(
          [
            for (final r in [dollars, bitcoin, predictions])
              StandingDepositStore.isInvestingWithdrawalLabel(r.label)
          ],
          everyElement(isTrue));
      expect(bodies.map((b) => b!['destination']), [
        {'chain': 'spark', 'asset': 'USDB', 'address': _spark},
        {'chain': 'spark', 'asset': 'BTC', 'address': _spark},
        {'chain': 'polygon', 'asset': 'USDC.e', 'address': pm},
      ]);
      expect(bodies.map((b) => b!['kuteRoute']),
          everyElement('investing_withdrawal'));
      expect(bodies.map((b) => b!['refundAddresses']),
          everyElement({'arbitrum': _eoa}));
      expect(bitcoin.asset, 'BTC');
      expect(predictions.chain, 'polygon');
      expect(
          StandingDepositStore.investingWithdrawalAddress(bitcoin, _spark,
              destination: InvestingWithdrawalDestination.bitcoin),
          _arbitrum);
      expect(
          StandingDepositStore.investingWithdrawalAddress(predictions, pm,
              destination: InvestingWithdrawalDestination.predictions),
          _arbitrum);
      // Never one destination's instruction for another.
      expect(
          StandingDepositStore.investingWithdrawalAddress(bitcoin, _spark),
          isNull);
      // Reused per destination: no second registration.
      await to(InvestingWithdrawalDestination.bitcoin);
      expect(calls.where((c) => c.startsWith('register')), hasLength(3));
    });

    test('the purpose sets per destination', () {
      expect(InvestingWithdrawalDestination.dollars.feePurposes,
          {'venue_withdrawal', 'investments_internal'});
      expect(InvestingWithdrawalDestination.bitcoin.feePurposes,
          {'venue_withdrawal', 'investments_internal'});
      expect(InvestingWithdrawalDestination.predictions.feePurposes,
          {'investments_internal', 'venue_withdrawal'});
    });

    test('the returned purpose is checked per destination', () async {
      await usePolicy(5);
      // Bitcoin pinned to its plain deposit rule: refused.
      purpose = 'cross_chain_deposit';
      await expectLater(to(InvestingWithdrawalDestination.bitcoin),
          throwsA(isA<InvestingWithdrawalTermsUnavailable>()));
      // Predictions pinned to the Predictions deposit rule: refused.
      purposes['polygon:USDC.e'] = 'predictions_deposit';
      await expectLater(to(InvestingWithdrawalDestination.predictions),
          throwsA(isA<InvestingWithdrawalTermsUnavailable>()));
    });

    test('either accepted rule is used, on Spark and on Polygon', () async {
      await usePolicy(5);
      purpose = 'investments_internal';
      expect(
          StandingDepositStore.investingWithdrawalAddress(
              await to(InvestingWithdrawalDestination.bitcoin), _spark,
              destination: InvestingWithdrawalDestination.bitcoin),
          _arbitrum);
      purposes['polygon:USDC.e'] = 'venue_withdrawal';
      expect(
          StandingDepositStore.investingWithdrawalAddress(
              await to(InvestingWithdrawalDestination.predictions), pm,
              destination: InvestingWithdrawalDestination.predictions),
          _arbitrum);
    });

    test('Predictions registers only once the Polymarket wallet is linked',
        () async {
      await usePolicy(5);
      linked = false;
      await expectLater(to(InvestingWithdrawalDestination.predictions),
          throwsA(isA<InvestingWithdrawalTermsUnavailable>()));
      expect(calls.where((c) => c.startsWith('register')), isEmpty,
          reason: 'nothing registered before the link: via Dollars');
      linked = true;
      await to(InvestingWithdrawalDestination.predictions);
      // Never the same key as an unlinked registration (409).
      expect(keys.single, endsWith('-linked'));
    });

    test('past Dollars any refusal means: go through Dollars', () async {
      await usePolicy(5);
      for (final status in [400, 403, 409, 422, 500, 502]) {
        refuseWith = status;
        await expectLater(to(InvestingWithdrawalDestination.bitcoin),
            throwsA(isA<InvestingWithdrawalTermsUnavailable>()),
            reason: '$status');
      }
      // Dollars keep their own rule: a provider outage is not a refusal.
      refuseWith = 502;
      await expectLater(to(InvestingWithdrawalDestination.dollars),
          throwsA(isA<StandingRequestException>()));
    });
  });

  test('Dollars Receive never shows the Investing-withdrawal address',
      () async {
    await usePolicy(5);
    await instruction();
    final receive = await StandingDepositStore.register(
        walletId: 'a',
        recipient: _spark,
        destinationAsset: 'USDB',
        sourceChain: 'base',
        sourceAsset: 'USDC',
        wanted: () => true);
    expect(StandingDepositStore.isInvestingWithdrawalLabel(receive!.label),
        isFalse);
    expect(receive.label, StandingDepositStore.labelFor(_spark, 'USDB', 5));
    expect(calls.where((c) => c == 'register:s'), hasLength(1),
        reason: 'its own registration, at the dollar-deposit terms');
  });

  test('rows on the instruction read as Investing withdrawals', () {
    final record = StandingDepositRecord(
        walletId: 'a',
        label: StandingDepositStore.investingWithdrawalLabelFor(_spark, 5),
        recipient: _spark,
        asset: 'USDB',
        revision: 5,
        response: const {
          'addresses': {'arbitrum': _arbitrum}
        });
    final order = standingOrderRow(
        record: record,
        orderId: 'ord_1',
        chain: 'arbitrum',
        asset: 'USDC',
        depositAddress: _arbitrum,
        amountIn: '4800000',
        amountOut: '4790000',
        status: 'exchanging',
        timestamp: 1,
        recipient: _spark,
        walletId: 'a');
    expect(order.networkFrom, 'HYPERCORE');
    expect(order.coinFrom, 'USDC');
    expect(order.purchaseSource, isNull);
    expect(order.depositAmount, '4.8');
    final held = stuckStandingDepositRow(
        deposit: {
          'id': 'dep',
          'chain': 'arbitrum',
          'asset': 'USDC',
          'amount': '4800000',
          'status': 'held',
        },
        record: record,
        walletId: 'a',
        recipient: _spark)!;
    expect(held.networkFrom, 'HYPERCORE');
    expect(held.status, 'held');
    // A receive instruction keeps the receive shape.
    final receive = standingOrderRow(
        record: StandingDepositRecord(
            walletId: 'a',
            label: StandingDepositStore.labelFor(_spark, 'USDB', 5),
            recipient: _spark,
            asset: 'USDB',
            revision: 5),
        orderId: 'ord_2',
        chain: 'base',
        asset: 'USDC',
        depositAddress: _base,
        amountIn: '4800000',
        amountOut: '4790000',
        status: 'exchanging',
        timestamp: 1,
        recipient: _spark,
        walletId: 'a');
    expect(receive.networkFrom, 'base');
    expect(receive.purchaseSource, 'crypto_receive');
  });
}
