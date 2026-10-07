// lib/services/transaction_cache_codec.dart
//
// JSON codec for the per-wallet `Transaction` aggregate, used by
// `WalletTransactionCacheNotifier` to persist its in-memory state to
// Hive so cold start renders the home Activity feed immediately
// instead of waiting for the first sync.
//
// What we serialize:
//   - SwapOrderTransaction        (wraps SwapOrder — toJson)
//   - OutlogicTransaction         (wraps OutlogicOrder — toJson)
//   - PolymarketTransaction       (wraps Activity — toJson on the
//                                  upstream package)
//   - PolymarketUsdcReceive       (toJson on this file's pair)
//   - MempoolAddressTransaction   (wraps MempoolTransaction — toJson)
//   - SparkPendingDeposit         (wraps MempoolTransaction — toJson)
//
// SparkTransaction and SparkUnclaimedDeposit are persisted as
// primitive shells — the wrapped `breez.*` types can't be
// reconstructed from JSON (FFI handles), so we serialise the
// user-visible primitives (amount, direction, txid, isMature, etc.)
// and hydrate via the corresponding `fromCache` constructors.
// Downstream renderers that need raw SDK fields null-check the live
// payload; the next sync / event replaces shells with full entries.
//
// What we deliberately skip (the SDK-bound categories):
//   - UsdbTokenTransaction        (`breez.Payment` likewise)
//
// `BitcoinTransaction` is a special case: the wrapped `bdk.TxDetails`
// can't be reconstructed from JSON, but the user-visible row only
// needs id + timestamp + isConfirmed + received/sent sats — all
// primitives. We persist those and use the
// [BitcoinTransaction.fromCache] constructor on hydration to
// rebuild a shell that satisfies the home Activity row's
// rendering. Detail screens that dereference `btcDetails` see null
// and surface a "loading details" affordance until the next sync
// replaces the shell with a live instance. Critical for the
// savings-wallet cold-start UX — without this the Activity feed
// shows empty until the first post-launch sync writes fresh data.
//
// The skipped categories are repopulated on the first post-boot sync
// from their underlying SDK databases (BDK SQLite, Breez SDK DB),
// which are themselves persisted across launches and load fast. So
// at cold start the home feed shows whichever rows we've persisted
// here; a few hundred ms later the SDK-derived rows appear.
//
// Schema is versioned so an incompatible model change cleanly drops
// old caches instead of crashing — `_kSchemaVersion` bump = old
// entries return `null` from [decode] and the cache treats it as
// empty.

import 'dart:convert';

import 'package:kute/models/outlogic_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/persistence/hive_schema.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Activity;

class TransactionCacheCodec {
  TransactionCacheCodec._();

  /// Map key of the swap-order list. The name is from older builds and
  /// is kept so existing caches keep reading back.
  static const String _kSwapOrdersKey = 'sideshift';

  static const int _kSchemaVersion = 2;

  /// Forward migrations indexed by source version: `_migrations[0]`
  /// handles v1 → v2, etc. v1→v2 added Spark transaction
  /// persistence — purely additive, so the migration just stamps
  /// the version forward; the missing `'spark'` key reads as an
  /// empty list via the decode `?? const []` fallback. Without
  /// this, every v1 entry was being dropped (swap order
  /// / Polymarket / Outlogic rows lost on app upgrade) because
  /// `upgradeOrDrop` returns null when the migration list is empty.
  static const List<HiveMigration> _migrations = <HiveMigration>[
    _migrateV1ToV2,
  ];

  static Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> v1) {
    return {...v1, 'v': 2};
  }

  /// Serializes the persistable subset of [tx] to a JSON string.
  /// Caller writes the result into Hive keyed by walletId.
  static String encode(Transaction tx) => jsonEncode(toCacheMap(tx));

  /// The json-safe map behind [encode], exposed so callers can build
  /// it on the main isolate (model objects hold SDK payloads and must
  /// not cross an isolate boundary) and then run the heavy
  /// `jsonEncode` in a background isolate via `compute`.
  static Map<String, dynamic> toCacheMap(Transaction tx) {
    final map = <String, dynamic>{
      'v': _kSchemaVersion,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'bitcoin':
          tx.bitcoinTransactions.map((t) => _bitcoinToJson(t)).toList(),
      'spark':
          tx.sparkTransactions.map((t) => _sparkToJson(t)).toList(),
      'sparkUnclaimed': tx.sparkUnclaimedDeposits
          .map((d) => _sparkUnclaimedToJson(d))
          .toList(),
      _kSwapOrdersKey:
          tx.swapOrderTransactions.map((t) => _swapOrderToJson(t)).toList(),
      'outlogic':
          tx.outlogicTransactions.map((t) => _outlogicToJson(t)).toList(),
      'polymarket':
          tx.polymarketTransactions.map((t) => _polymarketToJson(t)).toList(),
      'polymarketUsdcReceives':
          tx.polymarketUsdcReceives.map((r) => r.toJson()).toList(),
      'mempool':
          tx.mempoolTransactions.map((t) => _mempoolToJson(t)).toList(),
      'sparkPendingDeposits':
          tx.sparkPendingDeposits.map((d) => _pendingToJson(d)).toList(),
      // The 'usdbSwap' key is no longer written (Flashnet Earn removed).
      // Old blobs still carrying it decode fine: unread keys are ignored.
      // The schema version stays at 2 ON PURPOSE — bumping it without a
      // migration drops EVERY user's whole cold-start cache.
    };
    return map;
  }

  /// Reconstructs a `Transaction` from the cached JSON. Returns
  /// `null` if the payload is missing, malformed, or schema-mismatched
  /// — caller treats `null` as cache miss.
  ///
  /// SDK-bound categories (bitcoin, spark, sparkUnclaimedDeposits,
  /// usdbToken) are returned as empty lists; they'll fill in on the
  /// first post-boot sync.
  static Transaction? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final rawMap = jsonDecode(raw) as Map<String, dynamic>;
      final map = HiveSchema.upgradeOrDrop(
        rawMap,
        currentVersion: _kSchemaVersion,
        migrations: _migrations,
      );
      if (map == null) return null;
      return Transaction(
        bitcoinTransactions: ((map['bitcoin'] as List?) ?? const [])
            .whereType<Map>()
            .map((j) => _bitcoinFromJson(Map<String, dynamic>.from(j)))
            .whereType<BitcoinTransaction>()
            .toList(),
        sparkTransactions: ((map['spark'] as List?) ?? const [])
            .whereType<Map>()
            .map((j) => _sparkFromJson(Map<String, dynamic>.from(j)))
            .whereType<SparkTransaction>()
            .toList(),
        sparkUnclaimedDeposits:
            ((map['sparkUnclaimed'] as List?) ?? const [])
                .whereType<Map>()
                .map((j) =>
                    _sparkUnclaimedFromJson(Map<String, dynamic>.from(j)))
                .whereType<SparkUnclaimedDeposit>()
                .toList(),
        sparkPendingDeposits:
            ((map['sparkPendingDeposits'] as List?) ?? const [])
                .whereType<Map>()
                .map((j) => _pendingFromJson(Map<String, dynamic>.from(j)))
                .whereType<SparkPendingDeposit>()
                .toList(),
        mempoolTransactions: ((map['mempool'] as List?) ?? const [])
            .whereType<Map>()
            .map((j) => _mempoolFromJson(Map<String, dynamic>.from(j)))
            .whereType<MempoolAddressTransaction>()
            .toList(),
        usdbTokenTransactions: const [],
        swapOrderTransactions: ((map[_kSwapOrdersKey] as List?) ?? const [])
            .whereType<Map>()
            .map((j) => _swapOrderFromJson(Map<String, dynamic>.from(j)))
            .whereType<SwapOrderTransaction>()
            .toList(),
        polymarketTransactions: ((map['polymarket'] as List?) ?? const [])
            .whereType<Map>()
            .map((j) => _polymarketFromJson(Map<String, dynamic>.from(j)))
            .whereType<PolymarketTransaction>()
            .toList(),
        polymarketUsdcReceives:
            ((map['polymarketUsdcReceives'] as List?) ?? const [])
                .whereType<Map>()
                .map((j) =>
                    PolymarketUsdcReceive.fromJson(Map<String, dynamic>.from(j)))
                .toList(),
        outlogicTransactions: ((map['outlogic'] as List?) ?? const [])
            .whereType<Map>()
            .map((j) => _outlogicFromJson(Map<String, dynamic>.from(j)))
            .whereType<OutlogicTransaction>()
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  // ─── per-category helpers ─────────────────────────────────────

  static Map<String, dynamic> _bitcoinToJson(BitcoinTransaction t) => {
        'id': t.id,
        'timestamp': t.timestamp.millisecondsSinceEpoch,
        'isConfirmed': t.isConfirmed,
        'receivedSats': t.receivedSats,
        'sentSats': t.sentSats,
      };

  static BitcoinTransaction? _bitcoinFromJson(Map<String, dynamic> j) {
    try {
      return BitcoinTransaction.fromCache(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        isConfirmed: j['isConfirmed'] as bool? ?? false,
        receivedSats: (j['receivedSats'] as num?)?.toInt() ?? 0,
        sentSats: (j['sentSats'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  // SparkTransaction — primitives only, see file header.
  // `sparkType` and `direction` serialize as their enum index so a
  // value-only re-import (no source dependency) stays cheap.
  static Map<String, dynamic> _sparkToJson(SparkTransaction t) => {
        'id': t.id,
        'timestamp': t.timestamp.millisecondsSinceEpoch,
        'isConfirmed': t.isConfirmed,
        'amountSats': t.amountSats,
        'sparkType': t.sparkType.index,
        'direction': t.type.index,
        'pending': t.isPending,
        if (t.onChainTxId != null) 'onChainTxId': t.onChainTxId,
      };

  static SparkTransaction? _sparkFromJson(Map<String, dynamic> j) {
    try {
      final sparkTypeIdx = (j['sparkType'] as num?)?.toInt() ??
          SparkTransactionType.spark.index;
      final directionIdx =
          (j['direction'] as num?)?.toInt() ?? TransactionType.sent.index;
      return SparkTransaction.fromCache(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        isConfirmed: j['isConfirmed'] as bool? ?? false,
        amountSats: (j['amountSats'] as num?)?.toInt() ?? 0,
        sparkType: SparkTransactionType
            .values[sparkTypeIdx.clamp(0, SparkTransactionType.values.length - 1)],
        direction: TransactionType.values[
            directionIdx.clamp(0, TransactionType.values.length - 1)],
        pending: j['pending'] as bool? ?? false,
        onChainTxId: j['onChainTxId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // SparkUnclaimedDeposit — primitives only, see file header.
  // Reconstructed via `SparkUnclaimedDeposit.fromCache`. Lets the
  // home Activity feed render the in-flight Bitcoin pending row
  // immediately on cold start instead of waiting for the SDK to
  // re-emit `unclaimedDeposits`.
  static Map<String, dynamic> _sparkUnclaimedToJson(
          SparkUnclaimedDeposit d) =>
      {
        'id': d.id,
        'timestamp': d.timestamp.millisecondsSinceEpoch,
        'txid': d.txid,
        'vout': d.vout,
        'amountSats': d.amount.toInt(),
        'isMature': d.isMature,
        'refundTxId': d.refundTxId,
        'hasClaimError': d.hasClaimError,
      };

  static SparkUnclaimedDeposit? _sparkUnclaimedFromJson(
      Map<String, dynamic> j) {
    try {
      return SparkUnclaimedDeposit.fromCache(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        txid: j['txid'] as String? ?? '',
        vout: (j['vout'] as num?)?.toInt() ?? 0,
        amountSats: (j['amountSats'] as num?)?.toInt() ?? 0,
        isMature: j['isMature'] as bool? ?? false,
        refundTxId: j['refundTxId'] as String?,
        hasClaimError: j['hasClaimError'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _swapOrderToJson(SwapOrderTransaction t) {
    // SwapOrder has no toJson on the entity itself (only on
    // request DTOs). Round-trip through the API shape its existing
    // fromJson reads — this keeps the codec narrowly scoped without
    // having to add a redundant toJson on the upstream class.
    final d = t.details;
    return {
      'id': t.id,
      'timestamp': t.timestamp.millisecondsSinceEpoch,
      'isConfirmed': t.isConfirmed,
      'details': {
        'id': d.id,
        'depositCoin': d.coinFrom,
        'settleCoin': d.coinTo,
        'depositNetwork': d.networkFrom,
        'settleNetwork': d.networkTo,
        'depositAddress': d.depositAddress,
        'depositMemo': d.depositExtraId,
        'settleAddress': d.withdrawalAddress,
        'depositAmount': d.depositAmount,
        'settleAmount': d.withdrawalAmount,
        'status': d.status,
        'createdAt': DateTime.fromMillisecondsSinceEpoch(d.timestamp)
            .toIso8601String(),
        'depositMin': d.depositMin,
        'depositMax': d.depositMax,
        'rate': d.rate,
        'refundAddress': d.refundAddress,
        'refundMemo': d.refundExtraId,
        'provider': d.provider,
        'providerToken': d.providerToken,
        'walletId': d.walletId,
        'purchaseSource': d.purchaseSource,
        'purchaseFiatUsd': d.purchaseFiatUsd,
        'operationId': d.operationId,
        'routeVersion': d.routeVersion,
        'expiresAt': d.expiresAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(d.expiresAt!)
                .toIso8601String(),
      },
    };
  }

  static SwapOrderTransaction? _swapOrderFromJson(Map<String, dynamic> j) {
    try {
      final d = Map<String, dynamic>.from(j['details'] as Map);
      // fromJson reads only the deposit/settle legs and DROPS the local
      // bookkeeping fields we serialized above — without restoring
      // them, every cache-hydrated Orchestra row cold-started with no
      // provider and the feed lost its "Predictions / Trading"
      // classification until the first live sync. The saved status is
      // restored too.
      final details = SwapOrder.fromJson(d).copyWith(
        status: d['status'] as String?,
        provider: d['provider'] as String?,
        providerToken: d['providerToken'] as String?,
        walletId: d['walletId'] as String?,
        purchaseSource: d['purchaseSource'] as String?,
        purchaseFiatUsd: d['purchaseFiatUsd'] as String?,
        operationId: d['operationId'] as String?,
        routeVersion: d['routeVersion'] as String?,
      );
      return SwapOrderTransaction(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        isConfirmed: j['isConfirmed'] as bool? ?? false,
        details: details,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _outlogicToJson(OutlogicTransaction t) {
    final d = t.details;
    return {
      'id': t.id,
      'timestamp': t.timestamp.millisecondsSinceEpoch,
      'isConfirmed': t.isConfirmed,
      'details': {
        'id': d.id,
        'status': d.status,
        'email': d.email,
        'deposit_crypto_address': d.depositCryptoAddress,
        'from_amount': d.fromAmount,
        'from_asset': d.fromAsset,
        'to_asset': d.toAsset,
        'destination_type': d.destinationType,
        'destination_crypto_address': d.destinationCryptoAddress,
        'destination_bank_address': d.destinationBankAddress,
        'destination_bank_name': d.destinationBankName,
        'destination_bank_account_number': d.destinationBankAccountNumber,
        'created_at': d.createdAt,
        'expires_at': d.expiresAt,
        'transfer_code': d.transferCode,
        'deposit_sepa_address': d.depositSepaAddress,
        'deposit_sepa_bic': d.depositSepaBic,
        'deposit_sepa_beneficiary': d.depositSepaBeneficiary,
        'deposit_sepa_bank_name': d.depositSepaBankName,
        // OutlogicTrade is non-trivial to round-trip and the home
        // Activity feed only needs the order shell to render the
        // row. Sync replaces with full data including trade soon
        // after boot.
        'trade': null,
      },
    };
  }

  static OutlogicTransaction? _outlogicFromJson(Map<String, dynamic> j) {
    try {
      return OutlogicTransaction(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        isConfirmed: j['isConfirmed'] as bool? ?? false,
        details: OutlogicOrder.fromJson(
            Map<String, dynamic>.from(j['details'] as Map)),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _polymarketToJson(PolymarketTransaction t) => {
        'id': t.id,
        'timestamp': t.timestamp.millisecondsSinceEpoch,
        'activity': t.activity.toJson(),
      };

  static PolymarketTransaction? _polymarketFromJson(Map<String, dynamic> j) {
    try {
      return PolymarketTransaction(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        activity:
            Activity.fromJson(Map<String, dynamic>.from(j['activity'] as Map)),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _mempoolToJson(MempoolAddressTransaction t) => {
        'id': t.id,
        'timestamp': t.timestamp.millisecondsSinceEpoch,
        'isConfirmed': t.isConfirmed,
        'details': t.details.toJson(),
      };

  static MempoolAddressTransaction? _mempoolFromJson(Map<String, dynamic> j) {
    try {
      return MempoolAddressTransaction(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        isConfirmed: j['isConfirmed'] as bool? ?? false,
        details: MempoolTransaction.fromJson(
            Map<String, dynamic>.from(j['details'] as Map)),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _pendingToJson(SparkPendingDeposit d) => {
        'id': d.id,
        'timestamp': d.timestamp.millisecondsSinceEpoch,
        'mempoolTx': d.mempoolTx.toJson(),
        'confirmations': d.confirmations,
      };

  static SparkPendingDeposit? _pendingFromJson(Map<String, dynamic> j) {
    try {
      return SparkPendingDeposit(
        id: j['id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        mempoolTx: MempoolTransaction.fromJson(
            Map<String, dynamic>.from(j['mempoolTx'] as Map)),
        confirmations: (j['confirmations'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

}
