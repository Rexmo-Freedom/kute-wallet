// lib/services/add_wallet_capabilities.dart
//
// Which runtime capability governs each way to add a bitcoin wallet beyond
// the spending account. Three separate backend switches, all shipping
// enabled (founder decision, October 2026):
//
// * `hardware.wallet`: pairing or importing a hardware signer (Ledger,
//   Jade, Keystone, Passport, SeedSigner, Krux) and adding a watch-only
//   wallet from an xpub or descriptor ("Other wallet"). Watch-only is the
//   same kind of wallet as a hardware one, so one switch governs both;
//   the separate `wallet.watchonly` switch is retired.
// * `wallet.savings`: creating or recovering another hot bitcoin (BDK)
//   wallet from 12 words.
// * `wallet.tracked`: tracking a single bitcoin address.
//
// Every option is always shown (founder decision): Add wallet, the wallets
// menu and settings search never hide one. A tap on an option whose
// capability is withheld does not start its flow (no scan, no pairing, no
// import screen); it opens the shared unavailable sheet with the policy's
// own reason, which for a region block is the region / VPN copy. The
// import and creation services re-check at commit as the backstop.
// Wallets already added keep working whatever these say.

import 'package:kute/services/runtime_capabilities_service.dart';

const kHardwareWalletCapability = 'hardware.wallet';
const kSavingsWalletCapability = 'wallet.savings';
const kTrackedAddressCapability = 'wallet.tracked';

const kAddWalletCapabilities = [
  kHardwareWalletCapability,
  kSavingsWalletCapability,
  kTrackedAddressCapability,
];

/// The capability behind an Add wallet option, by its `WalletDeviceConfig`
/// type. Null for the spending account (`spark`), which none of these
/// switches governs. Every hardware vendor row and "Other wallet"
/// (`generic`, a watch-only xpub) map to `hardware.wallet`.
String? addWalletOptionCapability(String type) => switch (type) {
      'spark' => null,
      'bitcoin' => kSavingsWalletCapability,
      'external_address' => kTrackedAddressCapability,
      _ => kHardwareWalletCapability,
    };

/// The capability an xpub or descriptor import commits under, whatever
/// its row: a hardware vendor and "Other wallet" (watch-only) alike answer
/// to `hardware.wallet`. Used by `ImportWalletController` and the import
/// screen.
String xpubImportCapability(String type) => kHardwareWalletCapability;

/// The tap-time check for the Add wallet option of [type]: null when its
/// flow may start, otherwise the policy's denial to show in the
/// unavailable sheet. Asks the backend unless a policy fetched in the last
/// 30 seconds can answer; an unreachable backend falls back to
/// [kOfflineAllowedCapabilities].
Future<CapabilityDecision?> addWalletOptionDenial(
    RuntimeCapabilitiesService policy, String type) async {
  final capability = addWalletOptionCapability(type);
  if (capability == null) return null;
  try {
    await policy.ensureAllowed(capability,
        maxAge: const Duration(seconds: 30));
    return null;
  } on CapabilityUnavailableException catch (e) {
    return e.decision;
  }
}
