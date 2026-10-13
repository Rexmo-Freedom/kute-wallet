// lib/models/settlement_operation.dart
//
// The write-ahead record of one Orchestra settlement operation (Phase 5
// plan B6). It is also Phase 4's funding route record (F22). Persisted as
// a map through lib/services/funding/settlement_codec.dart in the
// `settlement_operations` Hive box; lib/services/funding/settlement_store.dart
// owns every write. Holds public addresses, quote ids and txids, never
// secrets or signed transactions (F5).

import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/services/funding/settlement_stage.dart';

/// The record schema this build writes.
const int kSettlementSchemaVersion = 1;

/// Which account funds or receives an operation.
enum SettlementAccountKind {
  sparkHot,
  ledgerBtc,
  hlHot,
  hlLedger,
  pmHot,
  pmLedger,

  /// Written by a newer build. Kept raw on disk.
  unknown;

  bool get isLedger =>
      this == SettlementAccountKind.ledgerBtc ||
      this == SettlementAccountKind.hlLedger ||
      this == SettlementAccountKind.pmLedger;

  static SettlementAccountKind fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return SettlementAccountKind.unknown;
  }
}

/// The call site that started an operation.
enum SettlementFlow {
  moveUsdToBtc,
  moveBtcToPredictions,
  moveBtcToInvesting,
  moveInvestingToBtc,
  moveBtcToUsdc,
  sendExternal,
  predictionsDeposit,
  predictionsWithdraw,
  predictionsBtcRoute,
  ledgerBtcToInvesting,
  investingToLedgerBtc,
  ledgerBtcToPredictions,
  predictionsToLedgerBtc,
  sparkToInvestingDirect,
  investingToSparkDirect,

  /// The spending account's DOLLAR balance funding a venue, as opposed to
  /// its bitcoin. Separate values because the funding asset decides the
  /// unit the amount is in, and a flow name is what an operation is
  /// reconciled and reported by.
  moveUsdToPredictions,
  moveUsdToInvesting,

  /// The two venue cash-outs pointed at the spending account's DOLLAR
  /// balance instead of its bitcoin. Same source and same funding unit as
  /// [moveUsdToBtc] / [investingToSparkDirect]; separate values because
  /// the delivered asset is what the operation is reconciled and reported
  /// by, and a withdrawal named "…ToBtc" that landed in dollars would
  /// read as the wrong money everywhere it is logged.
  movePredictionsToDollars,
  investingToSparkUsdDirect,

  /// The spending account's DOLLAR balance buying spending BITCOIN.
  /// Distinct from [moveUsdToBtc], which is the Predictions cash-out
  /// (Polygon USDC.e → Spark BTC): different source account, different
  /// funding unit, so it must reconcile and report under its own name.
  moveDollarsToBtc,

  /// Written by a newer build. Kept raw on disk.
  unknown;

  /// Snake case analytics value.
  String get code => name.replaceAllMapped(
      RegExp('[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

  static SettlementFlow fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return SettlementFlow.unknown;
  }
}

/// Where an owned address came from (B4).
enum OwnedAddressKind {
  sparkSelf,
  hyperliquidEoa,
  polymarketDepositWallet,
  ledgerBitcoinReceive,
  ledgerEvm,

  /// A recipient the user typed or scanned (Send). Not owned.
  external,

  /// Written by a newer build. Kept raw on disk.
  unknown;

  static OwnedAddressKind fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return OwnedAddressKind.unknown;
  }
}

/// A recipient or refund address resolved from the wallet, never from a
/// backend response.
class SettlementAddressRef {
  const SettlementAddressRef({
    required this.address,
    required this.kind,
    this.index,
    this.deviceVerifiedAt,
  });

  final String address;
  final OwnedAddressKind kind;

  /// Derivation index for derived addresses.
  final int? index;

  /// When a hardware device showed and the user confirmed the address.
  final DateTime? deviceVerifiedAt;
}

/// The validated quote an operation is bound to.
class SettlementQuoteTerms {
  const SettlementQuoteTerms({
    required this.quoteId,
    required this.depositAddress,
    required this.amountIn,
    required this.estimatedOut,
    required this.feeBps,
    required this.expiresAt,
    this.skew = Duration.zero,
    this.lockedMinAmountOut,
    this.totalFeeAmount,
    this.feeAsset,
    this.priceLockMode,
    this.readToken,
  });

  final String quoteId;
  final String depositAddress;

  /// Smallest units, exactly as quoted.
  final String amountIn;
  final String estimatedOut;
  final int feeBps;

  /// The verified expiry (already capped by the Phase 2 guard).
  final DateTime expiresAt;

  /// Server clock minus local clock when the quote arrived.
  final Duration skew;
  final String? lockedMinAmountOut;
  final String? totalFeeAmount;
  final String? feeAsset;
  final String? priceLockMode;
  final String? readToken;
}

/// A quote that was replaced before any funds moved.
class SettlementQuoteHistoryEntry {
  const SettlementQuoteHistoryEntry({
    required this.quoteId,
    required this.reason,
    required this.supersededAt,
  });

  final String quoteId;
  final String reason;
  final DateTime supersededAt;
}

/// Idempotency keys (B7). [submit] is created with the funding proof.
class SettlementKeys {
  const SettlementKeys({
    this.quote,
    this.submit,
    this.submitHistory = const [],
    this.submitFingerprint,
  });

  final String? quote;
  final String? submit;
  final List<String> submitHistory;
  final String? submitFingerprint;
}

class SettlementStageEntry {
  const SettlementStageEntry(this.stage, this.at);

  final SettlementStage stage;
  final DateTime at;
}

/// Proof that funds left the source account.
class SettlementFunding {
  const SettlementFunding({
    this.kind,
    this.sparkPaymentId,
    this.btcTxid,
    this.btcVout,
    this.btcInputs = const [],
    this.evmTxHash,
    this.relayerTxId,
    this.hlNonce,
    this.hlActionHash,
  });

  /// Null only for a kind written by a newer build.
  final SettlementFundingKind? kind;
  final String? sparkPaymentId;
  final String? btcTxid;
  final int? btcVout;

  /// Outpoints `txid:vout` the funding transaction spends.
  final List<String> btcInputs;
  final String? evmTxHash;
  final String? relayerTxId;
  final int? hlNonce;
  final String? hlActionHash;

  bool get hasProof => kind == SettlementFundingKind.hyperliquid
      // A signed nonce locates an uncertain send; only its confirmed hash is
      // provider submission proof. Keep these separate across process exits.
      ? (evmTxHash?.isNotEmpty ?? false)
      : sparkPaymentId != null ||
          btcTxid != null ||
          evmTxHash != null ||
          relayerTxId != null;

  SettlementFunding copyWith({
    SettlementFundingKind? kind,
    String? sparkPaymentId,
    String? btcTxid,
    int? btcVout,
    List<String>? btcInputs,
    String? evmTxHash,
    String? relayerTxId,
    int? hlNonce,
    String? hlActionHash,
  }) =>
      SettlementFunding(
        kind: kind ?? this.kind,
        sparkPaymentId: sparkPaymentId ?? this.sparkPaymentId,
        btcTxid: btcTxid ?? this.btcTxid,
        btcVout: btcVout ?? this.btcVout,
        btcInputs: btcInputs ?? this.btcInputs,
        evmTxHash: evmTxHash ?? this.evmTxHash,
        relayerTxId: relayerTxId ?? this.relayerTxId,
        hlNonce: hlNonce ?? this.hlNonce,
        hlActionHash: hlActionHash ?? this.hlActionHash,
      );
}

class SettlementSubmitState {
  const SettlementSubmitState({
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastErrorCode,
    this.acceptedAt,
    this.providerDetected = false,
  });

  final int attempts;
  final DateTime? lastAttemptAt;

  /// HTTP status or provider code, never a message body.
  final String? lastErrorCode;
  final DateTime? acceptedAt;
  final bool providerDetected;
}

class SettlementPollState {
  const SettlementPollState({
    this.providerStatus,
    this.mappedStatus,
    this.lastCheckedAt,
    this.consecutiveFailures = 0,
    this.nextCheckAt,
    this.sdkSyncsSinceBroadcasting = 0,
    this.lastSdkSyncGeneration,
  });

  final String? providerStatus;
  final String? mappedStatus;
  final DateTime? lastCheckedAt;
  final int consecutiveFailures;
  final DateTime? nextCheckAt;
  final int sdkSyncsSinceBroadcasting;
  final int? lastSdkSyncGeneration;
}

class SettlementLate {
  const SettlementLate(
      {required this.quoteExpiredBeforeFunding, this.detectedAt});

  final bool quoteExpiredBeforeFunding;
  final DateTime? detectedAt;
}

class SettlementRefundObserved {
  const SettlementRefundObserved({this.at, this.txRef});

  final DateTime? at;
  final String? txRef;
}

class SettlementOperation {
  const SettlementOperation({
    this.schema = kSettlementSchemaVersion,
    required this.operationId,
    required this.walletId,
    required this.accountKind,
    required this.flow,
    this.routeVersion,
    required this.route,
    required this.amountInBaseUnits,
    this.quote,
    this.quoteHistory = const [],
    this.recipient,
    this.refund,
    this.keys = const SettlementKeys(),
    required this.stage,
    this.stageHistory = const [],
    this.funding,
    this.orderId,
    this.submit = const SettlementSubmitState(),
    this.poll = const SettlementPollState(),
    this.late,
    this.refundObserved,
    this.recoveredFrom,
    required this.createdAt,
    required this.updatedAt,
    this.terminalAt,
    this.version = 0,
    this.raw = const {},
  });

  /// The schema the record was read at. A record from a newer build keeps
  /// its number on write.
  final int schema;

  /// UUID v4 created before the first quote.
  final String operationId;
  final String walletId;

  /// The source account.
  final SettlementAccountKind accountKind;
  final SettlementFlow flow;
  final String? routeVersion;
  final RouteKey route;

  /// Exact-in amount in the source asset's smallest unit, kept verbatim.
  final String amountInBaseUnits;
  final SettlementQuoteTerms? quote;
  final List<SettlementQuoteHistoryEntry> quoteHistory;
  final SettlementAddressRef? recipient;
  final SettlementAddressRef? refund;
  final SettlementKeys keys;
  final SettlementStage stage;
  final List<SettlementStageEntry> stageHistory;
  final SettlementFunding? funding;
  final String? orderId;
  final SettlementSubmitState submit;
  final SettlementPollState poll;
  final SettlementLate? late;
  final SettlementRefundObserved? refundObserved;

  /// `backend` or `history` for operations rebuilt after device loss.
  final String? recoveredFrom;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? terminalAt;

  /// Incremented by every store write; the compare-and-set token.
  final int version;

  /// The decoded map this record was read from. The codec writes known
  /// fields over it, so fields from a newer build survive.
  final Map<String, Object?> raw;

  BigInt get amountIn => BigInt.parse(amountInBaseUnits);

  /// Whether funds may ever have moved: the history holds a stage at or
  /// after `broadcasting` (including `notFunded`). Such a record is never
  /// deleted (I4) and never quoted again (I2).
  bool get everBroadcast {
    bool moved(SettlementStage s) =>
        !s.isBeforeBroadcasting && s != SettlementStage.abandoned;
    return moved(stage) || stageHistory.any((e) => moved(e.stage));
  }

  DateTime? firstEnteredAt(SettlementStage target) {
    for (final entry in stageHistory) {
      if (entry.stage == target) return entry.at;
    }
    return null;
  }

  /// When the current stage was entered.
  DateTime? get stageEnteredAt {
    for (final entry in stageHistory.reversed) {
      if (entry.stage == stage) return entry.at;
    }
    return null;
  }

  SettlementOperation copyWith({
    int? schema,
    String? routeVersion,
    String? amountInBaseUnits,
    SettlementQuoteTerms? quote,
    List<SettlementQuoteHistoryEntry>? quoteHistory,
    SettlementAddressRef? recipient,
    SettlementAddressRef? refund,
    SettlementKeys? keys,
    SettlementStage? stage,
    List<SettlementStageEntry>? stageHistory,
    SettlementFunding? funding,
    String? orderId,
    SettlementSubmitState? submit,
    SettlementPollState? poll,
    SettlementLate? late,
    SettlementRefundObserved? refundObserved,
    String? recoveredFrom,
    DateTime? updatedAt,
    DateTime? terminalAt,
    int? version,
    Map<String, Object?>? raw,
  }) =>
      SettlementOperation(
        schema: schema ?? this.schema,
        operationId: operationId,
        walletId: walletId,
        accountKind: accountKind,
        flow: flow,
        routeVersion: routeVersion ?? this.routeVersion,
        route: route,
        amountInBaseUnits: amountInBaseUnits ?? this.amountInBaseUnits,
        quote: quote ?? this.quote,
        quoteHistory: quoteHistory ?? this.quoteHistory,
        recipient: recipient ?? this.recipient,
        refund: refund ?? this.refund,
        keys: keys ?? this.keys,
        stage: stage ?? this.stage,
        stageHistory: stageHistory ?? this.stageHistory,
        funding: funding ?? this.funding,
        orderId: orderId ?? this.orderId,
        submit: submit ?? this.submit,
        poll: poll ?? this.poll,
        late: late ?? this.late,
        refundObserved: refundObserved ?? this.refundObserved,
        recoveredFrom: recoveredFrom ?? this.recoveredFrom,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        terminalAt: terminalAt ?? this.terminalAt,
        version: version ?? this.version,
        raw: raw ?? this.raw,
      );
}
