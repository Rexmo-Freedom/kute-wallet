// lib/services/hardware/evm_signing_request.dart
//
// One signing request model for external EVM signers (Wallet hardening
// Phase 3, plan B3). A request always carries the full payload the device
// needs (full EIP-712 typed data, never a pair of hashes), the address
// the signature must recover to, and the reviewed action kind.

import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthSignature;
import 'package:web3dart/web3dart.dart'
    show MsgSignature, ecRecover, publicKeyToAddress;

sealed class EvmSigningRequest {
  const EvmSigningRequest({required this.expectedSigner, required this.kind});

  /// The paired address the signature must recover to.
  final String expectedSigner;
  final LedgerActionKind kind;

  /// The 32-byte digest the returned signature must recover over.
  Uint8List get digest;
}

final class Eip712Request extends EvmSigningRequest {
  const Eip712Request(this.data, String expectedSigner, LedgerActionKind kind)
      : super(expectedSigner: expectedSigner, kind: kind);

  final Eip712TypedData data;

  @override
  Uint8List get digest => data.digest;
}

final class PersonalMessageRequest extends EvmSigningRequest {
  const PersonalMessageRequest(
      this.message, String expectedSigner, LedgerActionKind kind)
      : super(expectedSigner: expectedSigner, kind: kind);

  final Uint8List message;

  @override
  Uint8List get digest => personalMessageDigest(message);
}

/// Reserved for O3 EOA mode, which the owner did not pick. The Ledger
/// signer refuses it.
final class EvmTransactionRequest extends EvmSigningRequest {
  const EvmTransactionRequest(this.unsignedTransaction, this.chainId,
      String expectedSigner, LedgerActionKind kind)
      : super(expectedSigner: expectedSigner, kind: kind);

  final Uint8List unsignedTransaction;
  final int chainId;

  @override
  Uint8List get digest =>
      KeccakDigest(256).process(Uint8List.fromList(unsignedTransaction));
}

/// Replaces the hash-only `EvmTypedDataSigner` and the unused
/// `EvmPersonalSigner`.
typedef EvmRequestSigner = Future<EthSignature> Function(
    EvmSigningRequest request);

/// An external signing authority bound to one address.
class EvmExternalSigner {
  const EvmExternalSigner({required this.address, required this.sign});

  final String address;
  final EvmRequestSigner sign;
}

/// `keccak256("\x19Ethereum Signed Message:\n" + len + message)`.
Uint8List personalMessageDigest(Uint8List message) {
  final prefix = utf8.encode('\x19Ethereum Signed Message:\n${message.length}');
  return KeccakDigest(256).process(Uint8List.fromList([...prefix, ...message]));
}

/// Lowercase 0x address that [signature] recovers to over [digest], or
/// null when recovery fails.
String? recoverSignerAddress(Uint8List digest, EthSignature signature) {
  try {
    var v = signature.v;
    if (v == 0 || v == 1) v += 27;
    final pub = ecRecover(digest, MsgSignature(signature.r, signature.s, v));
    final padded = Uint8List(64)..setRange(64 - pub.length, 64, pub);
    final address = publicKeyToAddress(padded);
    return '0x${address.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  } catch (_) {
    return null;
  }
}

bool sameEvmAddress(String a, String b) {
  final re = RegExp(r'^0x[0-9a-fA-F]{40}$');
  if (!re.hasMatch(a) || !re.hasMatch(b)) return false;
  return a.toLowerCase() == b.toLowerCase();
}
