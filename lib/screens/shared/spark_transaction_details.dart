import 'package:kute/screens/shared/money_fee_summary.dart';
import 'dart:math' show max, min;

import 'package:kute/helpers/extension.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/currency_conversions_provider.dart'; // NEW: Conversion Provider
import 'package:kute/providers/historical_price_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_paste_chip.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:url_launcher/url_launcher.dart';

final selectedSparkTransactionProvider =
    StateProvider<BaseTransaction?>((ref) => null);

class SparkTransactionDetails extends ConsumerStatefulWidget {
  const SparkTransactionDetails({super.key});

  @override
  _SparkTransactionDetailsState createState() =>
      _SparkTransactionDetailsState();
}

class _SparkTransactionDetailsState
    extends ConsumerState<SparkTransactionDetails> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final transaction = ref.watch(selectedSparkTransactionProvider);

    if (transaction == null) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
            title: Text(context.l10n.transactionDetails),
            backgroundColor: Colors.transparent),
        body: Center(
            child: Text(context.l10n.noTransactionSelected,
                style: TextStyle(color: c.textPrimary))),
      );
    }

    final isUnclaimed = transaction is SparkUnclaimedDeposit;
    final SparkTransaction? sparkTx =
        isUnclaimed ? null : transaction as SparkTransaction;
    bool isRefunding = false;
    String? sparkPaymentId;

    if (isUnclaimed) {
      final deposit = transaction;
      final r = deposit.refundTxId;
      if (r != null && r.isNotEmpty) {
        isRefunding = true;
      }
    } else {
      // Cached shell falls back to the wallet-internal id; live
      // entries use the SDK payment id.
      sparkPaymentId = sparkTx!.details?.id ?? sparkTx.id;
    }

    return KeyboardDismissOnTap(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: c.background,
        appBar: AppBar(
          title: Text(context.l10n.transactionDetails,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          centerTitle: true,
          leading: const KuteBackButton(),
          elevation: 0,
        ),
        body: Container(
          decoration: AppDecorations.screenGradient(context),
          child: PlatformSafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, ref, transaction, isRefunding),
                  SizedBox(height: 24.h),
                  _buildDetailsCard(context, ref, transaction, isRefunding),
                  SizedBox(height: 12.h),

                  Align(
                    alignment: Alignment.centerRight,
                    child: AskSalChip(
                      advisorContext:
                          const AdvisorContext(surface: 'spark_tx_detail'),
                    ),
                  ),
                  SizedBox(height: 20.h),

                  // 2. View on Spark Scan — unified to plain
                  // `launchUrl` (platform-default mode) so it opens
                  // via the same in-app browser path as Polygonscan.
                  if (sparkPaymentId != null) ...[
                    Builder(builder: (_) {
                      // `sparkPaymentId` is non-local so Dart's null
                      // promotion doesn't flow through this closure;
                      // use `!` after the `null` guard above.
                      final id = sparkPaymentId!;
                      final cleanId =
                          id.contains(':') ? id.split(':').first : id;
                      return _buildActionButton(
                          context.l10n.viewOnSparkScan,
                          () => launchUrl(Uri.parse(
                              'https://sparkscan.io/tx/$cleanId?network=mainnet')),
                          false);
                    }),
                    SizedBox(height: 12.h),
                  ],

                  // Mempool button removed — only shown on hardware wallet transactions

                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref,
      BaseTransaction transaction, bool isRefunding) {
    final c = context.colors;
    bool isReceiving = true;
    bool isUnclaimed = transaction is SparkUnclaimedDeposit;

    IconData icon = Icons.help_outline;
    String title = "Unknown";
    int amountSat = 0;

    if (isUnclaimed) {
      if (isRefunding) {
        icon = Icons.undo;
        title = context.l10n.refundingDeposit;
      } else {
        icon = Icons.priority_high;
        title = context.l10n.unclaimedDeposit;
      }
      amountSat = transaction.amount.toInt();
      isReceiving = true;
    } else {
      final sparkTx = transaction as SparkTransaction;
      // Safe accessors — works for both live SDK payload and the
      // Hive-hydrated cache shell.
      isReceiving = sparkTx.type == TransactionType.received;
      amountSat = sparkTx.amountSats;

      switch (sparkTx.sparkType) {
        case SparkTransactionType.lightning:
          icon = Icons.bolt;
          title = context.l10n.lightningBitcoin;
          break;
        case SparkTransactionType.bitcoin:
          icon = Icons.currency_bitcoin;
          title = context.l10n.bitcoin;
          break;
        case SparkTransactionType.spark:
          icon = Icons.swap_horiz;
          title = context.l10n.sparkTransfer;
          break;
      }
    }

    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    // REFACTOR: Use the provider to get formatted fiat string directly
    final fiatFormatted = ref.watch(conversionToFiatProvider(amountSat));
    // REFACTOR: Use extension for BTC/Sats string
    final btcFormatted = amountSat.toFormattedString(btcFormat);
    final unit = btcFormat == 'sats' ? 'sats' : 'BTC';

    // Historical price at transaction time
    final txDate = transaction.timestamp;
    final historicalPrice = ref.watch(historicalBtcPriceProvider(txDate));

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            color: c.surfaceLight.withValues(alpha: 0.5),
            border: Border.all(color: c.border),
          ),
          child: Icon(icon,
              color: isReceiving ? AppColors.success : context.colors.accent,
              size: 32.sp),
        ),
        SizedBox(height: 20.h),
        Text(
          "$btcFormatted $unit",
          style: TextStyle(
              color: c.textPrimary,
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
              color: c.textSecondary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500),
        ),
        // Historical value at time of transaction
        historicalPrice.when(
          data: (price) {
            if (price == null) {
              return const SizedBox.shrink();
            }
            final historicalValue = formatHistoricalValue(
              amountSats: amountSat,
              btcPriceUsd: price,
              currencySymbol: '\$',
            );
            // Calculate gain/loss
            final currentPrice = ref.watch(conversionToFiatProvider(100000000));
            final currentPriceNum = double.tryParse(
                    currentPrice.replaceAll(RegExp(r'[^\d.]'), '')) ??
                0;
            final historicalBtcValue = (amountSat / 100000000.0) * price;
            final currentBtcValue = (amountSat / 100000000.0) * currentPriceNum;
            final diff = currentBtcValue - historicalBtcValue;
            final diffPercent = historicalBtcValue > 0
                ? (diff / historicalBtcValue) * 100
                : 0.0;
            final isPositive = diff >= 0;

            return Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: (isPositive ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  context.l10n.txValueAtTx(historicalValue,
                      '${isPositive ? '+' : ''}${diffPercent.toStringAsFixed(1)}'),
                  style: TextStyle(
                    color: isPositive ? AppColors.success : AppColors.error,
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
        SizedBox(height: 8.h),
        Text(title, style: TextStyle(color: c.textSecondary, fontSize: 16.sp)),

        if (isUnclaimed && !isRefunding) ...[
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
                color: context.colors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12.r)),
            child: Text(context.l10n.actionRequired,
                style: TextStyle(
                    color: context.colors.accent,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsCard(BuildContext context, WidgetRef ref,
      BaseTransaction transaction, bool isRefunding) {
    final c = context.colors;

    final locale = Localizations.localeOf(context).languageCode;
    final formattedDate =
        DateFormat('d MMM yyyy, HH:mm', locale).format(transaction.timestamp);
    String statusText;
    Color statusColor;
    String typeLabel = context.l10n.txTypeUnknown;

    String? sparkPaymentId;
    String? txId;
    String? invoice;
    String? preimage;
    String? description;
    String? paymentHash;
    String? destinationPubkey;
    String? senderComment;
    int? vout;
    bool showFee = false;
    int feeSat = 0;

    if (transaction is SparkUnclaimedDeposit) {
      if (isRefunding) {
        statusText = context.l10n.refunding;
        statusColor = AppColors.info;
      } else {
        statusText = context.l10n.unclaimedDeposit;
        statusColor = context.colors.accent;
      }
      typeLabel = context.l10n.activityOnChainDeposit;
      txId = transaction.txid;
      vout = transaction.vout;
    } else {
      final sparkTx = transaction as SparkTransaction;
      final payment = sparkTx.details;
      // Cached shell: only the user-visible primitives are
      // populated. Skip the SDK-specific rows (raw method, fee,
      // PaymentDetails union) — the next live sync replaces this
      // entry with one that has all of them.
      if (payment == null) {
        sparkPaymentId = sparkTx.id;
        typeLabel = sparkTx.sparkType == SparkTransactionType.lightning
            ? 'Lightning'
            : sparkTx.sparkType == SparkTransactionType.bitcoin
                ? context.l10n.txTypeOnChain
                : 'Spark';
        feeSat = 0;
        showFee = false;
        statusText =
            sparkTx.isPending ? context.l10n.pending : context.l10n.completed;
        statusColor =
            sparkTx.isPending ? context.colors.accent : AppColors.success;
      } else {
        sparkPaymentId = payment.id;
        typeLabel = _getPaymentMethodString(context.l10n, payment.method);
        feeSat = payment.fees.toInt();
        showFee = payment.paymentType == breez.PaymentType.send && feeSat > 0;

        switch (payment.status) {
          case breez.PaymentStatus.completed:
            statusText = context.l10n.completed;
            statusColor = AppColors.success;
            break;
          case breez.PaymentStatus.failed:
            statusText = context.l10n.failed;
            statusColor = AppColors.error;
            break;
          case breez.PaymentStatus.pending:
            statusText = context.l10n.pending;
            statusColor = context.colors.accent;
            break;
        }
        final details = payment.details;
        if (details is breez.PaymentDetails_Deposit) {
          txId = details.txId;
        } else if (details is breez.PaymentDetails_Withdraw) {
          txId = details.txId;
        } else if (details is breez.PaymentDetails_Lightning) {
          invoice = details.invoice;
          preimage = details.htlcDetails.preimage;
          description = details.description;
          paymentHash = details.htlcDetails.paymentHash;
          destinationPubkey = details.destinationPubkey;
          // Extract sender comment from LNURL metadata
          if (details.lnurlReceiveMetadata?.senderComment != null &&
              details.lnurlReceiveMetadata!.senderComment!.isNotEmpty) {
            senderComment = details.lnurlReceiveMetadata!.senderComment;
          } else if (details.lnurlPayInfo?.comment != null &&
              details.lnurlPayInfo!.comment!.isNotEmpty) {
            senderComment = details.lnurlPayInfo!.comment;
          }
        } else if (details is breez.PaymentDetails_Spark) {
          if (details.invoiceDetails != null) {
            invoice = details.invoiceDetails!.invoice;
            description = details.invoiceDetails!.description;
          }
          if (details.htlcDetails != null) {
            paymentHash = details.htlcDetails!.paymentHash;
            preimage = details.htlcDetails!.preimage;
          }
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context.l10n.overview),
          SizedBox(height: 16.h),
          TransactionDetailRow(label: context.l10n.date, value: formattedDate),
          TransactionDetailRow(
              label: context.l10n.status,
              value: statusText,
              valueColor: statusColor),
          if (showFee)
            MoneyFeeSummary(
                label: context.l10n.networkFee, sats: feeSat.toDouble()),
          if (description != null && description.isNotEmpty)
            TransactionDetailRow(
                label: context.l10n.description, value: description),
          if (senderComment != null && senderComment.isNotEmpty)
            TransactionDetailRow(
                label: context.l10n.comment, value: senderComment),
          SizedBox(height: 20.h),
          Divider(color: c.border, height: 1),
          SizedBox(height: 20.h),
          _buildSectionHeader(context.l10n.technicalDetails),
          SizedBox(height: 16.h),
          TransactionDetailRow(label: context.l10n.type, value: typeLabel),
          if (txId != null)
            TransactionDetailRow(
                label: context.l10n.onChainTxid,
                value: txId,
                isCopiable: true,
                isAddress: true,
                onCopy: () => _copy(context, txId!)),
          if (vout != null)
            TransactionDetailRow(
                label: context.l10n.vout, value: vout.toString()),
          if (paymentHash != null)
            TransactionDetailRow(
                label: context.l10n.paymentHash,
                value: paymentHash,
                isCopiable: true,
                isAddress: true,
                onCopy: () => _copy(context, paymentHash!)),
          if (destinationPubkey != null)
            TransactionDetailRow(
                label: context.l10n.nodeId,
                value: destinationPubkey,
                isCopiable: true,
                isAddress: true,
                onCopy: () => _copy(context, destinationPubkey!)),
          if (invoice != null)
            TransactionDetailRow(
                label: context.l10n.invoice,
                value: invoice,
                isCopiable: true,
                isAddress: true,
                onCopy: () => _copy(context, invoice!)),
          if (preimage != null)
            TransactionDetailRow(
                label: context.l10n.preimage,
                value: preimage,
                isCopiable: true,
                isAddress: true,
                onCopy: () => _copy(context, preimage!)),
          if (sparkPaymentId != null)
            TransactionDetailRow(
                label: context.l10n.paymentId,
                value: sparkPaymentId.contains(':')
                    ? sparkPaymentId.split(':').first
                    : sparkPaymentId,
                isCopiable: true,
                isAddress: true,
                onCopy: () => _copy(
                    context,
                    sparkPaymentId!.contains(':')
                        ? sparkPaymentId.split(':').first
                        : sparkPaymentId)),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    showMessageSnackBarInfo(
        context: context, message: context.l10n.copiedToClipboard);
  }

  Widget _buildActionButton(
      String text, VoidCallback onPressed, bool isPrimary) {
    final c = context.colors;
    final bgColor = isPrimary ? context.colors.accent : c.surfaceLight;
    final txtColor = isPrimary ? Colors.black : c.textPrimary;

    return AppButton(
      text: text,
      onPressed: onPressed,
      color: bgColor,
      textColor: txtColor,
    );
  }

  Widget _buildSectionHeader(String title) {
    final c = context.colors;
    return Text(title,
        style: TextStyle(
            color: c.textPrimary,
            fontSize: 16.sp,
            fontWeight: FontWeight.bold));
  }

  String _getPaymentMethodString(
      AppLocalizations l10n, breez.PaymentMethod method) {
    switch (method) {
      case breez.PaymentMethod.lightning:
        return "Lightning";
      case breez.PaymentMethod.spark:
        return l10n.sparkTransfer;
      case breez.PaymentMethod.token:
        return l10n.txTypeToken;
      case breez.PaymentMethod.deposit:
        return l10n.activityOnChainDeposit;
      case breez.PaymentMethod.withdraw:
        return l10n.txTypeOnChainWithdrawal;
      case breez.PaymentMethod.unknown:
        return l10n.txTypeUnknown;
    }
  }
}

class TransactionDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isCopiable;
  final bool isAddress;
  final VoidCallback? onCopy;

  const TransactionDetailRow(
      {super.key,
      required this.label,
      required this.value,
      this.valueColor,
      this.isCopiable = false,
      this.isAddress = false,
      this.onCopy});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final displayText = isAddress && value.length > 16
        ? '${value.substring(0, 8)}...${value.substring(value.length - 8)}'
        : value;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: c.textSecondary, fontSize: 16.sp)),
          SizedBox(width: 16.w),
          Expanded(
            child: GestureDetector(
              onTap: onCopy ??
                  (isCopiable
                      ? () {
                          Clipboard.setData(ClipboardData(text: value));
                          showMessageSnackBarInfo(
                              context: context,
                              message: context.l10n.copiedToClipboard);
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
                          color: valueColor ?? c.textPrimary,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isCopiable) ...[
                    SizedBox(width: 8.w),
                    Icon(Icons.copy_rounded,
                        color: context.colors.accent, size: 14.sp)
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RefundAddressModalSheet extends StatefulWidget {
  const RefundAddressModalSheet({super.key});
  @override
  State<RefundAddressModalSheet> createState() =>
      _RefundAddressModalSheetState();
}

class _RefundAddressModalSheetState extends State<RefundAddressModalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _rateController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final rate = int.tryParse(_rateController.text);
      if (rate != null) {
        context.pop((address: _addressController.text, rate: rate));
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _fillAddress(text);
  }

  /// The bitcoin send's smart scanner, in return-value mode.
  Future<void> _scan() async {
    final scanned = await scanRecipientRaw(context);
    if (scanned == null || !mounted) return;
    _fillAddress(scanned);
  }

  /// A `bitcoin:` URI is reduced to its bare address, the way the send
  /// flow does it. The SDK still refuses a non-bitcoin address when it
  /// builds the refund.
  void _fillAddress(String raw) {
    final address = bareRecipientAddress(raw);
    if (address.isEmpty) return;
    setState(() => _addressController.text = address);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBottomSheetHeader(
              title: context.l10n.refundDeposit,
              subtitle: context.l10n.enterTheBitcoinAddressAndFeeRateToRefund),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _addressController,
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: c.surfaceLight,
                      labelText: context.l10n.bitcoinAddress,
                      labelStyle: TextStyle(color: c.textTertiary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16.r),
                          borderSide: BorderSide.none),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? context.l10n.pleaseEnterAnAddress
                        : null,
                  ),
                  SizedBox(height: 10.h),
                  // Paste and Scan, as on every other recipient field.
                  Row(
                    children: [
                      KutePasteChip(onPressed: _paste),
                      SizedBox(width: 8.w),
                      KuteScanChip(onPressed: _scan),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  TextFormField(
                    controller: _rateController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: c.surfaceLight,
                      labelText: context.l10n.feeRateSatsVbyte,
                      labelStyle: TextStyle(color: c.textTertiary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16.r),
                          borderSide: BorderSide.none),
                    ),
                    validator: (value) => (value == null ||
                            value.isEmpty ||
                            int.parse(value) <= 0)
                        ? context.l10n.invalidRate
                        : null,
                  ),
                  SizedBox(height: 32.h),
                  AppButton(
                    text: context.l10n.confirmRefund,
                    onPressed: _submit,
                    color: context.ctaFill,
                    textColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A claim quote can rise before the claim runs. Suggest the last quote plus
/// max(10%, 100 sats), kept below the deposit; null when no cap below the
/// deposit covers the quote.
int? suggestedClaimFeeSats(
    {required int lastQuoteSats, required int depositAmountSats}) {
  if (lastQuoteSats >= depositAmountSats - 1) {
    return null;
  }
  final headroom = max((lastQuoteSats + 9) ~/ 10, 100);
  return min(lastQuoteSats + headroom, depositAmountSats - 1);
}

/// The Spark claim fee is a quoted total fee, not a mining-speed selection.
/// Return a maximum in sats and enforce the same cap with MaxFee.fixed.
class ClaimFeePickerSheet extends ConsumerStatefulWidget {
  final int depositAmountSats;
  final breez.DepositClaimError? claimError;
  const ClaimFeePickerSheet(
      {super.key, required this.depositAmountSats, this.claimError});

  @override
  ConsumerState<ClaimFeePickerSheet> createState() =>
      _ClaimFeePickerSheetState();
}

class _ClaimFeePickerSheetState extends ConsumerState<ClaimFeePickerSheet> {
  late final TextEditingController _controller;
  int? _lastQuoteSats;

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('claim_fee_picker');
    final error = widget.claimError;
    if (error is breez.DepositClaimError_MaxDepositClaimFeeExceeded) {
      _lastQuoteSats = error.requiredFeeSats.toInt();
    }
    final lastQuote = _lastQuoteSats;
    final suggested = lastQuote == null
        ? null
        : suggestedClaimFeeSats(
            lastQuoteSats: lastQuote,
            depositAmountSats: widget.depositAmountSats);
    _controller = TextEditingController(text: suggested?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = int.tryParse(_controller.text) ?? 0;
    final valid = amount > 0 && amount < widget.depositAmountSats;
    final lastQuote = _lastQuoteSats;
    final quoteUsesDeposit = lastQuote != null &&
        suggestedClaimFeeSats(
                lastQuoteSats: lastQuote,
                depositAmountSats: widget.depositAmountSats) ==
            null;
    return AppBottomSheetContainer(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBottomSheetHeader(
              title: context.l10n.maximumClaimFee,
              subtitle: context.l10n.maximumClaimFeeExplanation,
              icon: Icons.account_balance_wallet_outlined),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: c.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surfaceLight,
                  labelText: context.l10n.maximumClaimFee,
                  labelStyle: TextStyle(color: c.textTertiary),
                  suffixText: 'sats',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.r),
                      borderSide: BorderSide.none),
                ),
              ),
              if (lastQuote != null)
                Padding(
                  padding: EdgeInsets.only(top: 8.h),
                  child: quoteUsesDeposit
                      ? Text(
                          context.l10n
                              .claimFeeQuoteExceedsDeposit('$lastQuote'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.accent, fontSize: 13.sp))
                      : Text(context.l10n.claimFeeLastQuote('$lastQuote'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.textTertiary, fontSize: 13.sp)),
                ),
              if (amount > 0)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Text(ref.watch(conversionToFiatProvider(amount)),
                      style: TextStyle(color: c.textSecondary)),
                ),
              if (amount >= widget.depositAmountSats)
                Text(context.l10n.claimFeeExceedsDeposit,
                    style: TextStyle(color: AppColors.error)),
              if (valid && amount > widget.depositAmountSats ~/ 2)
                Text(context.l10n.claimFeeWarning,
                    style: TextStyle(color: c.accent)),
              SizedBox(height: 20.h),
              AppButton(
                  text: context.l10n.confirmClaim,
                  onPressed: valid
                      ? () {
                          TrackingService.sparkDepositClaimFeeConfirmed();
                          context.pop(amount);
                        }
                      : null),
              AppBottomSheetTextButton(
                  text: context.l10n.cancel, onPressed: () => context.pop()),
            ]),
          ),
        ]),
      ),
    );
  }
}
