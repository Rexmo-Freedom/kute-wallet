import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/security/address_guard.dart';

// Spark vectors were encoded independently with the BIP-350 Python
// reference implementation: payload = 0x0a 0x21 || compressed pubkey
// (generator G, and 2G), under each HRP.
const _sparkG =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _spG = 'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _sprtG =
    'sprt1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucd5rgc0';
const _sparkrtG =
    'sparkrt1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc8pt5y4';
const _sparktG =
    'sparkt1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucr4k6m4';
const _spGBech32 =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucv7hm5j';
const _spark2G =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';

const _evmChecksummed = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

void main() {
  group('isEvmAddress', () {
    test('accepts lowercase, uppercase and valid EIP-55 checksums', () {
      expect(isEvmAddress(_evmChecksummed.toLowerCase()), isTrue);
      expect(isEvmAddress('0x${_evmChecksummed.substring(2).toUpperCase()}'),
          isTrue);
      expect(isEvmAddress(_evmChecksummed), isTrue);
      expect(isEvmAddress('0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359'),
          isTrue);
    });

    test('rejects a mixed-case address with a wrong checksum', () {
      expect(isEvmAddress('0x5aAeb6053f3E94C9b9A09f33669435E7Ef1BeAed'),
          isFalse);
    });

    test('rejects wrong lengths and non-hex input', () {
      final hex = _evmChecksummed.substring(2).toLowerCase();
      expect(isEvmAddress('0x${hex.substring(1)}'), isFalse);
      expect(isEvmAddress('0x${hex}a'), isFalse);
      expect(isEvmAddress(hex), isFalse);
      expect(isEvmAddress('0x${hex.substring(1)}g'), isFalse);
      expect(isEvmAddress(' ${_evmChecksummed.toLowerCase()}'), isFalse);
      expect(isEvmAddress(''), isFalse);
    });

    test('sameEvmAddress ignores case but not content', () {
      expect(sameEvmAddress(_evmChecksummed, _evmChecksummed.toLowerCase()),
          isTrue);
      expect(
          sameEvmAddress(_evmChecksummed,
              '0x0000000000000000000000000000000000000001'),
          isFalse);
      expect(sameEvmAddress(_evmChecksummed, 'not-an-address'), isFalse);
    });
  });

  group('bech32 / bech32m (BIP-350 vectors)', () {
    test('valid bech32m strings decode as bech32m', () {
      const valid = [
        'A1LQFN3A',
        'a1lqfn3a',
        'an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6',
        'abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx',
        '11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8',
        'split1checkupstagehandshakeupstreamerranterredcaperredlc445v',
        '?1v759aa',
      ];
      for (final s in valid) {
        final d = decodeBech32(s);
        expect(d, isNotNull, reason: s);
        expect(d!.encoding, Bech32Encoding.bech32m, reason: s);
      }
    });

    test('invalid bech32m strings are rejected', () {
      const invalid = [
        '\u00201xj0phk',
        '\u007f1g6xzxy',
        '\u00801vctc34',
        'an84characterslonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11d6pts4',
        'qyrz8wqd2c9m',
        '1qyrz8wqd2c9m',
        'y1b0jsk6g',
        'lt1igcx5c0',
        'in1muywd',
        'mm1crxm3i',
        'au1s5cgom',
        'M1VUXWEZ',
        '16plkw9',
        '1p2gdwpf',
      ];
      for (final s in invalid) {
        expect(decodeBech32(s), isNull, reason: s);
      }
    });
  });

  group('Spark addresses', () {
    test('mainnet accepts spark and sp HRPs', () {
      expect(isSparkAddress(_sparkG, mainnet: true), isTrue);
      expect(isSparkAddress(_spG, mainnet: true), isTrue);
      expect(isSparkAddress(_spark2G, mainnet: true), isTrue);
      expect(isSparkAddress(_sparkG.toUpperCase(), mainnet: true), isTrue);
      expect(isSparkAddress(_sprtG, mainnet: true), isFalse);
      expect(isSparkAddress(_sparktG, mainnet: true), isFalse);
    });

    test('regtest accepts sprt and sparkrt only', () {
      expect(isSparkAddress(_sprtG, mainnet: false), isTrue);
      expect(isSparkAddress(_sparkrtG, mainnet: false), isTrue);
      expect(isSparkAddress(_spG, mainnet: false), isFalse);
      expect(isSparkAddress(_sparktG, mainnet: false), isFalse);
    });

    test('a bad checksum, bech32 (not bech32m) or foreign input is rejected',
        () {
      final flipped =
          '${_sparkG.substring(0, _sparkG.length - 1)}${_sparkG.endsWith('q') ? 'p' : 'q'}';
      expect(isSparkAddress(flipped, mainnet: true), isFalse);
      expect(isSparkAddress(_spGBech32, mainnet: true), isFalse);
      expect(
          isSparkAddress(
              'lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq9qrsgq357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7mlcwspyetp5h2tztugp9lfyql',
              mainnet: true),
          isFalse);
      expect(isSparkAddress(_evmChecksummed, mainnet: true), isFalse);
      expect(isSparkAddress('sp1test', mainnet: true), isFalse);
      expect(isSparkAddress('', mainnet: true), isFalse);
    });

    test('sameSparkAddress treats sp1 and spark1 as equal', () {
      expect(sameSparkAddress(_spG, _sparkG), isTrue);
      expect(sameSparkAddress(_sparkG, _sparkG), isTrue);
      expect(sameSparkAddress(_sprtG, _sparkrtG), isTrue);
    });

    test('sameSparkAddress rejects other keys, networks and bad input', () {
      expect(sameSparkAddress(_sparkG, _spark2G), isFalse);
      expect(sameSparkAddress(_spG, _sprtG), isFalse);
      expect(sameSparkAddress(_spG, _spGBech32), isFalse);
      expect(sameSparkAddress('sp1test', 'sp1test'), isFalse);
    });
  });

  group('formatMatchesChain', () {
    const btcP2wpkh = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
    const btcP2tr =
        'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0';
    const btcLegacy = '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2';
    const btcP2sh = '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy';
    const tbP2wsh =
        'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7';
    const tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
    const solana = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

    AddressFormatMatch check(String chain, String address,
            {bool mainnet = true}) =>
        formatMatchesChain(chain, address, mainnet: mainnet);

    test('spark', () {
      expect(check('spark', _sparkG), AddressFormatMatch.ok);
      expect(check('SPARK', _spG), AddressFormatMatch.ok);
      expect(check('spark', _evmChecksummed), AddressFormatMatch.mismatch);
      expect(check('spark', btcP2wpkh), AddressFormatMatch.mismatch);
      expect(check('spark', _sprtG), AddressFormatMatch.mismatch);
      expect(check('spark', _sprtG, mainnet: false), AddressFormatMatch.ok);
    });

    test('every EVM chain', () {
      for (final chain in [
        'arc',
        'avalanche',
        'polygon',
        'arbitrum',
        'base',
        'ethereum',
        'optimism',
        'bsc',
        'hyperevm',
        'hypercore',
        'plasma',
        'monad',
        'robinhood',
        'sei',
        'tempo',
      ]) {
        expect(check(chain, _evmChecksummed), AddressFormatMatch.ok,
            reason: chain);
        expect(check(chain, _sparkG), AddressFormatMatch.mismatch,
            reason: chain);
        expect(check(chain, btcP2wpkh), AddressFormatMatch.mismatch,
            reason: chain);
        expect(check(chain, '0x5aAeb6053f3E94C9b9A09f33669435E7Ef1BeAed'),
            AddressFormatMatch.mismatch,
            reason: '$chain must retain the EIP-55 checksum check');
      }
    });

    test('bitcoin segwit, taproot and legacy', () {
      expect(check('bitcoin', btcP2wpkh), AddressFormatMatch.ok);
      expect(check('bitcoin', btcP2wpkh.toUpperCase()), AddressFormatMatch.ok);
      expect(check('bitcoin', btcP2tr), AddressFormatMatch.ok);
      expect(check('bitcoin', btcLegacy), AddressFormatMatch.ok);
      expect(check('bitcoin', btcP2sh), AddressFormatMatch.ok);
      expect(check('bitcoin', tbP2wsh), AddressFormatMatch.mismatch);
      expect(check('bitcoin', tbP2wsh, mainnet: false), AddressFormatMatch.ok);
      expect(check('bitcoin', btcP2wpkh, mainnet: false),
          AddressFormatMatch.mismatch);
      expect(check('bitcoin', '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN3'),
          AddressFormatMatch.mismatch);
      // v1 program with a bech32 checksum, v0 with bech32m.
      expect(
          check('bitcoin',
              'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd'),
          AddressFormatMatch.mismatch);
      expect(check('bitcoin', 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh'),
          AddressFormatMatch.mismatch);
      expect(check('bitcoin', _sparkG), AddressFormatMatch.mismatch);
      expect(check('bitcoin', _evmChecksummed), AddressFormatMatch.mismatch);
    });

    test('tron and solana', () {
      expect(check('tron', tron), AddressFormatMatch.ok);
      expect(check('tron', 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6u'),
          AddressFormatMatch.mismatch);
      expect(check('tron', _evmChecksummed), AddressFormatMatch.mismatch);
      expect(check('solana', solana), AddressFormatMatch.ok);
      expect(check('solana', _evmChecksummed), AddressFormatMatch.mismatch);
      expect(check('solana', btcLegacy), AddressFormatMatch.mismatch);
    });

    test('chains without a rule are unverifiable', () {
      // TON, XRP, Litecoin and Zcash have their own checksum rules now
      // (expanded_address_guard_test.dart); a wrong-family address is a
      // mismatch there, not unverifiable.
      for (final chain in ['lightning', 'newchain', '']) {
        expect(check(chain, _evmChecksummed), AddressFormatMatch.unverifiable,
            reason: chain);
      }
      for (final chain in ['ton', 'xrp', 'litecoin', 'zcash']) {
        expect(check(chain, _evmChecksummed), AddressFormatMatch.mismatch,
            reason: chain);
      }
    });
  });
}
