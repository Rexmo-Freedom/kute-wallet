// Tests for the pure-Dart export aggregation layer: period filtering,
// venue merging, summary totals and the Hyperliquid fill mapping the
// PDF/CSV exporters both consume.

import 'dart:io';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/services/export/export_aggregation.dart';
import 'package:kute/services/transaction_pdf_export.dart';

ExportRow _row({
  required DateTime date,
  String venue = ExportVenue.wallet,
  String type = 'Bitcoin Received',
  int sats = 0,
  bool isSent = false,
  int feeSats = 0,
  double usd = 0,
  double feeUsd = 0,
  double pnl = 0,
}) {
  return ExportRow(
    date: date,
    venue: venue,
    type: type,
    category: 'Bitcoin',
    rail: 'Onchain',
    sats: sats,
    isSent: isSent,
    status: 'Confirmed',
    txid: 'tx-${date.millisecondsSinceEpoch}',
    walletName: 'Main',
    walletId: 'w1',
    walletType: 'Spending',
    usdcAmount: usd,
    feeSats: feeSats,
    feeUsd: feeUsd,
    realizedPnlUsd: pnl,
  );
}

void main() {
  final jan = DateTime(2026, 1, 15);
  final mar = DateTime(2026, 3, 10);
  final jun = DateTime(2026, 6, 1);

  test(
      'Orchestra orders export both assets without duplicating settlement flow',
      () {
    final wallet = WalletConfig(id: 'w1', name: 'Spending');
    final swap = SwapOrder(
      id: 'ord_fixture',
      provider: 'Orchestra',
      coinFrom: 'USDB',
      networkFrom: 'spark',
      coinTo: 'BTC',
      networkTo: 'spark',
      depositAddress: '',
      depositAmount: '1.123456',
      withdrawalAmount: '0.00001',
      status: 'success',
      timestamp: jan.millisecondsSinceEpoch,
      withdrawalAddress: '',
      depositMin: '',
      depositMax: '',
      rate: '',
      refundAddress: '',
    );
    final rows = TransactionPdfExport.collectRows(
      wallets: [wallet],
      currentBtcPrice: null,
      walletTransactions: {
        'w1': Transaction(
          bitcoinTransactions: [],
          sparkTransactions: [
            SparkTransaction.fromCache(
              id: 'payment',
              timestamp: jan,
              isConfirmed: true,
              amountSats: 1000,
              sparkType: SparkTransactionType.spark,
              direction: TransactionType.received,
              pending: false,
            )
          ],
          sparkUnclaimedDeposits: [],
          swapOrderTransactions: [
            SwapOrderTransaction(
              id: swap.id,
              timestamp: jan,
              details: swap,
              isConfirmed: true,
            )
          ],
        )
      },
    );
    final order = rows.singleWhere((r) => r.isOrder);
    expect(order.type, 'Orchestra Swap');
    expect(order.orderAmounts, '1.123456 USDB -> 0.00001 BTC');
    expect(netSatsFlow(rows), 1000);
    final csv = TransactionPdfExport.buildCsv(rows);
    expect(csv, contains('Source Asset,Source Amount,Source Network'));
    expect(csv, contains('USDB,1.123456,spark,BTC,0.00001,spark'));
    expect(csv, isNot(contains('SideShift Swap')));
  });

  group('filterRowsByPeriod', () {
    final rows = [
      _row(date: jan, sats: 1000),
      _row(date: mar, sats: 2000),
      _row(date: jun, sats: 3000),
    ];

    test('null bounds keep everything', () {
      expect(filterRowsByPeriod(rows).length, 3);
    });

    test('start bound is inclusive and drops earlier rows', () {
      final out = filterRowsByPeriod(rows, start: mar);
      expect(out.map((r) => r.sats), [2000, 3000]);
    });

    test('end bound is inclusive and drops later rows', () {
      final out = filterRowsByPeriod(rows, end: mar);
      expect(out.map((r) => r.sats), [1000, 2000]);
    });

    test('both bounds select the window', () {
      final out = filterRowsByPeriod(
        rows,
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 4, 1),
      );
      expect(out.single.sats, 2000);
    });
  });

  group('opening / closing balance', () {
    test('opening balance sums flows strictly before the period', () {
      final rows = [
        _row(date: jan, sats: 5000),
        _row(date: DateTime(2026, 2, 1), sats: 1500, isSent: true),
        _row(date: mar, sats: 800),
      ];
      expect(openingBalanceSats(rows, mar), 3500);
      expect(openingBalanceSats(rows, null), 0);
    });

    test('closing = opening + period net', () {
      final all = [
        _row(date: jan, sats: 5000),
        _row(date: mar, sats: 2000),
        _row(date: jun, sats: 1000, isSent: true),
      ];
      final opening = openingBalanceSats(all, mar);
      final period = filterRowsByPeriod(all, start: mar);
      final s = summarizeRows(period, openingSats: opening);
      expect(s.openingSats, 5000);
      expect(s.netSats, 1000);
      expect(s.closingSats, 6000);
    });
  });

  group('summarizeRows', () {
    test('totals split by direction and accumulate fees', () {
      final s = summarizeRows([
        _row(date: jan, sats: 4000, feeSats: 0),
        _row(date: mar, sats: 1000, isSent: true, feeSats: 120),
        _row(date: jun, venue: ExportVenue.trading, usd: 50, feeUsd: 0.75),
      ]);
      expect(s.rowCount, 3);
      expect(s.totalReceivedSats, 4000);
      expect(s.totalSentSats, 1000);
      expect(s.totalFeeSats, 120);
      expect(s.totalFeeUsd, closeTo(0.75, 1e-9));
      expect(s.firstDate, jan);
      expect(s.lastDate, jun);
    });

    test('hl realized pnl and fees sum over trading rows only', () {
      final s = summarizeRows([
        _row(date: jan, venue: ExportVenue.trading, usd: 100, pnl: 12.5, feeUsd: 0.3),
        _row(date: mar, venue: ExportVenue.trading, usd: 80, pnl: -4.5, feeUsd: 0.2),
        // Non-trading pnl must not leak into the HL figure.
        _row(date: jun, venue: ExportVenue.other, usd: 10, pnl: 99),
      ]);
      expect(s.hlFillCount, 2);
      expect(s.hlRealizedPnlUsd, closeTo(8.0, 1e-9));
      expect(s.hlFeesUsd, closeTo(0.5, 1e-9));
    });

    test('predictions breakdown classifies by type label', () {
      final s = summarizeRows([
        _row(date: jan, venue: ExportVenue.predictions, type: 'Predictions Deposit', usd: 30, isSent: true),
        _row(date: jan, venue: ExportVenue.predictions, type: 'Predictions Buy (Yes)', usd: 20, isSent: true),
        _row(date: mar, venue: ExportVenue.predictions, type: 'Predictions Sell (Yes)', usd: 8),
        _row(date: mar, venue: ExportVenue.predictions, type: 'Predictions Claim', usd: 25),
        _row(date: jun, venue: ExportVenue.predictions, type: 'Predictions Withdrawal', usd: 10),
      ]);
      final p = s.predictions;
      expect(p.depositsUsd, 30);
      expect(p.betsPlacedUsd, 20);
      expect(p.positionsSoldUsd, 8);
      expect(p.claimsUsd, 25);
      expect(p.withdrawalsUsd, 10);
      expect(p.netTradingUsd, closeTo(13.0, 1e-9));
      expect(p.hasActivity, isTrue);
    });

    test('covered venues follow canonical order', () {
      final s = summarizeRows([
        _row(date: jan, venue: ExportVenue.predictions, usd: 5),
        _row(date: mar, sats: 100),
        _row(date: jun, venue: ExportVenue.trading, usd: 50),
      ]);
      expect(s.coveredVenues,
          [ExportVenue.wallet, ExportVenue.trading, ExportVenue.predictions]);
    });
  });

  group('groupRowsByVenue', () {
    test('sections in canonical order, newest-first inside each', () {
      final grouped = groupRowsByVenue([
        _row(date: jan, venue: ExportVenue.predictions, usd: 1),
        _row(date: jan, sats: 100),
        _row(date: jun, sats: 300),
        _row(date: mar, venue: ExportVenue.trading, usd: 2),
      ]);
      expect(grouped.keys.toList(), [
        ExportVenue.wallet,
        ExportVenue.trading,
        ExportVenue.predictions,
      ]);
      expect(grouped[ExportVenue.wallet]!.map((r) => r.date), [jun, jan]);
    });
  });

  group('ExportRow.fromHlFill', () {
    test('maps notional, fee, closedPnl and venue', () {
      final fill = HlFill(
        coin: 'BTC',
        px: 50000,
        sz: 0.002,
        side: 'B',
        time: DateTime(2026, 4, 2, 12).millisecondsSinceEpoch,
        closedPnl: 3.25,
        fee: 0.11,
        feeToken: 'USDC',
        oid: 1,
        hash: '0xabc',
        dir: 'Close Long',
        cloid: null,
      );
      final row = ExportRow.fromHlFill(fill);
      expect(row.venue, ExportVenue.trading);
      expect(row.category, 'Investing');
      expect(row.type, 'Close Long BTC');
      expect(row.sats, 0);
      expect(row.usdcAmount, closeTo(100.0, 1e-9));
      expect(row.feeUsd, closeTo(0.11, 1e-9));
      expect(row.realizedPnlUsd, closeTo(3.25, 1e-9));
      expect(row.date, DateTime(2026, 4, 2, 12));
      // Close fills bring USD back, so they count as inflow even when
      // the taker side says buy.
      expect(row.isSent, isFalse);
    });

    test('opening fills count as outflow, closes as inflow', () {
      HlFill fill(String dir, String side) => HlFill(
            coin: 'ETH',
            px: 100,
            sz: 1,
            side: side,
            time: 0,
            closedPnl: 0,
            fee: 0,
            feeToken: 'USDC',
            oid: 1,
            hash: '0x1',
            dir: dir,
            cloid: null,
          );
      expect(ExportRow.fromHlFill(fill('Open Long', 'B')).isSent, isTrue);
      expect(ExportRow.fromHlFill(fill('Close Long', 'A')).isSent, isFalse);
      expect(ExportRow.fromHlFill(fill('Buy', 'B')).isSent, isTrue);
    });
  });

  test('disclaimer is the exact product sentence', () {
    expect(
      exportDisclaimer,
      'This report is for personal orientation only. It is not a tax '
      'document and may be incomplete or inaccurate.',
    );
  });

  test('shortened txid description uses an ASCII ellipsis', () {
    final r = _row(date: jan, sats: 1);
    final long = ExportRow(
      date: jan,
      venue: ExportVenue.wallet,
      type: r.type,
      category: r.category,
      rail: r.rail,
      sats: 1,
      isSent: false,
      status: 'Confirmed',
      txid: 'a' * 64,
      walletName: 'Main',
      walletId: 'w1',
      walletType: 'Spending',
    );
    expect(long.description, 'aaaaaaaaaa...aaaaaa');
    expect(long.description.codeUnits.every((c) => c < 128), isTrue);
  });

  // ────────────────────────────────────────────────────────────────
  // PDF smoke tests. The renderer is pure with respect to platform
  // plumbing (no file system, no share sheet) so it runs headlessly.
  // ────────────────────────────────────────────────────────────────
  group('TransactionPdfExport', () {
    final wallets = [
      WalletConfig(id: 'w1', name: 'Main'),
      WalletConfig(id: 'w2', name: 'Cold storage', isHardware: true),
    ];

    ExportRow wallet({
      required DateTime date,
      required int sats,
      bool isSent = false,
      String walletId = 'w1',
      String category = 'Bitcoin',
      int feeSats = 0,
      String? note,
    }) {
      return ExportRow(
        date: date,
        venue: ExportVenue.wallet,
        type: '$category ${isSent ? 'Sent' : 'Received'}',
        category: category,
        rail: category == 'Lightning' ? 'Lightning' : 'Onchain',
        sats: sats,
        isSent: isSent,
        status: 'Confirmed',
        txid: 'f' * 64,
        walletName: walletId == 'w1' ? 'Main' : 'Cold storage',
        walletId: walletId,
        walletType: walletId == 'w1' ? 'Spending' : 'Hardware',
        feeSats: feeSats,
        note: note,
      );
    }

    ExportRow prediction(DateTime date, String type, double usd, bool isSent) {
      return ExportRow(
        date: date,
        venue: ExportVenue.predictions,
        type: type,
        category: 'Predictions',
        rail: 'Polygon',
        sats: 0,
        isSent: isSent,
        status: 'Completed',
        txid: '0xabc',
        walletName: 'Main',
        walletId: 'w1',
        walletType: 'Spending',
        usdcAmount: usd,
        marketTitle: 'Will it rain in Lisbon on Sunday?',
      );
    }

    final fill = HlFill(
      coin: 'BTC',
      px: 60000,
      sz: 0.01,
      side: 'A',
      time: DateTime(2026, 4, 2, 12).millisecondsSinceEpoch,
      closedPnl: 12.5,
      fee: 0.35,
      feeToken: 'USDC',
      oid: 1,
      hash: '0xfill',
      dir: 'Close Long',
      cloid: null,
    );

    final rows = <ExportRow>[
      // Pre-period history so the opening balance is non-zero.
      wallet(date: DateTime(2025, 11, 20), sats: 250000),
      wallet(date: DateTime(2025, 12, 5), sats: 40000, isSent: true, feeSats: 210),
      // Period rows across two wallets and several categories.
      wallet(date: jan, sats: 120000),
      wallet(date: DateTime(2026, 2, 3, 9, 30), sats: 15000, isSent: true, category: 'Lightning', feeSats: 3, note: 'Cafe com acucar'),
      wallet(date: mar, sats: 500000, walletId: 'w2'),
      wallet(date: DateTime(2026, 4, 18), sats: 1, category: 'Lightning'),
      prediction(DateTime(2026, 2, 10), 'Predictions Deposit', 50, true),
      prediction(DateTime(2026, 2, 11), 'Predictions Buy (Yes)', 20, true),
      prediction(DateTime(2026, 3, 1), 'Predictions Claim', 32, false),
      ExportRow.fromHlFill(fill),
      ExportRow(
        date: jun,
        venue: ExportVenue.other,
        type: 'USDB Received',
        category: 'USDB',
        rail: 'Spark Token',
        sats: 0,
        isSent: false,
        status: 'Confirmed',
        txid: 'usdb-1',
        walletName: 'Main',
        walletId: 'w1',
        walletType: 'Spending',
        usdcAmount: 10,
      ),
    ];

    ReportAssets bundledAssets() {
      Uint8List read(String p) => File(p).readAsBytesSync();
      return ReportAssets.fromBytes(
        regular: read('lib/assets/fonts/Inter-Regular.ttf'),
        semiBold: read('lib/assets/fonts/Inter-SemiBold.ttf'),
        bold: read('lib/assets/fonts/Inter-Bold.ttf'),
        mascot: read('lib/assets/kute_logo.png'),
      );
    }

    test('formats bitcoin amounts as ASCII words', () {
      expect(TransactionPdfExport.formatBtc(10, 'sats'), '10 sats');
      expect(TransactionPdfExport.formatBtc(1, 'sats'), '1 sat');
      expect(TransactionPdfExport.formatBtc(1234567, 'sats'), '1,234,567 sats');
      expect(TransactionPdfExport.formatBtc(12345, 'BTC'), '0.00012345 BTC');
      expect(TransactionPdfExport.formatBtc(150000000, 'BTC'), '1.50000000 BTC');
      expect(TransactionPdfExport.formatBtc(-2500, 'BTC'), '-0.00002500 BTC');
      for (final s in [
        TransactionPdfExport.formatBtc(987654321, 'sats'),
        TransactionPdfExport.formatBtc(987654321, 'BTC'),
      ]) {
        expect(s.codeUnits.every((c) => c < 128), isTrue, reason: s);
      }
    });

    test('builds the report in Portuguese when given Portuguese copy',
        () async {
      final bytes = await TransactionPdfExport.buildReportBytes(
        rows: rows,
        wallets: wallets,
        btcFormat: 'sats',
        currentBtcPrice: 65000,
        polymarketUsdcBalance: 62,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 6, 30),
        assets: bundledAssets(),
        generatedAt: DateTime(2026, 7, 1, 10, 30),
        l10n: lookupAppLocalizations(const Locale('pt')),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('builds a multi-page report with the bundled Inter faces', () async {
      final bytes = await TransactionPdfExport.buildReportBytes(
        rows: rows,
        wallets: wallets,
        btcFormat: 'sats',
        currentBtcPrice: 65000,
        polymarketUsdcBalance: 62,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 6, 30),
        assets: bundledAssets(),
        generatedAt: DateTime(2026, 7, 1, 10, 30),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // Cover, yearly, portfolio, activity and at least one ledger page.
      final pages = RegExp(r'/Type\s*/Page(?!s)').allMatches(
        String.fromCharCodes(bytes),
      );
      expect(pages.length, greaterThanOrEqualTo(5));

      // Optional: dump the bytes for a visual check.
      final out = Platform.environment['KUTE_PDF_SMOKE_OUT'];
      if (out != null && out.isNotEmpty) {
        File(out).writeAsBytesSync(bytes, flush: true);
      }
    });

    test('long ledgers paginate across several pages', () async {
      final many = <ExportRow>[
        for (var i = 0; i < 140; i++)
          wallet(
            date: DateTime(2026, 1, 1).add(Duration(hours: i * 7)),
            sats: 1000 + i,
            isSent: i.isOdd,
            walletId: i % 3 == 0 ? 'w2' : 'w1',
          ),
      ];
      final bytes = await TransactionPdfExport.buildReportBytes(
        rows: many,
        wallets: wallets,
        btcFormat: 'BTC',
        currentBtcPrice: 65000,
        assets: bundledAssets(),
        generatedAt: DateTime(2026, 7, 1),
      );
      final pages = RegExp(r'/Type\s*/Page(?!s)')
          .allMatches(String.fromCharCodes(bytes))
          .length;
      // Four static pages plus a ledger that needs more than one page.
      expect(pages, greaterThanOrEqualTo(7));

      final out = Platform.environment['KUTE_PDF_SMOKE_OUT'];
      if (out != null && out.isNotEmpty) {
        File(out.replaceFirst('.pdf', '_long.pdf')).writeAsBytesSync(bytes, flush: true);
      }
    });

    test('falls back to built-in fonts when no assets are supplied', () async {
      final bytes = await TransactionPdfExport.buildReportBytes(
        rows: rows,
        wallets: wallets,
        btcFormat: 'BTC',
        currentBtcPrice: null,
        generatedAt: DateTime(2026, 7, 1),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('throws when the period has no rows', () {
      expect(
        () => TransactionPdfExport.buildReportBytes(
          rows: rows,
          wallets: wallets,
          btcFormat: 'sats',
          currentBtcPrice: 65000,
          periodStart: DateTime(2030, 1, 1),
        ),
        throwsException,
      );
    });

    test('CSV text is plain UTF-8 with the disclaimer header', () {
      final csv = TransactionPdfExport.buildCsv(
        rows.where((r) => r.date.year == 2026).toList()
          ..sort((a, b) => b.date.compareTo(a.date)),
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 6, 30),
        currentBtcPrice: 65000,
      );
      expect(csv.startsWith('# kute activity export\n'), isTrue);
      expect(csv, contains('# $exportDisclaimer'));
      expect(csv, contains('Cafe com acucar'));
      expect(csv, isNot(contains('…')));
      expect(csv, isNot(contains('₿')));
    });

    test('report assets load from the asset bundle', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final assets = await TransactionPdfExport.loadReportAssets();
      expect(assets.regular, isNotNull);
      expect(assets.semiBold, isNotNull);
      expect(assets.bold, isNotNull);
      expect(assets.mascot, isNotNull);
    });
  });
}
