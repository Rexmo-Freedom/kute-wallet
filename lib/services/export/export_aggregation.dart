// lib/services/export/export_aggregation.dart
//
// Pure-Dart aggregation layer for the transaction export (PDF + CSV).
// Everything the two renderers need — the denormalised row shape, the
// period filter, per-venue merging and the summary totals — lives here
// with NO Flutter imports so it stays unit-testable.
//
// Rows come from two places:
//   * wallet activity (Bitcoin, Lightning/Spark, Polymarket, USDB,
//     ramp / swap rows) — enriched by TransactionPdfExport from the
//     same Transaction container the Activity feed renders;
//   * Hyperliquid fills — mapped by [ExportRow.fromHlFill] from the
//     hyperliquidUserFillsProvider list the Trading history uses.
//
// The summary reports ONLY what the app's own data actually carries:
// Hyperliquid realized PnL is the sum of each fill's exchange-reported
// closedPnl; Predictions figures are the period's USDC activity by
// type. No cost-basis accounting is invented here.

import 'package:kute/models/hyperliquid_market.dart' show HlFill;

/// Venue buckets used for sectioning the PDF ledger and the CSV
/// `Venue` column.
class ExportVenue {
  static const wallet = 'Wallet';
  static const trading = 'Trading';
  static const predictions = 'Predictions';
  static const other = 'Other';
}

/// One export row = one activity entry. Superset of what the PDF
/// ledger tables and the CSV columns render. Sats-denominated rows
/// carry [sats]; USD-denominated rows (Predictions, Trading, USDB)
/// carry [usdcAmount] and leave [sats] at 0 — the two are never mixed
/// into one number.
class ExportRow {
  final DateTime date;

  /// Venue bucket — one of the [ExportVenue] constants.
  final String venue;

  /// User-facing label, e.g. "Bitcoin Sent", "Lightning Received",
  /// "Open Long".
  final String type;

  /// Bucket for the category table / charts (Bitcoin, Lightning,
  /// Spark, Predictions, USDB, Exchange…).
  final String category;

  /// Rail label printed alongside the row — Lightning / Onchain /
  /// Spark / Polygon / Hyperliquid / Exchange.
  final String rail;
  final int sats;
  final bool isSent;
  final String status;
  final String txid;
  final String walletName;
  final String walletId;
  final String walletType;

  /// USD-denominated amount for non-BTC rows (Polymarket USDC, USDB,
  /// Hyperliquid notional). 0 for BTC rows.
  final double usdcAmount;
  final String? marketTitle;
  final String? address;
  final String? note;

  /// Order details are informational; wallet settlement rows carry cash flow.
  final String? sourceAsset;
  final String? sourceAmount;
  final String? destinationAsset;
  final String? destinationAmount;
  final String? sourceNetwork;
  final String? destinationNetwork;
  bool get isOrder => sourceAsset != null && destinationAsset != null;
  String get orderAmounts => [
        '${sourceAmount?.isNotEmpty == true ? sourceAmount : "Unknown"} $sourceAsset',
        '${destinationAmount?.isNotEmpty == true ? destinationAmount : "Not recorded"} $destinationAsset',
      ].join(' -> ');

  /// On-chain / Lightning fee in sats when known.
  final int feeSats;

  /// USD-denominated fee (Hyperliquid trading fee). 0 when N/A.
  final double feeUsd;

  /// Exchange-reported realized PnL for this row (Hyperliquid fill
  /// closedPnl). 0 when the venue doesn't report one.
  final double realizedPnlUsd;
  final double? fiatAtTime;
  final int? blockHeight;

  ExportRow({
    required this.date,
    required this.venue,
    required this.type,
    required this.category,
    required this.rail,
    required this.sats,
    required this.isSent,
    required this.status,
    required this.txid,
    required this.walletName,
    required this.walletId,
    required this.walletType,
    this.usdcAmount = 0,
    this.marketTitle,
    this.address,
    this.note,
    this.sourceAsset,
    this.sourceAmount,
    this.destinationAsset,
    this.destinationAmount,
    this.sourceNetwork,
    this.destinationNetwork,
    this.feeSats = 0,
    this.feeUsd = 0,
    this.realizedPnlUsd = 0,
    this.fiatAtTime,
    this.blockHeight,
  });

  /// Short human description used in the ledger tables — market title
  /// for predictions, note when present, otherwise a shortened txid.
  String get description {
    if (marketTitle != null && marketTitle!.isNotEmpty) return marketTitle!;
    if (note != null && note!.isNotEmpty) return note!;
    if (txid.isEmpty) return '';
    if (txid.length <= 18) return txid;
    // ASCII ellipsis on purpose: the PDF renderer must never depend on
    // a glyph outside the embedded font's guaranteed coverage.
    return '${txid.substring(0, 10)}...${txid.substring(txid.length - 6)}';
  }

  /// Maps one Hyperliquid fill onto the export row shape. Amounts are
  /// USD notional (px × sz); the fee and closedPnl come straight from
  /// the exchange payload the Trading history list already renders.
  factory ExportRow.fromHlFill(HlFill fill) {
    final dir = fill.dir.isNotEmpty ? fill.dir : (fill.isBuy ? 'Buy' : 'Sell');
    return ExportRow(
      date: DateTime.fromMillisecondsSinceEpoch(fill.time),
      venue: ExportVenue.trading,
      type: '$dir ${fill.coin}',
      // User copy says Investing; internal identifiers keep trading.
      category: 'Investing',
      rail: 'Hyperliquid',
      sats: 0,
      // Opens/buys move USD into the position, closes/sells bring it
      // back — mirrors how Predictions buys are treated as outflows.
      // Direction label wins over the taker side (a Close Long is an
      // inflow even though the exchange books it as a sell/ask), same
      // rule as _isOpeningFill in hyperliquid_sats_pnl_provider.
      isSent: _fillIsOutflow(fill),
      status: 'Filled',
      txid: fill.hash,
      walletName: 'Hyperliquid',
      walletId: 'hyperliquid',
      walletType: 'Investing',
      usdcAmount: fill.px * fill.sz,
      note: '${_trimNum(fill.sz)} ${fill.coin} @ \$${_trimNum(fill.px)}',
      feeUsd: fill.fee,
      realizedPnlUsd: fill.closedPnl,
    );
  }

  static bool _fillIsOutflow(HlFill f) {
    final dir = f.dir.toLowerCase();
    if (dir.startsWith('open') || dir == 'buy') return true;
    if (dir.startsWith('close') || dir == 'sell' || dir.contains('liquidat')) {
      return false;
    }
    return f.isBuy;
  }

  static String _trimNum(double v) {
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }
}

/// Inclusive period filter. Null bounds mean unbounded on that side.
List<ExportRow> filterRowsByPeriod(
  List<ExportRow> rows, {
  DateTime? start,
  DateTime? end,
}) {
  if (start == null && end == null) return List.of(rows);
  return rows.where((r) {
    if (start != null && r.date.isBefore(start)) return false;
    if (end != null && r.date.isAfter(end)) return false;
    return true;
  }).toList();
}

/// Sats balance delta contributed by [rows] (received minus sent).
/// Fees are not subtracted separately — they are embedded in sent
/// amounts the same way the app's running-balance ledger treats them.
int netSatsFlow(Iterable<ExportRow> rows) {
  var net = 0;
  for (final r in rows) {
    net += r.isSent ? -r.sats : r.sats;
  }
  return net;
}

/// Opening balance for a period = net flow of every row strictly
/// before [start]. Derivable only from the exported wallets' own
/// history, which is exactly what the report covers.
int openingBalanceSats(List<ExportRow> allRows, DateTime? start) {
  if (start == null) return 0;
  return netSatsFlow(allRows.where((r) => r.date.isBefore(start)));
}

/// Per-venue totals for the summary page and the CSV recap.
class VenueTotals {
  int receivedSats = 0;
  int sentSats = 0;
  int feeSats = 0;
  double usdIn = 0;
  double usdOut = 0;
  double feeUsd = 0;
  double realizedPnlUsd = 0;
  int count = 0;

  int get netSats => receivedSats - sentSats;
  double get netUsd => usdIn - usdOut;
}

/// Predictions activity breakdown by type — the period's USDC cash
/// movements, reported as such (not a cost-basis P&L).
class PredictionsBreakdown {
  double depositsUsd = 0;
  double withdrawalsUsd = 0;
  double betsPlacedUsd = 0;
  double positionsSoldUsd = 0;
  double claimsUsd = 0;

  /// Cash returned by markets (sells + claims) minus cash staked
  /// (bets placed) inside the period. A trading-result proxy only when
  /// the bets both opened and settled inside the period.
  double get netTradingUsd => positionsSoldUsd + claimsUsd - betsPlacedUsd;

  bool get hasActivity =>
      depositsUsd > 0 ||
      withdrawalsUsd > 0 ||
      betsPlacedUsd > 0 ||
      positionsSoldUsd > 0 ||
      claimsUsd > 0;
}

/// Everything the summary page renders, computed in one pass.
class ExportSummary {
  final int rowCount;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final int totalReceivedSats;
  final int totalSentSats;
  final int totalFeeSats;
  final double totalFeeUsd;
  final int netSats;
  final int openingSats;
  final int closingSats;

  /// Sum of Hyperliquid fill closedPnl over the period — the
  /// exchange's own realized PnL figure for closed positions.
  final double hlRealizedPnlUsd;
  final double hlFeesUsd;
  final int hlFillCount;
  final PredictionsBreakdown predictions;
  final Map<String, VenueTotals> byVenue;

  const ExportSummary({
    required this.rowCount,
    required this.firstDate,
    required this.lastDate,
    required this.totalReceivedSats,
    required this.totalSentSats,
    required this.totalFeeSats,
    required this.totalFeeUsd,
    required this.netSats,
    required this.openingSats,
    required this.closingSats,
    required this.hlRealizedPnlUsd,
    required this.hlFeesUsd,
    required this.hlFillCount,
    required this.predictions,
    required this.byVenue,
  });

  List<String> get coveredVenues {
    const order = [
      ExportVenue.wallet,
      ExportVenue.trading,
      ExportVenue.predictions,
      ExportVenue.other,
    ];
    return order.where((v) => (byVenue[v]?.count ?? 0) > 0).toList();
  }
}

/// One-pass summary of the period's rows. [openingSats] should come
/// from [openingBalanceSats] over the UNFILTERED row set so closing =
/// opening + period net stays consistent.
ExportSummary summarizeRows(
  List<ExportRow> periodRows, {
  int openingSats = 0,
}) {
  var receivedSats = 0, sentSats = 0, feeSats = 0;
  var feeUsd = 0.0;
  var hlPnl = 0.0, hlFees = 0.0;
  var hlFills = 0;
  final predictions = PredictionsBreakdown();
  final byVenue = <String, VenueTotals>{};
  DateTime? first, last;

  for (final r in periodRows) {
    if (first == null || r.date.isBefore(first)) first = r.date;
    if (last == null || r.date.isAfter(last)) last = r.date;

    if (r.isSent) {
      sentSats += r.sats;
    } else {
      receivedSats += r.sats;
    }
    feeSats += r.feeSats;
    feeUsd += r.feeUsd;

    final v = byVenue.putIfAbsent(r.venue, VenueTotals.new);
    v.count++;
    if (r.isSent) {
      v.sentSats += r.sats;
      v.usdOut += r.usdcAmount;
    } else {
      v.receivedSats += r.sats;
      v.usdIn += r.usdcAmount;
    }
    v.feeSats += r.feeSats;
    v.feeUsd += r.feeUsd;
    v.realizedPnlUsd += r.realizedPnlUsd;

    if (r.venue == ExportVenue.trading) {
      hlPnl += r.realizedPnlUsd;
      hlFees += r.feeUsd;
      hlFills++;
    }

    if (r.venue == ExportVenue.predictions) {
      final t = r.type.toLowerCase();
      if (t.contains('deposit')) {
        predictions.depositsUsd += r.usdcAmount;
      } else if (t.contains('withdraw')) {
        predictions.withdrawalsUsd += r.usdcAmount;
      } else if (t.contains('claim') || t.contains('redeem')) {
        predictions.claimsUsd += r.usdcAmount;
      } else if (t.contains('sell')) {
        predictions.positionsSoldUsd += r.usdcAmount;
      } else if (t.contains('buy')) {
        predictions.betsPlacedUsd += r.usdcAmount;
      }
    }
  }

  final netSats = receivedSats - sentSats;
  return ExportSummary(
    rowCount: periodRows.length,
    firstDate: first,
    lastDate: last,
    totalReceivedSats: receivedSats,
    totalSentSats: sentSats,
    totalFeeSats: feeSats,
    totalFeeUsd: feeUsd,
    netSats: netSats,
    openingSats: openingSats,
    closingSats: openingSats + netSats,
    hlRealizedPnlUsd: hlPnl,
    hlFeesUsd: hlFees,
    hlFillCount: hlFills,
    predictions: predictions,
    byVenue: byVenue,
  );
}

/// Groups the period rows by venue in presentation order, newest
/// first inside each venue — the shape the PDF ledger sections and
/// the CSV venue column both consume.
Map<String, List<ExportRow>> groupRowsByVenue(List<ExportRow> rows) {
  const order = [
    ExportVenue.wallet,
    ExportVenue.trading,
    ExportVenue.predictions,
    ExportVenue.other,
  ];
  final grouped = <String, List<ExportRow>>{};
  for (final r in rows) {
    grouped.putIfAbsent(r.venue, () => []).add(r);
  }
  final out = <String, List<ExportRow>>{};
  for (final v in order) {
    final list = grouped.remove(v);
    if (list == null || list.isEmpty) continue;
    list.sort((a, b) => b.date.compareTo(a.date));
    out[v] = list;
  }
  // Any venue outside the canonical order still lands at the end.
  for (final e in grouped.entries) {
    e.value.sort((a, b) => b.date.compareTo(a.date));
    out[e.key] = e.value;
  }
  return out;
}

/// The disclaimer sentence the export carries everywhere (summary
/// page, PDF footers, CSV header comment, share subject). Exact
/// product requirement — keep it verbatim.
const String exportDisclaimer =
    'This report is for personal orientation only. It is not a tax '
    'document and may be incomplete or inaccurate.';
