import 'dart:math';

import 'package:kute/models/auth_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// Creates a separate on-chain wallet using the existing native BDK and local
/// secure-storage paths. Never provisions Spark, Lightning or trading accounts.
class BitcoinWalletCreationService {
  final AuthModel auth;
  final SettingsModel settings;
  final NativeBitcoinPrimitives primitives;

  /// Whether the session is unlocked right now.
  final bool Function() isSessionUnlocked;

  /// The runtime policy check for `wallet.savings`; throws while the
  /// policy withholds new bitcoin wallets. Wallets already created keep
  /// working whatever it says.
  final Future<void> Function(String capability) ensureAllowed;
  BitcoinWalletCreationService({
    required this.auth,
    required this.settings,
    required this.isSessionUnlocked,
    NativeBitcoinPrimitives? primitives,
    Future<void> Function(String capability)? ensureAllowed,
  })  : primitives = primitives ?? NativeBitcoinPrimitives.instance,
        ensureAllowed =
            ensureAllowed ?? RuntimeCapabilitiesService.instance.ensureAllowed;

  Future<WalletConfig> create({
    required String name,
    String? recoveryPhrase,
    String scriptType = 'bip84',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 60) {
      throw const FormatException(
          'Enter a wallet name of up to 60 characters.');
    }
    if (!isSessionUnlocked()) throw const SeedLockedException();
    if (!const {'bip84', 'bip86', 'bip49', 'bip44'}.contains(scriptType)) {
      throw const FormatException('Choose a supported Bitcoin address type.');
    }
    await ensureAllowed(kSavingsWalletCapability);
    final recovered = recoveryPhrase != null;
    final mnemonic = (recoveryPhrase ?? await auth.generateMnemonic())
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .join(' ');
    if (mnemonic.split(' ').length != 12 ||
        !await auth.validateMnemonic(mnemonic)) {
      throw const FormatException('Enter a valid 12-word recovery phrase.');
    }
    // Validate derivation with the same BDK implementation that will receive
    // and sign. A platform failure cannot leave a partially registered wallet.
    await primitives.derive(
        network: Network.bitcoin, mnemonic: mnemonic, scriptType: scriptType);
    final random = Random.secure();
    final id =
        'btc-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final wallet = WalletConfig(
        id: id,
        name: cleanName,
        sparkEnabled: false,
        walletType: 'bitcoin',
        scriptType: scriptType,
        backedUp: recovered,
        isRestore: recovered);
    try {
      await auth.setMnemonic(id, mnemonic);
    } catch (_) {
      await auth.deleteWalletMnemonic(id);
      rethrow;
    }
    // Keep the stored seed if registration fails after persistence began.
    // A partially committed settings write must never leave a wallet keyless.
    await settings.addWallet(wallet);
    return wallet;
  }
}
