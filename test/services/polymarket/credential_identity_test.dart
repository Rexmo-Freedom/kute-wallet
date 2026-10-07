import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/services/polymarket/credential_identity.dart';

const legacyAddress = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';
const standardAddress = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

void main() {
  test('historical unbound credentials remain usable only for legacy wallets',
      () {
    const historical = {'apiKey': 'fixture', 'nonce': 0};
    expect(
      PolymarketCredentialIdentity.matches(historical,
          ownerAddress: legacyAddress,
          version: EvmDerivationVersion.legacySha256),
      isTrue,
    );
    expect(
      PolymarketCredentialIdentity.matches(historical,
          ownerAddress: standardAddress,
          version: EvmDerivationVersion.standardBip39),
      isFalse,
    );
  });

  for (final version in EvmDerivationVersion.values) {
    test('$version requires both owner and version to match', () {
      final owner = version == EvmDerivationVersion.legacySha256
          ? legacyAddress
          : standardAddress;
      final otherOwner =
          owner == legacyAddress ? standardAddress : legacyAddress;
      final otherVersion = version == EvmDerivationVersion.legacySha256
          ? EvmDerivationVersion.standardBip39
          : EvmDerivationVersion.legacySha256;
      final metadata = PolymarketCredentialIdentity.metadata(
          ownerAddress: owner, version: version);
      expect(
        PolymarketCredentialIdentity.matches(metadata,
            ownerAddress: owner, version: version),
        isTrue,
      );
      expect(
        PolymarketCredentialIdentity.matches(metadata,
            ownerAddress: owner.toLowerCase(), version: version),
        isTrue,
      );
      expect(
        PolymarketCredentialIdentity.matches(metadata,
            ownerAddress: otherOwner, version: version),
        isFalse,
      );
      expect(
        PolymarketCredentialIdentity.matches(metadata,
            ownerAddress: owner, version: otherVersion),
        isFalse,
      );
    });
  }

  test('partial, null, malformed and unknown identity metadata fail closed',
      () {
    for (final record in <Map<String, Object?>>[
      {'ownerAddress': legacyAddress},
      {'evmDerivationVersion': 'legacy-sha256'},
      {'ownerAddress': null, 'evmDerivationVersion': null},
      {'ownerAddress': legacyAddress, 'evmDerivationVersion': 'future-v3'},
      {'ownerAddress': '0x1234', 'evmDerivationVersion': 'legacy-sha256'},
      {'ownerAddress': 123, 'evmDerivationVersion': 'legacy-sha256'},
    ]) {
      for (final version in EvmDerivationVersion.values) {
        expect(
          PolymarketCredentialIdentity.matches(record,
              ownerAddress: legacyAddress, version: version),
          isFalse,
          reason: 'Malformed explicit identity must not fall back to legacy',
        );
      }
    }
  });

  test('invalid expected owner cannot adopt or persist a cache identity', () {
    expect(
      PolymarketCredentialIdentity.matches({},
          ownerAddress: '0x1234', version: EvmDerivationVersion.legacySha256),
      isFalse,
    );
    expect(
      () => PolymarketCredentialIdentity.metadata(
          ownerAddress: '0x1234', version: EvmDerivationVersion.standardBip39),
      throwsFormatException,
    );
  });
}
