// lib/services/hyperliquid/cctp_withdrawal.dart
//
// Investing → Dollars by Circle CCTP, the fallback while Orchestra refuses
// HyperCore-source routes ("unsupported_route": "HyperCore source routes
// require independent deposit verification and are unavailable").
//
// The normal route stays first: `hypercore:USDC → spark:USDB` quoted by
// Orchestra and funded by a perpetuals usdSend. Only when that quote is
// refused for the route itself, before anything is signed, the rail and
// the Move sheet come here:
//
//  0. The runtime policy: the capabilities the normal route's quote asks
//     of `hypercore:USDC → spark:USDB` (`hyperliquid.withdraw`), checked
//     the same way and read as fresh. Withheld, nothing is registered,
//     approved or signed. The fallback never quotes, so this is the only
//     place it meets the switch.
//  1. Kute's backend registers (or this wallet reuses) the wallet's
//     Investing-withdrawal standing instruction, `arbitrum:USDC →
//     spark:USDB` to the wallet's own Spark address, with the
//     venue-withdrawal fee pinned (StandingDepositStore
//     .investingWithdrawalInstruction). No verified fee, no send.
//  2. Read-only pre-flight on HyperEVM (Circle's CoreDepositWallet):
//     `paused()` must be false, `calculateCrossChainWithdrawalFee(true, 3)`
//     is the forwarding fee. The amount after that fee must clear
//     Orchestra's live minimum for the route plus a margin.
//  3. One signed Hyperliquid user action, `sendToEvmWithData`: HyperCore
//     burns the USDC and Circle's Forwarding Service mints native USDC
//     (amount − fee) on Arbitrum to the standing address. Empty hook data,
//     so Circle pays the destination mint. No HyperEVM transaction, no
//     HYPE, never `withdraw3`.
//  4. Orchestra sees the deposit on the standing address and converts it
//     to dollars with no quote or submit.
//
// Persistence is the settlement record (flow `investingToDollarsCctp`):
// the nonce is written (stage `broadcasting`) BEFORE the POST; the
// HyperCore ledger row is the funding proof (`funded`); the standing
// address's deposit and its order carry it to `processing` and the
// order's outcome. A restart resumes from the record and never signs
// again: a nonce the ledger never shows proves nothing left (`notFunded`).
//
// Sources: https://developers.circle.com/cctp/howtos/withdraw-usdc-from-hypercore-to-evm
// and https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint.
// Observed on mainnet 2026-10-13: a `sendToEvmWithData` of 173 USDC with
// `data: 0x` minted 172.8 USDC on Arbitrum about ten seconds after its
// HyperCore block; the ledger row is a `send` to the USDC system address
// 0x2000…0000 carrying the signed nonce, with the HyperCore gas fee
// (0.03 USDC) charged on top of the amount.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraOrder;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/arbitrum_read_rpc.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_reconciler.dart'
    show settlementStageForProviderStatus;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent, SettlementStepUpHook,
        SettlementStopReason, SettlementStopped;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart'
    show kHypercoreToSparkUsdRoute;
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_dex_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart'
    show hypercorePerpUsdcWire, hypercoreUsdcToken, verifyHypercoreUsdcMetadata;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraCapabilityRequirements;
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart'
    show claimOrderTerminalAnalytics, orchestraExchangeStatus;
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

// ───────────────────────────── constants ─────────────────────────────

/// Circle's CoreDepositWallet on HyperEVM (chain 999): the contract the
/// HyperCore USDC system address hands a `sendToEvmWithData` to.
const String kCircleCoreDepositWallet =
    '0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24';

/// Public HyperEVM RPC. Read-only `eth_call`s only; nothing is ever sent.
const String kHyperEvmRpc = 'https://rpc.hyperliquid.xyz/evm';
const int kHyperEvmChainId = 999;

/// CCTP domain of Arbitrum (the `destinationChainId` of the action).
const int kCctpArbitrumDomain = 3;

/// Destination gas Circle's guide uses for the forwarded mint.
const int kCctpForwardGasLimit = 200000;

/// HyperCore's USDC system address: the ledger `send` a CCTP burn records.
const String kHypercoreUsdcSystemAddress =
    '0x2000000000000000000000000000000000000000';

/// HyperCore gas a user action may charge on top of the amount, in
/// eight-decimal USDC: observed $0.002–0.05 for accounts without HYPE.
final BigInt kCctpCoreFeeReserve = BigInt.from(6000000); // $0.06

/// Kept above Orchestra's minimum so a price tick cannot hold the deposit.
const double kCctpMinimumMarginUsd = 0.05;

/// Orchestra's floor for `arbitrum:USDC → spark:USDB` (/limits, read
/// 2026-10-13: `minUsdCents` 80) when the live limits are unreachable.
const double kCctpFallbackMinimumUsd = 0.80;

/// The runtime-policy capabilities a CCTP move needs: exactly what the
/// normal route's quote asks of `hypercore:USDC → spark:USDB`
/// (`hyperliquid.withdraw`), so the fallback can never run while the
/// route it stands in for is switched off.
final List<String> kCctpCapabilities = orchestraCapabilityRequirements(
    sourceChain: kHypercoreToSparkUsdRoute.fromChain,
    sourceAsset: kHypercoreToSparkUsdRoute.fromAsset,
    destinationChain: kHypercoreToSparkUsdRoute.toChain,
    destinationAsset: kHypercoreToSparkUsdRoute.toAsset);

/// How old a policy the pre-flight may read instead of fetching it again:
/// the minute the Orchestra quote and the order posts use. The Move sheet
/// and the sweeper reach the fallback moments after the normal route's
/// quote fetched it.
const Duration kCctpPolicyMaxAge = Duration(seconds: 60);

/// A recorded nonce with no ledger row this long after signing proves the
/// burn never happened: the signed action was never stored, so nothing
/// can post it after this process lost it.
const Duration kCctpNotSentAfter = Duration(minutes: 5);

/// Funded but nothing at Orchestra this long after: needs attention (and
/// keeps being checked).
const Duration kCctpAttentionAfter = Duration(minutes: 45);

/// How long a not-funded / attention / failed operation keeps a check.
const Duration kCctpSlowWatch = Duration(days: 14);

/// Which `token` string the action carries. Circle's guide writes `USDC`;
/// Hyperliquid's docs write `tokenName:tokenId`. Mainnet accepts both
/// (both forms observed on 2026-10-13). Circle's form is the default;
/// `--dart-define=HL_CCTP_TOKEN_ID=true` switches for a device test.
enum CctpTokenForm { circle, tokenId }

const CctpTokenForm kHypercoreCctpTokenForm =
    bool.fromEnvironment('HL_CCTP_TOKEN_ID')
        ? CctpTokenForm.tokenId
        : CctpTokenForm.circle;

String cctpTokenWire(CctpTokenForm form) =>
    form == CctpTokenForm.circle ? 'USDC' : hypercoreUsdcToken;

/// The Arbitrum USDC → Dollars route the standing instruction converts.
final RouteKey kArbitrumUsdcToDollarsRoute = RouteKey(
    fromChain: 'arbitrum',
    fromAsset: 'USDC',
    toChain: 'spark',
    toAsset: 'USDB');

/// Activity row id prefix while the move has no Orchestra order yet. The
/// CCTP watcher owns these rows; the Orchestra status poller never asks
/// about them (`SwapOrder.shouldPollOrchestra`).
const String kCctpRowPrefix = 'cctp-';

/// The HyperCore → [destination] route a CCTP move stands for.
RouteKey cctpRouteFor(InvestingWithdrawalDestination destination) =>
    destination == InvestingWithdrawalDestination.dollars
        ? kHypercoreToSparkUsdRoute
        : RouteKey(
            fromChain: 'hypercore',
            fromAsset: 'USDC',
            toChain: destination.chain,
            toAsset: destination.asset);

/// The settlement flow a CCTP move into [destination] is recorded under.
SettlementFlow cctpFlowFor(InvestingWithdrawalDestination destination) =>
    switch (destination) {
      InvestingWithdrawalDestination.dollars =>
        SettlementFlow.investingToDollarsCctp,
      InvestingWithdrawalDestination.bitcoin =>
        SettlementFlow.investingToBtcCctp,
      InvestingWithdrawalDestination.predictions =>
        SettlementFlow.investingToPredictionsCctp,
    };

/// The destination a CCTP operation was recorded for.
InvestingWithdrawalDestination cctpDestinationOf(SettlementFlow flow) =>
    switch (flow) {
      SettlementFlow.investingToBtcCctp => InvestingWithdrawalDestination.bitcoin,
      SettlementFlow.investingToPredictionsCctp =>
        InvestingWithdrawalDestination.predictions,
      _ => InvestingWithdrawalDestination.dollars,
    };

/// The runtime-policy capabilities a CCTP move into [destination] needs:
/// what Orchestra's own quote would ask of the HyperCore route
/// (`hyperliquid.withdraw`, plus `polymarket.deposit` into Predictions).
List<String> cctpCapabilitiesFor(InvestingWithdrawalDestination destination) =>
    destination == InvestingWithdrawalDestination.dollars
        ? kCctpCapabilities
        : orchestraCapabilityRequirements(
            sourceChain: 'hypercore',
            sourceAsset: 'USDC',
            destinationChain: destination.chain,
            destinationAsset: destination.asset);

/// The analytics `destination` of a CCTP move into [destination].
String cctpAnalyticsDestination(InvestingWithdrawalDestination destination) =>
    switch (destination) {
      InvestingWithdrawalDestination.dollars => 'usd',
      InvestingWithdrawalDestination.bitcoin => 'btc',
      InvestingWithdrawalDestination.predictions => 'predictions',
    };

// ───────────────────────────── outcomes ──────────────────────────────

enum CctpUnavailableReason {
  paused('paused'),
  belowMinimum('below_minimum'),
  feeReadFailed('fee_read_failed'),
  rpcFailed('rpc_failed'),
  feeTermsUnavailable('fee_terms_unavailable'),
  inFlight('in_flight'),

  /// The runtime policy withholds a capability the route needs
  /// ([kCctpCapabilities]): an emergency switch or a region rule.
  capability('capability');

  const CctpUnavailableReason(this.code);

  /// Analytics value.
  final String code;
}

/// The fallback cannot run. Thrown before anything is signed.
class CctpUnavailable implements Exception {
  const CctpUnavailable(this.reason, {this.decision});
  final CctpUnavailableReason reason;

  /// The policy's denial when [reason] is
  /// [CctpUnavailableReason.capability], so a screen can show it the way
  /// every other withheld capability is shown.
  final CapabilityDecision? decision;

  @override
  String toString() => 'CctpUnavailable(${reason.code})';
}

/// The exchange answered the signed action with a rejection: it was not
/// executed. The ledger stays the judge on a later check.
class CctpSendRejected implements Exception {
  const CctpSendRejected(this.cause);
  final Object cause;

  @override
  String toString() => 'CctpSendRejected($cause)';
}

/// A CCTP move that was signed and sent.
class CctpWithdrawalResult {
  const CctpWithdrawalResult({
    required this.operationId,
    required this.sentUsd,
    required this.arrivingUsdEstimate,
    required this.registration,
  });

  final String operationId;

  /// What left Investing (the burned amount).
  final double sentUsd;

  /// What reaches the standing address after Circle's forwarding fee,
  /// before Orchestra's conversion.
  final double arrivingUsdEstimate;

  /// Completes with the Orchestra order id once the standing address
  /// turned the deposit into an order, or null when the foreground watch
  /// ended first (the reconciler carries on). Never throws.
  final Future<String?> registration;
}

// ───────────────────────────── pure rules ────────────────────────────

/// Why the pre-flight stops, or null to go ahead. [amount6] and
/// [forwardFee6] are six-decimal USDC; [minimumUsd] Orchestra's floor.
CctpUnavailableReason? cctpPreflightBlocker({
  required bool paused,
  required BigInt forwardFee6,
  required BigInt amount6,
  required double minimumUsd,
}) {
  if (paused) return CctpUnavailableReason.paused;
  if (forwardFee6 < BigInt.zero) return CctpUnavailableReason.feeReadFailed;
  if (amount6 <= forwardFee6) return CctpUnavailableReason.belowMinimum;
  final net = amount6 - forwardFee6;
  final floor =
      BigInt.from(((minimumUsd + kCctpMinimumMarginUsd) * 1e6).round());
  if (net < floor) return CctpUnavailableReason.belowMinimum;
  return null;
}

/// The amount to burn, in eight-decimal HyperCore USDC (whole micro-
/// dollars): what was asked for, capped at the sendable cash minus the
/// HyperCore gas reserve. Zero when nothing fits.
BigInt cctpSendAmount({
  required BigInt requested8,
  required BigInt sendable8,
}) {
  final unit = BigInt.from(100);
  final room = sendable8 - kCctpCoreFeeReserve;
  var amount = requested8 < room ? requested8 : room;
  amount = (amount ~/ unit) * unit;
  return amount > BigInt.zero ? amount : BigInt.zero;
}

BigInt? _usdcUnits8(Object? value) {
  final text = value?.toString() ?? '';
  if (!RegExp(r'^\d+(?:\.\d{1,8})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  return BigInt.tryParse(
      parts.first + (parts.length == 1 ? '' : parts[1]).padRight(8, '0'));
}

/// The ledger hash of exactly this burn: a `send` of [amount8] USDC from
/// [source] to the USDC system address carrying [nonce]. Null when there
/// is none or more than one.
String? matchHypercoreCctpSend({
  required Iterable<dynamic> updates,
  required String source,
  required BigInt amount8,
  required int nonce,
}) {
  final matches = <String>{};
  for (final update in updates) {
    if (update is! Map) continue;
    final hash = update['hash'];
    final delta = update['delta'];
    if (hash is! String ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash) ||
        delta is! Map ||
        delta['type'] != 'send' ||
        delta['nonce'] != nonce) {
      continue;
    }
    final token = delta['token'];
    if (token != 'USDC' && token != hypercoreUsdcToken) continue;
    if (!sameEvmAddress('${delta['user']}', source) ||
        !sameEvmAddress('${delta['destination']}', kHypercoreUsdcSystemAddress) ||
        _usdcUnits8(delta['amount']) != amount8) {
      continue;
    }
    matches.add(hash);
  }
  return matches.length == 1 ? matches.single : null;
}

/// The Arbitrum mint of this move: Circle mints at most [amount6] and at
/// least [amount6] − [maxFee6]. Null unless exactly one unclaimed mint
/// fits.
ArbitrumTokenMint? matchCctpMint({
  required Iterable<ArbitrumTokenMint> mints,
  required BigInt amount6,
  required BigInt maxFee6,
  Set<String> claimed = const {},
}) {
  final fits = mints
      .where((m) =>
          m.amount <= amount6 &&
          m.amount >= amount6 - maxFee6 &&
          !claimed.contains(m.txHash.toLowerCase()))
      .toList();
  return fits.length == 1 ? fits.single : null;
}

/// The standing deposit this move became: Arbitrum USDC in the mint's
/// amount window, observed after [sentAt] (less a clock margin), not
/// claimed by another move. The mint's transaction, when known, decides.
Map<String, dynamic>? matchCctpDeposit({
  required Iterable<Map<String, dynamic>> deposits,
  required BigInt amount6,
  required BigInt maxFee6,
  required DateTime sentAt,
  String? mintTxHash,
  Set<String> claimed = const {},
}) {
  final candidates = <Map<String, dynamic>>[];
  for (final d in deposits) {
    final id = d['id'];
    final amount = BigInt.tryParse('${d['amount']}');
    final observed = DateTime.tryParse('${d['observedAt']}');
    if (id is! String ||
        claimed.contains(id) ||
        d['chain'] != 'arbitrum' ||
        '${d['asset']}'.toUpperCase() != 'USDC' ||
        amount == null ||
        amount > amount6 ||
        amount < amount6 - maxFee6) {
      continue;
    }
    if (mintTxHash != null) {
      final tx = d['sourceTxId'];
      if (tx is String && tx.toLowerCase() == mintTxHash.toLowerCase()) {
        return d;
      }
    }
    if (observed != null &&
        observed.isBefore(sentAt.subtract(const Duration(minutes: 5)))) {
      continue;
    }
    candidates.add(d);
  }
  return candidates.length == 1 ? candidates.single : null;
}

// ───────────────────────────── ports ─────────────────────────────────

/// Public chain reads. Every read throws on failure: a failed read is
/// never an empty answer.
abstract interface class CctpChainReads {
  Future<bool> coreDepositWalletPaused();

  /// `calculateCrossChainWithdrawalFee(true, domain)`, six-decimal USDC.
  Future<BigInt> forwardingFee(int domain);

  Future<int> arbitrumBlock();

  Future<List<ArbitrumTokenMint>> arbitrumUsdcMints(String to, int fromBlock);

  /// The ledger hash of the burn, or null when the ledger has none.
  Future<String?> ledgerSendHash(
      {required String source, required BigInt amount8, required int nonce});
}

/// The Investing account's side: cash and the signed send.
abstract interface class CctpSender {
  /// HyperCore USDC (eight decimals) the account could send right now.
  Future<BigInt> sendableBaseUnits(String account);

  /// Collects the cash into perpetuals, signs one `sendToEvmWithData` of
  /// [amount8] to [destination] and POSTs it. [onBeforePost] runs after
  /// signing and before the POST (a throw aborts it). Returns the nonce.
  /// Throws [SettlementFundingRefused] when nothing was posted and
  /// [CctpSendRejected] when the exchange rejected the action.
  Future<int> send({
    required String walletId,
    required String account,
    required String destination,
    required BigInt amount8,
    required int domain,
    required String token,
    required Future<void> Function(int nonce) onBeforePost,
  });
}

/// Orchestra through Kute's backend.
abstract interface class CctpOrchestraPort {
  Future<StandingDepositRecord> instruction({
    required String walletId,
    required String recipient,
    required String refundAddress,
    required bool Function() wanted,
    InvestingWithdrawalDestination destination =
        InvestingWithdrawalDestination.dollars,
  });

  Future<StandingDepositRecord?> record(String walletId, String label);

  Future<List<Map<String, dynamic>>> deposits(
      StandingDepositRecord record, bool Function() current);

  /// The order, or null when it cannot be read.
  Future<OrchestraOrder?> order(String orderId);

  /// The route's live floor in dollars, or null when unreachable.
  Future<double?> minimumUsd(
      {InvestingWithdrawalDestination destination =
          InvestingWithdrawalDestination.dollars});

  void logPending(SwapOrder row);
}

abstract interface class CctpActivityRows {
  SwapOrder? find(String id);
  Future<void> put(SwapOrder row);
  Future<void> remove(String id);
}

abstract interface class CctpWalletContext {
  String spendingWalletId();
  void ensureSpending(String walletId);
  Future<String> investingAddress();
  Future<String> sparkAddress();

  /// The wallet's own Predictions account (its Polymarket deposit
  /// wallet), or '' when it is not set up.
  Future<String> predictionsAddress();
}

// ───────────────────────────── service ───────────────────────────────

class HypercoreCctpWithdrawal {
  HypercoreCctpWithdrawal({
    required this.reads,
    required this.sender,
    required this.orchestra,
    required this.rows,
    required this.wallet,
    Future<SettlementStore> Function()? store,
    DateTime Function()? clock,
    RuntimeCapabilitiesService Function()? policy,
    this.tokenForm = kHypercoreCctpTokenForm,
    this.confirmAttempts = 7,
    this.confirmInterval = const Duration(seconds: 1),
    this.watchInterval = const Duration(seconds: 4),
    this.watchFor = const Duration(minutes: 20),
  })  : _store = store ?? SettlementStore.shared,
        _clock = clock ?? DateTime.now,
        _policy = policy ?? (() => RuntimeCapabilitiesService.instance);

  factory HypercoreCctpWithdrawal.live(ProviderReader read) =>
      HypercoreCctpWithdrawal(
        reads: LiveCctpChainReads(),
        sender: LiveCctpSender(read),
        orchestra: const LiveCctpOrchestraPort(),
        rows: RiverpodCctpActivityRows(read),
        wallet: RiverpodCctpWalletContext(read),
      );

  final CctpChainReads reads;
  final CctpSender sender;
  final CctpOrchestraPort orchestra;
  final CctpActivityRows rows;
  final CctpWalletContext wallet;
  final Future<SettlementStore> Function() _store;
  final DateTime Function() _clock;
  final RuntimeCapabilitiesService Function() _policy;
  final CctpTokenForm tokenForm;
  final int confirmAttempts;
  final Duration confirmInterval;
  final Duration watchInterval;
  final Duration watchFor;

  /// Operations a pass is running for in this process.
  final Set<String> _running = {};

  static String rowIdFor(String operationId) => '$kCctpRowPrefix$operationId';

  Never _unavailable(CctpUnavailableReason reason, double usd,
      {CapabilityDecision? decision}) {
    TrackingService.hyperliquidCctpUnavailable(
        reason: reason.code, amountUsd: usd);
    throw CctpUnavailable(reason, decision: decision);
  }

  /// Brings [usd] of Investing cash home to Dollars by CCTP. [stepUp]
  /// approves the move (a user grant, or the sweep's own-address check);
  /// [purpose] is recorded with it. Throws [CctpUnavailable] or the
  /// step-up's [SettlementStopped] before anything is signed.
  Future<CctpWithdrawalResult> withdrawToDollars({
    required double usd,
    required SettlementStepUpHook stepUp,
    String purpose = 'manual_move',
  }) =>
      withdrawTo(
          destination: InvestingWithdrawalDestination.dollars,
          usd: usd,
          stepUp: stepUp,
          purpose: purpose);

  /// Moves [usd] of Investing cash by CCTP straight to [destination]:
  /// Dollars or Bitcoin on the wallet's own Spark address, or the
  /// wallet's own Predictions account. Each destination pays its own
  /// standing instruction, registered with the destination's fee rule.
  /// Throws [CctpUnavailable] (the instruction refused included, as
  /// [CctpUnavailableReason.feeTermsUnavailable]) or the step-up's
  /// [SettlementStopped] before anything is signed.
  Future<CctpWithdrawalResult> withdrawTo({
    required InvestingWithdrawalDestination destination,
    required double usd,
    required SettlementStepUpHook stepUp,
    String purpose = 'manual_move',
  }) async {
    final walletId = wallet.spendingWalletId();
    final predictions =
        destination == InvestingWithdrawalDestination.predictions;
    final flow = cctpFlowFor(destination);
    final route = cctpRouteFor(destination);
    final routeVersion = hypercoreCctpRouteVersion(destination);
    final String account;
    final String spark;
    try {
      account = await wallet.investingAddress();
      wallet.ensureSpending(walletId);
      spark = predictions
          ? await wallet.predictionsAddress()
          : await wallet.sparkAddress();
      wallet.ensureSpending(walletId);
    } catch (_) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet');
    }
    if (!isEvmAddress(account) ||
        spark.isEmpty ||
        (predictions &&
            (!isEvmAddress(spark) || sameEvmAddress(spark, account)))) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet');
    }
    final store = await _store();
    // One CCTP move at a time per wallet until the earlier one reached
    // Orchestra: the deposit match must never be ambiguous.
    for (final op in await store.pendingForReconcile()) {
      if (op.walletId == walletId &&
          op.flow.isInvestingCctp &&
          (op.stage == SettlementStage.created ||
              op.stage == SettlementStage.broadcasting ||
              op.stage == SettlementStage.fundingUnknown ||
              op.stage == SettlementStage.funded)) {
        _unavailable(CctpUnavailableReason.inFlight, usd);
      }
    }

    // 0. The runtime policy, as the normal route's quote checks it. A
    // policy that cannot be read follows the same rule: the offline
    // table (`hyperliquid.withdraw` is an exit, allowed) unless a policy
    // seen earlier denied it.
    try {
      await _policy().ensureAllAllowed(cctpCapabilitiesFor(destination),
          maxAge: kCctpPolicyMaxAge);
    } on CapabilityUnavailableException catch (e) {
      _unavailable(CctpUnavailableReason.capability, usd,
          decision: e.decision);
    }
    wallet.ensureSpending(walletId);

    // 1. The instruction, with Kute's venue-withdrawal fee verified.
    final StandingDepositRecord record;
    try {
      record = await orchestra.instruction(
          walletId: walletId,
          recipient: spark,
          refundAddress: account,
          wanted: () => wallet.spendingWalletId() == walletId,
          destination: destination);
    } on InvestingWithdrawalTermsUnavailable {
      _unavailable(CctpUnavailableReason.feeTermsUnavailable, usd);
    }
    wallet.ensureSpending(walletId);
    final depositAddress = StandingDepositStore.investingWithdrawalAddress(
        record, spark,
        destination: destination);
    if (depositAddress == null) {
      _unavailable(CctpUnavailableReason.feeTermsUnavailable, usd);
    }

    // 2. Amount and the read-only pre-flight.
    final BigInt sendable;
    try {
      sendable = await sender.sendableBaseUnits(account);
    } catch (_) {
      _unavailable(CctpUnavailableReason.rpcFailed, usd);
    }
    final amount8 = cctpSendAmount(
        requested8: hypercoreUsdcBaseUnits(usd), sendable8: sendable);
    final amount6 = amount8 ~/ BigInt.from(100);
    final bool paused;
    final BigInt fee6;
    try {
      paused = await reads.coreDepositWalletPaused();
    } catch (_) {
      _unavailable(CctpUnavailableReason.rpcFailed, usd);
    }
    try {
      fee6 = await reads.forwardingFee(kCctpArbitrumDomain);
    } catch (_) {
      _unavailable(CctpUnavailableReason.feeReadFailed, usd);
    }
    final minimum = await orchestra
            .minimumUsd(destination: destination)
            .catchError((Object _) => null) ??
        kCctpFallbackMinimumUsd;
    final blocker = cctpPreflightBlocker(
        paused: paused,
        forwardFee6: fee6,
        amount6: amount6,
        minimumUsd: minimum);
    if (blocker != null) _unavailable(blocker, usd);
    final sentUsd = amount6.toDouble() / 1e6;
    final arrivingUsd = (amount6 - fee6).toDouble() / 1e6;

    // 3. Approval. The final recipient is the wallet's own Spark address
    // through its own standing instruction; the intent names that, as the
    // normal route's does.
    final intent = SettlementAuthorizationIntent(
      flow: flow,
      walletId: walletId,
      destination: '$spark|$routeVersion',
      routeLabel: route.label,
      amountIn: amount8,
      minReceive: (amount6 - fee6) * BigInt.from(9900) ~/ BigInt.from(10000),
      maxFeeBps: 100,
    );
    if (!await stepUp(intent)) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    wallet.ensureSpending(walletId);

    int? fromBlock;
    try {
      fromBlock = await reads.arbitrumBlock();
    } catch (_) {
      // The mint watch is a step signal, not the proof: Orchestra's
      // deposit listing still finds the money.
    }

    // 4. The record, then the row, then the send.
    final now = _clock();
    final op = await store.create(SettlementOperation(
      operationId: OrchestraService.generateIdempotencyKey(),
      walletId: walletId,
      accountKind: SettlementAccountKind.hlHot,
      flow: flow,
      routeVersion: routeVersion,
      route: route,
      amountInBaseUnits: amount8.toString(),
      recipient: SettlementAddressRef(
          address: spark,
          kind: predictions
              ? OwnedAddressKind.polymarketDepositWallet
              : OwnedAddressKind.sparkSelf),
      refund: SettlementAddressRef(
          address: account, kind: OwnedAddressKind.hyperliquidEoa),
      stage: SettlementStage.created,
      createdAt: now,
      updatedAt: now,
      raw: {
        'cctp': {
          'label': record.label,
          'depositAddress': depositAddress,
          'destination': destination.key,
          'domain': kCctpArbitrumDomain,
          'forwardFee6': fee6.toString(),
          'amount6': amount6.toString(),
          'token': cctpTokenWire(tokenForm),
          'purpose': purpose,
          if (fromBlock != null) 'fromBlock': fromBlock,
          'steps': <String>[],
        },
      },
    ));
    TrackingService.settlementOperationStarted(
        flow: op.flow.code,
        routeVersion: routeVersion,
        amountUsd: sentUsd);
    final lease = store.acquireLease(op.operationId);
    final rowId = rowIdFor(op.operationId);
    await rows.put(_pendingRow(
        id: rowId,
        op: op,
        destination: depositAddress,
        target: destination,
        spark: spark,
        account: account,
        amount6: amount6,
        fee6: fee6));
    int nonce;
    try {
      nonce = await sender.send(
        walletId: walletId,
        account: account,
        destination: depositAddress,
        amount8: amount8,
        domain: kCctpArbitrumDomain,
        token: cctpTokenWire(tokenForm),
        onBeforePost: (signedNonce) async {
          final write = await store.transition(
            op.operationId,
            SettlementStage.broadcasting,
            from: SettlementStage.created,
            patch: (current) => current.copyWith(
                funding: SettlementFunding(
                    kind: SettlementFundingKind.hyperliquid,
                    hlNonce: signedNonce)),
          );
          if (!write.applied) throw StateError('CCTP operation changed');
        },
      );
    } on SettlementFundingRefused catch (e) {
      // Certainly not posted. Before the nonce write the record simply
      // ends; after it (a check between the write and the POST stopped
      // it) the record proves the nonce was never used.
      final current = await store.get(op.operationId);
      if (current?.stage == SettlementStage.broadcasting) {
        await _markNotFunded(store, op.operationId, rowId);
      } else {
        await _endUnsent(store, op.operationId, rowId);
      }
      if (lease != null) store.releaseLease(op.operationId, lease);
      throw e.cause;
    } on CctpSendRejected catch (e) {
      // Signed and answered with a rejection: not executed. The record
      // keeps its slow ledger check in case the answer was wrong.
      await _markNotFunded(store, op.operationId, rowId);
      if (lease != null) store.releaseLease(op.operationId, lease);
      throw e.cause;
    } catch (e) {
      // The POST may have reached the exchange. Nothing signs again; the
      // ledger decides.
      if (lease != null) store.releaseLease(op.operationId, lease);
      final current = await store.get(op.operationId);
      if (current?.stage == SettlementStage.created) {
        await _endUnsent(store, op.operationId, rowId);
        rethrow;
      }
      _startWatch(op.operationId);
      return CctpWithdrawalResult(
          operationId: op.operationId,
          sentUsd: sentUsd,
          arrivingUsdEstimate: arrivingUsd,
          registration: _registration(op.operationId));
    }
    if (lease != null) store.releaseLease(op.operationId, lease);
    await _step(store, op.operationId, 'cctp_sent', sentUsd);

    // 5. The ledger row, briefly in the foreground.
    for (var attempt = 0; attempt < confirmAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(confirmInterval);
      try {
        final hash = await reads.ledgerSendHash(
            source: account, amount8: amount8, nonce: nonce);
        if (hash != null) {
          await _markFunded(store, op.operationId, hash, sentUsd);
          break;
        }
      } catch (_) {
        // The persisted nonce lets the watcher carry on.
      }
    }
    _startWatch(op.operationId);
    return CctpWithdrawalResult(
        operationId: op.operationId,
        sentUsd: sentUsd,
        arrivingUsdEstimate: arrivingUsd,
        registration: _registration(op.operationId));
  }

  // ─────────────────────────── watching ───────────────────────────

  final Map<String, Completer<String?>> _registrations = {};

  Future<String?> _registration(String operationId) =>
      (_registrations[operationId] ??= Completer<String?>()).future;

  void _settleRegistration(String operationId, String? orderId) {
    final completer = _registrations.remove(operationId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(orderId);
    }
  }

  void _startWatch(String operationId) {
    unawaited(_watch(operationId));
  }

  Future<void> _watch(String operationId) async {
    final started = _clock();
    try {
      while (_clock().difference(started) < watchFor) {
        await Future<void>.delayed(watchInterval);
        final store = await _store();
        final op = await store.get(operationId);
        if (op == null) break;
        await reconcile(op, force: true);
        final after = await store.get(operationId);
        if (after == null) break;
        if (after.orderId != null) {
          _settleRegistration(operationId, after.orderId);
        }
        if (after.stage.isTerminal ||
            after.stage == SettlementStage.notFunded ||
            after.stage == SettlementStage.failed) {
          break;
        }
      }
    } catch (_) {
      // The reconciler driver carries on.
    } finally {
      _settleRegistration(operationId, null);
    }
  }

  /// One pass for [op]. Called by the foreground watch and by the
  /// settlement reconciler driver on start, resume, unlock and each sync.
  /// Never signs or sends.
  Future<void> reconcile(SettlementOperation op, {bool force = false}) async {
    if (!op.flow.isInvestingCctp) return;
    if (op.stage.isTerminal) return;
    if (!_running.add(op.operationId)) return;
    try {
      final store = await _store();
      if (store.isLeased(op.operationId)) return;
      final fresh = await store.get(op.operationId);
      if (fresh == null || fresh.stage.isTerminal) return;
      if (!force && !_due(fresh)) return;
      await _reconcileOnce(store, fresh);
    } finally {
      _running.remove(op.operationId);
    }
  }

  bool _due(SettlementOperation op) {
    final now = _clock();
    final last = op.poll.lastCheckedAt;
    final slow = op.stage == SettlementStage.notFunded ||
        op.stage == SettlementStage.needsAttention ||
        op.stage == SettlementStage.failed;
    if (slow) {
      final since = op.stageEnteredAt ?? op.updatedAt;
      if (now.difference(since) > kCctpSlowWatch) return false;
      return last == null || now.difference(last) >= const Duration(minutes: 10);
    }
    return last == null || now.difference(last) >= const Duration(seconds: 20);
  }

  Map<String, dynamic> _cctp(SettlementOperation op) {
    final raw = op.raw['cctp'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Future<void> _reconcileOnce(
      SettlementStore store, SettlementOperation op) async {
    final rowId = rowIdFor(op.operationId);
    final account = op.refund?.address ?? '';
    final nonce = op.funding?.hlNonce;
    await _touch(store, op);
    switch (op.stage) {
      case SettlementStage.created:
        // Never signed (the nonce write comes first). A record a live
        // send no longer holds is abandoned after a grace.
        if (_clock().difference(op.createdAt) > const Duration(minutes: 10)) {
          await _endUnsent(store, op.operationId, rowId);
        }
        return;
      case SettlementStage.broadcasting:
      case SettlementStage.fundingUnknown:
      case SettlementStage.notFunded:
        if (nonce == null) return;
        final String? hash;
        try {
          hash = await reads.ledgerSendHash(
              source: account, amount8: op.amountIn, nonce: nonce);
        } catch (_) {
          return; // A failed read proves nothing either way.
        }
        if (hash != null) {
          await _markFunded(store, op.operationId, hash,
              op.amountIn.toDouble() / 1e8);
          final funded = await store.get(op.operationId);
          if (funded != null) await _afterFunding(store, funded);
          return;
        }
        final signedAt = DateTime.fromMillisecondsSinceEpoch(nonce);
        if (op.stage != SettlementStage.notFunded &&
            _clock().difference(signedAt) > kCctpNotSentAfter) {
          await _markNotFunded(store, op.operationId, rowId);
        }
        return;
      default:
        await _afterFunding(store, op);
    }
  }

  Future<void> _afterFunding(
      SettlementStore store, SettlementOperation op) async {
    final cctp = _cctp(op);
    final amount6 = BigInt.tryParse('${cctp['amount6']}') ??
        op.amountIn ~/ BigInt.from(100);
    final fee6 = BigInt.tryParse('${cctp['forwardFee6']}') ?? BigInt.zero;
    final destination = '${cctp['depositAddress']}';
    final label = '${cctp['label']}';
    final sentUsd = amount6.toDouble() / 1e6;
    final signedAt = op.funding?.hlNonce == null
        ? op.createdAt
        : DateTime.fromMillisecondsSinceEpoch(op.funding!.hlNonce!);

    // Arbitrum mint: a step signal and the deposit's best key.
    var mintTx = cctp['mintTx'] as String?;
    final fromBlock = cctp['fromBlock'];
    if (mintTx == null && fromBlock is int && isEvmAddress(destination)) {
      try {
        final mints = await reads.arbitrumUsdcMints(destination, fromBlock);
        final mint = matchCctpMint(
            mints: mints,
            amount6: amount6,
            maxFee6: fee6,
            claimed: await _claimed(store, op, 'mintTx'));
        if (mint != null) {
          mintTx = mint.txHash;
          await _patchCctp(store, op.operationId, {'mintTx': mint.txHash});
          await _step(store, op.operationId, 'arbitrum_minted', sentUsd);
        }
      } catch (_) {
        // Never read a failed RPC as "not arrived".
      }
    }

    final record = await orchestra.record(op.walletId, label);
    if (record == null) return;
    var current = await store.get(op.operationId) ?? op;
    final depositId = _cctp(current)['depositId'] as String?;
    Map<String, dynamic>? deposit;
    try {
      final deposits = await orchestra.deposits(
          record, () => wallet.spendingWalletId() == op.walletId);
      if (depositId != null) {
        deposit = deposits.where((d) => d['id'] == depositId).firstOrNull;
      } else {
        deposit = matchCctpDeposit(
            deposits: deposits,
            amount6: amount6,
            maxFee6: fee6,
            sentAt: signedAt,
            mintTxHash: mintTx,
            claimed: await _claimed(store, current, 'depositId'));
        if (deposit != null) {
          await _patchCctp(
              store, op.operationId, {'depositId': deposit['id'] as String});
          await _step(store, op.operationId, 'orchestra_detected', sentUsd);
        }
      }
    } catch (_) {
      return; // The listing is unreachable: nothing changes.
    }
    current = await store.get(op.operationId) ?? current;

    if (deposit == null) {
      final fundedAt = current.firstEnteredAt(SettlementStage.funded) ??
          current.updatedAt;
      if (current.stage == SettlementStage.funded &&
          _clock().difference(fundedAt) > kCctpAttentionAfter) {
        await _move(store, current, SettlementStage.needsAttention);
        TrackingService.settlementNeedsAttention(current.route.label);
      }
      return;
    }

    final orderId = deposit['orderId'];
    final spark = current.recipient?.address ?? '';
    if (orderId is String && orderId.startsWith('ord_')) {
      final order = await orchestra.order(orderId);
      final status = order?.status ?? '${deposit['status']}';
      final evmRecipient = record.chain != 'spark';
      if (order != null &&
          (order.id != orderId ||
              (order.recipientAddress != null &&
                  !(evmRecipient
                      ? sameEvmAddress(order.recipientAddress!, spark)
                      : sameSparkAddress(order.recipientAddress!, spark))))) {
        return; // Not this wallet's dollars: never adopt it.
      }
      if (current.orderId == null) {
        await store.update(current.operationId,
            stage: current.stage,
            patch: (c) => c.copyWith(orderId: orderId));
      }
      final existing = rows.find(orderId);
      final row = standingOrderRow(
        record: record,
        orderId: orderId,
        chain: 'arbitrum',
        asset: 'USDC',
        depositAddress: destination,
        amountIn: order?.amountIn ?? '${deposit['amount']}',
        amountOut: order?.amountOut ?? '0',
        status: orchestraExchangeStatus(status),
        timestamp: existing?.timestamp ??
            rows.find(rowIdFor(current.operationId))?.timestamp ??
            current.createdAt.millisecondsSinceEpoch,
        recipient: spark,
        walletId: current.walletId,
        operationId: current.operationId,
      );
      if (existing == null || existing.operationId == null) {
        await rows.put(row);
        orchestra.logPending(row);
      }
      await rows.remove(rowIdFor(current.operationId));
      _settleRegistration(current.operationId, orderId);
      final stage = settlementStageForProviderStatus(status);
      if (stage != null) {
        current = await store.get(current.operationId) ?? current;
        await _moveToProviderStage(store, current, stage, orderId);
      }
      return;
    }

    // A deposit with no order: still converting, or held.
    final stuck = stuckStandingDepositStatus(deposit);
    if (stuck != null) {
      final stuckRow = stuckStandingDepositRow(
          deposit: deposit,
          record: record,
          walletId: current.walletId,
          recipient: spark,
          existing: rows.find(stuckStandingDepositRowId(deposit) ?? ''));
      if (stuckRow != null) {
        final prior = rows.find(stuckRow.id);
        if (prior == null || prior.status != stuckRow.status) {
          await rows.put(stuckRow.copyWith(operationId: current.operationId));
        }
        await rows.remove(rowIdFor(current.operationId));
      }
      if (deposit['refundTxId'] != null &&
          current.stage != SettlementStage.refunded) {
        await _moveToProviderStage(
            store, current, SettlementStage.refunded, null);
      } else if (current.stage != SettlementStage.needsAttention) {
        await _move(store, current, SettlementStage.needsAttention);
        TrackingService.settlementNeedsAttention(current.route.label);
      }
      return;
    }
    if (current.stage == SettlementStage.funded ||
        current.stage == SettlementStage.needsAttention) {
      await _move(store, current, SettlementStage.processing);
    }
  }

  Future<void> _moveToProviderStage(SettlementStore store,
      SettlementOperation op, SettlementStage target, String? orderId) async {
    if (op.stage == target) return;
    // The store's stage graph refuses anything a provider status cannot
    // move this operation to (never backwards).
    final write = await store.transition(op.operationId, target,
        from: op.stage, expectedVersion: op.version);
    if (!write.applied) return;
    if (target.isTerminal || target == SettlementStage.failed) {
      _reportTerminal(write.operation!, target, orderId);
    }
  }

  void _reportTerminal(
      SettlementOperation op, SettlementStage stage, String? orderId) {
    final ok = stage == SettlementStage.settled;
    if (!claimOrderTerminalAnalytics('settlement_op:${op.operationId}',
        success: ok)) {
      return;
    }
    final usd = op.amountIn.toDouble() / 1e8;
    final destination = cctpAnalyticsDestination(cctpDestinationOf(op.flow));
    TrackingService.settlementTerminal(
      route: op.route.label,
      outcome: stage.name,
      duration: _clock().difference(op.createdAt),
      flow: op.flow.code,
      walletKind: 'hot',
      amountUsd: usd,
    );
    if (ok) {
      TrackingService.hyperliquidWithdrawCompleted(
          amountUsd: usd,
          destination: destination,
          walletKind: 'hot',
          route: 'cctp',
          orderId: orderId);
    } else {
      TrackingService.hyperliquidWithdrawFailed(
          reason: stage.name,
          amountUsd: usd,
          destination: destination,
          walletKind: 'hot',
          route: 'cctp');
    }
  }

  Future<void> _move(SettlementStore store, SettlementOperation op,
      SettlementStage to) async {
    await store.transition(op.operationId, to,
        from: op.stage, expectedVersion: op.version);
  }

  Future<void> _touch(SettlementStore store, SettlementOperation op) =>
      store.update(op.operationId,
          stage: op.stage,
          patch: (c) => c.copyWith(
              poll: SettlementPollState(
                  providerStatus: c.poll.providerStatus,
                  mappedStatus: c.poll.mappedStatus,
                  lastCheckedAt: _clock(),
                  consecutiveFailures: c.poll.consecutiveFailures)));

  Future<Set<String>> _claimed(
      SettlementStore store, SettlementOperation op, String key) async {
    final out = <String>{};
    for (final other in await store.all()) {
      if (other.operationId == op.operationId || !other.flow.isInvestingCctp) {
        continue;
      }
      final value = _cctp(other)[key];
      if (value is String) out.add(key == 'mintTx' ? value.toLowerCase() : value);
    }
    return out;
  }

  Future<void> _patchCctp(SettlementStore store, String operationId,
      Map<String, Object> values) async {
    final op = await store.get(operationId);
    if (op == null) return;
    await store.update(operationId,
        stage: op.stage,
        patch: (c) => c.copyWith(raw: {
              ...c.raw,
              'cctp': {..._cctp(c), ...values},
            }));
  }

  /// Fires [step] once per operation.
  Future<void> _step(SettlementStore store, String operationId, String step,
      double usd) async {
    final op = await store.get(operationId);
    if (op == null) return;
    final steps = [...(_cctp(op)['steps'] as List? ?? const [])];
    if (steps.contains(step)) return;
    await _patchCctp(store, operationId, {'steps': [...steps, step]});
    final nonce = op.funding?.hlNonce;
    final from = nonce == null
        ? op.createdAt
        : DateTime.fromMillisecondsSinceEpoch(nonce);
    TrackingService.hyperliquidWithdrawStep(
      step: step,
      durationMs: _clock().difference(from).inMilliseconds.clamp(0, 1 << 31),
      amountUsd: usd,
    );
  }

  Future<void> _markFunded(SettlementStore store, String operationId,
      String ledgerHash, double usd) async {
    final op = await store.get(operationId);
    if (op == null ||
        !const {
          SettlementStage.broadcasting,
          SettlementStage.fundingUnknown,
          SettlementStage.notFunded,
        }.contains(op.stage)) {
      return;
    }
    final write = await store.transition(operationId, SettlementStage.funded,
        from: op.stage,
        expectedVersion: op.version,
        patch: (c) => c.copyWith(
            funding: (c.funding ??
                    const SettlementFunding(
                        kind: SettlementFundingKind.hyperliquid))
                .copyWith(evmTxHash: ledgerHash, hlActionHash: ledgerHash)));
    if (!write.applied) return;
    if (op.stage == SettlementStage.notFunded) {
      // A late ledger row: the row comes back as in flight.
      final rowId = rowIdFor(operationId);
      final row = rows.find(rowId);
      if (row != null) await rows.put(row.copyWith(status: 'exchanging'));
    }
    TrackingService.settlementFundingResolved(
        flow: op.flow.code, outcome: SettlementStage.funded.name);
    await _step(store, operationId, 'core_confirmed', usd);
  }

  Future<void> _markNotFunded(
      SettlementStore store, String operationId, String rowId) async {
    final op = await store.get(operationId);
    if (op == null) return;
    if (op.stage == SettlementStage.broadcasting ||
        op.stage == SettlementStage.fundingUnknown) {
      final write = await store.transition(
          operationId, SettlementStage.notFunded,
          from: op.stage, expectedVersion: op.version);
      if (!write.applied) return;
      TrackingService.settlementFundingResolved(
          flow: op.flow.code, outcome: SettlementStage.notFunded.name);
    }
    final row = rows.find(rowId);
    if (row != null) await rows.put(row.copyWith(status: 'expired'));
  }

  Future<void> _endUnsent(
      SettlementStore store, String operationId, String rowId) async {
    final op = await store.get(operationId);
    if (op != null && op.stage.isBeforeBroadcasting && !op.everBroadcast) {
      await store.transition(operationId, SettlementStage.abandoned,
          from: op.stage, expectedVersion: op.version);
    }
    await rows.remove(rowId);
  }

  SwapOrder _pendingRow({
    required String id,
    required SettlementOperation op,
    required String destination,
    required InvestingWithdrawalDestination target,
    required String spark,
    required String account,
    required BigInt amount6,
    required BigInt fee6,
  }) =>
      SwapOrder(
        id: id,
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: target.asset,
        networkTo: target.chain.toUpperCase(),
        depositAddress: destination,
        depositAmount: (amount6.toDouble() / 1e6).toStringAsFixed(2),
        // Bitcoin's amount is the order's, once there is one.
        withdrawalAmount: target == InvestingWithdrawalDestination.bitcoin
            ? '0'
            : ((amount6 - fee6).toDouble() / 1e6).toStringAsFixed(2),
        status: 'exchanging',
        timestamp: _clock().millisecondsSinceEpoch,
        withdrawalAddress: spark,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: account,
        provider: 'Orchestra',
        walletId: op.walletId,
        operationId: op.operationId,
        routeVersion: hypercoreCctpRouteVersion(target),
      );
}

final hypercoreCctpWithdrawalProvider = Provider<HypercoreCctpWithdrawal>(
    (ref) => HypercoreCctpWithdrawal.live(ref.read));

// ───────────────────────────── live ports ────────────────────────────

class LiveCctpChainReads implements CctpChainReads {
  LiveCctpChainReads({http.Client? client, ArbitrumReadRpc? arbitrum})
      : _client = client,
        _arbitrum = arbitrum ?? ArbitrumReadRpc();

  final http.Client? _client;
  final ArbitrumReadRpc _arbitrum;
  bool _chainVerified = false;

  Future<String> _hyperEvmCall(String method, List<Object> params) async {
    final response = await SharedHttpClient.post(Uri.parse(kHyperEvmRpc),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(
            {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}),
        kind: HttpCallKind.userAction,
        timeout: const Duration(seconds: 10),
        client: _client);
    if (response.statusCode != 200) throw StateError('HyperEVM read failed');
    final json = jsonDecode(response.body);
    final result = json is Map ? json['result'] : null;
    if (json is! Map || json['error'] != null || result is! String ||
        !result.startsWith('0x')) {
      throw StateError('HyperEVM read failed');
    }
    return result;
  }

  Future<String> _call(String data) async {
    if (!_chainVerified) {
      final chain = await _hyperEvmCall('eth_chainId', const []);
      if (int.tryParse(chain.substring(2), radix: 16) != kHyperEvmChainId) {
        throw StateError('Not HyperEVM');
      }
      _chainVerified = true;
    }
    final word = await _hyperEvmCall('eth_call', [
      {'to': kCircleCoreDepositWallet, 'data': data},
      'latest',
    ]);
    if (word.length != 66) throw StateError('Unexpected CoreDepositWallet answer');
    return word;
  }

  /// `paused()` (selector 0x5c975abb).
  @override
  Future<bool> coreDepositWalletPaused() async {
    final word = BigInt.parse((await _call('0x5c975abb')).substring(2),
        radix: 16);
    if (word > BigInt.one) throw StateError('Unexpected paused() answer');
    return word == BigInt.one;
  }

  /// `calculateCrossChainWithdrawalFee(bool,uint32)` (selector
  /// 0xe26f7d23) with forwarding on.
  @override
  Future<BigInt> forwardingFee(int domain) async {
    final data = '0xe26f7d23'
        '${'1'.padLeft(64, '0')}'
        '${domain.toRadixString(16).padLeft(64, '0')}';
    return BigInt.parse((await _call(data)).substring(2), radix: 16);
  }

  @override
  Future<int> arbitrumBlock() => _arbitrum.blockNumber();

  @override
  Future<List<ArbitrumTokenMint>> arbitrumUsdcMints(String to, int fromBlock) =>
      _arbitrum.mintsTo(
          token: ArbitrumReadRpc.usdcAddress, to: to, fromBlock: fromBlock);

  @override
  Future<String?> ledgerSendHash(
      {required String source,
      required BigInt amount8,
      required int nonce}) async {
    final response = await SharedHttpClient.post(HyperliquidConstants.infoUri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'type': 'userNonFundingLedgerUpdates',
          'user': source,
          // Block time can trail the signing clock.
          'startTime': nonce - 120000,
        }),
        kind: HttpCallKind.userAction,
        timeout: const Duration(seconds: 12),
        client: _client);
    if (response.statusCode != 200) throw StateError('Ledger unavailable');
    final data = jsonDecode(response.body);
    if (data is! List) throw const FormatException('Invalid ledger');
    return matchHypercoreCctpSend(
        updates: data, source: source, amount8: amount8, nonce: nonce);
  }
}

/// The hot Investing account's send, with the same session, wallet and
/// cash rules as the normal route's usdSend (HypercoreHotSourceSendNative).
class LiveCctpSender implements CctpSender {
  LiveCctpSender(this._read);
  final ProviderReader _read;

  @override
  Future<BigInt> sendableBaseUnits(String account) async {
    final snapshot = await HyperliquidModel()
        .getPortfolioSnapshot(account)
        .timeout(const Duration(seconds: 10));
    return hypercoreBalanceBaseUnits(
        hypercoreSendableUsdc(snapshot.withdrawable, snapshot.spotBalances));
  }

  @override
  Future<int> send({
    required String walletId,
    required String account,
    required String destination,
    required BigInt amount8,
    required int domain,
    required String token,
    required Future<void> Function(int nonce) onBeforePost,
  }) async {
    var externalPostStarted = false;
    try {
      if (!isEvmAddress(destination) || sameEvmAddress(account, destination)) {
        throw ArgumentError('Invalid CCTP destination');
      }
      final amountWire = hypercorePerpUsdcWire(amount8);
      await verifyHypercoreUsdcMetadata();
      final wallet = pickSpendingWallet(_read(settingsProvider));
      if (wallet == null || wallet.id != walletId) {
        throw StateError('The spending wallet changed.');
      }
      final session = _read(seedSessionProvider);
      final authSession = _read(sessionAuthProvider);
      if (!session.unlocked || authSession == null) {
        throw const SeedLockedException();
      }
      final mnemonic = await resolveBip39MnemonicFor(wallet,
          access: SeedAccess.automatic, session: session);
      if (mnemonic == null ||
          pickSpendingWallet(_read(settingsProvider))?.id != wallet.id) {
        throw StateError('The spending wallet changed.');
      }
      final hl = await HyperliquidOnboardingService.provisionHyperliquidAccount(
          mnemonic: mnemonic,
          walletId: wallet.id,
          evmDerivationVersion: wallet.evmDerivationVersion);
      if (!sameEvmAddress(hl.address, account)) {
        throw StateError('The Investing account changed.');
      }
      void ensureWallet() {
        if (!_read(seedSessionProvider).unlocked ||
            !identical(_read(sessionAuthProvider), authSession) ||
            pickSpendingWallet(_read(settingsProvider))?.id != wallet.id) {
          throw const SeedLockedException();
        }
      }

      // The burn leaves perpetuals; HyperCore's gas comes on top.
      final reserve = amount8 + kCctpCoreFeeReserve;
      final model = HyperliquidModel();
      Future<BigInt> perpShortfall() async {
        final snapshot = await model.getAccountSnapshot(hl.address);
        ensureWallet();
        return hypercorePerpShortfall(
          requiredBaseUnits: reserve,
          spotAvailable: hypercoreAvailableUsdc(0, snapshot.spotBalances),
          perpAvailable: snapshot.withdrawable,
        );
      }

      final portfolio = await model.getPortfolioSnapshot(hl.address);
      ensureWallet();
      final spotMove = hypercorePerpShortfall(
          requiredBaseUnits: reserve,
          spotAvailable: hypercoreAvailableUsdc(0, portfolio.spotBalances),
          perpAvailable: portfolio.withdrawable);
      final requiredDefault = reserve - spotMove;
      final exchange = HyperliquidExchangeService(
        credentials: hl.credentials,
        walletAddress: hl.address,
        allowNonceRetry: false,
        onBeforePost: (post) async {
          ensureWallet();
          if (post.action['type'] == 'sendToEvmWithData') {
            if (await perpShortfall() > BigInt.zero) {
              throw HypercoreBalanceShortfall(
                  'Insufficient available perpetuals balance.');
            }
            await onBeforePost(post.nonce);
            ensureWallet();
          }
        },
      );
      try {
        await collectOwnDexCash(
            model: model,
            exchange: exchange,
            requiredDefaultUsd: requiredDefault.toDouble() / 1e8,
            beforeSend: ensureWallet);
        final move = await perpShortfall();
        if (move > BigInt.zero) {
          await exchange.usdClassTransfer(
            amount: move.toDouble() / 1e8,
            toPerp: true,
            beforeSend: ensureWallet,
          );
        }
      } on HyperliquidRejectedException catch (e) {
        throw SettlementFundingRefused(e);
      }
      return await exchange.sendToEvmWithData(
        destination: destination,
        amount: amountWire,
        sourceDex: '',
        destinationDomain: domain,
        gasLimit: kCctpForwardGasLimit,
        token: token,
        beforeSend: () {
          ensureWallet();
          externalPostStarted = true;
        },
      );
    } on HyperliquidRejectedException catch (e) {
      // A rejection answer: the action was not executed.
      if (externalPostStarted) throw CctpSendRejected(e);
      throw SettlementFundingRefused(e);
    } catch (error) {
      // Anything before the burn's POST left nothing in flight: an
      // internal same-account move, even an uncertain one, never funds
      // the burn.
      if (!externalPostStarted) throw SettlementFundingRefused(error);
      rethrow;
    }
  }
}

class LiveCctpOrchestraPort implements CctpOrchestraPort {
  const LiveCctpOrchestraPort();

  @override
  Future<StandingDepositRecord> instruction({
    required String walletId,
    required String recipient,
    required String refundAddress,
    required bool Function() wanted,
    InvestingWithdrawalDestination destination =
        InvestingWithdrawalDestination.dollars,
  }) =>
      StandingDepositStore.investingWithdrawalInstruction(
          walletId: walletId,
          recipient: recipient,
          refundAddress: refundAddress,
          wanted: wanted,
          destination: destination);

  @override
  Future<StandingDepositRecord?> record(String walletId, String label) async =>
      (await StandingDepositStore.records(walletId))
          .where((r) => r.label == label)
          .firstOrNull;

  @override
  Future<List<Map<String, dynamic>>> deposits(
          StandingDepositRecord record, bool Function() current) =>
      StandingDepositStore.deposits(record, current);

  @override
  Future<OrchestraOrder?> order(String orderId) async {
    try {
      return (await OrchestraService.getStatus(orderId)).data;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<double?> minimumUsd(
      {InvestingWithdrawalDestination destination =
          InvestingWithdrawalDestination.dollars}) async {
    final limits = await OrchestraService.getRouteLimits(
            destination == InvestingWithdrawalDestination.dollars
                ? kArbitrumUsdcToDollarsRoute
                : RouteKey(
                    fromChain: 'arbitrum',
                    fromAsset: 'USDC',
                    toChain: destination.chain,
                    toAsset: destination.asset))
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    final cents = limits?.exactInMinUsdCents ?? limits?.orderMinUsdCents;
    return cents == null ? null : cents / 100;
  }

  @override
  void logPending(SwapOrder row) {
    if (!row.id.startsWith('ord_')) return;
    // ignore: unawaited_futures
    AffiliateService.logProviderEvent(
      provider: 'orchestra',
      providerOrderId: row.id,
      status: 'pending',
      sourceAsset: 'USDC',
      sourceAmount: double.tryParse(row.depositAmount),
      destinationAsset: row.coinTo,
      destinationAmount: double.tryParse(row.withdrawalAmount),
    );
  }
}

class RiverpodCctpActivityRows implements CctpActivityRows {
  RiverpodCctpActivityRows(this._read);
  final ProviderReader _read;

  @override
  SwapOrder? find(String id) =>
      _read(swapOrdersProvider).where((r) => r.id == id).firstOrNull;

  @override
  Future<void> put(SwapOrder row) async {
    final notifier = _read(swapOrdersProvider.notifier);
    if (find(row.id) == null) {
      await notifier.addExchange(row);
    } else {
      await notifier.updateExchange(row);
    }
    _read(walletTransactionCacheProvider.notifier).mergeSwapOrder(row);
  }

  @override
  Future<void> remove(String id) async {
    if (find(id) == null) return;
    await _read(swapOrdersProvider.notifier).deleteExchange(id);
    _read(walletTransactionCacheProvider.notifier).removeSwapOrder(id);
  }
}

class RiverpodCctpWalletContext implements CctpWalletContext {
  RiverpodCctpWalletContext(this._read);
  final ProviderReader _read;

  @override
  String spendingWalletId() => HotSettlement.spendingWalletId(_read);

  @override
  void ensureSpending(String walletId) {
    if (HotSettlement.spendingWalletId(_read) != walletId) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet');
    }
  }

  @override
  Future<String> investingAddress() async {
    final String? address = await _read(hyperliquidAddressProvider.future);
    return address ?? '';
  }

  @override
  Future<String> sparkAddress() async {
    final String? address = await _read(sparkSelfAddressProvider.future);
    return address ?? '';
  }

  @override
  Future<String> predictionsAddress() async {
    final live =
        _read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
    if (live != null && live.isNotEmpty) return live;
    return await _read(polymarketTradingProvider.notifier).depositAddress() ??
        '';
  }
}

@visibleForTesting
SettlementStage? cctpStageForProviderStatus(String status) =>
    settlementStageForProviderStatus(status);
