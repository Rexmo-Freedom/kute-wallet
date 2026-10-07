import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart'
    show Bip32Slip10Secp256k1;
import 'package:pointycastle/export.dart' as pc;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show HdWallet, WalletCredentials;

import 'package:kute/models/evm_derivation_version.dart';

/// Account zero of a wallet's phrase: the EOA and its 0x-prefixed,
/// lowercase, 64-hex-digit private key.
typedef EvmAccountKey = ({String address, String privateKey});

/// One derivation boundary for Polymarket, Hyperliquid and recovery checks.
/// Existing wallets keep the original SHA256 contract; new wallets can use
/// standard BIP39. Neither derivation changes Bitcoin or hardware-wallet keys.
abstract final class EvmWalletDerivation {
  static const pathPrefix = "m/44'/60'/0'/0/";

  /// Derivations already done this session. The seed stretch is 2048
  /// rounds of HMAC-SHA512 on the UI isolate, which a slow phone feels as
  /// a frozen second, and several providers ask for the same account at
  /// boot. The key is a digest of the inputs, never the phrase itself; the
  /// value holds the same secret the callers hold anyway.
  static final Map<String, WalletCredentials> _memo = {};

  @visibleForTesting
  static void clearMemoForTest() => _memo.clear();

  static WalletCredentials deriveWallet({
    required String mnemonic,
    required EvmDerivationVersion version,
    int index = 0,
  }) {
    if (index < 0 || index >= 0x80000000) {
      throw ArgumentError('EVM derivation index must be non-hardened');
    }
    final key = sha256
        .convert(utf8.encode('${version.name}:$index:${mnemonic.trim()}'))
        .toString();
    final held = _memo[key];
    if (held != null) return held;
    final derived = switch (version) {
      EvmDerivationVersion.legacySha256 =>
        HdWallet.deriveWallet(mnemonic: mnemonic, index: index),
      EvmDerivationVersion.standardBip39 => _deriveStandard(mnemonic, index),
    };
    _memo[key] = derived;
    return derived;
  }

  /// Account zero's key for the Settings reveal: the EOA that is both the
  /// Hyperliquid account and the Polymarket signer. Pure and local; the
  /// caller holds the result only while the key is on screen.
  static EvmAccountKey accountZeroKey({
    required String mnemonic,
    required EvmDerivationVersion version,
  }) {
    final wallet = deriveWallet(mnemonic: mnemonic, version: version);
    var hex = wallet.privateKey.trim().toLowerCase();
    if (hex.startsWith('0x')) hex = hex.substring(2);
    hex = hex.padLeft(64, '0');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
      throw StateError('Unexpected EVM private key format');
    }
    return (address: wallet.address, privateKey: '0x$hex');
  }

  static WalletCredentials _deriveStandard(String mnemonic, int index) {
    // The supported wordlist is English and no extra BIP39 passphrase is
    // accepted. Canonical words and the empty passphrase are already NFKD.
    final phrase =
        mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    if (!HdWallet.validateMnemonic(phrase)) {
      throw ArgumentError('Invalid mnemonic phrase');
    }
    final seed = (pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA512Digest(), 128))
          ..init(pc.Pbkdf2Parameters(
              Uint8List.fromList(utf8.encode('mnemonic')), 2048, 64)))
        .process(Uint8List.fromList(utf8.encode(phrase)));
    try {
      final child =
          Bip32Slip10Secp256k1.fromSeed(seed).derivePath('$pathPrefix$index');
      final privateKey = '0x${child.privateKey.raw.map(
            (byte) => byte.toRadixString(16).padLeft(2, '0'),
          ).join()}';
      return WalletCredentials(
        address: HdWallet.getAddress(privateKey),
        privateKey: privateKey,
        derivationIndex: index,
      );
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }
}
