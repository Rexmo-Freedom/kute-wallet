import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_session.dart';
import 'package:kute/services/evm_derivation_policy.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

/// Service for passkey-based wallet creation and restoration.
///
/// Uses the Breez SDK [PasskeyClient] (built-in [PasskeyProvider] on the
/// shared Breez RP `keys.breez.technology`), which derives wallet keys
/// deterministically from WebAuthn PRF extension output. Derived seeds are
/// cached in device-local secure storage.
/// App session authentication gates later seed access; recovery uses the passkey.
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
  static PasskeyClient? _client;
  static final _session = PasskeySession();

  static Future<void> drainPendingWrites() => _session.drainWrites();

  @visibleForTesting
  static void debugSetClient(PasskeyClient? client) {
    _client = client;
    clearSession();
  }

  /// Secure-storage key for the credential id the 0.17.1 [PasskeyClient]
  /// last resolved against on THIS device. Stored so [getWallet] can pin
  /// every subsequent `signIn` to that exact credential via
  /// `SignInRequest.allowCredentials`. Without the pin the OS free-picks
  /// among every credential on the shared RP `keys.breez.technology` —
  /// and all Kute credentials carry the same user name
  /// ('kute-wallet-user'), so a free pick can silently resolve a
  /// DIFFERENT passkey and derive a different, fund-losing seed. Kept
  /// separate from the legacy `prf_credential_id_v1__*` slot
  /// ([PasskeyPrfService]) because the two stacks must never share pins.
  static const String _credentialId017Key = 'passkey017_credential_id';

  // ─────────────────── 0.17 seed cache + ceremony coalescing ──────────────
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
  //   • device-local secureStorage (passkey017_seed_v1__…) — persists the
  //     derived seed so a warm device skips the ceremony on cold start too.
  // The persisted seed sits in the SAME this-device-only tier as the legacy
  // PRF seed and the app's BIP39 seeds; the passkey stays the recovery root.
  static final Map<String, Wallet> _walletSession = {};
  static final Map<String, Future<Wallet>> _walletInFlight = {};
  static const String _seedCacheKeyPrefix = 'passkey017_seed_v1__';

  /// The discovery sign-in in flight, so a double tap (or the auto lookup
  /// racing a tap) shares ONE ceremony.
  static Future<PasskeyDiscovery>? _discoveryInFlight;

  /// The wallet the last discovery derived for the SDK's default label,
  /// with the credential that derived it. Held in memory only, so a
  /// restore of that same label on that same credential needs no second
  /// ceremony. Consumed by [_resolveWallet].
  static ({String label, String credentialHex, Wallet wallet})? _discovered;

  /// The client whose label-store identity was primed most recently by a
  /// ceremony other than one on [_client] (the display-name register
  /// client). [storeLabel] uses it so publishing costs no extra prompt.
  static PasskeyClient? _labelClient;

  /// Forget every derived wallet and pending ceremony held in memory.
  /// Storage is untouched. Called by the wipe path.
  static void clearSession() {
    _session.clear();
    _walletSession.clear();
    _walletInFlight.clear();
    _discoveryInFlight = null;
    _discovered = null;
    _labelClient = null;
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

  /// Vintage tag for wallets derived through the SDK's [PasskeyClient].
  /// Mirrors `WalletConfig.passkeyProvider == 'breez-0.17'`. The literal
  /// is HISTORICAL — it was minted when the new stack shipped on SDK
  /// 0.17.1 and the SDK is now v0.23.0 — but it is a persisted
  /// discriminator on every new-stack wallet, so it must NEVER be
  /// renamed (same for the `passkey017_*` storage keys).
  static const String vintageBreez017 = 'breez-0.17';

  /// Vintage tag for LEGACY (pre-2.x, breez-0.15.1) passkey wallets whose
  /// seed reconstructs via [getLegacySeed]. Mirrors the `null`
  /// `WalletConfig.passkeyProvider` on those wallets, but recorded as an
  /// explicit non-null string.
  static const String vintageLegacy = '0.15.1';

  /// Get or create the [PasskeyClient]. The default constructor wires the
  /// built-in native [PasskeyProvider] (channel `breez_sdk_spark_passkey`,
  /// shipped by the SDK) on the shared Breez RP, so all we supply is the
  /// relay key for authenticated label storage.
  static PasskeyClient _getClient() {
    _client ??= PasskeyClient(breezApiKey: dotenv.env['BREEZ_API_KEY']);
    return _client!;
  }

  /// Check if passkey PRF is supported (and the app is RP-associated) on this
  /// device.
  static Future<bool> isAvailable() async {
    try {
      final availability = await _getClient().checkAvailability();
      return availability is PasskeyAvailability_Available;
    } catch (_) {
      return false;
    }
  }

  /// MINT a new passkey credential and derive the wallet for [label].
  /// First-time wallet creation only — runs the OS "create passkey" ceremony.
  /// (breez `register()`.) Returns the derived [Wallet].
  ///
  /// Persists the freshly minted credential id so the very first
  /// `signIn` after creation is already pinned to THIS credential —
  /// closing the window where an un-pinned assertion could resolve a
  /// sibling 'kute-wallet-user' credential on the shared RP.
  /// [userDisplayName] (when provided) becomes the WebAuthn `user.name` /
  /// `user.displayName` on the minted credential — the string the OS
  /// passkey sheet and iCloud Keychain / Google Password Manager list
  /// show — so the entry carries the user's own wallet label instead of
  /// the provider default. Cosmetic only: credential resolution stays
  /// pinned by credential id (never by name), and the seed derives from
  /// (PRF, label) exactly as before.
  static Future<Wallet> createWallet({
    required String label,
    String? userDisplayName,
  }) async {
    final generation = _session.generation;
    // Tell the platform about every credential this device already knows
    // (the 0.17 pin and the legacy pin) so a duplicate mint on the shared
    // RP fails cleanly with `credentialAlreadyExists` instead of creating
    // a sibling credential — a second credential forks the Nostr label
    // identity (old wallets vanish from recovery), and on iOS a second
    // same-name registration can REPLACE the first in iCloud Keychain,
    // permanently stranding wallets derived under it. This only protects
    // ids the device has learned; the caller-side signIn-first flow is
    // still the primary guard.
    final exclude = <Uint8List>[];
    final storedId017 = await _loadCredentialId017();
    _session.check(generation);
    if (storedId017 != null && storedId017.isNotEmpty) {
      exclude.add(storedId017);
    }
    final legacyId = await PasskeyPrfService.pinnedCredentialId();
    _session.check(generation);
    if (legacyId != null && legacyId.isNotEmpty) exclude.add(legacyId);
    // One-off client for the register ceremony ONLY, so the mint carries
    // the user's display name. The cached `_client` (default names) keeps
    // serving signIn / labels — assertions ignore the cosmetic names, so
    // the split changes nothing for existing flows.
    final registerClient = (userDisplayName == null ||
            userDisplayName.trim().isEmpty)
        ? _getClient()
        : PasskeyClient(
            breezApiKey: dotenv.env['BREEZ_API_KEY'],
            config: PasskeyConfig(
              providerOptions: PasskeyProviderOptions(
                userName: userDisplayName.trim(),
                userDisplayName: userDisplayName.trim(),
              ),
            ),
          );
    final resp = await registerClient.register(
      request: RegisterRequest(
        label: label,
        excludeCredentials: exclude.isEmpty ? null : exclude,
      ),
    );
    _session.check(generation);
    final credId = resp.credential?.credentialId;
    await _saveCredentialId017(credId, generation);
    _session.check(generation);
    // register() derived this credential's label-store identity on
    // `registerClient` (and already publishes the label in the background).
    // Route the caller's follow-up storeLabel through that same client so
    // it reuses the identity instead of costing a second OS prompt.
    _labelClient = registerClient;
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

  // ───────────────────────── typed error routing ────────────────────────────

  /// The user dismissed the OS passkey ceremony. Typed check first (the
  /// 0.23 SDK surfaces `PasskeyError.prf(PrfProviderError.userCancelled())`),
  /// string fallback for the legacy channel's `PlatformException` and any
  /// wrapped re-throws.
  static bool isUserCancelledError(Object e) {
    if (e is PasskeyError_Prf && e.field0 is PrfProviderError_UserCancelled) {
      return true;
    }
    return e.toString().toLowerCase().contains('cancel');
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

  /// Derive a wallet from an EXISTING passkey (breez `signIn()`).
  ///
  /// VINTAGE GATE — [legacy] is required precisely so the compiler forces
  /// every call site to route on the wallet's `passkeyProvider`:
  /// `legacy: true` throws immediately, pointing at [getLegacySeed]. A
  /// legacy (pre-2.x) wallet run through the new SDK's `signIn` can
  /// resolve a different credential on the shared RP and derive a
  /// different, fund-losing seed — this surface must never serve it.
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
  /// [label] defaults to "Default" (discovery) if null.
  static Future<Wallet> getWallet({
    String? label,
    required bool legacy,
    Uint8List? credentialId,
  }) async {
    if (legacy) {
      throw ArgumentError(
        'getWallet() serves only breez-0.17 passkey wallets. Legacy '
        '(passkeyProvider == null) wallets must derive via '
        'PasskeyService.getLegacySeed — the new SDK signIn can resolve a '
        'different credential and a different, fund-losing seed.',
      );
    }
    final generation = _session.generation;
    final key = label ?? '';
    // Fast path: already derived this session — no OS, no storage.
    final session = _walletSession[key];
    if (session != null) return session;
    // Coalesce concurrent callers (connect + relayer + affiliate on boot)
    // onto a SINGLE ceremony so they can't fight for the OS authorization.
    final pending = _walletInFlight[key];
    if (pending != null) return pending;
    final future = _resolveWallet(label, generation, credentialId);
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
  static Future<Wallet> _resolveWallet(
      String? label, int generation, Uint8List? discoveredId) async {
    final storedId = await _loadCredentialId017();
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
    // served for the wrong wallet.
    if (pin != null) {
      final cached = await _readCachedWallet(label, pin);
      _session.check(generation);
      if (cached != null) return cached;
    }
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
      credId = resp.credential?.credentialId;
    }
    // Reconcile: keep the stored id tracking what the OS actually
    // resolved against so the NEXT ceremony pins correctly.
    _session.check(generation);
    await _saveCredentialId017(credId, generation);
    _session.check(generation);
    // Persist the derived seed device-local, keyed by (label, resolved cred).
    if (credId != null && credId.isNotEmpty) {
      await _writeCachedWallet(label, credId, wallet, generation);
    }
    _session.check(generation);
    return wallet;
  }

  static String _seedCacheKey(String? label, Uint8List credId) {
    final digest =
        sha256.convert(utf8.encode('${label ?? ''}|${_hexOf(credId)}'));
    return '$_seedCacheKeyPrefix$digest';
  }

  static Future<Wallet?> _readCachedWallet(
      String? label, Uint8List credId) async {
    final raw =
        (await SecretStores.local.read(key: _seedCacheKey(label, credId)))
            .valueOrThrow();
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final seed = _decodeSeed(map['seed'] as String?);
    if (seed == null || (map['label'] != null && map['label'] != label)) {
      throw StateError('Stored passkey wallet is unreadable. Restore the wallet.');
    }
    return Wallet(seed: seed, label: (map['label'] as String?) ?? label ?? '');
  }

  static Future<void> _writeCachedWallet(
      String? label, Uint8List credId, Wallet wallet, int generation) async {
    try {
      await _session.write(generation, () => SecretStores.local.writeLocalOnly(
        key: _seedCacheKey(label, credId),
        value: jsonEncode({'label': wallet.label, 'seed': _encodeSeed(wallet.seed)}),
      ));
    } catch (_) {/* non-fatal: the session cache still covers this run */}
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

  static Future<Uint8List?> _loadCredentialId017() async {
    final hex = (await SecretStores.local.read(key: _credentialId017Key))
        .valueOrThrow();
    if (hex == null) return null;
    if (hex.isEmpty || hex.length.isOdd) {
      throw StateError('Stored passkey credential is unreadable.');
    }
    return _hexToBytes(hex);
  }

  /// Persist the resolved credential before publishing its wallet. A lost
  /// pin could let the next sign-in select a different wallet credential.
  static Future<void> _saveCredentialId017(Uint8List? id, int generation) async {
    if (id == null || id.isEmpty) return;
    final buf = StringBuffer();
    for (final b in id) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    await _session.write(generation, () => SecretStores.local
        .write(key: _credentialId017Key, value: buf.toString()));
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
  static Future<PasskeyDiscovery> discoverWallets() {
    final pending = _discoveryInFlight;
    if (pending != null) return pending;
    late final Future<PasskeyDiscovery> future;
    future = _discover(_session.generation).whenComplete(() {
      if (identical(_discoveryInFlight, future)) _discoveryInFlight = null;
    });
    _discoveryInFlight = future;
    return future;
  }

  static Future<PasskeyDiscovery> _discover(int generation) async {
    final storedId = await _loadCredentialId017();
    _session.check(generation);
    final hasStored = storedId != null && storedId.isNotEmpty;
    final resp = await _getClient().signIn(
      request: SignInRequest(
        label: null,
        allowCredentials: hasStored ? [storedId] : null,
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
    );
  }

  /// Publish a label to Nostr for later cross-device discovery.
  ///
  /// Retried because a dropped publish means the wallet silently won't
  /// appear in the recover picker on the user's other devices. The SDK
  /// call is idempotent (no-ops if the label already exists) and the PRF
  /// identity is cached on the client that last derived it (the sign-in or
  /// register that preceded this call), so the retries neither duplicate
  /// nor re-prompt for biometrics. Breez order: sign in with the new label
  /// first, store the label second — one OS prompt in total. Returns whether it ultimately landed; callers treat
  /// `false` as non-fatal (the wallet still works locally).
  static Future<bool> storeLabel(String label) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await (_labelClient ?? _getClient()).labels().store(label: label);
        return true;
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
    }
    return false;
  }

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

  /// Cache the active label locally for quick re-authentication.
  static Future<void> cacheLabel(String label) async {
    final box = await Hive.openBox('settings');
    await box.put('passkey_cached_label', label);
  }

  /// Get the cached label (if any).
  static Future<String?> getCachedLabel() async {
    final box = await Hive.openBox('settings');
    return box.get('passkey_cached_label') as String?;
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
  /// underneath.
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
    // (getLegacySeed); 'breez-0.17' wallets go through the new SDK.
    return PasskeyService.getMnemonic(
      label: wallet.passkeyLabel,
      legacy: wallet.passkeyProvider == null,
    );
  }
  return AuthModel().getMnemonic(wallet.id, access: access, session: session);
}

/// What a recovery discovery sign-in found: the wallet labels published
/// for the passkey, and the credential that owns them. Never sent to
/// analytics.
class PasskeyDiscovery {
  const PasskeyDiscovery({required this.labels, required this.credentialId});

  final List<String> labels;

  /// The credential the discovery ceremony resolved, or null when the
  /// platform provider does not surface it.
  final Uint8List? credentialId;
}
