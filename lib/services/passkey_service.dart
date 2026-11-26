import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart'
    show Listenable, ValueListenable, ValueNotifier, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:kute/services/tracking_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/passkey_home.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_session.dart';
import 'package:kute/services/evm_derivation_policy.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

export 'package:kute/services/passkey_home.dart';

/// Service for passkey-based wallet creation and restoration.
///
/// Uses the Breez SDK [PasskeyClient], which derives wallet keys
/// deterministically from WebAuthn PRF extension output. Derived seeds are
/// cached in device-local secure storage.
/// App session authentication gates later seed access; recovery uses the passkey.
///
/// TWO HOMES. A passkey lives on exactly one Relying Party ([PasskeyHome]):
/// every wallet created before Kute had its own RP is on Breez's shared RP
/// `keys.breez.technology` and stays there forever; new wallets go to
/// Kute's RP `kutewallet.com`. Each home is a [PasskeyHomeService] with its
/// OWN client, label identity, pinned credential, seed cache, discovery and
/// pending labels, so a wallet of one home can never read or write an
/// entry of the other. The static API of this class IS the Breez home
/// ([breez]), byte-for-byte what it was before Kute's home existed: the
/// same RP, SDK calls, storage keys and cache keys. Kute-home wallets go
/// through [kute]. Route a wallet by its marker with [forMarker] /
/// [PasskeyHomes.routeFor] (an unknown marker throws).
///
/// Cross-device restore works because the passkey credential syncs via the
/// platform (iOS passkeys / Android Credential Manager) and the seed is a
/// deterministic function of (PRF output, label): same passkey + same label =
/// same wallet seed.
///
/// Method mapping (breez 0.17.1): [createWallet] → `register()` (MINTS a new
/// passkey); [getWallet] → `signIn()` (derives from an EXISTING passkey, and
/// fails cleanly if none — deliberately NOT `connectWithPasskey`, which would
/// silently mint a new credential and derive a different, fund-losing seed).
class PasskeyService {
  static final _session = PasskeySession();

  static Future<void> drainPendingWrites() => _session.drainWrites();

  /// The Breez-home service: every existing SDK passkey wallet
  /// (`passkeyProvider == 'breez-0.17'`). The static API of this class
  /// delegates here.
  static final PasskeyHomeService breez =
      PasskeyHomeService._(PasskeyHome.breez);

  /// Kute's own home (`passkeyProvider == 'kute-1'`).
  static final PasskeyHomeService kute = PasskeyHomeService._(PasskeyHome.kute);

  /// The service of [home].
  static PasskeyHomeService home(PasskeyHome home) => switch (home) {
        PasskeyHome.breez => breez,
        PasskeyHome.kute => kute,
      };

  /// The service a wallet's provider [marker] names. Throws for a legacy
  /// (`null`) wallet, which has no SDK home, and for an unknown marker.
  static PasskeyHomeService forMarker(String? marker) =>
      home(PasskeyHomes.homeForMarker(marker));

  @visibleForTesting
  static void debugSetClient(PasskeyClient? client) {
    breez._client = client;
    clearSession();
  }

  /// [debugSetClient] for any home.
  @visibleForTesting
  static void debugSetHomeClient(PasskeyHome h, PasskeyClient? client) {
    home(h)._client = client;
    clearSession();
  }

  /// Test seam: builds every [PasskeyClient] a home constructs (its cached
  /// client and the one-off register client), given the home and the
  /// config it would pass. Null in production.
  @visibleForTesting
  static PasskeyClient Function(PasskeyHome home, PasskeyConfig? config)?
      debugClientFactory;

  /// Test seam: the platform's domain-association probe for a home
  /// (`PasskeyProvider.checkDomainAssociation`). Null in production.
  @visibleForTesting
  static Future<DomainAssociation> Function(PasskeyHome home)?
      debugDomainAssociation;

  /// Forget every derived wallet and pending ceremony held in memory, in
  /// both homes. Storage is untouched. Called by the wipe path.
  static void clearSession() {
    _session.clear();
    breez._clearMemory();
    kute._clearMemory();
  }

  // ─────────────────── retired iCloud recovery manifest ───────────────────
  //
  // Earlier builds kept a NON-SECRET { label -> vintage } map in the
  // iCloud-synced Keychain under this key so a fresh device could guess
  // labels. Recovery now follows the Breez flow instead: one discovery
  // sign-in (`signIn(label: null)`) lists the labels from Nostr and names
  // the credential, and the chosen wallet re-authenticates pinned to that
  // credential. The key is kept ONLY so [retireRecoveryManifest] can delete
  // the stale synced item once; nothing reads or writes it any more.
  static const String _retiredManifestKey = 'passkey017_recovery_manifest_v1';
  static const String _manifestRetiredFlag = 'passkey_recovery_manifest_retired';

  /// Vintage tag for wallets derived through the SDK's [PasskeyClient] on
  /// the Breez RP. Mirrors `WalletConfig.passkeyProvider == 'breez-0.17'`.
  /// The literal is HISTORICAL — it was minted when the new stack shipped
  /// on SDK 0.17.1 — but it is a persisted discriminator on every
  /// new-stack wallet, so it must NEVER be renamed (same for the
  /// `passkey017_*` storage keys).
  static const String vintageBreez017 = PasskeyHomes.markerBreez;

  /// Vintage tag for wallets on Kute's own RP (`kutewallet.com`).
  static const String vintageKute1 = PasskeyHomes.markerKute;

  /// Vintage tag for LEGACY (pre-2.x, breez-0.15.1) passkey wallets whose
  /// seed reconstructs via [getLegacySeed]. Mirrors the `null`
  /// `WalletConfig.passkeyProvider` on those wallets, but recorded as an
  /// explicit non-null string.
  static const String vintageLegacy = '0.15.1';

  /// Check if passkey PRF is supported (and the app is RP-associated) on this
  /// device, for the Breez home.
  static Future<bool> isAvailable() => breez.isAvailable();

  /// [PasskeyHomeService.createWallet] on the Breez home.
  static Future<Wallet> createWallet({
    required String label,
    String? userDisplayName,
  }) =>
      breez.createWallet(label: label, userDisplayName: userDisplayName);

  // ───────────────────────── LEGACY (pre-2.x) SEED PATH ─────────────────────
  //
  // Passkey wallets created on breez-sdk 0.15.1 did NOT derive through the
  // SDK's PasskeyClient — they derived through the app's own
  // `PasskeyPrfService` (native channel `com.kutewallet.app/passkey_prf`),
  // which pins the WebAuthn assertion to a stored credential id and caches
  // the PRF output in secure storage. The 0.17.1 `signIn` runs un-pinned
  // with no cache, so on a device holding several 'kute-wallet-user'
  // credentials (shared RP!) it can resolve a DIFFERENT credential and
  // therefore a different seed — the funds-loss bug. The KDF itself is
  // identical across versions; only credential resolution diverged. So for
  // legacy wallets we keep running the exact 0.15.1 pipeline below.

  /// Reconstruct a legacy (0.15.1-era) passkey wallet's [Seed],
  /// byte-identical to what the old build derived.
  ///
  /// Pipeline, step by step (each is load-bearing — do not "modernise"):
  ///  1. salt = label ?? 'Default' — the exact salt the 0.15.1 path fed
  ///     into the PRF extension. Same salt ⇒ same secure-storage cache
  ///     key ⇒ same PRF bytes.
  ///  2. PRF via [PasskeyPrfService.derivePrfSeed] — NOT the new SDK.
  ///     Its cache tiers (session → device secureStorage
  ///     'prf_seed_v1__…' → legacy synced storage → pinned OS ceremony
  ///     without silently changing the pinned credential) mean an updated device
  ///     resolves the seed from secure storage with ZERO ceremonies,
  ///     and a fresh device still pins to the correct credential.
  ///  3. entropy = first 16 of the 32 PRF bytes → 12-word BIP39
  ///     mnemonic → `Seed.mnemonic(passphrase: null)` — the identical
  ///     0.15.1 KDF tail (see [seedFromPrfBytes]).
  ///
  /// Throws on any failure (cancelled ceremony, PRF unavailable). Callers
  /// MUST propagate — falling through to a new-SDK derivation here would
  /// silently connect the user to a different (empty) wallet.
  static Future<Seed> getLegacySeed({String? label}) async {
    final generation = _session.generation;
    final salt = label ?? 'Default';
    final prfBytes = await PasskeyPrfService.derivePrfSeed(salt);
    _session.check(generation);
    final seed = await seedFromPrfBytes(prfBytes);
    _session.check(generation);
    return seed;
  }

  /// KDF tail of [getLegacySeed], split out so the byte-exact
  /// 0.15.1 entropy selection is testable separately from the platform
  /// channel behind [PasskeyPrfService.derivePrfSeed]. BIP39 conversion
  /// runs on the native primitives executor.
  ///
  /// 32 PRF bytes → first 16 bytes as entropy → BIP39 mnemonic →
  /// `Seed.mnemonic(mnemonic, passphrase: null)`. Truncating to 16
  /// bytes (a 12-word phrase) and the null passphrase are both part of
  /// the historical contract — changing either derives a different
  /// wallet.
  @visibleForTesting
  static Future<Seed> seedFromPrfBytes(Uint8List prfBytes) async {
    if (prfBytes.length < 16) {
      throw ArgumentError(
          'PRF output too short: ${prfBytes.length} bytes (need ≥ 16)');
    }
    final entropy = Uint8List.fromList(prfBytes.sublist(0, 16));
    final mnemonic =
        await NativeBitcoinPrimitives.instance.mnemonicFromEntropy(entropy);
    return Seed.mnemonic(mnemonic: mnemonic, passphrase: null);
  }

  /// Legacy seed derivation for RECOVERY PROBES: same byte-exact pipeline
  /// as [getLegacySeed], plus provenance. The provenance flags let the
  /// prober discard a fresh unpinned derive whose wallet probes as an
  /// empty phantom, un-poisoning the cache and pin.
  static Future<({Seed seed, bool fromCeremony, bool unpinned})>
      deriveLegacySeedForProbe(String label) async {
    final generation = _session.generation;
    final res = await PasskeyPrfService.derivePrfSeedTracked(label);
    _session.check(generation);
    final seed = await seedFromPrfBytes(res.seed);
    _session.check(generation);
    return (
      seed: seed,
      fromCeremony: res.fromCeremony,
      unpinned: res.unpinned,
    );
  }

  // ───────────────────────── wallet seed routing ────────────────────────────

  /// The seed of the passkey wallet whose record carries [passkeyLabel]
  /// and [provider] (`WalletConfig.passkeyProvider`), routed on the
  /// marker. The ONE resolver every seed-resolution site uses:
  ///  * `null` (legacy): [getLegacySeed], with the label resolved as the
  ///    0.15.1 build did (stored label, then the cached label);
  ///  * `'breez-0.17'`: [getWallet] on the Breez home, same label rule;
  ///  * `'kute-1'`: [PasskeyHomeService.getWallet] on Kute's home. Such a
  ///    wallet always carries its label; none is guessed.
  /// An unknown marker throws [UnknownPasskeyProvider] before any storage
  /// read or ceremony.
  static Future<Seed> seedFor({
    required String? passkeyLabel,
    required String? provider,
  }) async {
    final route = PasskeyHomes.routeFor(provider);
    if (route == PasskeyRoute.kute) {
      return (await kute.getWallet(label: _kuteLabel(passkeyLabel))).seed;
    }
    final label = passkeyLabel ?? await getCachedLabel();
    if (route == PasskeyRoute.legacy) return getLegacySeed(label: label);
    return (await getWallet(label: label, legacy: false)).seed;
  }

  /// A Kute-home wallet's label. Every such wallet is created or restored
  /// with one, so a missing label is a broken record, never a reason to
  /// fall back to the device-wide cached label (a Breez/legacy value).
  static String _kuteLabel(String? label) {
    if (label == null || label.isEmpty) {
      throw StateError('A Kute passkey wallet must carry its label.');
    }
    return label;
  }

  // ───────────────────────── typed error routing ────────────────────────────

  /// The user dismissed the OS passkey ceremony: the SDK's typed verdict
  /// (`PasskeyError.prf(PrfProviderError.userCancelled())`) or the legacy
  /// channel's `USER_CANCELLED` platform code. Never a string match: an
  /// error whose text happens to mention a cancel (a cancelled network
  /// request, a wrapped re-throw) is a failure, and a failure read as a
  /// cancel is swallowed silently.
  static bool isUserCancelledError(Object e) {
    if (e is PasskeyError_Prf && e.field0 is PrfProviderError_UserCancelled) {
      return true;
    }
    return e is PlatformException && e.code == 'USER_CANCELLED';
  }

  /// No credential resolved for the ceremony — the ONLY signal that may
  /// route a create flow to `register()`. Every other failure (timeout,
  /// collision, auth failure) must surface instead of minting: a second
  /// credential on the shared RP forks the Nostr label identity and hides
  /// every wallet created under the first one.
  static bool isCredentialNotFoundError(Object e) {
    return e is PasskeyError_Prf &&
        e.field0 is PrfProviderError_CredentialNotFound;
  }

  /// The platform refused a ceremony because this app is not associated
  /// with the RP (its `webcredentials` / Digital Asset Links are missing
  /// or not verified yet), BEFORE any credential was created. The only
  /// signal that lets new-wallet creation fall back from Kute's home to
  /// Breez's.
  ///
  /// Only `PasskeyError.prf(…)` qualifies: that is the SDK's shape for a
  /// ceremony that failed outright (the create step of `register()`, or
  /// a `signIn` assertion). `PasskeyError.createdButNotDerived` (a
  /// credential exists) never does. Inside it:
  ///  * `PrfProviderError.configuration` — the providers' typed "RP not
  ///    configured for this app" (iOS: Associated Domains entitlement).
  ///  * iOS: `ASAuthorizationError.failed` carrying the OS text
  ///    "Application with identifier … is not associated with domain …",
  ///    which the SDK plugin passes through as a generic error.
  ///  * Android: Credential Manager's Digital Asset Links failure ("The
  ///    incoming request cannot be validated"), passed through as a
  ///    generic / authentication error, or the plugin's own rewrite of
  ///    it ("Domain verification failed …").
  /// Cancels, timeouts, missing credentials, PRF gaps and every other
  /// failure are not this.
  static bool isRpNotAssociatedError(Object e) {
    if (e is! PasskeyError_Prf) return false;
    final source = e.field0;
    if (source is PrfProviderError_Configuration) return true;
    final String text;
    if (source is PrfProviderError_Generic) {
      text = source.field0;
    } else if (source is PrfProviderError_AuthenticationFailed) {
      text = source.field0;
    } else {
      return false;
    }
    return _rpNotAssociatedTexts.any(text.contains);
  }

  /// The fixed platform texts of an RP-association refusal (see
  /// [isRpNotAssociatedError]).
  static const List<String> _rpNotAssociatedTexts = [
    'is not associated with domain', // iOS AuthenticationServices
    'cannot be validated', // Android Credential Manager (DAL)
    'Domain verification failed', // the SDK Android plugin's rewrite
  ];

  /// The password manager that answered the ceremony cannot produce the
  /// WebAuthn PRF output Kute derives every passkey wallet from: it made
  /// (or found) a passkey but returned no PRF key for it. Microsoft
  /// Authenticator and some other third-party credential providers do
  /// this. No retry against the same manager can succeed, and nothing
  /// can be derived, so callers stop before saving anything and show the
  /// "this password manager can't hold your Kute wallet" sheet.
  ///
  /// The shapes, by layer (breez SDK v0.26.1):
  ///  * `register()`: the create ceremony succeeds without PRF outputs,
  ///    the pinned assertion that follows returns none, and the SDK
  ///    reports `PasskeyError.createdButNotDerived(source: …)`.
  ///  * `signIn()`: `PasskeyError.prf(…)` with the same sources.
  ///  * Source `prfNotSupported`: iOS answers with no `prf` output, or an
  ///    `invalidResponse` (`ERR_PRF_NOT_SUPPORTED`); Android answers with
  ///    no `clientExtensionResults.prf`.
  ///  * Source `prfEvaluationFailed`, kept for any platform that maps it.
  ///  * Android's `prf` with no `results` reaches Dart as a generic error
  ///    carrying the plugin's fixed text ([_androidPrfEvaluationFailed]),
  ///    because the plugin maps that kind to `ERR_PASSKEY`.
  ///  * The legacy (pre-2.x) channel: `PRF_UNAVAILABLE` with the native
  ///    "did not return PRF output" message (the same code also means "OS
  ///    too old" / "no plugin", which are not about the manager).
  ///
  /// A cancel, a timeout or a missing credential is never this.
  static bool isPrfUnsupportedError(Object e) {
    PrfProviderError? source;
    if (e is PasskeyError_Prf) source = e.field0;
    if (e is PasskeyError_CreatedButNotDerived) source = e.source;
    if (source != null) {
      return source is PrfProviderError_PrfNotSupported ||
          source is PrfProviderError_PrfEvaluationFailed ||
          (source is PrfProviderError_Generic &&
              source.field0.contains(_androidPrfEvaluationFailed));
    }
    return e is PlatformException &&
        e.code == 'PRF_UNAVAILABLE' &&
        (e.message ?? '').contains(_legacyNoPrfOutput);
  }

  /// Fixed text of the SDK Android plugin's `PrfEvaluationFailed` kind
  /// (BreezSdkSparkPasskeyPlugin.kt), the only part of that error that
  /// survives the `ERR_PASSKEY` mapping.
  static const String _androidPrfEvaluationFailed = 'PRF evaluation failed';

  /// Fixed text of the app's own legacy channel when the credential
  /// returned no PRF output (PasskeyPrfPlugin.swift, MainActivity.kt).
  static const String _legacyNoPrfOutput = 'did not return PRF output';

  /// Extract a BIP39 mnemonic from a [Seed] (entropy seeds convert via
  /// BDK). Returns null for entropy lengths BIP39 can't represent.
  static Future<String?> mnemonicOfSeed(Seed seed) async {
    switch (seed) {
      case Seed_Mnemonic(:final mnemonic):
        return mnemonic;
      case Seed_Entropy(:final field0):
        try {
          return await NativeBitcoinPrimitives.instance
              .mnemonicFromEntropy(field0);
        } catch (_) {
          return null;
        }
    }
  }

  /// Derive a Breez-home wallet from an EXISTING passkey (breez `signIn()`).
  ///
  /// VINTAGE GATE — [legacy] is required precisely so the compiler forces
  /// every call site to route on the wallet's `passkeyProvider`:
  /// `legacy: true` throws immediately, pointing at [getLegacySeed]. A
  /// legacy (pre-2.x) wallet run through the new SDK's `signIn` can
  /// resolve a different credential on the shared RP and derive a
  /// different, fund-losing seed — this surface must never serve it.
  /// Kute-home wallets go through [kute] ([seedFor] routes them).
  ///
  /// See [PasskeyHomeService.getWallet] for the resolution, pinning and
  /// [preferImmediatelyAvailable] semantics.
  static Future<Wallet> getWallet({
    String? label,
    required bool legacy,
    Uint8List? credentialId,
    bool? preferImmediatelyAvailable,
  }) async {
    if (legacy) {
      throw ArgumentError(
        'getWallet() serves only breez-0.17 passkey wallets. Legacy '
        '(passkeyProvider == null) wallets must derive via '
        'PasskeyService.getLegacySeed — the new SDK signIn can resolve a '
        'different credential and a different, fund-losing seed.',
      );
    }
    return breez.getWallet(
      label: label,
      credentialId: credentialId,
      preferImmediatelyAvailable: preferImmediatelyAvailable,
    );
  }

  /// Delete the retired iCloud recovery manifest once per install.
  ///
  /// Best-effort: it held only non-secret labels and vintage tags, so a
  /// failed delete is retried on the next start and costs nothing. This
  /// deletes that ONE synced key and nothing else — synced seed and PRF
  /// twins are never purged.
  static Future<void> retireRecoveryManifest() async {
    try {
      final box = await Hive.openBox('settings');
      if (box.get(_manifestRetiredFlag) == true) return;
      await SecretStores.synced.delete(key: _retiredManifestKey);
      await box.put(_manifestRetiredFlag, true);
    } catch (_) {/* best-effort: retried on the next start */}
  }

  /// Recovery discovery on the Breez home ([PasskeyHomeService.discoverWallets]).
  static Future<PasskeyDiscovery> discoverWallets() => breez.discoverWallets();

  /// Whether this device has learned any Breez-RP passkey credential: the
  /// current stack's pin or the legacy (pre-2.x) pin / registered flag.
  /// The create flow uses it to tell "no passkey on this device" (a
  /// dismissed sign-in sheet may be offered a fresh passkey) from "a known
  /// passkey exists" (never mint a second one). Storage failures read as
  /// "known", the conservative answer.
  static Future<bool> hasKnownCredential() => breez.hasKnownCredential();

  // ───────────────────────── label publishing ──────────────────────────
  //
  // Publishing a wallet's label to the Nostr label store is what makes the
  // wallet show up in the recover picker on another device. It is the only
  // network step around creation, so it never sits on the creation path:
  // the wallet is saved first, the label is published in the background
  // with a per-attempt timeout, and a label that did not land stays
  // "pending" on this device until a later ceremony lets it be retried.
  // A warm device reads its seeds from the local cache and runs no
  // ceremony, so the wallet's backup reminder stays up meanwhile and its
  // action ([finishLabelBackup]) runs the one ceremony that publishes.
  //
  // Every home keeps its own pending set and label identity: a label is
  // only ever published by the identity of the passkey that derived it.

  /// Per-attempt cap on a label publish. The SDK's own relay timeout is
  /// 30 s per relay batch, so one attempt could otherwise run for minutes
  /// on a dead link; this keeps every attempt short and lets the retry on
  /// a later ceremony finish the job.
  static Duration labelPublishAttemptTimeout = const Duration(seconds: 20);

  /// Base backoff between publish attempts (×1, ×2, …).
  static Duration labelPublishBackoff = const Duration(milliseconds: 600);

  /// Breez-home labels this device created but has not yet confirmed as
  /// published ([PasskeyHomeService.pendingLabels]).
  static ValueListenable<Set<String>> get pendingLabels => breez.pendingLabels;

  /// [pendingLabels] as it stands, without hydrating it from storage.
  static Set<String> get pendingLabelsNow => breez.pendingLabelsNow;

  /// Both homes' pending labels, for the reminder and the "syncing your
  /// backup" note. Notifies when either home's set changes. On a device
  /// with no Kute-home wallet this is exactly the Breez set.
  static Listenable get allPendingLabels =>
      Listenable.merge([breez.pendingLabels, kute.pendingLabels]);

  /// The union of both homes' pending sets as they stand.
  static Set<String> get allPendingLabelsNow {
    final k = kute.pendingLabelsNow;
    if (k.isEmpty) return breez.pendingLabelsNow;
    return {...breez.pendingLabelsNow, ...k};
  }

  /// Load the Breez home's pending set from storage.
  static Future<void> loadPendingLabels() => breez.loadPendingLabels();

  /// [PasskeyHomeService.markLabelPending] on the Breez home.
  static Future<void> markLabelPending(String label, {String? credentialHex}) =>
      breez.markLabelPending(label, credentialHex: credentialHex);

  /// [PasskeyHomeService.markLabelPendingForIdentity] on the Breez home.
  static Future<void> markLabelPendingForIdentity(String label) =>
      breez.markLabelPendingForIdentity(label);

  /// Told once a Breez-home label's publish landed AND its pending flag
  /// was cleared. The settings model registers itself here to mark that
  /// wallet backed up. Kute's home has its own
  /// ([PasskeyHomeService.labelPublishedHandler] on [kute]).
  static Future<void> Function(String label)? get labelPublishedHandler =>
      breez.labelPublishedHandler;
  static set labelPublishedHandler(
          Future<void> Function(String label)? handler) =>
      breez.labelPublishedHandler = handler;

  /// [PasskeyHomeService.clearLabelPending] on the Breez home.
  static Future<void> clearLabelPending(String label) =>
      breez.clearLabelPending(label);

  static Future<bool> hasPendingLabel(String label) =>
      breez.hasPendingLabel(label);

  @visibleForTesting
  static void debugResetPendingLabels() {
    breez._debugResetPending();
    kute._debugResetPending();
  }

  /// [PasskeyHomeService.storeLabel] on the Breez home.
  static Future<bool> storeLabel(String label, {int attempts = 3}) =>
      breez.storeLabel(label, attempts: attempts);

  /// [PasskeyHomeService.publishLabelInBackground] on the Breez home.
  static Future<bool> publishLabelInBackground(String label,
          {required String trigger}) =>
      breez.publishLabelInBackground(label, trigger: trigger);

  /// [PasskeyHomeService.retryPendingLabels] on the Breez home.
  static Future<void> retryPendingLabels({bool verifyRelay = false}) =>
      breez.retryPendingLabels(verifyRelay: verifyRelay);

  /// [retryPendingLabels] in every home (app resume, unlock). A home whose
  /// identity no ceremony primed in this process does nothing.
  static Future<void> retryPendingLabelsAllHomes() async {
    await Future.wait([
      breez.retryPendingLabels(),
      kute.retryPendingLabels(),
    ]);
  }

  /// [PasskeyHomeService.finishLabelBackup] on the Breez home.
  static Future<PasskeyLabelBackupResult> finishLabelBackup(String label,
          {required String surface}) =>
      breez.finishLabelBackup(label, surface: surface);

  /// Build a fresh, unique label for a spending wallet. The trailing
  /// epoch-millis guarantees a DISTINCT PRF seed per wallet (same label
  /// ⇒ same seed ⇒ same wallet) and doubles as the creation date that
  /// [displayNameForLabel] renders in the recover picker.
  static String newSpendingWalletLabel([int? createdAtMs]) =>
      newWalletLabel(createdAtMs: createdAtMs);

  /// Build a fresh, unique label carrying a user-chosen [name] (defaults
  /// to 'Spending Wallet' when absent/blank). The ` · <epochMs>` suffix
  /// is load-bearing exactly as in [newSpendingWalletLabel]: it keeps
  /// every creation on a DISTINCT seed even when two wallets share a
  /// name, and encodes the creation date for the recover picker. The
  /// name is trimmed and any ` · ` separator inside it collapsed so the
  /// suffix stays unambiguous for [displayNameForLabel] /
  /// [creationDateForLabel] parsing.
  static String newWalletLabel({String? name, int? createdAtMs}) {
    final cleaned = (name ?? '').trim().replaceAll(' · ', ' ');
    final base = cleaned.isEmpty ? 'Spending Wallet' : cleaned;
    return '$base · ${createdAtMs ?? DateTime.now().millisecondsSinceEpoch}';
  }

  /// Display name for a passkey [label]: the label with its ` · <ms>`
  /// creation-date suffix stripped — the creation date is surfaced
  /// separately via [creationDateForLabel] (only to tell wallets apart
  /// in the recover picker), never baked into the name. The legacy
  /// 'Default' label renders as 'Spending Wallet'; labels with no
  /// numeric suffix (e.g. legacy `wallet-<id>`) fall through raw.
  static String displayNameForLabel(String label) {
    label = displayPasskeyLabel(label);
    if (label == 'Default') return 'Spending Wallet';
    const sep = ' · ';
    final idx = label.lastIndexOf(sep);
    if (idx > 0 && int.tryParse(label.substring(idx + sep.length)) != null) {
      return label.substring(0, idx);
    }
    return label;
  }

  /// The creation date encoded in a `<name> · <ms>` label, e.g.
  /// "Jun 18, 2026" — or '' when the label carries none. Used only to
  /// distinguish wallets in the recover picker, never as the name.
  static String creationDateForLabel(String label) {
    label = displayPasskeyLabel(label);
    const sep = ' · ';
    final idx = label.lastIndexOf(sep);
    if (idx > 0) {
      final ms = int.tryParse(label.substring(idx + sep.length));
      if (ms != null) return _formatWalletDate(ms);
    }
    return '';
  }

  static String _formatWalletDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Hive `settings` key of the device-wide cached label.
  static const String _cachedLabelKey = 'passkey_cached_label';

  /// Cache the active label locally for quick re-authentication.
  ///
  /// Refused (kept as is) while a passkey record with no stored label
  /// exists: that record derives its seed from this cached value, and
  /// overwriting it would connect that wallet to a different seed and
  /// reveal the wrong words. The startup backfill
  /// (`backfillLegacyPasskeyLabels`) pins such records to their label, so
  /// this only fires until that has run. The caller's own wallet carries
  /// its label on its record and never reads the cache.
  ///
  /// A Breez / legacy value: Kute-home flows never write or read it.
  static Future<void> cacheLabel(String label) async {
    final box = await Hive.openBox('settings');
    final existing = box.get(_cachedLabelKey) as String?;
    if (existing != null && existing != label && _anyUnlabelledPasskeyRecord(box)) {
      TrackingService.track('passkey_cached_label_kept');
      return;
    }
    await box.put(_cachedLabelKey, label);
  }

  /// Forget the device-local seed material of the Breez-home (or legacy)
  /// passkey wallet [label] ([PasskeyHomeService.forgetWallet]).
  static Future<void> forgetWallet(String label) => breez.forgetWallet(label);

  /// [forgetWallet] routed on the removed record's [provider]: a Kute-home
  /// wallet forgets only Kute-home entries, every other wallet (legacy and
  /// Breez) exactly what [forgetWallet] always did. An unknown marker
  /// forgets nothing (nothing can be tied to it) and throws.
  static Future<void> forgetWalletFor(String label, {required String? provider}) {
    final route = PasskeyHomes.routeFor(provider);
    return route == PasskeyRoute.kute
        ? kute.forgetWallet(label)
        : breez.forgetWallet(label);
  }

  /// Whether a stored wallet record carries [label].
  static bool _anyRecordWithLabel(Box<dynamic> box, String label) {
    final raw = box.get('wallets');
    if (raw is! List) return false;
    for (final w in raw) {
      if (w is Map && w['isPasskey'] == true && w['passkeyLabel'] == label) {
        return true;
      }
    }
    return false;
  }

  /// Whether a stored wallet record is a passkey wallet with no label.
  static bool _anyUnlabelledPasskeyRecord(Box<dynamic> box) {
    final raw = box.get('wallets');
    if (raw is! List) return false;
    for (final w in raw) {
      if (w is Map && w['isPasskey'] == true && w['passkeyLabel'] == null) {
        return true;
      }
    }
    return false;
  }

  /// Get the cached label (if any).
  static Future<String?> getCachedLabel() async {
    final box = await Hive.openBox('settings');
    return box.get(_cachedLabelKey) as String?;
  }

  /// Resolve a BIP39 mnemonic for the passkey wallet identified by
  /// [label]. VINTAGE-AWARE: [legacy] wallets (passkeyProvider == null)
  /// reconstruct through [getLegacySeed] — the app's own 0.15.1 PRF
  /// pipeline — NEVER through a new-SDK signIn, which could resolve a
  /// different credential and reveal the WRONG mnemonic (catastrophic on
  /// a backup surface: the user writes down words that don't control
  /// their funds). New (breez-0.17) wallets use [getWallet], the
  /// canonical derive-on-demand path, then convert the returned `Seed`
  /// to a BIP39 phrase. Both paths re-derive on demand (modulo
  /// [PasskeyPrfService]'s caches); callers accept the biometric prompt
  /// underneath. Kute-home wallets use [getMnemonicFor].
  ///
  /// Returns null when:
  ///   * the user cancels the biometric prompt or PRF derive throws,
  ///   * the seed entropy isn't BIP39-valid (16/20/24/28/32 bytes).
  ///
  /// [label] defaults to the cached label (set at wallet
  /// creation/restore via [cacheLabel]). Pass an explicit label when
  /// the user has more than one wallet under the same passkey and
  /// wants the mnemonic for a non-default one.
  static Future<String?> getMnemonic(
      {String? label, required bool legacy}) async {
    final generation = _session.generation;
    try {
      // Resolution order matches the Breez passkey guide AND the
      // 0.15.1 build (identical order, so legacy wallets resolve the
      // exact salt they were created with):
      //   1. explicit `label` (caller knew which wallet they wanted)
      //   2. locally cached label (set at create/restore time)
      //   3. "Default" — the label every freshly-created passkey
      //      wallet uses, per `passkey_choice.dart`. Falling back to
      //      this catches wallets whose Hive cache was wiped (e.g.
      //      cross-version migration) where the passkey itself is
      //      still valid in iCloud Keychain.
      final resolvedLabel =
          label ?? await getCachedLabel() ?? 'Default';
      _session.check(generation);
      final Seed seed;
      if (legacy) {
        // getLegacySeed applies the final 'Default' fallback itself,
        // but pass the fully resolved label so the cached-label tier
        // participates — replicating 0.15.1 resolution exactly.
        seed = await getLegacySeed(label: resolvedLabel);
      } else {
        final wallet = await getWallet(label: resolvedLabel, legacy: false);
        seed = wallet.seed;
      }
      _session.check(generation);
      final mnemonic = await mnemonicOfSeed(seed);
      _session.check(generation);
      return mnemonic;
    } catch (_) {
      return null;
    }
  }

  /// [getMnemonic] routed on the wallet's [provider] marker: legacy and
  /// Breez-home wallets run [getMnemonic] exactly as before; a Kute-home
  /// wallet derives on Kute's home from its own [label] only. Null when
  /// no phrase can be produced, an unknown marker included.
  static Future<String?> getMnemonicFor(
      {required String? label, required String? provider}) async {
    final PasskeyRoute route;
    try {
      route = PasskeyHomes.routeFor(provider);
    } catch (_) {
      return null;
    }
    if (route != PasskeyRoute.kute) {
      return getMnemonic(label: label, legacy: route == PasskeyRoute.legacy);
    }
    final generation = _session.generation;
    try {
      final wallet = await kute.getWallet(label: _kuteLabel(label));
      _session.check(generation);
      final mnemonic = await mnemonicOfSeed(wallet.seed);
      _session.check(generation);
      return mnemonic;
    } catch (_) {
      return null;
    }
  }
}

/// One passkey home's SDK client and every piece of state bound to its RP:
/// the label-store identity, the pinned credential id, the device-local
/// seed cache, the discovery sign-in and the pending labels. Two instances
/// exist ([PasskeyService.breez], [PasskeyService.kute]); nothing here is
/// shared between them except the wipe generation ([PasskeySession]).
///
/// The Breez instance keeps every storage key it has always used
/// (`passkey017_credential_id`, `passkey017_seed_v1__…`, the Hive
/// `passkey_pending_labels`) and builds the exact clients it always built;
/// the Kute instance uses its own `passkey_kute1_*` keys and an RP of
/// `kutewallet.com` (rpName "Kute").
class PasskeyHomeService {
  PasskeyHomeService._(this.home)
      : _credentialIdKey = switch (home) {
          PasskeyHome.breez => 'passkey017_credential_id',
          PasskeyHome.kute => 'passkey_kute1_credential_id',
        },
        _seedCacheKeyPrefix = switch (home) {
          PasskeyHome.breez => 'passkey017_seed_v1__',
          PasskeyHome.kute => 'passkey_kute1_seed_v1__',
        },
        _pendingLabelsKey = switch (home) {
          PasskeyHome.breez => 'passkey_pending_labels',
          PasskeyHome.kute => 'passkey_kute1_pending_labels',
        };

  /// The RP this service derives on.
  final PasskeyHome home;

  bool get _isBreez => home == PasskeyHome.breez;

  PasskeySession get _session => PasskeyService._session;

  PasskeyClient? _client;

  /// Secure-storage key for the credential id the [PasskeyClient] last
  /// resolved against on THIS device, for this home. Stored so [getWallet]
  /// can pin every subsequent `signIn` to that exact credential via
  /// `SignInRequest.allowCredentials`. Without the pin the OS free-picks
  /// among every credential on the RP — and on the shared Breez RP all
  /// Kute credentials carry the same user name ('kute-wallet-user'), so a
  /// free pick can silently resolve a DIFFERENT passkey and derive a
  /// different, fund-losing seed. Kept separate from the legacy
  /// `prf_credential_id_v1__*` slot ([PasskeyPrfService]) and from the
  /// other home's slot because no two stacks may ever share pins.
  final String _credentialIdKey;

  /// Storage-key prefix of this home's device-local seed cache.
  final String _seedCacheKeyPrefix;

  /// Hive `settings` key holding `{label: credentialHex}` for this home's
  /// labels whose publish has not been confirmed yet. `credentialHex` is
  /// '' when the platform did not surface the credential.
  final String _pendingLabelsKey;

  /// The SDK config this home's clients are built with: none at all for
  /// the Breez home's cached client (the SDK's zero-config Breez RP),
  /// display names only for its register client; Kute's RP id and name
  /// on every Kute-home client.
  @visibleForTesting
  PasskeyConfig? clientConfig({String? userDisplayName}) {
    final name = (userDisplayName == null || userDisplayName.trim().isEmpty)
        ? null
        : userDisplayName.trim();
    switch (home) {
      case PasskeyHome.breez:
        if (name == null) return null;
        return PasskeyConfig(
          providerOptions: PasskeyProviderOptions(
            userName: name,
            userDisplayName: name,
          ),
        );
      case PasskeyHome.kute:
        return PasskeyConfig(
          providerOptions: PasskeyProviderOptions(
            rpId: PasskeyHomes.kuteRpId,
            rpName: PasskeyHomes.kuteRpName,
            userName: name,
            userDisplayName: name,
          ),
        );
    }
  }

  PasskeyClient _newClient(PasskeyConfig? config) {
    final factory = PasskeyService.debugClientFactory;
    if (factory != null) return factory(home, config);
    return config == null
        ? PasskeyClient(breezApiKey: dotenv.env['BREEZ_API_KEY'])
        : PasskeyClient(breezApiKey: dotenv.env['BREEZ_API_KEY'], config: config);
  }

  /// Get or create this home's [PasskeyClient]. For the Breez home the
  /// default constructor wires the built-in native [PasskeyProvider]
  /// (channel `breez_sdk_spark_passkey`, shipped by the SDK) on the
  /// shared Breez RP, so all we supply is the relay key for authenticated
  /// label storage. The Kute home passes its own RP.
  PasskeyClient _getClient() {
    _client ??= _newClient(clientConfig());
    return _client!;
  }

  /// Breez-home passkeys never run on the web: Breez's RP does not list
  /// Kute's website, so a ceremony there can only fail (or, worse, reach
  /// some other app's credential). Native builds are untouched.
  void _assertCeremonyAllowed() {
    if (kIsWeb && _isBreez) {
      throw UnsupportedError(
          'Breez-home passkey wallets cannot be used on the web.');
    }
  }

  // ─────────────────── seed cache + ceremony coalescing ──────────────────
  //
  // Unlike PasskeyPrfService (legacy), the SDK's PasskeyClient runs a FULL OS
  // ceremony on EVERY signIn and caches nothing. getWallet is called on every
  // passkey mnemonic need — connect, resolveBip39MnemonicFor (Polymarket
  // relayer/provisioning, EOA derivation), the affiliate path — so on boot
  // several fire at once, each launching its own ceremony: iOS rejects the
  // overlap ("Request already in progress") and the user sees a fresh Face ID
  // each time. We mirror the exact tiers PasskeyPrfService already proves:
  //   • _walletInFlight — coalesce concurrent callers onto ONE ceremony.
  //   • _walletSession  — in-memory, so later same-session calls never touch
  //     the OS or storage.
  //   • device-local secureStorage (<prefix>…) — persists the derived seed
  //     so a warm device skips the ceremony on cold start too.
  //     Keyed by (label, credential id); by the label alone when the
  //     platform surfaced no credential id and the device holds no pin, so
  //     a restore on such a device still spares the next cold start.
  // The persisted seed sits in the SAME this-device-only tier as the legacy
  // PRF seed and the app's BIP39 seeds; the passkey stays the recovery root.
  final Map<String, Wallet> _walletSession = {};
  final Map<String, Future<Wallet>> _walletInFlight = {};

  /// The cache key's credential part when none is known (see above).
  static final Uint8List _noCredential = Uint8List(0);

  /// The discovery sign-in in flight, so a double tap (or the auto lookup
  /// racing a tap) shares ONE ceremony.
  Future<PasskeyDiscovery>? _discoveryInFlight;

  /// The wallet the last discovery derived for the SDK's default label,
  /// with the credential that derived it. Held in memory only, so a
  /// restore of that same label on that same credential needs no second
  /// ceremony. Consumed by [_resolveWallet].
  ({String label, String credentialHex, Wallet wallet})? _discovered;

  /// The client whose label-store identity was primed most recently by a
  /// ceremony other than one on [_client] (the display-name register
  /// client). [storeLabel] uses it so publishing costs no extra prompt.
  PasskeyClient? _labelClient;

  /// Hex of the credential whose label-store identity the SDK client
  /// currently holds, i.e. the credential of the last `signIn` /
  /// `register` ceremony that ran in THIS process. `labels().store` needs
  /// that identity; without a ceremony the SDK would derive it with a
  /// fresh PRF assertion (a surprise biometric prompt), so the pending
  /// label retry only runs when this is set, and only for labels that
  /// belong to this credential.
  String? _identityCredentialHex;

  void _clearMemory() {
    _walletSession.clear();
    _walletInFlight.clear();
    _discoveryInFlight = null;
    _discovered = null;
    _labelClient = null;
    _identityCredentialHex = null;
    _publishing.clear();
    _labelBackupInFlight = null;
  }

  /// Check if passkey PRF is supported (and the app is RP-associated) on
  /// this device for this home. False on the web for the Breez home.
  Future<bool> isAvailable() async {
    try {
      _assertCeremonyAllowed();
      final availability = await _getClient().checkAvailability();
      return availability is PasskeyAvailability_Available;
    } catch (_) {
      return false;
    }
  }

  /// Whether the platform states, BEFORE any ceremony, that this app is
  /// not associated with this home's RP (the AASA / Digital Asset Links
  /// probe of the SDK's [PasskeyProvider]). Only iOS can answer
  /// "not associated": Android's plugin always soft-fails to "skipped",
  /// and a skipped, failed or unreachable probe reads as "no verdict"
  /// (false) so the ceremony itself decides. Always false on the web,
  /// where the page's host decides ([PasskeyHomes.webPageOnKuteHome]).
  Future<bool> platformReportsNotAssociated() async {
    if (kIsWeb) return false;
    try {
      final probe = PasskeyService.debugDomainAssociation;
      final DomainAssociation verdict;
      if (probe != null) {
        verdict = await probe(home);
      } else {
        final options =
            clientConfig()?.providerOptions ?? const PasskeyProviderOptions();
        verdict = await PasskeyProvider(options).checkDomainAssociation();
      }
      return verdict is DomainAssociationNotAssociated;
    } catch (_) {
      return false;
    }
  }

  /// MINT a new passkey credential on this home's RP and derive the wallet
  /// for [label]. First-time wallet creation only — runs the OS "create
  /// passkey" ceremony. (breez `register()`.) Returns the derived [Wallet].
  ///
  /// Persists the freshly minted credential id so the very first
  /// `signIn` after creation is already pinned to THIS credential —
  /// closing the window where an un-pinned assertion could resolve a
  /// sibling credential on the RP.
  /// [userDisplayName] (when provided) becomes the WebAuthn `user.name` /
  /// `user.displayName` on the minted credential — the string the OS
  /// passkey sheet and iCloud Keychain / Google Password Manager list
  /// show — so the entry carries the user's own wallet label instead of
  /// the provider default. Cosmetic only: credential resolution stays
  /// pinned by credential id (never by name), and the seed derives from
  /// (PRF, label) exactly as before.
  Future<Wallet> createWallet({
    required String label,
    String? userDisplayName,
  }) async {
    _assertCeremonyAllowed();
    final generation = _session.generation;
    // Tell the platform about every credential this device already knows
    // on THIS RP (the home's pin, and on the Breez RP also the legacy pin)
    // so a duplicate mint fails cleanly with `credentialAlreadyExists`
    // instead of creating a sibling credential — a second credential forks
    // the Nostr label identity (old wallets vanish from recovery), and on
    // iOS a second same-name registration can REPLACE the first in iCloud
    // Keychain, permanently stranding wallets derived under it. This only
    // protects ids the device has learned; the caller-side signIn-first
    // flow is still the primary guard. The legacy pin is a Breez-RP
    // credential and means nothing to Kute's RP.
    final exclude = <Uint8List>[];
    final storedId = await _loadCredentialId();
    _session.check(generation);
    if (storedId != null && storedId.isNotEmpty) {
      exclude.add(storedId);
    }
    if (_isBreez) {
      final legacyId = await PasskeyPrfService.pinnedCredentialId();
      _session.check(generation);
      if (legacyId != null && legacyId.isNotEmpty) exclude.add(legacyId);
    }
    // One-off client for the register ceremony ONLY, so the mint carries
    // the user's display name. The cached `_client` (default names) keeps
    // serving signIn / labels — assertions ignore the cosmetic names, so
    // the split changes nothing for existing flows.
    final registerClient = (userDisplayName == null ||
            userDisplayName.trim().isEmpty)
        ? _getClient()
        : _newClient(clientConfig(userDisplayName: userDisplayName));
    final resp = await registerClient.register(
      request: RegisterRequest(
        label: label,
        excludeCredentials: exclude.isEmpty ? null : exclude,
      ),
    );
    _session.check(generation);
    final credId = resp.credential?.credentialId;
    await _saveCredentialId(credId, generation);
    _session.check(generation);
    // register() derived this credential's label-store identity on
    // `registerClient` (and already publishes the label in the background:
    // the SDK spawns its own 3-attempt store_label, whose outcome it never
    // reports). Route the caller's follow-up storeLabel through that same
    // client so it reuses the identity instead of costing a second OS
    // prompt, and remember whose identity it is for the pending retry.
    _labelClient = registerClient;
    _identityCredentialHex =
        (credId != null && credId.isNotEmpty) ? _hexOf(credId) : null;
    unawaited(retryPendingLabels(verifyRelay: true));
    // Prime the caches with the freshly minted seed so the very first
    // getWallet after creation (connect / provisioning) reuses it instead of
    // launching a second, redundant ceremony.
    _session.check(generation);
    _walletSession[label] = resp.wallet;
    if (credId != null && credId.isNotEmpty) {
      await _writeCachedWallet(label, credId, resp.wallet, generation);
    }
    _session.check(generation);
    return resp.wallet;
  }

  /// Derive a wallet from an EXISTING passkey on this home (breez
  /// `signIn()`). On the Breez home use [PasskeyService.getWallet], whose
  /// vintage gate keeps legacy wallets out.
  ///
  /// Returns a [Wallet] containing a [Seed] that can be passed directly to
  /// Breez SDK's `ConnectRequest`. The same label always produces the same
  /// wallet (deterministic derivation via PRF). Throws cleanly when no passkey
  /// resolves — callers in the create flow catch that and fall through to
  /// [createWallet]. We use `signIn` (not `connectWithPasskey`) precisely so a
  /// missing/unsynced credential FAILS rather than silently minting a new
  /// passkey (which would derive a different seed and lock the user out).
  ///
  /// Credential PINNING: the id stored at create/last-signIn is passed as
  /// `SignInRequest.allowCredentials` so the OS asserts against the SAME
  /// credential every time — vital because every Kute credential on the
  /// shared RP is named 'kute-wallet-user'. A failed pinned ceremony must
  /// preserve the pin and surface the error. Selecting another credential
  /// is explicit recovery, never a silent retry for an existing wallet.
  ///
  /// [credentialId] is the credential a recovery discovery
  /// ([discoverWallets]) resolved. On a device with no stored pin it pins
  /// this ceremony to that credential (Breez: re-authentication must use
  /// the credential that owns the wallet), and is persisted once the
  /// ceremony succeeds. It must match the stored pin when one exists.
  ///
  /// [preferImmediatelyAvailable] is forwarded to the OS as
  /// `preferImmediatelyAvailableCredentials` (Android Credential Manager's
  /// `setPreferImmediatelyAvailableCredentials`, iOS's
  /// `.preferImmediatelyAvailableCredentials`): with it a device holding
  /// no local passkey fails fast with `CredentialNotFound` instead of
  /// showing a sign-in sheet (the cross-device / QR option included).
  /// The SDK's native providers already default to `true` when this is
  /// null; the create flow passes it explicitly so the fast fail does not
  /// depend on that default. Null keeps the SDK default.
  ///
  /// [label] defaults to "Default" (discovery) if null.
  Future<Wallet> getWallet({
    String? label,
    Uint8List? credentialId,
    bool? preferImmediatelyAvailable,
  }) async {
    _assertCeremonyAllowed();
    final generation = _session.generation;
    final key = label ?? '';
    // Fast path: already derived this session — no OS, no storage.
    final session = _walletSession[key];
    if (session != null) return session;
    // Coalesce concurrent callers (connect + relayer + affiliate on boot)
    // onto a SINGLE ceremony so they can't fight for the OS authorization.
    final pending = _walletInFlight[key];
    if (pending != null) return pending;
    final future = _resolveWallet(
        label, generation, credentialId, preferImmediatelyAvailable);
    _walletInFlight[key] = future;
    try {
      final wallet = await future;
      _session.check(generation);
      _walletSession[key] = wallet;
      return wallet;
    } finally {
      if (identical(_walletInFlight[key], future)) _walletInFlight.remove(key);
    }
  }

  /// The actual resolve: device-local cache → discovery reuse → pinned
  /// signIn → persist. Kept private so [getWallet] owns the session cache +
  /// in-flight coalescing around it.
  Future<Wallet> _resolveWallet(String? label, int generation,
      Uint8List? discoveredId, bool? preferImmediatelyAvailable) async {
    final storedId = await _loadCredentialId();
    _session.check(generation);
    final hasStored = storedId != null && storedId.isNotEmpty;
    final hasDiscovered = discoveredId != null && discoveredId.isNotEmpty;
    if (hasStored && hasDiscovered &&
        _hexOf(discoveredId) != _hexOf(storedId)) {
      throw StateError('Passkey credential changed. Recover the original wallet.');
    }
    final pin = hasStored ? storedId : (hasDiscovered ? discoveredId : null);
    // Device-local cache — a warm device skips the ceremony entirely. Keyed
    // by (label, credentialId): a different wallet has a different label, and
    // a rotated credential changes the key, so a stale entry can NEVER be
    // served for the wrong wallet. With no pin on this device the entry a
    // credential-less restore wrote sits under the label alone.
    final cached = await _readCachedWallet(label, pin ?? _noCredential);
    _session.check(generation);
    if (cached != null) return cached;
    final Wallet wallet;
    final Uint8List? credId;
    final discovered = _discovered;
    if (discovered != null && pin != null && label != null &&
        discovered.label == label &&
        discovered.credentialHex == _hexOf(pin)) {
      // The discovery ceremony already derived this exact label on this
      // exact credential: reuse it rather than prompting again.
      _discovered = null;
      wallet = discovered.wallet;
      credId = pin;
    } else {
      final resp = await _getClient().signIn(
        request: SignInRequest(
          label: label,
          allowCredentials: pin != null ? [pin] : null,
          preferImmediatelyAvailableCredentials: preferImmediatelyAvailable,
        ),
      );
      _session.check(generation);
      if (pin != null && resp.credential != null &&
          _hexOf(resp.credential!.credentialId) != _hexOf(pin)) {
        throw StateError('Passkey credential changed. Recover the original wallet.');
      }
      // `_client` now holds this credential's label-store identity.
      _labelClient = null;
      wallet = resp.wallet;
      // A platform that surfaces no credential id answered the pinned
      // ceremony, so the pin IS the credential: keep it as the resolved id
      // (a discovered pin gets persisted now, as the comment below says).
      credId = resp.credential?.credentialId ?? pin;
      _identityCredentialHex =
          (credId != null && credId.isNotEmpty) ? _hexOf(credId) : null;
      // A ceremony just primed the identity: labels still waiting to be
      // published (a creation on a slow link) can go out now, for free,
      // and every local label is checked against the relay list.
      unawaited(retryPendingLabels(verifyRelay: true));
    }
    // Reconcile: keep the stored id tracking what the OS actually
    // resolved against so the NEXT ceremony pins correctly.
    _session.check(generation);
    await _saveCredentialId(credId, generation);
    _session.check(generation);
    // Persist the derived seed device-local, keyed by (label, resolved
    // cred), or by the label alone when no credential id is known: the next
    // cold start would otherwise run an OS ceremony again.
    await _writeCachedWallet(
        label,
        (credId != null && credId.isNotEmpty) ? credId : _noCredential,
        wallet,
        generation);
    _session.check(generation);
    return wallet;
  }

  /// The storage key of this home's cached seed for (label, credential).
  @visibleForTesting
  String seedCacheKey(String? label, Uint8List credId) {
    final digest =
        sha256.convert(utf8.encode('${label ?? ''}|${_hexOf(credId)}'));
    return '$_seedCacheKeyPrefix$digest';
  }

  /// The storage key of this home's pinned credential id.
  @visibleForTesting
  String get credentialIdKey => _credentialIdKey;

  /// The Hive key of this home's pending labels.
  @visibleForTesting
  String get pendingLabelsKey => _pendingLabelsKey;

  Future<Wallet?> _readCachedWallet(String? label, Uint8List credId) async {
    final raw =
        (await SecretStores.local.read(key: seedCacheKey(label, credId)))
            .valueOrThrow();
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final seed = _decodeSeed(map['seed'] as String?);
    if (seed == null || (map['label'] != null && map['label'] != label)) {
      throw StateError('Stored passkey wallet is unreadable. Restore the wallet.');
    }
    return Wallet(seed: seed, label: (map['label'] as String?) ?? label ?? '');
  }

  Future<void> _writeCachedWallet(
      String? label, Uint8List credId, Wallet wallet, int generation) async {
    try {
      await _session.write(generation, () => SecretStores.local.writeLocalOnly(
        key: seedCacheKey(label, credId),
        value: jsonEncode({'label': wallet.label, 'seed': _encodeSeed(wallet.seed)}),
      ));
    } catch (e) {
      // Non-fatal: the session cache still covers this run, but the next
      // cold start will prompt again. Say so, by kind only: no label, no
      // credential, no error text.
      TrackingService.track('passkey_seed_cache_write_failed', params: {
        'error_category': TrackingService.errorReason(e),
        'keyed_by': credId.isEmpty ? 'label' : 'credential',
        if (!_isBreez) 'passkey_home': home.analyticsValue,
      });
    }
  }

  /// Serialize a [Seed] for device-local storage. The union is closed
  /// (mnemonic | entropy) so this is total.
  static String _encodeSeed(Seed s) => switch (s) {
        Seed_Mnemonic(:final mnemonic, :final passphrase) =>
          jsonEncode({'t': 'm', 'm': mnemonic, 'p': passphrase}),
        Seed_Entropy(:final field0) =>
          jsonEncode({'t': 'e', 'h': _hexOf(field0)}),
      };

  static Seed? _decodeSeed(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      switch (m['t']) {
        case 'm':
          return Seed.mnemonic(
              mnemonic: m['m'] as String, passphrase: m['p'] as String?);
        case 'e':
          return Seed.entropy(_hexToBytes(m['h'] as String));
      }
    } catch (_) {/* corrupt entry → treat as a miss */}
    return null;
  }

  static String _hexOf(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  Future<Uint8List?> _loadCredentialId() async {
    final hex = (await SecretStores.local.read(key: _credentialIdKey))
        .valueOrThrow();
    if (hex == null) return null;
    if (hex.isEmpty || hex.length.isOdd) {
      throw StateError('Stored passkey credential is unreadable.');
    }
    return _hexToBytes(hex);
  }

  /// Persist the resolved credential before publishing its wallet. A lost
  /// pin could let the next sign-in select a different wallet credential.
  Future<void> _saveCredentialId(Uint8List? id, int generation) async {
    if (id == null || id.isEmpty) return;
    final buf = StringBuffer();
    for (final b in id) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    await _session.write(generation, () => SecretStores.local
        .write(key: _credentialIdKey, value: buf.toString()));
  }

  /// Recovery discovery, per the Breez passkey guide: ONE `signIn` with no
  /// label derives the label-store identity (and the SDK's default label)
  /// and lists the user's wallet labels from Nostr in the same ceremony.
  ///
  /// The returned [PasskeyDiscovery.credentialId] is the credential that
  /// owns those labels; the caller passes it to [getWallet] so the chosen
  /// wallet re-authenticates against that credential and no other. On a
  /// device that already stores a pin, discovery is pinned to it too, so
  /// labels from a different passkey can never be paired with this
  /// device's credential. Nothing is persisted here: the pin is written
  /// only when the chosen wallet resolves, so a wrong pick on the OS sheet
  /// can still be retried.
  ///
  /// [preferImmediatelyAvailable] is forwarded as in [getWallet]: the
  /// fresh-install restore passes `true` for Kute's home so a device with
  /// no Kute passkey fails fast instead of showing an error sheet. The
  /// Breez home's discovery keeps passing nothing (the SDK default), as it
  /// always has.
  Future<PasskeyDiscovery> discoverWallets({bool? preferImmediatelyAvailable}) {
    final pending = _discoveryInFlight;
    if (pending != null) return pending;
    late final Future<PasskeyDiscovery> future;
    future = _discover(_session.generation, preferImmediatelyAvailable)
        .whenComplete(() {
      if (identical(_discoveryInFlight, future)) _discoveryInFlight = null;
    });
    _discoveryInFlight = future;
    return future;
  }

  Future<PasskeyDiscovery> _discover(
      int generation, bool? preferImmediatelyAvailable) async {
    _assertCeremonyAllowed();
    final storedId = await _loadCredentialId();
    _session.check(generation);
    final hasStored = storedId != null && storedId.isNotEmpty;
    final resp = await _getClient().signIn(
      // Null [preferImmediatelyAvailable] is the request the Breez home
      // has always sent (the field unset).
      request: SignInRequest(
        label: null,
        allowCredentials: hasStored ? [storedId] : null,
        preferImmediatelyAvailableCredentials: preferImmediatelyAvailable,
      ),
    );
    _session.check(generation);
    final resolved = resp.credential?.credentialId;
    if (hasStored && resolved != null &&
        _hexOf(resolved) != _hexOf(storedId)) {
      throw StateError('Passkey credential changed. Recover the original wallet.');
    }
    // `_client` now holds this credential's label-store identity.
    _labelClient = null;
    final credentialId = (resolved != null && resolved.isNotEmpty)
        ? resolved
        : (hasStored ? storedId : null);
    _identityCredentialHex =
        credentialId != null ? _hexOf(credentialId) : null;
    unawaited(retryPendingLabels(verifyRelay: true));
    _discovered = (credentialId != null && resp.wallet.label.isNotEmpty)
        ? (
            label: resp.wallet.label,
            credentialHex: _hexOf(credentialId),
            wallet: resp.wallet,
          )
        : null;
    return PasskeyDiscovery(
      labels: List.unmodifiable(resp.labels),
      credentialId: credentialId,
      home: home,
    );
  }

  /// Whether this device has learned any passkey credential on this
  /// home's RP: its pin, and on the Breez RP also the legacy (pre-2.x) pin
  /// / registered flag. Storage failures read as "known", the
  /// conservative answer.
  Future<bool> hasKnownCredential() async {
    try {
      final stored = await _loadCredentialId();
      if (stored != null && stored.isNotEmpty) return true;
      if (!_isBreez) return false;
      final legacy = await PasskeyPrfService.pinnedCredentialId();
      if (legacy != null && legacy.isNotEmpty) return true;
      return await PasskeyPrfService.hasRegisteredCredential();
    } catch (_) {
      return true;
    }
  }

  // ───────────────────────── label publishing ──────────────────────────
  //
  // The SDK's `register()` already publishes the label itself in the
  // background (3 attempts, outcome never reported back), so after a mint
  // the app-side publish is a verification + fallback: `store_label` is
  // idempotent (it reads the relays first and only writes when the label
  // is missing), so a landed SDK publish makes it a cheap no-op. After a
  // `signIn` (existing passkey, new label) the SDK publishes nothing, so
  // the app-side publish is the only one.

  final ValueNotifier<Set<String>> _pendingLabels =
      ValueNotifier<Set<String>>(const <String>{});
  bool _pendingLoaded = false;

  /// Labels of this home this device created but has not yet confirmed as
  /// published. Reactive, so a quiet "syncing your backup" note can follow
  /// it. Hydrates itself from storage on first use.
  ValueListenable<Set<String>> get pendingLabels {
    if (!_pendingLoaded) {
      _pendingLoaded = true;
      unawaited(loadPendingLabels());
    }
    return _pendingLabels;
  }

  /// [pendingLabels] as it stands, without hydrating it from storage.
  Set<String> get pendingLabelsNow => _pendingLabels.value;

  /// Publishes in flight in this process, so a retry never runs a second
  /// loop for a label that is already being published: it joins this one.
  final Map<String, Future<bool>> _publishing = {};

  Future<Map<String, String>> _readPending() async {
    final box = await Hive.openBox('settings');
    final raw = box.get(_pendingLabelsKey);
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.key is String) e.key as String: (e.value as String?) ?? '',
    };
  }

  Future<void> _writePending(Map<String, String> pending) async {
    // The in-memory set is what the screens show: publish it first, so a
    // reader that sees the stored flag never finds the set behind it.
    _pendingLabels.value = Set.unmodifiable(pending.keys);
    final box = await Hive.openBox('settings');
    if (pending.isEmpty) {
      await box.delete(_pendingLabelsKey);
    } else {
      await box.put(_pendingLabelsKey, Map<String, String>.from(pending));
    }
  }

  /// Load the pending set from storage into [pendingLabels].
  Future<void> loadPendingLabels() async {
    try {
      _pendingLabels.value = Set.unmodifiable((await _readPending()).keys);
    } catch (_) {/* storage unavailable: nothing to show */}
  }

  /// Tail of the chain every pending-map mutation runs on. Marks and
  /// clears each read-modify-write the whole map, and a background retry's
  /// clear can interleave with a create's mark; without the chain the
  /// later write would drop the other label, and a dropped pending label
  /// is never retried (the wallet would never appear in passkey recovery
  /// on a new device).
  Future<void> _pendingMutationTail = Future<void>.value();

  /// Run [body] after every pending-map mutation queued before it. The
  /// chain never breaks: a failing body still releases the next one.
  Future<T> _serializePendingMutation<T>(Future<T> Function() body) {
    final previous = _pendingMutationTail;
    final done = Completer<void>();
    _pendingMutationTail = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }

  /// Flag [label] as created-but-not-yet-published. [credentialHex] names
  /// the credential whose identity must publish it.
  Future<void> markLabelPending(String label, {String? credentialHex}) =>
      _serializePendingMutation(() async {
        final pending = await _readPending();
        pending[label] = credentialHex ?? pending[label] ?? '';
        await _writePending(pending);
      });

  /// [markLabelPending] for the credential of the last ceremony in this
  /// process. The create flow calls it BEFORE the wallet record is
  /// written, so a kill between the save and the publish still leaves the
  /// label to be retried. Throws when the flag could not be stored.
  Future<void> markLabelPendingForIdentity(String label) =>
      markLabelPending(label, credentialHex: _identityCredentialHex);

  /// Told once a label's publish landed AND its pending flag was cleared.
  /// The settings model registers itself here to mark that wallet backed
  /// up (a passkey wallet claims no backup until its label is on the
  /// relay, so the existing reminder shows meanwhile). Null when no model
  /// is alive; a throwing handler is reported by kind and ignored.
  Future<void> Function(String label)? labelPublishedHandler;

  /// Drop [label] from the pending set once its publish is confirmed.
  Future<void> clearLabelPending(String label) =>
      _serializePendingMutation(() async {
        final pending = await _readPending();
        if (pending.remove(label) != null) await _writePending(pending);
      });

  Future<bool> hasPendingLabel(String label) async =>
      (await _readPending()).containsKey(label);

  void _debugResetPending() {
    _pendingLoaded = false;
    _pendingLabels.value = const <String>{};
    _publishing.clear();
    _labelBackupInFlight = null;
    _identityCredentialHex = null;
    _pendingMutationTail = Future<void>.value();
    labelPublishedHandler = null;
  }

  /// Publish a label to Nostr for later cross-device discovery.
  ///
  /// Retried because a dropped publish means the wallet silently won't
  /// appear in the recover picker on the user's other devices. The SDK
  /// call is idempotent (no-ops if the label already exists) and the PRF
  /// identity is cached on the client that last derived it (the sign-in or
  /// register that preceded this call), so the retries neither duplicate
  /// nor re-prompt for biometrics. Breez order: sign in with the new label
  /// first, store the label second — one OS prompt in total. Every attempt
  /// is capped at [PasskeyService.labelPublishAttemptTimeout]. Returns
  /// whether it landed; callers treat `false` as non-fatal (the wallet
  /// still works locally).
  Future<bool> storeLabel(String label, {int attempts = 3}) async =>
      (await _storeLabel(label, attempts: attempts)).landed;

  Future<({bool landed, int attempts})> _storeLabel(String label,
      {required int attempts}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await (_labelClient ?? _getClient())
            .labels()
            .store(label: label)
            .timeout(PasskeyService.labelPublishAttemptTimeout);
        return (landed: true, attempts: attempt + 1);
      } catch (_) {
        if (attempt < attempts - 1) {
          await Future.delayed(
              PasskeyService.labelPublishBackoff * (attempt + 1));
        }
      }
    }
    return (landed: false, attempts: attempts);
  }

  /// Flag [label] pending, then publish it off the caller's path: the
  /// returned future completes when the publish loop ends, but creation
  /// never awaits it. A landed publish clears the flag; a failed one leaves
  /// it for [retryPendingLabels]. One `passkey_label_published` event per
  /// loop carries the outcome ([trigger] is `create`, `retry`, `reminder`
  /// or `relay_check`); the label itself is never sent. A call while a
  /// loop for [label] is running joins that loop.
  Future<bool> publishLabelInBackground(String label,
      {required String trigger}) {
    final inFlight = _publishing[label];
    if (inFlight != null) return inFlight;
    final loop = _publishLoop(label, trigger);
    _publishing[label] = loop;
    return loop.whenComplete(() {
      if (identical(_publishing[label], loop)) _publishing.remove(label);
    });
  }

  Future<bool> _publishLoop(String label, String trigger) async {
    final started = Stopwatch()..start();
    try {
      await markLabelPending(label, credentialHex: _identityCredentialHex);
    } catch (_) {/* storage hiccup: still try to publish */}
    final result = await _storeLabel(label, attempts: 3);
    if (result.landed) {
      var cleared = false;
      try {
        await clearLabelPending(label);
        cleared = true;
      } catch (_) {/* the next load re-reads storage */}
      // Backed up only once the flag is gone too: a flag that outlives
      // the publish is retried, and the retry's clear reports again.
      if (cleared) await _notifyLabelPublished(label);
    }
    TrackingService.track('passkey_label_published', params: {
      'result': result.landed ? 'landed' : 'failed',
      'attempts': result.attempts,
      'duration_ms': started.elapsedMilliseconds,
      'trigger': trigger,
      if (!_isBreez) 'passkey_home': home.analyticsValue,
    });
    return result.landed;
  }

  Future<void> _notifyLabelPublished(String label) async {
    final handler = labelPublishedHandler;
    if (handler == null) return;
    try {
      await handler(label);
    } catch (e) {
      TrackingService.track('passkey_label_published_handler_failed', params: {
        'error_category': TrackingService.errorReason(e),
      });
    }
  }

  /// Re-publish every pending label that belongs to the credential whose
  /// identity the SDK client holds right now. A no-op when no ceremony has
  /// run in this process (publishing would cost a biometric prompt) and
  /// for labels created under a different credential.
  ///
  /// Called after every ceremony, and again on app resume and unlock: a
  /// label whose publish failed on a dead link after a ceremony earlier
  /// in this process goes out once the link is back, with no prompt. The
  /// identity cannot be primed any cheaper (the SDK derives it with a PRF
  /// assertion), so on a cold process (a warm device reads its seed from
  /// the local cache and runs none) this stays a no-op; the backup
  /// reminder's [finishLabelBackup] is what guarantees the publish.
  ///
  /// [verifyRelay] (the ceremony hooks) then lists the labels on the relay
  /// and publishes every local passkey label of this credential that is
  /// missing (a lost pending flag). Free: the identity is already primed.
  Future<void> retryPendingLabels({bool verifyRelay = false}) async {
    final primed = _identityCredentialHex;
    if (primed == null) return;
    // Fire-and-forget from inside a ceremony: ride on the settings box the
    // app already holds open rather than opening it here, where a wipe or
    // a test teardown deleting the Hive directory could race the open.
    if (!Hive.isBoxOpen('settings')) return;
    try {
      await _syncLabels(primed,
          trigger: 'retry', verifyRelay: verifyRelay, explicit: false);
    } catch (_) {/* best-effort: the next ceremony or the reminder retries */}
  }

  /// Publish what this credential still owes the relay, as one pass:
  ///  1. every pending label of [primed] (or of no known credential);
  ///  2. with [verifyRelay], `labels().list` and a publish of every local
  ///     passkey label of this home and of [primed] the relay does not
  ///     list. A listed label whose flag or record still says unpublished
  ///     is confirmed as published without a write.
  /// A failed list ends a silent pass; an [explicit] one (the reminder)
  /// then publishes every label still owed instead (`store` reads the
  /// relays first, so it is the check itself). Returns how many labels
  /// were written and which owed labels are still not confirmed.
  Future<({int republished, Set<String> unconfirmed})> _syncLabels(
    String? primed, {
    required String trigger,
    required bool verifyRelay,
    required bool explicit,
  }) async {
    bool ours(String? credentialHex) =>
        credentialHex == null || credentialHex.isEmpty ||
        credentialHex == primed;
    final pending = await _readPending();
    final owed = <String>{
      for (final e in pending.entries)
        if (ours(e.value)) e.key,
    };
    final confirmed = <String>{};
    var republished = 0;
    Future<void> publish(Iterable<String> labels, String trigger) async {
      final list = labels.toList();
      final landed = await Future.wait([
        for (final l in list) publishLabelInBackground(l, trigger: trigger),
      ]);
      for (var i = 0; i < list.length; i++) {
        if (!landed[i]) continue;
        confirmed.add(list[i]);
        republished++;
      }
    }

    await publish(owed, trigger);
    if (!verifyRelay) {
      return (
        republished: republished,
        unconfirmed: owed.difference(confirmed),
      );
    }

    final local = <String, bool>{};
    for (final entry in (await _localPasskeyLabels(primed)).entries) {
      if (ours(pending[entry.key])) local[entry.key] = entry.value;
    }
    for (final entry in local.entries) {
      if (!entry.value) owed.add(entry.key);
    }
    Set<String>? listed;
    try {
      listed = (await (_labelClient ?? _getClient())
              .labels()
              .list()
              .timeout(PasskeyService.labelPublishAttemptTimeout))
          .toSet();
    } catch (_) {/* offline: decided below */}
    final missing = <String>[];
    for (final label in local.keys) {
      if (confirmed.contains(label)) continue;
      if (listed == null) {
        if (explicit && owed.contains(label)) missing.add(label);
      } else if (!listed.contains(label)) {
        missing.add(label);
      } else if (owed.contains(label)) {
        // Already on the relay (an SDK publish that never reported, or a
        // flag that outlived its publish): nothing to write.
        try {
          await clearLabelPending(label);
          await _notifyLabelPublished(label);
          confirmed.add(label);
        } catch (_) {/* the next pass confirms it */}
      }
    }
    await publish(missing, 'relay_check');
    return (republished: republished, unconfirmed: owed.difference(confirmed));
  }

  /// Whether a stored record's `passkeyProvider` is a wallet of this home:
  /// on the Breez home every SDK record that is not Kute's (exactly the
  /// records it always covered), on Kute's home only `'kute-1'` records.
  bool _recordOnThisHome(Object? provider) => _isBreez
      ? provider != null && provider != PasskeyHomes.markerKute
      : provider == PasskeyHomes.markerKute;

  /// `{label: backedUp}` of every SDK passkey wallet record of this home
  /// on this device, when they belong to [primed]: every such wallet is
  /// derived under the device's one pinned credential for this home, so a
  /// ceremony on any other credential owns none of them. Legacy (pre-2.x)
  /// wallets never publish through this identity and are left out, as are
  /// the other home's wallets.
  Future<Map<String, bool>> _localPasskeyLabels(String? primed) async {
    final pin = await _loadCredentialId();
    if (pin != null && pin.isNotEmpty && primed != null &&
        _hexOf(pin) != primed) {
      return const {};
    }
    final raw = (await Hive.openBox('settings')).get('wallets');
    if (raw is! List) return const {};
    return {
      for (final w in raw)
        if (w is Map &&
            w['isPasskey'] == true &&
            _recordOnThisHome(w['passkeyProvider']) &&
            w['passkeyLabel'] is String)
          w['passkeyLabel'] as String: w['backedUp'] == true,
    };
  }

  /// The reminder's run in flight, so a double tap shares ONE ceremony.
  Future<PasskeyLabelBackupResult>? _labelBackupInFlight;

  /// The backup reminder's action for a passkey wallet whose label is not
  /// confirmed on the relay (without it the wallet cannot be found by
  /// passkey on a new phone). A warm device never runs a ceremony on its
  /// own, so this is the step that guarantees the publish:
  ///  1. ONE `signIn` for [label], pinned to the stored credential, the
  ///     same call [getWallet] makes. It primes the label-store identity
  ///     and must derive the seed this device already holds for [label];
  ///  2. [_syncLabels] publishes every pending label of that credential,
  ///     then lists the relay and publishes any local label it lacks.
  /// A label counts as published (its wallet's `backedUp` flips through
  /// [labelPublishedHandler]) only once a publish landed or the relay
  /// listed it. Never throws: a cancel or a failure comes back in the
  /// result and every unconfirmed label keeps its reminder. One funnel
  /// (`passkey_label_backup_started` → `_succeeded` | `_failed`) per run;
  /// [surface] is the reminder's screen.
  Future<PasskeyLabelBackupResult> finishLabelBackup(String label,
      {required String surface}) {
    final pending = _labelBackupInFlight;
    if (pending != null) return pending;
    late final Future<PasskeyLabelBackupResult> future;
    future = _finishLabelBackup(label, surface, _session.generation)
        .whenComplete(() {
      if (identical(_labelBackupInFlight, future)) _labelBackupInFlight = null;
    });
    _labelBackupInFlight = future;
    return future;
  }

  Future<PasskeyLabelBackupResult> _finishLabelBackup(
      String label, String surface, int generation) async {
    final started = Stopwatch()..start();
    TrackingService.track('passkey_label_backup_started',
        params: {
          'surface': surface,
          if (!_isBreez) 'passkey_home': home.analyticsValue,
        });
    var republished = 0;
    try {
      _assertCeremonyAllowed();
      final pin = await _loadCredentialId();
      _session.check(generation);
      final hasPin = pin != null && pin.isNotEmpty;
      final resp = await _getClient().signIn(
        request: SignInRequest(
          label: label,
          allowCredentials: hasPin ? [pin] : null,
        ),
      );
      _session.check(generation);
      final resolved = resp.credential?.credentialId;
      if (hasPin && resolved != null && _hexOf(resolved) != _hexOf(pin)) {
        throw StateError('Passkey credential changed. Recover the original wallet.');
      }
      // Same seed as the one this device holds for the label, or this
      // ceremony resolved another credential: its identity must never
      // publish this wallet's label.
      final cached =
          await _readCachedWallet(label, hasPin ? pin : _noCredential);
      _session.check(generation);
      if (cached != null &&
          _encodeSeed(cached.seed) != _encodeSeed(resp.wallet.seed)) {
        throw StateError('Passkey credential changed. Recover the original wallet.');
      }
      // `_client` now holds this credential's label-store identity.
      _labelClient = null;
      final credId = (resolved != null && resolved.isNotEmpty)
          ? resolved
          : (hasPin ? pin : null);
      _identityCredentialHex = credId != null ? _hexOf(credId) : null;
      final sync = await _syncLabels(_identityCredentialHex,
          trigger: 'reminder', verifyRelay: true, explicit: true);
      _session.check(generation);
      republished = sync.republished;
      if (sync.unconfirmed.isNotEmpty) {
        throw const PasskeyLabelsUnconfirmed();
      }
      TrackingService.track('passkey_label_backup_succeeded', params: {
        'surface': surface,
        'labels_republished': republished,
        'duration_ms': started.elapsedMilliseconds,
        if (!_isBreez) 'passkey_home': home.analyticsValue,
      });
      return PasskeyLabelBackupResult(
          succeeded: true, cancelled: false, republished: republished);
    } catch (e) {
      final cancelled = PasskeyService.isUserCancelledError(e);
      TrackingService.track('passkey_label_backup_failed', params: {
        'surface': surface,
        'error_category': cancelled
            ? 'user_cancelled'
            : e is PasskeyLabelsUnconfirmed
                ? 'publish_failed'
                : TrackingService.errorReason(e),
        'labels_republished': republished,
        'duration_ms': started.elapsedMilliseconds,
        if (!_isBreez) 'passkey_home': home.analyticsValue,
      });
      return PasskeyLabelBackupResult(
          succeeded: false, cancelled: cancelled, republished: republished);
    }
  }

  /// Forget the device-local seed material of this home's passkey wallet
  /// [label] once its record is gone (called by `removeWallet`, after the
  /// record). Deletes only what is keyed by this label on this home: the
  /// seed cache entry under this home's stored credential and the
  /// label-only entry, and the in-memory copies. On the Breez home also,
  /// as always, the legacy PRF seed for this salt when no remaining record
  /// carries the label (a shared label cannot be tied to one wallet, so it
  /// is kept), and the cached label when it names this wallet and no
  /// unlabelled record still depends on it; Kute's home touches neither
  /// (both are Breez / legacy values). Credential pins, the passkey
  /// registry and relay labels are never touched. Every step is
  /// best-effort; failures are reported by kind only.
  Future<void> forgetWallet(String label) async {
    _walletSession.remove(label);
    _walletInFlight.remove(label);
    if (_discovered?.label == label) _discovered = null;

    await _forgetStep('seed_cache', () async {
      Uint8List? pin;
      try {
        pin = await _loadCredentialId();
      } catch (_) {/* unreadable pin: the label-only entry still goes */}
      if (pin != null && pin.isNotEmpty) {
        await SecretStores.local.deleteLocalOnly(key: seedCacheKey(label, pin));
      }
      await SecretStores.local
          .deleteLocalOnly(key: seedCacheKey(label, _noCredential));
    });
    if (!_isBreez) return;

    // Without the records nothing can tie the PRF seed or the cached label
    // to this wallet alone, so both are kept.
    Box<dynamic>? box;
    try {
      box = await Hive.openBox('settings');
    } catch (e) {
      TrackingService.track('passkey_forget_wallet_step_failed', params: {
        'step': 'records',
        'error_category': TrackingService.errorReason(e),
      });
      return;
    }
    final records = box;
    if (!PasskeyService._anyRecordWithLabel(records, label)) {
      await _forgetStep('legacy_prf_seed',
          () => PasskeyPrfService.discardDerive(label, dropPin: false));
    }
    await _forgetStep('cached_label', () async {
      if (records.get(PasskeyService._cachedLabelKey) == label &&
          !PasskeyService._anyUnlabelledPasskeyRecord(records)) {
        await records.delete(PasskeyService._cachedLabelKey);
      }
    });
  }

  Future<void> _forgetStep(String step, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      TrackingService.track('passkey_forget_wallet_step_failed', params: {
        'step': step,
        'error_category': TrackingService.errorReason(e),
        if (!_isBreez) 'passkey_home': home.analyticsValue,
      });
    }
  }
}

/// Single resolver for "give me a BIP39 mnemonic for [wallet]". Hides
/// the passkey-vs-stored branch from every call site that needs to
/// derive an EOA / sign an order / display a recovery phrase.
///
/// Passkey wallets re-derive on every call via Breez SDK
/// (`Passkey.getWallet`), per
/// https://sdk-doc-spark.breez.technology/guide/passkey.html. Stored
/// wallets read the persisted mnemonic via [AuthModel.readMnemonic].
///
/// With [SeedAccess.automatic] and a session that is not unlocked it
/// returns null before either branch, so nothing signs behind the lock.
/// Returns null when either path can't produce a phrase (cancelled
/// biometric, missing PIN, wallet wiped).
Future<String?> resolveBip39MnemonicFor(
  WalletConfig wallet, {
  required SeedAccess access,
  required SeedSession session,
}) async {
  LedgerOperationScope.assertHotAllowed(HotSigningAction.bip39MnemonicRead);
  if (access == SeedAccess.automatic && !session.unlocked) return null;
  if (wallet.isPasskey) {
    // Always pass the wallet's stored `passkeyLabel`. Falling back to
    // the singleton cache is only correct when the user has one
    // passkey wallet — with multiple, the cache holds whichever was
    // touched last, so we'd silently derive the wrong seed for any
    // other wallet. Null `passkeyLabel` (legacy single-wallet users
    // created before the unique-label fix) lets `getMnemonic` apply
    // its `'Default'` fallback.
    //
    // VINTAGE: `passkeyProvider == null` marks a pre-2.x wallet whose
    // seed only reconstructs via the app's own PRF pipeline
    // (getLegacySeed); 'breez-0.17' wallets go through the new SDK on
    // the Breez RP, 'kute-1' wallets on Kute's RP; any other marker
    // resolves nothing.
    return PasskeyService.getMnemonicFor(
      label: wallet.passkeyLabel,
      provider: wallet.passkeyProvider,
    );
  }
  return AuthModel().getMnemonic(wallet.id, access: access, session: session);
}

/// What a recovery discovery sign-in found: the wallet labels published
/// for the passkey, the credential that owns them and the home it lives
/// on. Never sent to analytics.
class PasskeyDiscovery {
  const PasskeyDiscovery({
    required this.labels,
    required this.credentialId,
    this.home = PasskeyHome.breez,
  });

  final List<String> labels;

  /// The credential the discovery ceremony resolved, or null when the
  /// platform provider does not surface it.
  final Uint8List? credentialId;

  /// The RP the credential (and so every listed wallet) lives on.
  final PasskeyHome home;
}

/// What the passkey backup reminder's run did. Carries no label.
class PasskeyLabelBackupResult {
  const PasskeyLabelBackupResult({
    required this.succeeded,
    required this.cancelled,
    required this.republished,
  });

  /// Every label the reminder was for is confirmed on the relay.
  final bool succeeded;

  /// The user dismissed the OS passkey sheet.
  final bool cancelled;

  /// Labels written to the relay by this run.
  final int republished;
}

/// The ceremony ran but at least one owed label is still not confirmed on
/// the relay (offline, or the relay refused it).
class PasskeyLabelsUnconfirmed implements Exception {
  const PasskeyLabelsUnconfirmed();

  @override
  String toString() => 'PasskeyLabelsUnconfirmed';
}
