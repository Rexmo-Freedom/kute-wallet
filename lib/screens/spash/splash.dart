import 'dart:async' show unawaited;

import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class Splash extends ConsumerStatefulWidget {
  const Splash({super.key});

  @override
  ConsumerState<Splash> createState() => _SplashState();
}

class _SplashState extends ConsumerState<Splash>
    with TickerProviderStateMixin {
  // Phase 1: Logo + text entrance
  late final AnimationController _entranceController;
  // Phase 2: Dot escapes — jumps up and bounces around
  late final AnimationController _dotEscapeController;
  // Phase 3: Dog chases the dot
  late final AnimationController _chaseController;
  // Ambient glow

  // Entrance animations
  late final Animation<double> _textOpacity;
  late final Animation<double> _textSlide;
  late final Animation<double> _subtitleOpacity;

  // Dot escape: the dot jumps out of position
  late final Animation<double> _dotOffsetX;
  late final Animation<double> _dotOffsetY;
  late final Animation<double> _dotBounceScale;

  // Dog chase: dog follows the dot
  late final Animation<double> _dogOpacity;
  late final Animation<double> _dogOffsetX;
  late final Animation<double> _dogOffsetY;
  late final Animation<double> _dogBounce;

  // Glow

  @override
  void initState() {
    super.initState();

    // ── Phase 1: Entrance (0–900ms) ──
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.85, curve: Curves.easeOut),
      ),
    );
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    // ── Phase 2: Dot escapes (800ms) ──
    // The dot jumps up-right, then bounces to a new spot
    _dotEscapeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Dot arcs right and up, then settles upper-right
    _dotOffsetX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 60), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 60, end: 40), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 40, end: 55), weight: 40),
    ]).animate(CurvedAnimation(
      parent: _dotEscapeController,
      curve: Curves.easeOut,
    ));
    _dotOffsetY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -80), weight: 35),
      TweenSequenceItem(tween: Tween(begin: -80, end: -30), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -30, end: -60), weight: 35),
    ]).animate(CurvedAnimation(
      parent: _dotEscapeController,
      curve: Curves.easeOut,
    ));
    _dotBounceScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.6), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 0.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.2), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(
      parent: _dotEscapeController,
      curve: Curves.easeInOut,
    ));

    // ── Phase 3: Dog chases (1000ms, starts slightly after dot) ──
    _chaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _dogOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _chaseController,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
      ),
    );
    // Dog follows the dot but arrives a bit behind/below
    _dogOffsetX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -30, end: 20), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 20, end: 35), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 35, end: 30), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _chaseController,
      curve: Curves.easeOut,
    ));
    _dogOffsetY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 20, end: -50), weight: 35),
      TweenSequenceItem(tween: Tween(begin: -50, end: -10), weight: 35),
      TweenSequenceItem(tween: Tween(begin: -10, end: -30), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _chaseController,
      curve: Curves.easeOut,
    ));
    // Dog bounces as it runs
    _dogBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -8, end: 0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -6, end: 0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0, end: -4), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 25),
    ]).animate(CurvedAnimation(
      parent: _chaseController,
      curve: Curves.linear,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      // `remove()` lets the engine send its first frame; the callback
      // registered here runs right after that frame, which is the first
      // one the user sees. One `app_time_to_first_frame` per cold start
      // (the key is consumed, so a later splash visit is a no-op).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LatencyTracker.stop(LatencyKeys.appTimeToFirstFrame);
      });
      // ── Choreography ──
      // Reduce-motion: skip the decorative entrance/dot-escape/dog-chase
      // animations entirely. Snap the entrance controller to its end so
      // the logo, subtitle and loading dots render fully visible (their
      // opacity/slide are driven off this controller), but don't run any
      // of the looping/transition motion. The loading indicator itself
      // stays animating — that's essential progress feedback.
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward().then((_) {
          // After entrance, pause, then dot escapes
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            _dotEscapeController.forward();
          });
          // Dog starts chasing slightly after the dot moves
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            _chaseController.forward();
          });
        });
      }
      _initializeAppAndRedirect();
    });
  }

  Future<void> _initializeAppAndRedirect() async {
    final stopwatch = Stopwatch()..start();
    final bootstrap = StorageBootstrap();
    // iOS launch before the first unlock after a reboot: read nothing
    // until protected data is available, then reload the settings.
    if (await bootstrap.waitForProtectedData()) {
      ref.invalidate(initialSettingsProvider);
    }
    if (!mounted) return;
    await ref.read(initialSettingsProvider.future);
    if (!mounted) return;
    // One-time cleanup of the retired iCloud recovery manifest (non-secret
    // labels only). Fire-and-forget: it never blocks or fails the start.
    unawaited(PasskeyService.retireRecoveryManifest());

    // Minimum splash floor cut 2200ms → 500ms: the old value was a hard
    // 2.2s artificial delay on EVERY cold start (the single largest
    // splash cost — settings load takes ~100-300ms, so users stared at
    // a finished animation for ~2s). 500ms keeps one beat of the brand
    // entrance so fast devices don't flash-cut mid-animation, while
    // giving back ~1.7s of cold-start time.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    stopwatch.stop();
    final settings = ref.read(settingsProvider);
    final bool hasAccount = settings.wallets.isNotEmpty;

    TrackingService.track('app_open');
    TrackingService.track('app_startup_completed', params: {'startup_ms': stopwatch.elapsedMilliseconds});
    // First-ever launch (no wallets yet, no install-id seen). Fired
    // once per device install — distinct from `app_open` which fires
    // on every cold start. Lets the install→first-funded funnel be
    // measured on day-1 retention.
    if (!hasAccount) {
      TrackingService.firstAppLaunch();
    }
    // Cold-start completion event — `app_startup_completed` above
    // tracks just startup_ms. This one is the structured equivalent
    // with the wallet-state context analysts need to segment cold
    // boots from warm resumes.
    TrackingService.appColdStartCompleted(
      startupMs: stopwatch.elapsedMilliseconds,
      hasWallet: hasAccount,
      walletCategory: settings.activeWallet == null
          ? null
          : TrackingService.walletCategory(
              isHardware: settings.activeWallet!.isHardware,
              isWatchOnly: settings.activeWallet!.isWatchOnly,
              isSigner: settings.activeWallet!.isSigner,
              isExternalAddress: settings.activeWallet!.isExternalAddress,
            ),
    );
    TrackingService.setUserProperty('has_wallet', hasAccount.toString());
    TrackingService.setUserProperty('wallet_count', settings.wallets.length.toString());
    TrackingService.setUserProperty('preferred_currency', settings.currency);
    TrackingService.setUserProperty('language', settings.language);
    TrackingService.setUserProperty('theme', settings.themeMode);
    // Report the CURRENT Electrum node (custom vs preset) so the whole base
    // is segmentable, not just users who change it this session.
    TrackingService.reportElectrumNode(settings.nodeType);
    if (hasAccount && settings.activeWallet != null) {
      final w = settings.activeWallet!;
      TrackingService.setActiveWalletCategory(
        TrackingService.walletCategory(
          isHardware: w.isHardware,
          isWatchOnly: w.isWatchOnly,
          isSigner: w.isSigner,
          isExternalAddress: w.isExternalAddress,
        ),
      );
      // Always land on the spending (Portfolio) card after a cold
      // start or post-grace resume. Spark / balance / address
      // providers are bound to the active wallet — when the user
      // last left the app on a savings card and the OS killed the
      // process, restoring straight into that savings context fires
      // spending-only providers against a wallet they don't apply
      // to and crashes mid-load. Resetting active here keeps the
      // load path on a known-good wallet; the carousel still lets
      // the user swipe to savings, and the wallet-scoped providers
      // render those views safely on demand.
      final isSavings = w.isHardware ||
          w.isWatchOnly ||
          w.isExternalAddress ||
          w.isSigner;
      if (isSavings) {
        final spending = pickSpendingWallet(settings);
        if (spending != null && spending.id != w.id) {
          await ref
              .read(settingsProvider.notifier)
              .setActiveWallet(spending.id);
          if (!mounted) return;
        }
      }
    }

    StorageBootResult boot;
    try {
      boot = await bootstrap.classify(hasWallets: hasAccount);
    } catch (e, st) {
      // Not user-caused: the storage layer could not even be classified.
      TrackingService.recordHandled(TrackingService.errorCategory(e), e, st,
          flow: 'app_start', stage: 'storage_classify');
      boot = const StorageBootResult(StorageBootState.storageUnavailable);
    }
    if (!mounted) return;
    ref.read(storageBootStateProvider.notifier).state = boot.state;
    TrackingService.seedStorageState(state: boot.state.name);

    switch (boot.state) {
      case StorageBootState.fresh:
        context.go('/start');
      case StorageBootState.secretsMissing:
        context.go('/restore_secrets',
            extra: RestoreSecretsReason.secretsMissing);
      case StorageBootState.storageUnavailable:
        context.go('/storage_unavailable', extra: boot);
      case StorageBootState.preBinding:
      case StorageBootState.ok:
      case StorageBootState.hiveRestoredOld:
      case StorageBootState.bindingMismatch:
        context.go('/open_pin');
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _dotEscapeController.dispose();
    _chaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final Color bgColor = c.background;
    final Color textColor = c.textPrimary;
    final Color subtitleColor = c.textTertiary;
    final Color accentColor = context.colors.accent;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Plain background — black in dark mode, white in light.
          // The earlier radial gradient + ambient yellow glow + floating
          // particles read as marketing-screen overkill on a wallet
          // app; calmer is better here. Theme background is enough.
          Container(color: bgColor),

          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Brand area: "kute" text + escaping dot + chasing dog ──
                SizedBox(
                  height: 180.h,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // "kute" text (without the dot)
                      AnimatedBuilder(
                        animation: _entranceController,
                        builder: (_, __) => Transform.translate(
                          offset: Offset(0, _textSlide.value),
                          child: Opacity(
                            opacity: _textOpacity.value,
                            child: Text(
                              'kute',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 56.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.4,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // The dot — starts next to "kute", then escapes
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _entranceController,
                          _dotEscapeController,
                        ]),
                        builder: (_, __) {
                          final escaped = _dotEscapeController.value > 0;
                          return Transform.translate(
                            offset: Offset(
                              // Start right of "kute", then escape
                              52.w + (escaped ? _dotOffsetX.value : 0),
                              _textSlide.value + (escaped ? _dotOffsetY.value : 0),
                            ),
                            child: Transform.scale(
                              scale: escaped ? _dotBounceScale.value : 1.0,
                              child: Opacity(
                                opacity: _textOpacity.value,
                                child: Text(
                                  '.',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 56.sp,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // Dog chasing the dot
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _chaseController,
                        ]),
                        builder: (_, __) {
                          if (_chaseController.value == 0) {
                            return const SizedBox.shrink();
                          }
                          return Transform.translate(
                            offset: Offset(
                              _dogOffsetX.value,
                              _dogOffsetY.value + _dogBounce.value,
                            ),
                            child: Opacity(
                              opacity: _dogOpacity.value,
                              child: SvgPicture.asset(
                                kuteDogAsset(context),
                                width: 40.sp,
                                height: 40.sp,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Subtitle
                AnimatedBuilder(
                  animation: _entranceController,
                  builder: (_, __) => Opacity(
                    opacity: _subtitleOpacity.value,
                    child: Text(
                      context.l10n.splashTagline,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 56.h),

                // Loading dots — staggeredDotsWave matches the rest of
                // the app's loading language (onboarding, sheets, etc.)
                AnimatedBuilder(
                  animation: _entranceController,
                  builder: (_, __) => Opacity(
                    opacity: _subtitleOpacity.value,
                    child: LoadingAnimationWidget.staggeredDotsWave(
                      color: accentColor,
                      size: 28.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

