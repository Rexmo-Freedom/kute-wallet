import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/slip_stat_tiles.dart'
    show SlipFigure, slipZeroFigure;
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/one_balance/funding_fees.dart'
    show FundingLegSource;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/screens/shared/position_rows_card.dart'
    show positionTileValueStyle;
import 'package:kute/theme/app_theme.dart';

/// The app's Bitcoin price in USD, for display-only unit bridging. Null while
/// the rate is missing. Never supplies amounts to a signer.
double? feeUsdPerBtc(WidgetRef ref) {
  final rates = ref.watch(currencyProvider).rates;
  final hasBtcRate = (double.tryParse('${rates['BTC']}') ?? 0) > 0;
  return hasBtcRate
      ? ref.watch(selectedCurrencyProvider('USD')).toDouble()
      : null;
}

/// One leg of an order's funding as a fee sheet line: what it is
/// ("Move from Bitcoin") and its fee in dollars.
typedef MoneyFeeLeg = ({String label, double usd});

/// The fee sheet's line for a funding leg from [source]: "Move from
/// Bitcoin", "Move from Investing".
String fundingLegFeeLabel(AppLocalizations l10n, FundingLegSource source) =>
    switch (source) {
      FundingLegSource.dollars => l10n.slipMoveFromDollars,
      FundingLegSource.bitcoin => l10n.slipMoveFromBitcoin,
      FundingLegSource.investing => l10n.slipMoveFromInvesting,
      FundingLegSource.predictions => l10n.slipMoveFromPredictions,
    };

/// Display-only money conversion. Never supplies amounts to a signer.
({String primary, String? secondary}) feeAmountText(WidgetRef ref,
    {double? usd, double? sats, bool? bitcoinFirst}) {
  final settings = ref.watch(settingsProvider);
  final rates = ref.watch(currencyProvider).rates;
  final hasFiatRate = (double.tryParse('${rates[settings.currency]}') ?? 0) > 0;
  return formatFeeAmount(
    usd: usd,
    sats: sats,
    currency: settings.currency,
    btcFormat: settings.btcFormat,
    bitcoinFirst: bitcoinFirst ?? settings.mainDenomination == 'bitcoin',
    usdPerBtc: feeUsdPerBtc(ref),
    fiatPerUsd: settings.currency == 'USD'
        ? 1
        : hasFiatRate
            ? ref
                .watch(selectedCurrencyProviderFromUSD(settings.currency))
                .toDouble()
            : null,
  );
}

/// Missing FX stays explicit; a positive fee never rounds down to zero.
({String primary, String? secondary}) formatFeeAmount({
  double? usd,
  double? sats,
  required String currency,
  required String btcFormat,
  required bool bitcoinFirst,
  double? usdPerBtc,
  double? fiatPerUsd,
}) {
  final hasBtcRate = usdPerBtc != null && usdPerBtc.isFinite && usdPerBtc > 0;
  final dollars =
      usd ?? (sats != null && hasBtcRate ? sats / 1e8 * usdPerBtc : null);
  final satAmount =
      sats ?? (usd != null && hasBtcRate ? usd / usdPerBtc * 1e8 : null);
  String? bitcoin;
  if (satAmount != null && satAmount.isFinite && satAmount >= 0) {
    bitcoin = satAmount > 0 && satAmount < 1
        ? '< ₿${1.toFormattedString(btcFormat)}'
        : '₿${satAmount.round().toFormattedString(btcFormat)}';
  }
  String? fiat;
  if (dollars != null && dollars.isFinite && dollars >= 0) {
    final haveFx = currency == 'USD' ||
        (fiatPerUsd != null && fiatPerUsd.isFinite && fiatPerUsd > 0);
    final code = haveFx ? currency : 'USD';
    final value = dollars * (haveFx && currency != 'USD' ? fiatPerUsd! : 1);
    final formatter = NumberFormat.simpleCurrency(name: code);
    final minimum = 1 / _pow10(formatter.decimalDigits ?? 2);
    fiat = value > 0 && value < minimum
        ? '< ${formatter.format(minimum)}'
        : formatter.format(value);
    if (!haveFx) fiat = '$fiat USD';
  }
  return (
    primary:
        (bitcoinFirst ? bitcoin ?? fiat : fiat ?? bitcoin) ?? 'Unavailable',
    secondary: bitcoinFirst
        ? (bitcoin == null ? null : fiat)
        : (fiat == null ? null : bitcoin)
  );
}

double _pow10(int decimals) {
  var value = 1.0;
  for (var i = 0; i < decimals; i++) {
    value *= 10;
  }
  return value;
}


/// Turns every [MoneyFeeSummary] below it into one quiet caption line
/// ("Fee about $0.12") instead of a label and value row. The Move sheet
/// sets it under its big amount; the breakdown opens on a tap, in its
/// own bottom sheet.
class MoneyFeeCaption extends InheritedWidget {
  const MoneyFeeCaption({super.key, this.enabled = true, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyFeeCaption>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(MoneyFeeCaption oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Turns every [MoneyFeeSummary] below it into one of a slip's figures
/// ([SlipFigure]): a small quiet title and the fee under it, no box and
/// no line under the number. Before there is a fee it reads zero ("$0");
/// while a new one is worked out it keeps the last one, dimmed. A tap
/// opens the breakdown in a bottom sheet; nothing ever opens in place.
/// The buy slips set it on their fee figure.
class MoneyFeeFigure extends InheritedWidget {
  const MoneyFeeFigure({super.key, this.enabled = true, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyFeeFigure>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(MoneyFeeFigure oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Inside the breakdown sheet: every [MoneyFeeSummary] is one plain line,
/// the label on the left and the amount on the right, with nothing to
/// open.
class _MoneyFeeSheetRows extends InheritedWidget {
  const _MoneyFeeSheetRows({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MoneyFeeSheetRows>() != null;

  @override
  bool updateShouldNotify(_MoneyFeeSheetRows oldWidget) => false;
}

/// States the caption leaves unsaid: there is no fee to speak of yet,
/// and the screen already says why (the amount is zero, the button reads
/// "Add funds", the source row names the shortfall).
const _captionSilentStates = {
  'Add funds to continue',
  'Enter an amount',
  'Insufficient balance',
};

/// States that stand in for a fee figure, so the caption keeps the label
/// that says which fee they are about.
const _captionLabelledStates = {
  'Shown before you confirm',
  'Shown before signing',
  'Shown in Cash App',
};

/// A compact summary with the same typography as the form around it. Fee
/// breakdowns and conversion equivalents open on a tap in a bottom sheet
/// ([_FeeBreakdownSheet]), never in place.
class MoneyFeeSummary extends ConsumerStatefulWidget {
  const MoneyFeeSummary({
    super.key,
    this.usd,
    this.sats,
    this.bitcoinFirst,
    this.label = 'Estimated fee',
    this.note,
    this.state,
    this.onRetry,
    this.details = const [],
  });
  final double? usd, sats;
  final bool? bitcoinFirst;
  final String label;
  final String? note, state;
  final VoidCallback? onRetry;
  final List<Widget> details;

  @override
  ConsumerState<MoneyFeeSummary> createState() => _MoneyFeeSummaryState();
}

class _MoneyFeeSummaryState extends ConsumerState<MoneyFeeSummary> {
  /// The summary an open breakdown sheet shows: it follows the slip, so a
  /// fee that lands while the sheet is up appears there too.
  ValueNotifier<MoneyFeeSummary>? _sheet;

  /// The figure form's last fee, kept on screen (dimmed) while the next
  /// one is worked out.
  String? _lastFigure;

  @override
  void didUpdateWidget(covariant MoneyFeeSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sheet = _sheet;
    if (sheet == null) return;
    // Never notify the sheet in the middle of this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheet == sheet) sheet.value = widget;
    });
  }

  Future<void> _openBreakdown() async {
    if (_sheet != null) return;
    HapticFeedback.selectionClick();
    final sheet = ValueNotifier<MoneyFeeSummary>(widget);
    _sheet = sheet;
    try {
      await showAppBottomSheet<void>(
        // The app's own colours, never the side tint of the slip it opens
        // from (a sheet takes its theme from where it is opened).
        context: Navigator.of(context, rootNavigator: true).context,
        builder: (_) => _FeeBreakdownSheet(summary: sheet),
      );
    } finally {
      if (_sheet == sheet) _sheet = null;
      sheet.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = widget.state == null
        ? feeAmountText(ref,
            usd: widget.usd,
            sats: widget.sats,
            bitcoinFirst: widget.bitcoinFirst)
        : (primary: '', secondary: null);
    final canExpand = widget.details.isNotEmpty ||
        (widget.state == null &&
            (widget.note != null || amount.secondary != null));
    if (_MoneyFeeSheetRows.of(context)) return _sheetRow(context, amount);
    if (MoneyFeeCaption.of(context)) {
      return _caption(context, amount, canExpand);
    }
    if (MoneyFeeFigure.of(context)) {
      return _figure(context, amount, canExpand);
    }
    final loading = widget.state == 'Calculating…';
    final label = Text(feeCopy(context, widget.label),
        style: TextStyle(color: c.textSecondary, fontSize: 15.sp));
    final value = Text(feeCopy(context, widget.state ?? amount.primary),
        textAlign: TextAlign.end,
        style: TextStyle(
          color: widget.state == null ? c.textPrimary : c.textSecondary,
          fontSize: 15.sp,
          height: 1.3,
          fontWeight: widget.state == null ? FontWeight.w600 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ));
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: 4, child: label),
        SizedBox(width: 12.w),
        if (loading) ...[
          SizedBox(
              width: 13.w,
              height: 13.w,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: c.textSecondary)),
          SizedBox(width: 8.w),
        ],
        Expanded(
            flex: 5,
            child: Align(alignment: Alignment.centerRight, child: value)),
        if (canExpand) ...[
          SizedBox(width: 6.w),
          Icon(Icons.chevron_right_rounded,
              size: 20.sp, color: c.textSecondary),
        ],
      ]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canExpand)
          Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: _openBreakdown,
              child: row,
            ),
          )
        else
          row,
        if (widget.onRetry != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onRetry,
              icon: Icon(Icons.refresh_rounded, size: 17.sp),
              label:
                  Text(context.l10n.retry, style: TextStyle(fontSize: 14.sp)),
              style: TextButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  minimumSize: Size(64.w, 40.h)),
            ),
          ),
        if (widget.note != null && widget.state != null)
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Text(feeCopy(context, widget.note!),
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13.sp, height: 1.4)),
          ),
      ],
    );
  }

  /// The figure form ([MoneyFeeFigure]): the label and the fee under it,
  /// nothing else. Zero before there is a fee; the last fee, dimmed,
  /// while the next one is worked out (or could not be); a tap opens the
  /// breakdown sheet, which also carries the state and any Retry.
  Widget _figure(BuildContext context,
      ({String primary, String? secondary}) amount, bool canExpand) {
    final state = widget.state;
    final silent = state != null && _captionSilentStates.contains(state);
    final String value;
    var dim = false;
    if (state == null) {
      value = _lastFigure = amount.primary;
    } else {
      if (silent) _lastFigure = null;
      value = _lastFigure ?? _zeroFee();
      dim = !silent;
    }
    final canOpen = canExpand || (state != null && !silent);
    return SlipFigure(
      label: feeCopy(context, widget.label),
      value: value,
      dim: dim,
      onTap: canOpen ? _openBreakdown : null,
    );
  }

  /// No fee yet, in the unit the fee would be shown in: "$0", "₿0".
  /// Needs no rate, only the person's currency.
  String _zeroFee() {
    final settings = ref.watch(settingsProvider);
    final bitcoin =
        widget.bitcoinFirst ?? settings.mainDenomination == 'bitcoin';
    if (bitcoin) return '₿0';
    return slipZeroFigure(
        NumberFormat.simpleCurrency(name: settings.currency).format(0));
  }

  /// One line of the breakdown sheet: the label on the left, the amount
  /// (or the state standing in for it) on the right, its note under it.
  Widget _sheetRow(
      BuildContext context, ({String primary, String? secondary}) amount) {
    final c = context.colors;
    final state = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Text(feeCopy(context, widget.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 15.sp)),
            ),
            SizedBox(width: 12.w),
            Expanded(
              flex: 2,
              child: Text(feeCopy(context, state ?? amount.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: state == null ? c.textPrimary : c.textSecondary,
                    fontSize: 15.sp,
                    fontWeight:
                        state == null ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
          ]),
        ),
        if (widget.note != null)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Text(feeCopy(context, widget.note!),
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13.sp, height: 1.4)),
          ),
        if (widget.details.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: widget.details,
            ),
          ),
      ],
    );
  }

  /// The one-line form: what the fee is about to be, or the state that
  /// stands in for it. Tapping it opens the breakdown sheet.
  Widget _caption(BuildContext context,
      ({String primary, String? secondary}) amount, bool canExpand) {
    final c = context.colors;
    final state = widget.state;
    if (state != null && _captionSilentStates.contains(state)) {
      return const SizedBox.shrink();
    }
    final text = state == null
        ? context.l10n.moveFeeAbout(amount.primary)
        : _captionLabelledStates.contains(state)
            ? '${feeCopy(context, widget.label)} · ${feeCopy(context, state)}'
            : feeCopy(context, state);
    final style = TextStyle(
      color: c.textSecondary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );
    final line = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(text, style: style)),
      if (canExpand) ...[
        SizedBox(width: 2.w),
        Icon(Icons.chevron_right_rounded, size: 16.sp, color: c.textSecondary),
      ],
    ]);
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Row(children: [
        Flexible(
          child: canExpand
              ? Semantics(
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8.r),
                    onTap: _openBreakdown,
                    child: line,
                  ),
                )
              : line,
        ),
        if (widget.onRetry != null) ...[
          SizedBox(width: 10.w),
          InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: widget.onRetry,
            child: Text(context.l10n.retry,
                style: style.copyWith(
                    color: c.textPrimary, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    );
  }
}

/// The fee's breakdown, in its own bottom sheet: the fee's name, the
/// figure large (its other unit under it), then one line per part, label
/// left and amount right, and the note. Follows [summary], so it updates
/// with the slip under it.
class _FeeBreakdownSheet extends StatelessWidget {
  const _FeeBreakdownSheet({required this.summary});

  final ValueListenable<MoneyFeeSummary> summary;

  @override
  Widget build(BuildContext context) => AppBottomSheetContainer(
        maxHeight: 0.8,
        child: ValueListenableBuilder<MoneyFeeSummary>(
          valueListenable: summary,
          builder: (context, s, _) => _FeeBreakdownBody(summary: s),
        ),
      );
}

class _FeeBreakdownBody extends ConsumerWidget {
  const _FeeBreakdownBody({required this.summary});

  final MoneyFeeSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = summary;
    final state = s.state;
    final amount = state == null
        ? feeAmountText(ref,
            usd: s.usd, sats: s.sats, bitcoinFirst: s.bitcoinFirst)
        : null;
    return Column(
      key: const ValueKey('money-fee-breakdown-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppBottomSheetHeader(title: feeCopy(context, s.label), compact: true),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount?.primary ?? feeCopy(context, state!),
                    maxLines: 1,
                    style: amount == null
                        ? TextStyle(
                            color: c.textSecondary,
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600)
                        : positionTileValueStyle(c),
                  ),
                ),
                if (amount?.secondary != null) ...[
                  SizedBox(height: 4.h),
                  Text(amount!.secondary!,
                      style:
                          TextStyle(color: c.textSecondary, fontSize: 14.sp)),
                ],
                if (s.onRetry != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: s.onRetry,
                      icon: Icon(Icons.refresh_rounded, size: 17.sp),
                      label: Text(context.l10n.retry,
                          style: TextStyle(fontSize: 14.sp)),
                      style: TextButton.styleFrom(
                          foregroundColor: c.textPrimary,
                          padding: EdgeInsets.zero,
                          minimumSize: Size(64.w, 40.h)),
                    ),
                  ),
                if (s.details.isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  Divider(height: 1, color: c.borderSubtle),
                  SizedBox(height: 4.h),
                  _MoneyFeeSheetRows(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: s.details,
                    ),
                  ),
                ],
                if (s.note != null) ...[
                  SizedBox(height: 8.h),
                  Text(feeCopy(context, s.note!),
                      style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          height: 1.4)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
