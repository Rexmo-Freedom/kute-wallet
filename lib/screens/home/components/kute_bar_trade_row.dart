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
//     Sell is the bar's neutral surface (dark in light mode, a light
//     hairline, white words; kute_bar_surface.dart). The press spring of
//     every button; a tap runs exactly what the pinned button ran;
//   * at the row's end the round Sal button ([KuteBarShareButton]): the
//     Sal pill folded to its 52 circle (KuteSalPill.collapsed), Sal and
//     the share badge, no words (founder: "just a share button on the
//     right side, in the same button style, with Sal, with no text"); read
//     aloud as "Send to a friend". A tap opens the page's Send to a friend
//     Sal sheet, the circle travelling to the composer as the pill does; on
//     an open position in profit it opens the brag card instead ("Brag
//     about it").
//
// THE SHARE BADGE (founder, 5 November 2026: "Kute symbol here should be
// with the share", then of the 3D clip with the glyph in front of Sal:
// "still not clear, kinda hides behind Sal"): share is said by a vector
// badge, apart from Sal. The circle holds his deadpan `idle` face whole,
// [kSalShareButtonSalSize] (not 38: no ear at the circle's edge), centred;
// over its bottom right, past the edge like an app badge, the share badge
// (kute_share_badge.dart): an ink disc in a white ring with the white iOS
// share glyph, whose arrow bobs up out of the tray as Sal blinks (his
// frames drive it; none under Reduce Motion, where he holds frame 0). On
// the dark circle of light mode it inverts: a white disc, the ink glyph, a
// ring of the circle's dark fill. The same button for Brag.
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
import 'package:kute/screens/shared/kute_share_badge.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteReduceMotion;
import 'package:kute/screens/shared/market_pair_button.dart'
    show marketPairDecoration;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';
import 'package:kute/theme/kute_motion.dart';

/// The air between the row's pills, and before the round Sal button.
const double kBarRowGap = 8;

/// The round share button's Sal clip (see the file header, THE SHARE
/// BADGE): his deadpan face, the badge keeping time with its blink.
const String kSalShareButtonClip = kShareBadgeBeatClip;

/// Sal's side in the round share button: his whole head inside the 52
/// circle, with room for the badge.
const double kSalShareButtonSalSize = 32;

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
    // No fill: the bar's neutral surface, dark in light mode
    // (kute_bar_surface.dart).
    final ink = fill != null
        ? contrastingOnColor(fill)
        : (isLight ? KuteBarSurface.ink : c.textPrimary);
    final reduce = kuteReduceMotion(context);
    final style =
        KuteBarPrimaryButton.labelStyle(context, weight: FontWeight.w800)
            .copyWith(color: ink);
    final value = trade.value;
    final BoxDecoration decoration = fill != null
        // The pinned pair's own slab, in the bar's pill shape.
        ? marketPairDecoration(fill,
            borderRadius: KuteBarPrimaryButton.radius, glow: isLight)
        // The bar's neutral surface (the Sal pill's and its one shadow):
        // dark in light mode, the surface grey in dark.
        : BoxDecoration(
            color: isLight ? KuteBarSurface.fill(context) : c.surface,
            borderRadius: KuteBarPrimaryButton.radius,
            border: Border.all(
                color: isLight ? KuteBarSurface.edge : c.borderSubtle,
                width: isLight ? KuteBarSurface.edgeWidth : 0.5),
            boxShadow: [KuteBarSurface.shadow(visible: isLight)],
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
/// the Sal pill folded to its circle, Sal's face ([kSalShareButtonClip])
/// and the share badge ([KuteShareBadge]), no words; read aloud as "Send
/// to a friend", or "Brag about it" where a tap opens the brag card.
/// [onTap] gets the button's own element.
class KuteBarShareButton extends StatefulWidget {
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
  State<KuteBarShareButton> createState() => _KuteBarShareButtonState();
}

class _KuteBarShareButtonState extends State<KuteBarShareButton> {
  /// The badge's arrow, up on Sal's blink (repainted, never rebuilt).
  final ValueNotifier<double> _lift = ValueNotifier<double>(0);

  @override
  void dispose() {
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final share = widget.share;
    // On the dark circle of light mode the badge inverts: a white disc, the
    // ink glyph, a ring of the circle's own fill (kute_share_badge.dart).
    final dark = KuteBarSurface.dark(context);
    return KeyedSubtree(
      key: const ValueKey('kute-bar-share'),
      child: KuteSalPill(
        label: share.brag != null ? l10n.bragAboutIt : l10n.shareHeaderLabel,
        clip: kSalShareButtonClip,
        // Sal's face whatever the AI setting: this is the share, not a
        // question to Sal.
        aiEnabled: true,
        collapsed: true,
        salCue: widget.salCue,
        salSize: kSalShareButtonSalSize,
        badge: dark
            ? KuteShareBadge(
                lift: _lift,
                ringColor: KuteBarSurface.fill(context),
                discColor: KuteBarSurface.ink,
                glyphColor: kShareBadgeInk,
              )
            : KuteShareBadge(lift: _lift),
        onSalFrame: (frame) => _lift.value = kuteShareBadgeLift(frame),
        onTap: () => widget.onTap(context),
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
