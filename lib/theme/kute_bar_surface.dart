// lib/theme/kute_bar_surface.dart
//
// THE BAR IS DARK IN LIGHT MODE, IN EVERY STATE (founder, 7 November
// 2026, of the white "Search or Manage with AI", "Pick a market group"
// and "Send to a friend" pills: "shoudn tthe button be black idk. why you
// didnt change?"). A white bar blended into the white cards behind it, so
// in light mode every neutral surface of the floating Sal bar wears the
// primary button's look: the near-black fill (the theme's textPrimary,
// #1D2024, the CTA fill) with white words and glyphs. That is the Sal pill
// (one line or two, kute_bottom_action_bar.dart), its folded circle and
// the round share button, the primary button in every state (enabled,
// busy, disabled; kute_shell_bar.dart), a trade row's neutral pill (a spot
// token's Sell; kute_bar_trade_row.dart) and the pill's travel to the Sal
// sheet's composer (search_morph.dart). A coloured button keeps its own
// colours (Yes, No, Invest, Short, Close position, a slip's own style).
//
// THE HIERARCHY ON THE ONE FILL:
//   * the action ([ink], white; contrast 16.4:1 on the fill): the primary
//     button's words, the pill's first line, every glyph;
//   * a hint's second line ([quietInk], white at 72%; about 9:1): "or ask
//     Sal to find one", "They get a link to look at it";
//   * the disabled primary's step to take ([disabledInk], white at 60%;
//     about 6.6:1, still AA): "Enter an amount", with Sal `curious`.
//
// THE EDGE AND THE SHADOW: on a white page the fill alone stands out; on
// dark content (the black Purchase square, a dark share card) a dark bar
// would sink into it, so every dark surface keeps a light hairline
// ([edge], white at 20% over the fill) and a soft drop shadow ([shadow]).
// ONE shadow in both modes at the same blur, transparent in dark: a
// spring that overshoots past 1 lerping a shadow towards none scales its
// blur negative (theme_switch_no_negative_shadow_test.dart).
//
// Dark mode keeps its own look (the white Sal pill, the white primary
// button, the surface-grey disabled pill): [dark] is false there.

import 'package:flutter/material.dart';
import 'package:kute/theme/app_theme.dart';

abstract final class KuteBarSurface {
  /// Whether the bar wears the dark look: in light mode.
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// The fill: the primary button's, the theme's textPrimary (#1D2024).
  static Color fill(BuildContext context) => context.colors.textPrimary;

  /// The words and glyphs of the action, and of the pill's first line.
  static const Color ink = Color(0xFFFFFFFF);

  /// A hint's second line: quieter than [ink], still well above AA.
  static const Color quietInk = Color(0xB8FFFFFF);

  /// The disabled primary's words: plainly off, still AA on the fill.
  static const Color disabledInk = Color(0x99FFFFFF);

  /// The hairline that keeps the dark bar apart from dark content.
  static const Color edge = Color(0x33FFFFFF);

  /// The hairline's width (the light pill's, so every width that counts
  /// it stays as it was).
  static const double edgeWidth = 1.0;

  /// The one drop shadow of every bar surface: [visible] in light mode,
  /// the same blur and offset transparent otherwise (see the file header).
  static BoxShadow shadow({required bool visible}) => BoxShadow(
        color: visible ? const Color(0x2E000000) : Colors.transparent,
        blurRadius: 12,
        offset: const Offset(0, 3),
      );

  // ── Dark mode's own look ─────────────────────────────────────────────

  /// The white pill of dark mode (the Sal pill, the Sal toast).
  static const Color whiteFill = Color(0xFFFFFFFF);

  /// Its words: the light theme's near-black ink.
  static const Color inkOnWhite = Color(0xFF1D2024);

  /// Its quieter second line.
  static const Color quietInkOnWhite = Color(0xFF6B7280);

  /// Sal's side in every Sal pill (the bar's, the toast's).
  static const double salSize = 38;
}
