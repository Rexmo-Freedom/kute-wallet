import 'dart:async';

import 'package:kute/models/breez/error_handling.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';

enum SparkDepositActionReason {
  walletChanged,
  busy,
  walletUnavailable,
  invalidDeposit,
  immature,
  refundInProgress,
  invalidFee,
  invalidAddress,
  feeExceeded,
}

/// Expected guard failures. The UI maps [reason] to localized copy instead
/// of showing exception text.
class SparkDepositActionException implements Exception {
  const SparkDepositActionException(this.reason, {this.requiredFeeSats});

  final SparkDepositActionReason reason;

  /// Set for [SparkDepositActionReason.feeExceeded].
  final BigInt? requiredFeeSats;

  @override
  String toString() => 'SparkDepositActionException(${reason.name})';
}

enum SparkDepositClaimOutcome {
  submitted,
  alreadyReceived,
  noLongerPending,

  /// The service may have accepted the claim before the SDK failed. The
  /// deposit stays listed until the transfer event settles it.
  statusUnknown,
}

class SparkDepositClaimResult {
  const SparkDepositClaimResult(this.outcome, {this.paymentStatus});

  final SparkDepositClaimOutcome outcome;

  /// Status of a submitted claim's payment. Usually pending: the incoming
  /// transfer completes after claimDeposit returns.
  final PaymentStatus? paymentStatus;
}

/// Explicit commands: completed/failed attempts are never cached as provider
/// values. Claim and refund share a per-wallet outpoint lock across all screens.
class SparkDepositActions {
  SparkDepositActions({
    required this.loadSdk,
    required this.currentWalletId,
    this.sdkLoadTimeout = const Duration(seconds: 15),
  });

  final Future<BreezSdk> Function(String walletId) loadSdk;
  final String? Function() currentWalletId;
  final Duration sdkLoadTimeout;
  final Set<(String, String, int)> _busy = {};

  static const _walletChanged =
      SparkDepositActionException(SparkDepositActionReason.walletChanged);

  Future<BreezSdk> _loadSdk(String walletId) async {
    final BreezSdk sdk;
    try {
      sdk = await loadSdk(walletId).timeout(sdkLoadTimeout);
    } on SparkDepositActionException {
      rethrow;
    } catch (_) {
      // Still connecting, locked or queued behind teardown.
      throw const SparkDepositActionException(
          SparkDepositActionReason.walletUnavailable);
    }
    if (currentWalletId() != walletId) throw _walletChanged;
    return sdk;
  }

  Future<T> _run<T>({
    required String walletId,
    required String txid,
    required int vout,
    required Future<T> Function(BreezSdk sdk) execute,
  }) async {
    if (walletId.isEmpty || currentWalletId() != walletId) {
      throw _walletChanged;
    }
    if (txid.isEmpty || vout < 0) {
      throw const SparkDepositActionException(
          SparkDepositActionReason.invalidDeposit);
    }
    final key = (walletId, txid, vout);
    if (!_busy.add(key)) {
      throw const SparkDepositActionException(SparkDepositActionReason.busy);
    }
    try {
      final sdk = await _loadSdk(walletId);
      try {
        return await execute(sdk);
      } on SparkDepositActionException {
        rethrow;
      } on SdkError_MaxDepositClaimFeeExceeded catch (error) {
        throw SparkDepositActionException(
          SparkDepositActionReason.feeExceeded,
          requiredFeeSats: error.requiredFeeSats,
        );
      } catch (error) {
        handlePaymentException(error);
      }
    } finally {
      _busy.remove(key);
    }
  }

  Future<DepositInfo?> _findDeposit(BreezSdk sdk, String txid, int vout) async {
    final pending = await sdk.listUnclaimedDeposits(
      request: const ListUnclaimedDepositsRequest(),
    );
    final wanted = txid.toLowerCase();
    return pending.deposits
        .where((item) => item.txid.toLowerCase() == wanted && item.vout == vout)
        .firstOrNull;
  }

  /// Whether a deposit payment that has not failed exists for the outpoint.
  Future<bool> _depositReceived(BreezSdk sdk, String txid, int vout) async {
    try {
      final response = await sdk.listPayments(
        request: const ListPaymentsRequest(typeFilter: [PaymentType.receive]),
      );
      final wanted = txid.toLowerCase();
      return response.payments.any((payment) {
        final details = payment.details;
        return payment.status != PaymentStatus.failed &&
            details is PaymentDetails_Deposit &&
            details.txId.toLowerCase() == wanted &&
            details.vout == vout;
      });
    } catch (_) {
      return false;
    }
  }

  /// A row missing from SDK storage was claimed, refunded or dropped. Only a
  /// matching deposit payment proves the funds were received.
  Future<SparkDepositClaimResult> _missingDepositOutcome(
      BreezSdk sdk, String txid, int vout) async {
    return SparkDepositClaimResult(await _depositReceived(sdk, txid, vout)
        ? SparkDepositClaimOutcome.alreadyReceived
        : SparkDepositClaimOutcome.noLongerPending);
  }

  /// A mature claim settles with its payment. Submitted and Deferred come
  /// from the SDK's early-claim path, which a deposit it still counts as
  /// immature takes even though the list reported it mature.
  static SparkDepositClaimResult _claimResult(ClaimDepositOutcome outcome) {
    switch (outcome) {
      case ClaimDepositOutcome_Settled(:final payment):
        return SparkDepositClaimResult(SparkDepositClaimOutcome.submitted,
            paymentStatus: payment.status);
      case ClaimDepositOutcome_Submitted():
        return const SparkDepositClaimResult(
            SparkDepositClaimOutcome.submitted);
      case ClaimDepositOutcome_Deferred(:final reason):
        if (reason case ClaimDeferredReason_MaxFeeExceeded(
          :final requiredFeeSats
        )) {
          throw SparkDepositActionException(
            SparkDepositActionReason.feeExceeded,
            requiredFeeSats: requiredFeeSats,
          );
        }
        throw const SparkDepositActionException(
            SparkDepositActionReason.immature);
    }
  }

  /// Errors the SDK raises before the service can accept a claim.
  static bool _failedBeforeClaim(Object error) =>
      error is SdkError_MaxDepositClaimFeeExceeded ||
      error is SdkError_MissingUtxo ||
      error is SdkError_ChainServiceError;

  /// Fresh SDK view of one outpoint; null once it is no longer pending.
  Future<DepositInfo?> liveDeposit({
    required String walletId,
    required String txid,
    required int vout,
  }) async {
    if (walletId.isEmpty || currentWalletId() != walletId) {
      throw _walletChanged;
    }
    final sdk = await _loadSdk(walletId);
    return _findDeposit(sdk, txid, vout);
  }

  /// Outcome for an outpoint that a fresh read no longer lists.
  Future<SparkDepositClaimResult> missingDepositOutcome({
    required String walletId,
    required String txid,
    required int vout,
  }) async {
    if (walletId.isEmpty || currentWalletId() != walletId) {
      throw _walletChanged;
    }
    final sdk = await _loadSdk(walletId);
    return _missingDepositOutcome(sdk, txid, vout);
  }

  Future<SparkDepositClaimResult> claim({
    required String walletId,
    required String txid,
    required int vout,
    required BigInt maxFeeSats,
    required BigInt depositAmountSats,
  }) async {
    if (maxFeeSats <= BigInt.zero || maxFeeSats >= depositAmountSats) {
      throw const SparkDepositActionException(
          SparkDepositActionReason.invalidFee);
    }
    return _run(
      walletId: walletId,
      txid: txid,
      vout: vout,
      execute: (sdk) async {
        final deposit = await _findDeposit(sdk, txid, vout);
        if (currentWalletId() != walletId) throw _walletChanged;
        if (deposit == null) return _missingDepositOutcome(sdk, txid, vout);
        if (!deposit.isMature) {
          throw const SparkDepositActionException(
              SparkDepositActionReason.immature);
        }
        if (deposit.refundTxId?.isNotEmpty == true ||
            deposit.refundTx?.isNotEmpty == true) {
          throw const SparkDepositActionException(
              SparkDepositActionReason.refundInProgress);
        }
        if (maxFeeSats >= deposit.amountSats) {
          throw const SparkDepositActionException(
              SparkDepositActionReason.invalidFee);
        }
        try {
          final response = await sdk.claimDeposit(
            request: ClaimDepositRequest(
              txid: txid,
              vout: vout,
              maxFee: MaxFee.fixed(amount: maxFeeSats),
            ),
          );
          return _claimResult(response.outcome);
        } on SdkError_DepositClaimInProgress {
          // The SDK's own auto-claim holds this outpoint right now.
          throw const SparkDepositActionException(
              SparkDepositActionReason.busy);
        } on SparkDepositActionException {
          rethrow;
        } catch (error, stackTrace) {
          // The service may commit before the SDK errors, or auto-claim may
          // win the race. Only a row that is still pending can be a failure.
          final DepositInfo? stillPending;
          try {
            stillPending = await _findDeposit(sdk, txid, vout);
          } catch (_) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          if (stillPending == null) {
            return _missingDepositOutcome(sdk, txid, vout);
          }
          // A rejected quote or claim stores a new claim error. A transfer
          // lookup that fails after the service accepted the claim does not,
          // and the SDK keeps the row until the transfer event arrives.
          if (_failedBeforeClaim(error) ||
              stillPending.claimError != deposit.claimError) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          return SparkDepositClaimResult(
              await _depositReceived(sdk, txid, vout)
                  ? SparkDepositClaimOutcome.alreadyReceived
                  : SparkDepositClaimOutcome.statusUnknown);
        }
      },
    );
  }

  Future<RefundDepositResponse> refund({
    required String walletId,
    required String txid,
    required int vout,
    required String address,
    required BigInt satPerVbyte,
  }) async {
    if (address.trim().isEmpty) {
      throw const SparkDepositActionException(
          SparkDepositActionReason.invalidAddress);
    }
    if (satPerVbyte <= BigInt.zero) {
      throw const SparkDepositActionException(
          SparkDepositActionReason.invalidFee);
    }
    return _run(
      walletId: walletId,
      txid: txid,
      vout: vout,
      execute: (sdk) => sdk.refundDeposit(
        request: RefundDepositRequest(
          txid: txid,
          vout: vout,
          destinationAddress: address.trim(),
          fee: Fee.rate(satPerVbyte: satPerVbyte),
        ),
      ),
    );
  }
}
