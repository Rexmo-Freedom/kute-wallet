// lib/models/transactions_model.dart

import 'package:kute/helpers/prediction_results.dart' show PredictionResult;
import 'package:kute/models/datetime_range_model.dart';
import 'package:kute/models/outlogic_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/polymarket_model.dart' show Activity, ActivityType;
import 'package:kute/services/mempool_address_service.dart' as mempool;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/models/onchain_types.dart' as bdk;
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;

enum TransactionType { received, sent }

enum SparkTransactionType {
  bitcoin,   // On-chain Deposit or Withdrawal
  lightning, // Standard Lightning Network payment
  spark      // Internal Spark transfer
}

abstract class BaseTransaction {
  final String id;
  final DateTime timestamp;
  final bool isConfirmed;

  BaseTransaction({
    required this.id,
    required this.timestamp,
    required this.isConfirmed,
  });

  TransactionType get type;
  num get amount;
  String get asset;

  // Value-equality so identical-content sync ticks don't trigger
  // a Riverpod notification cascade through every Transaction
  // consumer. Two rows are "the same" when their identity (id +
  // type, since the same id can in theory show on both sides of
  // a self-spend) plus the user-visible state (timestamp,
  // isConfirmed, amount, asset) all match. The wrapped SDK
  // payload (`btcDetails` on BitcoinTransaction, `details` on
  // SparkTransaction, etc.) is intentionally NOT compared here —
  // those types have FFI-handle equality which would never match
  // across syncs anyway, and the user-visible fields are derived
  // from them.
  /// Subclass equality helper. Subclasses that need to extend the
  /// base equality with type-specific fields (e.g. swap order status,
  /// Outlogic status) call this from their own `==` override and
  /// then chain on the extra fields. Skips the strict runtimeType
  /// match so a subclass that's already validated `other is FooTx`
  /// can compare without re-checking.
  bool maybeBaseEquals(BaseTransaction other) {
    return id == other.id &&
        timestamp == other.timestamp &&
        isConfirmed == other.isConfirmed &&
        amount == other.amount &&
        asset == other.asset &&
        type == other.type;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BaseTransaction) return false;
    if (runtimeType != other.runtimeType) return false;
    return maybeBaseEquals(other);
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, id, timestamp, isConfirmed, amount, asset, type);
}

class BitcoinTransaction extends BaseTransaction {
  /// Native wallet snapshot details, populated by sync.
  /// Null on instances reconstructed
  /// from the Hive cache via [BitcoinTransaction.fromCache] —
  /// callers that need fields beyond received/sent (chain position,
  /// confirmation block, raw fee, etc.) must null-check and fall
  /// back to a placeholder until the next sync replaces the cached
  /// shell with a live one.
  final bdk.TxDetails? btcDetails;

  BitcoinTransaction({
    required super.id,
    required super.timestamp,
    required super.isConfirmed,
    required this.btcDetails,
  })  : _cachedReceivedSats = null,
        _cachedSentSats = null;

  /// Hive-cache reconstruction. The existing cache schema stores only
  /// received/sent in sats, so we preserve it and rebuild a
  /// BitcoinTransaction whose getters read those primitives. UI
  /// detail screens that dereference `btcDetails` for chain
  /// position / fee / etc. will get null and skip those fields
  /// gracefully — within the next sync the live BitcoinTransaction
  /// replaces this shell with a full one.
  BitcoinTransaction.fromCache({
    required super.id,
    required super.timestamp,
    required super.isConfirmed,
    required int receivedSats,
    required int sentSats,
  })  : btcDetails = null,
        _cachedReceivedSats = receivedSats,
        _cachedSentSats = sentSats;

  /// Cached primitives populated by [BitcoinTransaction.fromCache].
  /// Null on a live (sync-built) instance.
  final int? _cachedReceivedSats;
  final int? _cachedSentSats;

  /// Convenience accessor that returns the received-sats value
  /// regardless of whether this is a live or cached instance.
  /// Detail screens that dereference `btcDetails.received` directly
  /// must null-check; they should fall back to this getter.
  int get receivedSats =>
      _cachedReceivedSats ?? btcDetails?.received.toSat() ?? 0;
  int get sentSats => _cachedSentSats ?? btcDetails?.sent.toSat() ?? 0;

  @override
  TransactionType get type =>
      receivedSats > sentSats ? TransactionType.received : TransactionType.sent;
  @override
  num get amount => (receivedSats - sentSats).abs();
  @override
  String get asset => 'btc';
}

class SparkTransaction extends BaseTransaction {
  /// Live SDK payload. Nullable because Spark / USDB / unclaimed
  /// rows are persisted to Hive as primitive shells (see
  /// [SparkTransaction.fromCache] + `TransactionCacheCodec`) so the
  /// home Activity feed renders pre-sync at cold start. Sites that
  /// dereference SDK-specific fields (raw routing data, fees, etc.)
  /// must null-check first; the user-visible row only needs the
  /// cached primitives below.
  final breez.Payment? details;

  // Cached primitives populated by [SparkTransaction.fromCache] so
  // a Hive-hydrated entry can render its row without the SDK
  // payload. Live entries leave these null and read through to
  // `details`.
  final int? _cachedAmountSats;
  final SparkTransactionType? _cachedSparkType;
  final TransactionType? _cachedDirection;
  final bool? _cachedPending;
  final String? _cachedOnChainTxId;

  SparkTransaction({
    required super.id,
    required super.timestamp,
    required this.details,
    required super.isConfirmed,
  })  : _cachedAmountSats = null,
        _cachedSparkType = null,
        _cachedDirection = null,
        _cachedPending = null,
        _cachedOnChainTxId = null;

  /// Hive-hydrated constructor — primitives only, no SDK payload.
  /// Used by `TransactionCacheCodec.decode` so the cold-start home
  /// Activity feed shows the user's recent Lightning / Spark /
  /// on-chain Spark history before the first live sync replaces
  /// the shells.
  SparkTransaction.fromCache({
    required super.id,
    required super.timestamp,
    required super.isConfirmed,
    required int amountSats,
    required SparkTransactionType sparkType,
    required TransactionType direction,
    required bool pending,
    String? onChainTxId,
  })  : details = null,
        _cachedAmountSats = amountSats,
        _cachedSparkType = sparkType,
        _cachedDirection = direction,
        _cachedPending = pending,
        _cachedOnChainTxId = onChainTxId;

  /// The bitcoin transaction id behind an on-chain deposit or withdrawal.
  /// Live entries read it from the SDK payload; cache-hydrated shells keep
  /// the value the last live sync persisted, so the detail sheet can show
  /// the id and draw the chain graph before the next sync. Null for
  /// Lightning and Spark-to-Spark payments.
  String? get onChainTxId {
    final d = details?.details;
    if (d is breez.PaymentDetails_Deposit) return d.txId;
    if (d is breez.PaymentDetails_Withdraw) return d.txId;
    return _cachedOnChainTxId;
  }

  SparkTransactionType get sparkType {
    final live = details;
    if (live == null) {
      return _cachedSparkType ?? SparkTransactionType.spark;
    }
    switch (live.method) {
      case breez.PaymentMethod.lightning:
        return SparkTransactionType.lightning;

      case breez.PaymentMethod.deposit:
      case breez.PaymentMethod.withdraw:
        return SparkTransactionType.bitcoin;

      case breez.PaymentMethod.spark:
        return SparkTransactionType.spark;

      default:
        return SparkTransactionType.spark;
    }
  }

  /// Sats. Reads from the live payload when present, else from the
  /// cached primitive seeded by `fromCache`.
  int get amountSats =>
      details?.amount.toInt() ?? _cachedAmountSats ?? 0;

  /// Network fee WE paid, in sats. Only known on live entries (the
  /// SDK payload carries `fees`); cache-hydrated shells have no
  /// payload and return 0 (fee genuinely unknown). Receives never
  /// carry an outbound fee here — the SDK nets any inbound fee.
  int get feeSats => details?.fees.toInt() ?? 0;

  /// True when the payment hasn't completed on chain yet. Live
  /// entries derive from `details.status`; cached entries use the
  /// stored flag.
  bool get isPending {
    final live = details;
    if (live == null) return _cachedPending ?? false;
    return live.status == breez.PaymentStatus.pending;
  }

  @override
  TransactionType get type {
    final live = details;
    if (live == null) {
      return _cachedDirection ?? TransactionType.sent;
    }
    return live.paymentType == breez.PaymentType.receive
        ? TransactionType.received
        : TransactionType.sent;
  }

  @override
  num get amount => amountSats;

  @override
  String get asset => 'btc';

  /// Human/search text pulled from the Lightning/Spark payment details —
  /// the invoice description plus any LNURL sender comment. Empty for
  /// cache-hydrated shells or rows that carry no note. Used by the unified
  /// search so a Lightning payment is findable by its description.
  String get searchableDetail {
    final d = details?.details;
    if (d is breez.PaymentDetails_Lightning) {
      return [
        d.description,
        d.lnurlReceiveMetadata?.senderComment,
        d.lnurlPayInfo?.comment,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    }
    if (d is breez.PaymentDetails_Spark) {
      return d.invoiceDetails?.description ?? '';
    }
    return '';
  }
}

class SparkUnclaimedDeposit extends BaseTransaction {
  /// Live SDK payload — null on cache-hydrated rows. Detail screens
  /// that need the raw `breez.DepositInfo` (claim flow, refund flow,
  /// FFI-handle work) must null-check; user-visible primitives are
  /// always available via the getters below.
  final breez.DepositInfo? depositInfo;

  // Primitives serialised by [TransactionCacheCodec] so the home
  // Activity feed can render the pending-deposit row immediately
  // on cold start without waiting for the SDK to re-emit
  // `unclaimedDeposits`.
  final String? _cachedTxid;
  final int? _cachedVout;
  final int? _cachedAmountSats;
  final bool? _cachedIsMature;
  final String? _cachedRefundTxId;
  final bool? _cachedHasClaimError;

  SparkUnclaimedDeposit({
    required super.id, // Usually `${txid}:${vout}`
    required super.timestamp,
    required this.depositInfo,
  })  : _cachedTxid = null,
        _cachedVout = null,
        _cachedAmountSats = null,
        _cachedIsMature = null,
        _cachedRefundTxId = null,
        _cachedHasClaimError = null,
        super(isConfirmed: false);

  /// Hive-hydrated constructor — primitives only, no SDK payload.
  SparkUnclaimedDeposit.fromCache({
    required super.id,
    required super.timestamp,
    required String txid,
    required int vout,
    required int amountSats,
    required bool isMature,
    String? refundTxId,
    bool hasClaimError = false,
  })  : depositInfo = null,
        _cachedTxid = txid,
        _cachedVout = vout,
        _cachedAmountSats = amountSats,
        _cachedIsMature = isMature,
        _cachedRefundTxId = refundTxId,
        _cachedHasClaimError = hasClaimError,
        super(isConfirmed: false);

  @override
  TransactionType get type => TransactionType.received;

  @override
  num get amount =>
      depositInfo?.amountSats.toInt() ?? _cachedAmountSats ?? 0;

  @override
  String get asset => 'btc';

  int get vout => depositInfo?.vout ?? _cachedVout ?? 0;
  String get txid => depositInfo?.txid ?? _cachedTxid ?? '';
  bool get isMature => depositInfo?.isMature ?? _cachedIsMature ?? false;
  String? get refundTxId =>
      depositInfo?.refundTxId ?? _cachedRefundTxId;

  /// True when the SDK reported a claim failure on the live entry,
  /// or when the cached primitive (carried across cold start) says
  /// so. Detail flows still need the live `claimError` struct for
  /// retry — they should null-check `depositInfo`.
  bool get hasClaimError =>
      depositInfo?.claimError != null || (_cachedHasClaimError ?? false);
}

class SparkPendingDeposit extends BaseTransaction {
  final mempool.MempoolTransaction mempoolTx;
  final int confirmations; // 0, 1, or 2

  SparkPendingDeposit({
    required super.id,
    required super.timestamp,
    required this.mempoolTx,
    required this.confirmations,
  }) : super(isConfirmed: false);

  @override
  TransactionType get type => TransactionType.received;

  @override
  num get amount => mempoolTx.balanceChange.abs();

  @override
  String get asset => 'btc';
}

/// Activity-feed row wrapping a [SwapOrder]: an Orchestra swap, a Cash
/// App purchase, or a retired provider's order (read-only history).
class SwapOrderTransaction extends BaseTransaction {
  final SwapOrder details;

  SwapOrderTransaction({
    required super.id,
    required super.timestamp,
    required this.details,
    required super.isConfirmed,
  });

  // Delegate: the exchange model's getter also accepts 'settled'
  // (the delivery reconciler's terminal spelling) —
  // checking only 'success' here left settled rows badged PENDING.
  bool get isComplete => details.isComplete;

  @override
  TransactionType get type => TransactionType.received;
  @override
  num get amount => 0;
  @override
  String get asset => details.coinTo;

  // BaseTransaction.== only compares id/timestamp/isConfirmed/amount
  // /asset/type. None of those change as a swap
  // exchange progresses through `exchanging → sending → success` —
  // the status flips while the row's identity stays the same. That
  // made Riverpod's value-equality short-circuit skip the rebuild,
  // so the UI didn't reflect status updates until the user pulled
  // to refresh. Including the status (and the live amounts that
  // Orchestra fills in mid-flight) in equality fixes propagation.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SwapOrderTransaction) return false;
    if (!super.maybeBaseEquals(other)) return false;
    return details.status == other.details.status &&
        details.depositAmount == other.details.depositAmount &&
        details.withdrawalAmount == other.details.withdrawalAmount;
  }

  @override
  int get hashCode => Object.hash(
      super.hashCode,
      details.status,
      details.depositAmount,
      details.withdrawalAmount);
}

class OutlogicTransaction extends BaseTransaction {
  final OutlogicOrder details;

  OutlogicTransaction({
    required super.id,
    required super.timestamp,
    required this.details,
    required super.isConfirmed,
  });

  bool get isBuy => details.fromAsset != 'BTC' && details.fromAsset != 'L-BTC';
  // Match the backend's normalizeOutlogicStatus "completed" set. Outlogic
  // finalizes orders as SETTLED / DEPOSIT_RECEIVED / DEPOSIT_CONFIRMED (not
  // always the literal COMPLETED), which the backend books as done — so the
  // UI must treat them as complete too, otherwise a finished order looks stuck
  // at "Waiting for deposit".
  bool get isComplete => const {
        'COMPLETED',
        'SETTLED',
        'DEPOSIT_RECEIVED',
        'DEPOSIT_CONFIRMED',
      }.contains(details.status);

  /// User-facing "pending" is narrower than `!isTerminal`. Once the deposit is
  /// confirmed / approved the user has nothing left to do; the order will
  /// settle on Outlogic's side. Polling keeps running (pendingOrders still
  /// drives sync), but the UI should stop flagging it as pending.
  bool get isPending =>
      !details.isTerminal &&
      details.status != 'DEPOSIT_CONFIRMED' &&
      details.status != 'APPROVED';

  String get fiatAsset => isBuy ? details.fromAsset : details.toAsset;
  String get fiatAmount {
    if (isBuy) return details.fromAmount.toStringAsFixed(2);
    if (details.trade != null) return details.trade!.toAmount.toStringAsFixed(2);
    return '...';
  }

  @override
  TransactionType get type => isBuy ? TransactionType.received : TransactionType.sent;
  @override
  num get amount => 0;
  @override
  String get asset => isBuy ? details.toAsset : details.fromAsset;

  // Status flips through WAITING_FOR_DEPOSIT → DEPOSIT_RECEIVED →
  // APPROVED → COMPLETED while every BaseTransaction field stays
  // identical. Include status here so Riverpod sees the change.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OutlogicTransaction) return false;
    if (!super.maybeBaseEquals(other)) return false;
    return details.status == other.details.status;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, details.status);
}

class PolymarketTransaction extends BaseTransaction {
  final Activity activity;

  /// Set on a row read from a resolved market rather than from the
  /// venue's history (`predictionResults`): a lost prediction, which is
  /// never claimed, or a win not claimed yet. Built when the list is
  /// drawn, never cached.
  final PredictionResult? result;

  PolymarketTransaction({
    required super.id,
    required super.timestamp,
    required this.activity,
    this.result,
  }) : super(isConfirmed: true);

  /// [result] as a row of the Predictions activity, dated at the
  /// resolution.
  factory PolymarketTransaction.result(PredictionResult result) =>
      PolymarketTransaction(
        id: 'result_${result.activity.asset}_${result.activity.timestamp}',
        timestamp: result.activity.timestampDate,
        activity: result.activity,
        result: result,
      );

  ActivityType get activityType => activity.activityType;

  double get usdcAmount => activity.usdcSize;
  String? get marketTitle => activity.title;
  String get txHash => activity.transactionHash;

  @override
  TransactionType get type {
    switch (activityType) {
      case ActivityType.deposit:
        return TransactionType.received;
      case ActivityType.withdraw:
        return TransactionType.sent;
      case ActivityType.trade:
        return activity.side?.toUpperCase() == 'SELL'
            ? TransactionType.sent
            : TransactionType.received;
      case ActivityType.redeem:
        return TransactionType.received;
      default:
        return TransactionType.received;
    }
  }

  @override
  num get amount => (usdcAmount * 1e6).toInt(); // Store in base units (6 decimals)

  @override
  String get asset => 'usdc';
}

class MempoolAddressTransaction extends BaseTransaction {
  final mempool.MempoolTransaction details;

  MempoolAddressTransaction({
    required super.id,
    required super.timestamp,
    required super.isConfirmed,
    required this.details,
  });

  // `isConfirmed` is part of the base equality, so a pending →
  // confirmed flip already triggers a rebuild. But block height
  // accumulating once confirmed (used by some UI to show
  // confirmations) doesn't — include it explicitly so deeper
  // confirmation counts still propagate without a force-refresh.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MempoolAddressTransaction) return false;
    if (!super.maybeBaseEquals(other)) return false;
    return details.blockHeight == other.details.blockHeight;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, details.blockHeight);

  @override
  TransactionType get type =>
      details.balanceChange >= 0 ? TransactionType.received : TransactionType.sent;

  @override
  num get amount => details.balanceChange.abs();

  @override
  String get asset => 'btc';
}

/// External USDC / USDC.e transfer landing at the Polymarket Safe.
/// Indexed by Polygonscan's `tokentx` API — the Polymarket Data
/// API only tracks bet activity, so plain inflows from another
/// wallet have no other source.
class PolymarketUsdcReceive extends BaseTransaction {
  final String fromAddress;
  final String tokenAddress;
  final BigInt rawAmount;
  final int blockNumber;

  PolymarketUsdcReceive({
    required super.id,
    required super.timestamp,
    required super.isConfirmed,
    required this.fromAddress,
    required this.tokenAddress,
    required this.rawAmount,
    required this.blockNumber,
  });

  @override
  TransactionType get type => TransactionType.received;
  @override
  num get amount => rawAmount.toDouble() / 1e6;
  @override
  String get asset => 'usdc';

  bool get isBridged =>
      tokenAddress.toLowerCase() ==
      '0x2791bca1f2de4661ed88a30c99a7a9449aa84174';

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'isConfirmed': isConfirmed,
        'fromAddress': fromAddress,
        'tokenAddress': tokenAddress,
        'rawAmount': rawAmount.toString(),
        'blockNumber': blockNumber,
      };

  factory PolymarketUsdcReceive.fromJson(Map<String, dynamic> json) =>
      PolymarketUsdcReceive(
        id: json['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        isConfirmed: json['isConfirmed'] as bool? ?? true,
        fromAddress: json['fromAddress'] as String,
        tokenAddress: json['tokenAddress'] as String,
        rawAmount: BigInt.parse(json['rawAmount'] as String),
        blockNumber: (json['blockNumber'] as num).toInt(),
      );
}

class UsdbTokenTransaction extends BaseTransaction {
  final breez.Payment details;

  UsdbTokenTransaction({
    required super.id,
    required super.timestamp,
    required this.details,
    required super.isConfirmed,
  });

  @override
  TransactionType get type =>
      details.paymentType == breez.PaymentType.receive
          ? TransactionType.received
          : TransactionType.sent;

  @override
  num get amount => details.amount.toInt();

  /// Network fee WE paid, in sats (USDB token transfers settle their
  /// fee in BTC/sats, not USDB). Always available — `details` is the
  /// live SDK payload on this row type.
  int get feeSats => details.fees.toInt();

  @override
  String get asset => 'usdb';
}

// `UsdbSwapTransaction` was deleted with the Flashnet Earn product. Its
// data came only from the Flashnet API plus a cache copy, so the rows are
// unrecoverable and gone. `UsdbTokenTransaction` above deliberately
// SURVIVES: it is a plain Spark token transfer the Breez SDK re-emits
// from its on-device DB forever, with no Flashnet coupling.

class Transaction {
  final List<BitcoinTransaction> bitcoinTransactions;
  final List<SparkTransaction> sparkTransactions;
  final List<SparkUnclaimedDeposit> sparkUnclaimedDeposits;
  final List<SparkPendingDeposit> sparkPendingDeposits;
  final List<MempoolAddressTransaction> mempoolTransactions;
  final List<UsdbTokenTransaction> usdbTokenTransactions;
  final List<SwapOrderTransaction> swapOrderTransactions;
  final List<PolymarketTransaction> polymarketTransactions;
  final List<PolymarketUsdcReceive> polymarketUsdcReceives;
  final List<OutlogicTransaction> outlogicTransactions;

  Transaction({
    required this.bitcoinTransactions,
    required this.sparkTransactions,
    required this.sparkUnclaimedDeposits,
    this.sparkPendingDeposits = const [],
    this.mempoolTransactions = const [],
    this.usdbTokenTransactions = const [],
    this.swapOrderTransactions = const [],
    this.polymarketTransactions = const [],
    this.polymarketUsdcReceives = const [],
    this.outlogicTransactions = const [],
  });

  Transaction copyWith({
    List<BitcoinTransaction>? bitcoinTransactions,
    List<SparkTransaction>? sparkTransactions,
    List<SparkUnclaimedDeposit>? sparkUnclaimedDeposits,
    List<SparkPendingDeposit>? sparkPendingDeposits,
    List<MempoolAddressTransaction>? mempoolTransactions,
    List<UsdbTokenTransaction>? usdbTokenTransactions,
    List<SwapOrderTransaction>? swapOrderTransactions,
    List<PolymarketTransaction>? polymarketTransactions,
    List<OutlogicTransaction>? outlogicTransactions,
  }) {
    return Transaction(
      bitcoinTransactions: bitcoinTransactions ?? this.bitcoinTransactions,
      sparkTransactions: sparkTransactions ?? this.sparkTransactions,
      sparkUnclaimedDeposits: sparkUnclaimedDeposits ?? this.sparkUnclaimedDeposits,
      sparkPendingDeposits: sparkPendingDeposits ?? this.sparkPendingDeposits,
      mempoolTransactions: mempoolTransactions ?? this.mempoolTransactions,
      usdbTokenTransactions: usdbTokenTransactions ?? this.usdbTokenTransactions,
      swapOrderTransactions: swapOrderTransactions ?? this.swapOrderTransactions,
      polymarketTransactions: polymarketTransactions ?? this.polymarketTransactions,
      polymarketUsdcReceives: polymarketUsdcReceives,
      outlogicTransactions: outlogicTransactions ?? this.outlogicTransactions,
    );
  }

  // Aggregate equality so the StateNotifier caching this Transaction
  // can short-circuit a notify when an idle sync tick rebuilt the
  // same content (every list len + element matches). Identical
  // ticks happen all the time — the 5-second loop fetches 8 sources
  // and most of the time none of them changed. With this in place,
  // the cascade of provider rebuilds (TransactionList, analytics,
  // home cards, polymarket activity feed) sees a single notification
  // per actual data delta, not one per sync tick.
  //
  // Performance: list length comparisons short-circuit in O(1); only
  // when lengths match does element-wise equality run. Element
  // equality is O(1) per element via [BaseTransaction.==].
  bool _listEqual(List<BaseTransaction> a, List<BaseTransaction> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Transaction) return false;
    return _listEqual(bitcoinTransactions, other.bitcoinTransactions) &&
        _listEqual(sparkTransactions, other.sparkTransactions) &&
        _listEqual(sparkUnclaimedDeposits, other.sparkUnclaimedDeposits) &&
        _listEqual(sparkPendingDeposits, other.sparkPendingDeposits) &&
        _listEqual(mempoolTransactions, other.mempoolTransactions) &&
        _listEqual(usdbTokenTransactions, other.usdbTokenTransactions) &&
        _listEqual(swapOrderTransactions, other.swapOrderTransactions) &&
        _listEqual(polymarketTransactions, other.polymarketTransactions) &&
        _listEqual(polymarketUsdcReceives, other.polymarketUsdcReceives) &&
        _listEqual(outlogicTransactions, other.outlogicTransactions);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(bitcoinTransactions),
        Object.hashAll(sparkTransactions),
        Object.hashAll(sparkUnclaimedDeposits),
        Object.hashAll(sparkPendingDeposits),
        Object.hashAll(mempoolTransactions),
        Object.hashAll(usdbTokenTransactions),
        Object.hashAll(swapOrderTransactions),
        Object.hashAll(polymarketTransactions),
        Object.hashAll(polymarketUsdcReceives),
        Object.hashAll(outlogicTransactions),
      );

  // Cached computed lists — safe because Transaction is immutable (all fields are final).
  List<BaseTransaction>? _cachedAllTransactions;
  List<BaseTransaction>? _cachedAllTransactionsWithSwaps;
  List<BaseTransaction>? _cachedAllTransactionsSorted;
  List<BaseTransaction>? _cachedHomeTransactionsSorted;

  /// Txids of on-chain deposits the Breez SDK has already credited (a
  /// completed deposit payment). The SDK claims early when the claim fee fits
  /// `kSparkAutoClaimMaxFeeSats`: instantly at 0 confirmations or expedited
  /// at 1-2, so a deposit can be spendable well before 3 confirmations.
  Set<String> get _creditedDepositTxids => {
        for (final t in sparkTransactions)
          if (t.details?.status == breez.PaymentStatus.completed &&
              t.details?.details is breez.PaymentDetails_Deposit)
            (t.details!.details as breez.PaymentDetails_Deposit)
                .txId
                .toLowerCase(),
      };

  /// Mempool `n/3` rows still waiting for their claim. Once the SDK has
  /// credited the deposit, its completed Breez row is the receive and the
  /// `n/3` row would wrongly say the bitcoin is not ready yet.
  List<SparkPendingDeposit> get _displayPendingDeposits {
    if (sparkPendingDeposits.isEmpty) return sparkPendingDeposits;
    final credited = _creditedDepositTxids;
    if (credited.isEmpty) return sparkPendingDeposits;
    return sparkPendingDeposits
        .where((d) => !credited.contains(d.mempoolTx.txid.toLowerCase()))
        .toList();
  }

  /// Txids of incoming on-chain deposits currently represented by a
  /// websocket/mempool row that is still waiting for its claim. While such a
  /// row exists it is the SINGLE representation and the raw Breez/BDK rows
  /// are hidden; keying on the row's existence means we never hide a receive
  /// that has no `n/3` replacement.
  Set<String> get _pendingDepositTxids => _displayPendingDeposits
      .map((d) => d.mempoolTx.txid.toLowerCase())
      .toSet();

  /// `sparkTransactions` with the Breez SDK's on-chain *deposit* rows hidden
  /// while a mempool `n/3` twin exists for the same txid. Full list is left
  /// on the state so receive analytics / the mascot still fire on first sight.
  List<SparkTransaction> get _displaySparkTransactions {
    final pending = _pendingDepositTxids;
    if (pending.isEmpty) return sparkTransactions;
    return sparkTransactions.where((t) {
      if (t.sparkType != SparkTransactionType.bitcoin) return true;
      final details = t.details?.details;
      if (details is! breez.PaymentDetails_Deposit) return true;
      return !pending.contains(details.txId.toLowerCase());
    }).toList();
  }

  List<BaseTransaction> get allTransactions {
    return _cachedAllTransactions ??= [
      ...bitcoinTransactions,
      ..._displaySparkTransactions,
      ...sparkUnclaimedDeposits,
      ..._displayPendingDeposits,
      ...mempoolTransactions,
      ...usdbTokenTransactions,
      ...swapOrderTransactions,
      ...polymarketTransactions,
      ...polymarketUsdcReceives,
      // Outlogic / bank-transfer orders surface on the home feed
      // from the moment they're created, including pending statuses
      // (`WAITING_FOR_DEPOSIT`, `DEPOSIT_RECEIVED`) so the user can
      // see "Awaiting Deposit" the second they finish the fiat
      // purchase. Earlier this branch hid pending rows to avoid
      // perceived double-counting against the on-chain receive that
      // lands later — UX call reversed: users want a paper trail of
      // the in-flight order more than they want to avoid the brief
      // overlap. Terminal-failure statuses (CANCELED / EXPIRED /
      // REJECTED / REFUNDED) still show with their badge so the
      // user can tell something went wrong; only undefined / blank
      // statuses are dropped.
      ...outlogicTransactions.where((tx) => tx.details.status.isNotEmpty),
    ];
  }

  List<BaseTransaction> get allTransactionsWithSwaps {
    return _cachedAllTransactionsWithSwaps ??= [
      ...bitcoinTransactions,
      ..._displaySparkTransactions,
      ...sparkUnclaimedDeposits,
      ..._displayPendingDeposits,
      ...mempoolTransactions,
      ...usdbTokenTransactions,
      ...swapOrderTransactions,
      ...polymarketTransactions,
      ...polymarketUsdcReceives,
      ...outlogicTransactions,
    ];
  }

  List<BaseTransaction> get allTransactionsSorted {
    return _cachedAllTransactionsSorted ??= (List<BaseTransaction>.from(allTransactions)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
  }

  List<BaseTransaction> get homeTransactionsSorted {
    if (_cachedHomeTransactionsSorted != null) {
      return _cachedHomeTransactionsSorted!;
    }
    // Snapshot Polymarket-tagged Spark tx ids + bet-flow Orchestra
    // orderIds once so we don't hit Hive for every tx while filtering.
    final polymarketSparkIds = PolymarketSparkTxsService.snapshot();
    final polymarketOrchestraIds =
        PolymarketSparkTxsService.orchestraOrderSnapshot();
    final orchestraDeliveryIds =
        PolymarketSparkTxsService.orchestraDeliverySnapshot();
    // Walk Spark txs newest-first and try to match each unmatched
    // incoming Spark against any open claim-window. First match wins
    // (claim windows are consumed) — this means a single inbound
    // Orchestra delivery is hidden but unrelated subsequent Spark
    // receives stay visible.
    //
    // Direction filter is REQUIRED here. The earlier code matched any
    // Spark tx (send or receive) in the 60-min window, which silently
    // hid unrelated Lightning RECEIVES that happened to land while an
    // unrelated USDC→BTC withdraw's claim window was still open —
    // exactly the bug where a user did a withdraw, then received sats
    // on Lightning, and the receive vanished from Home (still visible
    // in History since History bypasses this filter).
    final sparkTxs = allTransactionsSorted.whereType<SparkTransaction>();
    for (final tx in sparkTxs) {
      if (polymarketSparkIds.contains(tx.id)) continue;
      // Only consider RECEIVES — outbound sends can never be a claim
      // delivery. `tx.type == TransactionType.received` (resolved via
      // the wrapped Breez SDK paymentType or the cached direction) is
      // what we want; `amountSats > 0` would treat sends as eligible
      // too because amount is unsigned on this model.
      final isReceive = tx.type == TransactionType.received;
      if (!isReceive) continue;
      final matched = PolymarketSparkTxsService.consumeMatchingClaim(
        receivedAtMs: tx.timestamp.millisecondsSinceEpoch,
      );
      if (matched) {
        PolymarketSparkTxsService.tag(tx.id);
        polymarketSparkIds.add(tx.id);
      }
    }
    return _cachedHomeTransactionsSorted = allTransactionsSorted.where((tx) {
      if (tx is SwapOrderTransaction) {
        final status = tx.details.status;
        if (status == 'wait' || status == 'expired' || status == 'overdue') {
          return false;
        }
        // Hide ONLY bet-flow Orchestra exchanges (orderId tagged at
        // exchange creation in pending_bet_overlay.dart). User-initiated
        // Convert exchanges go un-tagged and stay visible — they ARE
        // the user-meaningful row. The full conversion record is still
        // in allTransactionsSorted regardless.
        if (tx.details.provider == 'Orchestra' &&
            polymarketOrchestraIds.contains(tx.id)) {
          return false;
        }
      }
      // Confirmed Orchestra delivery legs ARE hidden. Unlike the
      // disabled time-only heuristic below, these ids were matched by
      // amount AND window against one specific pending Orchestra→Spark
      // exchange row (background sync's reconciler), and that row was
      // settled with the real sats in the same pass — the feed always
      // keeps the user-meaningful "Trading withdraw" story row.
      if (tx is SparkTransaction && orchestraDeliveryIds.contains(tx.id)) {
        return false;
      }
      // Spark-side Polymarket hide DISABLED. The heuristic was
      // matching unrelated Spark receives that happened to land
      // inside a claim's 5-minute expected-delivery window, plus
      // every bet-funding send — which collapsed busy users' home
      // feeds down to one row even when History showed 9+. Users
      // would rather see a duplicate-looking "Sent BTC via Spark"
      // alongside the "Polymarket bet" card than have their feed go
      // empty. The tagging service still runs (so the Polymarket
      // screen's own bet-history filtering keeps working); we just
      // don't apply the hide on the home Activity surface.
      //
      // if (tx is SparkTransaction && polymarketSparkIds.contains(tx.id)) {
      //   return false;
      // }
      return true;
    }).toList();
  }

  List<BitcoinTransaction> filterBitcoinTransactions(DateTimeSelect range) {
    return bitcoinTransactions.where((tx) {
      return tx.timestamp.isAfter(DateTime.fromMillisecondsSinceEpoch(range.start * 1000)) &&
          tx.timestamp.isBefore(DateTime.fromMillisecondsSinceEpoch(range.end * 1000));
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<BaseTransaction> get unsettledSwapsAndPurchases {
    final List<BaseTransaction> unsettled = [];

    unsettled.addAll(sparkUnclaimedDeposits);

    unsettled.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return unsettled;
  }

  List<BaseTransaction> get settledTransactions {
    final unsettledIds = unsettledSwapsAndPurchases.map((tx) => tx.id).toSet();
    return allTransactionsSorted.where((tx) => !unsettledIds.contains(tx.id)).toList();
  }

  DateTime? get earliestTimestamp {
    if (allTransactions.isEmpty) return null;
    return allTransactions.map((tx) => tx.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  factory Transaction.empty() {
    return Transaction(
      bitcoinTransactions: [],
      sparkTransactions: [],
      sparkUnclaimedDeposits: [],
      sparkPendingDeposits: [],
      mempoolTransactions: [],
      usdbTokenTransactions: [],
      swapOrderTransactions: [],
      polymarketTransactions: [],
      polymarketUsdcReceives: [],
      outlogicTransactions: [],
    );
  }
}
