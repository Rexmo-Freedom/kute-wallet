// lib/services/funding/ledger_hypercore_funding_service.dart
//
// Ledger BTC to and from HyperCore USDC through Orchestra (Wallet
// hardening Phase 4, P4.10, plan B11), recorded in the Phase 5 settlement
// store.
//
// Forward (`ledger_btc_to_hypercore_v1`):
//   1. The refund address is a Ledger receive address confirmed on the
//      device ([LedgerVerifiedBtcAddress]); the recipient is the verified
//      Ledger EVM address. Both come from the Ledger rows of the Phase 5
//      ownership table, never from a backend response.
//   2. Route availability is the Phase 5 live catalog query; quote
//      `bitcoin:BTC` to `hypercore:USDC` through the Phase 2 gate. The
//      operation is created at `quoted` before any device prompt.
//   3. Build the PSBT to the deposit address (`reviewed`), sign on the
//      Ledger (`authorizing`, then `signed` with txid, vout and inputs on
//      disk). The B5 margins apply before the prompt and after it.
//   4. On an expired quote: no broadcast, the operation is `abandoned`.
//      The caller re-quotes, re-reviews and re-signs.
//   5. `broadcasting` is flushed before the broadcast; a failed write means
//      no broadcast. A failed broadcast call is `fundingUnknown`.
//   6. `funded` with the proof and a submit key, then `submitDeposit`
//      (bitcoinTxid and bitcoinVout) with that key. A failed submit stays
//      `funded`; the Phase 5 reconciler retries it and never re-signs or
//      re-broadcasts.
//   Moving USDC from spot to perps afterwards is a separate readable
//   `usdClassTransfer` (O7), not part of this service.
//
// Reverse uses native USDC spotSend, approved on the Ledger. If needed,
// moving uncommitted perp cash to spot is a separate device approval.
// The recipient is always a device-verified Ledger Bitcoin address.

import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/funding/ledger_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show
        LedgerBtcAddressProof,
        SettlementOwnership,
        resolveLedgerSettlementOwnership;
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/funding/ledger_hypercore_source_send.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

const String kLedgerBtcToHypercoreRouteVersion = 'ledger_btc_to_hypercore_v1';
const String kHypercoreToLedgerBtcRouteVersion = 'hypercore_to_ledger_btc_perps_v2';

/// HyperCore USDC carries 8 decimals on Orchestra (pinned in
/// `orchestra_router.dart`).
const int kHypercoreUsdcDecimals = 8;

final RouteKey kLedgerBtcToHypercoreRoute = RouteKey(
    fromChain: 'bitcoin',
    fromAsset: 'BTC',
    toChain: 'hypercore',
    toAsset: 'USDC');
final RouteKey kHypercoreToLedgerBtcRoute = RouteKey(
    fromChain: 'hypercore',
    fromAsset: 'USDC',
    toChain: 'bitcoin',
    toAsset: 'BTC');

/// Opens the existing app-authentication and Ledger approval flow for one
/// reviewed action. Only the native send receives a pre-POST persistence hook.
typedef LedgerHypercoreApproval = Future<int> Function(
  LedgerActionIntent intent, {
  Future<void> Function(int nonce)? onBeforeSend,
  void Function()? beforeSend,
});

abstract interface class HypercoreReverseSourceSend {
  bool get isReady;
  int get deviceConfirmations;
  Future<BigInt> activationFeeForDestination(String depositAddress);

  Future<String> sendToDeposit({
    required String walletId,
    required String evmAddress,
    required String depositAddress,
    required BigInt amountBaseUnits,
    required BigInt reviewedActivationFeeBaseUnits,
    required String quoteId,
    required LedgerHypercoreApproval approve,
    required Future<void> Function() onBeforeInternalSend,
    required Future<void> Function(int nonce) onBeforeSend,
  });
}

// ───────────────────────────── errors ────────────────────────────────────

enum LedgerFundingError {
  notLedger('not_ledger'),
  evmNotVerified('evm_not_verified'),
  refundNotOwn('refund_not_own'),
  recipientNotOwn('recipient_not_own'),
  recipientIsSpark('recipient_is_spark'),
  routeUnavailable('route_unavailable'),
  reverseNotReady('reverse_not_ready'),
  quoteBindingMismatch('quote_binding_mismatch'),
  invalidAmount('invalid_amount');

  const LedgerFundingError(this.code);
  final String code;
}

class LedgerFundingException implements Exception {
  const LedgerFundingException(this.error);
  final LedgerFundingError error;

  @override
  String toString() => 'LedgerFundingException(${error.code})';
}

/// The broadcast (forward) or source send (reverse) call failed after
/// `broadcasting` was persisted. Funds may have moved: never "Nothing was
/// sent". The operation is `fundingUnknown` for the reconciler.
class LedgerFundingOutcomeUnknown implements Exception {
  const LedgerFundingOutcomeUnknown(this.operationId, this.cause);
  final String operationId;
  final Object cause;

  @override
  String toString() => 'LedgerFundingOutcomeUnknown';
}

sealed class LedgerFundingOutcome {
  const LedgerFundingOutcome();
}

/// Funds moved and Orchestra accepted the deposit.
class LedgerFundingSubmitted extends LedgerFundingOutcome {
  const LedgerFundingSubmitted(this.operationId, {this.orderId});
  final String operationId;
  final String? orderId;
}

/// Funds moved; Orchestra has not accepted the deposit yet. The operation
/// stays `funded` and the Phase 5 reconciler retries the submit with the
/// persisted key. Never resend funds.
class LedgerFundingSubmitPending extends LedgerFundingOutcome {
  const LedgerFundingSubmitPending(this.operationId);
  final String operationId;
}

/// The quote expired before the broadcast or source send. Nothing moved and
/// the operation is `abandoned`. Re-quote, show the new review and sign
/// again.
class LedgerFundingQuoteExpired extends LedgerFundingOutcome {
  const LedgerFundingQuoteExpired({this.duringApproval = false});

  /// True when less than the B5 minimum was left after the Ledger signed:
  /// the signature was discarded and the re-review shows
  /// `settlementLedgerExpiredDuringApproval`.
  final bool duringApproval;
}

// ───────────────────────────── reviews ───────────────────────────────────

class LedgerHypercoreFundingReview {
  const LedgerHypercoreFundingReview._({
    required this.wallet,
    required this.evmAddress,
    required this.refund,
    required this.quote,
    required this.amountSats,
    required this.operationId,
    required this.skew,
  });

  final WalletConfig wallet;
  final String evmAddress;
  final LedgerVerifiedBtcAddress refund;
  final VerifiedOrchestraQuote quote;
  final int amountSats;

  /// The Phase 5 settlement operation, created at `quoted`.
  final String operationId;

  /// Server minus local clock from the quote response; null when unknown.
  final Duration? skew;

  /// Estimated USDC in HyperCore base units (8 decimals).
  String get estimatedOutBaseUnits => quote.quote.estimatedOut;
  int get feeBps => quote.quote.feeBps;
  DateTime get expiresAt => quote.expiresAt;
}

class LedgerHypercoreFundingPrepared {
  const LedgerHypercoreFundingPrepared._(this.review, this.send);
  final LedgerHypercoreFundingReview review;
  final LedgerBtcPreparedSend send;

  int get feeSats => send.feeSats;
}

class LedgerHypercoreFundingSigned {
  const LedgerHypercoreFundingSigned._(this.prepared, this.signed);
  final LedgerHypercoreFundingPrepared prepared;
  final LedgerBtcSignedSend signed;
}

class HypercoreLedgerWithdrawReview {
  const HypercoreLedgerWithdrawReview._({
    required this.wallet,
    required this.evmAddress,
    required this.recipient,
    required this.quote,
    required this.amountBaseUnits,
    required this.activationFeeBaseUnits,
    required this.operationId,
    required this.skew,
  });

  final WalletConfig wallet;
  final String evmAddress;
  final LedgerVerifiedBtcAddress recipient;
  final VerifiedOrchestraQuote quote;
  final BigInt amountBaseUnits;
  final BigInt activationFeeBaseUnits;
  BigInt get totalDebitBaseUnits => amountBaseUnits + activationFeeBaseUnits;
  final String operationId;
  final Duration? skew;

  /// Estimated sats.
  String get estimatedOutSats => quote.quote.estimatedOut;
  int get feeBps => quote.quote.feeBps;
  DateTime get expiresAt => quote.expiresAt;
}

// ───────────────────────────── service ───────────────────────────────────

typedef LedgerFundingQuoteFetcher
    = Future<({VerifiedOrchestraQuote quote, Duration? skew})> Function(
  OrchestraQuoteRequest request, {
  required double usdPerBtc,
  required String flow,
});

Future<({VerifiedOrchestraQuote quote, Duration? skew})> _gateFetch(
  OrchestraQuoteRequest request, {
  required double usdPerBtc,
  required String flow,
}) =>
    OrchestraQuoteGate.fetchVerifiedWithSkew(
      request,
      OrchestraQuoteGate.boundsFor(request, usdPerBtc: usdPerBtc),
      flow: flow,
      idempotencyKey: OrchestraService.generateIdempotencyKey(),
    );

class LedgerHypercoreFundingService {
  LedgerHypercoreFundingService({
    required LedgerBtcSendService btcSend,
    required LedgerSettlementRecords records,
    required FundingRouteAvailability availability,
    required HypercoreReverseSourceSend reverseSource,
    LedgerFundingQuoteFetcher? fetchQuote,
    DateTime Function()? clock,
    RoutePausePolicy pausePolicy = const RoutePausePolicy(),
  })  : _btc = btcSend,
        _records = records,
        _availability = availability,
        _reverse = reverseSource,
        _fetchQuote = fetchQuote ?? _gateFetch,
        _clock = clock ?? DateTime.now,
        _pause = pausePolicy;

  /// Remote pause switch for NEW Ledger funding (F16). Pending operations
  /// never consult it.
  final RoutePausePolicy _pause;

  final LedgerBtcSendService _btc;
  final LedgerSettlementRecords _records;
  final FundingRouteAvailability _availability;
  final HypercoreReverseSourceSend _reverse;
  final LedgerFundingQuoteFetcher _fetchQuote;
  final DateTime Function() _clock;

  static const String forwardFlow = 'ledger_btc_to_hypercore';
  static const String reverseFlow = 'hypercore_to_ledger_btc';

  /// Ledger prompts for the forward route: refund address, then the PSBT.
  static const int forwardDeviceConfirmations = 2;

  bool get reverseReady => _reverse.isReady;

  /// Ledger prompts for the reverse route: recipient address plus the
  /// source leg. Meaningless until [reverseReady].
  int get reverseDeviceConfirmations => 1 + _reverse.deviceConfirmations;

  Future<bool> forwardAvailable() async =>
      (await _availability.availability(kLedgerBtcToHypercoreRoute))
          .isAvailable;

  Future<bool> reverseAvailable() async =>
      _reverse.isReady &&
      (await _availability.availability(kHypercoreToLedgerBtcRoute))
          .isAvailable;

  String _requireVerifiedEvm(WalletConfig wallet) {
    if (!wallet.isLedger) {
      throw const LedgerFundingException(LedgerFundingError.notLedger);
    }
    final evm = wallet.evmAddress;
    if (!wallet.hasVerifiedEvm || evm == null || !isEvmAddress(evm)) {
      throw const LedgerFundingException(LedgerFundingError.evmNotVerified);
    }
    return evm;
  }

  /// The Phase 2 amount and expiry check plus the Phase 5 margin for
  /// [moment]. Throws [WalletGuardException] (`quoteExpired`).
  void _requireMargin(
    VerifiedOrchestraQuote quote,
    Duration? skew,
    BigInt amount,
    SettlementMoment moment,
    SettlementPayer payer,
  ) {
    OrchestraQuoteGate.ensurePayable(quote,
        amountBaseUnits: amount, now: _clock());
    final ok = SettlementQuotePolicy.hasMargin(
      expiresAt: quote.expiresAt,
      localNow: _clock(),
      skew: skew,
      moment: moment,
      payer: payer,
    );
    if (!ok) {
      throw const WalletGuardException(WalletGuardReason.quoteExpired);
    }
  }

  bool _isExpired(WalletGuardException e) =>
      e.reason == WalletGuardReason.quoteExpired;

  static LedgerBtcAddressProof _proof(LedgerVerifiedBtcAddress a) => (
        walletId: a.walletId,
        address: a.address,
        index: a.index,
        verifiedAt: a.verifiedAt,
      );

  /// A verified quote with enough time left to show a review (B5: 60 s,
  /// re-quoted silently once otherwise).
  Future<({VerifiedOrchestraQuote quote, Duration? skew})> _quoteForReview(
      OrchestraQuoteRequest request,
      {required double usdPerBtc,
      required String flow}) async {
    var fetched = await _fetchQuote(request, usdPerBtc: usdPerBtc, flow: flow);
    for (var attempt = 0; attempt < 2; attempt++) {
      final ok = SettlementQuotePolicy.hasMargin(
        expiresAt: fetched.quote.expiresAt,
        localNow: _clock(),
        skew: fetched.skew,
        moment: SettlementMoment.beforeReview,
        payer: SettlementPayer.ledgerBitcoin,
      );
      if (ok) return fetched;
      fetched = await _fetchQuote(request, usdPerBtc: usdPerBtc, flow: flow);
    }
    throw const WalletGuardException(WalletGuardReason.quoteExpired);
  }

  // ─────────────────────────── forward ───────────────────────────

  /// No device prompt. [refund] must already be device-verified for
  /// [wallet]. Creates the Phase 5 operation at `quoted`.
  ///
  /// [supersededQuoteId] is a quote an earlier attempt replaced before
  /// anything was sent; it is kept in the new operation's `quoteHistory`
  /// with [supersedeReason].
  Future<LedgerHypercoreFundingReview> quoteForward({
    required WalletConfig wallet,
    required int amountSats,
    required LedgerVerifiedBtcAddress refund,
    required double usdPerBtc,
    String? supersededQuoteId,
    String supersedeReason = 'expired_before_prompt',
  }) =>
      runLedgerFundingScope(wallet.id, () async {
        final evm = _requireVerifiedEvm(wallet);
        if (amountSats <= 0) {
          throw const LedgerFundingException(LedgerFundingError.invalidAmount);
        }
        if (refund.walletId != wallet.id) {
          throw const LedgerFundingException(LedgerFundingError.refundNotOwn);
        }
        // F16: a remote pause blocks new Ledger funding before any quote.
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        // F11 before any quote: an unresolved earlier funding blocks this one.
        if (!await forwardAvailable()) {
          throw const LedgerFundingException(
              LedgerFundingError.routeUnavailable);
        }
        // Ownership before any quote (B4).
        final SettlementOwnership ownership = resolveLedgerSettlementOwnership(
          walletId: wallet.id,
          route: kLedgerBtcToHypercoreRoute,
          source: SettlementAccountKind.ledgerBtc,
          destination: SettlementAccountKind.hlLedger,
          verifiedEvmAddress: evm,
          verifiedBtc: _proof(refund),
        );
        final request = OrchestraQuoteRequest(
          sourceChain: 'bitcoin',
          sourceAsset: 'BTC',
          destinationChain: 'hypercore',
          destinationAsset: 'USDC',
          amountBaseUnits: BigInt.from(amountSats),
          recipientAddress: ownership.recipient.address,
          refundAddress: ownership.refund.address,
          recipientKind: RecipientKind.ownEvm,
          ownAddress: ownership.recipient.address,
        );
        final fetched = await _quoteForReview(request,
            usdPerBtc: usdPerBtc, flow: forwardFlow);
        final quote = fetched.quote;
        if (!sameEvmAddress(quote.request.recipientAddress, evm) ||
            quote.request.refundAddress != refund.address ||
            quote.amountIn != BigInt.from(amountSats)) {
          throw const LedgerFundingException(
              LedgerFundingError.quoteBindingMismatch);
        }
        final op = await _records.start(
          walletId: wallet.id,
          accountKind: SettlementAccountKind.ledgerBtc,
          flow: SettlementFlow.ledgerBtcToInvesting,
          routeVersion: kLedgerBtcToHypercoreRouteVersion,
          route: kLedgerBtcToHypercoreRoute,
          quote: quote,
          recipient: ownership.recipient,
          refund: ownership.refund,
          skew: fetched.skew,
          quoteHistory: [
            if (supersededQuoteId != null)
              SettlementQuoteHistoryEntry(
                quoteId: supersededQuoteId,
                reason: supersedeReason,
                supersededAt: _clock(),
              ),
          ],
        );
        return LedgerHypercoreFundingReview._(
          wallet: wallet,
          evmAddress: evm,
          refund: refund,
          quote: quote,
          amountSats: amountSats,
          operationId: op.operationId,
          skew: fetched.skew,
        );
      });

  /// Builds the PSBT to the deposit address. No device prompt. The
  /// operation moves to `reviewed`. Throws [WalletGuardException]
  /// (`quoteExpired`) when the quote is too close to expiry to start; the
  /// operation is then `abandoned`.
  Future<LedgerHypercoreFundingPrepared> prepareForward(
    LedgerHypercoreFundingReview review, {
    required double feeRateSatVb,
    List<OutPoint>? selectedUtxos,
  }) =>
      runLedgerFundingScope(review.wallet.id, () async {
        final opId = review.operationId;
        try {
          OrchestraQuoteGate.ensurePayable(review.quote,
              amountBaseUnits: BigInt.from(review.amountSats), now: _clock());
          await _records.advance(opId, SettlementStage.reviewed);
          // F4: conflict with every earlier funding whose outcome is unknown.
          final mustSpend = await _records.mustSpendOutpointsFor(
              review.wallet.id, kLedgerBtcToHypercoreRoute);
          final send = await _btc.prepare(
            wallet: review.wallet,
            destination: review.quote.depositAddress,
            amountSats: review.amountSats,
            feeRateSatVb: feeRateSatVb,
            selectedUtxos: selectedUtxos,
            mustSpendOutpoints: mustSpend,
          );
          if (send.walletId != review.wallet.id ||
              send.destination.trim() != review.quote.depositAddress.trim() ||
              send.amountSats != review.amountSats) {
            throw const LedgerFundingException(
                LedgerFundingError.quoteBindingMismatch);
          }
          return LedgerHypercoreFundingPrepared._(review, send);
        } catch (_) {
          await _records.abandon(opId);
          rethrow;
        }
      });

  /// One Ledger prompt. Nothing is broadcast. The operation is
  /// `authorizing` during the prompt and `signed` (txid, vout and inputs)
  /// after it; any failure abandons it.
  Future<LedgerHypercoreFundingSigned> signForward(
          LedgerHypercoreFundingPrepared prepared) =>
      runLedgerFundingScope(prepared.review.wallet.id, () async {
        final review = prepared.review;
        final opId = review.operationId;
        try {
          _requireMargin(
              review.quote,
              review.skew,
              BigInt.from(review.amountSats),
              SettlementMoment.beforeDevicePrompt,
              SettlementPayer.ledgerBitcoin);
          await _records.hold(opId);
          await _records.advance(opId, SettlementStage.authorizing);
          final signed = await _btc.sign(prepared.send);
          await _records.recordSigned(
            opId,
            txid: signed.txid,
            vout: signed.vout,
            inputs: [
              for (final input in prepared.send.inputs)
                '${input.txid}:${input.vout}',
            ],
          );
          return LedgerHypercoreFundingSigned._(prepared, signed);
        } catch (_) {
          await _records.abandon(opId);
          rethrow;
        }
      });

  /// Expiry check, `broadcasting`, broadcast, `funded`, submit. Throws
  /// [LedgerFundingOutcomeUnknown] when the broadcast call fails.
  Future<LedgerFundingOutcome> broadcastForward(
          LedgerHypercoreFundingSigned signed) =>
      runLedgerFundingScope(signed.prepared.review.wallet.id, () async {
        final review = signed.prepared.review;
        final opId = review.operationId;
        final amount = BigInt.from(review.amountSats);
        try {
          try {
            _requireMargin(
                review.quote,
                review.skew,
                amount,
                SettlementMoment.afterDeviceSigned,
                SettlementPayer.ledgerBitcoin);
          } on WalletGuardException catch (e) {
            // The device signed with less than the B5 minimum left: the
            // signature is discarded and nothing is broadcast.
            await _records.abandon(opId);
            if (_isExpired(e)) {
              return const LedgerFundingQuoteExpired(duringApproval: true);
            }
            rethrow;
          }

          // I1: no durable `broadcasting`, no broadcast.
          try {
            await _records.advance(opId, SettlementStage.broadcasting);
          } catch (_) {
            await _records.abandon(opId);
            rethrow;
          }

          // The proof is the txid persisted at `signed`; a node answer for any
          // other txid is not proof of this transaction.
          final txid = signed.signed.txid;
          try {
            final reported = await _btc.broadcast(signed.signed);
            if (reported.trim().toLowerCase() != txid) {
              throw StateError('broadcast_txid_mismatch');
            }
          } catch (e) {
            await _records.advanceBestEffort(
                opId, SettlementStage.fundingUnknown);
            throw LedgerFundingOutcomeUnknown(opId, e);
          }
          await _records.recordFunded(
            opId,
            SettlementFunding(
              kind: SettlementFundingKind.bitcoin,
              btcTxid: txid,
              btcVout: signed.signed.vout,
              btcInputs: [
                for (final input in signed.prepared.send.inputs)
                  '${input.txid}:${input.vout}',
              ],
            ),
          );
          return await _submit(opId);
        } finally {
          await _records.release(opId);
        }
      });

  // ─────────────────────────── reverse ───────────────────────────

  /// No device prompt. [recipient] must be a device-verified receive
  /// address of [wallet].
  Future<HypercoreLedgerWithdrawReview> quoteReverse({
    required WalletConfig wallet,
    required BigInt amountBaseUnits,
    required LedgerVerifiedBtcAddress recipient,
    required double usdPerBtc,
  }) =>
      runLedgerFundingScope(wallet.id, () async {
        final evm = _requireVerifiedEvm(wallet);
        if (!_reverse.isReady) {
          throw const LedgerFundingException(
              LedgerFundingError.reverseNotReady);
        }
        // F16: a remote pause blocks new Ledger funding before any quote.
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        if (amountBaseUnits <= BigInt.zero) {
          throw const LedgerFundingException(LedgerFundingError.invalidAmount);
        }
        if (recipient.walletId != wallet.id) {
          throw const LedgerFundingException(
              LedgerFundingError.recipientNotOwn);
        }
        // Never a return leg to hot Spark.
        if (isSparkAddress(recipient.address, mainnet: true) ||
            isSparkAddress(recipient.address, mainnet: false)) {
          throw const LedgerFundingException(
              LedgerFundingError.recipientIsSpark);
        }
        if (!await reverseAvailable()) {
          throw const LedgerFundingException(
              LedgerFundingError.routeUnavailable);
        }
        final ownership = resolveLedgerSettlementOwnership(
          walletId: wallet.id,
          route: kHypercoreToLedgerBtcRoute,
          source: SettlementAccountKind.hlLedger,
          destination: SettlementAccountKind.ledgerBtc,
          verifiedEvmAddress: evm,
          verifiedBtc: _proof(recipient),
        );
        final allocated = await quoteHypercoreBudget(
          budget: amountBaseUnits,
          request: (netAmount, attempt) async {
            final request = OrchestraQuoteRequest(
              sourceChain: 'hypercore',
              sourceAsset: 'USDC',
              destinationChain: 'bitcoin',
              destinationAsset: 'BTC',
              amountBaseUnits: netAmount,
              recipientAddress: ownership.recipient.address,
              refundAddress: ownership.refund.address,
              // No own-Ledger-BTC kind exists in the guard; ownership is enforced
              // above through the device-verified address.
              recipientKind: RecipientKind.external,
            );
            final fetched = await _quoteForReview(request,
                usdPerBtc: usdPerBtc, flow: reverseFlow);
            final quote = fetched.quote;
            if (quote.request.recipientAddress != recipient.address ||
                !sameEvmAddress(quote.request.refundAddress, evm) ||
                quote.amountIn != netAmount) {
              throw const LedgerFundingException(
                  LedgerFundingError.quoteBindingMismatch);
            }
            final activationFee =
                await _reverse.activationFeeForDestination(quote.depositAddress);
            return HypercoreBudgetQuote(value: fetched,
                amount: quote.amountIn, activationFee: activationFee);
          },
        );
        final fetched = allocated.value;
        final quote = fetched.quote;
        final activationFee = allocated.activationFee;
        final op = await _records.start(
          walletId: wallet.id,
          accountKind: SettlementAccountKind.hlLedger,
          flow: SettlementFlow.investingToLedgerBtc,
          routeVersion: kHypercoreToLedgerBtcRouteVersion,
          route: kHypercoreToLedgerBtcRoute,
          quote: quote,
          recipient: ownership.recipient,
          refund: ownership.refund,
          skew: fetched.skew,
        );
        return HypercoreLedgerWithdrawReview._(
          wallet: wallet,
          evmAddress: evm,
          recipient: recipient,
          quote: quote,
          amountBaseUnits: quote.amountIn,
          activationFeeBaseUnits: activationFee,
          operationId: op.operationId,
          skew: fetched.skew,
        );
      });

  /// `broadcasting`, then the HyperCore source leg (device prompts and the
  /// POST), then `funded` and submit.
  Future<LedgerFundingOutcome> executeReverse(
    HypercoreLedgerWithdrawReview review, {
    required LedgerHypercoreApproval approve,
  }) =>
      runLedgerFundingScope(review.wallet.id, () async {
        final opId = review.operationId;
        if (!_reverse.isReady) {
          await _records.abandon(opId);
          throw const LedgerFundingException(
              LedgerFundingError.reverseNotReady);
        }
        try {
          try {
            _requireMargin(
                review.quote,
                review.skew,
                review.amountBaseUnits,
                SettlementMoment.beforeDevicePrompt,
                SettlementPayer.ledgerHypercore);
          } on WalletGuardException catch (e) {
            await _records.abandon(opId);
            if (_isExpired(e)) return const LedgerFundingQuoteExpired();
            rethrow;
          }

          // Keep the operation owned while the user reviews device approvals.
          try {
            await _records.hold(opId);
            await _records.advance(opId, SettlementStage.reviewed);
            await _records.advance(opId, SettlementStage.authorizing);
          } catch (_) {
            await _records.abandon(opId);
            rethrow;
          }

          var postStarted = false;
          var externalPostStarted = false;
          final String txHash;
          try {
            txHash = await _reverse.sendToDeposit(
              walletId: review.wallet.id,
              evmAddress: review.evmAddress,
              depositAddress: review.quote.depositAddress,
              amountBaseUnits: review.amountBaseUnits,
              reviewedActivationFeeBaseUnits: review.activationFeeBaseUnits,
              quoteId: review.quote.quoteId,
              approve: (intent, {onBeforeSend, beforeSend}) => approve(
                intent,
                onBeforeSend: onBeforeSend,
                beforeSend: () {
                  _requireMargin(review.quote, review.skew,
                      review.amountBaseUnits, SettlementMoment.afterDeviceSigned,
                      SettlementPayer.ledgerHypercore);
                  beforeSend?.call();
                },
              ),
              onBeforeInternalSend: () async {
                if (postStarted) {
                  throw StateError('Native internal move already submitted');
                }
                _requireMargin(review.quote, review.skew,
                    review.amountBaseUnits, SettlementMoment.afterDeviceSigned,
                    SettlementPayer.ledgerHypercore);
                await _records.advance(opId, SettlementStage.broadcasting);
                postStarted = true;
              },
              onBeforeSend: (nonce) async {
                if (externalPostStarted) {
                  throw StateError('Native funding already submitted');
                }
                _requireMargin(
                    review.quote,
                    review.skew,
                    review.amountBaseUnits,
                    SettlementMoment.afterDeviceSigned,
                    SettlementPayer.ledgerHypercore);
                await _records.advance(
                  opId,
                  SettlementStage.broadcasting,
                  patch: (current) => current.copyWith(
                      funding: SettlementFunding(
                    kind: SettlementFundingKind.hyperliquid,
                    hlNonce: nonce,
                  )),
                );
                postStarted = true;
                externalPostStarted = true;
              },
            );
          } catch (e) {
            if (!postStarted && e is WalletGuardException && _isExpired(e)) {
              await _records.abandon(opId);
              return const LedgerFundingQuoteExpired(duringApproval: true);
            }
            // Only an unstarted POST or an explicit venue rejection proves
            // the external deposit was not funded.
            final notSent = !postStarted ||
                e is HyperliquidRejectedException ||
                e is SettlementFundingNotStarted;
            if (notSent) {
              try {
                await _records.advance(opId, postStarted
                    ? SettlementStage.notFunded : SettlementStage.abandoned);
              } catch (writeError) {
                throw LedgerFundingOutcomeUnknown(opId, writeError);
              }
              if (e is SettlementFundingRefused) throw e.cause;
              rethrow;
            }
            await _records.advanceBestEffort(
                opId, SettlementStage.fundingUnknown);
            throw LedgerFundingOutcomeUnknown(opId, e);
          }
          await _records.recordFunded(
            opId,
            SettlementFunding(
              kind: SettlementFundingKind.hyperliquid,
              evmTxHash: txHash,
              hlActionHash: txHash,
            ),
          );
          return await _submit(opId);
        } finally {
          await _records.release(opId);
        }
      });

  // ─────────────────────────── submit ────────────────────────────

  Future<LedgerFundingOutcome> _submit(String operationId) async {
    final result = await _records.submit(operationId);
    return result.accepted
        ? LedgerFundingSubmitted(operationId, orderId: result.orderId)
        : LedgerFundingSubmitPending(operationId);
  }

  // ─────────────────────────── amounts ───────────────────────────

  /// Exact decimal to base units. Accepts `.` or `,`. Null when malformed,
  /// negative or more precise than [decimals].
  static BigInt? parseDecimalBaseUnits(String input, int decimals) {
    final s = input.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(s);
    if (s.isEmpty || match == null) return null;
    final whole = match.group(1) ?? '';
    final frac = match.group(2) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    if (frac.length > decimals) return null;
    return BigInt.parse(
        '${whole.isEmpty ? '0' : whole}${frac.padRight(decimals, '0')}');
  }
}

// ───────────────────────────── providers ─────────────────────────────────

final hypercoreReverseSourceSendProvider = Provider<HypercoreReverseSourceSend>(
    (ref) => LedgerHypercoreSourceSendNative(ref.read));

final ledgerHypercoreFundingServiceProvider =
    Provider<LedgerHypercoreFundingService>((ref) {
  return LedgerHypercoreFundingService(
    btcSend: ref.watch(ledgerBtcSendServiceProvider),
    records: ref.watch(ledgerSettlementRecordsProvider),
    availability: ref.watch(ledgerFundingRouteAvailabilityProvider),
    reverseSource: ref.watch(hypercoreReverseSourceSendProvider),
    pausePolicy: ref.watch(routePausePolicyProvider),
  );
});
