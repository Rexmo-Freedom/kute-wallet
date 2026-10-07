import 'dart:async';

import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab, activeShellTabProvider;
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/current_route_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/models/settings_model.dart' show Settings;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart'
    show needsWalletBackup;
import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/screens/app_shell.dart'
    show applyShellTabLivePolicy, pauseShellLiveSockets, resumeShellLiveSockets;
import 'package:kute/screens/polymarket/components/floating_stream_player.dart';
import 'package:kute/screens/shared/lock_overlay.dart';
import 'package:kute/screens/home/components/wallet_cards.dart'
    show WalletCardType, persistSelectedWalletCard, selectedWalletCardProvider;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/main.dart' show appColdStartStopwatch;
import './app_router.dart';

/// NavigatorObserver that (1) feeds the crash breadcrumb ring buffer
/// with screen NAMES only (no params — PII-free per the tracking rule)
/// and (2) fires the one-shot `app_cold_start` latency event the first
/// time the home route is reached. Wired alongside [PosthogObserver].
class _BreadcrumbObserver extends NavigatorObserver {
  bool _coldStartFired = false;

  void _record(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    TrackingService.pushBreadcrumb(name);
    if (!_coldStartFired && name == 'home') {
      _coldStartFired = true;
      // First home render: emit cold-start latency from main()'s stamp.
      // Deferred to the next frame so the timing reflects the home tree
      // actually painting, and so we never emit from inside route work.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appColdStartStopwatch.stop();
        TrackingService.appColdStart(
            latencyMs: appColdStartStopwatch.elapsedMilliseconds);
      });
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(previousRoute);
}

class AppWidget extends ConsumerStatefulWidget {
  const AppWidget({super.key});

  @override
  ConsumerState<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends ConsumerState<AppWidget>
    with WidgetsBindingObserver {
  late final GoRouter _router;

  DateTime? _pauseTime;
  // Anchors the start of the current foreground session so a coarse
  // session-length bucket can be emitted on background. Set on resume;
  // seeded here so the initial foreground session (cold start → first
  // background) is also measured.
  DateTime _foregroundAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Background sync (and any other route-aware service) needs to know
    // which screen the user is currently on. We feed the route name
    // through Riverpod via [currentRouteProvider], updated by an
    // observer attached to GoRouter. Using `ref.read` is safe inside a
    // navigation callback because pushes/pops happen between frames.
    final syncRouteObserver = SyncRouteObserver(
      onRouteChanged: (name) {
        if (!mounted) return;
        try {
          ref.read(currentRouteProvider.notifier).state = name;
        } catch (_) {}
      },
      // Popping back to an UNNAMED route means we're back over the nav
      // shell (its page carries no settings.name). Reset the route to
      // the active shell tab so the route-gated background pollers
      // (home 2 s sync loop, Polymarket poll pipeline, Spark push→sync)
      // resume instead of staying frozen on the closed sheet's name.
      onReturnedToUnnamed: () {
        if (!mounted) return;
        try {
          ref.read(currentRouteProvider.notifier).state =
              shellTabRouteName(ref.read(activeShellTabProvider));
        } catch (_) {}
      },
    );
    // Shell tab switches never traverse the root navigator (goBranch
    // swaps branch navigators inside the StatefulShellRoute), so the
    // observer above can't see them. Mirror the shell tab into the
    // route provider directly; fireImmediately seeds 'home' at boot so
    // the sync loop isn't gated off before the first navigation.
    // Crash context: the screen on top (named routes, and the shell tab's
    // route name when back over the nav shell or switching tabs).
    ref.listenManual<String?>(
      currentRouteProvider,
      (prev, next) => TrackingService.recordScreen(next),
      fireImmediately: true,
    );
    ref.listenManual<ActiveNavTab>(
      activeShellTabProvider,
      (prev, next) {
        TrackingService.setShellTab(next.name);
        // Deferred: fireImmediately invokes this synchronously inside
        // initState (mid first build), and tab writes land from
        // post-frame callbacks in AppShell — the microtask keeps every
        // provider write safely outside the build phase.
        scheduleMicrotask(() {
          if (!mounted) return;
          try {
            ref.read(currentRouteProvider.notifier).state =
                shellTabRouteName(next);
          } catch (_) {}
        });
      },
      fireImmediately: true,
    );
    // PostHog's GoRouter observer emits a `$screen` event on every
    // route push/pop. Pairs with the `PostHogWidget` wrapper below
    // (autocapture of taps + screens) for the funnel views.
    _router = AppRouter.createRouter('/splash', extraObservers: [
      syncRouteObserver,
      PosthogObserver(),
      _BreadcrumbObserver(),
    ]);
    WidgetsBinding.instance.addObserver(this);

    // Phase 4: stamp the user-settings person properties on boot. Read
    // once after the first frame so the settings provider is hydrated;
    // subsequent changes are picked up by the ref.listen in build().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _publishSettingsProps(ref.read(settingsProvider));
      } catch (_) {}
    });
    // The backend policy answer (referred or not) usually lands after the
    // first publish; re-publish when it does (throttled, so an answer that
    // changes nothing sends nothing).
    _capabilities = RuntimeCapabilitiesService.instance
      ..addListener(_onCapabilitiesChanged);
  }

  RuntimeCapabilitiesService? _capabilities;

  void _onCapabilitiesChanged() {
    if (!mounted) return;
    try {
      unawaited(_publishPersonProperties(ref.read(settingsProvider)));
    } catch (_) {}
  }

  /// Push the configuration and segmentation person properties from a
  /// [Settings] snapshot. Called on boot (post-frame) and from the
  /// ref.listen in build() whenever settings change; the segmentation set
  /// is throttled inside [TrackingService.refreshPersonProperties], so a
  /// settings change that touches none of it sends nothing. All values are
  /// coarse enums / counts / booleans — no PII, no amounts.
  void _publishSettingsProps(Settings settings) {
    TrackingService.refreshSettingsProps(
      selectedCurrency: settings.currency,
      btcFormat: settings.btcFormat,
      theme: settings.themeMode,
    );
    unawaited(_publishPersonProperties(settings));
  }

  Future<void> _publishPersonProperties(Settings settings) async {
    if (TrackingService.isDisabled) return;
    final wallets = settings.wallets;
    // Whether a PIN exists is a secure-storage read; a failed read leaves
    // the property untouched rather than guessing.
    bool? pinSet;
    try {
      pinSet = await ref
          .read(authModelProvider)
          .hasPinSet()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (!mounted) return;
    // Referrer truth is the backend's policy answer for this session; with
    // no snapshot yet the property is left as it was.
    final referred = RuntimeCapabilitiesService.instance.snapshot?.isReferred;
    TrackingService.refreshPersonProperties(
      walletCount: wallets.length,
      hardwareWalletKinds: [
        for (final w in wallets)
          if (w.isHardware) w.walletType,
      ],
      backedUp: wallets.isNotEmpty && !wallets.any(needsWalletBackup),
      hasPasskey: wallets.any((w) => w.isPasskey),
      biometricsEnabled: settings.biometricsEnabled,
      pinSet: pinSet,
      hasReferrer: referred,
    );
  }

  /// Builds the system UI overlay style for the given theme.
  /// On iOS, statusBarBrightness controls status bar icon color.
  /// On Android, statusBarIconBrightness controls status bar icon color.
  /// Both platforms: systemNavigationBarIconBrightness controls nav bar icons.
  static SystemUiOverlayStyle _buildOverlayStyle(bool isDark) {
    return SystemUiOverlayStyle(
      // Status bar
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark, // Android
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
      // Navigation bar — transparent for edge-to-edge
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );
  }

  bool _isPaused = false;

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // Recompute the status-bar overlay style when the user flips
    // device dark mode while the app is in the foreground — without
    // this, the overlay only updates on the next unrelated rebuild
    // and the status-bar icons read the wrong contrast.
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _isPaused = false;
        // Privacy cover down the moment we're active again.
        ref.read(appVisibleProvider.notifier).state = true;
        // Revive the live-price sockets: first re-stamp the per-tab
        // pause/resume policy for the visible shell tab, THEN clear the
        // background suspension. Order matters — resumeFromBackground
        // reconnects a feed an `acquire`d sheet still holds even when
        // its owning tab is not the active one, but only once the
        // policy has recorded which tab is on screen.
        applyShellTabLivePolicy(ref, ref.read(activeShellTabProvider));
        resumeShellLiveSockets(ref);
        _handleAppResume();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // `inactive` is ambiguous: the OS sends it both when the user
        // swipes away and when WE put a system biometric sheet on
        // screen. Face ID and the fingerprint prompt resign the app
        // active exactly like the app switcher does, so an unguarded
        // `inactive` threw the privacy cover over the user's own screen
        // for the whole scan, and booked the scan as a background trip
        // on top of that (spurious session events, and with auto-lock
        // set to immediately, a relock the moment the user passed the
        // very authentication being asked for). A prompt we started is
        // not the app leaving; a real departure always follows through
        // to paused/hidden, which still covers and still books.
        final selfPrompt = state == AppLifecycleState.inactive &&
            PrivacyCoverBridge.promptActive.value;
        if (!selfPrompt) {
          // Privacy cover up on INACTIVE already (not just paused) so
          // the iOS app-switcher snapshot captures the cover, never the
          // balances underneath.
          ref.read(appVisibleProvider.notifier).state = false;
          // iOS fires inactive → paused → hidden in succession on
          // background. Only run pause-side cleanup once per cycle —
          // re-stopping a Spark stream that's already torn down has
          // shown up as a backgrounding crash.
          if (!_isPaused) {
            _isPaused = true;
            _handleAppPause();
            BackgroundSyncService().stop();
          }
        }
        // Live-price sockets down only when the app actually leaves the
        // screen (paused/hidden) — NOT on `inactive`, which fires with
        // the app still fully visible (FaceID prompt mid-order, Control
        // Center pull, Android split-screen focus loss). Suspension is
        // unconditional even while an `acquire`d sheet (bet slip /
        // order slip / pro chart) holds the refcount; the resumed
        // branch above re-applies the per-tab policy and lifts the
        // suspension on the way back in. Idempotent, so the
        // paused → hidden double fire is harmless.
        if (state != AppLifecycleState.inactive) {
          pauseShellLiveSockets(ref);
        }
        break;
      case AppLifecycleState.detached:
        BackgroundSyncService().stop();
        break;
    }
  }

  /// Two-tier resume policy (was three-tier). The old middle tier
  /// (30s..5min → pop to /home without re-auth) is gone: it provided
  /// no security (still unlocked) and was the top UX complaint
  /// ("brief backgrounding dumps me on home"). The relock tier no
  /// longer navigates either — it engages the in-place [LockOverlay]
  /// over the live stack, so unlocking resumes the exact screen.
  ///
  ///   * `< autoLockSeconds` (Settings: 0 / 1min / 5min, default
  ///     5min) — stay on whatever screen the user was on; just
  ///     refresh balances.
  ///   * `>= autoLockSeconds` — lock IN PLACE via `appLockedProvider`
  ///     (the LockOverlay, drawn as the Welcome back screen). Cold start
  ///     still locks through splash → open_pin: the unlocked session is
  ///     memory-only.
  void _handleAppResume() {
    // NOTE: an earlier version short-circuited on a first-resume flag
    // and never evaluated the elapsed time on the first lifecycle
    // resume — that swallowed every relock decision after the first
    // background trip (the "app never auto-locks" bug). The
    // `_pauseTime != null` gate below already handles the cold-start
    // case (no pause recorded yet), so no extra guard exists.
    final relockAfter =
        Duration(seconds: ref.read(settingsProvider).autoLockSeconds);
    if (_pauseTime != null) {
      final elapsed = DateTime.now().difference(_pauseTime!);
      TrackingService.appForegrounded(sessionGapSeconds: elapsed.inSeconds);
      // New foreground session begins now — anchor for the next
      // `app_session` duration bucket fired on background.
      _foregroundAt = DateTime.now();
      // Android's BiometricPrompt fires inactive→resumed lifecycle events
      // every time it shows. If the user is on /open_pin (or under the
      // LockOverlay) and the prompt appears, we'd see a short-gap
      // "resume" here while the session is still locked. Firing sync in
      // that state builds breezSDKProvider while the session is locked,
      // which throws AND the FutureProvider caches the error — so every
      // sync after the user finally unlocks keeps failing on the cached
      // error and the wallet is stuck on "offline". Gate every
      // sync-firing branch on the lock state. NOTE the overlay lock
      // deliberately KEEPS sessionAuth in memory, so the lock state
      // comes from sessionUnlockedProvider, which also checks the overlay.
      final isLocked = !ref.read(sessionUnlockedProvider);
      // Negative elapsed = wall clock moved backwards while we were in
      // the background (manual change / timezone). We can't trust the
      // gap, so fail CLOSED and lock. Forward jumps only lock earlier,
      // which is safe.
      final clockRolledBack = elapsed.isNegative;
      if (isLocked) {
        // No-op: the re-auth surface (open_pin or LockOverlay) owns the
        // next sync kick via its unlock path.
      } else if (elapsed >= relockAfter || clockRolledBack) {
        // Lock IN PLACE: the LockOverlay covers the live stack and
        // unlocking resumes the exact screen. It is drawn as the same
        // Welcome back screen a cold start uses. Never navigate here:
        // iOS fires resume events for its own dialogs (Bluetooth pairing
        // during a Ledger import, permission prompts), so this can run
        // while a route is mid-transition, and replacing the stack then
        // crashed with a framework assertion.
        ref.read(appLockedProvider.notifier).state = true;
      } else {
        // Short gap: stay where the user was. Just refresh.
        // Defer EVERY heavy boot step past the first post-resume
        // frame. `BackgroundSyncService.start()` synchronously kicks
        // the pipelines, and the PushPipeline's first
        // `ref.read(breezSDKProvider.future)` triggers the FFI
        // `crateSdkConnect` handshake — observed at ~1 s on a real
        // device, blocking the calling isolate. Running both the
        // start and the refresh inside `addPostFrameCallback` means
        // the first frame paints from cached data before any of
        // that lands; the user sees their home immediately and any
        // subsequent stutter is invisible against an already-
        // populated UI rather than a frozen-empty one.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          BackgroundSyncService().start(context);
          // ignore: unawaited_futures
          BackgroundSyncService().forceRefreshAll();
          // A Predictions deposit that landed while the app was away is
          // still USDC.e: convert it now (the account's own guards apply).
          if (ref.exists(polymarketTradingProvider)) {
            unawaited(ref
                .read(polymarketTradingProvider.notifier)
                .wrapIdleUsdcE(trigger: 'resume'));
          }
        });
      }
    }
    _pauseTime = null;
  }

  void _handleAppPause() {
    _pauseTime ??= DateTime.now();
    TrackingService.appBackgrounded();
    // Emit the coarse length of the foreground session we're leaving.
    TrackingService.appSession(
      durationSeconds: DateTime.now().difference(_foregroundAt).inSeconds,
    );
  }

  @override
  void dispose() {
    _capabilities?.removeListener(_onCapabilitiesChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(settingsProvider).language;
    final themeMode = ref.watch(settingsProvider).themeMode;

    // Persist the user's foregrounded spending card (BTC vs USDC)
    // every time it changes — picking USDC and re-opening the app
    // should keep USDC on top.
    ref.listen<WalletCardType>(selectedWalletCardProvider, (prev, next) {
      if (prev == next) return;
      unawaited(persistSelectedWalletCard(next));
      // Central capture of the BTC vs USDC card-selection gateway —
      // fires wherever the front card flips (deck bring-to-front,
      // account-switcher pool pick, etc.) so the USDC home-action
      // funnel (card pick -> Receive/Deposit) is observable. The
      // StackedWalletDeck's `_bringToFront` was the documented call
      // site but is currently unwired, so emitting from the provider
      // flip is the single place that actually fires. Categorical
      // card_type only — no amount, no wallet id.
      TrackingService.homeWalletCardSelected(next.name);
    });

    // Phase 4: re-publish configuration person properties whenever any
    // tracked setting changes. Fires from a change callback (not the
    // build body), so it never emits on a plain rebuild.
    ref.listen(settingsProvider, (prev, next) {
      if (prev == next) return;
      _publishSettingsProps(next);
    });

    // `themeMode` is now tri-state: 'system' (default) / 'dark' / 'light'.
    // When 'system', mirror the device's current brightness for the
    // status-bar overlay style so the bar contrasts correctly out of
    // the gate; Flutter swaps the MaterialApp theme on system change
    // automatically because we pass `ThemeMode.system`.
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final bool isDark = themeMode == 'dark' ||
        (themeMode == 'system' && platformBrightness == Brightness.dark);
    final ThemeMode resolvedThemeMode = switch (themeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final overlayStyle = _buildOverlayStyle(isDark);
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
    // The native iOS app-switcher cover paints itself, outside any
    // Flutter frame, so it has to be told which Kute it is covering.
    // Only crosses the channel when the resolved mode changes.
    PrivacyCoverBridge.syncTheme(isDark: isDark);

    return Directionality(
      textDirection: TextDirection.ltr,
      // PostHogWidget enables tap autocapture across the whole tree.
      // Session replay stays OFF (set both in the Dart PostHogConfig
      // and in the Android / iOS manifest meta-data); sensitive
      // surfaces are further wrapped in `PostHogMaskWidget` so even
      // a future replay-on toggle never records seed/signer state.
      child: PostHogWidget(
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) {
            return MaterialApp.router(
              routerConfig: _router,
              locale: Locale(language),
              themeMode: resolvedThemeMode,
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) {
                // The language the app actually resolved (not the device's):
                // the `app_language` super property. Deduped inside.
                TrackingService.setAppLanguage(
                    Localizations.localeOf(context).languageCode);
                return Directionality(
                  textDirection: TextDirection.ltr,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: overlayStyle,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: const TextScaler.linear(1.0),
                      ),
                      child: Stack(
                        children: [
                          child!,
                          // Picture-in-picture livestream — persists across
                          // routes so the user can watch while betting.
                          const FloatingStreamPlayer(),
                          // In-place app lock: covers the live navigation
                          // stack when the background gap exceeded the
                          // auto-lock grace; unlocking dismisses it in
                          // place so the user resumes the exact screen
                          // (replaces the old go('/splash') relock that
                          // reset navigation to home).
                          const LockOverlay(),
                          // Topmost: opaque privacy cover while the app is
                          // inactive/backgrounded so the OS app switcher
                          // never snapshots balances.
                          const PrivacyCover(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
