import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';

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
}
