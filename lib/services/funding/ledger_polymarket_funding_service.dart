// lib/services/funding/ledger_polymarket_funding_service.dart
//
// Ledger BTC to and from Polymarket (Wallet hardening Phase 4, P4.11,
// plan B11).
//
// Forward: Ledger BTC -> Orchestra -> Polygon USDC.e in this Ledger's
// deposit wallet, then a separate "Make funds available" batch (exact
// approve plus wrap into pUSD) that passes the Phase 3 allowlist.
//
// Reverse: available collateral only. pUSD is unwrapped first (its own
// batch: exact pUSD approval to the offramp, then the unwrap), then the O3-gated USDC.e transfer to the quote-bound Orchestra
// deposit address, then `submitDeposit(txHash, sourceAddress)`. Open
// positions are never withdrawable; they must be sold or claimed first as
// separate actions. With `kLedgerPolymarketWithdrawEnabled` off (default)
// the whole reverse route refuses before any read, prompt or quote.
//
// Rules held here:
// * No phone signer exists for a Ledger account. This service takes no
//   key, mnemonic or credentials; BTC is signed by the Ledger Bitcoin app
//   and batches by the Ledger Ethereum app through the Phase 3 executor.
// * Recipient and refund addresses are resolved from this wallet (never
//   from a backend response) and must belong to the selected Ledger: the
//   deposit wallet is re-derived from the device-verified EVM address, the
//   BTC address is confirmed on the device.
// * The operation is a Phase 5 `SettlementOperation` written through
//   [LedgerSettlementRecords]: created before any device prompt, `signed`
//   with txid, vout and inputs, and `broadcasting` on disk before the
//   broadcast or relayer call. A failed write means no broadcast. The
//   Phase 5 reconciler retries a failed submit with the persisted key.
// * Route availability is the Phase 5 live catalog query.
// * An expired quote is never broadcast. The signed transaction is
//   discarded; the caller re-quotes, re-reviews and the user signs again.
// * The return leg never goes to hot Spark.
// * The deposit wallet is deployed only after the user explicitly
//   confirmed it in the explainer sheet.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/bitcoin_provider.dart'
    show getCustomFeeRateProvider;
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart'
    show ledgerPolymarketReadsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show walletReceiveInfoProvider;
import 'package:kute/services/ledger_service.dart' show ledgerServiceProvider;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/funding/ledger_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show SettlementOwnership, resolveLedgerSettlementOwnership;
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hardware/ledger/deposit_wallet_call_allowlist.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart'
    show LedgerSubmissionUnknownException;
import 'package:kute/services/hardware/ledger/ledger_polymarket_executor.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

// ───────────────────────────── route ids ─────────────────────────────

/// Route versions (plan B11). Phase 5's `SettlementFlow` names are
/// `ledgerBtcToPredictions` and `predictionsToLedgerBtc`.
const String kLedgerBtcToPolygonUsdceRoute = 'ledger_btc_to_polygon_usdce_v1';
const String kPolygonUsdceToLedgerBtcRoute = 'polygon_usdce_to_ledger_btc_v1';

const String _btcChain = 'bitcoin';
const String _btcAsset = 'BTC';
const String _polygonChain = 'polygon';
const String _usdceAsset = 'USDC.e';

/// Ledger approvals the forward route needs: the BTC transaction, then
/// the "Make funds available" batch. Shown upfront.
const int kLedgerPmForwardDeviceApprovals = 2;

/// Ledger approvals the reverse route needs when pUSD must be unwrapped
/// first: unwrap batch, then the transfer batch.
const int kLedgerPmReverseDeviceApprovalsWithUnwrap = 2;

final RouteKey _forwardRoute = RouteKey(
    fromChain: _btcChain,
    fromAsset: _btcAsset,
    toChain: _polygonChain,
    toAsset: _usdceAsset);
final RouteKey _reverseRoute = RouteKey(
    fromChain: _polygonChain,
    fromAsset: _usdceAsset,
    toChain: _btcChain,
    toAsset: _btcAsset);

// ─────────────────────────── flow stages ─────────────────────────────

/// Steps reported to a sheet through `executeForward(onStage:)`. The
/// durable stages live in the Phase 5 `SettlementOperation`.
enum LedgerPmFundingStage { signed, broadcasting }

/// Where an owned address came from. Names match Phase 5
/// `OwnedAddressKind`.
enum LedgerPmAddressKind { ledgerBitcoinReceive, polymarketDepositWallet }

class LedgerPmAddressRef {
  const LedgerPmAddressRef({
    required this.address,
    required this.kind,
    this.index,
    this.deviceVerifiedAt,
  });

  final String address;
  final LedgerPmAddressKind kind;
  final int? index;
  final DateTime? deviceVerifiedAt;
}

// ──────────────────────────── ports ──────────────────────────────────

/// A Ledger BTC receive address the user confirmed on the device.
class LedgerBtcVerifiedAddress {
  const LedgerBtcVerifiedAddress({
    required this.address,
    required this.index,
    required this.verifiedAt,
  });

  final String address;
  final int index;
  final DateTime verifiedAt;
}

/// A Ledger-signed BTC transaction not yet broadcast. Opaque to this
/// service apart from the output it pays.
class LedgerBtcSignedFunding {
  const LedgerBtcSignedFunding({
    required this.handle,
    required this.toAddress,
    required this.amountSats,
    this.inputs = const [],
    this.txid,
    this.vout,
  });

  /// Whatever the BTC send service needs to broadcast (signed PSBT).
  final Object handle;
  final String toAddress;
  final BigInt amountSats;

  /// Outpoints `txid:vout` spent.
  final List<String> inputs;

  /// Txid computed locally from the signed transaction, and the deposit
  /// output index, so both are persisted before the broadcast.
  final String? txid;
  final int? vout;
}

/// The Ledger Bitcoin leg. Wallet ID is always explicit; never follows
/// the active or BDK-scoped wallet.
abstract class LedgerPmBtcLeg {
  Future<LedgerBtcVerifiedAddress> verifyReceiveAddressOnDevice(
      String walletId);

  /// Builds the PSBT paying exactly [amountSats] to [toAddress] and signs
  /// it on the Ledger (the device shows outputs, amounts and fee).
  /// [mustSpendOutpoints] is the F4 rule: one group of `txid:vout` per
  /// earlier funding whose outcome is unknown; the PSBT spends at least one
  /// outpoint of every group or nothing is built.
  Future<LedgerBtcSignedFunding> buildAndSign({
    required String walletId,
    required String toAddress,
    required BigInt amountSats,
    List<List<String>> mustSpendOutpoints = const [],
  });

  Future<({String txid, int vout})> broadcast(
      String walletId, LedgerBtcSignedFunding signed);
}

/// Adapter over the hypercore group's `LedgerBtcSendService` (P4.10).
///
/// Wiring supplies the three resolvers: [walletFor] from settings by
/// wallet ID, [receiveInfoFor] from `walletReceiveInfoProvider(walletId)`
/// (address and index), [feeRateSatVb] from the fee estimator.
class LedgerBtcSendServiceLeg implements LedgerPmBtcLeg {
  LedgerBtcSendServiceLeg(
    this._service, {
    required WalletConfig Function(String walletId) walletFor,
    required Future<({String address, int index})> Function(String walletId)
        receiveInfoFor,
    required Future<double> Function() feeRateSatVb,
  })  : _walletFor = walletFor,
        _receiveInfoFor = receiveInfoFor,
        _feeRateSatVb = feeRateSatVb;

  final LedgerBtcSendService _service;
  final WalletConfig Function(String walletId) _walletFor;
  final Future<({String address, int index})> Function(String walletId)
      _receiveInfoFor;
  final Future<double> Function() _feeRateSatVb;

  WalletConfig _ledgerWallet(String walletId) {
    final wallet = _walletFor(walletId);
    if (wallet.id != walletId || !wallet.isLedger) {
      throw const LedgerBtcSendException(LedgerBtcSendError.notLedger);
    }
    return wallet;
  }

  @override
  Future<LedgerBtcVerifiedAddress> verifyReceiveAddressOnDevice(
      String walletId) async {
    final wallet = _ledgerWallet(walletId);
    final info = await _receiveInfoFor(walletId);
    final verified = await _service.verifyReceiveAddress(
      wallet: wallet,
      address: info.address,
      index: info.index,
    );
    if (verified.walletId != walletId) {
      throw const LedgerBtcSendException(LedgerBtcSendError.walletChanged);
    }
    return LedgerBtcVerifiedAddress(
      address: verified.address,
      index: verified.index,
      verifiedAt: verified.verifiedAt,
    );
  }

  @override
  Future<LedgerBtcSignedFunding> buildAndSign({
    required String walletId,
    required String toAddress,
    required BigInt amountSats,
    List<List<String>> mustSpendOutpoints = const [],
  }) async {
    if (!amountSats.isValidInt || amountSats <= BigInt.zero) {
      throw const LedgerBtcSendException(LedgerBtcSendError.invalidAmount);
    }
    final wallet = _ledgerWallet(walletId);
    final prepared = await _service.prepare(
      wallet: wallet,
      destination: toAddress,
      amountSats: amountSats.toInt(),
      feeRateSatVb: await _feeRateSatVb(),
      mustSpendOutpoints: mustSpendOutpoints,
    );
    if (prepared.walletId != walletId ||
        prepared.destination.trim() != toAddress.trim() ||
        prepared.amountSats != amountSats.toInt()) {
      throw const LedgerBtcSendException(LedgerBtcSendError.walletChanged);
    }
    final signed = await _service.sign(prepared);
    return LedgerBtcSignedFunding(
      handle: signed,
      toAddress: prepared.destination,
      amountSats: BigInt.from(prepared.amountSats),
      inputs: [for (final o in prepared.inputs) '${o.txid}:${o.vout}'],
      txid: signed.txid,
      vout: prepared.depositVout,
    );
  }

  @override
  Future<({String txid, int vout})> broadcast(
      String walletId, LedgerBtcSignedFunding signed) async {
    final handle = signed.handle;
    if (handle is! LedgerBtcSignedSend || handle.prepared.walletId != walletId) {
      throw const LedgerBtcSendException(LedgerBtcSendError.walletChanged);
    }
    final txid = await _service.broadcast(handle);
    return (txid: txid, vout: handle.prepared.depositVout);
  }
}

/// Phase 3 batches used by the funding route.
abstract class LedgerPmCollateralExecutor {
  Future<String> wrap(LedgerActionIntent intent);
  Future<String> unwrap(LedgerActionIntent intent);

  /// O3 transfer. [ensureStillPayable] throws when the bound quote is no
  /// longer payable (expired within its margin). It must run before the
  /// Ledger prompt and again after the approval, immediately before the
  /// relayer submit, so an approval that outlived the quote moves nothing.
  Future<String> withdraw(
    LedgerActionIntent intent, {
    required void Function() ensureStillPayable,
    Future<void> Function(String relayerTxId)? onRelayerSubmitted,
  });
}

/// Adapter over the Phase 3 [LedgerPolymarketExecutor].
///
/// [withdraw] checks the quote twice: before the device prompt, and as the
/// executor's `beforeSubmit` guard, which runs after the Ledger approval
/// and immediately before the relayer POST. A quote that expired while the
/// user was approving throws `WalletGuardException(quoteExpired)` there,
/// before any submission record or POST, so no funds move.
class LedgerPolymarketExecutorCollateral implements LedgerPmCollateralExecutor {
  LedgerPolymarketExecutorCollateral(this._executor);

  final LedgerPolymarketExecutor _executor;

  @override
  Future<String> wrap(LedgerActionIntent intent) => _executor.wrap(intent);

  @override
  Future<String> unwrap(LedgerActionIntent intent) => _executor.unwrap(intent);

  @override
  Future<String> withdraw(
    LedgerActionIntent intent, {
    required void Function() ensureStillPayable,
    Future<void> Function(String relayerTxId)? onRelayerSubmitted,
  }) {
    ensureStillPayable();
    return _executor.withdraw(
      intent,
      beforeSubmit: ensureStillPayable,
      onRelayerSubmitted: onRelayerSubmitted,
    );
  }
}

/// Builds the Phase 3 executor for a resolved deposit wallet. The caller
/// constructs it with the Ledger EVM signer for this wallet and must pass
/// [belongsToLedger] through to the executor's allowlist.
typedef LedgerPmCollateralExecutorFactory = LedgerPmCollateralExecutor
    Function(
  PolymarketLedgerAccount account,
  bool Function(String address) belongsToLedger,
);

/// Presents the exact unwrap intent before executing it with a Ledger signer.
typedef LedgerPmUnwrapApproval = Future<String> Function(
  LedgerActionIntent intent, {
  required PolymarketLedgerAccount account,
});

/// Presents the exact transfer intent. The executor must run
/// [ensureStillPayable] after signing, before its POST, and persist the
/// returned relayer ID through [onRelayerSubmitted] before polling.
typedef LedgerPmWithdrawalApproval = Future<String> Function(
  LedgerActionIntent intent, {
  required PolymarketLedgerAccount account,
  required bool Function(String address) belongsToLedger,
  required void Function() ensureStillPayable,
  required Future<void> Function(String relayerTxId) onRelayerSubmitted,
});

abstract class LedgerPmDepositWalletDeployer {
  /// Relayer WALLET-CREATE. No signature; returns the wallet address.
  Future<String> deploy(String eoa);
}

class OnboardingLedgerPmDepositWalletDeployer
    implements LedgerPmDepositWalletDeployer {
  OnboardingLedgerPmDepositWalletDeployer([PolymarketOnboardingService? s])
      : _onboarding = s ?? PolymarketOnboardingService();

  final PolymarketOnboardingService _onboarding;

  @override
  Future<String> deploy(String eoa) =>
      _onboarding.deployDepositWallet(eoaAddress: eoa);
}

abstract class LedgerPmQuoteSource {
  /// A verified quote and the server clock skew from its response's `Date`
  /// header (null when the header was missing).
  Future<({VerifiedOrchestraQuote quote, Duration? skew})> fetch(
    OrchestraQuoteRequest request, {
    required double usdPerBtc,
    required String flow,
  });

  Future<({String? error})> submitBtcDeposit({
    required String quoteId,
    required String txid,
    required int vout,
    required String idempotencyKey,
  });

  Future<({String? error})> submitEvmDeposit({
    required String quoteId,
    required String txHash,
    required String sourceAddress,
    required String idempotencyKey,
  });
}

/// Production quotes through the Phase 2 gate only.
class GatedLedgerPmQuoteSource implements LedgerPmQuoteSource {
  const GatedLedgerPmQuoteSource();

  /// Same gate call as the HyperCore Ledger route: the skew from the
  /// response, and transport retries on one idempotency key.
  @override
  Future<({VerifiedOrchestraQuote quote, Duration? skew})> fetch(
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

  @override
  Future<({String? error})> submitBtcDeposit({
    required String quoteId,
    required String txid,
    required int vout,
    required String idempotencyKey,
  }) async {
    final result = await OrchestraService.submitDeposit(
      quoteId: quoteId,
      bitcoinTxid: txid,
      bitcoinVout: vout,
      idempotencyKey: idempotencyKey,
    );
    return (error: result.isSuccess ? null : (result.error ?? 'submit_failed'));
  }

  @override
  Future<({String? error})> submitEvmDeposit({
    required String quoteId,
    required String txHash,
    required String sourceAddress,
    required String idempotencyKey,
  }) async {
    final result = await OrchestraService.submitDeposit(
      quoteId: quoteId,
      txHash: txHash,
      sourceAddress: sourceAddress,
      idempotencyKey: idempotencyKey,
    );
    return (error: result.isSuccess ? null : (result.error ?? 'submit_failed'));
  }
}

// ──────────────────────────── exceptions ─────────────────────────────

enum LedgerPmFundingRefusal {
  /// `kLedgerInvestingEnabled` is off.
  releaseFlagOff,

  /// No device-verified EVM identity for this Ledger.
  notPaired,

  /// Live catalog lacks the pair.
  routeUnavailable,

  /// Legacy Safe (O4) or an account read that did not settle.
  accountUnsupported,

  /// No deposit wallet yet and the user did not confirm creating one.
  deployNotConfirmed,

  /// The relayer has not reported the new wallet yet. Retry later.
  depositWalletPending,

  /// A deployed or quoted address does not belong to this Ledger.
  addressNotOwned,

  /// Not enough unwrapped collateral; positions never count.
  collateralNotAvailable,

  /// pUSD must be unwrapped before the transfer.
  unwrapRequired,

  /// Nothing to convert or withdraw.
  nothingToMove,

  /// A balance read failed. Never treated as zero.
  balanceUnknown,

  /// O3: withdrawals to the Ledger are off.
  withdrawDisabled,
}

class LedgerPmFundingRefused implements Exception {
  const LedgerPmFundingRefused(this.reason);
  final LedgerPmFundingRefusal reason;

  @override
  String toString() => 'LedgerPmFundingRefused(${reason.name})';
}

/// The quote expired between review and broadcast. Nothing was broadcast;
/// the signed transaction was discarded. Re-quote, re-review, re-sign.
class LedgerFundingQuoteExpiredException implements Exception {
  const LedgerFundingQuoteExpiredException(this.operationId,
      {this.duringApproval = false});
  final String? operationId;

  /// True when less than the B5 minimum was left after the Ledger approved:
  /// the signature was discarded before any broadcast or relayer POST and
  /// the re-review shows `settlementLedgerExpiredDuringApproval`.
  final bool duringApproval;

  @override
  String toString() => 'LedgerFundingQuoteExpiredException';
}

/// The BTC broadcast failed or could not be checked after the operation
/// was persisted. Funds may have moved: never "Nothing was sent".
class LedgerPmFundingOutcomeUnknown implements Exception {
  const LedgerPmFundingOutcomeUnknown(this.operationId, this.cause);
  final String operationId;
  final Object cause;

  @override
  String toString() => 'LedgerPmFundingOutcomeUnknown';
}

// ────────────────────────────── models ───────────────────────────────

enum LedgerPmFundingDirection { toPredictions, toLedgerBitcoin }

/// A checked "Make funds available" batch waiting for the Ledger approval.
class LedgerPmMakeAvailablePlan {
  const LedgerPmMakeAvailablePlan({
    required this.walletId,
    required this.account,
    required this.depositWallet,
    required this.amount,
    required this.intent,
    required this.belongsToLedger,
  });

  final String walletId;
  final PolymarketLedgerAccount account;
  final String depositWallet;

  /// USDC.e base units (6 decimals).
  final BigInt amount;
  final LedgerActionIntent intent;
  final bool Function(String address) belongsToLedger;
}

/// What the explainer sheet shows before anything starts.
class LedgerPmForwardPlan {
  const LedgerPmForwardPlan({
    required this.walletId,
    required this.eoa,
    required this.account,
    required this.depositWallet,
    required this.requiresDeploy,
  });

  final String walletId;
  final String eoa;
  final PolymarketLedgerAccount account;

  /// The deposit wallet funds will arrive in (existing or to be created).
  final String depositWallet;
  final bool requiresDeploy;
  int get deviceApprovals => kLedgerPmForwardDeviceApprovals;
}

class LedgerPmForwardQuote {
  const LedgerPmForwardQuote({
    required this.walletId,
    required this.quote,
    required this.recipient,
    required this.refund,
    required this.usdPerBtc,
    this.skew,
    this.supersedes,
  });

  final String walletId;
  final VerifiedOrchestraQuote quote;
  final LedgerPmAddressRef recipient;
  final LedgerPmAddressRef refund;
  final double usdPerBtc;

  /// Server minus local clock from the quote response; null when unknown.
  final Duration? skew;

  /// The quote this one replaced before anything was sent, if any. Kept in
  /// the operation's `quoteHistory`.
  final SettlementQuoteHistoryEntry? supersedes;

  BigInt get amountSats => quote.amountIn;
}

class LedgerPmForwardResult {
  const LedgerPmForwardResult({
    required this.operationId,
    required this.txid,
    required this.vout,
    required this.submitAccepted,
  });

  final String operationId;
  final String txid;
  final int vout;

  /// False when `submitDeposit` failed after the broadcast. Funds moved;
  /// Phase 5 reconciliation resubmits. Copy stays "Bitcoin sent. Waiting
  /// for confirmations." either way (plan B13).
  final bool submitAccepted;
}

/// Collateral for the reverse route. Null balances mean the read failed.
class LedgerPmWithdrawable {
  const LedgerPmWithdrawable({
    required this.withdrawEnabled,
    required this.usdce,
    required this.pusd,
    required this.openPositions,
  });

  final bool withdrawEnabled;

  /// Unwrapped collateral (6 decimals), ready for the transfer.
  final BigInt? usdce;

  /// Wrapped collateral (6 decimals); needs an unwrap batch first.
  final BigInt? pusd;

  /// Count of open positions. Never withdrawable; null when unread.
  final int? openPositions;

  bool get balancesKnown => usdce != null && pusd != null;

  /// Collateral the user can withdraw after unwrapping. Positions are
  /// excluded by construction.
  BigInt? get availableCollateral =>
      balancesKnown ? usdce! + pusd! : null;

  bool get needsUnwrap => (pusd ?? BigInt.zero) > BigInt.zero;
}

class LedgerPmReverseQuote {
  const LedgerPmReverseQuote({
    required this.walletId,
    required this.quote,
    required this.recipient,
    required this.refund,
    required this.binding,
    this.skew,
  });

  final String walletId;
  final VerifiedOrchestraQuote quote;

  /// Server minus local clock from the quote response; null when unknown.
  final Duration? skew;

  /// Ledger BTC address confirmed on the device. Never Spark.
  final LedgerPmAddressRef recipient;

  /// This Ledger's deposit wallet on Polygon.
  final LedgerPmAddressRef refund;
  final LedgerWithdrawalBinding binding;

  BigInt get amountUsdce => quote.amountIn;
}

class LedgerPmReverseResult {
  const LedgerPmReverseResult({
    required this.operationId,
    required this.relayerTxHash,
    required this.submitAccepted,
  });

  final String operationId;
  final String relayerTxHash;
  final bool submitAccepted;
}

// ───────────────────────────── service ───────────────────────────────

class LedgerPolymarketFundingService {
  LedgerPolymarketFundingService({
    required this.identity,
    required PolymarketAccountReads reads,
    required LedgerPmBtcLeg btcLeg,
    required LedgerPmCollateralExecutorFactory collateralFor,
    required LedgerSettlementRecords records,
    required FundingRouteAvailability routes,
    LedgerPmDepositWalletDeployer? deployer,
    LedgerPmQuoteSource quotes = const GatedLedgerPmQuoteSource(),
    RoutePausePolicy pausePolicy = const RoutePausePolicy(),
    this.investingEnabled = kLedgerInvestingEnabled,
    this.withdrawEnabled = kLedgerPolymarketWithdrawEnabled,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.deployPollAttempts = 5,
    this.deployPollInterval = const Duration(seconds: 3),
  })  : _reads = reads,
        _btcLeg = btcLeg,
        _collateralFor = collateralFor,
        _records = records,
        _routes = routes,
        _deployer = deployer ?? OnboardingLedgerPmDepositWalletDeployer(),
        _quotes = quotes,
        _pause = pausePolicy,
        _clock = clock ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  /// The selected Ledger. Null identity is refused at every entry.
  final LedgerIdentity? identity;
  final bool investingEnabled;
  final bool withdrawEnabled;
  final int deployPollAttempts;
  final Duration deployPollInterval;

  final PolymarketAccountReads _reads;
  final LedgerPmBtcLeg _btcLeg;
  final LedgerPmCollateralExecutorFactory _collateralFor;
  final LedgerSettlementRecords _records;
  final FundingRouteAvailability _routes;
  final LedgerPmDepositWalletDeployer _deployer;
  final LedgerPmQuoteSource _quotes;

  /// Remote pause switch for NEW Ledger funding (F16). Pending operations
  /// never consult it.
  final RoutePausePolicy _pause;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  /// Last BTC address the device confirmed in this service's lifetime.
  LedgerBtcVerifiedAddress? _verifiedBtc;
  bool _busy = false;

  bool get isBusy => _busy;

  // ── common checks ──

  Never _refuse(LedgerPmFundingRefusal reason) =>
      throw LedgerPmFundingRefused(reason);

  ({String walletId, String eoa}) _pairedLedger() {
    if (!investingEnabled) _refuse(LedgerPmFundingRefusal.releaseFlagOff);
    final id = identity;
    final eoa = id?.evmAddress;
    if (id == null || !id.hasVerifiedEvm || eoa == null || !isEvmAddress(eoa)) {
      _refuse(LedgerPmFundingRefusal.notPaired);
    }
    return (walletId: id.walletId, eoa: eoa);
  }

  bool get _withdrawAllowed =>
      withdrawEnabled &&
      isLedgerActionAllowed(LedgerActionKind.pmWithdrawal,
          polymarketWithdrawEnabled: withdrawEnabled);

  void _requireWithdrawAllowed() {
    if (!_withdrawAllowed) _refuse(LedgerPmFundingRefusal.withdrawDisabled);
  }

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    if (_busy) throw const LedgerFailure(LedgerFailureCode.busy);
    _busy = true;
    try {
      return await _scoped(body);
    } finally {
      _busy = false;
    }
  }

  /// Runs a flow step as a Ledger operation for this wallet (B12): hot
  /// signing entry points refuse inside it, and the backend session is
  /// prepared before it starts.
  Future<T> _scoped<T>(Future<T> Function() body) =>
      runLedgerFundingScope(identity?.walletId ?? '', body);

  /// Resolves the account from the verified EOA (never from UI state) and
  /// checks the deposit wallet is the one this EOA derives or predicts.
  Future<PolymarketLedgerAccount> _resolve(String eoa) async {
    final account = await PolymarketAccountResolver(_reads).resolve(eoa);
    switch (account.kind) {
      case PolymarketAccountKind.legacySafe:
      case PolymarketAccountKind.uncertain:
        _refuse(LedgerPmFundingRefusal.accountUnsupported);
      case PolymarketAccountKind.depositWallet:
      case PolymarketAccountKind.none:
        return account;
    }
  }

  Future<String> _depositWalletFor(String eoa) async {
    final account = await _resolve(eoa);
    final address = account.address;
    if (!account.canAct || address == null) {
      _refuse(LedgerPmFundingRefusal.accountUnsupported);
    }
    await _requireOwnedDepositWallet(eoa, address);
    return address;
  }

  Future<void> _requireOwnedDepositWallet(String eoa, String wallet) async {
    if (sameEvmAddress(wallet, _reads.deriveDepositWalletAddress(eoa))) return;
    String? predicted;
    try {
      predicted = await _reads.predictDepositWallet(eoa);
    } catch (_) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
    if (!sameEvmAddress(wallet, predicted)) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
  }

  bool Function(String address) _belongsToLedger({
    required String eoa,
    required String depositWallet,
    String? btcAddress,
  }) =>
      (address) =>
          sameEvmAddress(address, depositWallet) ||
          sameEvmAddress(address, eoa) ||
          (btcAddress != null && address.trim() == btcAddress.trim());

  Future<BigInt> _balance(String token, String owner) async {
    try {
      return await _reads.erc20Balance(token: token, owner: owner);
    } catch (_) {
      _refuse(LedgerPmFundingRefusal.balanceUnknown);
    }
  }

  /// Confirms a Ledger BTC receive address on the device. Always a
  /// mainnet bitcoin address; a Spark address is refused.
  Future<LedgerBtcVerifiedAddress> _verifiedBtcAddress(String walletId) async {
    final verified = await _btcLeg.verifyReceiveAddressOnDevice(walletId);
    if (formatMatchesChain(_btcChain, verified.address, mainnet: true) !=
            AddressFormatMatch.ok ||
        isSparkAddress(verified.address, mainnet: true)) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
    return _verifiedBtc = verified;
  }

  /// The Ledger rows of the Phase 5 ownership table for one operation.
  /// [btc] must carry the device verification of the Bitcoin address.
  SettlementOwnership _ledgerOwnership({
    required String walletId,
    required String eoa,
    required RouteKey route,
    required SettlementAccountKind source,
    required SettlementAccountKind destination,
    required LedgerPmAddressRef btc,
    required String depositWallet,
  }) {
    final index = btc.index;
    final verifiedAt = btc.deviceVerifiedAt;
    if (index == null || verifiedAt == null) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
    try {
      return resolveLedgerSettlementOwnership(
        walletId: walletId,
        route: route,
        source: source,
        destination: destination,
        verifiedEvmAddress: eoa,
        depositWallet: depositWallet,
        verifiedBtc: (
          walletId: walletId,
          address: btc.address,
          index: index,
          verifiedAt: verifiedAt,
        ),
      );
    } on WalletGuardException {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
  }

  /// The Phase 5 margin at [moment] for the quote the operation holds,
  /// with the skew its response carried (a null skew adds 10 s).
  bool _hasMargin(VerifiedOrchestraQuote quote, Duration? skew,
          SettlementMoment moment, SettlementPayer payer) =>
      SettlementQuotePolicy.hasMargin(
        expiresAt: quote.expiresAt,
        localNow: _clock(),
        skew: skew,
        moment: moment,
        payer: payer,
      );

  /// A verified quote with the B5 review margin (60 s) left. The user has
  /// not seen these terms yet, so a short quote is replaced silently, at
  /// most twice.
  Future<({VerifiedOrchestraQuote quote, Duration? skew})> _quoteForReview(
    OrchestraQuoteRequest request, {
    required double usdPerBtc,
    required String flow,
    required SettlementPayer payer,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final fetched =
          await _quotes.fetch(request, usdPerBtc: usdPerBtc, flow: flow);
      if (_hasMargin(fetched.quote, fetched.skew,
          SettlementMoment.beforeReview, payer)) {
        return fetched;
      }
    }
    throw const WalletGuardException(WalletGuardReason.quoteExpired);
  }

  static String _usdceBucket(BigInt amount) =>
      TrackingService.usdBucket(amount.toDouble() / 1e6);

  static String _satsBucket(BigInt sats, double usdPerBtc) =>
      TrackingService.usdBucket(sats.toDouble() / 1e8 * usdPerBtc);

  // ───────────────────────────── forward ─────────────────────────────

  /// Everything the explainer sheet needs. Reads only; no prompt, no
  /// deployment, no quote.
  Future<LedgerPmForwardPlan> planForward() => _scoped(() async {
    final ledger = _pairedLedger();
    if (!(await _routes.availability(_forwardRoute)).isAvailable) {
      _refuse(LedgerPmFundingRefusal.routeUnavailable);
    }
    final account = await _resolve(ledger.eoa);
    final wallet = account.address ??
        account.predictedDepositWallet ??
        _reads.deriveDepositWalletAddress(ledger.eoa);
    await _requireOwnedDepositWallet(ledger.eoa, wallet);
    return LedgerPmForwardPlan(
      walletId: ledger.walletId,
      eoa: ledger.eoa,
      account: account,
      depositWallet: wallet,
      requiresDeploy: account.kind == PolymarketAccountKind.none,
    );
  });

  /// Creates the deposit wallet if needed ([deployConfirmed] must come
  /// from the explainer sheet's explicit confirmation), confirms the
  /// refund address on the Ledger and fetches a verified quote.
  Future<LedgerPmForwardQuote> quoteForward({
    required LedgerPmForwardPlan plan,
    required BigInt amountSats,
    required double usdPerBtc,
    required bool deployConfirmed,
  }) =>
      _exclusive(() async {
        final ledger = _pairedLedger();
        if (ledger.walletId != plan.walletId ||
            !sameEvmAddress(ledger.eoa, plan.eoa)) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }
        if (amountSats <= BigInt.zero) {
          _refuse(LedgerPmFundingRefusal.nothingToMove);
        }
        // F16: a remote pause blocks new Ledger funding.
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        // F11 before any deployment, device prompt or quote.
        TrackingService.ledgerFundingStarted(route: kLedgerBtcToPolygonUsdceRoute);

        var account = await _resolve(ledger.eoa);
        if (account.kind == PolymarketAccountKind.none) {
          if (!deployConfirmed) {
            _refuse(LedgerPmFundingRefusal.deployNotConfirmed);
          }
          account = await _deployAndConfirm(ledger.eoa);
        }
        final wallet = await _depositWalletFor(ledger.eoa);

        final refund = await _verifiedBtcAddress(ledger.walletId);
        final request = OrchestraQuoteRequest(
          sourceChain: _btcChain,
          sourceAsset: _btcAsset,
          destinationChain: _polygonChain,
          destinationAsset: _usdceAsset,
          amountBaseUnits: amountSats,
          recipientAddress: wallet,
          refundAddress: refund.address,
          recipientKind: RecipientKind.ownPmWallet,
          ownAddress: wallet,
        );
        final fetched = await _quoteForReview(request,
            usdPerBtc: usdPerBtc,
            flow: kLedgerBtcToPolygonUsdceRoute,
            payer: SettlementPayer.ledgerBitcoin);
        final quote = fetched.quote;
        _checkQuoteAddresses(quote,
            recipient: wallet, refund: refund.address);

        return LedgerPmForwardQuote(
          walletId: ledger.walletId,
          quote: quote,
          skew: fetched.skew,
          recipient: LedgerPmAddressRef(
            address: wallet,
            kind: LedgerPmAddressKind.polymarketDepositWallet,
          ),
          refund: LedgerPmAddressRef(
            address: refund.address,
            kind: LedgerPmAddressKind.ledgerBitcoinReceive,
            index: refund.index,
            deviceVerifiedAt: refund.verifiedAt,
          ),
          usdPerBtc: usdPerBtc,
        );
      });

  Future<PolymarketLedgerAccount> _deployAndConfirm(String eoa) async {
    final deployed = await _deployer.deploy(eoa);
    await _requireOwnedDepositWallet(eoa, deployed);
    TrackingService.ledgerPmDepositWalletCreated();
    for (var attempt = 0; attempt < deployPollAttempts; attempt++) {
      final account = await _resolve(eoa);
      final address = account.address;
      if (account.kind == PolymarketAccountKind.depositWallet &&
          address != null &&
          sameEvmAddress(address, deployed)) {
        return account;
      }
      await _delay(deployPollInterval);
    }
    _refuse(LedgerPmFundingRefusal.depositWalletPending);
  }

  void _checkQuoteAddresses(
    VerifiedOrchestraQuote quote, {
    required String recipient,
    required String refund,
  }) {
    final request = quote.request;
    final destinationOk = request.destinationChain == _polygonChain
        ? sameEvmAddress(request.recipientAddress, recipient)
        : request.recipientAddress.trim() == recipient.trim();
    final refundOk = request.sourceChain == _polygonChain
        ? sameEvmAddress(request.refundAddress, refund)
        : request.refundAddress.trim() == refund.trim();
    if (!destinationOk || !refundOk) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
  }

  /// Re-quotes an expired or stale forward quote with the same verified
  /// addresses. The caller shows it for a new review; nothing is signed.
  /// [duringApproval] records why the previous quote was replaced.
  Future<LedgerPmForwardQuote> refreshForwardQuote(
    LedgerPmForwardQuote previous, {
    bool duringApproval = false,
  }) =>
      _scoped(() async {
    final ledger = _pairedLedger();
    if (ledger.walletId != previous.walletId) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
    final wallet = await _depositWalletFor(ledger.eoa);
    if (!sameEvmAddress(wallet, previous.recipient.address)) {
      _refuse(LedgerPmFundingRefusal.addressNotOwned);
    }
    final fetched = await _quoteForReview(previous.quote.request,
        usdPerBtc: previous.usdPerBtc,
        flow: kLedgerBtcToPolygonUsdceRoute,
        payer: SettlementPayer.ledgerBitcoin);
    final quote = fetched.quote;
    _checkQuoteAddresses(quote,
        recipient: wallet, refund: previous.refund.address);
    TrackingService.ledgerFundingQuoteRefreshed(
        route: kLedgerBtcToPolygonUsdceRoute);
    return LedgerPmForwardQuote(
      walletId: previous.walletId,
      quote: quote,
      recipient: previous.recipient,
      refund: previous.refund,
      usdPerBtc: previous.usdPerBtc,
      skew: fetched.skew,
      supersedes: SettlementQuoteHistoryEntry(
        quoteId: previous.quote.quoteId,
        reason: duringApproval
            ? 'expired_during_approval'
            : 'expired_before_prompt',
        supersededAt: _clock(),
      ),
    );
  });

  /// Signs the BTC leg on the Ledger, persists the operation, refuses an
  /// expired quote, broadcasts, then submits txid and vout.
  ///
  /// [onStage] reports `signed` and `broadcasting` so a sheet can say
  /// which step is running. A broadcast failure throws
  /// [LedgerPmFundingOutcomeUnknown]; every earlier throw means nothing
  /// was broadcast. Once the broadcast returned, the call always returns
  /// a result (a failed submit or stage write is left to reconciliation).
  Future<LedgerPmForwardResult> executeForward(
    LedgerPmForwardQuote q, {
    void Function(LedgerPmFundingStage stage)? onStage,
  }) =>
      _exclusive(() async {
        final ledger = _pairedLedger();
        if (ledger.walletId != q.walletId) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }
        // F16: the operation is created below, so a pause still applies.
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        final quote = q.quote;
        final wallet = await _depositWalletFor(ledger.eoa);
        _checkQuoteAddresses(quote,
            recipient: wallet, refund: q.refund.address);
        if (!sameEvmAddress(wallet, q.recipient.address)) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }
        final verifiedBtc = _verifiedBtc;
        if (verifiedBtc == null ||
            verifiedBtc.address.trim() != q.refund.address.trim()) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }

        void payable() => OrchestraQuoteGate.ensurePayable(quote,
            amountBaseUnits: q.amountSats, now: _clock());

        try {
          payable();
        } on WalletGuardException catch (e) {
          if (e.reason == WalletGuardReason.quoteExpired) {
            throw const LedgerFundingQuoteExpiredException(null);
          }
          rethrow;
        }

        final ownership = _ledgerOwnership(
          walletId: ledger.walletId,
          eoa: ledger.eoa,
          route: _forwardRoute,
          source: SettlementAccountKind.ledgerBtc,
          destination: SettlementAccountKind.pmLedger,
          btc: q.refund,
          depositWallet: wallet,
        );
        // Write-ahead before any device prompt: a failed write stops here.
        final operationId = (await _records.start(
          walletId: ledger.walletId,
          accountKind: SettlementAccountKind.ledgerBtc,
          flow: SettlementFlow.ledgerBtcToPredictions,
          routeVersion: kLedgerBtcToPolygonUsdceRoute,
          route: _forwardRoute,
          quote: quote,
          recipient: ownership.recipient,
          refund: ownership.refund,
          skew: q.skew,
          quoteHistory: [if (q.supersedes != null) q.supersedes!],
        ))
            .operationId;
        await _records.hold(operationId);
        try {
          try {
            await _records.advance(operationId, SettlementStage.reviewed);
            if (!_hasMargin(quote, q.skew, SettlementMoment.beforeDevicePrompt,
                SettlementPayer.ledgerBitcoin)) {
              throw LedgerFundingQuoteExpiredException(operationId);
            }
            await _records.advance(operationId, SettlementStage.authorizing);
          } catch (_) {
            await _records.abandon(operationId);
            rethrow;
          }

          final LedgerBtcSignedFunding signed;
          try {
            signed = await _btcLeg.buildAndSign(
              walletId: ledger.walletId,
              toAddress: quote.depositAddress,
              amountSats: q.amountSats,
              // F4: conflict with every earlier funding whose outcome is
              // unknown.
              mustSpendOutpoints: await _records.mustSpendOutpointsFor(
                  ledger.walletId, _forwardRoute),
            );
          } catch (error) {
            // Rejected, disconnected or not built: nothing was signed.
            await _records.abandon(operationId);
            TrackingService.ledgerFundingResult(
                route: kLedgerBtcToPolygonUsdceRoute,
                outcome: _errorCode(error));
            rethrow;
          }
          final signedTxid = signed.txid;
          final signedVout = signed.vout;
          if (signed.toAddress != quote.depositAddress ||
              signed.amountSats != q.amountSats ||
              signedTxid == null ||
              signedVout == null) {
            await _records.abandon(operationId);
            _refuse(LedgerPmFundingRefusal.addressNotOwned);
          }
          try {
            await _records.recordSigned(operationId,
                txid: signedTxid, vout: signedVout, inputs: signed.inputs);
          } catch (_) {
            // No txid on disk, no broadcast. The signature is discarded.
            await _records.abandon(operationId);
            rethrow;
          }
          onStage?.call(LedgerPmFundingStage.signed);

          // Device prompts can outlive a quote. Never broadcast late.
          var late = !_hasMargin(quote, q.skew,
              SettlementMoment.afterDeviceSigned, SettlementPayer.ledgerBitcoin);
          try {
            payable();
          } on WalletGuardException {
            late = true;
          }
          if (late) {
            await _records.abandon(operationId);
            TrackingService.ledgerFundingResult(
                route: kLedgerBtcToPolygonUsdceRoute, outcome: 'quote_expired');
            throw LedgerFundingQuoteExpiredException(operationId,
                duringApproval: true);
          }

          try {
            await _records.advance(operationId, SettlementStage.broadcasting);
          } catch (_) {
            await _records.abandon(operationId);
            rethrow;
          }
          onStage?.call(LedgerPmFundingStage.broadcasting);
          final ({String txid, int vout}) sent;
          try {
            sent = await _btcLeg.broadcast(ledger.walletId, signed);
            if (sent.txid.trim().toLowerCase() !=
                    signedTxid.trim().toLowerCase() ||
                sent.vout != signedVout) {
              throw StateError('broadcast_txid_mismatch');
            }
          } catch (error) {
            await _records.advanceBestEffort(
                operationId, SettlementStage.fundingUnknown);
            TrackingService.ledgerFundingResult(
                route: kLedgerBtcToPolygonUsdceRoute,
                outcome: 'funding_unknown');
            throw LedgerPmFundingOutcomeUnknown(operationId, error);
          }
          // The bitcoin left the Ledger. From here nothing may surface as
          // "Nothing was sent"; the stage write and the submit are best
          // effort and the Phase 5 reconciler picks up a missing submit.
          await _records.recordFunded(
            operationId,
            SettlementFunding(
              kind: SettlementFundingKind.bitcoin,
              btcTxid: sent.txid,
              btcVout: sent.vout,
              btcInputs: signed.inputs,
            ),
          );
          TrackingService.ledgerFundingBroadcast(
            route: kLedgerBtcToPolygonUsdceRoute,
            amountBucket: _satsBucket(q.amountSats, q.usdPerBtc),
          );

          final submit = await _records.submit(operationId);
          final accepted = submit.accepted;
          TrackingService.ledgerFundingResult(
              route: kLedgerBtcToPolygonUsdceRoute,
              outcome: accepted ? 'submitted' : 'submit_pending');
          return LedgerPmForwardResult(
            operationId: operationId,
            txid: sent.txid,
            vout: sent.vout,
            submitAccepted: accepted,
          );
        } finally {
          await _records.release(operationId);
        }
      });

  /// Unwrapped USDC.e waiting in the deposit wallet after arrival.
  Future<BigInt> readConvertible() async {
    final ledger = _pairedLedger();
    final wallet = await _depositWalletFor(ledger.eoa);
    return _balance(PolymarketConstants.usdcEAddress, wallet);
  }

  /// Reads, checks and builds the "Make funds available" batch (exact
  /// approve plus wrap of arrived USDC.e into pUSD) for the Ledger approval
  /// flow. No prompt. [amount] defaults to the whole USDC.e balance and
  /// never exceeds it. [summary] is what the approval sheet shows.
  Future<LedgerPmMakeAvailablePlan> prepareMakeFundsAvailable({
    BigInt? amount,
    Map<String, String>? summary,
  }) =>
      _scoped(() async {
    final ledger = _pairedLedger();
    final account = await _resolve(ledger.eoa);
    final wallet = account.address;
    if (!account.canAct || wallet == null) {
      _refuse(LedgerPmFundingRefusal.accountUnsupported);
    }
    await _requireOwnedDepositWallet(ledger.eoa, wallet);
    final balance = await _balance(PolymarketConstants.usdcEAddress, wallet);
    final wrapAmount = amount ?? balance;
    if (wrapAmount <= BigInt.zero) {
      _refuse(LedgerPmFundingRefusal.nothingToMove);
    }
    if (wrapAmount > balance) {
      _refuse(LedgerPmFundingRefusal.collateralNotAvailable);
    }
    final intent = LedgerPolymarketIntents.wrap(
      walletId: ledger.walletId,
      depositWallet: wallet,
      amount: wrapAmount,
      summary: summary ??
          {
            'action': 'make_funds_available',
            'asset': _usdceAsset,
            'amount': wrapAmount.toString(),
            'account': wallet.toLowerCase(),
          },
      now: _clock(),
    );
    // Same calls the executor builds; refused here before any prompt.
    DepositWalletCallAllowlist(
      depositWallet: wallet,
      withdrawEnabled: false,
    ).validate([
      (
        target: PolymarketConstants.usdcEAddress,
        value: BigInt.zero,
        data: encodeApproveCall(
            PolymarketConstants.collateralOnrampAddress, wrapAmount),
      ),
      (
        target: PolymarketConstants.collateralOnrampAddress,
        value: BigInt.zero,
        data:
            encodeWrapCall(PolymarketConstants.usdcEAddress, wallet, wrapAmount),
      ),
    ]);
    return LedgerPmMakeAvailablePlan(
      walletId: ledger.walletId,
      account: account,
      depositWallet: wallet,
      amount: wrapAmount,
      intent: intent,
      belongsToLedger: _belongsToLedger(eoa: ledger.eoa, depositWallet: wallet),
    );
  });

  /// Signs and submits a prepared batch: one Ledger approval. [executor]
  /// comes from the Ledger approval flow's signing context; null uses the
  /// live device session. The balance is read again first.
  Future<String> executeMakeFundsAvailable(
    LedgerPmMakeAvailablePlan plan, {
    LedgerPmCollateralExecutor? executor,
  }) =>
      _exclusive(() async {
        final ledger = _pairedLedger();
        if (ledger.walletId != plan.walletId) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        await _requireOwnedDepositWallet(ledger.eoa, plan.depositWallet);
        final balance =
            await _balance(PolymarketConstants.usdcEAddress, plan.depositWallet);
        if (plan.amount > balance) {
          _refuse(LedgerPmFundingRefusal.collateralNotAvailable);
        }
        final hash = await (executor ??
                _collateralFor(plan.account, plan.belongsToLedger))
            .wrap(plan.intent);
        TrackingService.ledgerPmFundsMadeAvailable(
            amountBucket: _usdceBucket(plan.amount));
        return hash;
      });

  /// [prepareMakeFundsAvailable] then [executeMakeFundsAvailable] over the
  /// live device session.
  Future<String> makeFundsAvailable({BigInt? amount}) async =>
      executeMakeFundsAvailable(
          await prepareMakeFundsAvailable(amount: amount));

  // ───────────────────────────── reverse ─────────────────────────────

  /// Collateral that can leave. Positions are counted for display only
  /// and never included. Refused while O3 is off.
  Future<LedgerPmWithdrawable> readWithdrawable() async {
    final ledger = _pairedLedger();
    _requireWithdrawAllowed();
    final wallet = await _depositWalletFor(ledger.eoa);
    BigInt? usdce;
    BigInt? pusd;
    int? positions;
    try {
      usdce = await _reads.erc20Balance(
          token: PolymarketConstants.usdcEAddress, owner: wallet);
    } catch (_) {}
    try {
      pusd = await _reads.erc20Balance(
          token: PolymarketConstants.pusdAddress, owner: wallet);
    } catch (_) {}
    try {
      positions = (await _reads.positions(wallet)).length;
    } catch (_) {}
    return LedgerPmWithdrawable(
      withdrawEnabled: _withdrawAllowed,
      usdce: usdce,
      pusd: pusd,
      openPositions: positions,
    );
  }

  /// Unwraps pUSD back to USDC.e ahead of a withdrawal: one batch with an
  /// exact pUSD approval to the offramp and the unwrap, one Ledger
  /// approval. Never touches positions.
  Future<String> unwrapForWithdrawal({
    required BigInt amount,
    LedgerPmUnwrapApproval? approve,
    Map<String, String>? summary,
  }) =>
      _exclusive(() async {
        final ledger = _pairedLedger();
        _requireWithdrawAllowed();
        final account = await _resolve(ledger.eoa);
        final wallet = account.address;
        if (!account.canAct || wallet == null) {
          _refuse(LedgerPmFundingRefusal.accountUnsupported);
        }
        await _requireOwnedDepositWallet(ledger.eoa, wallet);
        if (amount <= BigInt.zero) _refuse(LedgerPmFundingRefusal.nothingToMove);
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        final pusd = await _balance(PolymarketConstants.pusdAddress, wallet);
        if (amount > pusd) _refuse(LedgerPmFundingRefusal.collateralNotAvailable);
        final intent = LedgerPolymarketIntents.unwrap(
          walletId: ledger.walletId,
          depositWallet: wallet,
          amount: amount,
          summary: summary ?? {
            'action': 'unwrap_for_withdrawal',
            'asset': _usdceAsset,
            'amount': amount.toString(),
            'account': wallet.toLowerCase(),
            'spender':
                PolymarketConstants.collateralOfframpAddress.toLowerCase(),
          },
          now: _clock(),
        );
        // Same calls the executor builds (exact pUSD approval to the
        // offramp, then the unwrap); refused here before any prompt.
        DepositWalletCallAllowlist(depositWallet: wallet, withdrawEnabled: false)
            .validate(ledgerPmUnwrapCalls(wallet, amount));
        final hash = approve == null
            ? await _collateralFor(
                account,
                _belongsToLedger(eoa: ledger.eoa, depositWallet: wallet),
              ).unwrap(intent)
            : await approve(intent, account: account);
        TrackingService.ledgerPmCollateralUnwrapped(
            amountBucket: _usdceBucket(amount));
        return hash;
      });

  /// Quotes USDC.e to a Ledger BTC address confirmed on the device. The
  /// amount must already be unwrapped USDC.e; pUSD and positions never
  /// count.
  Future<LedgerPmReverseQuote> quoteReverse({
    required BigInt amountUsdce,
    required double usdPerBtc,
  }) =>
      _exclusive(() async {
        final ledger = _pairedLedger();
        _requireWithdrawAllowed();
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        if (!(await _routes.availability(_reverseRoute)).isAvailable) {
          _refuse(LedgerPmFundingRefusal.routeUnavailable);
        }
        if (amountUsdce <= BigInt.zero) {
          _refuse(LedgerPmFundingRefusal.nothingToMove);
        }
        TrackingService.ledgerFundingStarted(route: kPolygonUsdceToLedgerBtcRoute);
        final wallet = await _depositWalletFor(ledger.eoa);
        await _requireUnwrapped(wallet, amountUsdce);

        final recipient = await _verifiedBtcAddress(ledger.walletId);
        final request = OrchestraQuoteRequest(
          sourceChain: _polygonChain,
          sourceAsset: _usdceAsset,
          destinationChain: _btcChain,
          destinationAsset: _btcAsset,
          amountBaseUnits: amountUsdce,
          recipientAddress: recipient.address,
          refundAddress: wallet,
          // Phase 2 has no own-bitcoin kind. Any own kind makes the guard
          // require recipient == ownAddress, which is the device-confirmed
          // Ledger BTC address.
          recipientKind: RecipientKind.ownEvm,
          ownAddress: recipient.address,
        );
        final fetched = await _quoteForReview(request,
            usdPerBtc: usdPerBtc,
            flow: kPolygonUsdceToLedgerBtcRoute,
            payer: SettlementPayer.polygonRelayer);
        final quote = fetched.quote;
        _checkQuoteAddresses(quote,
            recipient: recipient.address, refund: wallet);

        return LedgerPmReverseQuote(
          walletId: ledger.walletId,
          quote: quote,
          skew: fetched.skew,
          recipient: LedgerPmAddressRef(
            address: recipient.address,
            kind: LedgerPmAddressKind.ledgerBitcoinReceive,
            index: recipient.index,
            deviceVerifiedAt: recipient.verifiedAt,
          ),
          refund: LedgerPmAddressRef(
            address: wallet,
            kind: LedgerPmAddressKind.polymarketDepositWallet,
          ),
          binding: LedgerWithdrawalBinding(
            depositAddress: quote.depositAddress,
            refundAddress: wallet,
            recipientAddress: recipient.address,
          ),
        );
      });

  Future<void> _requireUnwrapped(String wallet, BigInt amount) async {
    final usdce = await _balance(PolymarketConstants.usdcEAddress, wallet);
    if (amount <= usdce) return;
    final pusd = await _balance(PolymarketConstants.pusdAddress, wallet);
    _refuse(amount <= usdce + pusd
        ? LedgerPmFundingRefusal.unwrapRequired
        : LedgerPmFundingRefusal.collateralNotAvailable);
  }

  /// O3 transfer to the quote-bound Orchestra deposit address, then
  /// `submitDeposit(txHash, sourceAddress)`.
  Future<LedgerPmReverseResult> executeReverse(
    LedgerPmReverseQuote q, {
    LedgerPmWithdrawalApproval? approve,
    Map<String, String>? summary,
  }) =>
      _exclusive(() async {
        final ledger = _pairedLedger();
        _requireWithdrawAllowed();
        await _pause.ensureNewOperationAllowed(PausableRoute.ledgerFunding);
        if (ledger.walletId != q.walletId) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }
        final quote = q.quote;
        final account = await _resolve(ledger.eoa);
        final wallet = account.address;
        if (!account.canAct || wallet == null) {
          _refuse(LedgerPmFundingRefusal.accountUnsupported);
        }
        await _requireOwnedDepositWallet(ledger.eoa, wallet);
        final verifiedBtc = _verifiedBtc;
        if (!sameEvmAddress(wallet, q.refund.address) ||
            !sameEvmAddress(wallet, q.binding.refundAddress) ||
            verifiedBtc == null ||
            verifiedBtc.address.trim() != q.recipient.address.trim() ||
            q.binding.recipientAddress.trim() != q.recipient.address.trim() ||
            !sameEvmAddress(q.binding.depositAddress, quote.depositAddress) ||
            isSparkAddress(q.recipient.address, mainnet: true)) {
          _refuse(LedgerPmFundingRefusal.addressNotOwned);
        }
        _checkQuoteAddresses(quote,
            recipient: q.recipient.address, refund: wallet);
        await _requireUnwrapped(wallet, q.amountUsdce);

        void payable() => OrchestraQuoteGate.ensurePayable(quote,
            amountBaseUnits: q.amountUsdce, now: _clock());
        try {
          payable();
          // B5: 90 s before the batch prompt starts.
          if (!_hasMargin(quote, q.skew, SettlementMoment.beforeDevicePrompt,
              SettlementPayer.polygonRelayer)) {
            throw const WalletGuardException(WalletGuardReason.quoteExpired);
          }
        } on WalletGuardException catch (e) {
          if (e.reason == WalletGuardReason.quoteExpired) {
            throw const LedgerFundingQuoteExpiredException(null);
          }
          rethrow;
        }
        // B5: 60 s before the relayer POST. Checked before the prompt and
        // again after the Ledger approval, immediately before the POST.
        void stillPayable() {
          payable();
          if (!_hasMargin(quote, q.skew, SettlementMoment.afterDeviceSigned,
              SettlementPayer.polygonRelayer)) {
            throw const WalletGuardException(WalletGuardReason.quoteExpired);
          }
        }

        final belongs = _belongsToLedger(
          eoa: ledger.eoa,
          depositWallet: wallet,
          btcAddress: verifiedBtc.address,
        );
        DepositWalletCallAllowlist(
          depositWallet: wallet,
          withdrawalBinding: q.binding,
          belongsToLedger: belongs,
          withdrawEnabled: withdrawEnabled,
        ).validate([
          (
            target: PolymarketConstants.usdcEAddress,
            value: BigInt.zero,
            data: encodeTransferCall(q.binding.depositAddress, q.amountUsdce),
          ),
        ]);
        final intent = LedgerPolymarketIntents.withdraw(
          walletId: ledger.walletId,
          depositWallet: wallet,
          amount: q.amountUsdce,
          binding: q.binding,
          summary: summary ?? {
            'action': 'withdraw_to_ledger_bitcoin',
            'asset': _usdceAsset,
            'amount': q.amountUsdce.toString(),
            'quote': quote.quoteId,
            'recipient': q.recipient.address,
          },
          now: _clock(),
        );

        final ownership = _ledgerOwnership(
          walletId: ledger.walletId,
          eoa: ledger.eoa,
          route: _reverseRoute,
          source: SettlementAccountKind.pmLedger,
          destination: SettlementAccountKind.ledgerBtc,
          btc: q.recipient,
          depositWallet: wallet,
        );
        final operationId = (await _records.start(
          walletId: ledger.walletId,
          accountKind: SettlementAccountKind.pmLedger,
          flow: SettlementFlow.predictionsToLedgerBtc,
          routeVersion: kPolygonUsdceToLedgerBtcRoute,
          route: _reverseRoute,
          quote: quote,
          recipient: ownership.recipient,
          refund: ownership.refund,
          skew: q.skew,
        ))
            .operationId;
        await _records.hold(operationId);
        try {
          // The batch is signed and posted in one call, so `broadcasting`
          // is on disk before it starts. The funding kind is set now so the
          // reconciler probes the relayer after a kill.
          try {
            await _records.advance(operationId, SettlementStage.reviewed);
            await _records.advance(
              operationId,
              SettlementStage.broadcasting,
              patch: (c) => c.copyWith(
                funding:
                    const SettlementFunding(kind: SettlementFundingKind.relayer),
              ),
            );
          } catch (_) {
            await _records.abandon(operationId);
            rethrow;
          }

          // One batch, one relayer transaction; never merged with another.
          String? relayerTxId;
          final String hash;
          try {
            Future<void> recordRelayerSubmitted(String id) async {
              relayerTxId = id;
              await _records.recordRelayerSubmitted(operationId, id);
            }

            stillPayable();
            hash = approve == null
                ? await _collateralFor(account, belongs).withdraw(
                    intent,
                    ensureStillPayable: stillPayable,
                    onRelayerSubmitted: recordRelayerSubmitted,
                  )
                : await approve(
                    intent,
                    account: account,
                    belongsToLedger: belongs,
                    ensureStillPayable: stillPayable,
                    onRelayerSubmitted: recordRelayerSubmitted,
                  );
          } on WalletGuardException {
            // The late check runs before the relayer POST: nothing sent.
            await _records.advanceBestEffort(
                operationId, SettlementStage.notFunded);
            TrackingService.ledgerFundingResult(
                route: kPolygonUsdceToLedgerBtcRoute, outcome: 'quote_expired');
            throw LedgerFundingQuoteExpiredException(operationId,
                duringApproval: true);
          } on LedgerSubmissionUnknownException {
            await _records.advanceBestEffort(
                operationId, SettlementStage.fundingUnknown);
            TrackingService.ledgerFundingResult(
                route: kPolygonUsdceToLedgerBtcRoute,
                outcome: 'funding_unknown');
            rethrow;
          } catch (error) {
            // Refusals before the relayer POST leave funds in place.
            final nothingSent = error is LedgerFailure ||
                error is LedgerActionBlockedException ||
                error is LedgerIntentMismatchException ||
                error is DepositWalletCallRejected;
            await _records.advanceBestEffort(
              operationId,
              nothingSent
                  ? SettlementStage.notFunded
                  : SettlementStage.fundingUnknown,
            );
            TrackingService.ledgerFundingResult(
                route: kPolygonUsdceToLedgerBtcRoute,
                outcome: nothingSent ? _errorCode(error) : 'funding_unknown');
            rethrow;
          }

          await _records.recordFunded(
            operationId,
            SettlementFunding(
              kind: SettlementFundingKind.relayer,
              evmTxHash: hash,
              relayerTxId: relayerTxId,
            ),
          );
          TrackingService.ledgerFundingBroadcast(
            route: kPolygonUsdceToLedgerBtcRoute,
            amountBucket: _usdceBucket(q.amountUsdce),
          );
          final submit = await _records.submit(operationId);
          final accepted = submit.accepted;
          TrackingService.ledgerFundingResult(
              route: kPolygonUsdceToLedgerBtcRoute,
              outcome: accepted ? 'submitted' : 'submit_pending');
          return LedgerPmReverseResult(
            operationId: operationId,
            relayerTxHash: hash,
            submitAccepted: accepted,
          );
        } finally {
          await _records.release(operationId);
        }
      });

  // TODO(O7): Hyperliquid reverse builders (`usdSend` / `spotSend`) are
  // not part of this route and are not built anywhere yet.

  static String _errorCode(Object error) {
    if (error is LedgerFailure) return 'ledger_${error.code.name}';
    if (error is LedgerPmFundingRefused) return error.reason.name;
    if (error is WalletGuardException) return error.reason.code;
    if (error is LedgerActionBlockedException) return 'blocked';
    if (error is DepositWalletCallRejected) return 'allowlist_rejected';
    return 'error';
  }
}

// ───────────────────────────── providers ─────────────────────────────

/// One service per Ledger wallet. Keep it watched for the whole sheet:
/// `executeForward` relies on the refund address the same instance
/// confirmed on the device in `quoteForward`.
///
/// No key is involved. BTC is signed by the Ledger Bitcoin app through
/// `LedgerBtcSendService`; batches are signed by the Ledger Ethereum app
/// through the Phase 3 executor with the live device session, and refuse
/// when no Ledger is connected.
final ledgerPolymarketFundingServiceProvider = Provider.autoDispose
    .family<LedgerPolymarketFundingService, String>((ref, walletId) {
  final identity = ref.watch(ledgerIdentityProvider(walletId));
  return LedgerPolymarketFundingService(
    identity: identity,
    reads: ref.watch(ledgerPolymarketReadsProvider),
    btcLeg: LedgerBtcSendServiceLeg(
      ref.watch(ledgerBtcSendServiceProvider),
      walletFor: (id) {
        for (final wallet in ref.read(settingsProvider).wallets) {
          if (wallet.id == id) return wallet;
        }
        throw const LedgerBtcSendException(LedgerBtcSendError.notLedger);
      },
      receiveInfoFor: (id) => ref.read(walletReceiveInfoProvider(id).future),
      feeRateSatVb: () => ref.read(getCustomFeeRateProvider.future),
    ),
    collateralFor: (account, belongsToLedger) {
      final paired = identity?.evmAddress;
      final session = ref.read(ledgerServiceProvider.notifier).deviceSession;
      if (identity == null || !identity.hasVerifiedEvm || paired == null) {
        throw const LedgerFailure(LedgerFailureCode.wrongSigner);
      }
      if (session == null) {
        throw const LedgerFailure(LedgerFailureCode.disconnected);
      }
      final signer = ref.read(ledgerEvmSignerFactoryProvider)(session, paired);
      return LedgerPolymarketExecutorCollateral(
        ref.read(ledgerPmExecutorFactoryProvider)(
          walletId: walletId,
          pairedAddress: paired,
          signer: signer.externalSigner,
          account: account,
          belongsToLedger: belongsToLedger,
        ),
      );
    },
    records: ref.watch(ledgerSettlementRecordsProvider),
    routes: ref.watch(ledgerFundingRouteAvailabilityProvider),
    pausePolicy: ref.watch(routePausePolicyProvider),
  );
});
