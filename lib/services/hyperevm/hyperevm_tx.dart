// lib/services/hyperevm/hyperevm_tx.dart
//
// Calldata, EIP-3009 authorizations and signed EIP-1559 transactions for
// the three HyperEVM calls the Investing moves make. Pure: no network.
//
//  - USDC `transfer(to, amount)` to an Orchestra deposit address (a
//    withdrawal's last step).
//  - CoreDepositWallet `depositWithAuth(...)` (a deposit's last step): one
//    transaction, no approval, authorized by an EIP-3009
//    `ReceiveWithAuthorization` signature the contract redeems itself.
//  - A plain HYPE value transfer to 0x2222…2222 (part of the gas float
//    moving to HyperCore).
//
// The CoreDepositWallet and the system addresses can never be the
// recipient of a USDC transfer built here: a transfer to the
// CoreDepositWallet is lost for good (Circle).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' as pm
    show EthPrivateKey;
import 'package:web3dart/web3dart.dart' as w3;

/// A transaction this app refused to build.
class HyperEvmTxRefused implements Exception {
  const HyperEvmTxRefused(this.reason);
  final String reason;

  @override
  String toString() => 'HyperEvmTxRefused($reason)';
}

/// A signed transaction, ready to broadcast. [hash] is final before any
/// broadcast, so it is persisted first.
class SignedHyperEvmTx {
  const SignedHyperEvmTx({
    required this.raw,
    required this.hash,
    required this.nonce,
  });

  final String raw;
  final String hash;
  final int nonce;
}

Uint8List _keccak(List<int> data) =>
    KeccakDigest(256).process(Uint8List.fromList(data));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (clean.length.isOdd) throw ArgumentError.value(hex, 'hex');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16)
  ]);
}

Uint8List _uintWord(BigInt value) {
  if (value < BigInt.zero || value.bitLength > 256) {
    throw ArgumentError.value(value, 'value', 'not a uint256');
  }
  final out = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

Uint8List _addressWord(String address) {
  if (!isEvmAddress(address)) {
    throw ArgumentError.value(address, 'address', 'not an EVM address');
  }
  final out = Uint8List(32);
  out.setRange(12, 32, _bytes(address));
  return out;
}

String _word(BigInt value) => _hex(_uintWord(value));

/// USDC `transfer(to, amount)` calldata. Refuses the CoreDepositWallet,
/// the system addresses and a zero amount.
String usdcTransferData({required String to, required BigInt amountMicros}) {
  if (amountMicros <= BigInt.zero) {
    throw const HyperEvmTxRefused('amount');
  }
  if (!isEvmAddress(to) ||
      HyperEvmChain.forbiddenTransferRecipients.contains(to.toLowerCase())) {
    throw const HyperEvmTxRefused('recipient');
  }
  return '0xa9059cbb${_hex(_addressWord(to))}${_word(amountMicros)}';
}

/// The EIP-712 domain separator of HyperEVM USDC, computed locally. Must
/// equal [HyperEvmChain.usdcDomainSeparator] and the live
/// `DOMAIN_SEPARATOR()`.
Uint8List hyperEvmUsdcDomainSeparator() {
  final typeHash = _keccak(utf8.encode(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'));
  return _keccak([
    ...typeHash,
    ..._keccak(utf8.encode(HyperEvmChain.usdcEip712Name)),
    ..._keccak(utf8.encode(HyperEvmChain.usdcEip712Version)),
    ..._uintWord(BigInt.from(HyperEvmChain.chainId)),
    ..._addressWord(HyperEvmChain.usdc),
  ]);
}

/// The digest an EIP-3009 `receiveWithAuthorization` checks.
Uint8List receiveWithAuthorizationDigest({
  required String from,
  required String to,
  required BigInt value,
  required BigInt validAfter,
  required BigInt validBefore,
  required Uint8List nonce,
}) {
  if (nonce.length != 32) throw ArgumentError.value(nonce, 'nonce');
  final typeHash = _keccak(utf8.encode(
      'ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)'));
  final structHash = _keccak([
    ...typeHash,
    ..._addressWord(from),
    ..._addressWord(to),
    ..._uintWord(value),
    ..._uintWord(validAfter),
    ..._uintWord(validBefore),
    ...nonce,
  ]);
  return _keccak([0x19, 0x01, ...hyperEvmUsdcDomainSeparator(), ...structHash]);
}

/// A fresh random EIP-3009 nonce.
Uint8List randomAuthorizationNonce([math.Random? random]) {
  final source = random ?? math.Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => source.nextInt(256)));
}

/// CoreDepositWallet `depositWithAuth` calldata for an authorization
/// [key] signs over [amountMicros] from its own address to the
/// CoreDepositWallet. [destinationDex] is [HyperEvmChain.perpsDex] or
/// [HyperEvmChain.spotDex].
Future<String> depositWithAuthData({
  required pm.EthPrivateKey key,
  required BigInt amountMicros,
  required BigInt validAfter,
  required BigInt validBefore,
  required Uint8List nonce,
  required int destinationDex,
}) async {
  if (amountMicros <= BigInt.zero) throw const HyperEvmTxRefused('amount');
  if (destinationDex != HyperEvmChain.perpsDex &&
      destinationDex != HyperEvmChain.spotDex) {
    throw const HyperEvmTxRefused('dex');
  }
  final digest = receiveWithAuthorizationDigest(
    from: key.address.hexEip55,
    to: HyperEvmChain.coreDepositWallet,
    value: amountMicros,
    validAfter: validAfter,
    validBefore: validBefore,
    nonce: nonce,
  );
  final signature = await key.signToSignature(digest);
  final v = signature.v;
  _checkSigner(digest, signature.r, signature.s, v, key);
  return '0xea031649'
      '${_word(amountMicros)}'
      '${_word(validAfter)}'
      '${_word(validBefore)}'
      '${_hex(nonce)}'
      '${_word(BigInt.from(v))}'
      '${_word(signature.r)}'
      '${_word(signature.s)}'
      '${_word(BigInt.from(destinationDex))}';
}

/// Signs an EIP-1559 transaction on HyperEVM (chain 999) with [key].
Future<SignedHyperEvmTx> signHyperEvmTx({
  required pm.EthPrivateKey key,
  required String to,
  required String data,
  BigInt? valueWei,
  required int nonce,
  required BigInt gasLimit,
  required BigInt maxFeePerGasWei,
  BigInt? maxPriorityFeePerGasWei,
}) async {
  if (!isEvmAddress(to)) throw const HyperEvmTxRefused('to');
  if (to.toLowerCase() == HyperEvmChain.coreDepositWallet.toLowerCase() &&
      !data.toLowerCase().startsWith('0xea031649')) {
    // The CoreDepositWallet takes calls to its deposit functions only.
    throw const HyperEvmTxRefused('core_deposit_wallet');
  }
  if (nonce < 0 || gasLimit <= BigInt.zero || maxFeePerGasWei <= BigInt.zero) {
    throw const HyperEvmTxRefused('fields');
  }
  // EIP-1559 (type 2) per the spec: 0x02 || rlp([chainId, nonce,
  // maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data,
  // accessList]) is signed, then the signature's yParity, r and s are
  // appended to the same list.
  final fields = <Object>[
    BigInt.from(HyperEvmChain.chainId),
    BigInt.from(nonce),
    maxPriorityFeePerGasWei ?? BigInt.zero,
    maxFeePerGasWei,
    gasLimit,
    _bytes(to),
    valueWei ?? BigInt.zero,
    _bytes(data),
    <Object>[],
  ];
  final unsigned = Uint8List.fromList([0x02, ...w3.encode(fields)]);
  final digest = _keccak(unsigned);
  final signature = await key.signToSignature(digest);
  _checkSigner(digest, signature.r, signature.s, signature.v, key);
  final raw = Uint8List.fromList([
    0x02,
    ...w3.encode([
      ...fields,
      BigInt.from(signature.v - 27),
      signature.r,
      signature.s,
    ]),
  ]);
  return SignedHyperEvmTx(
    raw: '0x${_hex(raw)}',
    hash: '0x${_hex(_keccak(raw))}',
    nonce: nonce,
  );
}

/// Recovers the signer of [digest] and refuses anything but [key]'s own
/// address: the signer library falls back to v = 27 when it cannot
/// recover, which would broadcast a transaction from a stranger.
void _checkSigner(
    Uint8List digest, BigInt r, BigInt s, int v, pm.EthPrivateKey key) {
  if (v != 27 && v != 28) throw const HyperEvmTxRefused('signature');
  final Uint8List publicKey;
  try {
    publicKey = w3.ecRecover(digest, w3.MsgSignature(r, s, v));
  } catch (_) {
    throw const HyperEvmTxRefused('signature');
  }
  final recovered = '0x${_hex(w3.publicKeyToAddress(publicKey))}';
  if (!sameEvmAddress(recovered, key.address.hexEip55)) {
    throw const HyperEvmTxRefused('signature');
  }
}

/// The fee cap for a HyperEVM transaction: twice the current price, so
/// the next blocks' base fee fits, never below 0.1 gwei. Priority fees on
/// HyperEVM are burned and the network asks for none.
BigInt hyperEvmMaxFeePerGas(BigInt gasPriceWei) {
  final floor = BigInt.from(100000000);
  final doubled = gasPriceWei * BigInt.two;
  return doubled > floor ? doubled : floor;
}

/// [estimate] with 30% headroom.
BigInt hyperEvmGasLimit(BigInt estimate) =>
    estimate + (estimate * BigInt.from(3)) ~/ BigInt.from(10);
