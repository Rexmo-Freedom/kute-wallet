import 'dart:typed_data';

import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

export 'package:kute/services/hardware/evm_signing_request.dart'
    show EvmExternalSigner, EvmRequestSigner;

Uint8List typedDataDigest(Uint8List domain, Uint8List message) {
  if (domain.length != 32 || message.length != 32) {
    throw ArgumentError('EIP-712 hashes must be 32 bytes');
  }
  return KeccakDigest(256)
      .process(Uint8List.fromList([0x19, 0x01, ...domain, ...message]));
}

/// Thrown before any external prompt when a builder's full typed data does
/// not hash to the builder's own domain separator and struct hash.
class EvmTypedDataMismatchException implements Exception {
  const EvmTypedDataMismatchException();

  @override
  String toString() => 'EvmTypedDataMismatchException';
}

/// Signs builder-produced EIP-712 hashes with exactly one authority.
///
/// Software path: signs the digest with [credentials], unchanged.
///
/// External path (a hardware signer, never a private key):
///   1. [typedData] is required; the device receives full typed data, not
///      a pair of hashes.
///   2. The generic encoder's domain separator and struct hash must equal
///      the builder's [domain] and [message], or this throws before the
///      signer is called.
///   3. The returned signature must recover over the digest to the
///      signer's bound address, or this throws `wrongSigner`.
/// A failed external signature is never retried with a software key.
Future<EthSignature> signTypedDataHashes({
  required Uint8List domain,
  required Uint8List message,
  required LedgerActionKind kind,
  Eip712TypedData Function()? typedData,
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
}) async {
  if ((credentials == null) == (externalSigner == null)) {
    throw StateError('Exactly one signing authority is required');
  }
  final digest = typedDataDigest(domain, message);
  if (externalSigner == null) {
    return credentials!.signToSignature(digest);
  }
  if (typedData == null) {
    throw StateError('External signing requires full typed data');
  }
  final data = typedData();
  if (!_bytesEqual(data.domainSeparator, domain) ||
      !_bytesEqual(data.structHash, message)) {
    throw const EvmTypedDataMismatchException();
  }
  final signature = await externalSigner
      .sign(Eip712Request(data, externalSigner.address, kind));
  final recovered = recoverSignerAddress(digest, signature);
  if (recovered == null || !sameEvmAddress(recovered, externalSigner.address)) {
    throw const LedgerFailure(LedgerFailureCode.wrongSigner);
  }
  return signature;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
