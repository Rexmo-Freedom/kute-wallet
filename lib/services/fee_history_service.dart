// lib/services/fee_history_service.dart
//
// Persisted ledger of every fee the user pays across every flow —
// predictions, conversions, sends, swaps, on-chain, lightning, etc.
// One Hive box, one entry per fee event, idempotent by id so retries
// don't double-count.
//
// Read sites (analytics Fees tab) call summarize() / snapshot();
// every flow that incurs a fee calls record(). Wraps any storage
// failure in try/catch at the call site so a write hiccup never
// strands a real-money transaction — fee history is observability,
// not load-bearing.

import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// Categorisation of every fee the app ever charges or passes through.
/// String values are persisted in the Hive payload, so the ordering
/// and names here must stay stable across releases.
enum FeeKind {
  btcOnchain('btc_onchain'),
  lightningRouting('lightning_routing'),
  polymarketTaker('polymarket_taker'),
  uniswapSwap('uniswap_swap'),
  orchestraSpread('orchestra_spread'),
  kuteAffiliate('kute_affiliate'),
  // History only: fees paid to retired providers before they left the
  // app. Nothing logs these any more; old entries still render.
  sideshiftSpread('sideshift_spread'),
  bitcoinvnSpread('bitcoinvn_spread');

  final String wire;
  const FeeKind(this.wire);

  static FeeKind? fromWire(String? s) {
    if (s == null) return null;
    for (final k in FeeKind.values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

/// Single fee event. Keep entries small (~200 bytes serialised) — the
/// ledger can grow long over months and we read all of it on each
/// summary call.
class FeeEntry {
  /// Idempotent dedupe key — txHash on Polygon/Spark, orderId for
  /// Orchestra, or a synthetic UUID-like string for flows
  /// that don't have a natural identifier yet.
  final String id;

  /// Fee timestamp in ms since epoch. For flows with a quote/fill
  /// gap (Orchestra), use the moment the user committed —
  /// when we logged it — not "now" at the time the deposit settled.
  final int ts;
  final FeeKind kind;

  /// Fee amount expressed in 1e-6 USD (lossless for sub-cent fees,
  /// fits in int up to ~9e12 USD). All read-side fiat conversion
  /// happens by multiplying microUsd × usd→fiat at display time, so
  /// historical entries stay correct when the user changes currency.
  final int microUsd;

  /// Raw fee amount in the source unit (e.g. 247 sats, 0.05 USDC.e).
  /// Stored as a string to dodge double-precision rounding on small
  /// crypto amounts — display layer parses on demand.
  final String nativeAmount;

  /// Unit for nativeAmount: 'sats' / 'usdc' / 'usdc.e' / 'pusd' /
  /// 'btc' / etc. Lowercase, free-form — used only for display.
  final String nativeUnit;

  /// Human-readable provider label: 'Polymarket', 'Uniswap V3',
  /// 'Orchestra', 'Spark', 'Lightning', 'Kute', or a retired provider's
  /// name on old entries. Surfaced verbatim in the fees breakdown.
  final String source;

  /// Optional on-chain tx hash or relayer order id. Useful for
  /// drill-down ("show me on the explorer") and cross-referencing
  /// with the transaction list.
  final String? txId;

  /// Optional — only set for fees attributable to a specific
  /// prediction market (lets the fees tab attribute spend by market).
  final String? marketId;

  /// Wallet that was active when the fee was recorded. Lets the fees
  /// view filter to the active wallet (which is what users normally
  /// expect to see).
  final String? walletId;

  const FeeEntry({
    required this.id,
    required this.ts,
    required this.kind,
    required this.microUsd,
    required this.nativeAmount,
    required this.nativeUnit,
    required this.source,
    this.txId,
    this.marketId,
    this.walletId,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'kind': kind.wire,
        'microUsd': microUsd,
        'nativeAmount': nativeAmount,
        'nativeUnit': nativeUnit,
        'source': source,
        if (txId != null) 'txId': txId,
        if (marketId != null) 'marketId': marketId,
        if (walletId != null) 'walletId': walletId,
      };

  static FeeEntry? fromJson(String id, Map<String, dynamic> j) {
    final kind = FeeKind.fromWire(j['kind'] as String?);
    if (kind == null) return null;
    return FeeEntry(
      id: id,
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      kind: kind,
      microUsd: (j['microUsd'] as num?)?.toInt() ?? 0,
      nativeAmount: (j['nativeAmount'] as String?) ?? '0',
      nativeUnit: (j['nativeUnit'] as String?) ?? '',
      source: (j['source'] as String?) ?? '',
      txId: j['txId'] as String?,
      marketId: j['marketId'] as String?,
      walletId: j['walletId'] as String?,
    );
  }

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(ts);

  /// Fee in USD (lossless precision lost — fine for display).
  double get usd => microUsd / 1000000.0;
}

/// Aggregated view over a date range. `byKind` is dense — every
/// FeeKind that appears in the range gets an entry; absent kinds are
/// not in the map (caller can fall back to 0).
class FeeSummary {
  final int totalMicroUsd;
  final Map<FeeKind, int> byKind;
  final int count;

  /// Per-`(kind, source)` breakdown so the analytics row can show
  /// which wallet / origin a fee category came from. `source` is the
  /// human label captured at log-time (e.g. `'Spark'`, `'Savings'`,
  /// `'Polymarket'`); empty when the caller didn't provide one.
  final Map<FeeKind, Map<String, int>> byKindAndSource;

  const FeeSummary({
    required this.totalMicroUsd,
    required this.byKind,
    required this.count,
    this.byKindAndSource = const <FeeKind, Map<String, int>>{},
  });

  static const empty = FeeSummary(
    totalMicroUsd: 0,
    byKind: <FeeKind, int>{},
    count: 0,
    byKindAndSource: <FeeKind, Map<String, int>>{},
  );

  double get totalUsd => totalMicroUsd / 1000000.0;
}

class FeeHistoryService {
  static const _boxName = 'fee_history';

  /// The Hive box is opened at app start in main.dart. If something
  /// goes wrong (corrupted box, missing init), we fall back to a
  /// no-op so logging never throws.
  static Box<String>? get _box {
    try {
      if (!Hive.isBoxOpen(_boxName)) return null;
      return Hive.box<String>(_boxName);
    } catch (_) {
      return null;
    }
  }

  /// Idempotent — recording the same id twice overwrites instead of
  /// double-counting. Call sites that retry (e.g. an order
  /// resubmitted after a network hiccup) benefit from passing a
  /// stable orderId / txHash as the entry id.
  static void record(FeeEntry entry) {
    final box = _box;
    if (box == null) return;
    try {
      box.put(entry.id, jsonEncode(entry.toJson()));
    } catch (_) {
      // Storage write failed (locked box, disk full, etc.) — silently
      // drop. Fee logging is observability, not transactional state.
    }
  }

  /// Optional convenience — lets call sites build the entry inline
  /// without importing FeeEntry directly. All params mirror FeeEntry.
  static void log({
    required String id,
    required FeeKind kind,
    required int microUsd,
    required String nativeAmount,
    required String nativeUnit,
    required String source,
    int? ts,
    String? txId,
    String? marketId,
    String? walletId,
  }) {
    record(FeeEntry(
      id: id,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      kind: kind,
      microUsd: microUsd,
      nativeAmount: nativeAmount,
      nativeUnit: nativeUnit,
      source: source,
      txId: txId,
      marketId: marketId,
      walletId: walletId,
    ));
  }

  /// Total + per-kind breakdown for [from, to]. Both inclusive at the
  /// ms level. Either bound can be null to mean "no lower / no upper
  /// bound".
  ///
  /// [walletId] scopes the summary to fees paid from a specific
  /// wallet. Pass the active wallet's id when rendering wallet-scoped
  /// analytics so a hardware wallet doesn't show Polymarket / Spark /
  /// USDC fees that belong to the spending wallet. Entries with no
  /// recorded walletId (older fees logged before the field was added)
  /// are EXCLUDED when a filter is requested — the alternative is to
  /// pollute every wallet's chart with shared-pool history.
  static FeeSummary summarize({
    DateTime? from,
    DateTime? to,
    String? walletId,
    Set<String>? excludeIds,
  }) {
    final box = _box;
    if (box == null) return FeeSummary.empty;
    int total = 0;
    final byKind = <FeeKind, int>{};
    final byKindAndSource = <FeeKind, Map<String, int>>{};
    int count = 0;
    final fromMs = from?.millisecondsSinceEpoch;
    final toMs = to?.millisecondsSinceEpoch;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = _decode(key.toString(), raw);
      if (entry == null) continue;
      if (fromMs != null && entry.ts < fromMs) continue;
      if (toMs != null && entry.ts > toMs) continue;
      if (walletId != null && entry.walletId != walletId) continue;
      if (excludeIds != null && excludeIds.contains(entry.id)) continue;
      total += entry.microUsd;
      byKind[entry.kind] = (byKind[entry.kind] ?? 0) + entry.microUsd;
      // Record per-source attribution. Empty source falls back to
      // a generic label so the row still renders something the user
      // can identify; older entries logged before the source field
      // was added end up under "Unknown".
      final src = entry.source.isNotEmpty ? entry.source : 'Unknown';
      final inner =
          byKindAndSource.putIfAbsent(entry.kind, () => <String, int>{});
      inner[src] = (inner[src] ?? 0) + entry.microUsd;
      count++;
    }
    return FeeSummary(
      totalMicroUsd: total,
      byKind: byKind,
      count: count,
      byKindAndSource: byKindAndSource,
    );
  }

  /// All entries newest-first, optionally filtered by kind. Used by
  /// the drill-down list when the user taps a row in the breakdown.
  ///
  /// [walletId] scopes to one wallet's fees (see `summarize` for the
  /// same caveat about entries with no recorded walletId).
  static List<FeeEntry> snapshot({
    Set<FeeKind>? kinds,
    DateTime? from,
    DateTime? to,
    String? walletId,
  }) {
    final box = _box;
    if (box == null) return const [];
    final out = <FeeEntry>[];
    final fromMs = from?.millisecondsSinceEpoch;
    final toMs = to?.millisecondsSinceEpoch;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = _decode(key.toString(), raw);
      if (entry == null) continue;
      if (kinds != null && !kinds.contains(entry.kind)) continue;
      if (fromMs != null && entry.ts < fromMs) continue;
      if (toMs != null && entry.ts > toMs) continue;
      if (walletId != null && entry.walletId != walletId) continue;
      out.add(entry);
    }
    out.sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }

  /// Drop entries older than [olderThan] from now. Optional retention
  /// hook — call sites can leave fees alone forever and the box will
  /// still be small (~200B × hundreds of entries = single-digit MB
  /// over a year of heavy use), but exposing prune lets a "Clear fee
  /// history" affordance live in settings later.
  static int prune({required Duration olderThan}) {
    final box = _box;
    if (box == null) return 0;
    final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    final toDelete = <dynamic>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final entry = _decode(key.toString(), raw);
      if (entry == null) {
        // Garbage entry — clean it up too.
        toDelete.add(key);
        continue;
      }
      if (entry.ts < cutoff) toDelete.add(key);
    }
    if (toDelete.isEmpty) return 0;
    box.deleteAll(toDelete);
    return toDelete.length;
  }

  static FeeEntry? _decode(String id, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return FeeEntry.fromJson(id, decoded);
    } catch (_) {
      return null;
    }
  }
}
