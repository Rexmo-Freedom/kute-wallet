// lib/screens/home/components/kute_bar_trade_row.dart
//
// THE TRADE ROW (founder, 4 November 2026; kute_bar_context.dart, THE
// TRADE ROW): on a market page the shell bar (kute_shell_bar.dart) is the
// page's trade buttons, one floating row at the foot of the screen:
//
//   * the trade pills ([KuteBarTradePill]): Invest | Short on Investing,
//     Yes | No on one prediction, each the bar's primary shape (52 tall,
//     fully rounded) in the market's solid colour with its contrast ink
//     (white on the up and down colours) and the live figure after the
//     words ("Yes 62%"); the pinned pair's own fill, its top highlight and,
//     in light mode, its quiet glow (marketPairDecoration). A spot token's
//     Sell is the light pill (white, a hairline). The press spring of every
//     button; a tap runs exactly what the pinned button ran;
//   * at the row's end the round Sal button ([KuteBarShareButton]): the
//     Sal pill folded to its 52 circle (KuteSalPill.collapsed), Sal with
//     the share glyph and no words (founder: "just a share button on the
//     right side, in the same button style, with Sal, with no text"); read
//     aloud as "Send to a friend". A tap opens the page's Send to a friend
//     Sal sheet, the circle travelling to the composer as the pill does; on
//     an open position in profit it opens the brag card instead ("Brag
//     about it").
//
// THE SHARE CLIP (founder, 5 November 2026: "Kute symbol here should be
// with the share"): the round button wears [kSalShareButtonClip],
// `face_share`, a Blender clip of its own (the v5 rig, the face clips'
// camera and lights): Sal's head, deadpan, behind a 3D share glyph in
// Kute's ink (the iOS tray with the up arrow, bevelled), the arrow
// rising gently out of the tray twice a loop, a side-eye down at it and
// a dry blink; 48 frames at 24 fps, seamless. Its frame 0 (level stare,
// arrow at rest) is the Reduce Motion still. The same clip for Brag.
// Until the sheet loads, Sal's `share` face stands in.
//
// An open position's Close position or Sell keeps its own red primary
// button and takes the same round button at its right ([KuteBarShareSlot]:
// in and out with the context, the width on the chip spring).
//
// The pills sit in the bar's own box (no translate), so every tap lands
// where the pill is drawn; the gaps between them let taps through to the
// page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_morph_label.dart' show KuteMorphSize;
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteReduceMotion;
import 'package:kute/screens/shared/market_pair_button.dart'
    show marketPairDecoration;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The air between the row's pills, and before the round Sal button.
const double kBarRowGap = 8;

/// The round share button's Sal clip (see the file header, THE SHARE
/// CLIP): Sal presenting the share glyph.
const String kSalShareButtonClip = 'face_share';

/// The trade row: [barContext]'s trades side by side, each its flex of
/// the width the round Sal button leaves, and the button at the end.
/// [onShare] runs the button's tap with its own element (where the travel
/// to the composer starts); [salCue] is the bar's market intro.
class KuteBarTradeRow extends StatelessWidget {
  const KuteBarTradeRow({
    super.key,
    required this.barContext,
    required this.onShare,
    this.salCue = 0,
  });

  final KuteBarContext barContext;
  final void Function(BuildContext shareContext) onShare;
  final int salCue;

  @override
  Widget build(BuildContext context) {
    final trades = barContext.trades;
    final share = barContext.share;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < trades.length; i++) ...[
          if (i > 0) const SizedBox(width: kBarRowGap),
          Expanded(
            flex: trades[i].flex,
            child: KuteBarTradePill(trade: trades[i]),
          ),
        ],
        if (share != null) ...[
          if (trades.isNotEmpty) const SizedBox(width: kBarRowGap),
          KuteBarShareButton(share: share, onTap: onShare, salCue: salCue),
        ],
      ],
    );
  }
}

/// One trade pill of the row (see the file header), keyed
/// `kute-bar-trade-{id}`.
class KuteBarTradePill extends StatelessWidget {
  const KuteBarTradePill({super.key, required this.trade});

  final KuteBarTrade trade;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fill = trade.fill;
    final ink = fill != null ? contrastingOnColor(fill) : c.textPrimary;
    final reduce = kuteReduceMotion(context);
    final style =
        KuteBarPrimaryButton.labelStyle(context, weight: FontWeight.w800)
            .copyWith(color: ink);
    final value = trade.value;
    final BoxDecoration decoration = fill != null
        // The pinned pair's own slab, in the bar's pill shape.
        ? marketPairDecoration(fill,
            borderRadius: KuteBarPrimaryButton.radius, glow: isLight)
        // The light pill (the Sal pill's surface and its one shadow).
        : BoxDecoration(
            color: isLight ? Colors.white : c.surface,
            borderRadius: KuteBarPrimaryButton.radius,
            border: Border.all(
                color: isLight ? c.border : c.borderSubtle,
                width: isLight ? 1.0 : 0.5),
            boxShadow: [
              BoxShadow(
                color: isLight
                    ? Colors.black.withValues(alpha: 0.05)
                    : Colors.transparent,
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          );
    return Semantics(
      button: true,
      label: value == null ? trade.label : '${trade.label}, $value',
      excludeSemantics: true,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            trade.onTap();
          },
          child: Container(
            key: ValueKey('kute-bar-trade-${trade.id}'),
            height: KuteBarPrimaryButton.height,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            alignment: Alignment.center,
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    trade.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                if (value != null) ...[
                  SizedBox(width: 6.w),
                  // The live figure rolls, as it did on the pinned pair.
                  RollingNumberText(
                    key: ValueKey('kute-bar-trade-${trade.id}-value'),
                    text: value,
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    style: style.copyWith(
                      color: ink.withValues(alpha: 0.85),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round Sal button (see the file header), keyed `kute-bar-share`:
/// the Sal pill folded to its circle, Sal with the share glyph
/// ([kSalShareButtonClip]), no words; read aloud as "Send to a friend",
/// or "Brag about it" where a tap opens the brag card. [onTap] gets the
/// button's own element.
class KuteBarShareButton extends StatelessWidget {
  const KuteBarShareButton({
    super.key,
    required this.share,
    required this.onTap,
    this.salCue = 0,
  });

  final KuteBarShare share;
  final void Function(BuildContext shareContext) onTap;
  final int salCue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KeyedSubtree(
      key: const ValueKey('kute-bar-share'),
      child: KuteSalPill(
        label: share.brag != null ? l10n.bragAboutIt : l10n.shareHeaderLabel,
        clip: kSalShareButtonClip,
        // Sal's face whatever the AI setting: this is the share, not a
        // question to Sal.
        aiEnabled: true,
        collapsed: true,
        salCue: salCue,
        onTap: () => onTap(context),
      ),
    );
  }
}

/// The round Sal button beside a primary button (a position's Close
/// position or Sell): there while [share] is, in and out with the
/// context, the width on the chip spring and the button fading and
/// growing in on the settle. At once under Reduce Motion.
class KuteBarShareSlot extends StatelessWidget {
  const KuteBarShareSlot({
    super.key,
    required this.share,
    required this.onTap,
    this.salCue = 0,
  });

  final KuteBarShare? share;
  final void Function(BuildContext shareContext) onTap;
  final int salCue;

  @override
  Widget build(BuildContext context) {
    final reduce = kuteReduceMotion(context);
    final share = this.share;
    return KuteMorphSize(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : KuteMotion.settleDuration,
        switchInCurve: KuteMotion.settle,
        switchOutCurve: KuteMotion.settle,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: share == null
            ? const SizedBox.shrink(key: ValueKey('kute-bar-share-none'))
            : Padding(
                key: const ValueKey('kute-bar-share-slot'),
                padding: const EdgeInsets.only(left: kBarRowGap),
                child: KuteBarShareButton(
                    share: share, onTap: onTap, salCue: salCue),
              ),
      ),
    );
  }
}
