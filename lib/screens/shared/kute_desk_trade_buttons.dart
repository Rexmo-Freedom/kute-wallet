// lib/screens/shared/kute_desk_trade_buttons.dart
//
// THE DESK'S TRADE BUTTONS (founder, 25 November 2026, the market page on
// a laptop: "have a button like Long and Short ... Then clicking Long or
// Short this side bar appears"). On EXPANDED a market page's trade doors
// are not the floating trade row: they head the page's right column as
// two large buttons side by side, and sit, smaller, in the Advanced chart
// editor's header. They are the trade row's own pills
// (kute_bar_trade_row.dart, [KuteBarTrade]: its words, its fills, its
// tap) at the desk's sizes, with a pointer cursor and a hover wash for a
// mouse. Shared by Investing and Predictions; phones and MEDIUM never
// build them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart' show KuteBarTrade;
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/market_pair_button.dart'
    show marketPairDecoration;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';

/// The right column's buttons: about an option card's title block.
const double kuteDeskTradeButtonHeight = 64;

/// The editor header's buttons: its other controls' height.
const double kuteDeskTradeButtonCompactHeight = 40;

/// [trades] side by side. Large ([compact] false): the column's whole
/// width, each its flex of it. Compact: as wide as their words, for a
/// header.
class KuteDeskTradeButtons extends StatelessWidget {
  const KuteDeskTradeButtons({
    super.key,
    required this.trades,
    this.compact = false,
    this.gap = 12,
  });

  final List<KuteBarTrade> trades;
  final bool compact;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (var i = 0; i < trades.length; i++) ...[
        if (i > 0) SizedBox(width: compact ? 8 : gap),
        if (compact)
          KuteDeskTradeButton(trade: trades[i], compact: true)
        else
          Expanded(
            flex: trades[i].flex,
            child: KuteDeskTradeButton(trade: trades[i]),
          ),
      ],
    ];
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: children,
    );
  }
}

/// One of [KuteDeskTradeButtons], keyed `kute-desk-trade-{id}`.
class KuteDeskTradeButton extends StatefulWidget {
  const KuteDeskTradeButton(
      {super.key, required this.trade, this.compact = false});

  final KuteBarTrade trade;
  final bool compact;

  @override
  State<KuteDeskTradeButton> createState() => _KuteDeskTradeButtonState();
}

class _KuteDeskTradeButtonState extends State<KuteDeskTradeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trade = widget.trade;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fill = trade.fill;
    final ink = fill != null
        ? contrastingOnColor(fill)
        : (isLight ? KuteBarSurface.ink : c.textPrimary);
    final height = widget.compact
        ? kuteDeskTradeButtonCompactHeight
        : kuteDeskTradeButtonHeight;
    final radius = BorderRadius.circular(height / 2);
    final style =
        KuteBarPrimaryButton.labelStyle(context, weight: FontWeight.w800)
            .copyWith(
                color: ink,
                fontSize: widget.compact ? 14 : 17,
                letterSpacing: widget.compact ? -0.1 : -0.2);
    final decoration = fill != null
        ? marketPairDecoration(fill, borderRadius: radius, glow: isLight)
        : BoxDecoration(
            color: isLight ? KuteBarSurface.fill(context) : c.surface,
            borderRadius: radius,
            border: Border.all(
                color: isLight ? KuteBarSurface.edge : c.borderSubtle,
                width: isLight ? KuteBarSurface.edgeWidth : 0.5),
          );
    return Semantics(
      button: true,
      label: trade.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: KutePressable(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              trade.onTap();
            },
            child: AnimatedContainer(
              key: ValueKey('kute-desk-trade-${trade.id}'),
              duration: const Duration(milliseconds: 120),
              height: height,
              padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 18 : 16),
              alignment: Alignment.center,
              decoration: decoration,
              // The hover wash: the ink at a whisper over the fill.
              foregroundDecoration: BoxDecoration(
                color: ink.withValues(alpha: _hover ? 0.08 : 0),
                borderRadius: radius,
              ),
              child: Text(
                trade.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
