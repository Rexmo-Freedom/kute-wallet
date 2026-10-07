// lib/services/hardware/ledger/ledger_evm_signer.dart
//
// Ledger EVM signer (Wallet hardening Phase 3, P3.5).
//
// * Full EIP-712 mode only; hash-only (blind) signing has no code path.
// * Checks the release gate for the action kind before touching the
//   device; opaque kinds stay blocked while their flags are off.
// * Checks the Ethereum app version and the device account address
//   against the paired address before sending the payload.
// * Recovers the returned signature over the request digest and requires
//   the paired address.
// * One request at a time (the device session throws `busy`), and every
//   rejection, disconnect or timeout fails closed with a typed
//   [LedgerFailure]. There is no software fallback anywhere in this file.
//
// The Ledger proves the user approved on the device. For opaque kinds it
// does not prove what was signed; see plan section E.

import 'dart:async';
import 'dart:typed_data';

import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/eth/eth_address_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/eth/eth_app_config_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_eip712_operations.dart';
import 'package:kute/services/hardware/ledger/eth/eth_personal_sign_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_signature.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthSignature;

enum LedgerSignStep {
  openingApp,
  checkingAppVersion,
  checkingAccount,
  sendingPayload,
  awaitingApproval,
  verifyingSignature,
  signed,
  failed,
}

typedef LedgerActionGate = bool Function(LedgerActionKind kind);

class LedgerEvmSigner {
  LedgerEvmSigner({
    required this.session,
    required this.pairedAddress,
    this.derivationPath = kLedgerEvmDerivationPath,
    this.minimumAppVersion = kLedgerEthMinimumAppVersion,
    LedgerActionGate? gate,
  }) : _gate = gate ?? ((kind) => isLedgerActionAllowed(kind)) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(pairedAddress)) {
      throw ArgumentError('Paired address must be a 0x address');
    }
  }

  final LedgerDeviceSession session;
  final String pairedAddress;
  final String derivationPath;
  final LedgerSemver minimumAppVersion;
  final LedgerActionGate _gate;

  final _steps = StreamController<LedgerSignStep>.broadcast();

  /// Progress for the approval sheet. Connecting alone is never approval.
  Stream<LedgerSignStep> get steps => _steps.stream;

  /// The external authority to hand to builders and executors.
  EvmExternalSigner get externalSigner =>
      EvmExternalSigner(address: pairedAddress, sign: sign);

  Future<void> dispose() => _steps.close();

  void _emit(LedgerSignStep step) {
    if (!_steps.isClosed) _steps.add(step);
  }

  /// Signs [request] on the device. Matches [EvmRequestSigner].
  Future<EthSignature> sign(EvmSigningRequest request) async {
    // Everything below runs before any device command.
    if (!sameEvmAddress(request.expectedSigner, pairedAddress)) {
      throw const LedgerFailure(LedgerFailureCode.wrongSigner);
    }
    if (!_gate(request.kind)) {
      throw LedgerActionBlockedException(request.kind);
    }
    final List<LedgerApdu> payload;
    final LedgerApdu promptFrame;
    final Uint8List digest;
    switch (request) {
      case Eip712Request(:final data):
        digest = data.digest; // validates every value strictly
        payload = eip712PayloadApdus(data);
        promptFrame = eip712SignFullApdu(path: derivationPath);
      case PersonalMessageRequest(:final message):
        digest = request.digest;
        final frames =
            ethPersonalSignApdus(path: derivationPath, message: message);
        payload = frames.sublist(0, frames.length - 1);
        promptFrame = frames.last;
      case EvmTransactionRequest():
        throw UnsupportedError('Ledger EVM transactions are not enabled');
    }

    if (session.isBusy) throw const LedgerFailure(LedgerFailureCode.busy);
    try {
      return await session.run((scope) async {
        _emit(LedgerSignStep.openingApp);
        await scope.ensureApp(LedgerAppId.ethereum);

        _emit(LedgerSignStep.checkingAppVersion);
        final config = parseEthAppConfig(await scope.send(ethAppConfigApdu()));
        if (!config.supports(minimumAppVersion)) {
          throw const LedgerFailure(LedgerFailureCode.unsupportedAppVersion,
              app: LedgerAppId.ethereum);
        }

        _emit(LedgerSignStep.checkingAccount);
        final account = parseEthAddressResponse(await scope
            .send(ethGetAddressApdu(path: derivationPath, display: false)));
        if (!sameEvmAddress(account.address, pairedAddress)) {
          throw const LedgerFailure(LedgerFailureCode.wrongDevice);
        }

        _emit(LedgerSignStep.sendingPayload);
        for (final frame in payload) {
          await scope.send(frame);
        }

        _emit(LedgerSignStep.awaitingApproval);
        final response = await scope.send(promptFrame, prompts: true);

        _emit(LedgerSignStep.verifyingSignature);
        final EthSignature signature;
        try {
          signature = parseEthSignatureResponse(response);
        } on FormatException {
          throw const LedgerFailure(LedgerFailureCode.wrongSigner);
        }
        final recovered = recoverSignerAddress(digest, signature);
        if (recovered == null || !sameEvmAddress(recovered, pairedAddress)) {
          throw const LedgerFailure(LedgerFailureCode.wrongSigner);
        }
        _emit(LedgerSignStep.signed);
        return signature;
      });
    } on FormatException {
      _emit(LedgerSignStep.failed);
      throw const LedgerFailure(LedgerFailureCode.unknown);
    } catch (_) {
      _emit(LedgerSignStep.failed);
      rethrow;
    }
  }
}
