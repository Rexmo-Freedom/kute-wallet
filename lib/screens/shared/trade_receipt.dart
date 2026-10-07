import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// The on-chain transaction behind a receipt: shown shortened on one line
/// with a copy action, and opened on the chain's block explorer.
class TradeReceiptTransaction {
  final String hash;

  /// `polygon` (Polymarket) or `hyperliquid`.
  final String chain;
  const TradeReceiptTransaction._(this.hash, this.chain);

  static final _txHash = RegExp(r'^0x[0-9a-fA-F]{64}$');

  /// A Polymarket fill or claim. Null unless [hash] is a transaction hash.
  static TradeReceiptTransaction? polygon(String? hash) =>
      hash != null && _txHash.hasMatch(hash)
          ? TradeReceiptTransaction._(hash, 'polygon')
          : null;

  /// A Hyperliquid fill. Null unless [hash] is a real (non-zero) hash.
  static TradeReceiptTransaction? hyperliquid(String? hash) =>
      hash != null &&
              _txHash.hasMatch(hash) &&
              !RegExp(r'^0x0+$').hasMatch(hash)
          ? TradeReceiptTransaction._(hash, 'hyperliquid')
          : null;

  String get explorer => chain == 'hyperliquid' ? 'hyperliquid' : 'polygonscan';

  Uri get explorerUri => chain == 'hyperliquid'
      ? Uri.parse('https://app.hyperliquid.xyz/explorer/tx/$hash')
      : Uri.parse('https://polygonscan.com/tx/$hash');

  /// Test seam: widget tests record the opened link instead of launching.
  @visibleForTesting
  static Future<void> Function(Uri uri)? debugLaunchOverride;

  /// Opens the explorer the way the Activity sheets do (in-app browser,
  /// then the external one). Analytics get the chain, never the hash.
  Future<void> open() async {
    TrackingService.track('block_explorer_opened', params: {
      'explorer': explorer,
      'chain': chain,
      'has_tx': true,
      'surface': 'trade_receipt',
    });
    final uri = explorerUri;
    final override = debugLaunchOverride;
    if (override != null) return override(uri);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {/* No browser available: nothing else to do. */}
  }
}

/// A shared receipt for Predictions, Investing and Ledger confirmations.
/// Callers supply the actual labels: estimates never become settled amounts.
class TradeReceipt extends StatelessWidget {
  final String title;
  final Widget? leading;
  final String? subtitle;
  final Map<String, String> rows;

  /// Shown after [rows]: the hash shortened with a copy action, and a link
  /// to the chain's block explorer.
  final TradeReceiptTransaction? transaction;
  const TradeReceipt(
      {super.key,
      required this.title,
      this.leading,
      this.subtitle,
      required this.rows,
      this.transaction});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = rows.entries.toList();
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.all(20.w),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (subtitle?.isNotEmpty == true) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(subtitle!,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600)),
              ),
              SizedBox(height: 12.h),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (leading != null) ...[leading!, SizedBox(width: 12.w)],
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 20.sp,
                          height: 1.25,
                          letterSpacing: -.4,
                          fontWeight: FontWeight.w700))),
            ]),
            if (entries.isNotEmpty) ...[
              SizedBox(height: 24.h),
              Text(entries.first.key,
                  style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
              SizedBox(height: 5.h),
              Text(entries.first.value,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 30.sp,
                      height: 1.15,
                      letterSpacing: -.8,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ]),
        ),
        if (entries.length > 1 || transaction != null) ...[
          Divider(height: 1, color: c.border),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            child: LayoutBuilder(
              builder: (context, box) => Column(children: [
                for (final entry in entries.skip(1))
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The label gives way first: numbers stay on one
                        // line, right aligned; only long sentences wrap.
                        Expanded(
                            child: Text(entry.key,
                                style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 14.sp))),
                        SizedBox(width: 16.w),
                        ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: box.maxWidth * .6),
                          child: Text(entry.value,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ),
                      ],
                    ),
                  ),
                if (transaction != null) ...[
                  SheetDetailRow(
                    label: context.l10n.tnTransaction,
                    value: transaction!.hash,
                    copiable: true,
                    truncate: true,
                    onCopied: TrackingService.transactionIdCopied,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const ValueKey('trade-receipt-explorer'),
                      onPressed: transaction!.open,
                      style: TextButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                      ),
                      icon: Icon(Icons.open_in_new_rounded, size: 16.sp),
                      label: Text(context.l10n.activityViewOnBlockchain,
                          style: TextStyle(
                              fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
