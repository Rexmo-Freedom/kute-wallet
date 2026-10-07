import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/bitcoin_config_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show HdWallet;

import '../fixtures/native_bdk/fixture_bundle.dart';

/// Public BIP39 test phrase. Never fund it.
const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// Index 0 EVM key and address as Kute derives them today. Hyperliquid,
/// the Polymarket EOA and the recovery check address all use this key.
const kuteEvmPrivateKey =
    '0x501291248b5a9ab2c9fba2b1c8f6dfef52cbf8b9bb5b7635a2cd02ddd35fa939';
const kuteEvmAddress = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';

/// m/44'/60'/0'/0/0 over the standard BIP39 seed (PBKDF2-HMAC-SHA512).
/// Kute's EVM key is NOT this one.
const standardEvmPrivateKey =
    '0x1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727';

/// Offline CREATE2 address of the earlier UUPS deposit wallet for
/// [kuteEvmAddress]; used to detect existing Polymarket users.
const legacyDepositWallet = '0xB2F1f9632Ca20E98aC994301400126f063Eea9c5';

const accountXpubs = {
  'bip44':
      'xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj',
  'bip49':
      'xpub6C6nQwHaWbSrzs5tZ1q7m5R9cPK9eYpNMFesiXsYrgc1P8bvLLAet9JfHjYXKjToD8cBRswJXXbbFpXgwsswVPAZzKMa1jUp2kVkGVUaJa7',
  'bip84':
      'xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V',
  'bip86':
      'xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ',
};

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

Uint8List _bytes32(BigInt value) {
  final out = Uint8List(32);
  for (var i = 31; i >= 0; i--) {
    out[i] = (value & BigInt.from(0xff)).toInt();
    value >>= 8;
  }
  return out;
}

Uint8List _hmacSha512(List<int> key, List<int> data) =>
    (pc.HMac(pc.SHA512Digest(), 128)
          ..init(pc.KeyParameter(Uint8List.fromList(key))))
        .process(Uint8List.fromList(data));

Uint8List _pbkdf2Seed(pc.Digest digest, int blockLength) =>
    (pc.PBKDF2KeyDerivator(pc.HMac(digest, blockLength))
          ..init(pc.Pbkdf2Parameters(
              Uint8List.fromList(utf8.encode('mnemonic')), 2048, 64)))
        .process(Uint8List.fromList(utf8.encode(phrase)));

/// Plain BIP32 private derivation of m/44'/60'/0'/0/0.
String _ethIndex0PrivateKey(Uint8List seed) {
  final curve = pc.ECCurve_secp256k1();
  var node = _hmacSha512(utf8.encode('Bitcoin seed'), seed);
  var key = node.sublist(0, 32);
  var chain = node.sublist(32);
  for (final index in const [0x8000002c, 0x8000003c, 0x80000000, 0, 0]) {
    final data = BytesBuilder();
    if (index >= 0x80000000) {
      data
        ..addByte(0)
        ..add(key);
    } else {
      data.add((curve.G * _int(key))!.getEncoded(true));
    }
    data.add([
      (index >> 24) & 0xff,
      (index >> 16) & 0xff,
      (index >> 8) & 0xff,
      index & 0xff,
    ]);
    node = _hmacSha512(chain, data.toBytes());
    key = _bytes32((_int(node.sublist(0, 32)) + _int(key)) % curve.n);
    chain = node.sublist(32);
  }
  return '0x${_hex(key)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EVM index 0', () {
    test('Kute derives the pinned key and address', () {
      final wallet = HdWallet.deriveWallet(mnemonic: phrase, index: 0);
      expect(wallet.privateKey, kuteEvmPrivateKey);
      expect(wallet.address, kuteEvmAddress);
    });

    test('the seed is PBKDF2-HMAC-SHA256, not the standard BIP39 seed', () {
      expect(_ethIndex0PrivateKey(_pbkdf2Seed(pc.SHA256Digest(), 64)),
          kuteEvmPrivateKey);
      expect(_ethIndex0PrivateKey(_pbkdf2Seed(pc.SHA512Digest(), 128)),
          standardEvmPrivateKey);
      expect(kuteEvmPrivateKey, isNot(standardEvmPrivateKey));
    });

    test('Hyperliquid provisioning signs with the pinned address', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final account =
          await HyperliquidOnboardingService.provisionHyperliquidAccount(
              mnemonic: phrase,
              walletId: 'contract',
              evmDerivationVersion: EvmDerivationVersion.legacySha256);
      expect(account.address, kuteEvmAddress);
      expect(account.credentials.address.hexEip55, kuteEvmAddress);
    });

    test('new standard Hyperliquid wallet signs with the standard address',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final account =
          await HyperliquidOnboardingService.provisionHyperliquidAccount(
        mnemonic: phrase,
        walletId: 'standard-contract',
        evmDerivationVersion: EvmDerivationVersion.standardBip39,
      );
      expect(account.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(account.credentials.address.hexEip55, account.address);
      expect(account.address, isNot(kuteEvmAddress));
    });

    test('the recovery check address is the index 0 address', () {
      expect(HdWallet.deriveWallet(mnemonic: phrase, index: 0).address,
          kuteEvmAddress);
    });

    test('the earlier Polymarket deposit wallet derives offline', () {
      expect(
        PolymarketOnboardingService()
            .deriveDepositWalletAddress(kuteEvmAddress),
        legacyDepositWallet,
      );
    });
  });

  group('Bitcoin on-chain', () {
    final rows = (jsonDecode(nativeBdkFixtureJson)['wallets'] as List)
        .cast<Map<String, dynamic>>();
    late List<Map<String, Object?>> requests;
    late NativeBitcoinPrimitives primitives;

    setUp(() {
      requests = [];
      primitives = NativeBitcoinPrimitives(
          service: NativeOnchainService(transport: (method, arguments) async {
        expect(method, 'derive');
        requests.add(arguments);
        final row = rows.firstWhere((r) =>
            r['network'] == arguments['network'] &&
            r['scriptType'] == arguments['scriptType'] &&
            r['mnemonic'] == arguments['mnemonic']);
        return {
          'external': row['external'],
          'internal': row['internal'],
          'accountXpub': row['accountXpub'],
        };
      }));
    });

    BitcoinConfig config({String? mnemonicScriptType, String? scriptType}) =>
        BitcoinConfig(
          walletId: 'contract',
          mnemonic: phrase,
          network: Network.bitcoin,
          externalKeychain: KeychainKind.external_,
          internalKeychain: KeychainKind.internal,
          isElectrumBlockchain: true,
          electrumUrl: 'custom.example:50002',
          scriptType: scriptType,
          mnemonicScriptType: mnemonicScriptType,
        );

    test('spending and passkey wallets derive BIP84 account 0', () async {
      final descriptors = await BitcoinConfigModel(config(scriptType: 'bip44'),
              primitives: primitives)
          .createDescriptors();
      expect(
          requests.single,
          allOf(
            containsPair('network', 'bitcoin'),
            containsPair('mnemonic', phrase),
            containsPair('scriptType', 'bip84'),
            containsPair('masterFingerprint', '00000000'),
            isNot(contains('xpub')),
          ));
      expect(descriptors.accountXpub, accountXpubs['bip84']);
      final bip84 = rows.firstWhere((r) =>
          r['scriptType'] == 'bip84' &&
          r['network'] == 'bitcoin' &&
          r['mnemonic'] == phrase);
      expect((bip84['addresses'] as Map)['0'],
          'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu');
    });

    for (final scriptType in accountXpubs.keys) {
      test('software Bitcoin wallets derive $scriptType account 0', () async {
        final descriptors = await BitcoinConfigModel(
                config(mnemonicScriptType: scriptType),
                primitives: primitives)
            .createDescriptors();
        expect(requests.single['scriptType'], scriptType);
        expect(descriptors.accountXpub, accountXpubs[scriptType]);
      });
    }
  });
}
