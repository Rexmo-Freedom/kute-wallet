// lib/screens/shared/components/receipt_parts.dart
//
// THE RECEIPT, ONE STRUCTURE (founder, 1 November 2026: "all these cards
// should be redesigned with more space, like the squares we did"). Every
// sheet opened from an Activity row reads the same way, top to bottom:
//
//  1. [ReceiptHero]: the circled close at the top-right, the row's logo
//     (56), its title ("Sold · No", "Reduced OAI", "Sent"), the amount
//     large (40, w700), the result in its colour or the fiat value under
//     it, and the date as a quiet line. Centred. No Sal circle.
//  2. [ReceiptFactTiles]: the two to six facts that matter, as big square
//     tiles two per row (the position page's "Worth now / If No wins"
//     tiles; the action cards' soft card, KuteActionCard.surfaceOf, 14
//     padding), equal widths, 10 apart.
//  3. [ReceiptLongRow]: long text (a market question, a description, an
//     address to pay) on its own full-width row, label above and the value
//     wrapping under it, never squeezed into a value column.
//  4. Whatever the receipt draws itself (the flow diagram, Nerd data).
//  5. [ReceiptBarAction]: THE ACTION IS THE BAR. "View on the blockchain",
//     "View market", "Track this exchange" are the floating bar's primary
//     button; a long press opens the Sal sheet asking "What happened
//     here?". A receipt with no action keeps the default bar. Either way
//     the content scrolls clear of the bar.
//     EVERY TRANSACTION SHARES (founder, 5 November 2026: "All these
//     transactions, next to View on the blockchain, should have the share
//     and a special share card"): with [ReceiptBarAction.share] the round
//     Sal button (the market pages' own, kute_bar_trade_row.dart) sits at
//     the primary's right and opens the receipt's card
//     (screens/share/receipt_share.dart). A receipt with no action of its
//     own but a share gets Done as its primary (it closes the receipt),
//     so the button always has a pill beside it. A failed, refunded or
//     expired transaction passes no share.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/receipt_share.dart'
    show ReceiptShare, openReceiptShare;
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';

/// The `search_opened` / bar source every receipt reports.
const String kReceiptBarSource = 'receipt';

/// The top of every receipt (see the file header). [leading] is the row's
/// own icon at 56; [title] the row's title; [amount] the figure, already
/// styled ([receiptAmountStyle]); [result] the line under it (a profit or
/// loss in [resultColor], else the fiat value); [note] one more line of
/// context (a conversion's two legs); [date] the quiet date line.
class ReceiptHero extends StatelessWidget {
  const ReceiptHero({
    super.key,
    required this.leading,
    required this.title,
    required this.amount,
    this.result,
    this.resultColor,
    this.note,
    this.date,
    this.verified,
  });

  final Widget leading;
  final Widget title;
  final Widget amount;
  final String? result;
  final Color? resultColor;
  final String? note;
  final String? date;

  /// A quiet line under the title: "Verified by Branta" on a send whose
  /// payee Branta verified (send_branta_payee.dart).
  final Widget? verified;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      key: const ValueKey('receipt-hero'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: AppDecorations.dragHandle(context),
        ),
        SizedBox(height: 8.h),
        const Row(
          children: [
            Spacer(),
            KuteCloseButton(),
          ],
        ),
        leading,
        SizedBox(height: 14.h),
        DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          child: title,
        ),
        if (verified != null) ...[
          SizedBox(height: 4.h),
          verified!,
        ],
        SizedBox(height: 6.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: KeyedSubtree(
              key: const ValueKey('receipt-hero-amount'), child: amount),
        ),
        if (result != null && result!.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Text(
            result!,
            key: const ValueKey('receipt-hero-result'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: resultColor ?? c.textTertiary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (note != null && note!.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Text(
            note!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ],
        if (date != null && date!.isNotEmpty) ...[
          SizedBox(height: 6.h),
          Text(
            date!,
            key: const ValueKey('receipt-hero-date'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
        ],
        SizedBox(height: 22.h),
      ],
    );
  }
}

/// The hero amount's style: 40, w700, tabular.
TextStyle receiptAmountStyle(AppColorsExtension c, {Color? color}) =>
    TextStyle(
      color: color ?? c.textPrimary,
      fontSize: 40.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// One fact of a receipt, drawn as a [ReceiptFactTile].
class ReceiptFact {
  const ReceiptFact({
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
    this.subColor,
    this.copyValue,
  });

  final String label;
  final String value;

  /// The quiet line under the value, if any.
  final String? sub;
  final Color? valueColor;
  final Color? subColor;

  /// Set: a tap copies it (with the app's toast and a haptic).
  final String? copyValue;
}

/// One fact on its own square tile: the label (12, textSecondary) on top,
/// the value (17, w600) under it, an optional sub line (12) under that.
class ReceiptFactTile extends StatelessWidget {
  const ReceiptFactTile({super.key, required this.fact});

  final ReceiptFact fact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final copy = fact.copyValue;
    final tile = Container(
      key: ValueKey('receipt-tile-${fact.label}'),
      padding: EdgeInsets.all(14.w),
      // The app's one soft card, the action cards' own
      // (KuteActionCard.surfaceOf).
      decoration: KuteActionCard.surfaceOf(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fact.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    fact.value,
                    maxLines: 1,
                    style: TextStyle(
                      color: fact.valueColor ?? c.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (copy != null) ...[
                SizedBox(width: 6.w),
                Icon(Icons.copy_rounded, color: c.accent, size: 12.sp),
              ],
            ],
          ),
          if (fact.sub != null && fact.sub!.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              fact.sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fact.subColor ?? c.textTertiary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                height: 1.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
    if (copy == null) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => receiptCopy(context, copy),
      child: tile,
    );
  }
}

/// The receipt's facts as tiles, two per row, equal widths, 10 apart, each
/// row as tall as its taller tile. An odd last fact keeps its half width.
/// Nothing at all with no facts.
class ReceiptFactTiles extends StatelessWidget {
  const ReceiptFactTiles({super.key, required this.facts});

  final List<ReceiptFact> facts;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();
    final gap = 10.w;
    final rows = <Widget>[];
    for (var i = 0; i < facts.length; i += 2) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      final right = i + 1 < facts.length ? facts[i + 1] : null;
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ReceiptFactTile(fact: facts[i])),
            SizedBox(width: gap),
            Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : ReceiptFactTile(fact: right)),
          ],
        ),
      ));
    }
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        key: const ValueKey('receipt-tiles'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// Long text on its own full-width row: the label above (13,
/// textSecondary), the value under it (15, w600), wrapping. [copiable]
/// copies the full value on tap; [onTap] with [trailingIcon] makes the row
/// an affordance of its own (the label row's edit glyph).
class ReceiptLongRow extends StatelessWidget {
  const ReceiptLongRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.copiable = false,
    this.onTap,
    this.trailingIcon,
    this.onCopied,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool copiable;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  /// Runs after a copy; callers hook tracking here.
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = trailingIcon ?? (copiable ? Icons.copy_rounded : null);
    final tap = onTap ??
        (copiable
            ? () {
                receiptCopy(context, value);
                onCopied?.call();
              }
            : null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tap,
      child: Padding(
        key: ValueKey('receipt-long-$label'),
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
            SizedBox(height: 4.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: valueColor ?? c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      height: 1.35,
                    ),
                  ),
                ),
                if (icon != null) ...[
                  SizedBox(width: 8.w),
                  Padding(
                    padding: EdgeInsets.only(top: 3.h),
                    child: Icon(icon, color: c.accent, size: 14.sp),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Copies [value] with the app's toast and a haptic.
void receiptCopy(BuildContext context, String value) {
  HapticFeedback.selectionClick();
  Clipboard.setData(ClipboardData(text: value));
  showMessageSnackBarInfo(
      context: context, message: context.l10n.copiedToClipboard);
}

/// The receipt's action as the floating bar's primary button, and the
/// room the content keeps under it (see the file header). [label] and
/// [onPrimary] are the button the sheet used to pin at its foot; [busy]
/// while it runs. A long press on the bar opens the Sal sheet asking
/// "What happened here?" (the receipt's own question context, held in
/// the same route beside the primary). [share]: the round Sal button at
/// the primary's right, opening the receipt's card. With no [label] the
/// bar is the default one and only the scroll clearance is drawn, unless
/// there is a [share]: then Done (closing the receipt) is the primary.
class ReceiptBarAction extends StatelessWidget {
  const ReceiptBarAction({
    super.key,
    required this.label,
    required this.onPrimary,
    this.busy = false,
    this.share,
  });

  /// No action: the default bar, and the room under the content; with a
  /// [share], Done and the round share button.
  const ReceiptBarAction.none({super.key, this.share})
      : label = null,
        onPrimary = null,
        busy = false;

  final String? label;
  final VoidCallback? onPrimary;
  final bool busy;

  /// What the round Sal button shares; null: no button.
  final ReceiptShare? share;

  @override
  Widget build(BuildContext context) {
    final clearance = SizedBox(
        key: const ValueKey('receipt-bar-clearance'),
        height: kuteBarScrollClearance.h);
    final share = this.share;
    final label =
        this.label ?? (share == null ? null : context.l10n.done);
    if (label == null) return clearance;
    final question = context.l10n.receiptAskWhatHappened;
    final ask = KuteBarContext(
      label: question,
      question: question,
      source: kReceiptBarSource,
    );
    return KuteBarContextScope(
      barContext: ask,
      child: KuteBarContextScope(
        barContext: KuteBarContext.primary(
          label: label,
          // Done closes the receipt the bar stands for.
          onPrimary: this.label != null
              ? onPrimary
              : () => Navigator.of(context).maybePop(),
          busy: busy,
          disabledLabel: null,
          clip: 'idle',
          source: kReceiptBarSource,
          share: share == null
              ? null
              : KuteBarShare(
                  barContext: ask,
                  open: () => openReceiptShare(context, share),
                ),
        ),
        child: clearance,
      ),
    );
  }
}
