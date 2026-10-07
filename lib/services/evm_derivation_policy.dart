import 'package:kute/models/evm_derivation_version.dart';

// This marker is part of newly created passkey labels and therefore survives
// SDK label discovery on a fresh device. Never rewrite an existing label: it
// also selects the passkey-derived seed.
const _standardPasskeyPrefix = 'kute:evm:bip39-sha512:v1:';

String standardEvmPasskeyLabel(String label) => '$_standardPasskeyPrefix$label';

EvmDerivationVersion passkeyEvmDerivationVersion(String label) {
  if (label.startsWith(_standardPasskeyPrefix)) {
    return EvmDerivationVersion.standardBip39;
  }
  if (label.startsWith('kute:evm:')) {
    throw const FormatException('Unsupported passkey EVM derivation version');
  }
  return EvmDerivationVersion.legacySha256;
}

String displayPasskeyLabel(String label) => label.startsWith(_standardPasskeyPrefix)
    ? label.substring(_standardPasskeyPrefix.length)
    : label;
