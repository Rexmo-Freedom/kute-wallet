// Request a specific amount on the Receive screen.
//
// Opened from the Request amount pill under the QR. The sheet is the
// same hero amount the Send screen uses (56sp figure with the currency
// prefix, unit chip under it) and returns the typed amount plus the
// unit it was typed in; the caller turns that into a Lightning invoice
// or a BIP21 amount depending on the QR format in use.
//
// The figure is typed on the app's own keypad (AmountKeypad), never the
// OS keyboard: the sheet holds the raw string and the keypad enforces
// the per-unit decimals (0 sats, 8 BTC, 2 fiat).

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/address_receive_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/amount_unit_picker.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetHeader;
import 'package:kute/theme/app_theme.dart';

/// The amount the user asked for, as typed, and the unit it is in.
typedef RequestedAmount = ({String amount, String currency});

/// The minimum line and the check of a request whose limits can change
/// while the sheet is open (a live read landing).
typedef RequestAmountLimits = ({
  String? minimumLabel,
  String? Function(RequestedAmount requested)? validate,
});

/// Opens the request-amount sheet. Resolves to null when dismissed.
///
/// The Lightning receive passes nothing. The one-time receive of another
/// coin passes [fixedCurrency] `USD` for the Dollars receive (the figure
/// is typed in dollars and the unit cannot be changed), the route's
/// minimum as [minimumLabel] ("Minimum \$2.00", on the sheet's own
/// minimum line), and [validate], which answers the copy to show on that
/// line in the error colour (and disables "Create request") while the
/// typed amount is outside the route's limits.
///
/// [limits], when given, replaces [minimumLabel] and [validate] and is
/// followed live: the sheet opens at once and the minimum line and the
/// check move when the route's read lands. [pending] answers the read
/// still in flight, if any: "Create request" waits for it (the button's
/// loading state) and checks the amount again with what it brought.
Future<RequestedAmount?> showRequestAmountSheet(
  BuildContext context, {
  String? fixedCurrency,
  String? minimumLabel,
  String? Function(RequestedAmount requested)? validate,
  ValueListenable<RequestAmountLimits>? limits,
  Future<void>? Function()? pending,
}) {
  return showAppBottomSheet<RequestedAmount>(
    context: context,
    builder: (_) => RequestAmountSheet(
      fixedCurrency: fixedCurrency,
      minimumLabel: minimumLabel,
      validate: validate,
      limits: limits,
      pending: pending,
    ),
  );
}

class RequestAmountSheet extends ConsumerStatefulWidget {
  const RequestAmountSheet({
    super.key,
    this.fixedCurrency,
    this.minimumLabel,
    this.validate,
    this.limits,
    this.pending,
  });

  /// The one unit the amount is typed in, or null for the person's
  /// receive unit with its picker (sats, BTC or their fiat).
  final String? fixedCurrency;

  /// Said on the minimum line under the figure. Null leaves it out.
  final String? minimumLabel;

  /// Null when the typed amount may be requested; otherwise the copy the
  /// minimum line shows in the error colour instead of [minimumLabel].
  final String? Function(RequestedAmount requested)? validate;

  /// The minimum line and the check, followed live; when set, it
  /// replaces [minimumLabel] and [validate].
  final ValueListenable<RequestAmountLimits>? limits;

  /// The limits read still in flight, or null. "Create request" waits
  /// for it before checking the amount.
  final Future<void>? Function()? pending;

  @override
  ConsumerState<RequestAmountSheet> createState() => _RequestAmountSheetState();
}

class _RequestAmountSheetState extends ConsumerState<RequestAmountSheet> {
  /// The raw typed amount, exactly as it is returned to the caller
  /// (plain digits and at most one '.', never grouped).
  String _typed = '';

  /// "Create request" waiting for the limits read in flight.
  bool _waiting = false;

  String? get _minimumLabel => widget.limits == null
      ? widget.minimumLabel
      : widget.limits!.value.minimumLabel;

  String? Function(RequestedAmount requested)? get _validate =>
      widget.limits == null ? widget.validate : widget.limits!.value.validate;

  @override
  void initState() {
    super.initState();
    widget.limits?.addListener(_limitsChanged);
  }

  @override
  void didUpdateWidget(RequestAmountSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limits != widget.limits) {
      oldWidget.limits?.removeListener(_limitsChanged);
      widget.limits?.addListener(_limitsChanged);
    }
  }

  @override
  void dispose() {
    widget.limits?.removeListener(_limitsChanged);
    super.dispose();
  }

  void _limitsChanged() {
    if (mounted) setState(() {});
  }

  /// Pops [requested] once the limits read in flight (if any) is back and
  /// the amount still passes the latest check.
  Future<void> _submit(RequestedAmount requested) async {
    final inFlight = widget.pending?.call();
    if (inFlight != null) {
      setState(() => _waiting = true);
      try {
        await inFlight;
      } catch (_) {
        // A failed read leaves the check as it is; the quote decides.
      }
      if (!mounted) return;
      setState(() => _waiting = false);
      if (_validate?.call(requested) != null) return;
    }
    if (mounted) Navigator.of(context).pop(requested);
  }

  /// Decimals the unit allows — the same rule the field used to apply
  /// through DecimalTextInputFormatter.
  int _decimalsFor(String currency) =>
      currency == 'Sats' ? 0 : (currency == 'BTC' ? 8 : 2);

  bool _isBitcoinUnit(String currency) =>
      currency == 'BTC' || currency == 'Sats';

  String _prefixFor(String code) {
    switch (code) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'BRL':
        return 'R\$';
      case 'CHF':
        return 'Fr';
      case 'BTC':
      case 'Sats':
        return '₿';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fixed = widget.fixedCurrency;
    final String currency =
        fixed ?? ref.watch<String>(receiveInputCurrencyProvider);
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final typed = _typed;
    // A fixed unit is its own amount: no conversion to sats behind it.
    final sats = typed.isEmpty || fixed != null
        ? 0
        : ref.watch(inputToSatsProvider((amount: typed, currency: currency)));
    final positive =
        fixed != null ? (double.tryParse(typed) ?? 0) > 0 : sats > 0;
    // The other side of the amount: fiat under a bitcoin figure, sats
    // under a fiat figure. Only once something is typed.
    String secondary = '';
    if (sats > 0) {
      secondary = _isBitcoinUnit(currency)
          ? ref.watch(conversionToFiatProvider(sats))
          : '₿${sats.toFormattedString(btcFormat)}';
    }
    final error =
        positive ? _validate?.call((amount: typed, currency: currency)) : null;

    return AppBottomSheetContainer(
      maxHeight: 0.94,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The close X on the left, as on every receive sheet (this
          // sheet only ever opens from a receive).
          const ReceiveSheetHeader(leading: KuteCloseButton()),
          AppBottomSheetHeader(
              title: context.l10n.receiveRequestAmount, showDragHandle: false),
          // Hero block. It is the part that gives way on a short screen
          // or at a large text scale, so the keypad and the one CTA
          // below always stay on screen.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero amount: the same 56sp figure as the Send
                  // screen, with the currency prefix dimmed until the
                  // user types. Nothing here is focusable, so the OS
                  // keyboard never opens.
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: BigAmountDisplay(
                      prefix: _prefixFor(currency),
                      amountText: typed,
                      conversionLabel: secondary,
                      minimumLabel: error ?? _minimumLabel,
                      minimumIsError: error != null,
                      centered: true,
                      unitControl:
                          _unitChip(c, currency, picker: fixed == null),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          // The app's own keypad, so the amount is typed without ever
          // raising the OS keyboard. Decimals follow the unit.
          AmountKeypad(
            value: typed,
            maxDecimals: _decimalsFor(currency),
            onChanged: (value) => setState(() => _typed = value),
          ),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: AppButton(
              onPressed: positive && error == null && !_waiting
                  ? () => _submit((amount: typed, currency: currency))
                  : null,
              isLoading: _waiting,
              text: context.l10n.receiveCreateRequest,
            ),
          ),
        ],
      ),
    );
  }

  /// Unit chip: tap opens the unit picker. Neutral surface, no tint.
  /// With a fixed unit ([picker] false) the chip only names it.
  Widget _unitChip(AppColorsExtension c, String currency,
      {bool picker = true}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: picker
          ? () {
              HapticFeedback.selectionClick();
              _showUnitPicker();
            }
          : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _currencyIcon(currency, 16.sp),
            SizedBox(width: 6.w),
            Text(
              currency,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (picker) ...[
              SizedBox(width: 2.w),
              Icon(Icons.unfold_more_rounded,
                  color: c.textTertiary, size: 16.sp),
            ],
          ],
        ),
      ),
    );
  }

  void _showUnitPicker() {
    showAmountUnitPicker(
      context,
      selected: ref.read(receiveInputCurrencyProvider),
      iconBuilder: _currencyIcon,
      onSelected: (currency) {
        ref.read(receiveInputCurrencyProvider.notifier).state = currency;
        ref.read(isBitcoinInputProvider.notifier).state =
            _isBitcoinUnit(currency);
        // The typed digits belong to the old unit's decimals; start over.
        if (mounted) {
          setState(() => _typed = '');
        } else {
          _typed = '';
        }
        // Remember the pick across opens (see kReceiveUnitPrefKey).
        try {
          if (Hive.isBoxOpen('settings')) {
            Hive.box('settings').put(kReceiveUnitPrefKey, currency);
          }
        } catch (_) {}
      },
    );
  }

  Widget _currencyIcon(String currency, double size) {
    if (currency == 'BTC' || currency == 'Sats') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4.r),
        child: SvgPicture.asset(
          currency == 'BTC'
              ? 'lib/assets/bitcoin-icon.svg'
              : 'lib/assets/sats-icon.svg',
          width: size,
          height: size,
        ),
      );
    }
    return Text(_currencyFlag(currency), style: TextStyle(fontSize: size));
  }

  String _currencyFlag(String code) {
    switch (code) {
      case 'USD':
        return '🇺🇸';
      case 'EUR':
        return '🇪🇺';
      case 'GBP':
        return '🇬🇧';
      case 'BRL':
        return '🇧🇷';
      case 'CHF':
        return '🇨🇭';
      default:
        return '';
    }
  }
}
