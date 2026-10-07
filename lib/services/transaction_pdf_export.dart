import 'dart:convert' show utf8;
import 'package:kute/l10n/l10n.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:kute/models/onchain_types.dart' hide Transaction;
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/polymarket_model.dart' show ActivityType;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/export/export_aggregation.dart';
import 'package:kute/services/tx_fiat_snapshot_service.dart';

// ──────────────────────────────────────────────────────────────────
//  PALETTE: the app's light theme tokens, on paper.
//  Near-black monochrome primary, quiet grey hairlines, light grey
//  surface cards. marketUp / marketDown are reserved for signed
//  amounts. The only orange on the page is the mascot artwork.
// ──────────────────────────────────────────────────────────────────
const _kInk = PdfColor.fromInt(0xFF111114);
const _kText = PdfColor.fromInt(0xFF1D2024);
const _kTextSecondary = PdfColor.fromInt(0xFF626972);
const _kTextTertiary = PdfColor.fromInt(0xFF9CA2AB);
const _kHairline = PdfColor.fromInt(0xFFE2E5EA);
const _kHairlineSubtle = PdfColor.fromInt(0xFFEAECEF);
const _kSurface = PdfColor.fromInt(0xFFF3F5F8);
const _kSurfaceDeep = PdfColor.fromInt(0xFFE6E9EE);
const _kMarketUp = PdfColor.fromInt(0xFF1FA663);
const _kMarketDown = PdfColor.fromInt(0xFFD9485A);

/// Monochrome ramp for the allocation donut and the type bars.
const _kRamp = [
  PdfColor.fromInt(0xFF111114),
  PdfColor.fromInt(0xFF3F444B),
  PdfColor.fromInt(0xFF6B717A),
  PdfColor.fromInt(0xFF9CA2AB),
  PdfColor.fromInt(0xFFC3C8CF),
  PdfColor.fromInt(0xFFDDE1E6),
];

/// Bundled Inter static instances (pubspec `fonts:` entry). These are
/// the same files google_fonts serves the app UI, so the PDF's glyph
/// coverage matches what the user sees on screen.
const _kFontRegular = 'lib/assets/fonts/Inter-Regular.ttf';
const _kFontSemiBold = 'lib/assets/fonts/Inter-SemiBold.ttf';
const _kFontBold = 'lib/assets/fonts/Inter-Bold.ttf';
const _kMascotPng = 'lib/assets/kute_logo.png';

/// Fonts and artwork the report embeds. The app loads them from the
/// asset bundle with [TransactionPdfExport.loadReportAssets]; tests
/// build one from bytes on disk, or pass an empty one to exercise the
/// built-in font fallback (all generator copy is ASCII, so the
/// fallback never renders tofu either).
class ReportAssets {
  final pw.Font? regular;
  final pw.Font? semiBold;
  final pw.Font? bold;
  final pw.MemoryImage? mascot;

  const ReportAssets({this.regular, this.semiBold, this.bold, this.mascot});

  factory ReportAssets.fromBytes({
    Uint8List? regular,
    Uint8List? semiBold,
    Uint8List? bold,
    Uint8List? mascot,
  }) {
    pw.Font? ttf(Uint8List? b) =>
        b == null ? null : pw.Font.ttf(ByteData.sublistView(b));
    return ReportAssets(
      regular: ttf(regular),
      semiBold: ttf(semiBold),
      bold: ttf(bold),
      mascot: mascot == null ? null : pw.MemoryImage(mascot),
    );
  }

  bool get hasFonts => regular != null && bold != null;
}

class TransactionPdfExport {
  // ──────────────────────────────────────────────────────────────
  // MAIN ENTRY POINT
  // ──────────────────────────────────────────────────────────────
  static Future<void> exportAndShare({
    required Map<String, Transaction> walletTransactions,
    required List<WalletConfig> wallets,
    required String btcFormat,
    required String currency,
    required double? currentBtcPrice,
    double polymarketUsdcBalance = 0,
    List<HlFill> hlFills = const [],
    DateTime? periodStart,
    DateTime? periodEnd,
    AppLocalizations? l10n,
  }) async {
    final rows = collectRows(
      walletTransactions: walletTransactions,
      wallets: wallets,
      currentBtcPrice: currentBtcPrice,
      hlFills: hlFills,
    );
    final assets = await loadReportAssets();
    final bytes = await buildReportBytes(
      rows: rows,
      wallets: wallets,
      btcFormat: btcFormat,
      currentBtcPrice: currentBtcPrice,
      polymarketUsdcBalance: polymarketUsdcBalance,
      periodStart: periodStart,
      periodEnd: periodEnd,
      assets: assets,
      l10n: l10n,
    );

    // ── Save and Share ──
    final copy = l10n ?? l10nForLanguage('en');
    final shareText = copy.pdfShareSubject(copy.pdfDisclaimer);
    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/kute_activity_report_$ts.pdf');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: shareText,
        text: shareText,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
  }

  /// Loads the bundled Inter faces and the mascot. Each piece is
  /// optional: a missing asset degrades to the built-in Helvetica (or
  /// a text-only header) instead of failing the export.
  static Future<ReportAssets> loadReportAssets() async {
    Future<pw.Font?> font(String path) async {
      try {
        return pw.Font.ttf(await rootBundle.load(path));
      } catch (_) {
        return null;
      }
    }

    pw.MemoryImage? mascot;
    try {
      final data = await rootBundle.load(_kMascotPng);
      mascot = pw.MemoryImage(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {}

    return ReportAssets(
      regular: await font(_kFontRegular),
      semiBold: await font(_kFontSemiBold),
      bold: await font(_kFontBold),
      mascot: mascot,
    );
  }

  /// Every activity entry across [wallets] plus the Hyperliquid fills,
  /// unfiltered. Both exporters start from this list; the period
  /// filter is applied downstream so the opening balance can still be
  /// derived from the full history.
  static List<ExportRow> collectRows({
    required Map<String, Transaction> walletTransactions,
    required List<WalletConfig> wallets,
    required double? currentBtcPrice,
    List<HlFill> hlFills = const [],
  }) {
    final rows = <ExportRow>[];
    for (final wallet in wallets) {
      final txData = walletTransactions[wallet.id];
      if (txData == null) continue;
      // allTransactionsWithSwaps includes token transfers and swap
      // orders, same as the Activity feed.
      for (final tx in txData.allTransactionsWithSwaps) {
        final enriched = _enrich(tx, wallet, currentBtcPrice);
        if (enriched != null) rows.add(enriched);
      }
    }
    rows.addAll(hlFills.map(ExportRow.fromHlFill));
    return rows;
  }

  /// Renders the Activity Report and returns the PDF bytes. Pure with
  /// respect to platform plumbing (no file system, no share sheet), so
  /// it runs headlessly in unit tests.
  ///
  /// [rows] is the UNFILTERED history (see [collectRows]); the period
  /// filter is applied here so closing = opening + period net stays
  /// honest. Throws when the period contains no rows.
  static Future<Uint8List> buildReportBytes({
    required List<ExportRow> rows,
    required List<WalletConfig> wallets,
    required String btcFormat,
    required double? currentBtcPrice,
    double polymarketUsdcBalance = 0,
    DateTime? periodStart,
    DateTime? periodEnd,
    ReportAssets assets = const ReportAssets(),
    DateTime? generatedAt,
    AppLocalizations? l10n,
  }) async {
    final rollup = _rollupWallets(rows, wallets, polymarketUsdcBalance);

    // Opening balance is derived from the UNFILTERED history so
    // closing = opening + period net stays honest.
    final opening = openingBalanceSats(rows, periodStart);
    final periodRows = filterRowsByPeriod(rows, start: periodStart, end: periodEnd)
      ..sort((a, b) => b.date.compareTo(a.date));

    if (periodRows.isEmpty) {
      throw Exception('No transactions to export');
    }

    final summary = summarizeRows(periodRows, openingSats: opening);
    final metrics = _computeMetrics(periodRows, wallets);

    final r = _ReportRenderer(
      l: l10n ?? l10nForLanguage('en'),
      assets: assets,
      btcFormat: btcFormat,
      btcPrice: currentBtcPrice,
      now: generatedAt ?? DateTime.now(),
    );

    final pdf = pw.Document(
      title: 'kute Activity Report',
      author: 'kute Wallet',
      creator: 'kute',
      theme: r.theme,
    );

    // ── PAGE 1: COVER & EXECUTIVE SUMMARY ──
    pdf.addPage(r.coverPage(metrics, summary, periodStart, periodEnd));
    // ── PAGE 2: YEARLY BREAKDOWN ──
    pdf.addPage(r.yearlyPage(metrics));
    // ── PAGE 3: PORTFOLIO OVERVIEW ──
    pdf.addPage(r.portfolioPage(wallets, rollup, periodRows, metrics));
    // ── PAGE 4: ACTIVITY & PERFORMANCE ──
    pdf.addPage(r.activityPage(periodRows, metrics));
    // ── PAGES 5+: VENUE LEDGER TABLES ──
    pdf.addPage(r.ledgerPages(periodRows, metrics));

    return pdf.save();
  }

  // ──────────────────────────────────────────────────────────────
  // CSV EXPORT
  // ──────────────────────────────────────────────────────────────

  /// Exports all transactions (including Polymarket) as a CSV file.
  /// Mirrors the PDF: every per-tx field the PDF surfaces lands in
  /// the spreadsheet too, so a tax tool can re-derive what the PDF
  /// shows without parsing it. Written as UTF-8 without a BOM.
  static Future<void> exportCsv({
    required Map<String, Transaction> walletTransactions,
    required List<WalletConfig> wallets,
    required String btcFormat,
    required double? currentBtcPrice,
    List<HlFill> hlFills = const [],
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final allTxs = collectRows(
      walletTransactions: walletTransactions,
      wallets: wallets,
      currentBtcPrice: currentBtcPrice,
      hlFills: hlFills,
    );

    final rows = filterRowsByPeriod(allTxs, start: periodStart, end: periodEnd)
      ..sort((a, b) => b.date.compareTo(a.date));

    if (rows.isEmpty) {
      throw Exception('No transactions to export');
    }

    final csv = buildCsv(
      rows,
      periodStart: periodStart,
      periodEnd: periodEnd,
      currentBtcPrice: currentBtcPrice,
    );

    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/kute_transactions_$ts.csv');
    await file.writeAsString(csv, encoding: utf8, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'kute activity export (CSV). $exportDisclaimer',
        text: 'kute activity export (CSV). $exportDisclaimer',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
  }

  /// The CSV text for [rows] (already period-filtered, newest first).
  static String buildCsv(
    List<ExportRow> rows, {
    DateTime? periodStart,
    DateTime? periodEnd,
    double? currentBtcPrice,
  }) {
    final buf = StringBuffer();
    // Comment header rows: spreadsheet tools show them, parsers that
    // honor '#' skip them, and the disclaimer travels with the data.
    buf.writeln('# kute activity export');
    final from = periodStart ?? rows.last.date;
    final to = periodEnd ?? rows.first.date;
    buf.writeln(
        '# Period: ${DateFormat('yyyy-MM-dd').format(from)} to ${DateFormat('yyyy-MM-dd').format(to)}');
    buf.writeln('# $exportDisclaimer');
    buf.writeln([
      'Date (UTC)',
      'Date (Local)',
      'Venue',
      'Wallet',
      'Wallet Type',
      'Asset',
      'Type',
      'Direction',
      'Amount',
      'Unit',
      'Fee (sats)',
      'Fee (USD)',
      'Realized PnL (USD)',
      'USD at time',
      'USD now',
      'Status',
      'TXID',
      'Counterparty / Address',
      'Note',
      'Market',
      'Block Height',
      'Source Asset',
      'Source Amount',
      'Source Network',
      'Destination Asset',
      'Destination Amount',
      'Destination Network',
    ].map(_csvEscape).join(','));

    for (final tx in rows) {
      // Asset / amount / unit: BTC rows carry sats, stablecoin rows carry
      // their token amount. We never mix the two into a single number (the
      // old export summed USDC rows into the sats column as zeros).
      String asset = '';
      String amount = '';
      String unit = '';
      if (tx.sats > 0) {
        asset = 'BTC';
        amount = tx.sats.toString();
        unit = 'sats';
      } else if (tx.venue == ExportVenue.trading) {
        // Hyperliquid fills: the amount is the USD notional of the
        // fill (px times sz); the size/price detail lives in the Note.
        asset = 'USD';
        amount = tx.usdcAmount.toStringAsFixed(2);
        unit = 'USD';
      } else if (tx.usdcAmount > 0) {
        asset = tx.category == 'USDB' ? 'USDB' : 'USDC';
        amount = tx.usdcAmount.toStringAsFixed(2);
        unit = asset;
      }

      // USD at time = the value RECORDED when the tx was first seen
      // (TxFiatSnapshotService), never re-derived from today's price. Blank
      // when we never captured one; we don't fabricate it. Stablecoins are
      // about one dollar, so the token amount IS the USD value.
      String usdAtTime = '';
      String usdNow = '';
      if (tx.sats > 0) {
        final snap = TxFiatSnapshotService.snapshot(tx.txid);
        if (snap != null && snap.usd > 0) {
          usdAtTime = snap.usd.toStringAsFixed(2);
        }
        if (currentBtcPrice != null) {
          usdNow = ((tx.sats / 1e8) * currentBtcPrice).toStringAsFixed(2);
        }
      } else if (tx.usdcAmount > 0) {
        usdAtTime = tx.usdcAmount.toStringAsFixed(2);
        usdNow = tx.usdcAmount.toStringAsFixed(2);
      }

      buf.writeln([
        DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.date.toUtc()),
        DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.date),
        tx.venue.toLowerCase(),
        tx.walletName,
        tx.walletType,
        asset,
        tx.type,
        tx.isOrder ? 'Order' : (tx.isSent ? 'Out' : 'In'),
        amount,
        unit,
        tx.feeSats > 0 ? tx.feeSats.toString() : '',
        tx.feeUsd > 0.0005 ? tx.feeUsd.toStringAsFixed(4) : '',
        tx.realizedPnlUsd.abs() >= 0.005
            ? tx.realizedPnlUsd.toStringAsFixed(2)
            : '',
        usdAtTime,
        usdNow,
        tx.status,
        tx.txid,
        tx.address ?? '',
        tx.note ?? '',
        tx.marketTitle ?? '',
        tx.blockHeight?.toString() ?? '',
        tx.sourceAsset ?? '',
        tx.sourceAmount ?? '',
        tx.sourceNetwork ?? '',
        tx.destinationAsset ?? '',
        tx.destinationAmount ?? '',
        tx.destinationNetwork ?? '',
      ].map(_csvEscape).join(','));
    }
    return buf.toString();
  }

  static String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // ──────────────────────────────────────────────────────────────
  //  AMOUNT FORMATTING (ASCII only, by design)
  // ──────────────────────────────────────────────────────────────

  /// Bitcoin amount as plain words: "12,345 sats" or "0.00012345 BTC".
  /// No currency sign, so the output never depends on a glyph the
  /// embedded (or fallback) font might lack, and it reads better in
  /// print anyway.
  static String formatBtc(int sats, String format) {
    if (format == 'sats') {
      final n = NumberFormat('#,##0').format(sats);
      return sats.abs() == 1 ? '$n sat' : '$n sats';
    }
    // Integer math to avoid double precision loss: split sats into
    // whole BTC and the 8-digit fractional part.
    final abs = sats.abs();
    final whole = abs ~/ 100000000;
    final frac = abs % 100000000;
    return '${sats < 0 ? '-' : ''}$whole.${frac.toString().padLeft(8, '0')} BTC';
  }

  // ══════════════════════════════════════════════════════════════
  //  ENRICHMENT: single source of truth for both PDF and CSV
  // ══════════════════════════════════════════════════════════════
  /// Materialise a [BaseTransaction] subclass into the denormalised
  /// row shape both exporters render from. Returns null for the
  /// (unlikely) case where a future SDK type isn't handled; the
  /// caller drops those rows rather than render a half-empty entry.
  @visibleForTesting
  static ExportRow? enrichForTest(BaseTransaction tx, WalletConfig wallet,
          {double? currentBtcPrice}) =>
      _enrich(tx, wallet, currentBtcPrice);

  static ExportRow? _enrich(
    BaseTransaction tx,
    WalletConfig wallet,
    double? currentBtcPrice,
  ) {
    final walletName = wallet.name.isNotEmpty ? wallet.name : 'Wallet';
    final walletType = _walletTypeLabel(wallet);

    if (tx is BitcoinTransaction) {
      final details = tx.btcDetails;
      final isSent = tx.sentSats > tx.receivedSats;
      final sats = (tx.sentSats - tx.receivedSats).abs();
      // The fee belongs to whoever funded the inputs. On a plain receive
      // that is the sender, so it is not a fee this wallet paid and must
      // not reach "Fees paid".
      final fee = tx.sentSats > 0 ? (details?.fee?.toSat() ?? 0) : 0;
      String status;
      int? blockHeight;
      DateTime txDate = tx.timestamp;
      if (details != null) {
        final pos = details.chainPosition;
        if (pos is ConfirmedChainPosition) {
          status = 'Confirmed';
          blockHeight = pos.confirmationBlockTime.blockId.height;
          // SDK reports block time in seconds; prefer it over the
          // wrapper's cached timestamp so the ledger shows the real
          // settlement time, not when we first saw the tx.
          final blockTime = pos.confirmationBlockTime.confirmationTime;
          if (blockTime > 0) {
            txDate = DateTime.fromMillisecondsSinceEpoch(blockTime * 1000);
          }
        } else {
          status = 'Pending';
        }
      } else {
        status = tx.isConfirmed ? 'Confirmed' : 'Pending';
      }
      final txid = details != null ? details.txid.toString() : tx.id;
      return ExportRow(
        date: txDate,
        venue: ExportVenue.wallet,
        type: isSent ? 'Bitcoin Sent' : 'Bitcoin Received',
        category: 'Bitcoin',
        rail: 'Onchain',
        sats: sats,
        isSent: isSent,
        status: status,
        txid: txid,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        feeSats: fee,
        blockHeight: blockHeight,
        fiatAtTime: currentBtcPrice != null
            ? (sats / 1e8) * currentBtcPrice
            : null,
      );
    }

    if (tx is SparkTransaction) {
      final isSent = tx.type == TransactionType.sent;
      final railLabel = _sparkTypeLabel(tx.sparkType);
      final live = tx.details;
      final fees = live?.fees.toInt() ?? 0;
      String? note;
      String? address;
      if (live != null) {
        final details = live.details;
        if (details is breez.PaymentDetails_Lightning) {
          note = details.description;
          address = details.destinationPubkey;
        }
      }
      final status = live?.status.name ?? (tx.isPending ? 'pending' : 'completed');
      final humanStatus = status.isNotEmpty
          ? '${status[0].toUpperCase()}${status.substring(1)}'
          : status;
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.wallet,
        type: '$railLabel ${isSent ? 'Sent' : 'Received'}',
        category: railLabel,
        rail: railLabel,
        sats: tx.amountSats,
        isSent: isSent,
        status: humanStatus,
        txid: tx.id,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        feeSats: fees,
        note: note,
        address: address,
        fiatAtTime: currentBtcPrice != null
            ? (tx.amountSats / 1e8) * currentBtcPrice
            : null,
      );
    }

    if (tx is SparkUnclaimedDeposit) {
      final sats = tx.amount.toInt();
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.wallet,
        type: 'Unclaimed Deposit',
        category: 'Bitcoin',
        rail: 'Onchain',
        sats: sats,
        isSent: false,
        status: 'Unclaimed',
        txid: tx.txid,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        fiatAtTime: currentBtcPrice != null
            ? (sats / 1e8) * currentBtcPrice
            : null,
      );
    }

    if (tx is MempoolAddressTransaction) {
      final isSent = tx.details.balanceChange < 0;
      final sats = tx.details.balanceChange.abs();
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.wallet,
        type: isSent ? 'Bitcoin Sent' : 'Bitcoin Received',
        category: 'Bitcoin',
        rail: 'Onchain',
        sats: sats,
        isSent: isSent,
        status: tx.isConfirmed ? 'Confirmed' : 'Pending',
        txid: tx.details.txid,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        // A receive's fee was the sender's (see the BDK row above).
        feeSats: isSent ? tx.details.fee : 0,
        blockHeight: tx.details.blockHeight,
        fiatAtTime: currentBtcPrice != null
            ? (sats / 1e8) * currentBtcPrice
            : null,
      );
    }

    if (tx is UsdbTokenTransaction) {
      final isSent = tx.type == TransactionType.sent;
      final fee = tx.details.fees.toInt();
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.other,
        type: isSent ? 'USDB Sent' : 'USDB Received',
        category: 'USDB',
        rail: 'Spark Token',
        sats: 0,
        isSent: isSent,
        status: tx.isConfirmed ? 'Confirmed' : 'Pending',
        txid: tx.id,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        usdcAmount: tx.amount / 1000000,
        feeSats: fee,
      );
    }

    if (tx is SwapOrderTransaction) {
      final order = tx.details;
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.other,
        type:
            '${order.providerName} ${order.isCashAppPurchase ? "Purchase" : "Swap"}',
        category: 'Exchange',
        rail: '${order.networkFrom} to ${order.networkTo}',
        sats: 0,
        isSent: false,
        status: tx.isComplete ? 'Completed' : order.status,
        txid: tx.id,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        address: order.withdrawalAddress,
        sourceAsset: order.coinFrom,
        sourceAmount: order.depositAmount,
        sourceNetwork: order.networkFrom,
        destinationAsset: order.coinTo,
        destinationAmount: order.withdrawalAmount,
        destinationNetwork: order.networkTo,
        note: '${order.networkFrom} to ${order.networkTo}',
      );
    }

    if (tx is OutlogicTransaction) {
      final order = tx.details;
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.other,
        type: 'Bank ${tx.isBuy ? "Purchase" : "Withdrawal"}',
        category: 'Exchange',
        rail: order.destinationType,
        sats: 0,
        isSent: false,
        status: order.status,
        txid: tx.id,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        sourceAsset: order.fromAsset,
        sourceAmount: order.fromAmount.toString(),
        destinationAsset: order.toAsset,
        destinationAmount: order.trade?.toAmount.toString(),
      );
    }

    if (tx is SparkPendingDeposit) {
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.wallet,
        type: 'Bitcoin Deposit',
        category: 'Bitcoin',
        rail: 'Onchain',
        sats: tx.amount.toInt(),
        isSent: false,
        status: 'Pending',
        txid: tx.id,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
      );
    }

    if (tx is PolymarketUsdcReceive) {
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.predictions,
        type: 'Predictions Received',
        category: 'Predictions',
        rail: 'Polygon',
        sats: 0,
        isSent: false,
        status: tx.isConfirmed ? 'Confirmed' : 'Pending',
        txid: tx.id,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        usdcAmount: tx.amount.toDouble(),
        address: tx.fromAddress,
        blockHeight: tx.blockNumber,
      );
    }

    if (tx is PolymarketTransaction) {
      final actType = tx.activityType;
      String type;
      bool isSent;
      switch (actType) {
        case ActivityType.deposit:
          type = 'Predictions Deposit';
          isSent = true;
        case ActivityType.withdraw:
          type = 'Predictions Withdrawal';
          isSent = false;
        case ActivityType.trade:
          final side = tx.activity.side?.toUpperCase() ?? '';
          isSent = side == 'BUY';
          final outcome = tx.activity.outcome ?? '';
          type = 'Predictions ${side == 'BUY' ? 'Buy' : 'Sell'}'
              '${outcome.isNotEmpty ? ' ($outcome)' : ''}';
        case ActivityType.redeem:
          type = 'Predictions Claim';
          isSent = false;
        default:
          type = 'Predictions';
          isSent = false;
      }
      return ExportRow(
        date: tx.timestamp,
        venue: ExportVenue.predictions,
        type: type,
        category: 'Predictions',
        rail: 'Polygon',
        sats: 0,
        isSent: isSent,
        status: 'Completed',
        txid: tx.txHash,
        walletName: walletName,
        walletId: wallet.id,
        walletType: walletType,
        usdcAmount: tx.usdcAmount,
        marketTitle: tx.marketTitle,
        note: tx.activity.outcome,
      );
    }

    return null;
  }

  /// Human label for [WalletConfig] flags. Mirrors the wording used
  /// in the wallet picker so users see the same noun in both places.
  static String _walletTypeLabel(WalletConfig w) {
    if (w.isExternalAddress) return 'Tracked';
    if (w.isHardware) return 'Hardware';
    if (w.isWatchOnly) return 'Watch-Only';
    if (w.isSigner) return 'Signer';
    if (w.isPasskey) return 'Passkey';
    return 'Spending';
  }

  static String _sparkTypeLabel(SparkTransactionType type) {
    switch (type) {
      case SparkTransactionType.lightning:
        return 'Lightning';
      case SparkTransactionType.bitcoin:
        return 'Bitcoin';
      case SparkTransactionType.spark:
        return 'Spark';
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  WALLET ROLLUP (balances, USDC, counts) from the unfiltered rows
  // ══════════════════════════════════════════════════════════════
  static _WalletRollup _rollupWallets(
    List<ExportRow> rows,
    List<WalletConfig> wallets,
    double polymarketUsdcBalance,
  ) {
    final sats = {for (final w in wallets) w.id: 0};
    final usdc = {for (final w in wallets) w.id: 0.0};
    final counts = {for (final w in wallets) w.id: 0};

    for (final r in rows) {
      if (!sats.containsKey(r.walletId)) continue;
      sats[r.walletId] = sats[r.walletId]! + (r.isSent ? -r.sats : r.sats);
      counts[r.walletId] = counts[r.walletId]! + 1;
      if (r.venue == ExportVenue.predictions) {
        // USDC flow: deposits add to Polymarket, withdrawals remove,
        // claims add USDC back.
        final t = r.type.toLowerCase();
        if (t.contains('deposit') || t.contains('claim')) {
          usdc[r.walletId] = usdc[r.walletId]! + r.usdcAmount;
        } else if (t.contains('withdraw')) {
          usdc[r.walletId] = usdc[r.walletId]! - r.usdcAmount;
        }
      }
    }

    // Override with the live Polymarket balance when we have one.
    if (polymarketUsdcBalance > 0.01) {
      for (final w in wallets) {
        final hasPredictions = rows.any(
            (r) => r.walletId == w.id && r.venue == ExportVenue.predictions);
        if (hasPredictions) {
          usdc[w.id] = polymarketUsdcBalance;
          break;
        }
      }
    }

    return _WalletRollup(sats: sats, usdc: usdc, txCounts: counts);
  }

  // ══════════════════════════════════════════════════════════════
  //  METRICS COMPUTATION
  // ══════════════════════════════════════════════════════════════
  static _ReportMetrics _computeMetrics(
    List<ExportRow> txs,
    List<WalletConfig> wallets,
  ) {
    int totalReceived = 0, totalSent = 0;
    int largestReceived = 0, largestSent = 0;
    int receiveCount = 0, sendCount = 0, confirmedCount = 0;
    final satsValues = <int>[];
    final monthlyCounts = <String, int>{};
    final walletActivity = <String, int>{};
    final yearlyBreakdown = <int, _YearSummary>{};
    final categoryBreakdown = <String, _CategorySummary>{};
    final txIds = <String>{};

    for (final tx in txs) {
      if (tx.isSent) {
        totalSent += tx.sats;
        sendCount++;
        if (tx.sats > largestSent) largestSent = tx.sats;
      } else {
        totalReceived += tx.sats;
        receiveCount++;
        if (tx.sats > largestReceived) largestReceived = tx.sats;
      }
      if (tx.sats > 0) satsValues.add(tx.sats);

      final s = tx.status.toLowerCase();
      if (s.contains('confirm') || s == 'completed' || s == 'complete') {
        confirmedCount++;
      }

      final monthKey = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;

      walletActivity[tx.walletName] = (walletActivity[tx.walletName] ?? 0) + 1;

      // Yearly breakdown
      final year = tx.date.year;
      yearlyBreakdown.putIfAbsent(year, () => _YearSummary());
      yearlyBreakdown[year]!.txCount++;
      if (tx.isSent) {
        yearlyBreakdown[year]!.sent += tx.sats;
      } else {
        yearlyBreakdown[year]!.received += tx.sats;
      }

      // Category breakdown
      final cat = tx.category.isNotEmpty ? tx.category : 'Other';
      categoryBreakdown.putIfAbsent(cat, () => _CategorySummary());
      categoryBreakdown[cat]!.txCount++;
      if (tx.isSent) {
        categoryBreakdown[cat]!.sent += tx.sats;
      } else {
        categoryBreakdown[cat]!.received += tx.sats;
      }
      if (tx.usdcAmount > 0) {
        if (tx.isSent) {
          categoryBreakdown[cat]!.usdcSent += tx.usdcAmount;
        } else {
          categoryBreakdown[cat]!.usdcReceived += tx.usdcAmount;
        }
      }

      if (tx.txid.isNotEmpty) txIds.add(tx.txid);
    }

    // Quarterly breakdown for most recent year
    final quarterlyBreakdown = <String, _QuarterSummary>{};
    final sortedYears = yearlyBreakdown.keys.toList()..sort();
    if (sortedYears.isNotEmpty) {
      final recentYear = sortedYears.last;
      for (final tx in txs.where((t) => t.date.year == recentYear)) {
        final q = 'Q${((tx.date.month - 1) ~/ 3) + 1}';
        quarterlyBreakdown.putIfAbsent(q, () => _QuarterSummary());
        quarterlyBreakdown[q]!.txCount++;
        if (tx.isSent) {
          quarterlyBreakdown[q]!.sent += tx.sats;
        } else {
          quarterlyBreakdown[q]!.received += tx.sats;
        }
      }
    }

    satsValues.sort();
    final medianSats = satsValues.isNotEmpty
        ? satsValues[satsValues.length ~/ 2]
        : 0;

    final dates = txs.map((t) => t.date).toList();
    final firstDate = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final lastDate = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final daysCovered = max(1, lastDate.difference(firstDate).inDays);

    String mostActiveWallet = '-';
    int maxActivity = 0;
    for (final e in walletActivity.entries) {
      if (e.value > maxActivity) {
        maxActivity = e.value;
        mostActiveWallet = e.key;
      }
    }

    String mostActiveMonth = '-';
    int maxMonthTxs = 0;
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    for (final e in monthlyCounts.entries) {
      if (e.value > maxMonthTxs) {
        maxMonthTxs = e.value;
        final parts = e.key.split('-');
        final m = int.tryParse(parts[1]) ?? 0;
        mostActiveMonth = '${monthNames[m]} ${parts[0]}';
      }
    }

    return _ReportMetrics(
      txCount: txs.length,
      walletCount: wallets.length,
      totalReceived: totalReceived,
      totalSent: totalSent,
      netFlow: totalReceived - totalSent,
      largestTx: max(largestReceived, largestSent),
      largestReceived: largestReceived,
      largestSent: largestSent,
      medianTxSize: medianSats,
      receiveCount: receiveCount,
      sendCount: sendCount,
      confirmedCount: confirmedCount,
      firstTxDate: firstDate,
      lastTxDate: lastDate,
      daysCovered: daysCovered,
      mostActiveWallet: mostActiveWallet,
      mostActiveMonth: mostActiveMonth,
      activeMonths: monthlyCounts.length,
      yearlyBreakdown: yearlyBreakdown,
      quarterlyBreakdown: quarterlyBreakdown,
      categoryBreakdown: categoryBreakdown,
      uniqueTxIds: txIds.length,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  SHARED FORMATTERS (ASCII only)
// ══════════════════════════════════════════════════════════════════
String _fmtUsd(int sats, double btcPrice) {
  final usd = (sats / 100000000.0) * btcPrice;
  if (usd.abs() >= 1000000) {
    return '\$${(usd / 1000000).toStringAsFixed(2)}M';
  } else if (usd.abs() >= 1000) {
    return '\$${NumberFormat('#,##0').format(usd)}';
  } else {
    return '\$${usd.toStringAsFixed(2)}';
  }
}

String _signedUsd(double v) =>
    '${v >= 0 ? '+' : '-'}\$${v.abs().toStringAsFixed(2)}';

String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// User-facing label for a venue bucket. User copy says Investing;
/// internal identifiers keep the trading key.
String _venueDisplayLabel(AppLocalizations l, String venue) {
  switch (venue) {
    case ExportVenue.wallet:
      return l.pdfWallet;
    case ExportVenue.trading:
      return l.pdfVenueInvesting;
    case ExportVenue.predictions:
      return l.pdfVenuePredictions;
    default:
      return l.pdfOther;
  }
}

// ══════════════════════════════════════════════════════════════════
//  RENDERER: every page of the report, in the app's visual language
// ══════════════════════════════════════════════════════════════════
class _ReportRenderer {
  _ReportRenderer({
    required this.l,
    required this.assets,
    required this.btcFormat,
    required this.btcPrice,
    required this.now,
  })  : _regular = assets.regular ?? pw.Font.helvetica(),
        _semi = assets.semiBold ?? assets.bold ?? pw.Font.helveticaBold(),
        _bold = assets.bold ?? assets.semiBold ?? pw.Font.helveticaBold();

  /// Copy for the report, in the language the export was started in.
  final AppLocalizations l;
  final ReportAssets assets;
  final String btcFormat;
  final double? btcPrice;
  final DateTime now;

  final pw.Font _regular;
  final pw.Font _semi;
  final pw.Font _bold;

  /// Row types, categories and statuses are stored in English (the CSV
  /// and the summaries group on them); the report shows them in [l]'s
  /// language. Names such as wallets, markets and rails pass through.
  String _rowWord(String word) {
    switch (word) {
      case 'Unclaimed Deposit':
        return l.pdfRowUnclaimedDeposit;
      case 'Bank Purchase':
        return l.pdfRowBankPurchase;
      case 'Bank Withdrawal':
        return l.pdfRowBankWithdrawal;
      case 'Bitcoin Deposit':
        return l.pdfRowBitcoinDeposit;
      case 'Predictions Received':
        return l.pdfRowPredictionsReceived;
      case 'Predictions Deposit':
        return l.pdfRowPredictionsDeposit;
      case 'Predictions Withdrawal':
        return l.pdfRowPredictionsWithdrawal;
      case 'Predictions Buy':
        return l.pdfRowPredictionsBuy;
      case 'Predictions Sell':
        return l.pdfRowPredictionsSell;
      case 'Predictions Claim':
        return l.pdfRowPredictionsClaim;
      case 'Predictions':
        return l.predictions;
      case 'Investing':
        return l.trading;
      case 'Exchange':
        return l.pdfCatExchange;
      case 'Other':
        return l.pdfOther;
      case 'Confirmed':
        return l.pdfStatusConfirmed;
      case 'Pending':
        return l.pdfStatusPending;
      case 'Unclaimed':
        return l.pdfStatusUnclaimed;
      case 'Completed':
        return l.pdfStatusCompleted;
      case 'Filled':
        return l.pdfStatusFilled;
      case 'Failed':
        return l.pdfStatusFailed;
    }
    if (word.endsWith(' Sent')) {
      return l.pdfRowSent(word.substring(0, word.length - 5));
    }
    if (word.endsWith(' Received')) {
      return l.pdfRowReceived(word.substring(0, word.length - 9));
    }
    if (word.endsWith(' Purchase')) {
      return l.pdfRowPurchase(word.substring(0, word.length - 9));
    }
    if (word.endsWith(' Swap')) {
      return l.pdfRowSwap(word.substring(0, word.length - 5));
    }
    return word;
  }

  static const _marginX = 44.0;
  static const _date = 'MMM d, yyyy';

  /// Every text style resolves to one of the three embedded faces.
  /// Italic is mapped onto regular on purpose: there is no bundled
  /// italic and the Type 1 fallback would otherwise mix typefaces.
  pw.ThemeData get theme => pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        italic: _regular,
        boldItalic: _bold,
      );

  // ── Type scale ──────────────────────────────────────────────────
  pw.TextStyle _t(
    double size, {
    pw.Font? font,
    PdfColor color = _kText,
    double spacing = 0,
    double? lineSpacing,
  }) =>
      pw.TextStyle(
        font: font ?? _regular,
        fontSize: size,
        color: color,
        letterSpacing: spacing,
        lineSpacing: lineSpacing,
      );

  pw.TextStyle get _hero => _t(30, font: _bold, color: _kInk, spacing: -0.7);
  pw.TextStyle get _title => _t(21, font: _bold, color: _kInk, spacing: -0.4);
  pw.TextStyle get _section => _t(15, font: _semi, color: _kInk, spacing: -0.25);
  pw.TextStyle get _sub => _t(12, font: _semi, color: _kInk, spacing: -0.15);
  pw.TextStyle get _muted => _t(10.5, color: _kTextSecondary);
  pw.TextStyle get _caption => _t(8.5, color: _kTextSecondary);
  pw.TextStyle get _label => _t(8.5, font: _semi, color: _kTextSecondary);

  PdfColor _signColor(num v) => v >= 0 ? _kMarketUp : _kMarketDown;

  String _btc(int sats) => TransactionPdfExport.formatBtc(sats, btcFormat);

  /// Signed amount; zero stays unsigned so it renders in ink.
  String _signedBtc(int sats) =>
      sats == 0 ? _btc(0) : '${sats > 0 ? '+' : '-'}${_btc(sats.abs())}';

  /// Outflow amount: "-15,000 sats", or "0 sats" when nothing moved.
  String _outBtc(int sats) => sats == 0 ? _btc(0) : '-${_btc(sats.abs())}';
  String _d(DateTime d) => DateFormat(_date).format(d);

  // ── Chrome ──────────────────────────────────────────────────────
  pw.Widget _rule({PdfColor color = _kHairline}) =>
      pw.Container(width: double.infinity, height: 0.5, color: color);

  /// Small mascot plus wordmark. The mascot PNG carries its own
  /// orange; nothing else on the page does.
  pw.Widget _brand({double size = 22}) {
    final mascot = assets.mascot;
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (mascot != null) ...[
          pw.Image(mascot, width: size, height: size, fit: pw.BoxFit.contain),
          pw.SizedBox(width: size * 0.22),
        ],
        pw.Text('kute',
            style: _t(size * 0.72, font: _semi, color: _kInk, spacing: -0.3)),
      ],
    );
  }

  pw.Widget _pageHeader(String title, {String? subtitle}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(title, style: _title),
            _brand(size: 20),
          ],
        ),
        if (subtitle != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(subtitle, style: _muted),
        ],
        pw.SizedBox(height: 12),
        _rule(),
      ],
    );
  }

  pw.Widget _footer(String pageLabel) {
    return pw.Column(
      children: [
        _rule(),
        pw.SizedBox(height: 7),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(l.pdfFooterTagline,
                style: _t(8, color: _kTextTertiary)),
            pw.Text(l.pdfNotTaxShort,
                style: _t(8, color: _kTextTertiary)),
            pw.Text(pageLabel, style: _t(8, color: _kTextTertiary)),
          ],
        ),
      ],
    );
  }

  /// A fixed A4 page: body, then the footer pinned to the bottom.
  pw.Page _staticPage(int number, List<pw.Widget> Function(pw.Context) body) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(_marginX, 40, _marginX, 26),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          ...body(ctx),
          pw.Spacer(),
          _footer(l.pdfPage('$number')),
        ],
      ),
    );
  }

  pw.Widget _card({
    required pw.Widget child,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(14),
    PdfColor color = _kSurface,
  }) {
    return pw.Container(
      padding: padding,
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  pw.Widget _cardRow(List<pw.Widget> cards, {double gap = 10}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          pw.Expanded(child: cards[i]),
          if (i < cards.length - 1) pw.SizedBox(width: gap),
        ],
      ],
    );
  }

  pw.Widget _kpi(String label, String value, String? subtitle,
      {PdfColor color = _kInk}) {
    return _card(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _label),
          pw.SizedBox(height: 8),
          pw.Text(value, style: _t(15, font: _bold, color: color, spacing: -0.3)),
          if (subtitle != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: _caption),
          ],
        ],
      ),
    );
  }

  pw.Widget _metricTile(String label, String value) {
    return _card(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _label),
          pw.SizedBox(height: 6),
          pw.Text(value, style: _t(11.5, font: _semi, color: _kInk, spacing: -0.15)),
        ],
      ),
    );
  }

  /// Hairline-bounded strip of label/value pairs (cover meta).
  pw.Widget _metaStrip(List<MapEntry<String, String>> items) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _kHairline, width: 0.5),
          bottom: pw.BorderSide(color: _kHairline, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final e in items)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(e.key, style: _label),
                pw.SizedBox(height: 4),
                pw.Text(e.value,
                    style: _t(12, font: _semi, color: _kInk, spacing: -0.15)),
              ],
            ),
        ],
      ),
    );
  }

  /// Quiet numbered contents line.
  pw.Widget _tocLine(_Toc entry, {required bool last}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: last
          ? null
          : const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _kHairlineSubtle, width: 0.5),
              ),
            ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 24,
            child: pw.Text(entry.number, style: _t(10, color: _kTextTertiary)),
          ),
          pw.Text(entry.title, style: _t(10.5, font: _semi, color: _kInk)),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Text(entry.description,
                textAlign: pw.TextAlign.right, style: _t(9, color: _kTextSecondary)),
          ),
        ],
      ),
    );
  }

  /// Table with a light grey header row and hairline row separators.
  /// [numeric] columns are right-aligned; [signed] columns colour
  /// their values by leading sign (marketUp / marketDown).
  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> data,
    Map<int, pw.TableColumnWidth>? columnWidths,
    Set<int> numeric = const {},
    Set<int> signed = const {},
    double fontSize = 9.5,
  }) {
    final aligns = <int, pw.AlignmentGeometry>{
      for (final i in numeric) i: pw.Alignment.centerRight,
    };
    final cell = _t(fontSize, color: _kText);
    // Dense ledger tables get a little less side padding so amounts
    // and statuses keep to one line.
    final hPad = fontSize < 9 ? 6.0 : 8.0;
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: _t(fontSize - 0.5, font: _semi, color: _kTextSecondary),
      headerDecoration: const pw.BoxDecoration(color: _kSurface),
      headerAlignment: pw.Alignment.centerLeft,
      headerAlignments: aligns,
      headerPadding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
      cellStyle: cell,
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: aligns,
      cellPadding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: 6.5),
      columnWidths: columnWidths,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _kHairlineSubtle, width: 0.5),
        bottom: pw.BorderSide(color: _kHairline, width: 0.5),
      ),
      textStyleBuilder: signed.isEmpty
          ? null
          : (index, value, rowNum) {
              if (!signed.contains(index)) return null;
              final s = '$value';
              if (s.startsWith('+')) return cell.copyWith(color: _kMarketUp);
              if (s.startsWith('-')) return cell.copyWith(color: _kMarketDown);
              return null;
            },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  PAGE 1: COVER & EXECUTIVE SUMMARY
  // ════════════════════════════════════════════════════════════════
  pw.Page coverPage(
    _ReportMetrics m,
    ExportSummary summary,
    DateTime? periodStart,
    DateTime? periodEnd,
  ) {
    final periodFrom = periodStart ?? m.firstTxDate;
    final periodTo = periodEnd ?? m.lastTxDate;
    final price = btcPrice;

    final row1 = [
      _kpi(l.pdfTotalReceived, _signedBtc(m.totalReceived),
          price != null ? _fmtUsd(m.totalReceived, price) : null,
          color: m.totalReceived == 0 ? _kInk : _kMarketUp),
      _kpi(l.pdfTotalSent, _outBtc(m.totalSent),
          price != null ? _fmtUsd(m.totalSent, price) : null,
          color: m.totalSent == 0 ? _kInk : _kMarketDown),
      _kpi(l.pdfNetFlow, _signedBtc(m.netFlow),
          price != null ? _fmtUsd(m.netFlow.abs(), price) : null,
          color: _signColor(m.netFlow)),
    ];

    final row2 = [
      _kpi(
        l.pdfOpeningBalance,
        _btc(summary.openingSats),
        periodStart != null
            ? l.pdfBefore(_d(periodStart))
            : l.pdfStartOfHistory,
      ),
      _kpi(l.pdfClosingBalance, _btc(summary.closingSats),
          l.pdfOpeningPlusNet),
      _kpi(
        l.pdfFeesPaid,
        _btc(summary.totalFeeSats),
        summary.totalFeeUsd > 0.005
            ? l.pdfPlusVenueFees(_usd(summary.totalFeeUsd))
            : (price != null ? _fmtUsd(summary.totalFeeSats, price) : null),
      ),
    ];

    // Realized results, only where the data exists (exchange-reported
    // figures, no invented cost basis).
    final showRow3 =
        summary.hlFillCount > 0 || summary.predictions.hasActivity;
    final row3 = <pw.Widget>[
      if (summary.hlFillCount > 0)
        _kpi(
          l.pdfInvestingRealizedPnl,
          _signedUsd(summary.hlRealizedPnlUsd),
          l.pdfFillsFees(summary.hlFillCount, _usd(summary.hlFeesUsd)),
          color: _signColor(summary.hlRealizedPnlUsd),
        ),
      if (summary.predictions.hasActivity) ...[
        _kpi(
          l.pdfPredictionsNet,
          _signedUsd(summary.predictions.netTradingUsd),
          l.pdfSellsClaimsMinusBets,
          color: _signColor(summary.predictions.netTradingUsd),
        ),
        _kpi(
          l.pdfPredictionsClaimed,
          _usd(summary.predictions.claimsUsd),
          l.pdfPlacedInBets(_usd(summary.predictions.betsPlacedUsd)),
        ),
      ] else
        _kpi(l.pdfLargestTransaction, _btc(m.largestTx),
            price != null ? _fmtUsd(m.largestTx, price) : null),
    ];

    final toc = [
      _Toc('1', l.pdfSummary, l.pdfSummaryDesc),
      _Toc('2', l.pdfYearlyBreakdown, l.pdfYearlyDesc),
      _Toc('3', l.pdfPortfolioOverview, l.pdfPortfolioDesc),
      _Toc('4', l.pdfActivityAnalysis, l.pdfActivityDesc),
      _Toc('5+', l.pdfActivityLedger, l.pdfLedgerDesc),
    ];

    return _staticPage(1, (ctx) => [
      _brand(size: 30),
      pw.SizedBox(height: 30),
      pw.Text(l.pdfActivityReport, style: _hero),
      pw.SizedBox(height: 8),
      pw.Text(l.pdfPeriodRange(_d(periodFrom), _d(periodTo)),
          style: _t(14, color: _kTextSecondary, spacing: -0.1)),
      pw.SizedBox(height: 4),
      pw.Text(_coversSentence(summary.coveredVenues),
          style: _t(10, color: _kTextSecondary)),
      pw.SizedBox(height: 20),
      _metaStrip([
        MapEntry(l.pdfGenerated, _d(now)),
        MapEntry(l.pdfWallets, '${m.walletCount}'),
        MapEntry(l.pdfTransactions, '${m.txCount}'),
        MapEntry(l.pdfDays, '${m.daysCovered}'),
        if (price != null)
          MapEntry(l.pdfBtcPrice, '\$${NumberFormat('#,##0').format(price)}'),
      ]),
      pw.SizedBox(height: 22),
      pw.Text(l.pdfExecutiveSummary, style: _section),
      pw.SizedBox(height: 10),
      _cardRow(row1),
      pw.SizedBox(height: 8),
      _cardRow(row2),
      if (showRow3) ...[
        pw.SizedBox(height: 8),
        _cardRow(row3),
      ],
      pw.SizedBox(height: 20),
      pw.Text(l.pdfContents, style: _section),
      pw.SizedBox(height: 4),
      for (var i = 0; i < toc.length; i++)
        _tocLine(toc[i], last: i == toc.length - 1),
      pw.Spacer(),
      // Orientation disclaimer (product requirement).
      _card(
        child: pw.Text(l.pdfDisclaimer,
            style: _t(9.5, color: _kTextSecondary, lineSpacing: 2)),
      ),
      pw.SizedBox(height: 12),
    ]);
  }

  String _coversSentence(List<String> venues) {
    final labels = venues.map((v) => _venueDisplayLabel(l, v)).toList();
    if (labels.isEmpty) return '';
    if (labels.length == 1) return l.pdfCoversOne(labels.single);
    final head = labels.sublist(0, labels.length - 1).join(', ');
    return l.pdfCoversMany(head, labels.last);
  }

  // ════════════════════════════════════════════════════════════════
  //  PAGE 2: YEARLY BREAKDOWN
  // ════════════════════════════════════════════════════════════════
  pw.Page yearlyPage(_ReportMetrics m) {
    final price = btcPrice;
    final sortedYears = m.yearlyBreakdown.keys.toList()..sort((a, b) => b.compareTo(a));
    final sortedCategories = m.categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.txCount.compareTo(a.value.txCount));

    // ── Annual summary ──
    final annualHeaders = [
      l.pdfYear,
      l.pdfReceived,
      if (price != null) l.pdfReceivedUsd,
      l.pdfSent,
      if (price != null) l.pdfSentUsd,
      l.pdfNetFlow,
      l.pdfTxs,
    ];
    final annualData = sortedYears.map((year) {
      final ys = m.yearlyBreakdown[year]!;
      return [
        '$year',
        _btc(ys.received),
        if (price != null) _fmtUsd(ys.received, price),
        _btc(ys.sent),
        if (price != null) _fmtUsd(ys.sent, price),
        _signedBtc(ys.netFlow),
        '${ys.txCount}',
      ];
    }).toList();

    // ── Category breakdown ──
    final categoryHeaders = [
      l.pdfCategory,
      l.pdfReceived,
      l.pdfSent,
      l.pdfNetFlow,
      if (price != null) l.pdfValueUsd,
      l.pdfTxs,
      l.pdfShare,
    ];
    final categoryData = sortedCategories.map((e) {
      final cs = e.value;
      final hasUsdc = cs.usdcReceived > 0 || cs.usdcSent > 0;
      final net = cs.received - cs.sent;
      final usdcNet = cs.usdcReceived - cs.usdcSent;
      final pct = m.txCount > 0
          ? (cs.txCount / m.txCount * 100).toStringAsFixed(1)
          : '0.0';
      String amount(int sats, double usdc) =>
          hasUsdc ? '${usdc.toStringAsFixed(2)} USDC' : _btc(sats);
      return [
        e.key,
        amount(cs.received, cs.usdcReceived),
        amount(cs.sent, cs.usdcSent),
        hasUsdc
            ? '${usdcNet >= 0 ? '+' : '-'}${usdcNet.abs().toStringAsFixed(2)} USDC'
            : _signedBtc(net),
        if (price != null)
          hasUsdc ? _usd(usdcNet.abs()) : _fmtUsd(net.abs(), price),
        '${cs.txCount}',
        '$pct%',
      ];
    }).toList();

    return _staticPage(2, (ctx) => [
      _pageHeader(l.pdfYearlyBreakdown),
      pw.SizedBox(height: 20),
      pw.Text(l.pdfAnnualSummary, style: _section),
      pw.SizedBox(height: 10),
      _table(
        headers: annualHeaders,
        data: annualData,
        numeric: {for (var i = 1; i < annualHeaders.length; i++) i},
        signed: {annualHeaders.indexOf(l.pdfNetFlow)},
      ),
      pw.SizedBox(height: 22),
      if (m.quarterlyBreakdown.isNotEmpty) ...[
        pw.Text(l.pdfQuarterlyBreakdown('${sortedYears.first}'),
            style: _section),
        pw.SizedBox(height: 10),
        _cardRow([
          for (final q in const ['Q1', 'Q2', 'Q3', 'Q4'])
            _quarterCard(q, m.quarterlyBreakdown[q]),
        ], gap: 8),
        pw.SizedBox(height: 22),
      ],
      pw.Text(l.pdfCategoryBreakdown, style: _section),
      pw.SizedBox(height: 10),
      _table(
        headers: categoryHeaders,
        data: categoryData,
        numeric: {for (var i = 1; i < categoryHeaders.length; i++) i},
        signed: {categoryHeaders.indexOf(l.pdfNetFlow)},
      ),
      pw.Spacer(),
      // Tax disclaimer.
      _card(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(l.pdfNotTaxTitle, style: _sub),
            pw.SizedBox(height: 4),
            pw.Text(
              '${l.pdfDisclaimer} ${l.pdfTaxAdvice}',
              style: _t(9.5, color: _kTextSecondary, lineSpacing: 2),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
    ]);
  }

  pw.Widget _quarterCard(String q, _QuarterSummary? qs) {
    if (qs == null) {
      return _card(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(q, style: _sub.copyWith(color: _kTextTertiary)),
            pw.SizedBox(height: 8),
            pw.Text(l.pdfNoActivity, style: _caption),
          ],
        ),
      );
    }
    return _card(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(q, style: _sub),
          pw.SizedBox(height: 8),
          pw.Text(_signedBtc(qs.received),
              style: _t(9.5, font: _semi,
                  color: qs.received == 0 ? _kInk : _kMarketUp)),
          pw.Text(_outBtc(qs.sent),
              style: _t(9.5, font: _semi,
                  color: qs.sent == 0 ? _kInk : _kMarketDown)),
          pw.SizedBox(height: 6),
          _rule(color: _kHairline),
          pw.SizedBox(height: 6),
          pw.Text(l.pdfNet, style: _label),
          pw.SizedBox(height: 2),
          pw.Text(_signedBtc(qs.netFlow),
              style: _t(10, font: _semi,
                  color: qs.netFlow == 0 ? _kInk : _signColor(qs.netFlow))),
          pw.SizedBox(height: 2),
          pw.Text(l.pdfTxCount(qs.txCount), style: _caption),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  PAGE 3: PORTFOLIO OVERVIEW
  // ════════════════════════════════════════════════════════════════
  pw.Page portfolioPage(
    List<WalletConfig> wallets,
    _WalletRollup rollup,
    List<ExportRow> periodRows,
    _ReportMetrics m,
  ) {
    final price = btcPrice;

    // Wallet allocation data
    final pieEntries = <_PieEntry>[];
    int totalAbsBal = 0;
    for (final w in wallets) {
      final sats = (rollup.sats[w.id] ?? 0).abs();
      totalAbsBal += sats;
      pieEntries.add(_PieEntry(
        label: w.name.isNotEmpty ? w.name : l.pdfWallet,
        value: sats,
      ));
    }

    // Transaction type distribution
    final typeCounts = <String, int>{};
    for (final tx in periodRows) {
      final type = _rowWord(tx.category);
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }
    final typeEntries = typeCounts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final subtitle = StringBuffer(
        l.pdfAsOf(DateFormat('MMM d, yyyy HH:mm').format(now)));
    if (price != null) {
      subtitle.write(
          l.pdfBtcPriceSuffix('\$${NumberFormat('#,##0').format(price)}'));
    }
    subtitle.write('.');

    return _staticPage(3, (ctx) => [
      _pageHeader(l.pdfPortfolioOverview, subtitle: subtitle.toString()),
      pw.SizedBox(height: 20),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: _chartCard(l.pdfWalletAllocation,
                _donutChart(pieEntries, totalAbsBal)),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            flex: 2,
            child: _chartCard(l.pdfTransactionTypes,
                _typeBreakdown(typeEntries)),
          ),
        ],
      ),
      pw.SizedBox(height: 22),
      pw.Text(l.pdfWalletBreakdown, style: _section),
      pw.SizedBox(height: 10),
      _walletTable(wallets, rollup, totalAbsBal),
    ]);
  }

  pw.Widget _chartCard(String title, pw.Widget chart) {
    return _card(
      padding: const pw.EdgeInsets.all(16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: _sub),
          pw.SizedBox(height: 12),
          chart,
        ],
      ),
    );
  }

  pw.Widget _walletTable(
    List<WalletConfig> wallets,
    _WalletRollup rollup,
    int totalBal,
  ) {
    final price = btcPrice;
    final headers = [
      l.pdfWallet,
      l.pdfType,
      l.pdfBalance,
      if (price != null) l.pdfValueUsd,
      l.pdfTransactions,
      l.pdfAllocation,
    ];

    final rows = wallets.map((w) {
      final bal = rollup.sats[w.id] ?? 0;
      final usdc = rollup.usdc[w.id] ?? 0;
      final pct = totalBal > 0 ? (bal.abs() / totalBal * 100).toStringAsFixed(1) : '0.0';

      // Show USDC balance for wallets with Polymarket activity
      final balanceStr = usdc > 0.01 ? '${usdc.toStringAsFixed(2)} USDC' : _btc(bal.abs());
      final valueStr = usdc > 0.01
          ? _usd(usdc)
          : (price != null ? _fmtUsd(bal.abs(), price) : null);

      return [
        w.name.isNotEmpty ? w.name : l.pdfWallet,
        w.isExternalAddress
            ? l.pdfWalletTracked
            : w.isHardware
                ? l.pdfWalletHardware
                : w.isWatchOnly
                    ? l.pdfWalletWatchOnly
                    : w.sparkEnabled
                        ? 'Spark'
                        : l.pdfWalletStandard,
        balanceStr,
        if (price != null) valueStr ?? '\$0.00',
        '${rollup.txCounts[w.id] ?? 0}',
        '$pct%',
      ];
    }).toList();

    return _table(
      headers: headers,
      data: rows,
      numeric: {for (var i = 2; i < headers.length; i++) i},
      fontSize: 10,
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  PAGE 4: ACTIVITY & PERFORMANCE
  // ════════════════════════════════════════════════════════════════
  pw.Page activityPage(List<ExportRow> periodRows, _ReportMetrics m) {
    // Day-of-week distribution
    final dowCounts = List.filled(7, 0);
    for (final tx in periodRows) {
      dowCounts[tx.date.weekday - 1]++;
    }

    return _staticPage(4, (ctx) => [
      _pageHeader(l.pdfActivityAnalysis),
      pw.SizedBox(height: 20),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(l.pdfKeyMetrics, style: _section),
                pw.SizedBox(height: 10),
                // Two tiles per row so amounts and labels stay on one line.
                _cardRow([
                  _metricTile(l.pdfMostActiveWallet, m.mostActiveWallet),
                  _metricTile(l.pdfMostActiveMonth, m.mostActiveMonth),
                ], gap: 8),
                pw.SizedBox(height: 8),
                _cardRow([
                  _metricTile(l.pdfLargestReceive, _btc(m.largestReceived)),
                  _metricTile(l.pdfLargestSend, _btc(m.largestSent)),
                ], gap: 8),
                pw.SizedBox(height: 8),
                _cardRow([
                  _metricTile(l.pdfMedianTx, _btc(m.medianTxSize)),
                  _metricTile(l.pdfActiveMonths, '${m.activeMonths}'),
                ], gap: 8),
              ],
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(l.pdfActivityByDay, style: _section),
                pw.SizedBox(height: 10),
                _card(child: _dayOfWeekChart(dowCounts)),
              ],
            ),
          ),
        ],
      ),
    ]);
  }

  // ════════════════════════════════════════════════════════════════
  //  PAGES 5+: ACTIVITY LEDGER (sectioned tables per venue)
  // ════════════════════════════════════════════════════════════════
  /// One MultiPage that flows one table per venue (Wallet, Investing,
  /// Predictions, Other) across as many pages as needed. Rows are
  /// newest-first inside each section. Full txids live in the CSV.
  pw.Page ledgerPages(List<ExportRow> periodRows, _ReportMetrics m) {
    final grouped = groupRowsByVenue(periodRows);

    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(_marginX, 36, _marginX, 26),
      maxPages: 400,
      header: (ctx) {
        // `ctx.pageNumber` is global across the document; the four
        // earlier static pages already exist by the time MultiPage
        // starts laying out, so page 5 is the first ledger page.
        if (ctx.pageNumber == 5) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 18),
            child: _pageHeader(
              l.pdfActivityLedger,
              subtitle: '${l.pdfEntriesCount(periodRows.length)}. '
                  '${l.pdfLedgerIntro(_d(m.firstTxDate), _d(m.lastTxDate))}',
            ),
          );
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(l.pdfLedgerContinued, style: _caption),
                  _brand(size: 16),
                ],
              ),
              pw.SizedBox(height: 8),
              _rule(),
            ],
          ),
        );
      },
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: _footer(
            l.pdfPageOf('${ctx.pageNumber}', '${ctx.pagesCount}')),
      ),
      build: (ctx) => [
        for (final entry in grouped.entries) ...[
          _venueSectionHeader(entry.key, entry.value),
          pw.SizedBox(height: 8),
          _venueTable(entry.key, entry.value),
          pw.SizedBox(height: 22),
        ],
      ],
    );
  }

  /// Section line above each venue table: display label, entry count
  /// and the venue's net movement in its own denomination.
  pw.Widget _venueSectionHeader(String venue, List<ExportRow> rows) {
    var netSats = 0;
    var netUsd = 0.0;
    for (final r in rows) {
      netSats += r.isSent ? -r.sats : r.sats;
      netUsd += r.isSent ? -r.usdcAmount : r.usdcAmount;
    }
    final netLabel = netSats != 0 ? _signedBtc(netSats) : _signedUsd(netUsd);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(_venueDisplayLabel(l, venue), style: _sub),
        pw.Text(l.pdfEntriesNet(l.pdfEntriesCount(rows.length), netLabel),
            style: _caption),
      ],
    );
  }

  /// One venue's ledger table. Columns adapt to the venue's
  /// denomination: sats rows show BTC amount, fiat and fee in sats;
  /// USD venues show notional, realized PnL (Investing) and USD fees.
  pw.Widget _venueTable(String venue, List<ExportRow> rows) {
    final price = btcPrice;
    final isTrading = venue == ExportVenue.trading;
    final isPredictions = venue == ExportVenue.predictions;

    final headers = <String>[
      l.pdfDate,
      l.pdfType,
      isPredictions ? l.pdfMarket : l.pdfDetails,
      if (isTrading || isPredictions) l.pdfAmountUsd else l.pdfAmount,
      if (isTrading) l.pdfRealizedPnl else l.pdfFiatUsd,
      l.pdfFee,
      l.pdfStatus,
    ];

    final data = rows.map((tx) {
      final date = DateFormat('MMM d, yyyy HH:mm').format(tx.date);
      String amount;
      if (tx.isOrder) {
        amount = tx.orderAmounts;
      } else if (tx.sats > 0) {
        amount = '${tx.isSent ? '-' : '+'}${_btc(tx.sats)}';
      } else if (tx.usdcAmount > 0) {
        amount = '${tx.isSent ? '-' : '+'}${_usd(tx.usdcAmount)}';
      } else {
        amount = '';
      }

      String fiatOrPnl;
      if (isTrading) {
        fiatOrPnl = tx.realizedPnlUsd.abs() >= 0.005
            ? _signedUsd(tx.realizedPnlUsd)
            : '';
      } else if (tx.sats > 0) {
        final snap = TxFiatSnapshotService.snapshot(tx.txid);
        if (snap != null && snap.usd > 0) {
          fiatOrPnl = _usd(snap.usd);
        } else if (price != null) {
          fiatOrPnl = _fmtUsd(tx.sats, price);
        } else {
          fiatOrPnl = '';
        }
      } else if (tx.usdcAmount > 0) {
        fiatOrPnl = _usd(tx.usdcAmount);
      } else {
        fiatOrPnl = '';
      }

      String fee;
      if (tx.feeSats > 0) {
        fee = '${NumberFormat('#,##0').format(tx.feeSats)} sats';
      } else if (tx.feeUsd > 0.0005) {
        fee = _usd(tx.feeUsd);
      } else {
        fee = '';
      }

      var desc = tx.description;
      if (!tx.isOrder && desc.length > 46) desc = '${desc.substring(0, 43)}...';

      return [
        date,
        _rowWord(tx.type),
        desc,
        amount,
        fiatOrPnl,
        fee,
        _rowWord(tx.status)
      ];
    }).toList();

    return _table(
      headers: headers,
      data: data,
      fontSize: 8.5,
      numeric: const {3, 4, 5},
      signed: {3, if (isTrading) 4},
      columnWidths: {
        0: const pw.FlexColumnWidth(1.35),
        1: const pw.FlexColumnWidth(1.4),
        2: const pw.FlexColumnWidth(1.9),
        3: const pw.FlexColumnWidth(1.7),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(0.8),
        6: const pw.FlexColumnWidth(1.25),
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  CHARTS (monochrome)
  // ════════════════════════════════════════════════════════════════

  /// Donut chart with legend, drawn in the grey ramp.
  pw.Widget _donutChart(List<_PieEntry> entries, int totalAbs) {
    if (totalAbs == 0) {
      return pw.Container(
        height: 150,
        alignment: pw.Alignment.center,
        child: pw.Text(l.pdfNoBalanceData, style: _caption),
      );
    }

    return pw.SizedBox(
      height: 150,
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            height: 120,
            child: pw.CustomPaint(
              size: const PdfPoint(120, 120),
              painter: (canvas, size) {
                final cx = size.x / 2;
                final cy = size.y / 2;
                final outerR = size.x / 2 - 2;
                final innerR = outerR * 0.62;
                double startAngle = -pi / 2;

                for (var i = 0; i < entries.length; i++) {
                  if (entries[i].value == 0) continue;
                  final sweep = (entries[i].value / totalAbs) * 2 * pi;
                  canvas.setFillColor(_kRamp[i % _kRamp.length]);

                  // Outer arc
                  canvas.moveTo(
                    cx + innerR * cos(startAngle),
                    cy + innerR * sin(startAngle),
                  );
                  canvas.lineTo(
                    cx + outerR * cos(startAngle),
                    cy + outerR * sin(startAngle),
                  );
                  const seg = 40;
                  for (var s = 1; s <= seg; s++) {
                    final a = startAngle + (sweep * s / seg);
                    canvas.lineTo(cx + outerR * cos(a), cy + outerR * sin(a));
                  }
                  // Inner arc (reverse)
                  canvas.lineTo(
                    cx + innerR * cos(startAngle + sweep),
                    cy + innerR * sin(startAngle + sweep),
                  );
                  for (var s = seg; s >= 0; s--) {
                    final a = startAngle + (sweep * s / seg);
                    canvas.lineTo(cx + innerR * cos(a), cy + innerR * sin(a));
                  }
                  canvas.fillPath();
                  startAngle += sweep;
                }
              },
            ),
          ),
          pw.SizedBox(width: 16),
          // Legend
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                for (var i = 0; i < entries.length; i++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 8,
                          height: 8,
                          margin: const pw.EdgeInsets.only(top: 1.5),
                          decoration: pw.BoxDecoration(
                            color: _kRamp[i % _kRamp.length],
                            borderRadius: pw.BorderRadius.circular(2),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(entries[i].label,
                                  style: _t(8.5, font: _semi, color: _kInk)),
                              pw.Text(
                                '${((entries[i].value / totalAbs) * 100).toStringAsFixed(1)}% '
                                '(${_btc(entries[i].value)})',
                                style: _t(7.5, color: _kTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Transaction type breakdown (horizontal bars).
  pw.Widget _typeBreakdown(List<MapEntry<String, int>> types) {
    if (types.isEmpty) {
      return pw.SizedBox(height: 150);
    }
    final maxCount = types.first.value;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < types.length; i++) ...[
          pw.Row(
            children: [
              pw.SizedBox(
                width: 58,
                child: pw.Text(types[i].key,
                    style: _t(8, font: _semi, color: _kInk)),
              ),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (context, constraints) {
                    final barWidth = (maxCount > 0 ? types[i].value / maxCount : 0.0) *
                        (constraints?.maxWidth ?? 100);
                    return pw.Stack(children: [
                      pw.Container(
                        height: 12,
                        decoration: pw.BoxDecoration(
                          color: _kSurfaceDeep,
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                      ),
                      pw.Container(
                        width: barWidth,
                        height: 12,
                        decoration: pw.BoxDecoration(
                          color: _kRamp[i % _kRamp.length],
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: 30,
                child: pw.Text(
                  '${types[i].value}',
                  textAlign: pw.TextAlign.right,
                  style: _t(8, font: _semi, color: _kInk),
                ),
              ),
            ],
          ),
          if (i < types.length - 1) pw.SizedBox(height: 8),
        ],
      ],
    );
  }

  /// Day-of-week activity chart.
  pw.Widget _dayOfWeekChart(List<int> counts) {
    final maxCount = counts.reduce(max);
    if (maxCount == 0) return pw.SizedBox(height: 80);
    final days = l.pdfWeekdaysShort.split(',');

    return pw.Column(
      children: [
        for (var i = 0; i < 7; i++)
          pw.Padding(
            padding: pw.EdgeInsets.only(bottom: i < 6 ? 5 : 0),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 26,
                  child: pw.Text(days[i], style: _t(7.5, color: _kTextSecondary)),
                ),
                pw.Expanded(
                  child: pw.LayoutBuilder(
                    builder: (context, constraints) {
                      final barWidth = (counts[i] / maxCount) * (constraints?.maxWidth ?? 100);
                      return pw.Stack(children: [
                        pw.Container(
                          height: 10,
                          decoration: pw.BoxDecoration(
                            color: _kSurfaceDeep,
                            borderRadius: pw.BorderRadius.circular(2),
                          ),
                        ),
                        pw.Container(
                          width: barWidth,
                          height: 10,
                          decoration: pw.BoxDecoration(
                            color: _kInk,
                            borderRadius: pw.BorderRadius.circular(2),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.SizedBox(
                  width: 16,
                  child: pw.Text('${counts[i]}',
                      textAlign: pw.TextAlign.right,
                      style: _t(7.5, font: _semi, color: _kInk)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  DATA CLASSES
// ══════════════════════════════════════════════════════════════════
class _Toc {
  final String number;
  final String title;
  final String description;
  const _Toc(this.number, this.title, this.description);
}

class _WalletRollup {
  final Map<String, int> sats;
  final Map<String, double> usdc;
  final Map<String, int> txCounts;
  const _WalletRollup({
    required this.sats,
    required this.usdc,
    required this.txCounts,
  });
}

class _ReportMetrics {
  final int txCount;
  final int walletCount;
  final int totalReceived;
  final int totalSent;
  final int netFlow;
  final int largestTx;
  final int largestReceived;
  final int largestSent;
  final int medianTxSize;
  final int receiveCount;
  final int sendCount;
  final int confirmedCount;
  final DateTime firstTxDate;
  final DateTime lastTxDate;
  final int daysCovered;
  final String mostActiveWallet;
  final String mostActiveMonth;
  final int activeMonths;
  final Map<int, _YearSummary> yearlyBreakdown;
  final Map<String, _QuarterSummary> quarterlyBreakdown;
  final Map<String, _CategorySummary> categoryBreakdown;
  final int uniqueTxIds;

  _ReportMetrics({
    required this.txCount,
    required this.walletCount,
    required this.totalReceived,
    required this.totalSent,
    required this.netFlow,
    required this.largestTx,
    required this.largestReceived,
    required this.largestSent,
    required this.medianTxSize,
    required this.receiveCount,
    required this.sendCount,
    required this.confirmedCount,
    required this.firstTxDate,
    required this.lastTxDate,
    required this.daysCovered,
    required this.mostActiveWallet,
    required this.mostActiveMonth,
    required this.activeMonths,
    required this.yearlyBreakdown,
    required this.quarterlyBreakdown,
    required this.categoryBreakdown,
    required this.uniqueTxIds,
  });
}

class _PieEntry {
  final String label;
  final int value;
  _PieEntry({required this.label, required this.value});
}

class _YearSummary {
  int received = 0;
  int sent = 0;
  int txCount = 0;
  int get netFlow => received - sent;
}

class _QuarterSummary {
  int received = 0;
  int sent = 0;
  int txCount = 0;
  int get netFlow => received - sent;
}

class _CategorySummary {
  int received = 0;
  int sent = 0;
  int txCount = 0;
  double usdcReceived = 0;
  double usdcSent = 0;
}
