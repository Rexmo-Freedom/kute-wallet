// The web build's pure-Dart key work against published vectors: BIP39
// (Trezor's vectors, passphrase "TREZOR"), BIP84 and BIP86 account keys.
// The addresses of those accounts come from bdk-wasm itself (BDK's own
// descriptor templates), so they are not repeated here.

import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/onchain/web/web_bitcoin_keys.dart';

Uint8List _hex(String value) => Uint8List.fromList(BytesUtils.fromHexString(value));

/// SLIP-132 zpub/ypub to the plain xpub BDK prints: same key, version
/// bytes 0488b21e.
String _asXpub(String key) {
  final bytes = Base58Decoder.checkDecode(key);
  return Base58Encoder.checkEncode([0x04, 0x88, 0xb2, 0x1e, ...bytes.sublist(4)]);
}

const _abandon =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

void main() {
  group('BIP39', () {
    const vectors = [
      (
        '00000000000000000000000000000000',
        _abandon,
        'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04'
      ),
      (
        '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f',
        'legal winner thank year wave sausage worth useful legal winner thank yellow',
        '2e8905819b8723fe2c1d161860e5ee1830318dbf49a83bd451cfb8440c28bd6fa457fe1296106559a3c80937a1c1069be3a3a5bd381ee6260e8d9739fce1f607'
      ),
      (
        '80808080808080808080808080808080',
        'letter advice cage absurd amount doctor acoustic avoid letter advice cage above',
        'd71de856f81a8acc65e6fc851a38d4d7ec216fd0796d0a6827a3ad6ed5511a30fa280f12eb2e47ed2ac03b5c462a0358d18d69fe4f985ec81778c1b370b652a8'
      ),
      (
        'ffffffffffffffffffffffffffffffff',
        'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong',
        'ac27495480225222079d7be181583751e86f571027b0497b5b5d11218e0a8a13332572917f0f8e5a589620c6f15b11c61dee327651a14c34e18231052e48c069'
      ),
      (
        '9e885d952ad362caeb4efe34a8e91bd2',
        'ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic',
        '274ddc525802f7c828d8ef7ddbcdc5304e87ac3535913611fbbfa986d0c9e5476c91689f9c8a54fd55bd38606aa6a8595ad213d4c9c9f9aca3fb217069a41028'
      ),
      (
        '0000000000000000000000000000000000000000000000000000000000000000',
        'abandon abandon abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon abandon abandon art',
        'bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd3097170af7a4d73245cafa9c3cca8d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8'
      ),
    ];
    for (final (entropy, phrase, seed) in vectors) {
      test('${phrase.split(' ').first}… (${entropy.length ~/ 2} bytes)', () {
        expect(WebBitcoinKeys.mnemonicFromEntropy(_hex(entropy)), phrase);
        expect(WebBitcoinKeys.validateMnemonic(phrase), isTrue);
        expect(
            BytesUtils.toHexString(
                WebBitcoinKeys.seed(phrase, passphrase: 'TREZOR')),
            seed);
      });
    }

    test('validation follows rust-bip39', () {
      // Bad checksum, unknown word, wrong count, uppercase.
      expect(WebBitcoinKeys.validateMnemonic(_abandon.replaceFirst('about', 'abandon')), isFalse);
      expect(WebBitcoinKeys.validateMnemonic(_abandon.replaceFirst('about', 'bitcoins')), isFalse);
      expect(WebBitcoinKeys.validateMnemonic(_abandon.substring(8)), isFalse);
      expect(WebBitcoinKeys.validateMnemonic(_abandon.toUpperCase()), isFalse);
      // Any whitespace separates words; the seed uses single spaces.
      final spaced = '  ${_abandon.replaceAll(' ', ' \n\t ')}  ';
      expect(WebBitcoinKeys.validateMnemonic(spaced), isTrue);
      expect(WebBitcoinKeys.seed(spaced), WebBitcoinKeys.seed(_abandon));
    });

    test('generates valid 12-word phrases', () {
      for (var i = 0; i < 20; i++) {
        final phrase = WebBitcoinKeys.generateMnemonic();
        expect(phrase.split(' '), hasLength(12));
        expect(WebBitcoinKeys.validateMnemonic(phrase), isTrue);
      }
    });

    test('rejects entropy BIP39 does not define', () {
      expect(() => WebBitcoinKeys.mnemonicFromEntropy(Uint8List(15)),
          throwsArgumentError);
    });
  });

  group('account keys', () {
    final seed = WebBitcoinKeys.seed(_abandon);

    test('BIP84 account 0', () {
      expect(
          WebBitcoinKeys.accountXpub(seed, purpose: 84, mainnet: true),
          _asXpub('zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3'
              'EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs'));
    });

    test('BIP86 account 0', () {
      expect(
          WebBitcoinKeys.accountXpub(seed, purpose: 86, mainnet: true),
          'xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoG'
          'Vky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ');
    });

    test('BIP49 account 0', () {
      expect(
          WebBitcoinKeys.accountXpub(seed, purpose: 49, mainnet: true),
          _asXpub('ypub6Ww3ibxVfGzLrAH1PNcjyAWenMTbbAosGNB6VvmSEgytSER9azLDWC'
              'xoJwW7Ke7icmizBMXrzBx9979FfaHxHcrArf3zbeJJJUZPf663zsP'));
    });

    test('off mainnet: coin 1, tpub', () {
      expect(WebBitcoinKeys.accountXpub(seed, purpose: 84, mainnet: false),
          startsWith('tpub'));
      expect(WebBitcoinKeys.accountXpub(seed, purpose: 84, mainnet: false),
          isNot(WebBitcoinKeys.accountXpub(seed, purpose: 84, mainnet: true)));
    });
  });
}
