import 'package:kute/models/evm_derivation_version.dart';

/// Binds cached CLOB credentials to the owner key that provisioned them.
/// This is the EOA identity, independently of an API key's funder binding.
abstract final class PolymarketCredentialIdentity {
  static final _address = RegExp(r'^0x[0-9a-fA-F]{40}$');

  static bool matches(
    Map<dynamic, dynamic> record, {
    required String ownerAddress,
    required EvmDerivationVersion version,
  }) {
    if (!_address.hasMatch(ownerAddress)) return false;
    final hasOwner = record.containsKey('ownerAddress');
    final hasVersion = record.containsKey('evmDerivationVersion');
    if (!hasOwner && !hasVersion) {
      // Historical entries have neither field. Never reuse those entries
      // for a new standard wallet, even when the storage ID was reused.
      return version == EvmDerivationVersion.legacySha256;
    }
    if (!hasOwner || !hasVersion) return false;
    final storedOwner = record['ownerAddress'];
    return storedOwner is String &&
        _address.hasMatch(storedOwner) &&
        storedOwner.toLowerCase() == ownerAddress.toLowerCase() &&
        record['evmDerivationVersion'] == version.storageValue;
  }

  static Map<String, String> metadata({
    required String ownerAddress,
    required EvmDerivationVersion version,
  }) {
    if (!_address.hasMatch(ownerAddress)) {
      throw const FormatException('Invalid credential owner address');
    }
    return {
      'ownerAddress': ownerAddress.toLowerCase(),
      'evmDerivationVersion': version.storageValue,
    };
  }
}
