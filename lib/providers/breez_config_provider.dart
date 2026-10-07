import 'package:kute/models/breez/init.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Spark SDK is bound to the user's spending wallet for the
/// lifetime of the session — Lightning channels and the Polymarket
/// Safe all live inside the spending wallet's
/// SDK instance. Carousel swipes to savings / hardware / watch-
/// only / signer wallets DO NOT change which wallet Spark
/// represents.
///
/// Previously this provider watched `settings.activeWallet`, which
/// meant every swipe to a savings page tore down the SDK
/// (`disconnect()`) and reinitialised it for that wallet's
/// mnemonic — minutes of allocation churn (~14 MB GC cycles per
/// swipe in the user's logs) and a flurry of network reconnects
/// for nothing, since the savings wallet doesn't even use Spark.
///
/// Pin to the spending wallet directly. The provider now only
/// rebuilds when the spending wallet identity itself changes (rare
/// — typically once per app install) and stays connected across
/// every carousel swipe / active-wallet change.
WalletConfig? _pickSpending(Settings settings) {
  for (final w in settings.wallets) {
    if (!w.isSparkWallet) continue;
    if (w.isHardware) continue;
    if (w.isWatchOnly) continue;
    if (w.isExternalAddress) continue;
    if (w.isSigner) continue;
    return w;
  }
  return null;
}

final breezSDKProvider = FutureProvider<BreezSdkSpark>((ref) async {
  // Watch the SPENDING wallet's id only. `.select` narrows the
  // dependency so unrelated settings churn (currency, btc format,
  // theme) doesn't tear the SDK down, AND so swiping the carousel
  // to a savings wallet doesn't either — the spending wallet's id
  // is invariant across that swipe.
  final spendingId = ref.watch(
      settingsProvider.select((s) => _pickSpending(s)?.id));
  final spendingIsPasskey = ref.watch(
      settingsProvider.select((s) => _pickSpending(s)?.isPasskey ?? false));
  // Passkey VINTAGE + per-wallet label — both are create-time-immutable
  // for a given wallet identity, so watching them adds no extra rebuild
  // pressure beyond the id watch above.
  final spendingPasskeyVintage = ref.watch(
      settingsProvider.select((s) => _pickSpending(s)?.passkeyProvider));
  final spendingPasskeyLabel = ref.watch(
      settingsProvider.select((s) => _pickSpending(s)?.passkeyLabel));

  // CLEANUP — only fires when this provider is genuinely
  // invalidated (spending wallet changed identity, or app shutdown).
  // Removed `.autoDispose` so a transient "no consumers" gap on a
  // wallet swap doesn't trigger a disconnect we'll have to reverse
  // a few hundred ms later.
  ref.onDispose(() {
    BreezSdkSpark().disconnect();
  });

  if (spendingId == null) {
    throw Exception('No spending wallet present.');
  }

  // Passkey wallets re-derive the seed from PRF on every call — they
  // do NOT need a PIN. The session gate below applies only to stored
  // wallets. Without this
  // split, a freshly-recovered passkey wallet whose PIN session
  // isn't hydrated yet throws here, the Breez SDK never connects,
  // the Spark stream never opens, and the Activity feed stays empty
  // forever (the user's reported "balance shows but no transactions"
  // symptom).
  if (spendingIsPasskey) {
    // Resolution order replicates 0.15.1 exactly: the wallet's own
    // stored label first, then the Hive 'settings' box
    // 'passkey_cached_label' fallback (getCachedLabel). Same order for
    // both vintages so a legacy wallet resolves the exact PRF salt it
    // was created with.
    final label =
        spendingPasskeyLabel ?? await PasskeyService.getCachedLabel();
    if (spendingPasskeyVintage == null) {
      // LEGACY (pre-2.x) vintage: reconstruct through the app's own
      // 0.15.1 PRF pipeline (pinned credential + secure-storage cache).
      // FAIL CLOSED — if this throws, the error propagates and the SDK
      // simply doesn't connect this round. We must never fall through
      // to the new-SDK derivation (different credential resolution ⇒
      // different seed ⇒ the user's funds "vanish") and never create.
      final seed = await PasskeyService.getLegacySeed(label: label);
      await initializeSDKWithSeed(seed, spendingId);
    } else {
      // 'breez-0.17' vintage: the new PasskeyClient path, now pinned to
      // the stored credential id inside getWallet.
      final wallet =
          await PasskeyService.getWallet(label: label, legacy: false);
      await initializeSDKWithSeed(wallet.seed, spendingId);
    }
  } else {
    // A locked session throws SeedLockedException; `completeUnlock` heals
    // the cached error after unlock.
    final mnemonic = await ref
        .read(authModelProvider)
        .requireMnemonic(spendingId, session: ref.read(seedSessionProvider));
    await initializeSDK(mnemonic, spendingId);
  }

  return BreezSdkSpark();
});