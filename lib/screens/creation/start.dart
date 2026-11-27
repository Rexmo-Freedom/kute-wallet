import 'dart:math';
import 'package:kute/screens/shared/sal_sprite.dart';
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
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/platform/platform_caps.dart';
import 'package:kute/platform/kute_wide_frames.dart';

class Start extends ConsumerStatefulWidget {
  const Start({super.key});

  @override
  _StartState createState() => _StartState();
}

class _StartState extends ConsumerState<Start> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _breatheController;

  // Staggered entrance animations
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _headlineFade;
  late Animation<double> _buttonsFade;
  late Animation<Offset> _buttonsSlide;

  // The background wash breathing
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
      // Skip the entrance and the breathing background wash: snap
      // straight to the final composed frame.
      _entranceController.value = 1.0;
      // Haptics still fire on a single beat so the "arrival" cue survives
      // without the looping/staggered motion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) HapticFeedback.heavyImpact();
      });
      return;
    }

    _entranceController.forward();
    _breatheController.repeat(reverse: true);
    // One beat as Sal lands, after he has scaled in (~0.35 of the 2 s
    // entrance = ~700 ms). The echo and the decay tail that chased the
    // spark burst went with it (founder, 27 November 2026).
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _breatheController.dispose();
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
          // Across the whole window, never cut at the form column's sides.
          Positioned.fill(
            child:
                KuteFullBleed(child: _buildBackground(c, accentColor, isLight)),
          ),
          PlatformSafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28.w),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Sal on his own (founder, 27 November 2026: the
                  // lightning burst around him is gone), in the same
                  // 220 box it filled, so the column keeps its rhythm.
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Hero(
                        tag: 'app_logo',
                        child: SizedBox(
                          width: 220.w,
                          height: 220.w,
                          child: Center(
                            // The 3D Sal idling (he breathes, wags, blinks
                            // and glances around); the rig until the
                            // sheets exist.
                            child: SalSprite(
                              clip: 'body_idle',
                              size: 160.w,
                              fallback: KuteDogIdle(size: 160.w),
                            ),
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
            // Quiet alternative: a text button above the bar.
            AppTextButton(
              text: context.l10n.iAlreadyHaveAnAccount,
              textColor: c.textSecondary,
              onPressed: () {
                TrackingService.onboardingCtaTapped('already_have_wallet');
                ref.read(recoveryModeProvider.notifier).state = true;
                context.push('/set_pin');
              },
            ),
            // THE BAR IS THE BUTTON (kute_bar_context.dart): Create account
            // is the floating Sal bar's primary action.
            KuteBarContextScope(
              barContext: KuteBarContext.primary(
                label: context.l10n.createAccount,
                onPrimary: () {
                  TrackingService.onboardingCtaTapped('get_started');
                  ref.read(recoveryModeProvider.notifier).state = false;
                  context.push('/set_pin');
                },
                source: 'start',
                disabledLabel: null,
              ),
              // The link 12 above the bar (founder, 1 November 2026), the
              // bar centred at its own width: the room the bar takes, less
              // the 20 the column keeps under it.
              child: SizedBox(
                  height: KuteBarPrimaryButton.roomUnder(context,
                          pageToFoot: !PlatformOs.isAndroid) -
                      20.h),
            ),
          ],
        ),
      ),
    );
  }
}

/// THE BRAND SIDE of a split screen on EXPANDED (round three, founder 25
/// November 2026: "it must be all occupying full screen when we can";
/// kute_split_screen.dart): the Start screen's own hero, Sal idling over
/// the tagline (no burst around him since 27 November 2026), on its
/// breathing background wash across the whole half. No entrance (the
/// steps after Start show it already composed, so moving between steps
/// never replays it) and no haptics; the wash breathes unless Reduce
/// Motion is on.
class StartBrandSide extends StatefulWidget {
  const StartBrandSide({super.key});

  @override
  State<StartBrandSide> createState() => _StartBrandSideState();
}

class _StartBrandSideState extends State<StartBrandSide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breatheController = AnimationController(
    duration: const Duration(seconds: 4),
    vsync: this,
  );
  late final Animation<double> _breathe =
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _breatheController.stop();
      _started = false;
    } else if (!_started) {
      _started = true;
      _breatheController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = !context.isDark;
    final accent = c.accent;
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // The Start screen's 220 box around Sal, a little larger on a wide
      // half.
      final box = (w * 0.42).clamp(220.0, 320.0);
      final scale = box / 220;
      return AnimatedBuilder(
        animation: _breathe,
        builder: (context, _) {
          final t = _breathe.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              // The app's background, as the form half's: the seam
              // between the halves is no line, only the glow fading out.
              ColoredBox(color: c.background),
              // The Start screen's two glows, sized to the half. Each
              // fades out whole before the seam (a radial glow cut at the
              // half's edge would stand as a hard vertical line); they
              // bleed off the window's own edges only.
              Positioned(
                top: -h * 0.16 + (10 * sin(t * pi)),
                right: w * 0.06,
                child: _glow(
                  w * 0.85,
                  accent.withValues(
                      alpha: isLight ? 0.06 + 0.02 * t : 0.10 + 0.04 * t),
                ),
              ),
              Positioned(
                bottom: -h * 0.06 - (15 * sin(t * pi * 0.7)),
                left: -w * 0.18,
                child: _glow(
                  w * 0.7,
                  (isLight ? accent : c.surfaceLight)
                      .withValues(alpha: isLight ? 0.04 : 0.12 + 0.04 * t),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: box,
                        height: box,
                        child: Center(
                          child: SalSprite(
                            clip: 'body_idle',
                            size: 160 * scale,
                            fallback: KuteDogIdle(size: 160 * scale),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 40 * min(scale, 1.3),
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.6,
                            height: 1.05,
                            fontFamily: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.fontFamily,
                          ),
                          children: [
                            TextSpan(
                              text: context.l10n.startTaglineLead,
                              style: TextStyle(color: c.textPrimary),
                            ),
                            TextSpan(
                              text: context.l10n.startTaglineAccent,
                              style: TextStyle(color: accent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      );
}
