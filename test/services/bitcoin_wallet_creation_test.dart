import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/bitcoin_config_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/bitcoin_wallet_creation_service.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Settings _settings(List<WalletConfig> wallets) => Settings(
    currency: 'USD',
    language: 'en',
    btcFormat: 'sats',
    backup: false,
    biometricsEnabled: false,
    bitcoinElectrumNode: 'https://blockstream.info/api',
    nodeType: 'Blockstream',
    reviewDone: false,
    wallets: wallets,
    activeWalletId: wallets.isEmpty ? null : wallets.first.id);

class _Auth extends AuthModel {
  final stored = <String, String>{};
  final deleted = <String>[];
  int generated = 0;
  bool writeFails = false;
  @override
  Future<String> generateMnemonic() async {
    generated++;
    return phrase;
  }

  @override
  Future<bool> validateMnemonic(String mnemonicString) async =>
      mnemonicString == phrase;
  @override
  Future<void> setMnemonic(String walletId, String mnemonic) async {
    stored[walletId] = mnemonic;
    if (writeFails) throw StateError('Storage unavailable');
  }

  @override
  Future<SeedRead> readMnemonic(String walletId,
      {required SeedAccess access,
      SeedSession session = SeedSession.locked}) async {
    if (access == SeedAccess.automatic && !session.unlocked) {
      return const SeedLocked();
    }
    final value = stored[walletId];
    return value == null
        ? const SeedUnavailable(SeedUnavailableReason.absent)
        : SeedOk(value, SeedSource.v2Local);
  }

  @override
  Future<void> deleteWalletMnemonic(String walletId) async {
    deleted.add(walletId);
    stored.remove(walletId);
  }
}

class _Settings extends SettingsModel {
  bool registrationFails = false;
  _Settings(super.state);
  Settings get snapshot => state;
  @override
  Future<void> addWallet(WalletConfig newWallet) async {
    if (registrationFails) throw StateError('Settings unavailable');
    state = state.copyWith(
        wallets: [...state.wallets, newWallet],
        activeWalletId: state.activeWalletId ?? newWallet.id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late _Settings settings;
  late NativeBitcoinPrimitives primitives;
  late List<Map<String, Object?>> derivations;
  late BitcoinWalletCreationService service;
  late WalletConfig spending;
  late bool unlocked;
  setUp(() {
    unlocked = true;
    spending = WalletConfig(id: 'spending', name: 'Spending wallet');
    auth = _Auth();
    auth.stored[spending.id] = 'existing separate spending seed';
    settings = _Settings(_settings([spending]));
    derivations = [];
    primitives = NativeBitcoinPrimitives(
        service: NativeOnchainService(transport: (method, arguments) async {
      expect(method, 'derive');
      derivations.add(arguments);
      return {
        'external': 'external descriptor',
        'internal': 'internal descriptor',
        'accountXpub': 'public xpub'
      };
    }));
    service = BitcoinWalletCreationService(
        auth: auth,
        settings: settings,
        primitives: primitives,
        isSessionUnlocked: () => unlocked,
        // These tests cover creation itself; the wallet.savings policy
        // gate has its own tests.
        ensureAllowed: (_) async {});
  });
  tearDown(() => settings.dispose());

  test('fresh wallet has its own seed and leaves spending wallet selected',
      () async {
    final wallet = await service.create(name: 'My Bitcoin');
    expect(auth.generated, 1);
    expect(wallet.id, isNot(spending.id));
    expect(wallet.isBitcoinSoftware, isTrue);
    expect(wallet.isSparkWallet, isFalse);
    expect(wallet.usesBdk, isTrue);
    expect(wallet.isWatchOnly, isFalse);
    expect(wallet.isHardware, isFalse);
    expect(wallet.isSigner, isFalse);
    expect(wallet.walletType, 'bitcoin');
    expect(wallet.backedUp, isFalse);
    expect(wallet.scriptType, 'bip84');
    expect(wallet.firstScanDone, isFalse);
    expect(auth.stored[wallet.id], phrase);
    expect(auth.stored[spending.id], 'existing separate spending seed');
    expect(settings.snapshot.activeWalletId, spending.id);
    expect(
        settings.snapshot.wallets.map((w) => w.id), [spending.id, wallet.id]);
    expect(derivations.single['scriptType'], 'bip84');
  });

  test(
      'recovery normalizes exactly twelve words and remembers original address type',
      () async {
    final wallet = await service.create(
        name: 'Recovered',
        recoveryPhrase: '  ${phrase.toUpperCase().replaceAll(' ', '  ')} ',
        scriptType: 'bip86');
    expect(auth.generated, 0);
    expect(wallet.isRestore, isTrue);
    expect(wallet.backedUp, isTrue);
    expect(wallet.scriptType, 'bip86');
    expect(derivations.single['mnemonic'], phrase);
    expect(derivations.single['scriptType'], 'bip86');
    expect(auth.stored[wallet.id], phrase);
  });

  test('a locked session refuses to create and stores nothing', () async {
    unlocked = false;
    await expectLater(
        service.create(name: 'Bitcoin'), throwsA(isA<SeedLockedException>()));
    await expectLater(service.create(name: 'Recovered', recoveryPhrase: phrase),
        throwsA(isA<SeedLockedException>()));
    expect(auth.generated, 0);
    expect(derivations, isEmpty);
    expect(auth.stored.keys, [spending.id]);
    expect(settings.snapshot.wallets.length, 1);
  });

  test('invalid or non-twelve-word recovery never stores a wallet', () async {
    for (final input in [
      'not a valid phrase',
      '$phrase $phrase',
      phrase.replaceFirst('about', 'abandon')
    ]) {
      await expectLater(
          service.create(name: 'Recovered', recoveryPhrase: input),
          throwsFormatException);
    }
    expect(derivations, isEmpty);
    expect(settings.snapshot.wallets.length, 1);
    expect(auth.stored.keys, [spending.id]);
  });

  test('BDK derivation failure leaves no registered wallet or stored seed',
      () async {
    final failed = BitcoinWalletCreationService(
        auth: auth,
        settings: settings,
        isSessionUnlocked: () => unlocked,
        ensureAllowed: (_) async {},
        primitives: NativeBitcoinPrimitives(
            service: NativeOnchainService(
                transport: (_, __) async =>
                    throw const OnchainException('unsupported'))));
    await expectLater(
        failed.create(name: 'Bitcoin'), throwsA(isA<OnchainException>()));
    expect(auth.stored.keys, [spending.id]);
    expect(settings.snapshot.wallets.length, 1);
  });

  test('partial secret storage failure cleans up only new secret', () async {
    auth.writeFails = true;
    await expectLater(service.create(name: 'Bitcoin'), throwsStateError);
    expect(auth.deleted.length, 1);
    expect(auth.deleted.single, isNot(spending.id));
    expect(auth.stored.keys, [spending.id]);
    expect(settings.snapshot.wallets.length, 1);
  });

  test(
      'uncertain settings persistence cannot delete a possibly registered seed',
      () async {
    settings.registrationFails = true;
    await expectLater(service.create(name: 'Bitcoin'), throwsStateError);
    expect(auth.deleted, isEmpty);
    expect(auth.stored.length, 2);
  });

  test(
      'software wallet survives settings serialization and capability selection',
      () async {
    final wallet = await service.create(name: 'Bitcoin');
    final restored = WalletConfig.fromMap(wallet.toMap());
    expect(restored.isBitcoinSoftware, isTrue);
    expect(restored.walletType, 'bitcoin');
    final account = BtcColdAccount(restored, ColdAccountKind.software);
    expect(account.subtitle, 'Bitcoin');
    expect(account.capabilities.canSend, isTrue);
    expect(account.capabilities.canReceive, isTrue);
    expect(account.capabilities.canSwap, isFalse);
    expect(account.capabilities.canFundPredictions, isFalse);
    expect(
        pickSpendingWallet(_settings([restored, spending]))!.id, spending.id);
    expect(pickSpendingWallet(_settings([restored])), isNull);
  });

  test(
      'scoped account and receive address resolve the software wallet, not Spark',
      () async {
    final wallet = await service.create(name: 'Bitcoin');
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => _Settings(_settings([spending, wallet]))),
      walletReceiveInfoProvider(wallet.id).overrideWith(
          (ref) async => (address: 'bc1-software-wallet', index: 0)),
    ]);
    addTearDown(container.dispose);
    container.read(bdkScopeWalletIdProvider.notifier).state = wallet.id;
    final selected = container.read(selectedAccountProvider)!;
    expect(selected, isA<BtcColdAccount>());
    expect(selected.wallet!.id, wallet.id);
    expect((selected as BtcColdAccount).kind, ColdAccountKind.software);
    expect(container.read(accountsListProvider).map((a) => a.wallet!.id),
        [spending.id, wallet.id]);
    expect(await container.read(walletAddressProvider(wallet.id).future),
        'bc1-software-wallet');
  });

  test('stored recovery type reaches BDK only for new bitcoin wallet records',
      () async {
    final wallet = await service.create(
        name: 'Bitcoin', recoveryPhrase: phrase, scriptType: 'bip49');
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => _Settings(_settings([spending, wallet]))),
      authModelProvider.overrideWith((ref) => auth),
      sessionAuthProvider.overrideWith((ref) =>
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026))),
    ]);
    addTearDown(container.dispose);
    final config =
        await container.read(bitcoinConfigForWalletProvider(wallet.id).future);
    expect(config.mnemonicScriptType, 'bip49');
    expect(config.isWatchOnly, isFalse);
    await BitcoinConfigModel(config, primitives: primitives)
        .createDescriptors();
    expect(derivations.last['scriptType'], 'bip49');
    expect(derivations.last['mnemonic'], phrase);
  });

  test(
      'legacy hot descriptor stays BIP84 while new software accepts explicit type',
      () async {
    BitcoinConfig config({String? explicitType}) => BitcoinConfig(
        walletId: 'wallet',
        mnemonic: phrase,
        network: Network.bitcoin,
        externalKeychain: KeychainKind.external_,
        internalKeychain: KeychainKind.internal,
        isElectrumBlockchain: true,
        electrumUrl: 'https://blockstream.info/api',
        scriptType: 'bip44',
        mnemonicScriptType: explicitType);
    await BitcoinConfigModel(config(), primitives: primitives)
        .createDescriptors();
    expect(derivations.last['scriptType'], 'bip84');
    await BitcoinConfigModel(config(explicitType: 'bip44'),
            primitives: primitives)
        .createDescriptors();
    expect(derivations.last['scriptType'], 'bip44');
  });
}
