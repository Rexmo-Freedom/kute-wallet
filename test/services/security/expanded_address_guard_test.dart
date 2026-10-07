import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';

void main() {
  // Independent Python Base58Check and CRC16 fixtures, payload bytes 0..19/31.
  const vectors = {
    'litecoin': [
      'LKDyUEtTR1HXamkiEphisSiBJu6o3ZPE34',
      'M7uBSTV2qNDHDe2tHfNMqhFkZucgRMpJQk'
    ],
    'zcash': [
      't1HsdDMzmJfq4vc7T17XYjEkLMLvbgM1fCi',
      't3JZe8uVCra9T1mot8DC99s7GVsDKFy2Xa2'
    ],
    'ton': [
      'EQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHx2j',
      'UQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH0Bm'
    ],
    'xrp': ['rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh'],
  };
  for (final row in vectors.entries) {
    test('${row.key} accepts checksummed addresses and rejects corruption', () {
      for (final address in row.value) {
        expect(formatMatchesChain(row.key, address, mainnet: true),
            AddressFormatMatch.ok);
        expect(
            formatMatchesChain(
                row.key, '${address.substring(0, address.length - 1)}0',
                mainnet: true),
            AddressFormatMatch.mismatch);
      }
    });
  }
  test('rejects testnet TON, raw TON and ambiguous Bitcoin P2SH on Litecoin',
      () {
    for (final address in [
      'kQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6Yp',
      '0:${'0' * 64}'
    ]) {
      expect(formatMatchesChain('ton', address, mainnet: true),
          AddressFormatMatch.mismatch);
    }
    expect(
        formatMatchesChain('litecoin', '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
            mainnet: true),
        AddressFormatMatch.mismatch);
  });
  test('dollar send validates expanded EVM chains and actual checksums', () {
    const address = '0x52908400098527886E0F7030069857D2E4169EE7';
    for (final chain in ['avalanche', 'hyperevm', 'monad', 'sei', 'tempo']) {
      expect(usdSendChainAcceptsAddress(chain, address), isTrue);
      expect(
          usdSendChainAcceptsAddress(
              chain, '0x52908400098527886E0F7030069857D2E4169Ee7'),
          isFalse);
    }
    expect(
        usdSendChainAcceptsAddress('zcash', vectors['zcash']!.first), isTrue);
    expect(usdSendChainAcceptsAddress('litecoin', vectors['zcash']!.first),
        isFalse);
    // Destination memo contracts are not part of the generic quote request.
    expect(usdSendChainAcceptsAddress('xrp', vectors['xrp']!.first), isFalse);
  });
}
