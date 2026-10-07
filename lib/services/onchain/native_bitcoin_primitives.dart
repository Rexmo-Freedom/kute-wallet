import 'dart:typed_data';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

/// Stateless BDK operations run on a separate native executor, so a slow
/// wallet sync cannot delay passkey entropy conversion or seed validation.
class NativeBitcoinPrimitives {
  static final instance = NativeBitcoinPrimitives();
  final NativeOnchainService service;
  NativeBitcoinPrimitives({NativeOnchainService? service})
      : service = service ?? NativeOnchainService.instance;

  Future<String> generateMnemonic() async => (await service.primitive(
      'mnemonic', {'action': 'generate', 'wordCount': 12}))! as String;
  Future<bool> validateMnemonic(String mnemonic) async => (await service
          .primitive('mnemonic', {'action': 'validate', 'mnemonic': mnemonic}))!
      as bool;
  Future<String> mnemonicFromEntropy(Uint8List entropy) async =>
      (await service.primitive(
              'mnemonic', {'action': 'fromEntropy', 'entropy': entropy}))!
          as String;

  Future<BitcoinDescriptors> derive(
          {required Network network,
          String? mnemonic,
          String? xpub,
          required String scriptType,
          String masterFingerprint = '00000000'}) async =>
      BitcoinDescriptors.fromMap(await service.primitive('derive', {
        'network': network.name,
        if (mnemonic != null) 'mnemonic': mnemonic,
        if (xpub != null) 'xpub': xpub,
        'scriptType': scriptType,
        'masterFingerprint': masterFingerprint
      }));

  Future<Psbt> inspectPsbt(String psbt) async =>
      Psbt.fromMap(await service.primitive('inspectPsbt', {'psbt': psbt}));
}

class BitcoinDescriptors {
  final String external;
  final String internal;
  final String accountXpub;
  const BitcoinDescriptors(
      {required this.external,
      required this.internal,
      required this.accountXpub});
  factory BitcoinDescriptors.fromMap(Object? value) {
    if (value is! Map ||
        value['external'] is! String ||
        value['internal'] is! String ||
        value['accountXpub'] is! String) {
      throw const OnchainException('internal');
    }
    return BitcoinDescriptors(
        external: value['external'] as String,
        internal: value['internal'] as String,
        accountXpub: value['accountXpub'] as String);
  }
}
