/// Web only: which secure storage keys are "secret" (live in the seed vault,
/// readable only after unlock) and which are "ordinary" (plain IndexedDB,
/// readable before unlock). Every key the app writes through
/// flutter_secure_storage is listed in [webVaultKeyClasses]; anything not
/// matched is ordinary.
library;

/// One classification rule, for the audit table and the tests.
class VaultKeyClass {
  const VaultKeyClass(this.pattern, {required this.secret, required this.why});

  /// An exact key, or a prefix ending in `*`.
  final String pattern;
  final bool secret;
  final String why;

  bool matches(String key) => pattern.endsWith('*')
      ? key.startsWith(pattern.substring(0, pattern.length - 1))
      : key == pattern;
}

/// The audit of every key the app stores in secure storage.
const List<VaultKeyClass> webVaultKeyClasses = [
  // Seeds and anything that decrypts or derives them.
  VaultKeyClass('v2:wallet:*', secret: true, why: 'wallet recovery phrase'),
  VaultKeyClass('mnemonic_*', secret: true, why: 'PIN-encrypted phrase (V1)'),
  VaultKeyClass('mnemonic', secret: true, why: 'pre-multi-wallet phrase'),
  VaultKeyClass('mnemonic.next', secret: true, why: 'PIN change staging'),
  VaultKeyClass('prf_seed_v1__*', secret: true, why: 'passkey-derived seed'),
  VaultKeyClass('passkey017_seed_v1__*',
      secret: true, why: 'passkey-derived seed cache'),
  VaultKeyClass('pm_api_credentials_*',
      secret: true, why: 'Polymarket CLOB key, secret, passphrase'),
  // PIN material. On web none of these is written any more (the vault tag
  // verifies the PIN and biometrics use WebAuthn PRF); a stray write still
  // lands in the vault, never in plain storage.
  VaultKeyClass('pin_hash', secret: true, why: 'PIN hash (offline guessable)'),
  VaultKeyClass('pin', secret: true, why: 'legacy plaintext PIN'),
  VaultKeyClass('biometric_pin', secret: true, why: 'raw PIN copy'),
  // Ordinary: public data, flags, ids and counters, some needed before the
  // PIN is entered.
  VaultKeyClass('kute.binding.v1', secret: false, why: 'install binding id'),
  VaultKeyClass('failed_pin_attempts', secret: false, why: 'lockout counter'),
  VaultKeyClass('lockout_until', secret: false, why: 'lockout deadline'),
  VaultKeyClass('xpub_*', secret: false, why: 'watch-only public key'),
  VaultKeyClass('external_address_*', secret: false, why: 'public address'),
  VaultKeyClass('standing_order:*',
      secret: false,
      why: 'one signed order the user approved; not a key, cannot sign '
          'anything else'),
  VaultKeyClass('pm_proxy_wallet_*', secret: false, why: 'public address'),
  VaultKeyClass('pm_setup_verified_*', secret: false, why: 'flag'),
  VaultKeyClass('prf_credential_id_v1__*', secret: false, why: 'credential id'),
  VaultKeyClass('passkey_*', secret: false, why: 'labels, flags, ids'),
  VaultKeyClass('passkey017_recovery_manifest_v1',
      secret: false, why: 'retired manifest, delete only'),
  VaultKeyClass('hl_*', secret: false, why: 'Hyperliquid flags'),
  VaultKeyClass('kute_venue_owner_v1:*', secret: false, why: 'link flags'),
  VaultKeyClass('kute_affiliate_*',
      secret: false, why: 'referral session and code (no wallet power)'),
  VaultKeyClass('kute_pending_referrer', secret: false, why: 'referral code'),
  VaultKeyClass('kute_install_attribution_*', secret: false, why: 'flags'),
  VaultKeyClass('kute_device_uuid', secret: false, why: 'analytics id'),
  VaultKeyClass('kute_aliased_*', secret: false, why: 'analytics flags'),
  VaultKeyClass('analytics_*', secret: false, why: 'analytics counters'),
  VaultKeyClass('bio_domain_state_v1', secret: false, why: 'biometry hash'),
  VaultKeyClass('reviewDone', secret: false, why: 'flag'),
  VaultKeyClass('fcmToken', secret: false, why: 'push token'),
  VaultKeyClass('backendJwt', secret: false, why: 'legacy, read only'),
];

/// True when [key] belongs in the seed vault. Secret rules win over the
/// ordinary ones, and PIN-change staging copies (`{key}.next`) of a secret
/// key are secret too.
bool isVaultSecretKey(String key) {
  final base = key.endsWith('.next') ? key.substring(0, key.length - 5) : key;
  for (final rule in webVaultKeyClasses) {
    if (rule.secret && (rule.matches(key) || rule.matches(base))) return true;
  }
  return false;
}

/// Key names that must never be written to localStorage or sessionStorage
/// by anything, under any prefix.
bool isKnownSecretKeyName(String storageKey) {
  // flutter_secure_storage_web writes `<publicKey>.<key>`; the raw AES key
  // itself sits under the bare publicKey.
  if (storageKey == 'FlutterSecureStorage') return true;
  final dot = storageKey.indexOf('.');
  final candidates = [
    storageKey,
    if (dot > 0) storageKey.substring(dot + 1),
  ];
  return candidates.any(isVaultSecretKey);
}

final RegExp _word = RegExp(r'^[a-z]{3,8}$');

/// A value that looks like a recovery phrase (12 to 24 short lowercase
/// words), alone or inside JSON. Raw hex keys are not matched: hashes and
/// ids look the same. Used by the debug guards; a false positive only
/// fails a debug assertion.
bool looksLikeSecretValue(String value) {
  final trimmed = value.trim();
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length >= 12 &&
      words.length <= 24 &&
      words.length % 3 == 0 &&
      words.every(_word.hasMatch)) {
    return true;
  }
  // A phrase inside JSON or another wrapper.
  final embedded = RegExp(r'([a-z]{3,8} ){11,23}[a-z]{3,8}');
  return embedded.hasMatch(trimmed);
}
