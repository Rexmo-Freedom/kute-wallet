import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert';
import 'dart:isolate';
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

  /// Derivations already done this session. Several providers ask for the
  /// same account at boot and on every wallet switch. The key is a digest
  /// of the inputs, never the phrase itself; the value holds the same
  /// secret the callers hold anyway. Each isolate has its own copy, so a
  /// derivation run by [deriveWalletAsync] is stored here on the caller's
  /// isolate when it returns.
  static final Map<String, WalletCredentials> _memo = {};

  /// Derivations running in a background isolate, so two callers asking
  /// for the same account at once share one run.
  static final Map<String, Future<WalletCredentials>> _inFlight = {};

  /// Seed stretches and child derivations computed on this isolate (memo
  /// misses of [deriveWallet]). The UI isolate should keep this at zero.
  @visibleForTesting
  static int computedOnThisIsolate = 0;

  @visibleForTesting
  static void clearMemoForTest() {
    _memo.clear();
    _inFlight.clear();
    computedOnThisIsolate = 0;
  }

  static void _checkIndex(int index) {
    if (index < 0 || index >= 0x80000000) {
      throw ArgumentError('EVM derivation index must be non-hardened');
    }
  }

  static String _key(String mnemonic, EvmDerivationVersion version, int index) =>
      sha256
          .convert(utf8.encode('${version.name}:$index:${mnemonic.trim()}'))
          .toString();

  /// Synchronous derivation. The seed stretch (2048 rounds of HMAC-SHA512
  /// plus pure-Dart secp256k1 child derivation for the standard format)
  /// takes about 0.4 s on a desktop and several seconds on a low-end
  /// Android phone, long enough for an ANR. App code on the UI isolate
  /// calls [deriveWalletAsync]; this is for background isolates, tests
  /// and memo hits.
  static WalletCredentials deriveWallet({
    required String mnemonic,
    required EvmDerivationVersion version,
    int index = 0,
  }) {
    _checkIndex(index);
    final key = _key(mnemonic, version, index);
    final held = _memo[key];
    if (held != null) return held;
    computedOnThisIsolate++;
    final derived = _compute(mnemonic, version, index);
    _memo[key] = derived;
    return derived;
  }

  /// [deriveWallet] off the UI isolate: a memo hit returns at once,
  /// otherwise the derivation runs in a short-lived isolate that receives
  /// only the phrase, the version and the index, and the result is kept
  /// in this isolate's memo.
  static Future<WalletCredentials> deriveWalletAsync({
    required String mnemonic,
    required EvmDerivationVersion version,
    int index = 0,
  }) {
    try {
      _checkIndex(index);
    } catch (e) {
      return Future.error(e);
    }
    final key = _key(mnemonic, version, index);
    final held = _memo[key];
    if (held != null) return Future.value(held);
    return _inFlight[key] ??= _track(key, _spawn(mnemonic, version, index));
  }

  /// Account zero in both formats from one background isolate, both kept
  /// in the memo: a phrase recovery checks both accounts and then uses
  /// the chosen one right away.
  static Future<({WalletCredentials legacy, WalletCredentials standard})>
      deriveBothAsync(String mnemonic) async {
    const legacy = EvmDerivationVersion.legacySha256;
    const standard = EvmDerivationVersion.standardBip39;
    final legacyKey = _key(mnemonic, legacy, 0);
    final standardKey = _key(mnemonic, standard, 0);
    final pending = [legacyKey, standardKey]
        .every((k) => !_memo.containsKey(k) && !_inFlight.containsKey(k));
    if (pending) {
      final both = _spawnBoth(mnemonic);
      _inFlight[legacyKey] = _track(legacyKey, both.then((b) => b.legacy));
      _inFlight[standardKey] =
          _track(standardKey, both.then((b) => b.standard));
    }
    final results = await Future.wait([
      deriveWalletAsync(mnemonic: mnemonic, version: legacy),
      deriveWalletAsync(mnemonic: mnemonic, version: standard),
    ]);
    return (legacy: results[0], standard: results[1]);
  }

  static Future<WalletCredentials> _track(
          String key, Future<WalletCredentials> run) =>
      run.then((wallet) {
        _memo[key] = wallet;
        return wallet;
      }).whenComplete(() {
        // A block body: returning the removed future here would make
        // whenComplete wait on itself.
        _inFlight.remove(key);
      });

  // The closures below capture only their parameters, so nothing else
  // from the caller is copied into the background isolate.
  static Future<WalletCredentials> _spawn(
          String mnemonic, EvmDerivationVersion version, int index) =>
      Isolate.run(() => _compute(mnemonic, version, index));

  static Future<({WalletCredentials legacy, WalletCredentials standard})>
      _spawnBoth(String mnemonic) => Isolate.run(
          () => (
                legacy: _compute(
                    mnemonic, EvmDerivationVersion.legacySha256, 0),
                standard: _compute(
                    mnemonic, EvmDerivationVersion.standardBip39, 0),
              ));

  static WalletCredentials _compute(
          String mnemonic, EvmDerivationVersion version, int index) =>
      switch (version) {
        EvmDerivationVersion.legacySha256 =>
          HdWallet.deriveWallet(mnemonic: mnemonic, index: index),
        EvmDerivationVersion.standardBip39 => _deriveStandard(mnemonic, index),
      };

  /// Account zero's key for the Settings reveal: the EOA that is both the
  /// Hyperliquid account and the Polymarket signer. Pure and local, derived
  /// off the UI isolate; the caller holds the result only while the key is
  /// on screen.
  static Future<EvmAccountKey> accountZeroKey({
    required String mnemonic,
    required EvmDerivationVersion version,
  }) async {
    final wallet = await deriveWalletAsync(mnemonic: mnemonic, version: version);
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
