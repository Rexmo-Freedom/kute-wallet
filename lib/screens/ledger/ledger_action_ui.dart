// lib/screens/ledger/ledger_action_ui.dart
//
// Shared pieces for the Ledger action sheets (Wallet hardening Phase 4a,
// P4.6 and P4.7): the sheet frame, amount field, neutral choice chips,
// notes and the success confirmation. Visuals follow the app rules: sheets
// in AppBottomSheetContainer, solid or neutral buttons (no tinted chips),
// the shared KuteConfirmation for success.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetAnimatedSize;
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/theme/app_theme.dart';

String ledgerFormatUsd(double value) =>
    NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(value);

/// 6-decimal base units (USDC, USDC.e, pUSD, outcome shares) as dollars.
String ledgerFormatMicros(BigInt micros) =>
    ledgerFormatUsd(micros.toDouble() / 1e6);

/// 6-decimal outcome shares with two decimals.
String ledgerFormatShares(BigInt micros) =>
    (micros.toDouble() / 1e6).toStringAsFixed(2);

double? ledgerParseAmount(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || value.isNaN || value.isInfinite || value <= 0) {
    return null;
  }
  return value;
}

/// The shared success confirmation. Push with a navigator captured before
/// any sheet was popped.
void showLedgerConfirmation(
  NavigatorState navigator, {
  required String message,
  String? detail,
}) {
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: KuteConfirmation(
      message: message,
      detail: detail,
      showCloseButton: true,
      onDone: () => navigator.pop(),
    ),
  );
}

class LedgerActionSheetFrame extends StatelessWidget {
  const LedgerActionSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.buttons,
  });

  final String title;
  final String? subtitle;
  final List<Widget> body;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: title, subtitle: subtitle),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttons,
            ),
          ),
        ],
      ),
    );
  }
}

class LedgerNote extends StatelessWidget {
  const LedgerNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 18.sp, color: c.textTertiary),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Network fee: Free" on the Predictions claim and withdraw reviews.
/// Kute's relayer pays the Polygon fee; that detail sits behind the row's
/// chevron instead of being the fee value.
class LedgerRelayerFeeRow extends StatelessWidget {
  const LedgerRelayerFeeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MoneyFeeSummary(
      label: 'Network fee',
      state: l10n.ledgerFeeFree,
      details: [LedgerNote(text: l10n.ledgerFeeRelayerNote)],
    );
  }
}

/// Collapsed disclosure inside a sheet ("Advanced", "How this works"):
/// the nerd data pattern with a caller-chosen label. Closed by default on
/// every visit, so the rows above stay the whole story for most people.
class LedgerDisclosure extends StatefulWidget {
  const LedgerDisclosure({
    super.key,
    required this.label,
    required this.children,
    this.onExpanded,
  });

  final String label;
  final List<Widget> children;

  /// Fires once per expand (analytics).
  final VoidCallback? onExpanded;

  @override
  State<LedgerDisclosure> createState() => _LedgerDisclosureState();
}

class _LedgerDisclosureState extends State<LedgerDisclosure> {
  bool _expanded = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) widget.onExpanded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(10.r),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18.sp,
                    color: c.textTertiary,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SheetAnimatedSize(
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 4.h),
                    ...widget.children,
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// The "Advanced" disclosure: addresses, sizes, prices and other technical
/// rows a review keeps one tap away.
class LedgerAdvancedDisclosure extends StatelessWidget {
  const LedgerAdvancedDisclosure({
    super.key,
    required this.children,
    this.onExpanded,
  });

  final List<Widget> children;
  final VoidCallback? onExpanded;

  @override
  Widget build(BuildContext context) => LedgerDisclosure(
        label: context.l10n.ledgerAdvancedTitle,
        onExpanded: onExpanded,
        children: children,
      );
}

/// Neutral single-choice chips: the selected chip is the solid CTA fill,
/// the others the plain surface. Never tinted.
class LedgerChoiceChips<T> extends StatelessWidget {
  const LedgerChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.enabled = true,
  });

  final List<T> options;
  final T selected;
  final String Function(T option) label;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: 8.w),
          Expanded(
            child: Semantics(
              button: true,
              selected: options[i] == selected,
              child: Material(
                color:
                    options[i] == selected ? context.ctaFill : c.surfaceLight,
                borderRadius: BorderRadius.circular(12.r),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12.r),
                  onTap: !enabled
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onSelected(options[i]);
                        },
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    child: Text(
                      label(options[i]),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: options[i] == selected
                            ? context.ctaOnColor
                            : c.textPrimary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A dollar amount typed on the app's own keypad: the big figure with
/// the available line under it, an optional Max chip beside it, and the
/// shared [AmountKeypad] below. No focusable field, so the OS keyboard
/// never opens on these sheets.
///
/// The [controller] stays the contract with the owning sheet — every key
/// press writes the whole new string into it, so the existing parsing,
/// validation and Max handlers are untouched.
class LedgerAmountField extends StatefulWidget {
  const LedgerAmountField({
    super.key,
    required this.controller,
    required this.semanticLabel,
    this.availableText,
    this.maxLabel,
    this.onMax,
    this.onChanged,
    this.enabled = true,
    this.maxDecimals = 2,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final String? availableText;
  final String? maxLabel;
  final VoidCallback? onMax;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Dollars, so cents. Max writes two decimals too.
  final int maxDecimals;

  @override
  State<LedgerAmountField> createState() => _LedgerAmountFieldState();
}

class _LedgerAmountFieldState extends State<LedgerAmountField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant LedgerAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  // Max and any other external write land here too, so the figure and
  // the keypad always read the same string.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onKey(String value) {
    widget.controller.text = value;
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final showMax = widget.onMax != null && widget.maxLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: widget.semanticLabel,
          value: text.isEmpty ? '0' : text,
          child: BigAmountDisplay(
            prefix: r'$',
            amountText: text,
            availableLabel: widget.availableText,
            onAvailableTap:
                showMax && widget.enabled ? widget.onMax : null,
            trailing: showMax
                ? _MaxChip(
                    label: widget.maxLabel!,
                    onTap: widget.enabled ? widget.onMax : null,
                  )
                : null,
          ),
        ),
        SizedBox(height: 16.h),
        AmountKeypad(
          value: text,
          maxDecimals: widget.maxDecimals,
          enabled: widget.enabled,
          onChanged: _onKey,
        ),
        // Keeps the keypad off whatever row the sheet puts next.
        SizedBox(height: 4.h),
      ],
    );
  }
}

/// Neutral Max chip beside the big figure. Surface fill and a hairline
/// border, never a tint.
class _MaxChip extends StatelessWidget {
  const _MaxChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? c.textTertiary : c.textPrimary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
