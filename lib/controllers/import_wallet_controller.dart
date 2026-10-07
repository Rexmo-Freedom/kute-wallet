import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart' show appL10n;
import 'package:kute/models/settings_model.dart'; // WalletConfig
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/add_wallet_model.dart'; // WalletDeviceConfig
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

final importWalletControllerProvider =
StateNotifierProvider<ImportWalletController, AsyncValue<void>>((ref) {
  return ImportWalletController(ref);
});

class ImportWalletController extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  ImportWalletController(this.ref) : super(const AsyncData(null));

  /// ID and device type of the wallet the last successful import created,
  /// so the import screen can route a Ledger to the investing setup step
  /// (Wallet hardening Phase 4, P4.3). Null until an import succeeds.
  String? lastImportedWalletId;
  String? lastImportedWalletType;

  Future<void> importXpub({
    required String xpub,
    required WalletDeviceConfig config,
    String? scriptType,
    String? masterFingerprint,
  }) async {
    // 1. Validation
    if (xpub.isEmpty) {
      state = AsyncError(
          LocalizedError.from(appL10n(), (l) => l.importEnterXpub),
          StackTrace.current);
      return;
    }

    // Accept plain xpub/zpub/ypub OR output descriptors like tr([fp/path]xpub.../0/*)
    final xpubRegex = RegExp(r'^[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]{100,108}$');
    final descriptorRegex = RegExp(r'^(tr|wpkh|sh\(wpkh|pkh)\(.*[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]+.*\)$');
    if (!xpubRegex.hasMatch(xpub) && !descriptorRegex.hasMatch(xpub)) {
      state = AsyncError(
          LocalizedError.from(appL10n(), (l) => l.importInvalidXpub),
          StackTrace.current);
      return;
    }

    // 1b. Check for duplicate xpub across existing wallets
    final settings = ref.read(settingsProvider);
    final authModel = ref.read(authModelProvider);
    for (final wallet in settings.wallets) {
      if (wallet.isExternalAddress) continue;
      final existingXpub = await authModel.getExtendedPublicKey(wallet.id);
      if (existingXpub != null && existingXpub == xpub) {
        state = AsyncError(
          LocalizedError.from(
              appL10n(), (l) => l.importAlreadyImported(wallet.name)),
          StackTrace.current,
        );
        return;
      }
    }

    // 2. Set Loading
    lastImportedWalletId = null;
    lastImportedWalletType = null;
    state = const AsyncLoading();

    try {
      // Both the import screen and smart QR scanner enter here. A hardware
      // vendor and "Other wallet" (watch-only) both answer to
      // `hardware.wallet`. Existing wallets stay usable when new imports
      // are disabled.
      await RuntimeCapabilitiesService.instance
          .ensureAllowed(xpubImportCapability(config.type));
      final newWalletId = DateTime.now().millisecondsSinceEpoch.toString();

      // 3. Save to Secure Storage
      await ref.read(authModelProvider).setExtendedPublicKey(newWalletId, xpub);

      // 4. Create Config — clean name + auto-numbering on collision.
      // Earlier this stamped the last 4 digits of the wallet id onto
      // every imported wallet ("LEDGER 4047") to guarantee a unique
      // label. The cost was every imported wallet looking like a
      // serial number. Now we use the vendor title as-is and only
      // append a counter ("Ledger 2", "Ledger 3") when the user
      // actually adds a duplicate.
      final existing =
          ref.read(settingsProvider).wallets.map((w) => w.name).toSet();
      final base = config.title;
      var name = base;
      var counter = 2;
      while (existing.contains(name)) {
        name = '$base $counter';
        counter++;
      }
      final newWalletConfig = WalletConfig(
        id: newWalletId,
        name: name,
        sparkEnabled: false,
        backedUp: true,
        isWatchOnly: true,
        isHardware: config.type != 'generic' && config.type != 'spark',
        walletType: config.type,
        scriptType: scriptType,
        // Persist only a valid 8-hex fingerprint; store null otherwise so a
        // mislabelled value can never reach a hex parse downstream (the
        // "Invalid radix-16 number" Move error). The real fingerprint is
        // recovered from the device's signed PSBT regardless.
        masterFingerprint: (masterFingerprint != null &&
                RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(masterFingerprint))
            ? masterFingerprint
            : null,
      );

      // 5. Add to Settings
      await ref.read(settingsProvider.notifier).addWallet(newWalletConfig);

      // No scan at add — we only store the xpub + config here. The first
      // on-chain sync (a one-time Electrum FULL scan, gated by the
      // wallet's persisted `firstScanDone` flag) runs on the user's first
      // pull-to-refresh; every sync after that is incremental.

      // 6. Success
      lastImportedWalletId = newWalletId;
      lastImportedWalletType = newWalletConfig.walletType;
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> importExternalAddress({
    required String address,
    required String walletName,
  }) async {
    // 1. Validation
    if (address.isEmpty) {
      state = AsyncError(
          LocalizedError.from(appL10n(), (l) => l.importEnterAddress),
          StackTrace.current);
      return;
    }

    // Basic Bitcoin address validation (mainnet: 1..., 3..., bc1...)
    final addressRegex = RegExp(r'^(1[1-9A-HJ-NP-Za-km-z]{25,34}|3[1-9A-HJ-NP-Za-km-z]{25,34}|bc1[a-zA-HJ-NP-Z0-9]{25,90})$');
    if (!addressRegex.hasMatch(address)) {
      state = AsyncError(
          LocalizedError.from(appL10n(), (l) => l.importInvalidAddress),
          StackTrace.current);
      return;
    }

    // 2. Set Loading
    lastImportedWalletId = null;
    lastImportedWalletType = null;
    state = const AsyncLoading();

    try {
      // Tracking an address answers to `wallet.tracked`; addresses already
      // tracked keep working when it is off.
      await RuntimeCapabilitiesService.instance
          .ensureAllowed(kTrackedAddressCapability);
      final newWalletId = DateTime.now().millisecondsSinceEpoch.toString();

      // 3. Save the external address to secure storage
      await ref.read(authModelProvider).setExternalAddress(newWalletId, address);

      // 4. Create Config
      final name = walletName.trim().isEmpty
          ? "Track ${address.substring(0, 8)}..."
          : walletName.trim();

      final newWalletConfig = WalletConfig(
        id: newWalletId,
        name: name,
        sparkEnabled: false,
        backedUp: true,
        isWatchOnly: true,
        isHardware: false,
        isExternalAddress: true,
        walletType: 'external_address',
      );

      // 5. Add to Settings
      await ref.read(settingsProvider.notifier).addWallet(newWalletConfig);

      // 6. Success
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
