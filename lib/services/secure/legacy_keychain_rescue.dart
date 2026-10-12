import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:kute/models/settings_model.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/tracking_service.dart';

/// Read-only Keychain lookup that ignores the item's accessibility.
///
/// iOS wallets created on 1.x builds between 2026-03-12 and 2026-06-09
/// stored their items with `kSecAttrAccessibleAfterFirstUnlock` instead of
/// `...ThisDeviceOnly`. flutter_secure_storage 10 puts the configured
/// accessibility into every read query, so those items read as absent and
/// a cold start classifies the phone as `secretsMissing`. This lookup goes
/// through `SecurityNativePlugin` with no `kSecAttrAccessible` in the
/// query. It never writes or deletes. Android has no such items: every
/// call answers "absent".
abstract class LegacyKeychainLookup {
  Future<SecretRead> read(String account, {bool synchronizable = false});

  /// Account names starting with [prefix]. Attributes only; no item data
  /// is read.
  Future<List<String>> listAccounts(
      {required String prefix, bool synchronizable = false});
}

class NativeLegacyKeychainLookup implements LegacyKeychainLookup {
  const NativeLegacyKeychainLookup({
    this.platform,
    this.service = AppleOptions.defaultAccountName,
  });

  static const channel = KeychainLocal.channel;

  final TargetPlatform? platform;
  final String service;

  bool get _native => (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  @override
  Future<SecretRead> read(String account, {bool synchronizable = false}) async {
    if (!_native) return const SecretAbsent();
    try {
      final value = await channel.invokeMethod<String>('readLegacyItem', {
        'service': service,
        'account': account,
        'synchronizable': synchronizable,
      });
      return value == null ? const SecretAbsent() : SecretPresent(value);
    } catch (error, stackTrace) {
      return SecretFailed(
          classifySecretError(error, platform: platform), error, stackTrace);
    }
  }

  @override
  Future<List<String>> listAccounts(
      {required String prefix, bool synchronizable = false}) async {
    if (!_native) return const [];
    try {
      final accounts =
          await channel.invokeListMethod<String>('listLegacyAccounts', {
        'service': service,
        'prefix': prefix,
        'synchronizable': synchronizable,
      });
      return accounts ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

/// Where an old copy was written.
enum LegacyCopyEra {
  /// `mnemonic_{id}`: PIN-encrypted (`PinEncryptionHelper`), 1.x.
  a,

  /// `v2:wallet:{id}.mnemonic`: plaintext, device-local, 1.x.
  b,

  /// `v2:wallet:{id}.mnemonic` in iCloud Keychain (synchronizable).
  icloud,
}

/// One wallet whose old copies this phone still holds but the current
/// store cannot read. Key names only; nothing is decrypted to build it.
@immutable
class LegacyWalletCopy {
  const LegacyWalletCopy({
    required this.walletId,
    this.wallet,
    this.plain = false,
    this.encrypted = false,
    this.icloud = false,
  });

  final String walletId;

  /// The Hive wallet record, when the wallet is still listed.
  final WalletConfig? wallet;

  /// Era B copy under the legacy accessibility.
  final bool plain;

  /// Era A copy under the legacy accessibility.
  final bool encrypted;

  /// Synced copy, with no readable local one.
  final bool icloud;

  /// The copy a restore reads first: plain, then iCloud, then encrypted.
  LegacyCopyEra get preferredEra => plain
      ? LegacyCopyEra.b
      : icloud
          ? LegacyCopyEra.icloud
          : LegacyCopyEra.a;

  /// A copy readable without the PIN exists.
  bool get needsPin => !plain && !icloud;
}

/// What the lookup found.
class LegacyRescueScan {
  const LegacyRescueScan({
    required this.copies,
    required this.pinHash,
    required this.legacyPin,
    required this.biometricPin,
  });

  static const empty = LegacyRescueScan(
      copies: [], pinHash: false, legacyPin: false, biometricPin: false);

  final List<LegacyWalletCopy> copies;

  /// An old `pin_hash` exists under the legacy accessibility.
  final bool pinHash;

  /// An old plaintext `pin` exists under the legacy accessibility.
  final bool legacyPin;

  /// An old `biometric_pin` exists under the legacy accessibility.
  final bool biometricPin;

  bool get found => copies.isNotEmpty;
  bool get hasPinMaterial => pinHash || legacyPin;
  int get plainCount => copies.where((c) => c.plain).length;
  int get encryptedCount => copies.where((c) => c.encrypted).length;
  int get icloudCount => copies.where((c) => c.icloud).length;
}

/// How a phrase found on the phone was checked before it was re-saved.
/// `address`: it derives to the wallet's stored recovery check address;
/// `proxy`: it derives to the cached Polymarket deposit wallet; `none`: the
/// phone holds no public data for this wallet, so only the BIP39 check ran.
enum LegacyCopyCheck { address, proxy, none }

/// Why a copy was not restored.
enum LegacyRescueFailure {
  invalidPhrase,
  mismatch,
  wrongPin,
  readFailed,
  writeFailed,
}

class LegacyRescueException implements Exception {
  const LegacyRescueException(this.reason);
  final LegacyRescueFailure reason;
  @override
  String toString() => 'LegacyRescueException(${reason.name})';
}

/// Outcome of the silent startup path.
enum StartupRescueOutcome {
  /// Nothing usable was found: open the restore screen as before.
  nothing,

  /// PIN material was re-saved: the normal PIN screen can open. Plain
  /// copies were re-saved; encrypted-only wallets finish on PIN entry.
  pinScreen,
}

typedef PhraseValidator = Future<bool> Function(String mnemonic);
typedef BlobDecryptor = Future<String> Function(String blob, String pin);
typedef AddressDeriver = Future<String> Function(
    String mnemonic, WalletConfig wallet);
typedef ProxyDeriver = Future<Set<String>> Function(String mnemonic);

/// Finds and re-saves wallet copies that an earlier build stored under the
/// legacy accessibility, so the current store can read them again.
///
/// Rules: nothing here runs on wallet creation; old copies are never
/// deleted; a re-save is `writeLocalOnly` on the same account, which
/// updates the item in place (a synced twin is never touched); balances are
/// never moved. Analytics carry counts and outcomes only.
class LegacyKeychainRescue {
  LegacyKeychainRescue({
    LegacyKeychainLookup? lookup,
    SecretStore? store,
    SecretStore? syncedStore,
    PhraseValidator? validate,
    AddressDeriver? deriveAddress,
    ProxyDeriver? deriveProxyWallets,
    Future<String?> Function(String walletId)? cachedProxyWallet,
    BlobDecryptor? decrypt,
    bool? isCupertino,
  })  : _lookup = lookup ?? const NativeLegacyKeychainLookup(),
        _store = store ?? SecretStores.local,
        _synced = syncedStore ?? SecretStores.synced,
        _validate = validate ??
            ((m) => NativeBitcoinPrimitives.instance.validateMnemonic(m)),
        _decrypt = decrypt ?? PinEncryptionHelper.decryptDataAsync,
        _deriveAddress = deriveAddress ??
            ((m, w) => RecoveryCheck.derive(m, version: w.evmDerivationVersion)),
        _deriveProxyWallets = deriveProxyWallets,
        _cachedProxyWallet = cachedProxyWallet,
        _isCupertino =
            isCupertino ?? defaultTargetPlatform == TargetPlatform.iOS;

  final LegacyKeychainLookup _lookup;
  final SecretStore _store;
  final SecretStore _synced;
  final PhraseValidator _validate;
  final BlobDecryptor _decrypt;
  final AddressDeriver _deriveAddress;
  final ProxyDeriver? _deriveProxyWallets;
  final Future<String?> Function(String walletId)? _cachedProxyWallet;
  final bool _isCupertino;

  static const String _v2Prefix = 'v2:wallet:';
  static const String _v2Suffix = '.mnemonic';
  static const String _v1Prefix = 'mnemonic_';

  static String v2Key(String walletId) => '$_v2Prefix$walletId$_v2Suffix';
  static String v1Key(String walletId) => '$_v1Prefix$walletId';

  /// Wallet ids of the encrypted-only copies the startup path left for the
  /// PIN screen. `AuthModel.checkPin` finishes them on a matching PIN.
  static Future<void> Function(String pin)? _pendingAfterPin;

  @visibleForTesting
  static bool get hasPendingAfterPin => _pendingAfterPin != null;

  @visibleForTesting
  static void debugReset() => _pendingAfterPin = null;

  /// Runs the rescue the startup path left for the PIN screen, once, with
  /// the PIN that just verified. Never throws.
  static Future<void> runPendingWithPin(String pin) async {
    final pending = _pendingAfterPin;
    if (pending == null) return;
    _pendingAfterPin = null;
    try {
      await pending(pin);
    } catch (_) {}
  }

  // ───────────────────────── lookup ─────────────────────────

  Future<bool> _readableNow(SecretStore store, String key) async =>
      switch (await store.read(key: key)) {
        SecretPresent(:final value) => value.isNotEmpty,
        _ => false,
      };

  /// Looks up old copies for [wallets] (stored-seed wallets only) and, when
  /// [includeUnlisted] is set, for wallet ids the Keychain still names but
  /// Hive no longer lists. Attributes only: account names are listed and
  /// compared with what the current store can read; no item data is
  /// fetched to build the result.
  Future<LegacyRescueScan> scan(
    List<WalletConfig> wallets, {
    required String source,
    bool includeUnlisted = false,
  }) async {
    if (!_isCupertino) return LegacyRescueScan.empty;
    try {
      final listed = {
        for (final w in wallets.where(RecoveryCheck.holdsStoredSeed)) w.id: w,
      };
      final local = <String>{
        ...await _lookup.listAccounts(prefix: _v2Prefix),
        ...await _lookup.listAccounts(prefix: _v1Prefix),
        ...await _lookup.listAccounts(prefix: 'pin'),
        ...await _lookup.listAccounts(prefix: 'biometric_pin'),
      };
      final synced = includeUnlisted
          ? (await _lookup.listAccounts(prefix: _v2Prefix, synchronizable: true))
              .toSet()
          : const <String>{};
      String? v2WalletId(String account) =>
          account.startsWith(_v2Prefix) && account.endsWith(_v2Suffix)
              ? account.substring(
                  _v2Prefix.length, account.length - _v2Suffix.length)
              : null;

      final ids = <String>{...listed.keys};
      if (includeUnlisted) {
        for (final account in local) {
          final v2Id = v2WalletId(account);
          if (v2Id != null) ids.add(v2Id);
          if (account.startsWith(_v1Prefix)) {
            final id = account.substring(_v1Prefix.length);
            if (id.isNotEmpty && !id.endsWith('.next')) ids.add(id);
          }
        }
        for (final account in synced) {
          final v2Id = v2WalletId(account);
          if (v2Id != null) ids.add(v2Id);
        }
      }
      final copies = <LegacyWalletCopy>[];
      for (final id in ids) {
        final v2 = v2Key(id);
        if (await _readableNow(_store, v2)) continue;
        final plain = local.contains(v2);
        final encrypted =
            local.contains(v1Key(id)) && !await _readableNow(_store, v1Key(id));
        final icloud = synced.contains(v2);
        if (!plain && !encrypted && !icloud) continue;
        copies.add(LegacyWalletCopy(
          walletId: id,
          wallet: listed[id],
          plain: plain,
          encrypted: encrypted,
          icloud: icloud,
        ));
      }
      Future<bool> legacyOnly(String key) async =>
          local.contains(key) && !await _readableNow(_store, key);
      final scan = LegacyRescueScan(
        copies: copies,
        pinHash: await legacyOnly('pin_hash'),
        legacyPin: await legacyOnly('pin'),
        biometricPin: await legacyOnly('biometric_pin'),
      );
      TrackingService.seedRescueLookupCompleted(
        source: source,
        outcome: scan.found || scan.hasPinMaterial ? 'found' : 'none',
        plain: scan.plainCount,
        encrypted: scan.encryptedCount,
        icloud: scan.icloudCount,
      );
      return scan;
    } catch (_) {
      TrackingService.seedRescueLookupCompleted(
          source: source, outcome: 'failed');
      return LegacyRescueScan.empty;
    }
  }

  // ───────────────────────── validation ─────────────────────────

  /// BIP39 first, then whatever public data the phone still holds for the
  /// wallet. Throws [LegacyRescueException] on an invalid or mismatching
  /// phrase; a phrase with nothing to compare against passes as
  /// [LegacyCopyCheck.none].
  Future<LegacyCopyCheck> validate(String phrase, WalletConfig? wallet) async {
    final normalized = RecoveryCheck.normalize(phrase);
    if (normalized.isEmpty || !await _validate(normalized)) {
      throw const LegacyRescueException(LegacyRescueFailure.invalidPhrase);
    }
    if (wallet == null) return LegacyCopyCheck.none;
    final stored = wallet.recoveryCheckAddress;
    if (stored != null) {
      final derived = await _deriveAddress(normalized, wallet);
      if (!RecoveryCheck.matches(stored, derived)) {
        throw const LegacyRescueException(LegacyRescueFailure.mismatch);
      }
      return LegacyCopyCheck.address;
    }
    final proxy = await _readCachedProxyWallet(wallet.id);
    final derive = _deriveProxyWallets;
    if (proxy != null && derive != null) {
      try {
        final candidates = await derive(normalized);
        if (candidates.any((a) => RecoveryCheck.matches(proxy, a))) {
          return LegacyCopyCheck.proxy;
        }
      } catch (_) {}
      // A cached proxy that matches no derivation is not a mismatch: it may
      // be a Safe or a factory wallet this check cannot derive offline.
    }
    return LegacyCopyCheck.none;
  }

  Future<String?> _readCachedProxyWallet(String walletId) async {
    final custom = _cachedProxyWallet;
    if (custom != null) return custom(walletId);
    final key = 'pm_proxy_wallet_$walletId';
    final current = await _store.read(key: key);
    if (current is SecretPresent && current.value.isNotEmpty) {
      return current.value;
    }
    final legacy = await _lookup.read(key);
    return legacy is SecretPresent && legacy.value.isNotEmpty
        ? legacy.value
        : null;
  }

  // ───────────────────────── reads ─────────────────────────

  /// The plaintext phrase of a copy that needs no PIN.
  Future<String> readPlain(LegacyWalletCopy copy) async {
    final key = v2Key(copy.walletId);
    final read = copy.plain
        ? await _lookup.read(key)
        : copy.icloud
            ? await _synced.read(key: key)
            : const SecretAbsent();
    return switch (read) {
      SecretPresent(:final value) when value.isNotEmpty => value,
      _ => throw const LegacyRescueException(LegacyRescueFailure.readFailed),
    };
  }

  /// Decrypts the Era A copy with [pin]. The stored blob is a
  /// `PinEncryptionHelper` blob (`v2:` PBKDF2 + AES-GCM, or the older
  /// SHA-256 + AES-CBC form); a wrong PIN fails the authentication tag or
  /// the padding.
  Future<String> readEncrypted(LegacyWalletCopy copy, String pin) async {
    final blob = await _lookup.read(v1Key(copy.walletId));
    if (blob is! SecretPresent || blob.value.isEmpty) {
      throw const LegacyRescueException(LegacyRescueFailure.readFailed);
    }
    try {
      return await _decrypt(blob.value, pin);
    } catch (_) {
      throw const LegacyRescueException(LegacyRescueFailure.wrongPin);
    }
  }

  /// The old `pin_hash` (or plaintext `pin`) verifies [pin].
  Future<bool> legacyPinMatches(String pin) async {
    final hash = await _lookup.read('pin_hash');
    if (hash is SecretPresent && hash.value.isNotEmpty) {
      return PinHashHelper.verifyPinAsync(pin, hash.value);
    }
    final plain = await _lookup.read('pin');
    return plain is SecretPresent && plain.value == pin;
  }

  /// PINs to try before asking: the one typed this session and a stored
  /// `biometric_pin` (current store, then legacy accessibility).
  Future<List<String>> silentPinCandidates({String? typedPin}) async {
    final pins = <String>[];
    if (typedPin != null && typedPin.isNotEmpty) pins.add(typedPin);
    for (final read in [
      await _store.read(key: 'biometric_pin'),
      await _lookup.read('biometric_pin'),
    ]) {
      if (read is SecretPresent &&
          read.value.isNotEmpty &&
          !pins.contains(read.value)) {
        pins.add(read.value);
      }
    }
    return pins;
  }

  // ───────────────────────── re-saves ─────────────────────────

  /// Re-saves a legacy item under the same account so the current store
  /// can read it. The value is read natively and written back with
  /// `writeLocalOnly` (an in-place update). Returns false when there was
  /// nothing to re-save. Never deletes.
  Future<bool> _resave(String key) async {
    final legacy = await _lookup.read(key);
    if (legacy is! SecretPresent || legacy.value.isEmpty) return false;
    try {
      await _store.writeLocalOnly(key: key, value: legacy.value);
      return true;
    } catch (_) {
      throw const LegacyRescueException(LegacyRescueFailure.writeFailed);
    }
  }

  /// Re-saves the old `pin_hash`, `pin` and `biometric_pin` where present.
  /// Returns true when PIN material is now readable.
  Future<bool> resavePinMaterial(LegacyRescueScan scan) async {
    var restored = false;
    if (scan.pinHash) restored |= await _resave('pin_hash');
    if (scan.legacyPin) restored |= await _resave('pin');
    if (scan.biometricPin) {
      try {
        await _resave('biometric_pin');
      } on LegacyRescueException {
        // Biometric unlock is a convenience; the PIN still works.
      }
    }
    return restored;
  }

  /// Validates and re-saves the plain copy of [copy] for its own wallet id.
  Future<LegacyCopyCheck> restorePlainInPlace(LegacyWalletCopy copy,
      {required String source}) async {
    final era = copy.plain ? LegacyCopyEra.b : LegacyCopyEra.icloud;
    try {
      final phrase = await readPlain(copy);
      final check = await validate(phrase, copy.wallet);
      if (copy.plain) {
        await _resave(v2Key(copy.walletId));
      } else {
        try {
          await _store.writeLocalOnly(
              key: v2Key(copy.walletId), value: phrase);
        } catch (_) {
          throw const LegacyRescueException(LegacyRescueFailure.writeFailed);
        }
      }
      TrackingService.seedRescueRestored(
          source: source, era: era.name, check: check.name);
      return check;
    } on LegacyRescueException catch (e) {
      TrackingService.seedRescueFailed(
          source: source, era: era.name, reason: e.reason.name);
      rethrow;
    }
  }

  /// Decrypts the Era A copy of [copy] with [pin], validates it and saves
  /// it as this wallet's V2 copy; the V1 blob is re-saved in place too so
  /// `changePin` keeps seeing it. Nothing is deleted.
  Future<LegacyCopyCheck> restoreEncryptedInPlace(
    LegacyWalletCopy copy,
    String pin, {
    required String source,
  }) async {
    try {
      final phrase = await readEncrypted(copy, pin);
      final check = await validate(phrase, copy.wallet);
      try {
        await _store.writeLocalOnly(
            key: v2Key(copy.walletId), value: RecoveryCheck.normalize(phrase));
        await _resave(v1Key(copy.walletId));
      } catch (_) {
        throw const LegacyRescueException(LegacyRescueFailure.writeFailed);
      }
      TrackingService.seedRescueRestored(
          source: source, era: LegacyCopyEra.a.name, check: check.name);
      return check;
    } on LegacyRescueException catch (e) {
      TrackingService.seedRescueFailed(
          source: source, era: LegacyCopyEra.a.name, reason: e.reason.name);
      rethrow;
    }
  }

  // ───────────────────────── flows ─────────────────────────

  /// Applies a [scan] to the wallets it names: plain copies are validated
  /// and re-saved, PIN material is re-saved, and encrypted-only wallets
  /// are left for the next matching PIN entry. Returns the wallet ids that
  /// still wait for the PIN.
  Future<Set<String>> apply(LegacyRescueScan scan,
      {required String source}) async {
    final pendingPin = <String>{};
    for (final copy in scan.copies.where((c) => c.wallet != null)) {
      if (copy.plain) {
        try {
          await restorePlainInPlace(copy, source: source);
          continue;
        } on LegacyRescueException {
          // Fall through to the encrypted copy when there is one.
        }
      }
      if (copy.encrypted) pendingPin.add(copy.walletId);
    }
    var pinMaterial = false;
    try {
      pinMaterial = await resavePinMaterial(scan);
    } on LegacyRescueException catch (e) {
      TrackingService.seedRescueFailed(
          source: source, era: 'pin', reason: e.reason.name);
    }
    if (pendingPin.isNotEmpty && pinMaterial) {
      final copies = {
        for (final c in scan.copies)
          if (pendingPin.contains(c.walletId)) c.walletId: c,
      };
      _pendingAfterPin = (pin) async {
        for (final copy in copies.values) {
          try {
            await restoreEncryptedInPlace(copy, pin, source: source);
          } on LegacyRescueException {
            // Reported; the next PIN entry does not retry (the pending
            // hook is consumed), and the restore screen stays reachable.
          }
        }
      };
    }
    return pendingPin;
  }

  /// The silent startup path, run only when the cold-start classification
  /// would be `secretsMissing`. Returns [StartupRescueOutcome.pinScreen]
  /// when PIN material was re-saved, so the splash can classify again and
  /// open the normal PIN screen.
  Future<StartupRescueOutcome> rescueAtStartup(
      List<WalletConfig> wallets) async {
    const source = 'startup';
    final found = await scan(wallets, source: source);
    if (!found.found && !found.hasPinMaterial) {
      return StartupRescueOutcome.nothing;
    }
    await apply(found, source: source);
    final pinReadable = await _readableNow(_store, 'pin_hash') ||
        await _readableNow(_store, 'pin');
    return pinReadable
        ? StartupRescueOutcome.pinScreen
        : StartupRescueOutcome.nothing;
  }
}
