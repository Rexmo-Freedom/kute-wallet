import 'package:kute/screens/shared/bitcoin_labels.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/helpers/common_operation_methods.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transaction_search_provider.dart';
import 'package:kute/screens/shared/app_card.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/providers/historical_price_provider.dart';
import 'package:intl/intl.dart';
import 'package:kute/services/tracking_service.dart';

class BitcoinTransactionDetailsScreen extends ConsumerWidget {
  final BitcoinTransaction transaction;

  const BitcoinTransactionDetailsScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cached BitcoinTransactions (sourced from the per-wallet Hive
    // snapshot) only carry primitives — id, timestamp, isConfirmed,
    // received/sent sats. The detail screen below dereferences the
    // live `btcDetails` for chain position, fee, raw tx bytes, etc.
    // When the user opens this screen for a cached entry we show a
    // brief "loading" placeholder; the next sync replaces the
    // cached shell with a live one and the screen rebuilds with
    // full data. Without this guard the screen would crash
    // dereferencing a null btcDetails.
    if (transaction.btcDetails == null) {
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          centerTitle: true,
          title: Text(context.l10n.transactionDetails,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        // Skeleton mimicking the loaded layout (header + detail card)
        // so the screen keeps its shape while the live tx syncs in.
        body: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
          child: KuteSkeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(
                  height: 120.h,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SkeletonCircle(40.w),
                      SizedBox(height: 12.h),
                      SkeletonBar(160.w, 22.h, radius: 8.r),
                    ],
                  ),
                ),
                SizedBox(height: 24.h),
                SkeletonCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < 5; i++) ...[
                        if (i > 0) SizedBox(height: 18.h),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            SkeletonBar(90.w, 12.h),
                            SkeletonBar(120.w, 12.h),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: context.colors.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          context.l10n.transactionDetails,
          style: TextStyle(color: context.colors.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const KuteBackButton(),
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, ref),
                SizedBox(height: 24.h),
                _buildDetailsCard(context, ref),
                BitcoinTransactionLabel(txid: transaction.id),
                SizedBox(height: 12.h),

                Align(
                  alignment: Alignment.centerRight,
                  child: AskSalChip(
                    advisorContext: const AdvisorContext(surface: 'btc_tx_detail'),
                  ),
                ),
                SizedBox(height: 12.h),
                _buildTechnicalCard(context, ref),
                SizedBox(height: 32.h),
                _buildActionButtons(context, ref),
                SizedBox(height: 40.h),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    // Calculate Total Amount involved (Sent - Received absolute difference)
    final totalAmountSats = (transaction.btcDetails!.sent.toSat() - transaction.btcDetails!.received.toSat()).abs();

    // REFACTOR: Use provider for Fiat conversion directly
    final fiatFormatted = ref.watch(conversionToFiatProvider(totalAmountSats.toInt()));

    // Historical price at transaction time
    final cp = transaction.btcDetails!.chainPosition;
    final txTimestamp = cp is ConfirmedChainPosition ? cp.confirmationBlockTime.confirmationTime : null;
    final txDate = txTimestamp != null && txTimestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(txTimestamp * 1000)
        : null;
    final historicalPrice = txDate != null
        ? ref.watch(historicalBtcPriceProvider(txDate))
        : null;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: context.colors.surfaceLight.withValues(alpha:0.5),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: context.colors.borderSubtle),
          ),
          child: transactionTypeIcon(transaction.btcDetails!),
        ),
        SizedBox(height: 20.h),
        Text(
          transactionAmount(transaction.btcDetails!, ref),
          style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 36.sp,
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -1.0),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8.h),
        Text(
          fiatFormatted,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 16.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        // Historical value at time of transaction
        if (historicalPrice != null)
          historicalPrice.when(
            data: (price) {
              if (price == null) return const SizedBox.shrink();
              final historicalValue = formatHistoricalValue(
                amountSats: totalAmountSats.toInt(),
                btcPriceUsd: price,
                currencySymbol: '\$',
              );
              // Calculate gain/loss vs current value
              final currentPrice = ref.watch(conversionToFiatProvider(100000000)); // 1 BTC in fiat
              final currentPriceNum = double.tryParse(currentPrice.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
              final historicalBtcValue = (totalAmountSats.toInt() / 100000000.0) * price;
              final currentBtcValue = (totalAmountSats.toInt() / 100000000.0) * currentPriceNum;
              final diff = currentBtcValue - historicalBtcValue;
              final diffPercent = historicalBtcValue > 0 ? (diff / historicalBtcValue) * 100 : 0.0;
              final isPositive = diff >= 0;

              return Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: (isPositive ? context.colors.success : context.colors.error).withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    context.l10n.txValueAtTx(historicalValue,
                        '${isPositive ? '+' : ''}${diffPercent.toStringAsFixed(1)}'),
                    style: TextStyle(
                      color: isPositive ? context.colors.success : context.colors.error,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
            loading: () => Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: KuteSkeleton(
                child: SkeletonBar(150.w, 26.h, radius: 12.r),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _buildDetailsCard(BuildContext context, WidgetRef ref) {
    final denomination = ref.read(settingsProvider).btcFormat;
    final isConfirmed = transaction.btcDetails!.chainPosition is ConfirmedChainPosition;

    return AppCard(
      padding: EdgeInsets.all(20.w),
      radius: 24.r,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, context.l10n.overview),
          SizedBox(height: 16.h),
          TransactionDetailRow(
            label: context.l10n.date,
            value: _formatTimestamp(context, transaction.btcDetails!.chainPosition is ConfirmedChainPosition
                ? (transaction.btcDetails!.chainPosition as ConfirmedChainPosition).confirmationBlockTime.confirmationTime
                : null),
          ),
          TransactionDetailRow(
            label: context.l10n.status,
            value: confirmationStatus(context, transaction.btcDetails!, ref),
            valueColor: _getStatusColor(context, confirmationStatus(context, transaction.btcDetails!, ref)),
          ),
          TransactionDetailRow(
            label: context.l10n.blockHeight,
            value: isConfirmed
                ? (transaction.btcDetails!.chainPosition as ConfirmedChainPosition).confirmationBlockTime.blockId.height.toString()
                : context.l10n.pending,
          ),
          SizedBox(height: 20.h),
          Divider(color: context.colors.borderSubtle, height: 1),
          SizedBox(height: 20.h),
          _buildSectionHeader(context, context.l10n.financials),
          SizedBox(height: 16.h),
          if (transaction.btcDetails!.fee != null)
            TransactionDetailRow(
              label: context.l10n.networkFee,
              // REFACTOR: Use extension for BTC/Sats string
              value: "${transaction.btcDetails!.fee!.toSat().toFormattedString(denomination)} $denomination",
            ),
        ],
      ),
    );
  }

  Widget _buildTechnicalCard(BuildContext context, WidgetRef ref) {
    final details = transaction.btcDetails!;

    // FIX: Changed details.transaction to details.tx based on your TxDetails class model
    final rawTx = details.tx;

    // NOTE: Removed the nullable operator `?` since `tx` is non-nullable in your model
    final int vSize = rawTx.vsize().toInt();
    final int inputsCount = rawTx.inputCount;
    final int outputsCount = rawTx.outputCount;
    final double fee = (details.fee?.toSat() ?? 0).toDouble();

    String feeRateString = "N/A";
    if (vSize > 0 && fee > 0) {
      final rate = fee / vSize;
      feeRateString = "${rate.toStringAsFixed(1)} ${context.l10n.satVb}";
    }

    return AppCard(
      padding: EdgeInsets.all(20.w),
      radius: 24.r,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, context.l10n.technicalDetails),
          SizedBox(height: 16.h),
          TransactionDetailRow(
            label: context.l10n.txId,
            value: details.txid.toString(),
            isCopiable: true,
            isAddress: true,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: details.txid.toString()));
              showMessageSnackBarInfo(context: context, message: context.l10n.transactionIdCopied);
            },
          ),
          if (feeRateString != "N/A") TransactionDetailRow(label: context.l10n.feeRate2, value: feeRateString),
          if (inputsCount > 0) TransactionDetailRow(label: context.l10n.inputsOutputs, value: "$inputsCount / $outputsCount"),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(title, style: TextStyle(color: context.colors.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.bold));
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref) {
    final mempoolButton = _buildActionButton(
        context: context,
        icon: Icons.public,
        label: context.l10n.viewInMempool,
        onPressed: () {
          TrackingService.track('tx_detail_action', params: {'action': 'open_explorer'});
          ref.read(transactionSearchProvider).isLiquid = false;
          ref.read(transactionSearchProvider).txid = transaction.btcDetails!.txid.toString();
          context.push('/search_modal');
        },
        isPrimary: false
    );

    return mempoolButton;
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    final bgColor = isPrimary ? context.colors.accent : context.colors.surfaceLight;
    final txtColor = isPrimary ? Colors.black : context.colors.textPrimary;

    return AppButton(
      text: label,
      onPressed: onPressed,
      icon: icon,
      color: bgColor,
      textColor: txtColor,
    );
  }

  Color _getStatusColor(BuildContext context, String status) {
    if (status == context.l10n.confirmed) return context.colors.success;
    if (status == context.l10n.unconfirmed || status == context.l10n.pending) return context.colors.accent;
    return context.colors.textPrimary;
  }

  String _formatTimestamp(BuildContext context, int? timestamp) {
    if (timestamp == null || timestamp == 0) return context.l10n.pending;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('d MMM yyyy, HH:mm').format(date);
  }
}

class TransactionDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isCopiable;
  final bool isAddress;
  final VoidCallback? onCopy;

  const TransactionDetailRow({super.key, required this.label, required this.value, this.valueColor, this.isCopiable = false, this.isAddress = false, this.onCopy});

  @override
  Widget build(BuildContext context) {
    final displayText = isAddress && value.length > 16
        ? '${value.substring(0, 8)}...${value.substring(value.length - 8)}'
        : value;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 16.sp)),
          SizedBox(width: 16.w),
          Expanded(
            child: GestureDetector(
              onTap: onCopy ?? (isCopiable
                  ? () {
                Clipboard.setData(ClipboardData(text: value));
                showMessageSnackBarInfo(context: context, message: context.l10n.copiedToClipboard);
              }
                  : null),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      displayText,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: valueColor ?? context.colors.textPrimary,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isCopiable) ...[SizedBox(width: 8.w), Icon(Icons.copy_rounded, color: context.colors.accent, size: 14.sp)]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
