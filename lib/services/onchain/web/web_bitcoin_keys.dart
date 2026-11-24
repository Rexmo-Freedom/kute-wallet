// lib/services/onchain/web/web_bitcoin_keys.dart
//
// The key work the browser build of BDK (bdk-wasm) does not expose:
// BIP39 mnemonics (generate, validate, from entropy), the BIP39 seed and
// the account xpub. Pure Dart on blockchain_utils' primitives, so it runs
// in a browser and in a VM test alike. Each function answers exactly what
// the native BDK 3.1 bindings answer for the same input (see
// NativeBdkPlugin.swift and test/services/onchain/web_bitcoin_keys_test.dart).
//
// Only the web channel implementation uses this; iOS and Android keep
// asking native BDK.

import 'dart:math';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

abstract final class WebBitcoinKeys {
  static List<String>? _english;
  static Map<String, int>? _index;

  static List<String> get _words =>
      _english ??= List.unmodifiable(Bip39Languages.english.wordList);
  static Map<String, int> get _wordIndex => _index ??= {
        for (var i = 0; i < _words.length; i++) _words[i]: i,
      };

  /// Entropy lengths BIP39 defines (12 to 24 words).
  static const entropyLengths = {16, 20, 24, 28, 32};

  /// A new 12-word English phrase from 16 bytes of secure randomness, as
  /// BDK's `Mnemonic(wordCount: .words12)`.
  static String generateMnemonic({Random? random}) {
    final source = random ?? Random.secure();
    return mnemonicFromEntropy(
        Uint8List.fromList(List.generate(16, (_) => source.nextInt(256))));
  }

  /// The English phrase for [entropy] (16, 20, 24, 28 or 32 bytes), words
  /// joined by single spaces, as BDK's `Mnemonic.fromEntropy`.
  static String mnemonicFromEntropy(List<int> entropy) {
    if (!entropyLengths.contains(entropy.length)) {
      throw ArgumentError('entropy length');
    }
    final checksumBits = entropy.length ~/ 4;
    final hash = QuickCrypto.sha256Hash(entropy);
    final bits = StringBuffer();
    for (final byte in entropy) {
      bits.write(byte.toRadixString(2).padLeft(8, '0'));
    }
    bits.write(hash[0].toRadixString(2).padLeft(8, '0').substring(0, checksumBits));
    final all = bits.toString();
    return [
      for (var i = 0; i < all.length; i += 11)
        _words[int.parse(all.substring(i, i + 11), radix: 2)],
    ].join(' ');
  }

  /// The words of [phrase] when it is a valid English BIP39 mnemonic, else
  /// null. As rust-bip39's `Mnemonic::from_str` (what BDK parses with):
  /// any whitespace separates words, 12, 15, 18, 21 or 24 of them, every
  /// word exactly an English list word, and the checksum must match.
  static List<String>? parseMnemonic(String phrase) {
    final words =
        phrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 12 || words.length > 24 || words.length % 3 != 0) {
      return null;
    }
    final bits = StringBuffer();
    for (final word in words) {
      final index = _wordIndex[word];
      if (index == null) return null;
      bits.write(index.toRadixString(2).padLeft(11, '0'));
    }
    final all = bits.toString();
    final checksumBits = words.length ~/ 3;
    final entropyBits = all.length - checksumBits;
    final entropy = Uint8List(entropyBits ~/ 8);
    for (var i = 0; i < entropy.length; i++) {
      entropy[i] = int.parse(all.substring(i * 8, i * 8 + 8), radix: 2);
    }
    final hash = QuickCrypto.sha256Hash(entropy);
    final expected =
        hash[0].toRadixString(2).padLeft(8, '0').substring(0, checksumBits);
    if (all.substring(entropyBits) != expected) return null;
    return words;
  }

  static bool validateMnemonic(String phrase) => parseMnemonic(phrase) != null;

  /// The 64-byte BIP39 seed of a valid [phrase]. Like BDK, the seed is
  /// taken from the canonical phrase (words joined by single spaces), not
  /// the caller's spacing.
  static Uint8List seed(String phrase, {String passphrase = ''}) {
    final words = parseMnemonic(phrase);
    if (words == null) throw ArgumentError('mnemonic');
    return Uint8List.fromList(QuickCrypto.pbkdf2DeriveKey(
      password: StringUtils.encode(words.join(' ')),
      salt: StringUtils.encode('mnemonic$passphrase'),
      iterations: 2048,
      dklen: 64,
    ));
  }

  /// The account xpub (tpub off mainnet) at m/[purpose]'/coin'/0' of
  /// [seed], as native BDK's `key.derive(path).asPublic()`: coin 0 on
  /// mainnet, 1 everywhere else.
  static String accountXpub(Uint8List seed,
      {required int purpose, required bool mainnet}) {
    final versions = mainnet
        ? Bip32Const.mainNetKeyNetVersions
        : Bip32Const.testNetKeyNetVersions;
    final master = Bip32Slip10Secp256k1.fromSeed(seed, versions);
    final coin = mainnet ? 0 : 1;
    return master.derivePath("m/$purpose'/$coin'/0'").publicKey.toExtended;
  }
}
