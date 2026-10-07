import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color accent;
  final Color accentLight;

  final Color success;
  final Color error;
  final Color warning;
  final Color info;

  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceElevated;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  final Color border;
  final Color borderFocused;
  final Color borderSubtle;

  final Color gradientTop;
  final Color gradientBottom;

  final Color cardShadow;

  final Color dragHandle;
  final Color modalBarrier;

  /// The charts' categorical palette (the allocation donuts and their
  /// legends): five distinct hues for the named slices, in slot order, and
  /// a muted grey last for "Other". Stepped per mode against the card
  /// surface: every slot clears 3:1 on it, and neighbouring slots differ in
  /// lightness as well as hue so they stay apart under red-green colour
  /// blindness. None is the market up/down pair or the accent, so an
  /// allocation never reads as a gain, a loss or an action.
  final List<Color> chartCategorical;

  const AppColorsExtension({
    required this.accent,
    required this.accentLight,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.border,
    required this.borderFocused,
    required this.borderSubtle,
    required this.gradientTop,
    required this.gradientBottom,
    required this.cardShadow,
    required this.dragHandle,
    required this.modalBarrier,
    required this.chartCategorical,
  });

  factory AppColorsExtension.dark() => AppColorsExtension(
        accent: const Color(0xFFF7931A),
        accentLight: const Color(0xFFFFB74D),
        success: const Color(0xFF34C759),
        error: const Color(0xFFFF3B30),
        warning: const Color(0xFFF7931A),
        info: const Color(0xFF007AFF),
        // Flat charcoal, the same near-black as the light-mode primary button.
        // Surfaces step up from it so cards stay distinct without a gradient.
        background: const Color(0xFF1D2024),
        surface: const Color(0xFF262A2F),
        surfaceLight: const Color(0xFF30353B),
        surfaceElevated: const Color(0xFF3B4148),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFF8E8E93),
        textTertiary: const Color(0xFF636366),
        textDisabled: const Color(0xFF48484A),
        border: Colors.white.withValues(alpha: 0.08),
        borderFocused: const Color(0xFFF7931A),
        borderSubtle: Colors.white.withValues(alpha: 0.05),
        gradientTop: const Color(0xFF1D2024),
        gradientBottom: const Color(0xFF1D2024),
        cardShadow: Colors.black.withValues(alpha: 0.4),
        dragHandle: Colors.white.withValues(alpha: 0.2),
        modalBarrier: Colors.black.withValues(alpha: 0.3),
        // Violet, cyan, azure, sand, pink; slate for Other.
        chartCategorical: const [
          Color(0xFF9B79EE),
          Color(0xFF4CD1EE),
          Color(0xFF347EC4),
          Color(0xFFEBD56A),
          Color(0xFFEC78C9),
          Color(0xFF70777F),
        ],
      );

  factory AppColorsExtension.light() => AppColorsExtension(
        accent: const Color(0xFF3B82F6),
        accentLight: const Color(0xFF60A5FA),
        success: const Color(0xFF1B9E52),
        error: const Color(0xFFCC3328),
        warning: const Color(0xFFD4800E),
        info: const Color(0xFF1A6FD4),
        // Pure white background; card surface is a near-imperceptible
        // off-white so every card differentiates from the background even
        // without a shadow. Reads visually as "white card on white bg"
        // but guarantees a clean delineation — belt-and-braces safety
        // net for the ~25 hand-built card decorations across the app
        // that don't all carry explicit light-mode shadows.
        background: const Color(0xFFFFFFFF),
        surface: const Color(0xFFF8FAFC),
        // SurfaceLight is the input/inset tone used for filled fields,
        // selected pills, divider rails. Bumped a touch darker than the
        // old #F6F7F9 so it still reads as a distinct fill against the
        // now-white background.
        surfaceLight: const Color(0xFFF3F5F8),
        surfaceElevated: const Color(0xFFEDF0F4),
        textPrimary: const Color(0xFF1D2024),
        textSecondary: const Color(0xFF626972),
        textTertiary: const Color(0xFF9CA2AB),
        textDisabled: const Color(0xFFD0D4DA),
        border: const Color(0xFFE2E5EA),
        borderFocused: const Color(0xFF1A6FD4),
        borderSubtle: const Color(0xFFEAECEF),
        // Flat-white gradient. The old #F0F2F5 → #F0F2F5 gave the screen a
        // slight grey wash that competed with the card surfaces; pure
        // white is the canvas.
        gradientTop: const Color(0xFFFFFFFF),
        gradientBottom: const Color(0xFFFFFFFF),
        // Slightly stronger card shadow than before (0x0A → 0x14) so
        // cards still pop against the now-equal-white background.
        cardShadow: const Color(0x14000000),
        dragHandle: Colors.black.withValues(alpha: 0.10),
        modalBarrier: Colors.black.withValues(alpha: 0.20),
        // Violet, cyan, cobalt, ochre, magenta; slate for Other.
        chartCategorical: const [
          Color(0xFF6443CC),
          Color(0xFF0999B2),
          Color(0xFF1E5099),
          Color(0xFFB88513),
          Color(0xFFC348A9),
          Color(0xFF666C75),
        ],
      );

  @override
  ThemeExtension<AppColorsExtension> copyWith({
    Color? accent,
    Color? accentLight,
    Color? success,
    Color? error,
    Color? warning,
    Color? info,
    Color? background,
    Color? surface,
    Color? surfaceLight,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? border,
    Color? borderFocused,
    Color? borderSubtle,
    Color? gradientTop,
    Color? gradientBottom,
    Color? cardShadow,
    Color? dragHandle,
    Color? modalBarrier,
    List<Color>? chartCategorical,
  }) {
    return AppColorsExtension(
      accent: accent ?? this.accent,
      accentLight: accentLight ?? this.accentLight,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      borderFocused: borderFocused ?? this.borderFocused,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      gradientTop: gradientTop ?? this.gradientTop,
      gradientBottom: gradientBottom ?? this.gradientBottom,
      cardShadow: cardShadow ?? this.cardShadow,
      dragHandle: dragHandle ?? this.dragHandle,
      modalBarrier: modalBarrier ?? this.modalBarrier,
      chartCategorical: chartCategorical ?? this.chartCategorical,
    );
  }

  @override
  ThemeExtension<AppColorsExtension> lerp(
      covariant ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      accent: Color.lerp(accent, other.accent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocused: Color.lerp(borderFocused, other.borderFocused, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      gradientTop: Color.lerp(gradientTop, other.gradientTop, t)!,
      gradientBottom: Color.lerp(gradientBottom, other.gradientBottom, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      dragHandle: Color.lerp(dragHandle, other.dragHandle, t)!,
      modalBarrier: Color.lerp(modalBarrier, other.modalBarrier, t)!,
      chartCategorical: [
        for (var i = 0; i < chartCategorical.length; i++)
          i < other.chartCategorical.length
              ? Color.lerp(chartCategorical[i], other.chartCategorical[i], t)!
              : chartCategorical[i],
      ],
    );
  }
}

extension AppThemeX on BuildContext {
  AppColorsExtension get colors =>
      Theme.of(this).extension<AppColorsExtension>()!;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Primary-CTA fill: the sober monochrome CTA — NEAR-BLACK in light mode,
  /// WHITE in dark mode (never orange, never blue). This restores the
  /// documented original design; the light-mode blue accent fill was drift.
  /// Text on it must contrast — see [ctaOnColor].
  Color get ctaFill => isDark ? AppColors.ctaFillDark : colors.textPrimary;

  /// Text/icon color on [ctaFill]: white on the near-black light fill,
  /// near-black on the white dark fill (white-on-white is not allowed).
  Color get ctaOnColor =>
      isDark ? AppColors.ctaTextOnDark : AppColors.ctaTextOnLight;
}

/// Returns the black/white text color that gives the best WCAG contrast
/// against [background]. Picks white when contrast(white) > contrast(black),
/// otherwise black. Use on filled buttons / chips whose background is a
/// saturated brand color (accent, success, error, warning) where the
/// "obvious" Colors.white can fall below the 3:1 large-text threshold —
/// notably orange (#F7931A) at L≈0.40 where white scores 2.3:1 and black
/// scores 9.1:1. The threshold-on-luminance heuristic in WCAG gives the
/// same answer here because we only compare against pure black/white, but
/// computing both contrasts is what the rule actually says to do.
Color contrastingOnColor(Color background) {
  final lum = background.computeLuminance();
  // Math crossover is ~0.179 but mid-luminance saturated colors (blue, red,
  // purple) read as "dark" to designers and conventionally take white text.
  // Threshold 0.30 keeps black on truly-light bgs (orange #F7931A L≈0.40,
  // yellow, light/pastel reds like Poly red #FF6565 L≈0.31, light greys)
  // while flipping medium-dark colored bgs (pure red #FF3B30 L≈0.25,
  // pure blue, purple) to white. #196 — was 0.35 which incorrectly
  // flipped Poly red to white despite white-on-red scoring only 2.88
  // contrast vs black-on-red scoring 6.4.
  return lum > 0.30 ? Colors.black : Colors.white;
}

class AppColors {
  AppColors._();

  static const Color accent = Color(0xFFF7931A);
  static const Color accentLight = Color(0xFFFFB74D);

  // Primary CTA fill: sober monochrome — NEAR-BLACK in light mode (white
  // text), WHITE in dark mode (near-black text). White text on the white
  // button is not allowed. Light fill uses the live `textPrimary`; only the
  // dark fill + on-colors are fixed here. Resolve per-mode via
  // `context.ctaFill` / `context.ctaOnColor`.
  static const Color ctaFillDark = Color(0xFFF5F5F7); // white (dark mode)
  static const Color ctaTextOnLight = Color(0xFFFFFFFF); // on the dark fill
  static const Color ctaTextOnDark = Color(0xFF111114); // on the white fill

  // Canonical market-direction pair for BUY/SELL, YES/NO, up/down fills and
  // chart strokes. Distinct from `success`/`error` (which mean "operation
  // outcome", not "price direction"). These replace the scattered local
  // greens/reds (#16A34A, #1FA663, #22C55E, #47C97A / #FF5252, #D9485A,
  // #EF4444, #FF6565) — use these two everywhere a value goes up or down.
  static const Color marketUp = Color(0xFF1FA663);
  static const Color marketDown = Color(0xFFD9485A);

  static const Color success = Color(0xFF34C759);
  static const Color error = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFF7931A);
  static const Color info = Color(0xFF007AFF);

  static const Color ledger = Color(0xFFFFFFFF);
  static const Color passport = Color(0xFF5ABCB9);
  static const Color jade = Color(0xFF00B473);
  static const Color seedsigner = Color(0xFFFF6B00);
  static const Color keystone = Color(0xFF4CAF50);
  static const Color krux = Color(0xFFB388FF);
}

class AppRadius {
  AppRadius._();

  /// Shared action-button geometry. Category chips and navigation chrome
  /// use their own shapes; actions never fall back to Material's pill shape.
  static const buttonBorder = BorderRadius.all(Radius.circular(12));

  static double get sm => 8.r;
  static double get md => 12.r;
  static double get lg => 16.r;
  static double get xl => 20.r;
  static double get xxl => 24.r;
  static double get pill => 100.r;
}

class PlatformSafeArea extends StatelessWidget {
  final Widget child;
  final bool top;

  const PlatformSafeArea({
    super.key,
    required this.child,
    this.top = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: top,
      bottom: Platform.isAndroid,
      child: child,
    );
  }
}

class AppDecorations {
  AppDecorations._();

  static BoxDecoration card(BuildContext context,
      {Color? color, Color? borderColor}) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: color ?? c.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      // Light mode drops the border entirely — cards lift from the
      // white background via layered shadows instead of a hairline
      // outline (the fintech "floating card" look). Dark mode is
      // unchanged and keeps the 1px outline.
      border:
          isLight ? null : Border.all(color: borderColor ?? c.border, width: 1),
      boxShadow: isLight
          ? [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 4)),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 1)),
            ]
          : null,
    );
  }

  static BoxDecoration fintechCard(BuildContext context, {Color? accentColor}) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      // Same rule as `card`: light mode = no border, just shadow.
      // Dark mode keeps the existing 1px outline.
      border: isLight ? null : Border.all(color: c.border, width: 1),
      boxShadow: isLight
          ? [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 6)),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ]
          : [
              BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 20,
                  offset: const Offset(0, 4))
            ],
    );
  }

  static BoxDecoration innerCard(BuildContext context, {Color? borderColor}) {
    final c = context.colors;
    return BoxDecoration(
      color: c.surfaceLight,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: borderColor ?? c.border),
    );
  }

  static BoxDecoration bottomSheet(BuildContext context) {
    final c = context.colors;
    return BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
    );
  }

  /// Flat page background in both modes. The name stays for its 40+ callers.
  static BoxDecoration screenGradient(BuildContext context) =>
      BoxDecoration(color: context.colors.background);

  /// Flat by default: screens sit on the plain background (same as
  /// [screenGradient]). Only an explicit [color] paints a radial glow.
  static BoxDecoration ambientGlow(BuildContext context, {Color? color}) {
    if (color == null) return const BoxDecoration();
    return BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topCenter,
        radius: 1.0,
        colors: [
          color.withValues(alpha: 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ),
    );
  }

  static Widget dragHandle(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: 36.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: c.dragHandle,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle heading1(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 28.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
      );

  static TextStyle heading2(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 22.sp,
        fontWeight: FontWeight.bold,
      );

  static TextStyle heading3(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 18.sp,
        fontWeight: FontWeight.bold,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w500,
      );

  static TextStyle bodySmall(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
      );

  static TextStyle caption(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );

  static TextStyle sectionHeader(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 14.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      );

  static TextStyle balance(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 34.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.0,
      );

  static TextStyle modalTitle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 18.sp,
        fontWeight: FontWeight.bold,
      );

  static TextStyle modalItem(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
      );

  static TextStyle modalSubtitle(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 15.sp,
      );

  static TextStyle settingsTitle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
      );

  static TextStyle settingsSubtitle(BuildContext context) => TextStyle(
        color: context.colors.textSecondary,
        fontSize: 15.sp,
      );
}

const _actionButtonStyle = ButtonStyle(
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: AppRadius.buttonBorder),
  ),
);

ThemeData buildDarkTheme() {
  final ext = AppColorsExtension.dark();
  return ThemeData(
    brightness: Brightness.dark,
    fontFamily: GoogleFonts.inter().fontFamily,
    scaffoldBackgroundColor: ext.background,
    appBarTheme: AppBarTheme(
      backgroundColor: ext.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ext.textPrimary,
      selectionColor: ext.textPrimary.withValues(alpha: 0.4),
      selectionHandleColor: ext.textPrimary,
    ),
    elevatedButtonTheme:
        const ElevatedButtonThemeData(style: _actionButtonStyle),
    filledButtonTheme: const FilledButtonThemeData(style: _actionButtonStyle),
    outlinedButtonTheme:
        const OutlinedButtonThemeData(style: _actionButtonStyle),
    textButtonTheme: const TextButtonThemeData(style: _actionButtonStyle),
    extensions: [ext],
  );
}

ThemeData buildLightTheme() {
  final ext = AppColorsExtension.light();
  return ThemeData(
    brightness: Brightness.light,
    fontFamily: GoogleFonts.inter().fontFamily,
    scaffoldBackgroundColor: ext.background,
    canvasColor: ext.surface,
    cardColor: ext.surface,
    dividerColor: ext.border,
    appBarTheme: AppBarTheme(
      backgroundColor: ext.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ext.textPrimary,
      selectionColor: ext.accent.withValues(alpha: 0.2),
      selectionHandleColor: ext.accent,
    ),
    elevatedButtonTheme:
        const ElevatedButtonThemeData(style: _actionButtonStyle),
    filledButtonTheme: const FilledButtonThemeData(style: _actionButtonStyle),
    outlinedButtonTheme:
        const OutlinedButtonThemeData(style: _actionButtonStyle),
    textButtonTheme: const TextButtonThemeData(style: _actionButtonStyle),
    extensions: [ext],
  );
}
