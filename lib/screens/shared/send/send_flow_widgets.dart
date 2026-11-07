// lib/screens/shared/send/send_flow_widgets.dart
//
// THE PIECES BOTH SEND FLOWS ARE BUILT FROM.
//
// Send bitcoin (`confirm_send.dart`) and Send dollars
// (`usd/usd_send_screen.dart`) are the same three screens to the person
// using them: an amount on the app's own keypad, a recipient field that
// recognises whatever is pasted or scanned, and a review with one Send
// button. They keep separate money paths on purpose (a dollar send must
// never fall back to spending bitcoin), so what they share is everything
// on screen: the frame, the recipient field, the list cards under it,
// the clipboard nudge and the review rows. Each widget here was lifted
// out of the bitcoin send as it was, so that flow renders exactly as
// before and the dollar flow cannot drift from it.
//
// Presentation only: no provider, no route table and no money call.

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show groupTypedAmount;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/theme/app_theme.dart';

/// The send stepper's body under the app bar: the screen gradient, the
/// step progress, the steps as pages the flow advances itself, and the
/// shared bottom action.
class SendStepperFrame extends StatefulWidget {
  const SendStepperFrame({
    super.key,
    required this.progress,
    required this.controller,
    required this.pages,
    required this.cta,
    this.onPageChanged,
    this.bleedPages = const {},
  });

  /// The step progress bar (or an empty box for a one-step flow).
  final Widget progress;
  final PageController controller;
  final List<Widget> pages;

  /// The shared Continue under the pages. Each step decides whether it
  /// shows one.
  final Widget cta;
  final ValueChanged<int>? onPageChanged;

  /// Pages that run to the sheet's bottom edge, as the Dollars Send does
  /// (founder, 1 November 2026: "things get cut"): while one of them is
  /// settled on screen, nothing is reserved under the pages (no bottom
  /// inset, no room for the Continue) and the shared [cta] takes no
  /// height, so the page's one scroll view flows under the floating bar
  /// and pads its own end by the bar's clearance (kuteBarScrollClearance)
  /// plus the home-indicator inset. While pages slide, the frame keeps
  /// its usual reserve, so the next page lays out at its final size.
  final Set<int> bleedPages;

  @override
  State<SendStepperFrame> createState() => _SendStepperFrameState();
}

class _SendStepperFrameState extends State<SendStepperFrame> {
  /// A text field (the recipient) has focus. The steps make room for the
  /// keyboard only then: a step that has just taken over from the field
  /// (Continue puts the keyboard away) lays out at its full height at
  /// once instead of being squeezed while the keyboard slides down. The
  /// amount step's keypad has no room to give.
  bool _textFocus = false;

  /// A [SendStepperFrame.bleedPages] page is settled on screen.
  bool _bleeding = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
    _textFocus = _hasTextFocus();
    widget.controller.addListener(_onPage);
    _bleeding = _settledOnBleedPage();
  }

  @override
  void didUpdateWidget(SendStepperFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPage);
      widget.controller.addListener(_onPage);
    }
    _bleeding = _settledOnBleedPage();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    widget.controller.removeListener(_onPage);
    super.dispose();
  }

  /// Settled exactly on a bleed page: false the moment a slide starts
  /// (the page leaving shrinks unseen, the next one is laid out at its
  /// final size), true again only once a slide back has finished.
  bool _settledOnBleedPage() {
    if (widget.bleedPages.isEmpty) return false;
    final ctrl = widget.controller;
    final page = ctrl.hasClients && ctrl.position.haveDimensions
        ? ctrl.page
        : ctrl.initialPage.toDouble();
    if (page == null || page != page.roundToDouble()) return false;
    return widget.bleedPages.contains(page.round());
  }

  void _onPage() {
    final next = _settledOnBleedPage();
    if (next != _bleeding && mounted) setState(() => _bleeding = next);
  }

  static bool _hasTextFocus() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  void _onFocus() {
    final next = _hasTextFocus();
    if (next != _textFocus && mounted) setState(() => _textFocus = next);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets =
        _textFocus ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    // Bottom padding for the Continue CTA. iOS sits ~44dp above the
    // home indicator (was 32.h); Android adds the gesture-nav inset
    // on top of a 28.h baseline.
    // With the keyboard up the home indicator is under it, so the CTA
    // rests a short, even gap above the keys (pinned there, frame for
    // frame with the platform's keyboard animation).
    final bottomPad = _bleeding
        ? 0.0
        : viewInsets > 0
            ? 12.h
            : Platform.isAndroid
                ? 28.h + MediaQuery.of(context).padding.bottom
                : 44.h;
    return Container(
      decoration: AppDecorations.screenGradient(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // 20.w horizontal padding so the Continue CTA sits inside
          // the standard screen gutter instead of stretching nearly
          // edge-to-edge.
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, bottomPad + viewInsets),
          child: Column(
            children: [
              widget.progress,
              SizedBox(height: 12.h),
              Expanded(
                child: PageView(
                  controller: widget.controller,
                  // Steps advance only via the Continue/Next buttons.
                  // Swiping must NOT skip a step — it would bypass the
                  // per-step validation and completion tracking.
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: widget.onPageChanged,
                  children: widget.pages,
                ),
              ),
              // A bleed page reserves nothing: the Continue (the bar's
              // scope) stays mounted, at no height. One widget type in
              // both states, so the bar's scope is never remounted.
              Align(
                alignment: Alignment.bottomCenter,
                heightFactor: _bleeding ? 0 : 1,
                child: widget.cta,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One step of a send sheet, with no visible heading (founder decision,
/// 14 October 2026): the sheet's own header (close or back, the wallet
/// pill) is all the chrome a step gets, and its content starts right
/// under the progress bar. The step's name is still announced to screen
/// readers as a header. [trailing], when given, sits on its own short
/// row, right-aligned, above the content (Sal is the bar, never here).
class SendStepPage extends StatelessWidget {
  const SendStepPage({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  /// Read out as the step's header; never drawn.
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: title,
            child: const SizedBox(height: 1),
          ),
          if (trailing != null) ...[
            Align(alignment: Alignment.centerRight, child: trailing),
            SizedBox(height: 8.h),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The hero figure's type: the one big number on the amount and review
/// steps.
TextStyle sendHeroAmountStyle(Color color) => TextStyle(
      color: color,
      fontSize: 56.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A typed decimal amount as one big static number with its currency
/// prefix. The raw string carries no thousands separators and is grouped
/// only for display, so the keypad can read it straight back.
class SendTypedAmountHero extends StatelessWidget {
  const SendTypedAmountHero({
    super.key,
    required this.prefix,
    required this.typed,
    this.overBalance = false,
  });

  final String prefix;
  final String typed;
  final bool overBalance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasDigits = typed.isNotEmpty && (double.tryParse(typed) ?? 0) != 0;
    final color = !hasDigits
        ? c.textTertiary
        : overBalance
            ? AppColors.marketDown
            : c.textPrimary;
    final amountTextStyle = sendHeroAmountStyle(color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(prefix, style: amountTextStyle),
        SizedBox(width: 6.w),
        Text(typed.isEmpty ? '0' : groupTypedAmount(typed),
            maxLines: 1, style: amountTextStyle),
      ],
    );
  }
}

/// The unit pill beside the amount hero. With [onTap] it is the control
/// that changes the unit; without one it only names it.
class SendAmountUnitPill extends StatelessWidget {
  final String code;
  final Widget icon;
  final VoidCallback? onTap;

  const SendAmountUnitPill(
      {super.key, required this.code, required this.icon, this.onTap});

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
          constraints: BoxConstraints(minHeight: 48.h),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.buttonBorder,
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            icon,
            SizedBox(width: 8.w),
            // A longer label (the dollar send's coin · network) gives way
            // with an ellipsis rather than overflowing at large text.
            Flexible(
              child: Text(code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
                      letterSpacing: -0.2)),
            ),
            if (onTap != null) ...[
              SizedBox(width: 6.w),
              Icon(Icons.expand_more_rounded,
                  color: c.textSecondary, size: 20.sp),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── The bitcoin amount step's pieces ─────────────────────────────────
//
// Lifted out of the Bitcoin Send's amount step (confirm_send.dart) so a
// screen that asks for a bitcoin amount the same way ("Send to anyone",
// share/send_to_anyone_sheet.dart; founder, 6 November 2026: "this one
// must have the sats and such, like here") draws it identically: the big
// figure in the chosen unit (₿ sats, ₿ BTC or a fiat), the other unit's
// figure with the ⇅ swap under it, the "328,686 sats available · $248.82"
// line and the unit pill ([SendAmountUnitPill] with [sendCurrencyIcon]).

/// The longest run of digits the Bitcoin figure takes (≈100 BTC in sats).
const int kSendAtmMaxDigits = 10;

/// The fiat units the unit sheet offers beside sats and BTC.
const Set<String> kSendFiatUnits = {'USD', 'EUR', 'GBP', 'BRL', 'CHF'};

/// Whether [unit] is a Bitcoin unit ('Sats' or 'BTC') rather than a fiat.
bool sendIsBitcoinUnit(String unit) => unit == 'Sats' || unit == 'BTC';

/// The symbol a figure in [code] starts with: ₿ for sats and BTC, $, €, …
String sendCurrencyPrefix(String code) {
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
      return '₿';
    case 'Sats':
      return '₿';
    default:
      return '';
  }
}

/// The unit's mark in the unit pill and the unit sheet: the bitcoin or
/// the sats icon, a fiat's flag.
Widget sendCurrencyIcon(String code, {required double size}) {
  switch (code) {
    case 'BTC':
      return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.3),
          child: SvgPicture.asset('lib/assets/bitcoin-icon.svg',
              width: size, height: size));
    case 'Sats':
      return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.3),
          child: SvgPicture.asset('lib/assets/sats-icon.svg',
              width: size, height: size));
    default:
      return Text(_sendCurrencyFlag(code), style: TextStyle(fontSize: size));
  }
}

String _sendCurrencyFlag(String code) {
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

/// The fiat unit the ⇅ swap flips a Bitcoin figure to: the one last typed
/// in ([lastFiat]), else [settingsCurrency] when the unit sheet offers it,
/// else USD.
String sendFiatFlipUnit({String? lastFiat, required String settingsCurrency}) {
  if (lastFiat != null && kSendFiatUnits.contains(lastFiat)) return lastFiat;
  final code = settingsCurrency.toUpperCase();
  return kSendFiatUnits.contains(code) ? code : 'USD';
}

/// The keypad's raw text as the Bitcoin figure's digits: digits only, no
/// leading zero (a lone 0 is no amount), the last [kSendAtmMaxDigits].
String sendAtmDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  digits = digits.replaceAll(RegExp(r'^0+'), '');
  if (digits.length > kSendAtmMaxDigits) {
    digits = digits.substring(digits.length - kSendAtmMaxDigits);
  }
  return digits;
}

/// [sats] as the Bitcoin figure's digits ('' for none).
String sendAtmDigitsOf(int sats) => sats <= 0 ? '' : sendAtmDigits('$sats');

/// The Bitcoin figure as shown: the bare integer in sats ("550"), the
/// spaced 8-decimal form in BTC ("0.00 000 550") so the keystrokes flow
/// in from the right.
String sendFormatAtmAmount(String digits, String unit) {
  final sats = digits.isEmpty ? 0 : int.tryParse(digits) ?? 0;
  if (unit == 'Sats') return sats.toString();
  return sats.toFormattedString('BTC');
}

/// [formatted] split where the typed digits start ([userDigitCount] digit
/// characters from the right): the zero padding before, drawn tertiary,
/// and the typed digits after.
(String leading, String trailing) sendSplitAtmDisplay(
    String formatted, int userDigitCount) {
  if (userDigitCount <= 0) return (formatted, '');
  var counted = 0;
  var splitIdx = 0;
  for (var i = formatted.length - 1; i >= 0; i--) {
    final ch = formatted.codeUnitAt(i);
    if (ch >= 0x30 && ch <= 0x39) {
      counted++;
      if (counted >= userDigitCount) {
        splitIdx = i;
        break;
      }
    }
  }
  return (formatted.substring(0, splitIdx), formatted.substring(splitIdx));
}

/// The Bitcoin figure, ATM style: the ₿ prefix and [digits] in [unit]
/// ('Sats' or 'BTC'), the BTC zero padding in tertiary and the typed
/// digits in primary (red when [overBalance]). No TextField: the digits
/// come from the app's keypad.
class SendBitcoinAmountHero extends StatelessWidget {
  const SendBitcoinAmountHero({
    super.key,
    required this.digits,
    required this.unit,
    this.overBalance = false,
  });

  final String digits;
  final String unit;
  final bool overBalance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isSatsUnit = unit == 'Sats';
    final hasDigits = digits.isNotEmpty;
    final typedColor = overBalance ? AppColors.marketDown : c.textPrimary;
    final formatted = sendFormatAtmAmount(digits, unit);
    // In sats there is no padding: what was typed is the whole figure.
    final (leading, trailing) = isSatsUnit || !hasDigits
        ? (hasDigits ? '' : formatted, hasDigits ? formatted : '')
        : sendSplitAtmDisplay(formatted, digits.length);
    final amountTextStyle = TextStyle(
      fontSize: 56.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(sendCurrencyPrefix(unit),
            style: amountTextStyle.copyWith(
                color: hasDigits ? typedColor : c.textTertiary)),
        SizedBox(width: 6.w),
        Text.rich(
          TextSpan(
            children: [
              if (leading.isNotEmpty)
                TextSpan(
                  text: leading,
                  style: amountTextStyle.copyWith(color: c.textTertiary),
                ),
              if (trailing.isNotEmpty)
                TextSpan(
                  text: trailing,
                  style: amountTextStyle.copyWith(color: typedColor),
                ),
            ],
          ),
          maxLines: 1,
        ),
      ],
    );
  }
}

/// "$105.40" under a Bitcoin figure, "₿45,120" under a fiat one, and the
/// ⇅ swap that flips the entry unit ([onSwap]). No approximation mark: it
/// reads as a second price tag, not a hedge.
class SendAmountConversionLine extends StatelessWidget {
  const SendAmountConversionLine({
    super.key,
    required this.secondary,
    required this.onSwap,
  });

  final String secondary;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      key: const ValueKey('send-amount-conversion'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          secondary,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(width: 4.w),
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            key: const ValueKey('send-amount-swap'),
            customBorder: const CircleBorder(),
            onTap: onSwap,
            child: Padding(
              padding: EdgeInsets.all(6.w),
              child: Icon(Icons.swap_vert_rounded,
                  size: 20.sp, color: c.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

/// The balance the amount is judged against, under the figure ("328,686
/// sats available · $248.82", "$12.00 available").
class SendAmountAvailableLine extends StatelessWidget {
  const SendAmountAvailableLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        key: const ValueKey('send-amount-available'),
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: 14.sp,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

/// What is wrong with the amount, in red, under the figure ("That is more
/// than you have available.").
class SendAmountWarningLine extends StatelessWidget {
  const SendAmountWarningLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        key: const ValueKey('send-amount-warning'),
        style: TextStyle(
          color: AppColors.marketDown,
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      );
}

/// Recipient field of the Send to step. One tall surface card (56pt
/// minimum, hairline border, 14 radius) that holds the address or
/// invoice and the two ways to fill it: an inline Paste button and an
/// inline Scan button that live inside the field while it is empty.
/// Once text is in they give way to a validation tick plus a clear
/// button. No leading icon: the address itself is the focus and the
/// network is communicated by the badge below.
class SendRecipientField extends StatelessWidget {
  final TextEditingController controller;
  final AppColorsExtension colors;
  final ValueChanged<String> onChanged;

  /// Inline Paste: reads the clipboard and runs the flow's commit path.
  final VoidCallback onPaste;

  /// Inline Scan: opens the scanner sheet in recipient mode.
  final VoidCallback onScan;

  /// Whether the current text is a recipient the flow recognises. Drives
  /// the green border and the tick.
  final bool isValid;

  /// Placeholder shown when the field is empty.
  final String? hintText;

  const SendRecipientField({
    super.key,
    required this.controller,
    required this.colors,
    required this.onChanged,
    required this.onPaste,
    required this.onScan,
    required this.isValid,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final addr = controller.text;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedContainer(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      constraints: BoxConstraints(minHeight: 56.h),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 6.w, 4.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isValid
              ? c.success
              : addr.isNotEmpty
                  ? c.border
                  : c.borderSubtle,
          width: isValid ? 1.0 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              cursorColor: c.accent,
              cursorWidth: 2.0,
              maxLines: 2,
              minLines: 1,
              // An address or invoice, never prose: a plain text
              // keyboard with nothing that rewrites what is pasted or
              // typed (autocorrect, suggestions, capitals, smart
              // punctuation would all corrupt a recipient).
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              // Room under the field when the keyboard scrolls it into
              // view, so the badge under it shows too.
              scrollPadding: EdgeInsets.only(bottom: 120.h),
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText ??
                    context.l10n.sendBitcoinLightningOrSparkAddressHint,
                hintMaxLines: 2,
                hintStyle: TextStyle(
                    color: c.textSecondary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                isDense: true,
              ),
            ),
          ),
          SizedBox(width: 4.w),
          // Trailing controls share one slot so the field never jumps:
          // Paste + Scan while empty, tick + clear once there is text.
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: addr.isEmpty
                ? Row(
                    key: const ValueKey('empty'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SendFieldIconButton(
                        icon: Icons.content_paste_rounded,
                        tooltip: context.l10n.paste,
                        colors: c,
                        onTap: onPaste,
                      ),
                      SendFieldIconButton(
                        icon: Icons.qr_code_scanner_rounded,
                        tooltip: context.l10n.scan,
                        colors: c,
                        onTap: onScan,
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('filled'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isValid)
                        Container(
                          margin: EdgeInsets.only(right: 4.w),
                          width: 24.sp,
                          height: 24.sp,
                          decoration: BoxDecoration(
                            color: c.success,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_rounded,
                              color: Colors.white, size: 16.sp),
                        ),
                      SendFieldIconButton(
                        icon: Icons.cancel_rounded,
                        tooltip: context.l10n.close,
                        colors: c,
                        onTap: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 44pt icon button that sits inside the recipient field.
class SendFieldIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final AppColorsExtension colors;
  final VoidCallback onTap;

  const SendFieldIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 44.sp, minHeight: 44.sp),
      icon: Icon(icon, color: colors.textSecondary, size: 22.sp),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

/// Subtle pill that appears below the address field once the flow has
/// identified what was pasted: a filled check, the kind's icon and its
/// plain-words label. Animates in so the moment of recognition reads as
/// deliberate.
class SendDetectedBadge extends StatelessWidget {
  const SendDetectedBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.identity,
  });

  final String label;
  final IconData icon;

  /// The check disc's fill.
  final Color color;

  /// What the badge animates on. Defaults to [label].
  final String? identity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Container(
          key: ValueKey('detected-${identity ?? label}'),
          padding: EdgeInsets.fromLTRB(8.w, 6.h, 12.w, 6.h),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18.sp,
                height: 18.sp,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 12.sp,
                ),
              ),
              SizedBox(width: 8.w),
              Icon(icon, color: c.textSecondary, size: 14.sp),
              SizedBox(width: 6.w),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of red copy under the recipient field: the reason the
/// entered recipient cannot be used. Continue stays dead beside it.
class SendRecipientError extends StatelessWidget {
  const SendRecipientError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.error,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

/// Neutral list row used under the recipient field on the Send to
/// step (recent recipients, the destination card). Leading 40pt
/// artwork, title with optional subtitle, optional trailing amount and
/// date, chevron. Rows stack inside [SendToListCard] with hairline
/// dividers.
class SendToListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailingTitle;
  final String? trailingSubtitle;

  /// An explicit action at the row's end (a compact button), drawn in
  /// place of the chevron.
  final Widget? trailing;
  final AppColorsExtension colors;
  final VoidCallback onTap;

  const SendToListRow({
    super.key,
    required this.leading,
    required this.title,
    required this.colors,
    required this.onTap,
    this.subtitle,
    this.trailingTitle,
    this.trailingSubtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // The trailing column may never squeeze the recipient out on a
    // narrow screen or at a large text scale: cap it and ellipsize.
    final trailingMax = MediaQuery.sizeOf(context).width * 0.34;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            // Bare artwork, no tile or border behind it (user decision).
            SizedBox(
              width: 40.sp,
              height: 40.sp,
              child: Center(child: leading),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingTitle != null || trailingSubtitle != null) ...[
              SizedBox(width: 10.w),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: trailingMax),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingTitle != null)
                      Text(
                        trailingTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (trailingSubtitle != null) ...[
                      if (trailingTitle != null) SizedBox(height: 2.h),
                      Text(
                        trailingSubtitle!,
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
                  ],
                ),
              ),
            ],
            if (trailing != null) ...[
              SizedBox(width: 10.w),
              trailing!,
            ] else ...[
              SizedBox(width: 6.w),
              Icon(Icons.chevron_right_rounded,
                  size: 20.sp, color: c.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Surface card that stacks [SendToListRow]s with hairline dividers
/// indented past the leading tile.
class SendToListCard extends StatelessWidget {
  final List<Widget> rows;
  final AppColorsExtension colors;

  /// Draws the border in the stronger border colour. Used while the
  /// entered address still needs a network pick, where the card is the
  /// only forward path.
  final bool emphasized;

  const SendToListCard({
    super.key,
    required this.rows,
    required this.colors,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: emphasized ? c.border : c.borderSubtle,
          width: emphasized ? 1.0 : 0.5,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: c.borderSubtle,
                indent: 68.w,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Section label above a list card on the Send to step.
class SendToSectionHeader extends StatelessWidget {
  const SendToSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
      child: Text(
        title,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Quiet one-line card under the recipient field while the clipboard
/// holds something payable: Use fills the field, the cross dismisses.
class SendClipboardNudge extends StatelessWidget {
  const SendClipboardNudge({
    super.key,
    required this.onUse,
    required this.onDismiss,
  });

  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 4.h, 4.w, 4.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.content_paste_rounded,
              size: 18.sp, color: c.textSecondary),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              context.l10n.sendClipboardAddressFound,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ),
          SizedBox(width: 6.w),
          InkWell(
            onTap: onUse,
            borderRadius: BorderRadius.circular(8.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
              child: Text(
                context.l10n.useIt,
                style: TextStyle(
                  color: c.accent,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
          SendFieldIconButton(
            icon: Icons.close_rounded,
            tooltip: context.l10n.close,
            colors: c,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// The card the Review's fee rows sit on: the app's one soft card
/// (kute_action_cards.dart; founder, 7 November 2026: the grey bordered
/// boxes are the old style), the From and To squares' own surface.
class SendReviewCard extends StatelessWidget {
  const SendReviewCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: PremiumGroupContainer.decorationOf(context),
      child: child,
    );
  }
}

/// A label and its value on the Review fee card. [muted] renders the
/// quiet grey fee language — fees and ETAs are context, not the headline
/// numbers of the review card.
class SendReviewKVRow extends StatelessWidget {
  const SendReviewKVRow({
    super.key,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Text(label,
            style: TextStyle(
              color: muted ? c.textTertiary : c.textSecondary,
              fontSize: muted ? 13.sp : 15.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            )),
        SizedBox(width: 12.w),
        // The value is usually a short figure, but some callers pass a
        // whole sentence here when the fee cannot be worked out, so it
        // wraps and stays inside the row.
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: muted ? c.textTertiary : c.textPrimary,
                fontSize: muted ? 13.sp : 16.sp,
                fontWeight: muted ? FontWeight.w600 : FontWeight.w800,
                letterSpacing: -0.2,
                height: 1.35,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      ],
    );
  }
}

/// A Review fee-card row whose value is the reason it cannot be shown,
/// in red.
class SendReviewErrorRow extends StatelessWidget {
  const SendReviewErrorRow(
      {super.key, required this.label, required this.error});

  final String label;
  final String error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            )),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            error,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.error,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// The small info line under the Review fee rows.
class SendReviewNote extends StatelessWidget {
  const SendReviewNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14.sp, color: c.textTertiary),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// The whole destination under the Review's From and To squares, once the
/// To square is tapped: wrapped so every character is readable, with a
/// Copy action, on the same soft card.
class SendReviewFullAddress extends StatelessWidget {
  const SendReviewFullAddress({
    super.key,
    required this.address,
    this.onCopied,
  });

  final String address;

  /// Called after the address is on the clipboard (analytics; never the
  /// address itself).
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('send-review-full-address'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 10.w, 8.h),
      decoration: PremiumGroupContainer.decorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(right: 6.w),
            child: Text(
              address,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                height: 1.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(height: 4.h),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: address));
                onCopied?.call();
                if (!context.mounted) return;
                showMessageSnackBarInfo(
                    context: context, message: context.l10n.copied);
              },
              borderRadius: BorderRadius.circular(8.r),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 14.sp, color: c.textPrimary),
                    SizedBox(width: 4.w),
                    Text(
                      context.l10n.copy,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Review step's one primary action and the footnote over it.
///
/// THE BAR IS THE BUTTON (founder, 31 October 2026; kute_bar_context
/// .dart): Send / Continue is the floating Sal bar's primary action, with
/// the label, the enabled state and the spinner the drawn button had;
/// the footnote stays on the page, above the bar's clearance.
class SendReviewAction extends StatelessWidget {
  const SendReviewAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.footnote,
    this.loading = false,
    this.source = 'send_review',
    this.disabledLabel,
  });

  final String label;
  final VoidCallback? onPressed;

  /// What the bar says while [onPressed] is null (KuteBarContext
  /// .disabledLabel).
  final String? disabledLabel;
  final String footnote;
  final bool loading;

  /// The `search_opened` source of the bar's long press.
  final String source;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KuteBarContextScope(
          barContext: KuteBarContext.primary(
            label: label,
            onPrimary: onPressed,
            enabled: onPressed != null && !loading,
            busy: loading,
            source: source,
            disabledLabel: disabledLabel,
          ),
          child: const SizedBox.shrink(),
        ),
        Center(
          child: Text(
            footnote,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Clear of the bar (the frame's own bottom padding is under this).
        SizedBox(height: kuteBarScrollClearance.h - 16.h),
      ],
    );
  }
}

/// The phase a [SendRubberBand] reads from the screen's own flags.
enum _SendBandPhase { idle, preparing, approving, finishing }

/// The rubber band the Review step's [SendReviewAction] wears from the
/// Send tap until the send is out or has stopped ([RubberBandProgress]).
///
/// It reads the flags the send screens already keep, nothing else:
///   * [busy] up (the tap's readiness wait, the quote, the SDK prepare):
///     the band takes the first pull at once
///     ([RubberBandProgress.firstPull]) and eases on toward
///     [preparingProgress] over [expected];
///   * [authorising] up (the face scan or PIN): it holds at least
///     [approvalProgress];
///   * [authorising] down again while still [busy] (broadcasting and
///     waiting for the SDK's answer): it eases on from
///     [afterApprovalProgress] toward [ceiling] over [expected], so the
///     pull grows the closer the money is to leaving;
///   * [succeeded]: the spring snap and light tap, even while [busy] is
///     still up, so the screen can let it play ([RubberBand.settle])
///     before the success screen covers it; [busy] down without it (a
///     failure, a declined scan, a stop for re-review): the soft
///     release, with no tap of its own. The band cannot tell a failure
///     from the person's own stop, so the screen plays the failure tap
///     where the send really failed (`moneyFailureFeedbackAfterBand`),
///     and a declined scan stays quiet.
///
/// Presentation only: it never decides anything about the send.
/// Reduce Motion: no easing runs and the block sits still.
class SendRubberBand extends StatefulWidget {
  const SendRubberBand({
    super.key,
    required this.busy,
    required this.child,
    this.authorising = false,
    this.succeeded = false,
    this.expected = const Duration(seconds: 4),
  });

  /// The send is under way (from the tap until it is out or stopped).
  final bool busy;

  /// The approval prompt is up.
  final bool authorising;

  /// The send went out. Read only once a wait has begun.
  final bool succeeded;

  /// How long each eased stretch (before and after approval) usually
  /// takes.
  final Duration expected;

  final Widget child;

  /// Where the wait before approval eases to.
  static const double preparingProgress = 0.6;

  /// The least the band holds while the person approves.
  static const double approvalProgress = 0.62;

  /// Where the wait after approval starts from, at least.
  static const double afterApprovalProgress = 0.68;

  /// Where the waits ease to; the answer does the rest.
  static const double ceiling = 0.85;

  @override
  State<SendRubberBand> createState() => SendRubberBandState();
}

/// Public so tests can read the eased [progress] and whether the easing
/// is [easing].
class SendRubberBandState extends State<SendRubberBand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ease = AnimationController(vsync: this)
    ..addListener(_onEase);

  _SendBandPhase _phase = _SendBandPhase.idle;
  RubberBandOutcome _outcome = RubberBandOutcome.none;
  double _progress = 0;
  double _from = 0;
  double _to = 0;

  /// The progress the band is given now.
  @visibleForTesting
  double get progress => _progress;

  /// The band's outcome now.
  @visibleForTesting
  RubberBandOutcome get outcome => _outcome;

  /// Whether the eased progress is ticking.
  @visibleForTesting
  bool get easing => _ease.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduce && _ease.isAnimating) {
      _ease.stop();
      _progress = _to;
    }
    _sync();
  }

  @override
  void didUpdateWidget(SendRubberBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy ||
        oldWidget.authorising != widget.authorising ||
        oldWidget.succeeded != widget.succeeded) {
      _sync();
    }
  }

  bool get _reduce => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _sync() {
    if (_phase == _SendBandPhase.idle) {
      // A finished send stays at rest; only a fresh wait engages it.
      if (!widget.busy || widget.succeeded) return;
      _outcome = RubberBandOutcome.none;
      _phase = _SendBandPhase.preparing;
      _run(RubberBandProgress.firstPull, SendRubberBand.preparingProgress);
    }
    if (widget.succeeded) {
      _finish(RubberBandOutcome.success);
      return;
    }
    if (!widget.busy) {
      _finish(RubberBandOutcome.failure);
      return;
    }
    if (widget.authorising) {
      if (_phase != _SendBandPhase.approving) {
        _phase = _SendBandPhase.approving;
        _ease.stop();
        _progress = math.max(_progress, SendRubberBand.approvalProgress);
        _to = _progress;
      }
      return;
    }
    if (_phase == _SendBandPhase.approving) {
      _phase = _SendBandPhase.finishing;
      _run(math.max(_progress, SendRubberBand.afterApprovalProgress),
          SendRubberBand.ceiling);
    }
  }

  void _run(double from, double to) {
    _from = from;
    _to = to;
    _progress = from;
    if (_reduce) {
      // Nothing moves under Reduce Motion, so nothing needs to tick.
      _ease.stop();
      return;
    }
    _ease
      ..duration = widget.expected
      ..forward(from: 0);
  }

  void _finish(RubberBandOutcome outcome) {
    _ease.stop();
    _phase = _SendBandPhase.idle;
    _outcome = outcome;
  }

  void _onEase() {
    final p = _from + (_to - _from) * Curves.easeOut.transform(_ease.value);
    // A step at a time: the band's spring smooths between them, and the
    // block is not rebuilt every frame.
    if ((p - _progress).abs() >= 0.01 || !_ease.isAnimating) {
      setState(() => _progress = p);
    }
  }

  @override
  void dispose() {
    _ease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RubberBandProgress(
        progress: _progress,
        outcome: _outcome,
        // A stop may be the person's own: the screen taps on a failure.
        failureTap: false,
        child: widget.child,
      );
}

/// Shortened destination for a one-line row: the first ten and last
/// eight characters.
String sendShortAddress(String addr) => addr.length > 22
    ? '${addr.substring(0, 10)}…${addr.substring(addr.length - 8)}'
    : addr;
