import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/fee_copy.dart';
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
/// sets it under its big amount; the breakdown still opens on a tap, as
/// ordinary rows.
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
/// breakdowns and conversion equivalents are available on demand.
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
  bool _expanded = false;

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
    if (MoneyFeeCaption.of(context)) {
      return _caption(context, amount, canExpand);
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
          Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20.sp,
              color: c.textSecondary),
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
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: () => setState(() => _expanded = !_expanded),
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
        if (canExpand && _expanded) ...[
          Divider(height: 1, color: c.borderSubtle),
          if (amount.secondary != null)
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Text(amount.secondary!,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
            ),
          ...widget.details,
        ],
        if (widget.note != null && (_expanded || widget.state != null))
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Text(feeCopy(context, widget.note!),
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13.sp, height: 1.4)),
          ),
      ],
    );
  }

  /// The one-line form: what the fee is about to be, or the state that
  /// stands in for it. Tapping it opens the same breakdown the row does.
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
        Icon(
            _expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 16.sp,
            color: c.textSecondary),
      ],
    ]);
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Flexible(
              child: canExpand
                  ? Semantics(
                      button: true,
                      expanded: _expanded,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8.r),
                        onTap: () => setState(() => _expanded = !_expanded),
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
          if (canExpand && _expanded)
            // The breakdown is ordinary rows, not captions of captions.
            MoneyFeeCaption(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (amount.secondary != null)
                    Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: Text(amount.secondary!,
                          style: TextStyle(
                              color: c.textSecondary, fontSize: 14.sp)),
                    ),
                  ...widget.details,
                  if (widget.note != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 10.h),
                      child: Text(feeCopy(context, widget.note!),
                          style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.sp,
                              height: 1.4)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
