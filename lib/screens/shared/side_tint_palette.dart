import 'package:flutter/material.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';

/// Re-expresses the whole palette as contrast ink on [side], so a sheet
/// can paint itself in a money direction's own colour and every child
/// that reads `context.colors` follows without being forked. Handed to
/// the subtree as a theme extension.
///
/// The steps are spaced wider than the neutral theme's on purpose. A flat
/// 14% ink is legible on grey but silts up on saturated green or red, so
/// there are three separated tiers: [AppColorsExtension.surface] for
/// inert panes, `surfaceLight` for anything tappable and
/// `surfaceElevated` for the selected or pressed state.
AppColorsExtension sideTintPalette(AppColorsExtension base, Color side) {
  final on = contrastingOnColor(side);
  // The quieter text steps: white keeps the steps it always had; dark ink
  // on a light fill (an outcome's soft line colour) loses contrast faster
  // as it thins, so its steps sit higher and still read at 4.5:1 on any
  // fill dark ink is picked for.
  final dark = on != Colors.white;
  // Panes, borders and the drag handle are one family ([tintPane]): in
  // white ink the steps they always had, in dark ink each matched to the
  // contrast its white step has on the Yes slip's green, so a light sheet's
  // outlines are as quiet as a green sheet's (founder, 12 November 2026,
  // on the Draw slip: "they look like they have bigger borders").
  return base.copyWith(
    background: side,
    surface: tintPane(on, side, 0.16),
    surfaceLight: tintPane(on, side, 0.24),
    surfaceElevated: tintPane(on, side, 0.32),
    textPrimary: on,
    textSecondary: on.withValues(alpha: dark ? 0.86 : 0.78),
    textTertiary: on.withValues(alpha: dark ? 0.76 : 0.64),
    textDisabled: on.withValues(alpha: dark ? 0.46 : 0.38),
    border: tintPane(on, side, 0.34),
    borderSubtle: tintPane(on, side, 0.22),
    borderFocused: on,
    dragHandle: tintPane(on, side, 0.45),
    accent: on,
    // Status inks go to full-strength contrast: an error line on a red
    // sheet has to stay readable, and the icon beside it carries the
    // meaning the colour used to.
    error: on,
    success: on,
    warning: on,
    info: on,
    cardShadow: Colors.transparent,
  ) as AppColorsExtension;
}

/// The white-ink sheet every dark-ink step is matched to: the Yes slip's
/// green.
const Color kTintParitySheet = AppColors.marketUp;

/// The WCAG contrast of [step] painted over the opaque [sheet], against
/// [sheet]: how far a pane or a border stands off the sheet it is on.
double tintStepContrast(Color step, Color sheet) {
  final a = Color.alphaBlend(step, sheet).computeLuminance();
  final b = sheet.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

final Map<(int, int, double), double> _stepAlphas = {};

/// The strength of a tinted sheet's step in ink [on] over [side]: in white
/// ink [alpha] itself, the step the green and red sheets have always had;
/// in dark ink the strength at which it stands off [side] exactly as far
/// (WCAG contrast, [tintStepContrast]) as white at [alpha] stands off the
/// Yes slip's green ([kTintParitySheet]). Black weighs far more over a
/// soft fill than white over a saturated one: the same alpha in black was
/// a pane of mud and a border two and a half times as heavy.
double tintStepAlpha(Color on, Color side, double alpha) {
  if (on == Colors.white || alpha <= 0) return alpha;
  return _stepAlphas.putIfAbsent((on.toARGB32(), side.toARGB32(), alpha), () {
    final target = tintStepContrast(
        Colors.white.withValues(alpha: alpha), kTintParitySheet);
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (tintStepContrast(on.withValues(alpha: mid), side) < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  });
}

/// A step of a tinted sheet's ink [on] over [side] (a tappable surface, a
/// selected side, a key, a border, the close circle): [alpha] is its
/// strength in white ink, and dark ink takes [tintStepAlpha] of it, so a
/// light sheet's panes and outlines separate exactly as quietly as the
/// green sheet's and the words on them keep reading.
Color tintPane(Color on, Color side, double alpha) =>
    on.withValues(alpha: tintStepAlpha(on, side, alpha));

/// A border of ink [on] at white strength [alpha] drawn over a pane of
/// the same ink at white strength [over] (a side button's outline over its
/// own pane): in white ink [alpha] itself; in dark ink the strength at
/// which the outline and the pane under it together stand off [side] as
/// far as the white pair stands off the Yes slip's green. Matching the
/// two steps one by one would stack two darks into a heavier rim.
Color tintEdge(Color on, Color side, double alpha, {required double over}) {
  if (on == Colors.white) return on.withValues(alpha: alpha);
  final whole = tintStepAlpha(on, side, 1 - (1 - alpha) * (1 - over));
  final pane = tintStepAlpha(on, side, over);
  return on.withValues(
      alpha: ((whole - pane) / (1 - pane)).clamp(0.0, 1.0).toDouble());
}

/// The fill of a slip's one primary button on a sheet lettered in [on]:
/// the ink itself. On a dark fill that is the white button the green and
/// red slips have always had; on a light fill (an outcome's soft line
/// colour) a white button would not stand off the sheet, so it is the
/// app's own near-black button ([KuteBarSurface.inkOnWhite], the bar's
/// fill in light mode), lettered by [slipCtaLabelColor].
Color slipCtaFill(Color on) =>
    on == Colors.white ? on : KuteBarSurface.inkOnWhite;

/// The label colour of a slip's one primary button whose fill is [fill].
/// A trade (Yes/No, Long/Short) sitting on the sheet's ink is lettered in
/// its side colour [side]; anything neutral (the "Add $X to Investments"
/// door, a wait, a retry) contrasts with its fill, the way `AppButton`'s
/// own label does. The bet slip and the order slip both read this, so
/// their buttons letter alike in light and dark.
Color slipCtaLabelColor(
        {required Color fill, required Color side, required bool neutral}) =>
    neutral ? contrastingOnColor(fill) : side;

/// Money in is green, money out is red: the sheet wears the direction of
/// the move the user is about to make.
Color sideTintForMoneyIn(bool moneyIn) =>
    moneyIn ? AppColors.marketUp : AppColors.marketDown;

/// For a small control that must stay crisp on a tinted sheet (the Ask
/// Sal chip): a SOLID contrast-ink pill with the side colour as its own
/// ink, the same inversion the primary action uses. Translucent tiers
/// read as smudges at that size.
AppColorsExtension sideTintInvertedPalette(
    AppColorsExtension base, Color side) {
  final on = contrastingOnColor(side);
  return base.copyWith(
    surface: on,
    surfaceLight: on,
    surfaceElevated: on,
    background: on,
    textPrimary: side,
    textSecondary: side,
    textTertiary: side,
    border: on,
    borderSubtle: on,
    accent: side,
    cardShadow: Colors.transparent,
  ) as AppColorsExtension;
}

/// Wraps [child] in [sideTintInvertedPalette] so shared widgets follow it.
class SideTintInverted extends StatelessWidget {
  const SideTintInverted({super.key, required this.side, required this.child});

  final Color side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((e) => e is! AppColorsExtension),
          sideTintInvertedPalette(context.colors, side),
        ],
      ),
      child: child,
    );
  }
}

/// True when [colors] came from [sideTintPalette] or
/// [sideTintInvertedPalette], i.e. the subtree is painted in a money
/// direction rather than on the neutral surface.
///
/// Both tints collapse every status ink onto the one contrast colour, so
/// that collapse is the signal. Widgets shared between a tinted sheet and
/// a plain screen need it: a solid green fill is the clearest way to show
/// a selected Long on grey, and completely invisible on green.
bool isSideTinted(AppColorsExtension colors) =>
    colors.error == colors.textPrimary &&
    colors.success == colors.textPrimary &&
    colors.accent == colors.textPrimary;

/// Marks the subtree as sitting on a side-tinted sheet. Only widgets that
/// paint their own fill need it — everything else reads the tinted
/// [AppColorsExtension] through `context.colors`.
class SheetTint extends InheritedWidget {
  const SheetTint({
    super.key,
    required this.side,
    required this.on,
    required super.child,
  });

  /// The side colour the sheet is painted with.
  final Color side;

  /// Best-contrast ink on [side] — the same helper the CTA label uses.
  final Color on;

  /// A pane or a border of the sheet's ink at [alpha], its strength in
  /// white ink ([tintPane]).
  Color pane(double alpha) => tintPane(on, side, alpha);

  /// An outline of the sheet's ink at [alpha] over its own pane at
  /// [over], both strengths in white ink ([tintEdge]).
  Color edge(double alpha, {required double over}) =>
      tintEdge(on, side, alpha, over: over);

  static SheetTint? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetTint>();

  @override
  bool updateShouldNotify(SheetTint old) => old.side != side || old.on != on;
}

/// Paints a whole sheet subtree in [side]: publishes the [SheetTint] marker
/// and hands down [sideTintPalette], so every child that reads
/// `context.colors` follows the direction without knowing about it.
///
/// Anything opened ON TOP of a tinted subtree must not inherit this —
/// `showModalBottomSheet` captures the caller's inherited theme, so a
/// picker that paints with `c.surface` would come out translucent-white
/// on its own untinted surface. Open nested sheets from a context ABOVE
/// this wrapper (a `State.context` is above it) or restore the base
/// palette first.
class SideTintedSubtree extends StatelessWidget {
  const SideTintedSubtree({
    super.key,
    required this.side,
    required this.child,
  });

  final Color side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = sideTintPalette(context.colors, side);
    final on = tint.textPrimary;
    return SheetTint(
      side: side,
      on: on,
      child: Theme(
        data: theme.copyWith(
          brightness: on == Colors.white ? Brightness.dark : Brightness.light,
          extensions: [
            ...theme.extensions.values.where((e) => e is! AppColorsExtension),
            tint,
          ],
        ),
        child: child,
      ),
    );
  }
}
