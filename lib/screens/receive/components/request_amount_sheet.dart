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
import 'package:kute/theme/app_theme.dart';

/// The amount the user asked for, as typed, and the unit it is in.
typedef RequestedAmount = ({String amount, String currency});

/// Opens the request-amount sheet. Resolves to null when dismissed.
Future<RequestedAmount?> showRequestAmountSheet(BuildContext context) {
  return showAppBottomSheet<RequestedAmount>(
    context: context,
    builder: (_) => const RequestAmountSheet(),
  );
}

class RequestAmountSheet extends ConsumerStatefulWidget {
  const RequestAmountSheet({super.key});

  @override
  ConsumerState<RequestAmountSheet> createState() => _RequestAmountSheetState();
}

class _RequestAmountSheetState extends ConsumerState<RequestAmountSheet> {
  /// The raw typed amount, exactly as it is returned to the caller
  /// (plain digits and at most one '.', never grouped).
  String _typed = '';

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
    final currency = ref.watch(inputCurrencyProvider);
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final typed = _typed;
    final sats = typed.isEmpty
        ? 0
        : ref.watch(inputToSatsProvider((amount: typed, currency: currency)));
    // The other side of the amount: fiat under a bitcoin figure, sats
    // under a fiat figure. Only once something is typed.
    String secondary = '';
    if (sats > 0) {
      secondary = _isBitcoinUnit(currency)
          ? ref.watch(conversionToFiatProvider(sats))
          : '₿${sats.toFormattedString(btcFormat)}';
    }

    return AppBottomSheetContainer(
      maxHeight: 0.94,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: context.l10n.receiveRequestAmount),
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
                      centered: true,
                      unitControl: _unitChip(c, currency),
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
              onPressed: sats > 0
                  ? () => Navigator.of(context)
                      .pop((amount: typed, currency: currency))
                  : null,
              text: context.l10n.receiveCreateRequest,
            ),
          ),
        ],
      ),
    );
  }

  /// Unit chip: tap opens the unit picker. Neutral surface, no tint.
  Widget _unitChip(AppColorsExtension c, String currency) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        _showUnitPicker();
      },
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
            SizedBox(width: 2.w),
            Icon(Icons.unfold_more_rounded, color: c.textTertiary, size: 16.sp),
          ],
        ),
      ),
    );
  }

  void _showUnitPicker() {
    showAmountUnitPicker(
      context,
      selected: ref.read(inputCurrencyProvider),
      iconBuilder: _currencyIcon,
      onSelected: (currency) {
        ref.read(inputCurrencyProvider.notifier).state = currency;
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
