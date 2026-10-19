// The portfolio cards' shared frame and figure, for Predictions and
// Investing, the spending wallet and a Ledger: the app's card surface on
// the list cards' insets, and on its right the position's value with the
// profit or loss under it. The type is the Predictions list card's (its
// 20sp figure and its 13sp caption), so a card on the Portfolio reads
// like a card on the lists.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardCaptionStyle, polyCardFigureStyle;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/theme/app_theme.dart';

/// The caption line of a portfolio card (an entry price, a clock, a date).
TextStyle portfolioCardCaptionStyle(AppColorsExtension c) =>
    polyCardCaptionStyle(c)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// The value of a position with its profit or loss under it: the big
/// right-hand figure of a portfolio card, the same on a Predictions and an
/// Investing card. [pnl] null writes no second line (a holding with no
/// cost on record); [detail] replaces it with a quiet caption ("Est.
/// value").
class PortfolioCardValue extends StatelessWidget {
  final String value;
  final String? pnl;

  /// Whether [pnl] is a gain; picks the up or the down colour.
  final bool up;
  final String? detail;

  const PortfolioCardValue({
    super.key,
    required this.value,
    this.pnl,
    this.up = true,
    this.detail,
  });

  /// "+$3.80 (+7.5%)": a signed amount, then the signed percent when
  /// there is one. The signs are the app's ("+" and the true minus).
  static String pnlText(String amount, double pnl, {double? percent}) {
    final sign = pnl >= 0 ? '+' : '−';
    final pct = percent == null || !percent.isFinite
        ? ''
        : ' ($sign${percent.abs().toStringAsFixed(1)}%)';
    return '$sign$amount$pct';
  }

  static TextStyle _captionStyle(AppColorsExtension c) =>
      polyCardCaptionStyle(c).copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// The live figures' line box (RollingNumberText's).
  static const _rolledHeight = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  /// The room the figure takes in a card's top-right corner, [maxWidth]
  /// being the card's inner width: its own size, measured as the rolling
  /// digits lay it out, capped at a little under half the card (a longer
  /// figure scales down as one block, so its height shrinks with it).
  /// Lets a card keep its names clear of the figure without squeezing
  /// them beside it.
  static Size slotFor(
    BuildContext context, {
    required String value,
    String? pnl,
    String? detail,
    required double maxWidth,
  }) {
    final c = context.colors;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    Size measure(String text, TextStyle style, {bool rolled = true}) {
      final merged = base.merge(style);
      // A rolling figure is a row of single characters.
      final parts = rolled ? text.characters.toList() : [text];
      var width = 0.0;
      var height = 0.0;
      for (final part in parts) {
        final painter = TextPainter(
          text: TextSpan(text: part, style: merged),
          textDirection: direction,
          textScaler: scaler,
          textHeightBehavior: rolled ? _rolledHeight : null,
        )..layout();
        width += painter.width;
        if (painter.height > height) height = painter.height;
        painter.dispose();
      }
      return Size(width, height);
    }

    final top = measure(value, polyCardFigureStyle(c.textPrimary));
    final under = pnl != null
        ? measure(pnl, _captionStyle(c))
        : detail != null
            ? measure(detail,
                _captionStyle(c).copyWith(fontWeight: FontWeight.w500),
                rolled: false)
            : null;
    // A hair of slack: a glyph may paint a little past its measure.
    var width = (under == null || top.width > under.width
            ? top.width
            : under.width) +
        2;
    var height = top.height + (under == null ? 0 : 2.h + under.height) + 1;
    final cap = maxWidth * 0.45;
    if (width > cap) {
      height *= cap / width;
      width = cap;
    }
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final caption = _captionStyle(c);
    // A long figure scales down as one block; it never wraps or pushes
    // the names off the card.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live figures: a new value or P&L rolls the digits that
          // changed, nothing else moves.
          RollingFigure(text: value, style: polyCardFigureStyle(c.textPrimary)),
          if (pnl != null) ...[
            SizedBox(height: 2.h),
            RollingFigure(
              text: pnl!,
              style: caption.copyWith(
                  color: up ? AppColors.marketUp : AppColors.marketDown),
            ),
          ] else if (detail != null) ...[
            SizedBox(height: 2.h),
            Text(detail!,
                maxLines: 1,
                style: caption.copyWith(fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

/// The frame every portfolio card shares: the app's card surface, the
/// list card's insets, one tap target. [action] (a Ledger's Sell / Claim)
/// sits under the content in the app's own button.
class PortfolioCardFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Widget? action;

  /// The gap under the card; a list that spaces its own rows passes zero.
  final EdgeInsetsGeometry? margin;

  const PortfolioCardFrame({
    super.key,
    required this.child,
    this.onTap,
    this.action,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    return Container(
      margin: margin ?? EdgeInsets.only(bottom: 12.h),
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                if (action != null) ...[
                  SizedBox(height: 14.h),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
