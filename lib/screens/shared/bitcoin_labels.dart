import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/bitcoin_labels_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> editBitcoinLabel(
  BuildContext context,
  WidgetRef ref, {
  required String walletId,
  required String labelKey,
  required String title,
  String? inheritedLabel,
}) async {
  await showAppBottomSheet(
    context: context,
    builder: (_) => _LabelEditor(
        walletId: walletId,
        labelKey: labelKey,
        title: title,
        inheritedLabel: inheritedLabel),
  );
}

class _LabelEditor extends ConsumerStatefulWidget {
  const _LabelEditor(
      {required this.walletId,
      required this.labelKey,
      required this.title,
      this.inheritedLabel});
  final String walletId, labelKey, title;
  final String? inheritedLabel;
  @override
  ConsumerState<_LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends ConsumerState<_LabelEditor> {
  late final TextEditingController _controller;
  bool _saving = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text:
            ref.read(bitcoinLabelsProvider(widget.walletId))[widget.labelKey] ??
                '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final text = _controller.text.trim();
      await ref
          .read(bitcoinLabelsProvider(widget.walletId).notifier)
          .setLabel(widget.labelKey, text);
      // Coarse only: whether a label exists and what it names. The text
      // itself is local wallet metadata and never leaves the device.
      TrackingService.track('coin_label_saved', params: {
        'has_label': text.isNotEmpty,
        'kind': widget.labelKey.startsWith('coin:') ? 'coin' : 'transaction',
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  // The app's field chrome inside a sheet: `surfaceLight` fill on the
  // `surface` sheet, 12 corners, hairline at rest, accent hairline focused.
  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.r),
      borderSide: BorderSide(color: color, width: width));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          AppBottomSheetHeader(
              title: widget.title,
              subtitle: widget.inheritedLabel == null
                  ? context.l10n.coinLabelsLocal
                  : context.l10n.coinLabelInheritedHint),
          Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLength: 100,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                            counterText: '',
                            hintText: widget.inheritedLabel ??
                                context.l10n.coinLabelHint,
                            hintStyle: TextStyle(
                                color: c.textTertiary,
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w500),
                            filled: true,
                            fillColor: c.surfaceLight,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 14.w, vertical: 12.h),
                            border: _border(c.borderSubtle, 0.5),
                            enabledBorder: _border(c.borderSubtle, 0.5),
                            disabledBorder: _border(c.borderSubtle, 0.5),
                            focusedBorder: _border(c.accent, 1)),
                        onSubmitted: (_) {
                          if (!_saving) _save();
                        }),
                    if (_failed) ...[
                      SizedBox(height: 10.h),
                      Text(context.l10n.coinLabelSaveFailed,
                          style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                              color: c.error)),
                    ],
                    SizedBox(height: 20.h),
                    AppButton(
                        text: context.l10n.save,
                        onPressed: _saving ? null : _save,
                        isLoading: _saving),
                  ])),
        ]));
  }
}

/// Label row in the sheet vocabulary: title left, the label (or its "add"
/// placeholder in tertiary) right, edit glyph where a copiable row shows
/// its copy icon. Shared by the coin and transaction label rows.
class _LabelRow extends StatelessWidget {
  const _LabelRow(
      {required this.title,
      required this.label,
      required this.placeholder,
      required this.onTap});
  final String title;
  final String? label;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SheetDetailRow(
      label: title,
      value: label ?? placeholder,
      valueColor: label == null ? context.colors.textTertiary : null,
      trailingIcon: Icons.edit_outlined,
      onTap: onTap);
}

class BitcoinTransactionLabel extends ConsumerWidget {
  const BitcoinTransactionLabel({super.key, required this.txid, this.walletId});
  final String txid;
  final String? walletId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = walletId ?? ref.watch(bitcoinLabelsWalletIdProvider);
    if (owner == null) return const SizedBox.shrink();
    final label = ref
        .watch(bitcoinLabelsProvider(owner))[bitcoinTransactionLabelKey(txid)];
    return _LabelRow(
      title: context.l10n.coinTransactionLabel,
      label: label,
      placeholder: context.l10n.coinAddTransactionLabel,
      onTap: () => editBitcoinLabel(context, ref,
          walletId: owner,
          labelKey: bitcoinTransactionLabelKey(txid),
          title: context.l10n.coinTransactionLabel),
    );
  }
}

Future<void> showBitcoinCoinDetails(
    BuildContext context, WidgetRef ref, LocalOutput coin) async {
  final owner = ref.read(bitcoinLabelsWalletIdProvider);
  if (owner == null) return;
  TrackingService.track('coin_details_opened');
  await showAppBottomSheet(
      context: context,
      builder: (_) => _CoinDetailsSheet(owner: owner, coin: coin));
}

class _CoinDetailsSheet extends ConsumerWidget {
  const _CoinDetailsSheet({required this.owner, required this.coin});
  final String owner;
  final LocalOutput coin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final labels = ref.watch(bitcoinLabelsProvider(owner));
    final label = bitcoinCoinLabel(labels, coin.outpoint);
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final sats = coin.txout.value.toSat();
    final fiat = ref.watch(conversionToFiatProvider(sats));
    final txid = coin.outpoint.txid.toString();
    final outpoint = '$txid:${coin.outpoint.vout}';
    final position = coin.chainPosition;
    final blockTime =
        position is ConfirmedChainPosition ? position.confirmationBlockTime : null;
    final confirmed = blockTime != null;
    final amountStyle = TextStyle(
        fontSize: 34.sp,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return AppBottomSheetContainer(
        maxHeight: 0.85,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBottomSheetHeader(
                  title: context.l10n.coinDetails,
                  // The coin's label, or the day it arrived. The outpoint
                  // stays under Nerd data below.
                  subtitle: label ??
                      (blockTime != null && blockTime.confirmationTime != 0
                          ? DateFormat('d MMM yyyy').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  blockTime.confirmationTime * 1000))
                          : context.l10n.unconfirmed)),
              Flexible(
                  child: SheetScrollView(
                      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Hero amount, the transaction sheet's 34sp
                            // hierarchy with dimmed leading zeros.
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Flexible(
                                      child: BtcAmountText(
                                          text: sats
                                              .toFormattedString(btcFormat),
                                          style: amountStyle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                  SizedBox(width: 6.w),
                                  Text(btcFormat == 'sats' ? 'sats' : 'BTC',
                                      style: TextStyle(
                                          color: c.textSecondary,
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2)),
                                ]),
                            if (fiat.isNotEmpty) ...[
                              SizedBox(height: 4.h),
                              Text(fiat,
                                  style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.2)),
                            ],
                            SizedBox(height: 12.h),
                            _LabelRow(
                                title: context.l10n.coinLabel,
                                label: label,
                                placeholder: context.l10n.coinAddLabel,
                                onTap: () => editBitcoinLabel(context, ref,
                                    walletId: owner,
                                    labelKey:
                                        bitcoinCoinLabelKey(coin.outpoint),
                                    title: context.l10n.coinLabel,
                                    inheritedLabel: labels[
                                        bitcoinTransactionLabelKey(txid)])),
                            BitcoinTransactionLabel(
                                txid: txid, walletId: owner),
                            SheetDetailRow(
                                label: context.l10n.status,
                                value: confirmed
                                    ? context.l10n.confirmed
                                    : context.l10n.unconfirmed,
                                valueColor:
                                    confirmed ? c.success : c.accent),
                            if (blockTime != null &&
                                blockTime.confirmationTime != 0)
                              SheetDetailRow(
                                  label: context.l10n.date,
                                  value: DateFormat('d MMM yyyy, HH:mm')
                                      .format(DateTime
                                          .fromMillisecondsSinceEpoch(
                                              blockTime.confirmationTime *
                                                  1000))),
                            // Outpoint, tx id and height are nerd data.
                            SheetNerdDataSection(children: [
                              SheetDetailRow(
                                  label: context.l10n.coinOutput,
                                  value: outpoint,
                                  copiable: true,
                                  truncate: true,
                                  onCopied: () => TrackingService.track(
                                      'coin_outpoint_copied')),
                              SheetDetailRow(
                                  label: context.l10n.txId,
                                  value: txid,
                                  copiable: true,
                                  truncate: true,
                                  onCopied:
                                      TrackingService.transactionIdCopied),
                              if (blockTime != null)
                                SheetDetailRow(
                                    label: context.l10n.coinBlockHeight,
                                    value: '${blockTime.blockId.height}'),
                            ]),
                            SizedBox(height: 16.h),
                            SheetLinkButton(
                                label: context.l10n.activityViewOnBlockchain,
                                uri: Uri.parse(
                                    'https://mempool.space/tx/$txid'),
                                onPressed: () => Navigator.of(context).pop()),
                          ]))),
            ]));
  }
}
