import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/bitcoin_labels_provider.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Entry row for manual coin control, in the detail row vocabulary of the
/// coin sheets. Visible beside the payment review; the picker itself is
/// the advanced surface. All consumers keep the existing unsigned-PSBT
/// rebuild/invalidation contract on `selectedUtxosProvider`.
class CoinSelectionTile extends ConsumerWidget {
  const CoinSelectionTile({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(bitcoinLabelsWalletIdProvider);
    if (owner == null) return const SizedBox.shrink();
    final selected = ref.watch(selectedUtxosProvider);
    return SheetDetailRow(
      label: context.l10n.coinSelection,
      value: selected.isEmpty
          ? context.l10n.coinSelectionAutomatic
          : context.l10n.coinSelectionCount(selected.length),
      trailingIcon: Icons.chevron_right_rounded,
      onTap: () => _open(context, ref, owner),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String owner) async {
    final draft = await showAppBottomSheet<List<OutPoint>>(
        context: context, builder: (_) => const _CoinSelectionSheet());
    if (!context.mounted ||
        draft == null ||
        ref.read(bitcoinLabelsWalletIdProvider) != owner) {
      return;
    }
    final previous = ref.read(selectedUtxosProvider);
    if (previous.length == draft.length &&
        previous.every((coin) => draft.any((s) => _same(s, coin)))) {
      return;
    }
    ref.read(selectedUtxosProvider.notifier).state = draft;
    TrackingService.track('coin_selection_changed', params: {
      'count': draft.length,
      'mode': draft.isEmpty ? 'automatic' : 'manual',
    });
    onChanged?.call();
  }
}

class _CoinSelectionSheet extends ConsumerStatefulWidget {
  const _CoinSelectionSheet();
  @override
  ConsumerState<_CoinSelectionSheet> createState() =>
      _CoinSelectionSheetState();
}

class _CoinSelectionSheetState extends ConsumerState<_CoinSelectionSheet> {
  late List<OutPoint> _draft;
  late String? _owner;

  @override
  void initState() {
    super.initState();
    _draft = [...ref.read(selectedUtxosProvider)];
    _owner = ref.read(bitcoinLabelsWalletIdProvider);
  }

  void _toggle(OutPoint outpoint, bool checked) {
    HapticFeedback.selectionClick();
    final next = [..._draft];
    if (checked) {
      next.removeWhere((s) => _same(s, outpoint));
    } else {
      next.add(outpoint);
    }
    setState(() => _draft = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final owner = ref.watch(bitcoinLabelsWalletIdProvider);
    final labels = owner == null
        ? <String, String>{}
        : ref.watch(bitcoinLabelsProvider(owner));
    final coins = ref.watch(unspentUtxosProvider);
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final scriptType = owner == null
        ? null
        : ref.watch(
            settingsProvider.select((s) => _scriptTypeOf(s.wallets, owner)));
    final sendTx = ref.watch(sendTxProvider);
    final feeRate = ref.watch(getCustomFeeRateProvider).valueOrNull;
    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
              title: l10n.coinSelection, subtitle: l10n.coinSelectionHelp),
          Flexible(
            child: coins.when(
              loading: () => const _CoinListSkeleton(),
              error: (_, __) => _CoinStateMessage(
                icon: Icons.cloud_off_rounded,
                message: l10n.failedToLoadUtxos,
                actionLabel: l10n.retry,
                onAction: () => ref.invalidate(unspentUtxosProvider),
              ),
              data: (values) {
                if (values.isEmpty) {
                  return _CoinStateMessage(
                      icon: Icons.toll_outlined, message: l10n.noUtxosAvailable);
                }
                final sorted = [...values]..sort((a, b) => b.txout.value
                    .toSat()
                    .compareTo(a.txout.value.toSat()));
                final selectedCoins = sorted
                    .where((coin) =>
                        _draft.any((s) => _same(s, coin.outpoint)))
                    .toList();
                final total = selectedCoins.fold<int>(
                    0, (sum, coin) => sum + coin.txout.value.toSat());
                final feeSats = feeRate == null
                    ? null
                    : _estimateFeeSats(feeRate,
                        inputs: selectedCoins.isEmpty ? 1 : selectedCoins.length,
                        scriptType: scriptType);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: _SelectionSummary(
                        btcFormat: btcFormat,
                        selectedSats: total,
                        selectedCount: selectedCoins.length,
                        availableSats: sorted.fold<int>(
                            0, (sum, coin) => sum + coin.txout.value.toSat()),
                        amountSats: sendTx.amount,
                        drain: sendTx.drain,
                        feeSats: feeSats,
                        onAutomatic: _draft.isEmpty
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                setState(() => _draft = []);
                              },
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 4.h),
                        itemCount: sorted.length,
                        itemBuilder: (_, index) {
                          final coin = sorted[index];
                          final checked =
                              _draft.any((s) => _same(s, coin.outpoint));
                          return _CoinTile(
                            coin: coin,
                            label: bitcoinCoinLabel(labels, coin.outpoint),
                            btcFormat: btcFormat,
                            selected: checked,
                            onTap: () => _toggle(coin.outpoint, checked),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
            child: AppButton(
              text: l10n.done,
              onPressed: owner == _owner
                  ? () =>
                      Navigator.of(context).pop(List<OutPoint>.from(_draft))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Selected total against the amount to send, with the estimated fee when
/// a rate is known, a thin progress bar and one state line.
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.btcFormat,
    required this.selectedSats,
    required this.selectedCount,
    required this.amountSats,
    required this.drain,
    required this.feeSats,
    required this.availableSats,
    required this.onAutomatic,
  });

  final String btcFormat;
  final int selectedSats;
  final int selectedCount;

  /// Everything this wallet could spend. In automatic mode it is what
  /// the figure shows, because nothing is selected by hand and a
  /// selected total of zero is not a fact about the wallet.
  final int availableSats;
  final int amountSats;
  final bool drain;
  final int? feeSats;
  final VoidCallback? onAutomatic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
    final automatic = selectedCount == 0;
    final needed = amountSats + (feeSats ?? 0);
    final compares = !automatic && !drain && amountSats > 0;
    final enough = drain || (compares && selectedSats >= needed);
    final fraction = drain
        ? 1.0
        : needed <= 0
            ? 0.0
            : (selectedSats / needed).clamp(0.0, 1.0).toDouble();
    final String stateLine;
    final Color stateColor;
    if (automatic) {
      stateLine = l10n.coinSelectionAutomaticHint;
      stateColor = c.textTertiary;
    } else if (drain) {
      stateLine = l10n.coinSelectionDrainHint;
      stateColor = c.textSecondary;
    } else if (!compares) {
      stateLine = l10n.coinSelectionInsufficient;
      stateColor = c.textTertiary;
    } else if (enough) {
      stateLine = l10n.coinSelectionEnough;
      stateColor = c.success;
    } else {
      stateLine = l10n.coinSelectionNotEnough;
      stateColor = c.error;
    }
    final detailLabel = TextStyle(
      color: c.textTertiary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
    );
    final detailValue = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      automatic
                          ? l10n.coinSelectionAutomatic
                          : l10n.coinSelectionCount(selectedCount),
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${(automatic ? availableSats : selectedSats).toFormattedString(btcFormat)} $unit',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              _AutomaticChip(onTap: onAutomatic),
            ],
          ),
          if (!drain && amountSats > 0) ...[
            SizedBox(height: 10.h),
            Row(
              children: [
                Text(l10n.coinSelectionToSend, style: detailLabel),
                const Spacer(),
                Text('${amountSats.toFormattedString(btcFormat)} $unit',
                    style: detailValue),
              ],
            ),
          ],
          if (feeSats != null) ...[
            SizedBox(height: 4.h),
            Row(
              children: [
                Text(l10n.coinSelectionEstimatedFee, style: detailLabel),
                const Spacer(),
                Text('~${feeSats!.toFormattedString(btcFormat)} $unit',
                    style: detailValue),
              ],
            ),
          ],
          if (!automatic) ...[
            SizedBox(height: 10.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(3.r),
              child: SizedBox(
                height: 4.h,
                child: LinearProgressIndicator(
                  value: fraction,
                  backgroundColor: c.border,
                  valueColor:
                      AlwaysStoppedAnimation(enough ? c.success : c.accent),
                ),
              ),
            ),
          ],
          SizedBox(height: 8.h),
          Text(
            stateLine,
            style: TextStyle(
              color: stateColor,
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral reset chip: `surface` ground with a hairline, dimmed when the
/// selection is already automatic.
class _AutomaticChip extends StatelessWidget {
  const _AutomaticChip({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 14.sp, color: c.textSecondary),
                SizedBox(width: 5.w),
                Text(
                  context.l10n.coinSelectionAutomatic,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One coin: amount as the hero, fiat below, label when set, confirmation
/// badge and the truncated outpoint. Its own widget so the lazy list never
/// reads the theme inside an item builder.
class _CoinTile extends ConsumerWidget {
  const _CoinTile({
    required this.coin,
    required this.label,
    required this.btcFormat,
    required this.selected,
    required this.onTap,
  });

  final LocalOutput coin;
  final String? label;
  final String btcFormat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sats = coin.txout.value.toSat();
    final fiat = ref.watch(conversionToFiatProvider(sats));
    final txid = coin.outpoint.txid.toString();
    final shortTxid = txid.length > 16
        ? '${txid.substring(0, 8)}...${txid.substring(txid.length - 8)}'
        : txid;
    final confirmed = coin.chainPosition is ConfirmedChainPosition;
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: selected ? c.accent : c.borderSubtle,
                width: selected ? 1.5 : 0.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1.h),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? c.accent : c.textTertiary,
                    size: 22.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              sats.toFormattedString(btcFormat),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                          Text(
                            btcFormat == 'sats' ? ' sats' : ' BTC',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        fiat,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        children: [
                          Text(
                            confirmed
                                ? context.l10n.confirmed
                                : context.l10n.unconfirmed,
                            style: TextStyle(
                              color: confirmed ? c.success : c.accent,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                          if (label case final label?) ...[
                            SizedBox(width: 6.w),
                            Flexible(child: _CoinLabelChip(label: label)),
                          ],
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '$shortTxid:${coin.outpoint.vout}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral label chip on the tile's `surfaceLight` ground: `surface` fill
/// with a hairline, no tint.
class _CoinLabelChip extends StatelessWidget {
  const _CoinLabelChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_outline_rounded, size: 12.sp, color: c.textSecondary),
          SizedBox(width: 4.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading state shaped like the summary card and three coin tiles.
class _CoinListSkeleton extends StatelessWidget {
  const _CoinListSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget tile() => Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: SkeletonCard(
            radius: 16.r,
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonCircle(22.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(130.w, 16.h),
                      SizedBox(height: 6.h),
                      SkeletonBar(70.w, 12.h),
                      SizedBox(height: 8.h),
                      SkeletonBar(160.w, 11.h),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return KuteSkeleton(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonCard(
              radius: 16.r,
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(90.w, 11.h),
                  SizedBox(height: 8.h),
                  SkeletonBar(150.w, 20.h),
                  SizedBox(height: 12.h),
                  SkeletonBar(double.infinity, 4.h),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            for (var i = 0; i < 3; i++) tile(),
          ],
        ),
      ),
    );
  }
}

/// Empty and error states in the Coins tab's quiet pattern: tertiary
/// glyph, one line of copy and a plain retry. Sized to its content so the
/// sheet stays short.
class _CoinStateMessage extends StatelessWidget {
  const _CoinStateMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 28.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c.textTertiary, size: 24.sp),
          SizedBox(height: 12.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          if (actionLabel != null) ...[
            SizedBox(height: 8.h),
            AppTextButton(
                text: actionLabel!, onPressed: onAction, textColor: c.textPrimary),
          ],
        ],
      ),
    );
  }
}

String? _scriptTypeOf(List<WalletConfig> wallets, String id) {
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet.scriptType;
  }
  return null;
}

/// Rough virtual size for one payment with change, by the wallet's script
/// type, so the summary can show a fee figure before BDK builds the real
/// transaction. The build is the source of truth; this only guides the
/// enough / not enough line.
int _estimateFeeSats(double rate,
    {required int inputs, required String? scriptType}) {
  final (inputVb, outputVb) = switch (scriptType) {
    'bip86' => (57.5, 43.0),
    'bip49' => (91.0, 32.0),
    'bip44' => (148.0, 34.0),
    _ => (68.0, 31.0),
  };
  final vsize = 10.5 + inputs * inputVb + 2 * outputVb;
  return (rate * vsize).ceil();
}

bool _same(OutPoint a, OutPoint b) =>
    a.txid.toString() == b.txid.toString() && a.vout == b.vout;
