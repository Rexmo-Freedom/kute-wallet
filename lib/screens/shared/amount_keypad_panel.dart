// lib/screens/shared/amount_keypad_panel.dart
//
// Shared building blocks for the full-screen amount entry (Phantom
// Buy-style) used by the Move flow (deposits, withdrawals, exchange,
// the coming-soon fiat screen):
//
//   * [BigAmountDisplay] — the one big typed number, left-aligned,
//     grey while zero and primary once nonzero, with the conversion
//     line and the available-balance line beneath it. Shows a
//     [SkeletonBar] while the rate is loading.
//   * [AmountPercentChips] — the 25% / 50% / 100% row (100% = Max).
//   * [AmountQuickChips] — fixed amounts ending in Max (the Move sheet).
//   * [AmountMaxChip] — that chip alone, beside the figure (the
//     Investing and Predictions slips).
//   * [AmountKeypad] — the shared [CustomKeypad] wired with the
//     typed-amount editing rules (single decimal point, capped
//     decimals, no leading-zero runs).
//
// The editing rules ([amountAppendKey] / [amountBackspace]) are pure
// string transforms so both flows share identical behavior.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/theme/app_theme.dart';

/// Appends a keypad key to a typed amount string, enforcing:
///   * at most one decimal point ('.' on an empty string yields '0.');
///   * at most [maxDecimals] digits after the point (0 = integer only);
///   * a bare leading '0' is replaced by the next digit ("05" never
///     appears; a second '0' on '0' is a no-op);
///   * the integer part is capped at 12 digits so the display can't
///     overflow into absurd numbers.
String amountAppendKey(String current, String key, {int maxDecimals = 2}) {
  if (key == '.') {
    if (maxDecimals <= 0) return current;
    if (current.contains('.')) return current;
    return current.isEmpty ? '0.' : '$current.';
  }
  final dot = current.indexOf('.');
  if (dot >= 0) {
    if (current.length - dot - 1 >= maxDecimals) return current;
    return current + key;
  }
  if (current == '0') {
    return key == '0' ? current : key;
  }
  if (current.length >= 12) return current;
  return current + key;
}

/// Deletes the last typed character. Empty stays empty (== 0).
String amountBackspace(String current) =>
    current.isEmpty ? current : current.substring(0, current.length - 1);

/// Groups the integer part of a typed amount with thousands separators
/// while leaving whatever the user typed after the decimal point
/// untouched, so the big number reads "12,500.5" as they type.
/// A formatted money string as the plain decimal the keypad understands,
/// whatever the locale's separators. Only the digits are trusted and the
/// decimal point is put back by count: "1,00" → "1.00", "0,07" → "0.07",
/// "1.234,56" → "1234.56", "1,234.56" → "1234.56". Stripping commas as if
/// they were thousands separators turned a euro user's €1,00 into 100.
String canonicalDecimalText(String formatted, {int decimals = 2}) {
  final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final padded = digits.padLeft(decimals + 1, '0');
  final whole = padded.substring(0, padded.length - decimals);
  final fraction = padded.substring(padded.length - decimals);
  final trimmedWhole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return decimals == 0 ? trimmedWhole : '$trimmedWhole.$fraction';
}

String groupTypedAmount(String raw) {
  if (raw.isEmpty) return raw;
  final dot = raw.indexOf('.');
  final intPart = dot >= 0 ? raw.substring(0, dot) : raw;
  final rest = dot >= 0 ? raw.substring(dot) : '';
  final grouped =
      intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '$grouped$rest';
}

/// The Phantom-style hero: one big typed number with a conversion line
/// and the available balance underneath. Purely presentational — the
/// owning screen holds the typed string and the derived labels.
class BigAmountDisplay extends StatelessWidget {
  /// Symbol rendered before the number ('$', '€'…). Empty for BTC/sats.
  final String prefix;

  /// The raw typed amount ('' renders as 0 in the zero style).
  final String amountText;

  /// Unit rendered after the number (' sats', ' BTC'…). Empty for fiat.
  final String suffix;

  /// True while the rate needed to interpret the amount is loading —
  /// the number is replaced by a skeleton bar.
  final bool loading;

  /// Small line under the number (e.g. "≈ 21,340 sats from Spending").
  final String? conversionLabel;

  /// True renders [conversionLabel] in the error color (inline
  /// validation like an over-balance amount).
  final bool conversionIsError;

  /// Skeleton stand-in for the conversion line (e.g. quote loading).
  final bool conversionLoading;

  /// "518 sats available" line. Null hides it.
  final String? availableLabel;

  /// True turns the available line red — the typed amount exceeds the
  /// balance (it clamps to the maximum on dispatch).
  final bool availableExceeded;

  /// Tapping the available line fills the maximum. Every sheet that shows
  /// a balance there wires this; null leaves the line as plain text.
  final VoidCallback? onAvailableTap;

  /// The smallest amount the venue takes ("Minimum \$3.40"), said on the
  /// available line after a middle dot. Null leaves the line as it was.
  final String? minimumLabel;

  /// True paints [minimumLabel] (only that part of the line) in the
  /// palette's error color: the typed amount is under it.
  final bool minimumIsError;

  /// One more quiet line under the available line, in its caption style
  /// (the Investing slip says what the order does to a position already
  /// held). Null leaves it out.
  final String? noteLabel;

  /// Optional widget rendered to the right of the number (the fiat
  /// currency selector pill).
  final Widget? trailing;

  /// Unit control rendered CENTRED under the figure, the arrangement the
  /// Receive request sheet uses and the one this component now leads
  /// with. Pass [trailing] instead when a screen needs it beside the
  /// number.
  final Widget? unitControl;

  /// Centres the figure and its lines. The default is left-aligned,
  /// which is what the Move and Send steps want.
  final bool centered;

  const BigAmountDisplay({
    super.key,
    required this.amountText,
    this.prefix = '',
    this.suffix = '',
    this.loading = false,
    this.conversionLabel,
    this.conversionIsError = false,
    this.conversionLoading = false,
    this.availableLabel,
    this.availableExceeded = false,
    this.onAvailableTap,
    this.minimumLabel,
    this.minimumIsError = false,
    this.noteLabel,
    this.trailing,
    this.unitControl,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isZero =
        amountText.isEmpty || (double.tryParse(amountText) ?? 0) == 0;
    final display = amountText.isEmpty ? '0' : groupTypedAmount(amountText);
    // One rhythm for every amount screen in the app: the figure, then a
    // secondary line at a readable size, then the unit control. Taken
    // from the Receive request sheet, which is the proportion the owner
    // picked.
    final align = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: loading
                  ? SkeletonBar(160.w, 48.h, radius: 12.r)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment:
                          centered ? Alignment.center : Alignment.centerLeft,
                      child: Text(
                        '$prefix$display$suffix',
                        maxLines: 1,
                        style: TextStyle(
                          color: isZero ? c.textTertiary : c.textPrimary,
                          fontSize: 56.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
            ),
            if (trailing != null) ...[
              SizedBox(width: 10.w),
              trailing!,
            ],
          ],
        ),
        SizedBox(height: 8.h),
        if (conversionLoading)
          SkeletonBar(120.w, 14.h)
        else if (conversionLabel != null)
          Text(
            conversionLabel!,
            textAlign: align,
            style: TextStyle(
              color: conversionIsError ? AppColors.error : c.textTertiary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        if (availableLabel != null || minimumLabel != null) ...[
          SizedBox(height: 6.h),
          _TappableAvailable(
            onTap: onAvailableTap,
            centered: centered,
            child: Text.rich(
              TextSpan(children: [
                if (availableLabel != null) TextSpan(text: availableLabel),
                if (availableLabel != null && minimumLabel != null)
                  const TextSpan(text: ' · '),
                if (minimumLabel != null)
                  TextSpan(
                    text: minimumLabel,
                    // The palette's error ink: red on the app ground, the
                    // full-contrast ink on a side-tinted sheet.
                    style: minimumIsError ? TextStyle(color: c.error) : null,
                  ),
              ]),
              textAlign: align,
              style: TextStyle(
                color: availableExceeded ? AppColors.error : c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (noteLabel != null) ...[
          SizedBox(height: 4.h),
          Text(
            noteLabel!,
            textAlign: align,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (unitControl != null) ...[
          SizedBox(height: 14.h),
          Center(child: unitControl!),
        ],
      ],
    );
  }
}

/// Wraps the available line in a hit target when the owning sheet can
/// fill the maximum, and leaves it untouched when it cannot. The padding
/// is horizontal only so the line keeps its place in the stack.
class _TappableAvailable extends StatelessWidget {
  const _TappableAvailable(
      {required this.onTap, required this.centered, required this.child});
  final VoidCallback? onTap;
  final bool centered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The 25% / 50% / 100% quick-amount row. 100% means Max.
class AmountPercentChips extends StatelessWidget {
  final void Function(double ratio) onPercent;
  final bool enabled;

  const AmountPercentChips({
    super.key,
    required this.onPercent,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (final r in const [0.25, 0.5, 1.0]) ...[
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? () => onPercent(r) : null,
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 9.h),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: c.borderSubtle, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${(r * 100).round()}%',
                    style: TextStyle(
                      color: enabled ? c.textPrimary : c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (r != 1.0) SizedBox(width: 8.w),
        ],
      ],
    );
  }
}

/// One chip of an [AmountQuickChips] row.
class AmountQuickChip {
  const AmountQuickChip({
    required this.label,
    required this.onTap,
    this.dimmed = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Reads as out of reach (an amount above the balance) while staying
  /// tappable: the owning sheet answers an over-balance amount itself.
  final bool dimmed;
}

/// A quick-amount row of fixed amounts ending in Max, on the same chip
/// chrome as [AmountPercentChips].
class AmountQuickChips extends StatelessWidget {
  final List<AmountQuickChip> chips;
  final bool enabled;

  const AmountQuickChips({
    super.key,
    required this.chips,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) SizedBox(width: 8.w),
          Expanded(
            child: _AmountChipFace(
              label: chips[i].label,
              onTap: enabled ? chips[i].onTap : null,
              dimmed: chips[i].dimmed,
            ),
          ),
        ],
      ],
    );
  }
}

/// One Max chip at its own width, for the [BigAmountDisplay.trailing]
/// slot beside the figure: the [AmountQuickChips] chip, without the row.
/// Null [onTap] leaves it inert and dimmed. The owning sheet runs its
/// own haptic and tracking in [onTap].
class AmountMaxChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// What a screen reader says instead of [label] ("Use maximum" for a
  /// chip that reads "Max").
  final String? semanticLabel;

  const AmountMaxChip({
    super.key,
    required this.label,
    required this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return _AmountChipFace(
      label: label,
      onTap: onTap,
      semanticLabel: semanticLabel,
      horizontalPadding: 14.w,
    );
  }
}

/// The quick-amount chip itself: surface fill, hairline border, 12
/// radius, a bold 13 label. Fills the width it is given ([AmountQuickChips]
/// hands it an equal share) and otherwise hugs its label.
class _AmountChipFace extends StatelessWidget {
  const _AmountChipFace({
    required this.label,
    required this.onTap,
    this.dimmed = false,
    this.semanticLabel,
    this.horizontalPadding = 0,
  });

  final String label;
  final VoidCallback? onTap;
  final bool dimmed;
  final String? semanticLabel;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final face = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.symmetric(
              vertical: 9.h, horizontal: horizontalPadding),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            excluding: semanticLabel != null,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color:
                    onTap != null && !dimmed ? c.textPrimary : c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return face;
    return Semantics(label: semanticLabel, button: true, child: face);
  }
}

/// The shared keypad wired with the typed-amount editing rules. The
/// owning screen holds the string; every key press reports the full
/// new value through [onChanged].
class AmountKeypad extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  /// 0 hides the decimal key entirely (sats are integers).
  final int maxDecimals;
  final bool enabled;

  const AmountKeypad({
    super.key,
    required this.value,
    required this.onChanged,
    this.maxDecimals = 2,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: CustomKeypad(
          // Amount sheets share the screen with a hero figure and an
          // action, so the pad uses its shorter geometry.
          compact: true,
          showDecimal: maxDecimals > 0,
          onDigitPressed: (d) =>
              onChanged(amountAppendKey(value, d, maxDecimals: maxDecimals)),
          onDecimalPressed: () =>
              onChanged(amountAppendKey(value, '.', maxDecimals: maxDecimals)),
          onBackspacePressed: () => onChanged(amountBackspace(value)),
        ),
      ),
    );
  }
}

/// X-close + operation title header of a full-screen amount entry
/// ("Deposit to Polymarket", "Buy Bitcoin"…). The X pops the route.
class AmountScreenHeader extends StatelessWidget {
  final String title;

  const AmountScreenHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        const KuteCloseButton(),
        SizedBox(width: 12.w),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.05,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small flag + code pill rendered next to the fiat big number — taps
/// into the flow's currency picker.
class AmountCurrencyPill extends StatelessWidget {
  final String flag;
  final String code;
  final VoidCallback? onTap;

  const AmountCurrencyPill({
    super.key,
    required this.flag,
    required this.code,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.buttonBorder,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.buttonBorder,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.buttonBorder,
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flag, style: TextStyle(fontSize: 16.sp)),
              SizedBox(width: 6.w),
              Text(
                code,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (onTap != null)
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: c.textSecondary, size: 18.sp),
            ],
          ),
        ),
      ),
    );
  }
}
