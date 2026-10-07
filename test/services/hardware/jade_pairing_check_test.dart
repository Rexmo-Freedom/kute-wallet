import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/hardware/jade_pairing_check.dart';

void main() {
  WalletConfig wallet(String? fingerprint) => WalletConfig(
        id: 'jade-wallet',
        name: 'Jade',
        isHardware: true,
        isWatchOnly: true,
        walletType: 'Jade',
        masterFingerprint: fingerprint,
      );

  late List<WalletConfig> saved;
  Future<void> save(WalletConfig updated) async => saved.add(updated);

  setUp(() => saved = []);

  test('a different Jade is rejected and the stored fingerprint is kept',
      () async {
    await expectLater(
        verifyJadePairing(
            wallet: wallet('aabbccdd'),
            actualFingerprint: '11223344',
            save: save),
        throwsA(isA<JadeWrongDeviceException>()));
    expect(saved, isEmpty);
  });

  test('the paired Jade passes regardless of case and saves nothing',
      () async {
    await verifyJadePairing(
        wallet: wallet('AABBCCDD'), actualFingerprint: 'aabbccdd', save: save);
    expect(saved, isEmpty);
  });

  for (final stored in [null, '', '00000000', 'external']) {
    test('first pairing (stored ${stored ?? 'null'}) stores the device value',
        () async {
      await verifyJadePairing(
          wallet: wallet(stored), actualFingerprint: '11223344', save: save);
      expect(saved.single.masterFingerprint, '11223344');
      expect(saved.single.id, 'jade-wallet');
    });
  }

  test('an unreadable device fingerprint changes nothing', () async {
    await verifyJadePairing(
        wallet: wallet('aabbccdd'), actualFingerprint: null, save: save);
    await verifyJadePairing(
        wallet: wallet(null), actualFingerprint: 'nope', save: save);
    expect(saved, isEmpty);
  });

  test('the signing screen stops on a mismatch instead of overwriting', () {
    final source = File('lib/screens/pay/components/watch_only_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<void> _handleJadeSigningImpl()');
    final end = source.indexOf('jade.signPsbt(', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final flow = source.substring(start, end);
    expect(flow, contains('verifyJadePairing('));
    expect(flow, contains('on JadeWrongDeviceException'));
    expect(flow, contains('jadeErrorWrongDevice'));
    // The old silent overwrite must not come back.
    expect(flow, isNot(contains('copyWith(masterFingerprint')));
  });
}
