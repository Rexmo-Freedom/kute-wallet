import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

class BitcoinConfigModel {
  final BitcoinConfig config;

  final NativeBitcoinPrimitives _primitives;
  BitcoinConfigModel(this.config, {NativeBitcoinPrimitives? primitives})
      : _primitives = primitives ?? NativeBitcoinPrimitives.instance;

  Future<BitcoinDescriptors>? _derived;
  Future<BitcoinDescriptors> createDescriptors() => _derived ??= _derive();

  Future<BitcoinDescriptors> _derive() async {
    var mnemonic = config.mnemonic;
    if (mnemonic != null) {
      // Preserve the historical first-16-byte passkey conversion upstream.
      // Legacy config also accepts hex entropy; ordinary phrases stay intact.
      final isHexEntropy = config.isPasskey &&
          mnemonic.isNotEmpty &&
          mnemonic.length.isEven &&
          !mnemonic.contains(' ') &&
          RegExp(r'^[0-9a-fA-F]+$').hasMatch(mnemonic);
      if (isHexEntropy) {
        mnemonic = await _primitives.mnemonicFromEntropy(Uint8List.fromList([
          for (var i = 0; i < mnemonic.length; i += 2)
            int.parse(mnemonic.substring(i, i + 2), radix: 16),
        ]));
      }
      // Existing hot/passkey BDK wallets always used BIP84, regardless of
      // scriptType. Changing that default would derive a different wallet.
      return _primitives.derive(
          network: config.network, mnemonic: mnemonic,
          scriptType: config.mnemonicScriptType ?? 'bip84');
    }
    final originalKey = config.xpub;
    if (originalKey == null) throw const OnchainException('invalid_request');
    final String scriptType;
    if (originalKey.startsWith('zpub') || originalKey.startsWith('vpub')) {
      scriptType = 'bip84';
    } else if (originalKey.startsWith('ypub') ||
        originalKey.startsWith('upub')) {
      scriptType = 'bip49';
    } else if (const ['bip84', 'bip49', 'bip86'].contains(config.scriptType)) {
      scriptType = config.scriptType!;
    } else {
      scriptType = 'bip44';
    }
    try {
      return await _primitives.derive(
          network: config.network,
          xpub: _convertKeyToStandard(originalKey, config.network),
          scriptType: scriptType,
          masterFingerprint: _validFingerprint(config.masterFingerprint));
    } on OnchainException {
      rethrow;
    } catch (_) {
      throw const OnchainException('invalid_request');
    }
  }

  String _convertKeyToStandard(String key, Network network) {
    final rawBytes = _base58Decode(key);

    final List<int> targetVersion = network == Network.bitcoin
        ? [0x04, 0x88, 0xB2, 0x1E]
        : [0x04, 0x35, 0x87, 0xCF];

    if (rawBytes.length > 4) {
      for (int i = 0; i < 4; i++) {
        rawBytes[i] = targetVersion[i];
      }
    }

    return _base58EncodeCheck(rawBytes.sublist(0, rawBytes.length - 4));
  }

  static const String _alphabet =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

  Uint8List _base58Decode(String input) {
    if (input.isEmpty) return Uint8List(0);

    BigInt intData = BigInt.zero;
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      final digit = _alphabet.indexOf(char);
      if (digit == -1) throw FormatException("Invalid Base58 character: $char");
      intData = intData * BigInt.from(58) + BigInt.from(digit);
    }

    final bytes = _bigIntToBytes(intData);

    int leadingZeros = 0;
    for (int i = 0; i < input.length; i++) {
      if (input[i] == '1') {
        leadingZeros++;
      } else {
        break;
      }
    }

    final result = Uint8List(leadingZeros + bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      result[leadingZeros + i] = bytes[i];
    }
    return result;
  }

  String _base58EncodeCheck(List<int> payload) {
    final checksum =
        sha256.convert(sha256.convert(payload).bytes).bytes.sublist(0, 4);
    final fullBytes = [...payload, ...checksum];

    BigInt intData = BigInt.zero;
    for (final byte in fullBytes) {
      intData = intData * BigInt.from(256) + BigInt.from(byte);
    }

    String result = "";
    while (intData > BigInt.zero) {
      final remainder = intData % BigInt.from(58);
      intData = intData ~/ BigInt.from(58);
      result = _alphabet[remainder.toInt()] + result;
    }

    for (final byte in fullBytes) {
      if (byte == 0) {
        result = "1$result";
      } else {
        break;
      }
    }

    return result;
  }

  Uint8List _bigIntToBytes(BigInt number) {
    if (number == BigInt.zero) return Uint8List(0);
    String hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final len = hex.length ~/ 2;
    final bytes = Uint8List(len);
    for (int i = 0; i < len; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  Future<String> createInternalDescriptor() async {
    final pair = await createDescriptors();
    return config.internalKeychain == KeychainKind.internal
        ? pair.internal
        : pair.external;
  }

  Future<String> createExternalDescriptor() async {
    final pair = await createDescriptors();
    return config.externalKeychain == KeychainKind.external_
        ? pair.external
        : pair.internal;
  }

  /// Master fingerprint, validated to exactly 8 hex chars. A malformed
  /// value (non-hex / wrong length from a device-import path that didn't
  /// enforce it) makes BDK's Rust descriptor parser throw "FormatInvalid
  /// radix-16 number". BDK accepts the dummy "00000000"; the real
  /// fingerprint is recovered later from the device's signed PSBT.
  String _validFingerprint(String? fp) {
    if (fp == null || fp.isEmpty) return "00000000";
    return RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(fp) ? fp : "00000000";
  }

  /// Native opens existing SQLite in place. Load errors preserve the database.
  Future<NativeWalletSession> restoreWallet(
      String descriptor, String change) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    return NativeOnchainService.instance.open(
      walletId: config.walletId,
      dbPath: '${appDocDir.path}/bdk_wallet_${config.walletId}.sqlite',
      descriptor: descriptor,
      changeDescriptor: change,
      network: config.network.name,
      endpoint: OnchainEndpoint.fromStored(config.electrumUrl,
          testnet: config.network != Network.bitcoin),
    );
  }
}

class BitcoinConfig {
  final String walletId;
  final String? mnemonic;
  final String? xpub;
  final Network network;
  final KeychainKind externalKeychain;
  final KeychainKind internalKeychain;
  final bool isElectrumBlockchain;
  final String electrumUrl;
  /// Explicit opt-in for newly added ordinary Bitcoin wallets; legacy hot and
  /// passkey descriptors remain BIP84 regardless of their old scriptType field.
  final String? mnemonicScriptType;
  final String? scriptType; // e.g. 'bip84', 'bip86', 'bip49', 'bip44'
  final String? masterFingerprint; // 8-char hex from hardware wallet
  final bool
      isPasskey; // true = mnemonic field contains hex entropy, not BIP39 words

  BitcoinConfig({
    required this.walletId,
    this.mnemonic,
    this.xpub,
    required this.network,
    required this.externalKeychain,
    required this.internalKeychain,
    required this.isElectrumBlockchain,
    required this.electrumUrl,
    this.scriptType,
    this.mnemonicScriptType,
    this.masterFingerprint,
    this.isPasskey = false,
  }) {
    if (mnemonic == null && xpub == null) {
      throw Exception("BitcoinConfig requires either a mnemonic or an xpub");
    }
  }
  bool get isWatchOnly => mnemonic == null && xpub != null;
}
