// lib/services/polymarket/deposit_wallet_batch_signer.dart
//
// Signing authority for Polymarket DepositWallet batches (Wallet
// hardening Phase 3, plan B3). `executeDepositWalletBatch` no longer takes
// a raw private key: hot callers pass a credentials-backed signer, the
// Ledger path passes an external signer that receives the full Batch
// typed data and never merges with another in-flight batch.

import 'dart:typed_data';

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signer.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

typedef DepositWalletCall = ({String target, BigInt value, String data});

abstract class DepositWalletBatchSigner {
  const DepositWalletBatchSigner();

  Future<EthSignature> signBatch({
    required Uint8List domain,
    required Uint8List message,
    required LedgerActionKind kind,
    required Eip712TypedData Function() typedData,
  });
}

/// The hot path: signs with the spending wallet's derived key.
class CredentialsDepositWalletBatchSigner extends DepositWalletBatchSigner {
  const CredentialsDepositWalletBatchSigner(this._privateKeyHex);

  final String _privateKeyHex;

  @override
  Future<EthSignature> signBatch({
    required Uint8List domain,
    required Uint8List message,
    required LedgerActionKind kind,
    required Eip712TypedData Function() typedData,
  }) {
    LedgerOperationScope.assertHotAllowed(
        HotSigningAction.polymarketHotCredentials);
    return signTypedDataHashes(
      domain: domain,
      message: message,
      kind: kind,
      credentials: EthPrivateKey.fromHex(_privateKeyHex),
    );
  }
}

/// A hardware signer: full typed data, runtime hash equality, recovery
/// against the bound address, no merging.
class ExternalDepositWalletBatchSigner extends DepositWalletBatchSigner {
  const ExternalDepositWalletBatchSigner(this.signer);

  final EvmExternalSigner signer;

  @override
  Future<EthSignature> signBatch({
    required Uint8List domain,
    required Uint8List message,
    required LedgerActionKind kind,
    required Eip712TypedData Function() typedData,
  }) =>
      signTypedDataHashes(
        domain: domain,
        message: message,
        kind: kind,
        typedData: typedData,
        externalSigner: signer,
      );
}

/// `Batch(address wallet,uint256 nonce,uint256 deadline,Call[] calls)`
/// under the four-field DepositWallet domain (chainId 137, verifying
/// contract = the deposit wallet).
Eip712TypedData depositWalletBatchTypedData({
  required String walletAddress,
  required BigInt nonce,
  required BigInt deadline,
  required List<DepositWalletCall> calls,
  int chainId = PolymarketConstants.polygonChainId,
}) =>
    Eip712TypedData(
      types: const {
        kEip712DomainType: kEip712DomainFields,
        'Batch': [
          Eip712Field('wallet', 'address'),
          Eip712Field('nonce', 'uint256'),
          Eip712Field('deadline', 'uint256'),
          Eip712Field('calls', 'Call[]'),
        ],
        'Call': [
          Eip712Field('target', 'address'),
          Eip712Field('value', 'uint256'),
          Eip712Field('data', 'bytes'),
        ],
      },
      primaryType: 'Batch',
      domain: {
        'name': PolymarketConstants.depositWalletDomainName,
        'version': PolymarketConstants.depositWalletDomainVersion,
        'chainId': chainId,
        'verifyingContract': walletAddress,
      },
      message: {
        'wallet': walletAddress,
        'nonce': nonce,
        'deadline': deadline,
        'calls': [
          for (final c in calls)
            {
              'target': c.target,
              'value': c.value,
              'data': c.data.startsWith('0x') ? c.data : '0x${c.data}',
            },
        ],
      },
    );
