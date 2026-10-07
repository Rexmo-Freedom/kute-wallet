import 'dart:math';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';

class Start extends ConsumerStatefulWidget {
  const Start({super.key});

  @override
  _StartState createState() => _StartState();
}

class _StartState extends ConsumerState<Start> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _breatheController;
  late AnimationController _sparksEntrance;

  // Staggered entrance animations
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _headlineFade;
  late Animation<double> _buttonsFade;
  late Animation<Offset> _buttonsSlide;

  // Ambient glow breathing
  late Animation<double> _breathe;

  @override
  void initState() {
    super.initState();
    TrackingService.onboardingStartedOnce();
    trackOnboardingStep('welcome');

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _breatheController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    // Logo: 0% - 30%
    _logoFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
      ),
    );

    // Headline: 15% - 45%
    _headlineFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.15, 0.45, curve: Curves.easeOut),
    );

    // Buttons: 55% - 80%
    _buttonsFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.55, 0.8, curve: Curves.easeOut),
    );
    _buttonsSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.55, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _breathe = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // Sparks — Strike-style. One-shot pop-in animation that runs
    // after Sal lands. Each individual spark adds its own stagger
    // inside the painter using `progress` as a global clock.
    _sparksEntrance = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Animation starts are deferred to didChangeDependencies so we can
    // honour the platform "reduce motion" setting (read off MediaQuery,
    // which is only reliable after initState). See _startAnimations.

    // Passkey discovery happens on /recover_wallet so the welcome
    // screen stays uncluttered — see RecoverWallet._checkForPasskeys.
  }

  bool _animationsStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationsStarted) return;
    _animationsStarted = true;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      // Skip the decorative entrance bloom, breathing glow loop and the
      // one-shot spark burst — snap straight to the final composed frame.
      _entranceController.value = 1.0;
      _sparksEntrance.value = 1.0;
      // Haptics still fire on a single beat so the "arrival" cue survives
      // without the looping/staggered motion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) HapticFeedback.heavyImpact();
      });
      return;
    }

    _entranceController.forward();
    _breatheController.repeat(reverse: true);
    // Fire the sparks after the logo has scaled in (~0.35 of the
    // 2 s entrance = ~700 ms). Strike-style thunder-reverb: a
    // heavy "strike" doubled at +80 ms to feel like a clap echoing
    // off the chest, then a decay tail of medium/light/selection
    // pulses chasing the visual spark fade.
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _sparksEntrance.forward();
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) HapticFeedback.heavyImpact();
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
      Future.delayed(const Duration(milliseconds: 340), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
      Future.delayed(const Duration(milliseconds: 480), () {
        if (mounted) HapticFeedback.lightImpact();
      });
      Future.delayed(const Duration(milliseconds: 620), () {
        if (mounted) HapticFeedback.selectionClick();
      });
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _breatheController.dispose();
    _sparksEntrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = !context.isDark;
    final accentColor = isLight ? c.accent : context.colors.accent;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          _buildBackground(c, accentColor, isLight),
          PlatformSafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28.w),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Dog logo + Strike-style spark burst. The sparks
                  // sit in a fixed-size box around the dog so they
                  // can radiate beyond the GIF's bounds without
                  // disturbing the column's vertical rhythm.
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Hero(
                        tag: 'app_logo',
                        child: SizedBox(
                          width: 220.w,
                          height: 220.w,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: Listenable.merge(
                                    [_sparksEntrance, _breatheController]),
                                builder: (context, _) {
                                  return CustomPaint(
                                    size: Size(220.w, 220.w),
                                    painter: _SparkPainter(
                                      entrance: _sparksEntrance.value,
                                      twinkle: _breatheController.value,
                                      color: accentColor,
                                    ),
                                  );
                                },
                              ),
                              // The hero. The sparks behind him were always
                              // animated; Sal himself was a still GIF loop.
                              // He now breathes, wags, blinks and glances
                              // around inside the same burst.
                              KuteDogIdle(size: 160.w),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 28.h),

                  // Hero tagline — mirrors the website: "Change starts
                  // with **you.**" with the accent landing on "you.".
                  FadeTransition(
                    opacity: _headlineFade,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 40.sp,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.6,
                          height: 1.05,
                          fontFamily:
                              Theme.of(context).textTheme.bodyLarge?.fontFamily,
                        ),
                        children: [
                          // Both halves are localized. This was the very
                          // first screen of the app and the only words on
                          // it were hardcoded English, so a Portuguese
                          // user was greeted in a language they may not
                          // read, before anything else had happened.
                          TextSpan(
                            text: context.l10n.startTaglineLead,
                            style: TextStyle(color: c.textPrimary),
                          ),
                          TextSpan(
                            text: context.l10n.startTaglineAccent,
                            style: TextStyle(color: accentColor),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 4),

                  _buildActions(c, accentColor, isLight),

                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(
      AppColorsExtension c, Color accentColor, bool isLight) {
    return AnimatedBuilder(
      animation: _breathe,
      builder: (context, _) {
        final t = _breathe.value;
        return Stack(
          children: [
            Container(
              decoration: isLight
                  ? BoxDecoration(color: c.background)
                  : BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [c.gradientTop, c.gradientBottom],
                      ),
                    ),
            ),
            Positioned(
              top: -140.h + (10.h * sin(t * pi)),
              right: -80.w,
              child: Container(
                width: 360.w,
                height: 360.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accentColor.withValues(
                          alpha: isLight ? 0.06 + 0.02 * t : 0.10 + 0.04 * t),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -40.h - (15.h * sin(t * pi * 0.7)),
              left: -100.w,
              child: Container(
                width: 280.w,
                height: 280.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isLight ? accentColor : c.surfaceLight)
                          .withValues(alpha: isLight ? 0.04 : 0.12 + 0.04 * t),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActions(AppColorsExtension c, Color accentColor, bool isLight) {
    return FadeTransition(
      opacity: _buttonsFade,
      child: SlideTransition(
        position: _buttonsSlide,
        child: Column(
          children: [
            CustomButton(
              text: context.l10n.createAccount,
              primaryColor: context.ctaFill,
              // Let the button pick a contrasting label (white on the light
              // mode blue, black on the dark mode yellow). Was hardcoding
              // white-in-light / background-in-dark, which drifted from the
              // other CTAs and left the perma-dark onboarding inconsistent.
              textColor: contrastingOnColor(accentColor),
              onPressed: () {
                TrackingService.onboardingCtaTapped('get_started');
                ref.read(recoveryModeProvider.notifier).state = false;
                context.push('/set_pin');
              },
            ),

            SizedBox(height: 12.h),

            // Quiet alternative — the secondary tier (AppButton fires
            // the light haptic itself).
            AppButton(
              text: context.l10n.iAlreadyHaveAnAccount,
              variant: AppButtonVariant.secondary,
              textColor: c.textSecondary,
              fontSize: 15.sp,
              onPressed: () {
                TrackingService.onboardingCtaTapped('already_have_wallet');
                ref.read(recoveryModeProvider.notifier).state = true;
                context.push('/set_pin');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Strike-style lightning arc burst around Sal. Each spark is a
/// short jagged bolt radiating outward from just past the mascot's
/// silhouette — like static electricity arcing off him. Two
/// animation inputs:
///   * [entrance] (0..1) — one-shot bloom. Bolts grow outward
///     across this window with per-bolt stagger.
///   * [twinkle] (0..1) — continuous ambient pulse for the
///     post-entrance flicker (each bolt blinks at its own phase
///     so the field looks alive, not metronomic).
class _SparkPainter extends CustomPainter {
  final double entrance;
  final double twinkle;
  final Color color;
  // Deterministic seed so bolt geometry stays stable across rebuilds.
  // Re-rolling each frame would scatter the bolts visibly.
  static const _seed = 0xC0FFEE;
  static const int _boltCount = 10;

  const _SparkPainter({
    required this.entrance,
    required this.twinkle,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entrance <= 0) return;
    final rng = Random(_seed);
    final center = Offset(size.width / 2, size.height / 2);
    // Each bolt starts at the edge of the dog's silhouette
    // (~22% of canvas) and extends outward into the band.
    final innerRadius = size.width * 0.28;
    // Bolt length range — short enough to read as discrete sparks,
    // long enough to feel electric rather than dotted.
    final boltMin = size.width * 0.08;
    final boltMax = size.width * 0.16;

    // Pre-generate all bolt geometries (angle, length, segment
    // offsets) using the seeded RNG so paint order is stable.
    for (int i = 0; i < _boltCount; i++) {
      final t = i / _boltCount;
      // Stagger entrance — bolts bloom outward in a wave.
      final startThresh = t * 0.45;
      final localEntry = ((entrance - startThresh) / 0.55).clamp(0.0, 1.0);
      if (localEntry <= 0) continue;

      // Anchor angle: equally-spaced around the ring with a tight
      // jitter so the bolts don't form a perfect clock.
      final angle = (t * 2 * pi) + (rng.nextDouble() - 0.5) * 0.5;
      final boltLength = boltMin + rng.nextDouble() * (boltMax - boltMin);

      // Pre-generate zigzag offsets — 3 segments per bolt with
      // alternating perpendicular jitter so they read as lightning.
      const segments = 3;
      final jitterMags = List<double>.generate(
        segments,
        // Less jitter toward the tip — bolts end clean.
        (s) =>
            (0.38 - 0.18 * (s / segments)) * (0.55 + rng.nextDouble() * 0.45),
      );

      // Build the bolt path from anchor outward.
      final anchor = Offset(
        center.dx + cos(angle) * innerRadius,
        center.dy + sin(angle) * innerRadius,
      );

      // The bolt only extends as far as `localEntry` lets it grow.
      final grownLength =
          boltLength * Curves.easeOutCubic.transform(localEntry);
      final segLen = grownLength / segments;

      final path = Path()..moveTo(anchor.dx, anchor.dy);
      var curX = anchor.dx;
      var curY = anchor.dy;
      for (int s = 0; s < segments; s++) {
        // Alternate the jitter direction so it zigzags.
        final sign = (s % 2 == 0) ? 1.0 : -1.0;
        final segAngle = angle + sign * jitterMags[s];
        curX += cos(segAngle) * segLen;
        curY += sin(segAngle) * segLen;
        path.lineTo(curX, curY);
      }

      // Flicker: each bolt's alpha pulses on its own phase so the
      // crowd doesn't blink as one.
      final phase = (twinkle + t * 1.3) % 1.0;
      final flicker = 0.55 + 0.45 * sin(phase * 2 * pi);
      final alpha = (flicker * localEntry).clamp(0.0, 1.0);

      // Outer glow — wide, soft, blurred.
      final glow = Paint()
        ..color = color.withValues(alpha: 0.32 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(path, glow);

      // Mid stroke — softer ramp from glow to core.
      final mid = Paint()
        ..color = color.withValues(alpha: 0.55 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, mid);

      // Bright core — the actual lightning line.
      final core = Paint()
        ..color = color.withValues(alpha: 0.95 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, core);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.entrance != entrance || old.twinkle != twinkle || old.color != color;
}
