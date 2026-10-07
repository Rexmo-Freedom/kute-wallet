import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/ledger/ledger_venue_descriptor_store.dart';

const _hl = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _pm = '0x1111111111111111111111111111111111111111';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ledger_descriptor_test');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('write, read and merge public descriptors', () async {
    var now = 1000;
    final store = LedgerVenueDescriptorStore(
        clock: () => DateTime.fromMillisecondsSinceEpoch(now));

    expect(await store.read('w1'), isNull);
    await store.merge('w1', hlAddress: _hl);
    now = 2000;
    final merged = await store.merge('w1',
        pmAccountKind: LedgerPmAccountKind.depositWallet,
        pmAddress: _pm,
        pmSignatureType: 3);

    expect(merged.hlAddress, _hl);
    expect(merged.pmAddress, _pm);
    final read = await store.read('w1');
    expect(read!.schema, LedgerVenueDescriptor.currentSchema);
    expect(read.hlAddress, _hl);
    expect(read.pmAccountKind, LedgerPmAccountKind.depositWallet);
    expect(read.pmSignatureType, 3);
    expect(read.resolvedAtMs, 2000);
  });

  test('rejects malformed addresses and ignores unknown schemas', () async {
    final store = LedgerVenueDescriptorStore();
    expect(
      () => store.write(
          'w1', const LedgerVenueDescriptor(hlAddress: 'nope', resolvedAtMs: 1)),
      throwsArgumentError,
    );
    final box = await Hive.openBox<String>(LedgerVenueDescriptorStore.boxName);
    await box.put('w2', '{"schema":99,"resolvedAtMs":1}');
    await box.put('w3', '{"schema":1,"resolvedAtMs":1,"pmAddress":"0x12"}');
    await box.put('w4', 'not json');
    expect(await store.read('w2'), isNull);
    expect(await store.read('w3'), isNull);
    expect(await store.read('w4'), isNull);
  });

  test('only public fields are persisted', () async {
    final store = LedgerVenueDescriptorStore();
    await store.merge('w1', hlAddress: _hl, pmAddress: _pm);
    final box = await Hive.openBox<String>(LedgerVenueDescriptorStore.boxName);
    final raw = jsonDecode(box.get('w1')!) as Map<String, dynamic>;
    expect(raw.keys.toSet(), {
      'schema',
      'hlAddress',
      'pmAccountKind',
      'pmAddress',
      'pmSignatureType',
      'resolvedAtMs',
    });
  });

  test('wallet removal clears descriptors and submitted actions', () async {
    final descriptors = LedgerVenueDescriptorStore();
    final actions = LedgerSubmittedActionStore();
    await descriptors.merge('w1', hlAddress: _hl);
    await descriptors.merge('w2', hlAddress: _hl);
    for (final wallet in ['w1', 'w2']) {
      await actions.recordBeforeSubmit(LedgerSubmittedAction(
        id: 'hl-1',
        walletId: wallet,
        kind: 'hlUsdClassTransfer',
        paramsHash: 'h',
        stage: LedgerSubmissionStage.submitting,
        submittedAtMs: 1,
        nonce: 1,
      ));
    }

    await wipeLedgerWalletLocalData('w1',
        descriptors: descriptors, submittedActions: actions);

    expect(await descriptors.read('w1'), isNull);
    expect(await actions.forWallet('w1'), isEmpty);
    expect(await descriptors.read('w2'), isNotNull);
    expect(await actions.forWallet('w2'), hasLength(1));
  });

  test('SettingsModel.removeWallet calls the Ledger cleanup next to the '
      'credential delete', () {
    final source = File('lib/models/settings_model.dart').readAsStringSync();
    final remove = source.substring(source.indexOf('Future<void> removeWallet'),
        source.indexOf('Future<void> _wipePerWalletHiveData'));
    expect(remove.contains("'pm_api_credentials_\$walletId'"), isTrue);
    expect(remove.contains('wipeLedgerWalletLocalData(walletId)'), isTrue);
  });
}
