import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/bitcoin_config_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import '../../fixtures/native_bdk/fixture_bundle.dart';

void main() {
  final fixtures = jsonDecode(nativeBdkFixtureJson) as Map;
  final rows = fixtures['wallets'] as List;
  final phrase = (rows.first as Map)['mnemonic'] as String;
  late List<(String, Map<String, Object?>)> requests;
  late NativeBitcoinPrimitives primitives;
  setUp(() {
    requests = [];
    primitives = NativeBitcoinPrimitives(
        service: NativeOnchainService(transport: (method, arguments) async {
      requests.add((method, arguments));
      if (method == 'mnemonic') {
        if (arguments['action'] == 'validate') return true;
        return phrase;
      }
      final row = rows.firstWhere((value) =>
          value['network'] == arguments['network'] &&
          value['scriptType'] == arguments['scriptType'] &&
          value.containsKey('mnemonic') ==
              arguments.containsKey('mnemonic')) as Map;
      return {
        'external': row['external'],
        'internal': row['internal'],
        'accountXpub': row['accountXpub']
      };
    }));
  });

  BitcoinConfig config(
          {String? mnemonic,
          String? xpub,
          String? scriptType,
          String? fingerprint,
          bool passkey = false,
          Network network = Network.bitcoin}) =>
      BitcoinConfig(
          walletId: 'test-only',
          mnemonic: mnemonic,
          xpub: xpub,
          network: network,
          internalKeychain: KeychainKind.internal,
          externalKeychain: KeychainKind.external_,
          electrumUrl: 'custom.example:50002',
          isElectrumBlockchain: true,
          isPasskey: passkey,
          scriptType: scriptType,
          masterFingerprint: fingerprint);

  test(
      'hot wallets retain BIP84 and unchanged mnemonic even when scriptType differs',
      () async {
    final model = BitcoinConfigModel(
        config(mnemonic: phrase, scriptType: 'bip44'),
        primitives: primitives);
    await model.createExternalDescriptor();
    await model.createInternalDescriptor();
    expect(requests, hasLength(1));
    expect(requests.single.$1, 'derive');
    expect(requests.single.$2['scriptType'], 'bip84');
    expect(requests.single.$2['mnemonic'], phrase);
    expect(requests.single.$2.containsKey('walletId'), false);
    expect(requests.single.$2.containsKey('password'), false);
  });

  test(
      'legacy passkey hex entropy goes through native BIP39 before unchanged BIP84',
      () async {
    final model = BitcoinConfigModel(config(mnemonic: '00' * 16, passkey: true),
        primitives: primitives);
    await model.createDescriptors();
    expect(requests.map((r) => r.$1), ['mnemonic', 'derive']);
    expect(requests.first.$2['action'], 'fromEntropy');
    expect(requests.first.$2['entropy'], orderedEquals(Uint8List(16)));
    expect(requests.last.$2['mnemonic'], phrase);
    expect(requests.last.$2['scriptType'], 'bip84');
  });

  test('passkey mnemonic phrases do not get reinterpreted as entropy',
      () async {
    await BitcoinConfigModel(config(mnemonic: phrase, passkey: true),
            primitives: primitives)
        .createDescriptors();
    expect(requests.single.$1, 'derive');
    expect(requests.single.$2['mnemonic'], phrase);
  });

  const prefixed = [
    (
      'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs',
      'bip84',
      Network.bitcoin
    ),
    (
      'ypub6XR9pJPUsVBFKweLeV85HtwdxjjmKEuUr6djm9mNdkh47X7ASsD6byaXFotRAKByFoWgSzCuoTjaYdrv2yoJroLAPtBuHFjVm5vNmhyNehE',
      'bip49',
      Network.bitcoin
    ),
    (
      'vpub5Y6cjg78GGuNLsaPhmYsiw4gYX3HoQiRBiSwDaBXKUafCt9bNwWQiitDk5VZ5BVxYnQdwoTyXSs2JHRPAgjAvtbBrf8ZhDYe2jWAqvZVnsc',
      'bip84',
      Network.testnet
    ),
    (
      'upub5DGMS1SD7bMtVaPGsQmFWqyBNYtqrnivGbviSBHdwUCn9nLN8HLr6fE5isXy5Gr399HqCKsR4nWUQzopSzKA8euazKS97Jj9m1SXTNjmvtM',
      'bip49',
      Network.testnet
    ),
  ];
  for (final (key, script, network) in prefixed) {
    test(
        '${key.substring(0, 4)} remains authoritative over a conflicting scriptType',
        () async {
      final expectedXpub = rows.firstWhere((r) =>
          r['network'] == network.name &&
          r['scriptType'] == 'bip84' &&
          r.containsKey('xpub'))['xpub'];
      await BitcoinConfigModel(
              config(xpub: key, scriptType: 'bip86', network: network),
              primitives: primitives)
          .createDescriptors();
      expect(requests.single.$2['xpub'], expectedXpub);
      expect(requests.single.$2['scriptType'], script);
      expect(requests.single.$2['network'], network.name);
    });
  }

  test(
      'plain xpub defaults to BIP44 and invalid hardware fingerprint stays zero',
      () async {
    final xpub =
        rows.firstWhere((r) => r.containsKey('xpub'))['xpub'] as String;
    await BitcoinConfigModel(config(xpub: xpub, fingerprint: 'invalid'),
            primitives: primitives)
        .createDescriptors();
    expect(requests.single.$2['scriptType'], 'bip44');
    expect(requests.single.$2['masterFingerprint'], '00000000');
  });

  test(
      'plain xpub honors explicit Taproot and preserves valid hardware fingerprint',
      () async {
    final xpub =
        rows.firstWhere((r) => r.containsKey('xpub'))['xpub'] as String;
    await BitcoinConfigModel(
            config(xpub: xpub, scriptType: 'bip86', fingerprint: 'aabbccdd'),
            primitives: primitives)
        .createDescriptors();
    expect(requests.single.$2['scriptType'], 'bip86');
    expect(requests.single.$2['masterFingerprint'], 'aabbccdd');
  });
}
