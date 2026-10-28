import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:async';
import 'package:kute/app_widget.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/restart_widget.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/exit_reason_service.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/hive_boot.dart';
import 'package:kute/services/icon_cache/icon_warmup.dart';
import 'package:kute/services/hive_wipe.dart' show deleteOrphanedHiveBoxes;
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kute/firebase_options.dart';
import 'package:kute/theme/app_theme.dart' show loadAppFonts;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Wall-clock stamp taken at the very first line of `main()`. Read once
/// from the first home render to emit the `app_cold_start` latency
/// bucket. Lives at top-level so `app_widget.dart`'s first-home observer
/// can reach it without threading it through the widget tree.
final Stopwatch appColdStartStopwatch = Stopwatch()..start();

Future<void> main() async {
  // Boot latency stamps (durations only). Stopped by the splash once the
  // first frame is actually shown (native splash removed) and by the home
  // card's first real balance render.
  LatencyTracker.start(LatencyKeys.appTimeToFirstFrame);
  LatencyTracker.start(LatencyKeys.balanceLoaded);
  // Run the whole app inside a guarded zone so that async / microtask
  // errors which escape `FlutterError.onError` and
  // `PlatformDispatcher.instance.onError` (e.g. an unawaited Future that
  // throws deep in a provider) still reach the crash sink. Together with
  // the two handlers installed in `_bootstrap`, this gives PostHog Error
  // Tracking the COMPLETE set of Dart exceptions — not just widget-tree
  // build failures. `ensureInitialized()` runs inside the same zone as
  // `runApp` (both live in `_bootstrap`) to avoid a zone mismatch.
  runZonedGuarded<Future<void>>(_bootstrap, (error, stack) {
    if (!kDebugMode) {
      try {
        TrackingService.recordCrash(error, stack, reason: 'zone', fatal: true);
      } catch (_) {/* Crashlytics not initialized yet */}
    }
    try {
      TrackingService.unhandledExceptionCaught(
        errorClass: error.runtimeType.toString(),
        crashType: 'dart_fatal',
      );
    } catch (_) {}
  });
}

Future<void> _bootstrap() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Pre-warm the Liquid Glass shader pipeline so the first glass paint
  // (the bottom command bar) doesn't flash. Fire-and-forget — it warms via
  // a post-frame callback and must never delay boot.
  unawaited(LiquidGlassWidgets.initialize());

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Cap Flutter's image cache. Default is 100 MB of decoded bitmaps in
  // RAM, which on a 6 GB device thrashes GC every time the user
  // browses Polymarket markets / asset icons / token logos. The
  // 105 ms+ "Background concurrent copying GC" pauses we saw on the
  // S21FE costs ~6 frames each. 30 MB is plenty for the icon set we
  // actually use; cache misses just decode again from the on-disk
  // file cache (free).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;

  // Install global error handlers BEFORE Firebase init so they're
  // active for the entire boot sequence and any later runtime error.
  // Previously these lived inside `Firebase.initializeApp().then(...)`
  // — on no/slow internet the SDK init could be delayed or fail and
  // the handlers never got attached, so any subsequent build-method
  // exception (e.g. a settings toggle rebuilding a screen that reads
  // a network-stalled AsyncValue) red-screened the UI. The handlers
  // are now no-op-safe when Crashlytics isn't ready yet (try/catch
  // around the recordError call swallows the "Firebase not initialized"
  // assertion).
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kDebugMode) {
      try {
        TrackingService.recordCrash(error, stack, fatal: true);
      } catch (_) {/* Crashlytics not initialized yet */}
    }
    try {
      TrackingService.unhandledExceptionCaught(
        errorClass: error.runtimeType.toString(),
        crashType: 'dart_fatal',
      );
    } catch (_) {}
    return true;
  };
  // Framework errors (build/layout/paint/gesture) are caught by Flutter
  // and the app keeps running, so they are NON-fatal: recording them as
  // fatal inflated the crash-free rate with errors no user saw as a crash.
  // `silent` ones (e.g. image-load noise) are skipped entirely.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.silent) return;
    if (!kDebugMode) {
      try {
        TrackingService.recordCrash(
          details.exception,
          details.stack,
          reason: details.library,
          fatal: false,
          information: [
            if (details.context != null) 'context: ${details.context}',
            if (details.library != null) 'library: ${details.library}',
            ...TrackingService.crashContextLines(),
          ],
        );
      } catch (_) {/* Crashlytics not initialized yet */}
    }
    try {
      TrackingService.unhandledExceptionCaught(
        errorClass: details.exception.runtimeType.toString(),
        screenName: details.library,
        crashType: 'dart_nonfatal',
      );
    } catch (_) {}
  };

  // Build-method failures: in release the default `ErrorWidget` is a
  // grey box ("In release Flutter shows a grey box"), but it lays out
  // with `width:double.infinity` which itself can re-throw when the
  // parent constraint is unbounded — that's the actual "the screen
  // crashes" UX the user sees. Swap in a zero-sized SizedBox so a
  // broken subtree silently vanishes instead of cascading.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return const SizedBox.shrink();
  };

  await _initializeApp();

  // Icon disk caches open now; the logos of the last launch are read
  // back into memory after the first frame (non-blocking).
  startIconWarmup();

  runApp(
    const OverlaySupport.global(
      child: RestartWidget(
        child: AppWidget(),
      ),
    ),
  );
}

/// Firebase init that can NEVER sink the boot `Future.wait`. The old
/// inline `.catchError((_) => Firebase.app())` fallback threw a second
/// exception when `initializeApp` failed because no config existed for
/// the platform (the macOS Runner had no GoogleService-Info.plist), and
/// an exception inside `catchError` fails the leg anyway — so boot died
/// before `runApp` and the deferred first frame left a black window.
/// Options come from the flutterfire-generated `firebase_options.dart`
/// so desktop works without a bundled plist; on timeout/failure the app
/// simply continues without Firebase (handlers are no-op-safe).
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    // Offline cold start, Firebase outage, or an unconfigured platform —
    // analytics resume on a later launch; never block first frame.
  }
}

/// Awaits [step] and attaches how long it took, as `<name>_ms`, to the
/// `app_time_to_first_frame` event the splash emits. The step's own
/// error handling stays with the step: this never throws and never adds
/// a wait of its own.
Future<void> _timedBootStep(String name, Future<void> step) async {
  final sw = Stopwatch()..start();
  try {
    await step;
  } finally {
    sw.stop();
    LatencyTracker.addParams(
        LatencyKeys.appTimeToFirstFrame, {'${name}_ms': sw.elapsedMilliseconds});
  }
}

Future<void> _initializeApp() async {
  // Boot fan-out. Each leg is wrapped in its own try-catch so a single
  // failure (no internet, missing `.env`, Hive corruption, Firebase
  // outage) can't sink the whole boot. Without this, `Future.wait`
  // rejects on the first throw and we never reach `runApp` — the user
  // sees the native splash forever and assumes the app crashed.
  // .env FIRST, not inside the fan-out: the PostHog + AppsFlyer client
  // keys live there now (no longer hardcoded in source), so _initPostHog
  // below must not race the load. It's a local asset read — milliseconds.
  // Every pre-frame step is timed onto `app_time_to_first_frame` so a slow
  // first frame names the step that caused it.
  await _timedBootStep(
      'env',
      dotenv.load(fileName: ".env").catchError((_) {
        // .env missing in release/CI — fall back to platform-channel
        // ints / build flavor; downstream services read with defaults.
      }));
  // PostHog's Dart setup is OFF the awaited path: it is started here, in
  // parallel with the fan-out, and the first frame does not wait for it.
  // Until it completes, TrackingService holds every capture in order and
  // releases them all in `markAnalyticsReady`, so no boot event is lost
  // and none reaches the SDK before its config. The hold is released
  // whatever the outcome (success, failure, the 5 s bound inside), so a
  // PostHog outage can never mute the app. `posthog_before_first_frame`
  // on the first-frame event says whether setup had finished by then.
  TrackingService.holdAnalyticsUntilReady();
  LatencyTracker.addParams(
      LatencyKeys.appTimeToFirstFrame, {'posthog_before_first_frame': 0});
  final posthogSw = Stopwatch()..start();
  unawaited(_initPostHog()
      .catchError((_) {/* network/SDK init failed; events buffer */})
      .whenComplete(() {
    posthogSw.stop();
    LatencyTracker.addParams(LatencyKeys.appTimeToFirstFrame, {
      'posthog_ms': posthogSw.elapsedMilliseconds,
      'posthog_before_first_frame': 1,
    });
    TrackingService.markAnalyticsReady();
  }));
  await Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
        .catchError((_) {}),
    _timedBootStep('firebase', _initFirebase()),
    _timedBootStep('hive', _initHive()),
    // Inter is in the engine before the first frame lays out any text (a
    // local asset read, done well inside the legs above).
    loadAppFonts(),
  ]);
  // The analytics opt-out was applied inside `_initHive` (hive_boot.dart)
  // the moment the settings box opened, before anything below fires.

  // Firebase Crashlytics is the single crash backend. The native manifests
  // ship with collection OFF (AndroidManifest
  // firebase_crashlytics_collection_enabled=false, Info.plist
  // FirebaseCrashlyticsCollectionEnabled=NO) so a debug build never reports
  // even before Dart runs; this call is the one switch, ON in
  // release/profile and explicitly OFF in debug (the override persists
  // across launches, so native crashes early in the next boot are covered).
  // Crash reports are NOT tied to the analytics opt-out: the privacy policy
  // (§6.3) covers them separately. Crashlytics is offline-safe; not awaited
  // so a slow/failed enable can never block first frame or throw into boot.
  try {
    unawaited(FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode)
        .catchError((_) {}));
  } catch (_) {/* Firebase not ready (offline cold start) — retries next launch */}
  // Once-per-session crash context key (release-gated inside).
  try {
    TrackingService.setSessionKey(
        'locale', PlatformDispatcher.instance.locale.toLanguageTag());
    TrackingService.setSessionKey('breez_connected', false);
  } catch (_) {}

  // The runtime policy goes out FIRST, in parallel with the first frame:
  // the policy service adopts the policies saved on disk and asks for the
  // public policy (no session needed) at once; the stored session token is
  // read from secure storage (a local read, no network, no AppsFlyer, no
  // sign-in) and the session policy is layered on top as soon as it is.
  // Nothing below waits for either. Never minted here: a session mint
  // signs with the hot wallet and must stay behind AppsFlyer init (see the
  // chain below), and the policy service has no container to mint with
  // yet; a wallet without a stored session keeps the public policy until
  // the background registration mints one.
  final publicPolicyFetched = RuntimeCapabilitiesService.instance.start();
  // Region answers follow the network: the venue checks and the policy's
  // region denials are asked again on resume and on a network or VPN
  // change (native path listener), so a stale "restricted" never sticks.
  RegionFreshness.start();
  final sessionRestored = AffiliateService.restore().catchError((_) {});
  final sessionPolicyFetched = sessionRestored
      .then((_) => RuntimeCapabilitiesService.instance.refreshAfterCurrent());
  unawaited(Future.wait([publicPolicyFetched, sessionPolicyFetched]).then(
      (landed) {
    TrackingService.setSessionKey('backend_reachable', landed.any((ok) => ok));
  }, onError: (Object _) {
    TrackingService.setSessionKey('backend_reachable', false);
  }));
  // Analytics must never delay first frame (offline, PostHog down).
  await TrackingService.initialize()
      .timeout(const Duration(seconds: 4), onTimeout: () {})
      .catchError((_) {});
  // Post-mortem for the PREVIOUS run. LMK/OOM kills and native (Rust
  // FFI) aborts bypass every Dart handler, so they never reach
  // Crashlytics — and Play vitals misses them too (LMK isn't counted
  // as a crash; sideloaded builds don't report at all). On Android 11+
  // the OS records why the last process died (ApplicationExitInfo);
  // report the abnormal ones now that Crashlytics + Hive are up.
  // Fire-and-forget — must never delay first frame.
  unawaited(ExitReasonService.reportLastExit());
  // AppsFlyer (install attribution / ad ROAS) + PostHog identify:
  // DEFERRED as one fire-and-forget CHAIN. The chain preserves the
  // required internal ordering — the PostHog setup first (so identify
  // reaches a configured SDK), AppsFlyer after TrackingService.initialize
  // (awaited above, so the device UUID exists for customerUserId) and
  // BEFORE any AffiliateService auth (so authWallet can hand the
  // appsflyer_id to the backend for S2S revenue events; the session
  // restore above only reads storage); identify runs after that restore
  // so the next event lands under the stable identity. None of it is
  // needed for first frame: attribution fires once per install and
  // queues, the affiliate code is read lazily by the Earn screen, and
  // pre-identify events sit under PostHog's anonymous id and are aliased
  // on identify (the 'unknown' sentinel fallback still counts the user in
  // MAU until a real code lands).
  //
  // Persist any deferred-deeplink referrer the moment AppsFlyer
  // delivers it, so it survives the race against the first authWallet
  // (and across boots) and binds within the backend's 7-day late-bind
  // window. Wired BEFORE init so a callback that fires during startup
  // is captured.
  AppsFlyerService.onReferrerCaptured = AffiliateService.setPendingReferrer;
  AppsFlyerService.onInstallAttributionCaptured =
      AffiliateService.queueInstallAttribution;
  unawaited(() async {
    await TrackingService.analyticsReady;
    await AppsFlyerService.init().catchError((_) {});
    // WalletIdentityService binds to Breez SDK lazily (in the Earn
    // screen's bootstrap) — no SDK wait here.
    await sessionRestored;
    try {
      final code = AffiliateService.affiliateCode ?? '';
      await TrackingService.identifyWithAffiliate(code);
    } catch (_) {}
  }());
  // Breez Spark init can hang on no/slow internet — the SDK opens a
  // gRPC channel to the Breez node and won't return until it either
  // connects or its internal timer fires. Bound the wait so the
  // splash always hands off to `runApp` within a few seconds; if init
  // didn't complete in time, downstream Spark-reading providers fall
  // through to their cached/empty branches and the SDK will retry
  // when the screen that needs it actually mounts.
  final sparkSw = Stopwatch()..start();
  try {
    await BreezSdkSparkLib.init().timeout(const Duration(seconds: 6));
    sparkSw.stop();
    TrackingService.sparkSdkConnect(
        result: 'ok', latencyMs: sparkSw.elapsedMilliseconds);
    if (kDebugMode) {
      // Debug builds print the SDK's own wallet sync steps (`[sdk-sync]`),
      // so a slow or failing sync step shows which one it is.
      try {
        BreezSdkSpark().initializeLogStream(
            logFilter: kSdkSyncDebugLogFilter, printSyncSteps: true);
      } catch (_) {
        // Rust's process-global logger can still target the previous Dart
        // isolate after a hot restart. Do not silently lose device diagnosis.
        debugPrint('[sdk-sync] logging_unavailable: fully stop and relaunch '
            'the app to restore native sync diagnostics.');
      }
    }
  } catch (e) {
    sparkSw.stop();
    // A TimeoutException means the 6s bound fired; anything else is a
    // genuine init/connect error. Both still degrade gracefully.
    TrackingService.sparkSdkConnect(
      result: e is TimeoutException ? 'timeout' : 'error',
      latencyMs: sparkSw.elapsedMilliseconds,
    );
    // Degrade gracefully (downstream Spark providers fall through to
    // cached/empty branches), but ALSO report the swallowed init
    // failure — recordCrash is release-gated and message-scrubbed.
    TrackingService.recordCrash(e, null, reason: 'breez_spark_init');
  }
}

/// PostHog Dart-side init. The Android meta-data / iOS Info.plist keys
/// already auto-init the native SDK; this Dart call sets the explicit
/// config the Flutter wrapper uses for events fired from Dart.
///
/// HARD CONSTRAINT — `sessionReplay: false`. The platform manifests
/// also have replay disabled. Both layers must be flipped on (AND
/// every sensitive-screen `PostHogMaskWidget` audited) before any
/// replay can be enabled. Private keys, recovery phrases, and signer
/// state must never enter the rolling pre-crash buffer.
///
/// Debug builds: SDK is set up so calls don't crash, then immediately
/// disabled so NO events (custom OR autocaptured lifecycle/screen)
/// reach PostHog. `TrackingService._disabled = kDebugMode` already
/// short-circuits our custom `track()` calls; this disable belt is for
/// the SDK's own autocapture stream (`Application Opened`, `$screen`,
/// `$autocapture`) so `flutter run` sessions never inflate DAU/MAU.
Future<void> _initPostHog() async {
  // Project token lives in .env (loaded before this runs). The same token
  // also sits in the AndroidManifest / Info.plist PROJECT_TOKEN meta-data —
  // the native SDK auto-init reads it from there at install time and can't
  // see .env, so both copies must stay in sync. POSTHOG_API_KEY is the old
  // .env name, still read so existing .env files keep working.
  final envToken = dotenv.env['POSTHOG_PROJECT_TOKEN'] ?? '';
  final projectToken =
      envToken.isNotEmpty ? envToken : dotenv.env['POSTHOG_API_KEY'] ?? '';
  if (projectToken.isEmpty) {
    // .env missing/incomplete — skip the Dart-side setup. The native
    // manifest auto-init still runs, so lifecycle capture survives.
    return;
  }
  // Host routes through our managed reverse proxy (m.rexmo.io)
  // instead of eu.i.posthog.com — bypasses ad blockers / privacy
  // extensions that intercept requests to known analytics domains.
  // The PostHog ingestion pipeline behind the proxy is unchanged.
  // Both Android `POSTHOG_HOST` meta-data + iOS Info.plist key must
  // match this value (the native SDK reads them at install time).
  final config = PostHogConfig(projectToken)
    ..host = 'https://m.rexmo.io'
    ..captureApplicationLifecycleEvents = true
    ..debug = kDebugMode
    ..sessionReplay = false
    // PostHog is collection only: nothing in the app reads a feature flag
    // (see TrackingService.isDisabled), so the flag fetch the SDK would
    // otherwise make at setup is a network round-trip for nothing, on the
    // boot path of a weak link. Off, like the explicit reload was before.
    ..preloadFeatureFlags = false
    // Surveys are never shown in Kute (founder decision, 2026-09-30).
    // Set explicitly so an SDK default flip can't render one.
    ..surveys = false
    // No rage-click capture (on by default for iOS in the SDK). The
    // native SDK builds those events itself, so they never pass the
    // beforeSend scrubbers below, and three quick taps on one PIN keypad
    // key would say where on screen they landed.
    ..rageClickConfig = (PostHogRageClickConfig()..enabled = false)
    // Last line of defence before anything leaves the device. Exception
    // capture is off, so this should never have work to do; it is here so
    // that if a future flag or SDK default turns it back on, the message
    // body is scrubbed rather than shipped verbatim.
    //
    // dropWhenMuted runs first: while the user has opted out (or a debug
    // build is muted), nothing captured from Dart reaches the SDK queue.
    ..beforeSend = [
      TrackingService.dropWhenMuted,
      TrackingService.sanitizeExceptionEvent,
    ];
    // PostHog is PRODUCT ANALYTICS ONLY now. All crash / exception reporting
    // (Dart + native + ANR) goes to Firebase Crashlytics — so every PostHog
    // error-capture flag stays OFF and we no longer send `$exception` events.
  // Bounded so a wedged SDK init can never keep the capture hold in
  // `_initializeApp` closed for long. PostHog is offline-safe (it queues
  // events to disk and flushes when connectivity returns).
  await Posthog().setup(config).timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
  if (kDebugMode) {
    await Posthog().disable().catchError((_) {});
  }
}

Future<void> _initHive() async {
  final directory = await getApplicationDocumentsDirectory();
  Hive.init(directory.path);
  Hive.registerAdapter(SwapOrderAdapter());
  // Every startup box, the stored analytics opt-out and the once-per-
  // launch reusable-deposit hygiene live in lib/services/hive_boot.dart
  // so a test can run exactly this path.
  await openStartupHiveBoxes();
  // Boxes a retired build left behind that nothing reads (best-effort).
  await deleteOrphanedHiveBoxes();
}
