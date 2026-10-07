/// The phrase-to-EVM-key contract is part of a wallet's permanent identity.
enum EvmDerivationVersion {
  legacySha256('legacy-sha256'),
  standardBip39('bip39-sha512');

  const EvmDerivationVersion(this.storageValue);

  final String storageValue;

  /// Missing metadata belongs to an existing wallet and must stay legacy.
  /// Unknown explicit versions must never silently select a different key.
  static EvmDerivationVersion fromStorage(Object? value) {
    if (value == null) return legacySha256;
    for (final version in values) {
      if (value == version.storageValue) return version;
    }
    throw const FormatException('Unsupported EVM derivation version');
  }
}
