import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/claim_auto_fire.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

import '../support/fake_secret_store.dart';
import '../support/recording_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const kuteEvmAddress = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';

final _session =
    SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
final _stored = WalletConfig(id: 'w1', name: 'Spending');
final _legacyPasskey =
    WalletConfig(id: 'p1', name: 'Passkey', isPasskey: true, passkeyLabel: 'L');
final _sdkPasskey = WalletConfig(
    id: 'p2',
    name: 'Passkey',
    isPasskey: true,
    passkeyLabel: 'L',
    passkeyProvider: 'breez-0.17');

Settings _settings(List<WalletConfig> wallets) => Settings(
      wallets: wallets,
      activeWalletId: wallets.first.id,
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

/// Any read of a seed, a PIN-encrypted copy, a stored PIN or a passkey
/// cache.
bool _isSeedRead(String entry) =>
    entry.contains('mnemonic') ||
    entry.contains('biometric_pin') ||
    entry.contains('prf_seed') ||
    entry.contains('passkey017');

class _FakeTrading extends PolymarketTradingNotifier {
  int redeems = 0;

  static const position = Position(
    proxyWallet: '0x0000000000000000000000000000000000000001',
    asset: 'yes',
    conditionId: '0xc1',
    size: 1,
    avgPrice: 0.5,
    initialValue: 0.5,
    currentValue: 1,
    cashPnl: 0.5,
    percentPnl: 100,
    totalBought: 0.5,
    realizedPnl: 0,
    percentRealizedPnl: 0,
    curPrice: 1,
    redeemable: true,
    title: 'Market',
    slug: 'market',
    eventSlug: 'event',
    outcome: 'Yes',
    outcomeIndex: 0,
    oppositeOutcome: 'No',
    oppositeAsset: 'no',
  );

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(openPositions: [position]);

  @override
  Future<double?> redeemPosition({
    required String conditionId,
    List<int> indexSets = const [1, 2],
    String? trigger,
    String? surface,
    bool reportFailure = true,
  }) async {
    redeems++;
    return 0;
  }

  void tick(double balance) => state = AsyncData(PolymarketTradingState(
      openPositions: const [position], usdcBalance: balance));
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const prfChannel = MethodChannel('com.kutewallet.app/passkey_prf');
  late FakeKeychain keychain;
  late List<String> reads;
  late List<MethodCall> prfCalls;
  late Directory hiveDir;

  setUp(() async {
    keychain = FakeKeychain();
    reads = [];
    prfCalls = [];
    SecretStores.debugOverride(
      local: RecordingSecretStore(keychain.local, name: 'local', log: reads),
      synced: RecordingSecretStore(keychain.synced, name: 'synced', log: reads),
    );
    PasskeyPrfService.clearMemory();
    PasskeyService.clearSession();
    messenger.setMockMethodCallHandler(prfChannel, (call) async {
      prfCalls.add(call);
      throw PlatformException(code: 'unexpected');
    });
    hiveDir = await Directory.systemTemp.createTemp('automatic_signers');
    Hive.init(hiveDir.path);
    keychain.seed('v2:wallet:w1.mnemonic', phrase);
  });

  tearDown(() async {
    SecretStores.debugReset();
    messenger.setMockMethodCallHandler(prfChannel, null);
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  ProviderContainer containerWith(WalletConfig spending,
      {bool session = false, bool overlay = false}) {
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => SettingsModel(_settings([spending]))),
    ]);
    addTearDown(container.dispose);
    if (session) container.read(sessionAuthProvider.notifier).state = _session;
    if (overlay) container.read(appLockedProvider.notifier).state = true;
    return container;
  }

  group('resolver', () {
    for (final wallet in [_stored, _legacyPasskey, _sdkPasskey]) {
      test('never resolves ${wallet.id} for automatic access while locked',
          () async {
        for (final session in const [
          SeedSession.locked,
          SeedSession(typedPin: '123456'),
        ]) {
          expect(
              await resolveBip39MnemonicFor(wallet,
                  access: SeedAccess.automatic, session: session),
              isNull);
        }
        expect(reads, isEmpty);
        expect(prfCalls, isEmpty);
      });
    }

    test('resolves a stored wallet once unlocked', () async {
      expect(
          await resolveBip39MnemonicFor(_stored,
              access: SeedAccess.automatic,
              session: const SeedSession(unlocked: true)),
          phrase);
    });
  });

  group('hyperliquidAddressProvider', () {
    test('derives nothing while locked or behind the overlay, then derives',
        () async {
      final container = containerWith(_stored);
      container.listen(hyperliquidAddressProvider, (_, __) {});
      expect(await container.read(hyperliquidAddressProvider.future), isNull);

      container.read(sessionAuthProvider.notifier).state = _session;
      container.read(appLockedProvider.notifier).state = true;
      expect(await container.read(hyperliquidAddressProvider.future), isNull);
      expect(reads, isEmpty);

      container.read(appLockedProvider.notifier).state = false;
      final address = await container.read(hyperliquidAddressProvider.future);
      expect(address?.toLowerCase(), kuteEvmAddress.toLowerCase());
    });

    test('passkey wallets derive nothing while locked', () async {
      for (final wallet in [_legacyPasskey, _sdkPasskey]) {
        final container = containerWith(wallet, session: true, overlay: true);
        expect(await container.read(hyperliquidAddressProvider.future), isNull);
      }
      expect(reads.where(_isSeedRead), isEmpty);
      expect(prfCalls, isEmpty);
    });
  });

  test('Hyperliquid onboarding and the builder fee stay locked', () async {
    for (final container in [
      containerWith(_stored),
      containerWith(_stored, session: true, overlay: true),
      containerWith(_legacyPasskey),
    ]) {
      container.listen(hyperliquidTradingProvider, (_, __) {});
      await container.read(hyperliquidTradingProvider.future);
      final notifier = container.read(hyperliquidTradingProvider.notifier);
      await expectLater(
          notifier.ensureOnboarded(), throwsA(isA<SeedLockedException>()));
      expect(await notifier.ensureBuilderFeeApproved(), isFalse);
    }
    expect(reads.where(_isSeedRead), isEmpty);
    expect(prfCalls, isEmpty);
  });

  test('automatic claims wait for an unlocked session, passkey wallets too',
      () async {
    for (final wallet in [_stored, _legacyPasskey]) {
      final fake = _FakeTrading();
      final container = ProviderContainer(overrides: [
        settingsProvider
            .overrideWith((ref) => SettingsModel(_settings([wallet]))),
        polymarketTradingProvider.overrideWith(() => fake),
      ]);
      addTearDown(container.dispose);
      container.listen(polymarketTradingProvider, (_, __) {});
      await container.read(polymarketTradingProvider.future);
      container.read(claimAutoFireProvider);

      fake.tick(1);
      await _settle();
      expect(fake.redeems, 0);

      container.read(sessionAuthProvider.notifier).state = _session;
      container.read(appLockedProvider.notifier).state = true;
      fake.tick(2);
      await _settle();
      expect(fake.redeems, 0, reason: 'the lock overlay is up');

      container.read(appLockedProvider.notifier).state = false;
      fake.tick(3);
      await _settle();
      expect(fake.redeems, 1);
    }
  });

  test('the wallet BDK config uses no seed while locked, then reads it',
      () async {
    final container = containerWith(_stored);
    final config = bitcoinConfigForWalletProvider('w1');
    container.listen(config, (_, __) {});
    await expectLater(container.read(config.future), throwsException);
    expect(reads.where(_isSeedRead), isEmpty);

    container.read(sessionAuthProvider.notifier).state = _session;
    expect((await container.read(config.future)).mnemonic, phrase);
  });

  test('the recovery check backfill reads nothing while locked', () async {
    await RecoveryCheck.backfill(
      settings: SettingsModel(_settings([_stored])),
      wallets: [_stored],
      auth: AuthModel(),
      session: SeedSession.locked,
      deriveAddress: (_) async => fail('must not derive'),
    );
    expect(reads, isEmpty);
  });

  test('no session PIN remains and every resolver call is automatic', () {
    final sessionPin = 'session' 'PinProvider';
    final emptyPin = 'pin ?? ' "''";
    final calls =
        RegExp(r'await resolveBip39MnemonicFor\((.*?)\);', dotAll: true);
    var resolverCalls = 0;
    for (final root in ['lib', 'test']) {
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        expect(source.contains(sessionPin), isFalse, reason: file.path);
        if (root != 'lib') continue;
        expect(source.contains(emptyPin), isFalse, reason: file.path);
        for (final match in calls.allMatches(source)) {
          resolverCalls++;
          expect(match.group(1), contains('access: SeedAccess.automatic'),
              reason: file.path);
        }
      }
    }
    expect(resolverCalls, greaterThanOrEqualTo(10));
  });
}
