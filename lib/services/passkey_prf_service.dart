import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/passkey_session.dart';

/// Platform channel bridge for WebAuthn PRF extension.
///
/// Calls native iOS (ASAuthorization) and Android (CredentialManager)
/// passkey APIs with the PRF extension to derive deterministic seeds.
///
/// The Relying Party is keys.breez.technology (shared RP for cross-app passkey).
class PasskeyPrfService {
  static const _channel = MethodChannel('com.kutewallet.app/passkey_prf');
  static final _session = PasskeySession();

  static Future<void> drainPendingWrites() => _session.drainWrites();

  /// Per-(rpId, salt) cache of the PRF output — SESSION-ONLY (in-memory,
  /// process lifetime), above a device-local secure-storage cache. This cache
  /// only stops the Breez Rust worker from re-prompting on every reconnect
  /// within a single session.
  static final Map<String, Uint8List> _prfCache = {};

  /// In-flight derive promise per cache key. iOS's
  /// `ASAuthorizationController` refuses concurrent ceremonies for
  /// the same RP — the second tap returns "Request already in
  /// progress for specified application identifier." So multiple
  /// callers that arrive while a ceremony is on screen all await the
  /// same future and share its result.
  static final Map<String, Future<PrfDeriveResult>> _inFlight = {};

  /// Secure-storage key prefix for the persisted PRF output (the wallet
  /// master secret). [_loadOrDerive] keeps it device-local. Builds up to
  /// 1.2.11 wrote the same key to the synced store (iCloud Keychain); that
  /// copy is still read as a fallback and is never written, copied into
  /// local storage or deleted.
  ///
  /// The salt is SHA-256'd into the key name to avoid storing a
  /// potentially long arbitrary string in a Keychain attribute.
  static const String _storageKeyPrefix = 'prf_seed_v1__';

  /// Secure-storage key for the credential ID the OS resolves against.
  /// Stored per rpId, DEVICE-LOCALLY (`secureStorage`, this-device-only)
  /// so the assertion ceremony can pin to it and skip the account
  /// picker. It is deliberately NOT iCloud/Google synced: the raw id is
  /// an OS reference to a credential materialised on THIS device, so
  /// syncing it (as older builds did) shipped one device's id to another
  /// and made the pinned assertion fail with "no passkey found" on the
  /// second device. Each device learns its own id from its first
  /// successful assertion (`_runDerive`), then preserves that pin.
  static const String _credentialIdKeyPrefix = 'prf_credential_id_v1__';

  /// Derive a 32-byte PRF seed from the passkey using the given salt.
  ///
  /// Triggers biometric/device authentication and returns the PRF output.
  /// The same passkey + salt always produces the same 32 bytes (deterministic).
  ///
  /// Cached for the process lifetime so the OS doesn't re-prompt on
  /// every Breez SDK reconnect. The Breez Rust worker calls this
  /// from its FFI bridge whenever it needs the seed; without the
  /// cache the user sees the Face ID sheet every few seconds.
  ///
  /// Throws a [PlatformException] when the native handler is missing
  /// (no iOS/Android implementation registered for the channel) so
  /// callers can route to a non-PRF code path instead of letting the
  /// underlying `MissingPluginException` bubble up to Rust — which
  /// panics the SDK's tokio worker because the bridge contract
  /// assumes the Dart side is infallible.
  static Future<Uint8List> derivePrfSeed(String salt) async =>
      (await derivePrfSeedTracked(salt)).seed;

  /// [derivePrfSeed] plus provenance, for callers that must know whether
  /// the bytes came from a trusted persisted tier or a fresh OS ceremony.
  ///
  /// `fromCeremony` is true only when an OS assertion ran for THIS call;
  /// `unpinned` is true when that assertion ran without a credential pin
  /// (the OS account picker chose, so on a multi-credential device the
  /// resolved credential is user-choice, not guaranteed). Recovery probes
  /// use this to discard a fresh derive whose wallet turns out to be an
  /// empty phantom — otherwise one wrong pick on the picker permanently
  /// poisons the persisted cache and the pin ([discardDerive]).
  static Future<PrfDeriveResult> derivePrfSeedTracked(String salt) async {
    final generation = _session.generation;
    const rpId = 'keys.breez.technology';
    final cacheKey = '$rpId|$salt';

    // Fast path: in-memory cache, no Keychain or OS round-trip.
    final cached = _prfCache[cacheKey];
    if (cached != null) {
      return PrfDeriveResult(seed: cached, fromCeremony: false, unpinned: false);
    }

    // Coalesce concurrent callers onto a single in-flight OS ceremony.
    // The Breez SDK is async-heavy and fires the seed callback from
    // multiple tokio tasks during a single connect cycle — without this
    // guard each task spawns its own passkey UI and they fight (iOS
    // rejects concurrent ceremonies for the same RP).
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    final future = _loadOrDerive(rpId, salt, generation);
    _inFlight[cacheKey] = future;
    try {
      final result = await future;
      _session.check(generation);
      _prfCache[cacheKey] = result.seed;
      return result;
    } finally {
      if (identical(_inFlight[cacheKey], future)) _inFlight.remove(cacheKey);
    }
  }

  /// Discard the device-local artifacts a FRESH derive for [salt] just
  /// wrote, so the next attempt re-runs the OS ceremony. Called by
  /// recovery when a freshly derived seed probes as an empty phantom —
  /// the ceremony almost certainly resolved the wrong credential, and
  /// leaving the cache in place would serve the wrong bytes forever with
  /// no ceremony ever offered again.
  ///
  /// [dropPin] additionally forgets the pinned credential id (pass true
  /// only when the bad ceremony ran UN-pinned and its reconcile step may
  /// have just re-pointed the pin at the wrong credential). Only the
  /// device-local seed copy is deleted: the legacy iCloud-synced copy
  /// predates this session and is ground truth for upgraded devices.
  static Future<void> discardDerive(String salt, {required bool dropPin}) async {
    const rpId = 'keys.breez.technology';
    _prfCache.remove('$rpId|$salt');
    try {
      await SecretStores.local.deleteLocalOnly(key: _storageKey(rpId, salt));
    } catch (_) {/* best-effort */}
    if (dropPin) {
      await _deleteCredentialId(rpId);
    }
  }

  /// The pinned legacy credential id for the shared Breez RP, or null when
  /// this device never learned one. Read-only surface for the create flow
  /// (seed `SignInRequest.allowCredentials` / `RegisterRequest.excludeCredentials`
  /// with it so the new SDK reuses the old credential instead of minting a
  /// sibling on the shared RP).
  static Future<Uint8List?> pinnedCredentialId() =>
      _loadCredentialId('keys.breez.technology');

  /// Device-local seed tier between the in-memory cache and the OS ceremony.
  /// Reads the persisted PRF seed from DEVICE-LOCAL storage (this-device-only,
  /// NOT iCloud-synced) so a passkey wallet doesn't re-prompt Face ID on every
  /// cold start / SDK reconnect; runs the OS ceremony only on a true miss,
  /// then persists. Same protection class as the BIP39 seeds the app already
  /// stores device-local — the seed never leaves the device, and recovery on
  /// a NEW device still re-derives from the OS-synced passkey. A legacy
  /// iCloud-synced copy is read but never copied into local storage.
  static Future<PrfDeriveResult> _loadOrDerive(
      String rpId, String salt, int generation) async {
    final key = _storageKey(rpId, salt);
    // 1. Device-local cache — fast, no OS prompt.
    final local = await _readSeed(SecretStores.local, key);
    _session.check(generation);
    if (local != null) {
      return PrfDeriveResult(seed: local, fromCeremony: false, unpinned: false);
    }
    // 2. MIGRATION (funds safety) — the legacy iCloud/Google-synced seed an
    //    older build (≤1.2.11) wrote, keyed by the SAME label-salt. Reading
    //    it guarantees an EXISTING wallet re-derives the EXACT seed it was
    //    created with, regardless of which passkey the OS would resolve now
    //    — critical for users who accumulated multiple passkeys (the no-iCloud
    //    change removed this read and exposed the "wrong wallet" derivation).
    //    We only READ the legacy copy: it is never written, never mirrored
    //    into device-local storage and never deleted.
    final synced = await _readSeed(SecretStores.synced, key);
    _session.check(generation);
    if (synced != null) {
      return PrfDeriveResult(seed: synced, fromCeremony: false, unpinned: false);
    }
    // 3. Derive via the OS ceremony, persist device-local.
    final fresh = await _runDerive(rpId, salt, generation);
    _session.check(generation);
    try {
      await _session.write(generation, () => SecretStores.local
          .writeLocalOnly(key: key, value: _bytesToHex(fresh.seed)));
    } catch (_) {/* non-fatal: the in-memory cache covers this session */}
    _session.check(generation);
    return fresh;
  }

  static Future<Uint8List?> _readSeed(SecretStore store, String key) async {
    final value = (await store.read(key: key)).valueOrThrow();
    if (value == null) return null;
    if (value.length != 64) {
      throw StateError('Stored passkey seed is unreadable. Restore the wallet.');
    }
    return _hexToBytes(value);
  }

  static String _storageKey(String rpId, String salt) {
    final digest = sha256.convert(utf8.encode('$rpId|$salt'));
    return '$_storageKeyPrefix$digest';
  }

  static String _bytesToHex(Uint8List bytes) {
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

  static Future<PrfDeriveResult> _runDerive(
      String rpId, String salt, int generation) async {
    try {
      // A credential selects the wallet, not just the account-picker UI.
      // Never drop an existing pin after cancellation, storage or OS failure.
      final knownCredentialId = await _loadCredentialId(rpId);
      _session.check(generation);
      final pinned = knownCredentialId == null
          ? <Uint8List>[]
          : <Uint8List>[knownCredentialId];
      final unpinned = pinned.isEmpty;
      final res = await _invokeDerive(rpId, salt, pinned);
      _session.check(generation);
      final prfBytes = res.$1;
      final assertedCredentialId = res.$2;
      if (knownCredentialId != null && assertedCredentialId != null &&
          !_bytesEqual(knownCredentialId, assertedCredentialId)) {
        throw PlatformException(code: 'CREDENTIAL_MISMATCH',
            message: 'Passkey credential changed. Recover the original wallet.');
      }


      // Reconcile: keep the stored id tracking whatever the OS actually
      // resolved against on this device (replacing — not just filling —
      // a stale or foreign id) so the next ceremony pins correctly.
      if (assertedCredentialId != null &&
          assertedCredentialId.isNotEmpty &&
          !_bytesEqual(assertedCredentialId, knownCredentialId)) {
        await _saveCredentialId(rpId, assertedCredentialId, generation);
      }
      _session.check(generation);
      return PrfDeriveResult(
          seed: prfBytes, fromCeremony: true, unpinned: unpinned);
    } on MissingPluginException {
      throw PlatformException(
        code: 'PRF_UNAVAILABLE',
        message: 'PRF not available on this platform',
      );
    }
  }

  /// One native `derivePrfSeed` assertion. Returns the 32-byte PRF
  /// output and the credential the OS resolved against (null on older
  /// native builds that returned bare bytes). Throws [PlatformException]
  /// when the ceremony fails (cancelled, no matching passkey, etc.).
  /// A failed pinned assertion is never retried against another credential.
  static Future<(Uint8List, Uint8List?)> _invokeDerive(
    String rpId,
    String salt,
    List<Uint8List> credentialIds,
  ) async {
    final args = <String, dynamic>{
      'salt': salt,
      'rpId': rpId,
    };
    if (credentialIds.isNotEmpty) {
      args['credentialIds'] = credentialIds;
    }
    // The assertion puts the OS passkey sheet, and Face ID with it, on
    // screen. Scoped so the privacy cover does not cover the app for
    // the length of the scan.
    //
    // Native side returns `{prf: Uint8List, credentialId: Uint8List}`.
    // Older builds returned bare bytes; tolerate both so a partial
    // platform upgrade doesn't brick the wallet.
    final raw = await runBiometricPrompt(
      () => _channel.invokeMethod<dynamic>('derivePrfSeed', args),
    );
    Uint8List? prfBytes;
    Uint8List? assertedCredentialId;
    if (raw is Map) {
      final p = raw['prf'];
      if (p is Uint8List) prfBytes = p;
      final c = raw['credentialId'];
      if (c is Uint8List) assertedCredentialId = c;
    } else if (raw is Uint8List) {
      prfBytes = raw;
    }
    if (prfBytes == null || prfBytes.length != 32) {
      throw PlatformException(
        code: 'PRF_ERROR',
        message: 'Failed to derive PRF seed — expected 32 bytes',
      );
    }
    return (prfBytes, assertedCredentialId);
  }

  static bool _bytesEqual(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Drop the cached PRF seed (in-memory and the device-local copy).
  /// Called when the user explicitly signs out / wipes the wallet so the
  /// next session re-authenticates via the OS ceremony from scratch.
  /// No-op when there's nothing cached.
  ///
  /// Only the in-memory keys we know about get individually deleted from
  /// device-local storage. Anything not in `_prfCache` at clear time is
  /// harmless leftover — the next derive overwrites it. A legacy
  /// iCloud-synced copy is never deleted.
  static Future<void> clearCache() async {
    final keys = {..._prfCache.keys, ..._inFlight.keys}.toList();
    clearMemory();
    await drainPendingWrites();
    for (final cacheKey in keys) {
      final parts = cacheKey.split('|');
      if (parts.length != 2) continue;
      try {
        await SecretStores.local
            .deleteLocalOnly(key: _storageKey(parts[0], parts[1]));
      } catch (_) {
        // best-effort cleanup
      }
    }
    // Drop the pinned credential id too — a wiped wallet must not leave a
    // stale id that pins (and breaks) the next ceremony. The RP is fixed,
    // so delete it unconditionally: `_prfCache` may already be empty here
    // (wipe before any derive ran this session).
    await _deleteCredentialId('keys.breez.technology');
  }

  /// Forget every PRF seed and pending ceremony held in memory. Storage is
  /// untouched. Called by the wipe path.
  static void clearMemory() {
    _session.clear();
    _prfCache.clear();
    _inFlight.clear();
  }

  /// Check if a PRF-capable passkey exists for the RP.
  ///
  /// Returns `false` when the native handler isn't installed for the
  /// passkey-PRF channel (e.g. macOS host, custom build flavour, or a
  /// platform we haven't wired up yet). Without this guard, the
  /// Breez Spark SDK's Rust worker calls into this Dart function via
  /// the FFI bridge — which translates a thrown `MissingPluginException`
  /// into a "Dart throws exception but Rust side assume it is not
  /// failable" panic at `frb_generated.rs:4934`. Treating "no
  /// platform handler" as "no PRF passkey available" is semantically
  /// equivalent and lets the SDK fall back to its non-PRF code path.
  static Future<bool> isPrfAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPrfAvailable', {
        'rpId': 'keys.breez.technology',
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Register a new passkey credential with PRF support.
  ///
  /// Called once during initial wallet creation. The credential is then
  /// synced via iCloud Keychain (iOS) or Google Password Manager (Android).
  ///
  /// Returns the credential ID bytes from the OS. We persist them in
  /// `syncedSecureStorage` so future assertion ceremonies pin to this
  /// specific credential — without that, the OS shows the account
  /// picker every sign-in even though we know exactly which passkey
  /// to use. Stored value rides iCloud / Google sync onto new devices
  /// alongside the passkey itself.
  /// Device-local marker that a passkey has been registered for the RP on
  /// this device. Persisted independently of the wallet list (and NOT cleared
  /// by deleting a wallet), so deleting + recreating a wallet REUSES the same
  /// passkey instead of minting a second — keeping it to ONE passkey per
  /// device, which is what makes per-wallet derivation unambiguous.
  static const String _passkeyRegisteredKey = 'passkey_registered_v1';

  /// True once [registerCredential] has created a passkey on this device.
  static Future<bool> hasRegisteredCredential() async {
    try {
      return (await SecretStores.local.read(key: _passkeyRegisteredKey))
              .valueOrThrow() ==
          '1';
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> registerCredential() async {
    final generation = _session.generation;
    const rpId = 'keys.breez.technology';
    try {
      // Registration shows the same OS passkey sheet as an assertion.
      final result = await runBiometricPrompt(
        () => _channel.invokeMethod<Uint8List>(
          'registerCredential',
          {
            'rpId': rpId,
            'rpName': 'Kute Wallet',
            'userName': 'kute-wallet-user',
            'userDisplayName': 'Kute Wallet',
          },
        ),
      );
      _session.check(generation);
      // Mark that a passkey now exists on this device so we never mint a
      // second one. NB: we deliberately do NOT persist the credential id
      // here — the raw id the OS hands back at registration doesn't reliably
      // match the one a later assertion resolves against; the id is learned
      // from the first successful assertion in `_runDerive`.
      if (result != null && result.isNotEmpty) {
        try {
          await _session.write(generation, () => SecretStores.local
              .write(key: _passkeyRegisteredKey, value: '1'));
        } catch (_) {}
      }
      _session.check(generation);
      return result;
    } on MissingPluginException {
      throw PlatformException(
        code: 'PRF_UNAVAILABLE',
        message: 'Passkey registration not available on this platform',
      );
    }
  }

  static String _credentialIdKey(String rpId) {
    final digest = sha256.convert(utf8.encode(rpId));
    return '$_credentialIdKeyPrefix$digest';
  }

  static Future<Uint8List?> _loadCredentialId(String rpId) async {
    final hex = (await SecretStores.local.read(key: _credentialIdKey(rpId)))
        .valueOrThrow();
    if (hex == null) return null;
    if (hex.isEmpty || hex.length.isOdd) {
      throw StateError('Stored passkey credential is unreadable.');
    }
    return _hexToBytes(hex);
  }

  static Future<void> _saveCredentialId(
      String rpId, Uint8List id, int generation) async {
    // The credential must be durable before its seed enters either cache.
    await _session.write(generation, () => SecretStores.local.write(
      key: _credentialIdKey(rpId),
      value: _bytesToHex(id),
    ));
  }

  /// Forget the pinned credential id for [rpId] on BOTH stores: the
  /// device-local copy we now use, and any legacy iCloud/Google-synced
  /// copy an older build wrote — otherwise a stale synced id resurrects
  /// the broken pin on the next Keychain sync.
  static Future<void> _deleteCredentialId(String rpId) async {
    final key = _credentialIdKey(rpId);
    try {
      await SecretStores.local.delete(key: key);
    } catch (_) {/* best-effort */}
    try {
      await SecretStores.synced.delete(key: key);
    } catch (_) {/* best-effort cleanup of legacy synced copy */}
  }
}

/// 32 PRF bytes plus their provenance. `fromCeremony` marks bytes an OS
/// assertion produced for THIS call (vs a persisted/in-memory tier);
/// `unpinned` marks that assertion having run without a credential pin,
/// so on a multi-credential device the resolved credential was the
/// user's picker choice rather than a stored id.
class PrfDeriveResult {
  final Uint8List seed;
  final bool fromCeremony;
  final bool unpinned;

  const PrfDeriveResult({
    required this.seed,
    required this.fromCeremony,
    required this.unpinned,
  });
}
