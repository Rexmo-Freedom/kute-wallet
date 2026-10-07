import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/secure/secret_store.dart';

import '../services/support/fake_secret_store.dart';
import '../services/support/recording_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// Stops the provider right after the seed resolved, before the native
/// Spark SDK would connect.
class _Stop implements Exception {
  const _Stop();
}

class _SpyAuth extends AuthModel {
  _SpyAuth(SecretStore store, SecretStore synced)
      : super(store: store, syncedStore: synced);

  final calls = <(SeedAccess, SeedSession)>[];

  @override
  Future<String> requireMnemonic(
    String walletId, {
    SeedAccess access = SeedAccess.automatic,
    required SeedSession session,
  }) async {
    calls.add((access, session));
    await super.requireMnemonic(walletId, access: access, session: session);
    throw const _Stop();
  }
}

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late List<String> reads;
  late _SpyAuth auth;

  setUp(() {
    keychain = FakeKeychain();
    reads = [];
    auth = _SpyAuth(
      RecordingSecretStore(keychain.local, name: 'local', log: reads),
      RecordingSecretStore(keychain.synced, name: 'synced', log: reads),
    );
  });

  ProviderContainer container({bool session = false, bool overlay = false}) {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
      authModelProvider.overrideWith((ref) => auth),
    ]);
    addTearDown(c.dispose);
    if (session) {
      c.read(sessionAuthProvider.notifier).state =
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    }
    c.read(appLockedProvider.notifier).state = overlay;
    return c;
  }

  test('a locked session throws before reading the stored seed', () async {
    keychain.seed('v2:wallet:w1.mnemonic', phrase);
    await expectLater(container().read(breezSDKProvider.future),
        throwsA(isA<SeedLockedException>()));
    expect(auth.calls.single.$1, SeedAccess.automatic);
    expect(auth.calls.single.$2.unlocked, isFalse);
    expect(reads, isEmpty);
  });

  test('the lock overlay blocks it too', () async {
    keychain.seed('v2:wallet:w1.mnemonic', phrase);
    await expectLater(
        container(session: true, overlay: true).read(breezSDKProvider.future),
        throwsA(isA<SeedLockedException>()));
    expect(reads, isEmpty);
  });

  test('an unlocked session resolves the stored seed before connecting',
      () async {
    keychain.seed('v2:wallet:w1.mnemonic', phrase);
    await expectLater(container(session: true).read(breezSDKProvider.future),
        throwsA(isA<_Stop>()));
    expect(auth.calls.single.$2.unlocked, isTrue);
    expect(reads, ['local:v2:wallet:w1.mnemonic']);
  });

  test('a missing seed never reaches the SDK', () async {
    await expectLater(
        container(session: true).read(breezSDKProvider.future),
        throwsA(isA<SeedUnavailableException>()
            .having((e) => e.reason, 'reason', SeedUnavailableReason.absent)));
  });
}
