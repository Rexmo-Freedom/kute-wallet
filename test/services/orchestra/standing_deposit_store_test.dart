import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/api/orchestra_api.dart'
    show StandingRequestException;
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('standing-deposit-');
    Hive.init(directory.path);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  const record = StandingDepositRecord(
      walletId: 'a',
      label: 'ref',
      recipient: 'spark',
      asset: 'USDB',
      revision: 1);
  test('fee revision and recipient get separate immutable references', () {
    expect(StandingDepositStore.labelFor('one', 'USDB', 1),
        isNot(StandingDepositStore.labelFor('one', 'USDB', 2)));
    expect(StandingDepositStore.labelFor('one', 'USDB', 1),
        isNot(StandingDepositStore.labelFor('two', 'USDB', 1)));
  });
  test('retained references and pending refunds survive restart', () async {
    await StandingDepositStore.save(
        record.copy(refunds: {
          'dep': {'state': 'requested', 'key': 'key'}
        }),
        StandingDepositStore.capture('a'));
    await Hive.close();
    final recovered = await StandingDepositStore.records('a');
    expect(recovered.single.refunds['dep']['state'], 'requested');
    expect(await StandingDepositStore.records('b'), isEmpty);
  });
  test('restores backend-listed references without replacing local records',
      () async {
    const spark = 'spark1qexamplerecipient';
    final ownLabel = StandingDepositStore.labelFor(spark, 'USDB', 3);
    final calls = <String>[];
    final original = StandingDepositStore.standingRequest;
    StandingDepositStore.standingRequest = (
        {required operation,
        label,
        required current,
        body,
        idempotencyKey,
        offset = 0}) async {
      calls.add('$operation:${label ?? ''}');
      if (operation == 'mine') {
        return {
          'references': [
            // Reproduces from this wallet's recipient: admitted.
            {
              'label': ownLabel,
              'destinationChain': 'spark',
              'destinationAsset': 'USDB',
              'policyRevision': 3,
              'standingAddressId': 'sda_3',
              'enabled': true,
            },
            // Already held locally, with a refund journal: untouched.
            {
              'label': 'ref',
              'destinationChain': 'spark',
              'destinationAsset': 'USDB',
              'policyRevision': 1,
              'standingAddressId': 'sda_1',
              'enabled': true,
            },
            // Unknown recipient and the provider names none: skipped.
            {
              'label': 'sorphan',
              'destinationChain': 'spark',
              'destinationAsset': 'USDB',
              'policyRevision': 2,
              'standingAddressId': 'sda_2',
              'enabled': true,
            },
          ]
        };
      }
      expect(operation, 'read');
      return {
        'standingAddressId': 'sda_$label',
        'enabled': false,
        'addresses': {'base': '0xbase'},
      };
    };
    addTearDown(() => StandingDepositStore.standingRequest = original);
    final scope = StandingDepositStore.capture('a');
    await StandingDepositStore.save(
        record.copy(refunds: {
          'dep': {'state': 'requested', 'key': 'key'}
        }),
        scope);
    final restored = await StandingDepositStore.restore(
        walletId: 'a', recipient: spark, wanted: () => true);
    expect(restored, 1);
    final stored = await StandingDepositStore.records('a');
    expect(stored.map((r) => r.label), unorderedEquals(['ref', ownLabel]));
    final recovered = stored.singleWhere((r) => r.label == ownLabel);
    expect(recovered.recipient, spark);
    expect(recovered.revision, 3);
    expect(recovered.enabled, isFalse);
    expect(recovered.addressFor('base'), '0xbase');
    expect(stored.singleWhere((r) => r.label == 'ref').refunds['dep']['state'],
        'requested');
    // Only the stored instruction is read; nothing is re-registered.
    expect(calls.where((c) => c.startsWith('register')), isEmpty);
    expect(calls, isNot(contains('read:ref')));
  });

  test('wallet deletion fences a late registration response', () async {
    final scope = StandingDepositStore.capture('a');
    await StandingDepositStore.deleteWallet('a');
    await expectLater(
        StandingDepositStore.save(record, scope), throwsStateError);
    expect(await StandingDepositStore.records('a'), isEmpty);
  });
  test('refresh and registration preserve concurrent refund journals',
      () async {
    final scope = StandingDepositStore.capture('a');
    await StandingDepositStore.ensureRecord(record, scope);
    await Future.wait([
      for (final id in ['first', 'second'])
        StandingDepositStore.recordRefund(
            record: record,
            scope: scope,
            depositId: id,
            requestKey: id,
            address: 'return'),
      StandingDepositStore.saveResponse(record, {'enabled': false}, scope),
      StandingDepositStore.ensureRecord(record, scope),
    ]);
    final stored = (await StandingDepositStore.records('a')).single;
    expect(stored.refunds.keys, containsAll(['first', 'second']));
    expect(stored.response['enabled'], isFalse);
    await expectLater(
        StandingDepositStore.recordRefund(
            record: record,
            scope: scope,
            depositId: 'first',
            requestKey: 'duplicate',
            address: 'other'),
        throwsStateError);
    await StandingDepositStore.recordRefund(
        record: record,
        scope: scope,
        depositId: 'first',
        requestKey: 'wrong-key',
        address: 'other',
        refused: true);
    expect(
        (await StandingDepositStore.records('a')).single.refunds['first']
            ['state'],
        'requested');
    await StandingDepositStore.recordRefund(
        record: record,
        scope: scope,
        depositId: 'first',
        requestKey: 'first',
        address: 'return',
        refused: true);
    await StandingDepositStore.recordRefund(
        record: record,
        scope: scope,
        depositId: 'first',
        requestKey: 'retry',
        address: 'return');
    expect(
        (await StandingDepositStore.records('a')).single.refunds['first']
            ['key'],
        'retry');
  });
  test('Tron standing funding does not inherit generic TRX support', () {
    expect(StandingDepositStore.supportsSource('tron', 'TRX'), isFalse);
    expect(StandingDepositStore.supportsSource('tron', 'USDT'), isTrue);
  });

  group('one address per coin and network', () {
    const spark =
        'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
    const first = '0x1111111111111111111111111111111111111111';
    const second = '0x2222222222222222222222222222222222222222';
    late List<String> calls;
    late Map<String, Map<String, dynamic>> provider;
    late List<Map<String, dynamic>> mine;
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

    Future<String?> openReceive() async => (await StandingDepositStore.register(
            walletId: 'a',
            recipient: spark,
            destinationAsset: 'USDB',
            sourceChain: 'base',
            sourceAsset: 'USDC',
            wanted: () => true))
        ?.addressFor('base');

    setUp(() {
      AffiliateService.debugSessionToken = 'test-session';
      calls = [];
      provider = {};
      mine = [];
      original = StandingDepositStore.standingRequest;
      var minted = 0;
      StandingDepositStore.standingRequest = (
          {required operation,
          label,
          required current,
          body,
          idempotencyKey,
          offset = 0}) async {
        calls.add(operation);
        switch (operation) {
          case 'destinations':
            return {
              'destinations': [
                {'chain': 'spark', 'asset': 'USDB'}
              ]
            };
          case 'mine':
            return {'references': mine};
          case 'register':
            final revision = RuntimeCapabilitiesService
                .instance.snapshot!.revision;
            return provider[label!] ??= {
              'standingAddressId': 'sda_$label',
              'enabled': true,
              'addresses': {'base': minted++ == 0 ? first : second},
              'kuteFeePolicy': {'revision': revision},
            };
          case 'read':
            final state = provider[label];
            if (state == null) throw const StandingRequestException(404, null);
            return state;
        }
        throw StateError('unexpected $operation');
      };
    });
    tearDown(() {
      StandingDepositStore.standingRequest = original;
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    test('opening Receive twice returns the same address', () async {
      await usePolicy(5);
      expect(await openReceive(), first);
      expect(await openReceive(), first);
      expect(calls.where((c) => c == 'register'), hasLength(1));
      expect((await StandingDepositStore.records('a')), hasLength(1));
    });

    test('a newer policy revision does not replace the address', () async {
      await usePolicy(5);
      expect(await openReceive(), first);
      await usePolicy(6);
      expect(await openReceive(), first);
      expect(calls.where((c) => c == 'register'), hasLength(1));
    });

    test('a paused or forgotten address is replaced', () async {
      await usePolicy(5);
      expect(await openReceive(), first);
      final label = provider.keys.single;
      provider[label] = {...provider[label]!, 'enabled': false};
      await usePolicy(6);
      expect(await openReceive(), second);
      expect(calls.where((c) => c == 'register'), hasLength(2));
      // And the replacement is the one reused from then on.
      expect(await openReceive(), second);
      expect(calls.where((c) => c == 'register'), hasLength(2));
    });

    test('an address another install registered is reused', () async {
      await usePolicy(7);
      final label = StandingDepositStore.labelFor(spark, 'USDB', 3);
      provider[label] = {
        'standingAddressId': 'sda_other',
        'enabled': true,
        'addresses': {'base': second},
      };
      mine = [
        {
          'label': label,
          'destinationChain': 'spark',
          'destinationAsset': 'USDB',
          'policyRevision': 3,
        }
      ];
      expect(await openReceive(), second);
      expect(calls, isNot(contains('register')));
    });

    test('crypto deposits off refuses before any address is shown',
        () async {
      final policy = runtimePolicyFixture(blocked: {'crypto.deposit'});
      addTearDown(policy.dispose);
      RuntimeCapabilitiesService.debugInstance = policy;
      expect(await policy.refresh(), isTrue);
      await expectLater(
          openReceive(), throwsA(isA<CapabilityUnavailableException>()));
      expect(calls, isEmpty);
    });
  });
}
