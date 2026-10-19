// A passkey record with no stored label derives its seed from the
// device-wide cached label, which any later create or restore overwrites.
// The startup backfill pins the label on the record once, and the cache
// refuses to change while such a record still exists.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/tracking_service.dart';

WalletConfig _passkey(String id, {String? label, String? provider}) =>
    WalletConfig(
      id: id,
      name: id,
      sparkEnabled: true,
      isPasskey: true,
      passkeyLabel: label,
      passkeyProvider: provider,
    );

void main() {
  group('backfillLegacyPasskeyLabels', () {
    test('a record with no label takes the cached label', () {
      final out = backfillLegacyPasskeyLabels(
        [_passkey('A'), WalletConfig(id: 'S', name: 'S')],
        cachedLabel: 'Spending Wallet · 1',
      );
      expect(out[0].passkeyLabel, 'Spending Wallet · 1');
      expect(out[1].isPasskey, isFalse);
      expect(out[1].passkeyLabel, isNull);
    });

    test('no cached label falls back to the historical default', () {
      final out = backfillLegacyPasskeyLabels([_passkey('A')], cachedLabel: null);
      expect(out.single.passkeyLabel, kLegacyPasskeyDefaultLabel);
      expect(
          backfillLegacyPasskeyLabels([_passkey('A')], cachedLabel: '')
              .single
              .passkeyLabel,
          kLegacyPasskeyDefaultLabel);
    });

    test('a cached label another record already carries is not reused', () {
      // The later wallet overwrote the cache with its own label; the old
      // record was created with the default.
      final out = backfillLegacyPasskeyLabels(
        [
          _passkey('old'),
          _passkey('new', label: 'Spending Wallet · 2', provider: 'breez-0.17'),
        ],
        cachedLabel: 'Spending Wallet · 2',
      );
      expect(out[0].passkeyLabel, kLegacyPasskeyDefaultLabel);
      expect(out[1].passkeyLabel, 'Spending Wallet · 2');
    });

    test('a stored label is never overwritten', () {
      final wallets = [
        _passkey('A', label: 'Mine · 1', provider: 'breez-0.17'),
        _passkey('B', label: 'Default'),
      ];
      final out = backfillLegacyPasskeyLabels(wallets, cachedLabel: 'Other · 9');
      expect(identical(out, wallets), isTrue);
      expect(out[0].passkeyLabel, 'Mine · 1');
      expect(out[1].passkeyLabel, 'Default');
    });

    test('is idempotent', () {
      final once =
          backfillLegacyPasskeyLabels([_passkey('A')], cachedLabel: 'L · 1');
      final twice = backfillLegacyPasskeyLabels(once, cachedLabel: 'M · 2');
      expect(identical(once, twice), isTrue);
      expect(twice.single.passkeyLabel, 'L · 1');
    });

    test('keeps every other field', () {
      final out = backfillLegacyPasskeyLabels(
        [_passkey('A').copyWith(backedUp: true, isRestore: true)],
        cachedLabel: 'L · 1',
      );
      expect(out.single.id, 'A');
      expect(out.single.backedUp, isTrue);
      expect(out.single.isRestore, isTrue);
      expect(out.single.passkeyProvider, isNull);
    });
  });

  group('PasskeyService.cacheLabel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory hiveDir;
    late List<(String, Map<String, Object>?)> events;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('label_backfill');
      Hive.init(hiveDir.path);
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });

    tearDown(() async {
      TrackingService.debugTrackObserver = null;
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    test('keeps the cached label while an unlabelled passkey record exists',
        () async {
      final box = await Hive.openBox('settings');
      await box.put('passkey_cached_label', 'Default');
      await box.put('wallets', [_passkey('old').toMap()]);

      await PasskeyService.cacheLabel('Spending Wallet · 2');

      expect(await PasskeyService.getCachedLabel(), 'Default');
      expect(events.map((e) => e.$1), contains('passkey_cached_label_kept'));
      expect(events.single.$2, isNull);
    });

    test('writes once every passkey record carries its label', () async {
      final box = await Hive.openBox('settings');
      await box.put('passkey_cached_label', 'Default');
      final labelled = backfillLegacyPasskeyLabels([_passkey('old')],
          cachedLabel: 'Default');
      await box.put('wallets', labelled.map((w) => w.toMap()).toList());

      await PasskeyService.cacheLabel('Spending Wallet · 2');

      expect(await PasskeyService.getCachedLabel(), 'Spending Wallet · 2');
      expect(events, isEmpty);
    });

    test('writes when nothing is cached yet, and for a non-passkey list',
        () async {
      final box = await Hive.openBox('settings');
      await box.put('wallets', [_passkey('old').toMap()]);
      await PasskeyService.cacheLabel('L · 1');
      expect(await PasskeyService.getCachedLabel(), 'L · 1');

      await box.put('wallets', [WalletConfig(id: 'S', name: 'S').toMap()]);
      await PasskeyService.cacheLabel('M · 2');
      expect(await PasskeyService.getCachedLabel(), 'M · 2');
    });
  });
}
