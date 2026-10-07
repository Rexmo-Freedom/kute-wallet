import 'package:flutter/material.dart';
import 'package:kute/theme/app_theme.dart';

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
  return base.copyWith(
    background: side,
    surface: on.withValues(alpha: 0.16),
    surfaceLight: on.withValues(alpha: 0.24),
    surfaceElevated: on.withValues(alpha: 0.32),
    textPrimary: on,
    textSecondary: on.withValues(alpha: 0.78),
    textTertiary: on.withValues(alpha: 0.64),
    textDisabled: on.withValues(alpha: 0.38),
    border: on.withValues(alpha: 0.34),
    borderSubtle: on.withValues(alpha: 0.22),
    borderFocused: on,
    dragHandle: on.withValues(alpha: 0.45),
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
