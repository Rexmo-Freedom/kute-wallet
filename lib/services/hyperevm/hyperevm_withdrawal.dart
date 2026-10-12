// lib/services/hyperevm/hyperevm_withdrawal.dart
//
// The funding steps of an Investing withdrawal through HyperEVM, run by
// the settlement runner's `fund` call after the record reached
// `broadcasting` (and holding [HyperEvmVaultLock] for the address):
//
//  1. HyperCore → HyperEVM: `sendAsset` of the USDC still needed to the
//     USDC system address (0x2000…0000), from perpetuals or spot, or from
//     the one balance of a unified account. Its nonce is persisted before
//     the POST. USDC already sitting on the HyperEVM address (a stopped
//     withdrawal, a refund) counts toward the amount first.
//  2. Wait for the USDC to land on HyperEVM (balance poll, about a dozen
//     calls over at most a minute).
//  3. USDC `transfer` to the quote's deposit address. Its hash and nonce
//     are persisted before the broadcast.
//  4. Wait for the receipt; the hash is the proof Orchestra verifies.
//
// Anything that stops before step 3 is broadcast throws
// [SettlementFundingRefused]: nothing reached Orchestra, the record ends
// `notFunded`, and USDC already moved to HyperEVM is the account's own,
// shown as pending Investing balance and swept back by [HyperEvmSweeper].

import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_rpc.dart';
import 'package:kute/services/hyperevm/hyperevm_tx.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';
import 'package:kute/services/security/address_guard.dart';

/// The HyperCore account refused the HyperCore → HyperEVM transfer (for
/// example an account mode that disables it). Nothing moved.
class HyperEvmCoreTransferRefused implements Exception {
  const HyperEvmCoreTransferRefused(this.cause);
  final Object cause;

  @override
  String toString() => 'HyperEvmCoreTransferRefused';
}

/// The provider transfer was sent and is not mined yet. The record stays
/// `fundingUnknown` for the reconciler, which reads the receipt.
class HyperEvmTransferUnconfirmed implements Exception {
  const HyperEvmTransferUnconfirmed();

  @override
  String toString() => 'HyperEvmTransferUnconfirmed';
}

/// One step reached, for analytics: `core_to_evm`, `evm_arrived`,
/// `provider_sent`, with the time since the steps began.
typedef HyperEvmStepReport = void Function(String step, Duration elapsed);

class HyperEvmWithdrawalSteps {
  HyperEvmWithdrawalSteps({
    required this.reader,
    required this.journal,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.arrivalTimeout = const Duration(seconds: 60),
    this.receiptTimeout = const Duration(seconds: 45),
  })  : _clock = clock ?? DateTime.now,
        _sleep = sleep;

  final HyperEvmReader reader;
  final HyperEvmTxJournal journal;
  final DateTime Function() _clock;
  final Future<void> Function(Duration)? _sleep;
  final Duration arrivalTimeout;
  final Duration receiptTimeout;

  /// Runs the steps and returns the provider transfer's hash.
  ///
  /// [ensurePayable] throws when the quote no longer has the margin a
  /// send needs; it runs before each transfer. [persist] writes a funding
  /// patch at `broadcasting` and must throw when the write did not apply.
  Future<String> run({
    required HyperEvmSigner signer,
    required String depositAddress,
    required BigInt amountMicros,
    required void Function() ensurePayable,
    required Future<void> Function(
            SettlementFunding Function(SettlementFunding current) patch)
        persist,
    HyperEvmStepReport? onStep,
  }) async {
    final started = _clock();
    void step(String name) => onStep?.call(name, _clock().difference(started));
    final address = signer.address;
    var providerSigned = false;
    try {
      if (amountMicros <= BigInt.zero) throw ArgumentError('amount');
      if (!isEvmAddress(depositAddress) ||
          sameEvmAddress(depositAddress, address) ||
          HyperEvmChain.forbiddenTransferRecipients
              .contains(depositAddress.toLowerCase())) {
        throw const HyperEvmTxRefused('recipient');
      }
      if (await resolveHyperEvmJournal(
              address: address,
              journal: journal,
              reader: reader,
              now: _clock()) ==
          HyperEvmJournalStatus.pending) {
        throw const HyperEvmTransactionPending();
      }
      final before = await reader.evm(address);
      if (before.hasPendingTransaction) {
        throw const HyperEvmTransactionPending();
      }
      final parked = before.usdcMicros;
      final stage = amountMicros > parked ? amountMicros - parked : BigInt.zero;
      if (stage > BigInt.zero) {
        // HyperCore amounts carry eight decimals; HyperEVM USDC six.
        final amount = stage * BigInt.from(100);
        ensurePayable();
        final sourceDex =
            await signer.gatherUsdc(amount, beforeSend: ensurePayable);
        try {
          await signer.coreToEvm(
            token: HyperCoreTokens.usdc,
            amount: amount,
            sourceDex: sourceDex,
            onBeforePost: (nonce) => persist(
                (current) => current.copyWith(
                    kind: SettlementFundingKind.evm, hlNonce: nonce)),
            beforeSend: ensurePayable,
          );
        } catch (e) {
          if (e is StateError || e is ArgumentError) rethrow;
          throw HyperEvmCoreTransferRefused(e);
        }
        step('core_to_evm');
        await pollHyperEvm<BigInt>(
          read: () => reader.evmUsdc(address),
          done: (usdc) => usdc >= parked + stage,
          schedule: hyperEvmPollSchedule(arrivalTimeout),
          sleep: _sleep,
        );
        step('evm_arrived');
      }
      ensurePayable();
      final hash = await signer.sendEvmTx(
        kind: HyperEvmTxKind.usdcTransfer,
        to: depositAddress,
        amount: amountMicros,
        onSigned: (hash, nonce) async {
          await persist((current) => current.copyWith(
              kind: SettlementFundingKind.evm,
              evmTxHash: hash,
              evmNonce: nonce));
          providerSigned = true;
        },
      );
      step('provider_sent');
      final receipt = await waitForHyperEvmReceipt(reader, hash,
          total: receiptTimeout, sleep: _sleep);
      if (receipt == null) throw const HyperEvmTransferUnconfirmed();
      if (!receipt.success) {
        // Mined and reverted: the USDC never left the HyperEVM address.
        throw SettlementFundingRefused(const HyperEvmTxRefused('reverted'));
      }
      return hash;
    } on SettlementFundingRefused {
      rethrow;
    } on HyperEvmBroadcastUncertain {
      // Signed and persisted; a node may hold it. The reconciler settles
      // it from the receipt or the nonce.
      rethrow;
    } on HyperEvmTransferUnconfirmed {
      rethrow;
    } catch (e) {
      if (providerSigned && !(e is HyperEvmRpcException && e.isNodeError)) {
        rethrow;
      }
      // A node refused the signed transfer, or nothing was signed for the
      // provider at all: nothing reached Orchestra.
      throw SettlementFundingRefused(e);
    }
  }
}

/// The reconciler's read of a HyperEVM withdrawal left at `broadcasting`
/// or `fundingUnknown` by a kill or an unconfirmed transfer. Public chain
/// data only; nothing is signed or sent.
///
///  - no provider transfer hash on the record: it was never signed (the
///    hash is persisted before any broadcast), so nothing reached the
///    provider: proven not sent;
///  - a receipt: confirmed when it succeeded, proven not sent when it
///    reverted;
///  - no receipt, a node still knows it: inconclusive;
///  - no receipt, unknown, and the account's nonce moved past it: the
///    slot went to another transaction: proven not sent;
///  - unknown and unmined 30 minutes after the quote expired: dropped,
///    and never rebroadcast (the signed bytes were not kept): proven not
///    sent. Otherwise inconclusive.
Future<({HyperEvmFundingProbe probe, String? hash})> probeHyperEvmWithdrawal({
  required SettlementOperation op,
  required HyperEvmReader reader,
  required DateTime now,
}) async {
  final hash = op.funding?.evmTxHash;
  if (hash == null || hash.isEmpty) {
    return (probe: HyperEvmFundingProbe.provenNotSent, hash: null);
  }
  final receipt = await reader.receipt(hash);
  if (receipt != null) {
    return (
      probe: receipt.success
          ? HyperEvmFundingProbe.confirmed
          : HyperEvmFundingProbe.provenNotSent,
      hash: receipt.success ? hash : null,
    );
  }
  if (await reader.isKnownTransaction(hash)) {
    return (probe: HyperEvmFundingProbe.inconclusive, hash: null);
  }
  final nonce = op.funding?.evmNonce;
  final owner = op.refund?.address;
  if (nonce != null && owner != null && await reader.nonce(owner) > nonce) {
    // Re-read: the transaction may have been mined between the reads.
    final late = await reader.receipt(hash);
    if (late != null && late.success) {
      return (probe: HyperEvmFundingProbe.confirmed, hash: hash);
    }
    return (probe: HyperEvmFundingProbe.provenNotSent, hash: null);
  }
  final expiresAt = op.quote?.expiresAt;
  if (expiresAt != null &&
      now.add(op.quote!.skew).isAfter(
          expiresAt.add(const Duration(minutes: 30)))) {
    return (probe: HyperEvmFundingProbe.provenNotSent, hash: null);
  }
  return (probe: HyperEvmFundingProbe.inconclusive, hash: null);
}

/// What [probeHyperEvmWithdrawal] concluded. Mirrors the reconciler's
/// funding-source probe without importing it.
enum HyperEvmFundingProbe { confirmed, provenNotSent, inconclusive }
