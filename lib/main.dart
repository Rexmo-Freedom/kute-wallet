import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:async';
import 'package:kute/app_widget.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/restart_widget.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/exit_reason_service.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/tx_fiat_snapshot_service.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kute/firebase_options.dart';
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
import 'package:kute/services/venue_total_cache_service.dart';

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

Future<void> _initializeApp() async {
  // Boot fan-out. Each leg is wrapped in its own try-catch so a single
  // failure (no internet, missing `.env`, Hive corruption, Firebase
  // outage) can't sink the whole boot. Without this, `Future.wait`
  // rejects on the first throw and we never reach `runApp` — the user
  // sees the native splash forever and assumes the app crashed.
  // .env FIRST, not inside the fan-out: the PostHog + AppsFlyer client
  // keys live there now (no longer hardcoded in source), so _initPostHog
  // below must not race the load. It's a local asset read — milliseconds.
  await dotenv.load(fileName: ".env").catchError((_) {
    // .env missing in release/CI — fall back to platform-channel
    // ints / build flavor; downstream services read with defaults.
  });
  await Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
        .catchError((_) {}),
    _initFirebase(),
    _initPostHog().catchError((_) {/* network/SDK init failed; buffer */}),
    _initHive(),
  ]);
  // The analytics opt-out lives in Hive, so apply it the moment Hive is
  // open, before anything below can fire an event. Synchronous; the SDK
  // opt-out it may trigger is fire-and-forget.
  TrackingService.applyStoredOptOut();

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

  RuntimeCapabilitiesService.instance.start();
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
  // AppsFlyer (install attribution / ad ROAS) + AffiliateService +
  // PostHog identify: DEFERRED as one fire-and-forget CHAIN. The chain
  // preserves the required internal ordering — AppsFlyer after
  // TrackingService.initialize (awaited above, so the device UUID
  // exists for customerUserId) and BEFORE AffiliateService auth (so
  // authWallet can hand the appsflyer_id to the backend for S2S
  // revenue events); identify runs after restore so the next event
  // lands under the stable identity. None of it is needed for first
  // frame: attribution fires once per install and queues, the
  // affiliate code is read lazily by the Earn screen, and pre-identify
  // events sit under PostHog's anonymous id and are aliased on
  // identify (the 'unknown' sentinel fallback still counts the user in
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
    await AppsFlyerService.init().catchError((_) {});
    // WalletIdentityService binds to Breez SDK lazily (in the Earn
    // screen's bootstrap) — no SDK wait here.
    await AffiliateService.restore().catchError((_) {});
    unawaited(RuntimeCapabilitiesService.instance.refresh().then((ok) {
      TrackingService.setSessionKey('backend_reachable', ok);
    }, onError: (Object _) {
      TrackingService.setSessionKey('backend_reachable', false);
    }));
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
    // Surveys are never shown in Kute (founder decision, 2026-09-30).
    // Set explicitly so an SDK default flip can't render one.
    ..surveys = false
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
  // Timeout-guard the setup so a no-internet cold start can't hang boot on
  // the SDK's init. PostHog is offline-safe (it queues events to disk and
  // flushes when connectivity returns); the timeout just protects first frame.
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
  // All box opens run in PARALLEL — they're independent file opens with
  // no data dependencies, and sequential awaits put ~20 × ~40ms of I/O
  // on the cold-start critical path (measured as one of the top splash
  // costs). `_openHiveBoxSafe` still isolates per-box corruption.
  //
  // Box-by-box rationale (kept from the sequential version):
  //  * TxFiatSnapshotService.boxName — at-the-time USD value of txs
  //    (Outlogic / BTC receives+sends / Polymarket) for historical
  //    value + gain/loss vs current price.
  //  * once_flags — once-only milestone flags (first_swap, first_bet…).
  //  * milestones_log — chronological log of unlocked milestones.
  //  * polymarket_suppressed_positions — recently sold/redeemed
  //    positions stay hidden across restarts while the Data API
  //    catches up (epoch-ms per conditionId).
  //  * polymarket_optimistic_activity — synthetic Sold/Bought entries
  //    injected before the Data API confirms them.
  //  * polymarket_spark_txs — Spark tx ids from bet/claim plumbing,
  //    hidden from the Activity feed.
  //  * polymarket_spark_claim_windows — expected-inbound windows for
  //    Orchestra claim receives.
  //  * polymarket_orchestra_orders — orderIds tagged as bet-flow
  //    plumbing (hidden); user Convert exchanges stay visible.
  //  * polymarket_bet_funding — per-bet funding-currency tag (BTC vs
  //    USDC), read on resolve/sell to route proceeds back.
  //  * polymarket_btc_route_queue — queued USDC.e → BTC routes drained
  //    once the pUSD unwrap settles.
  //  * fee_history — universal fee ledger for the analytics Fees tab.
  //  * wallet_balance_cache — per-wallet balance snapshots so cards
  //    never flash "0" on open.
  //  * polymarket_usdc_cache — last-known Safe USDC.e balance.
  //  * venue_total_cache — last-known Predictions / Investing total per
  //    wallet, so the balance headers never show a bare dash.
  //  * polymarket_activity_cache / polymarket_usdc_receives_cache /
  //    mempool_address_tx_cache — API-response caches so cold start
  //    renders the Activity feed without waiting on live APIs.
  //  * wallet_transaction_cache — per-wallet Transaction snapshots
  //    read synchronously at construction time.
  //  * spark_address_ring — recent Spark deposit addresses (ring, max
  //    5) so pending inbound txs survive address rotation + restarts.
  //  * settings — pre-opened here (was opened lazily by
  //    initialSettingsProvider on the splash critical path; opening it
  //    in this parallel batch removes that sequential cost — openBox
  //    on an already-open box is a fast no-op there).
  await Future.wait([
    _openHiveBoxSafe<String>('asset_icons'),
    _openHiveBoxSafe<String>(TxFiatSnapshotService.boxName),
    _openHiveBoxSafe<bool>('once_flags'),
    _openHiveBoxSafe('milestones_log'),
    _openHiveBoxSafe<String>('outlogicOrders'),
    _openHiveBoxSafe<String>('accumulation_addresses'),
    _openHiveBoxSafe<String>('usdc_balance_history'),
    _openHiveBoxSafe<String>('polymarket_suppressed_positions'),
    _openHiveBoxSafe<String>('polymarket_optimistic_activity'),
    _openHiveBoxSafe<String>('polymarket_spark_txs'),
    _openHiveBoxSafe<String>('polymarket_spark_claim_windows'),
    _openHiveBoxSafe<String>('orchestra_delivery_spark_txs'),
    _openHiveBoxSafe<String>('polymarket_orchestra_orders'),
    _openHiveBoxSafe<String>('polymarket_bet_funding'),
    _openHiveBoxSafe<String>('polymarket_btc_route_queue'),
    _openHiveBoxSafe<String>('fee_history'),
    _openHiveBoxSafe<String>('wallet_balance_cache'),
    _openHiveBoxSafe<double>('polymarket_usdc_cache'),
    _openHiveBoxSafe<double>(VenueTotalCacheService.boxName),
    _openHiveBoxSafe<String>('polymarket_activity_cache'),
    _openHiveBoxSafe<String>('polymarket_usdc_receives_cache'),
    _openHiveBoxSafe<String>('mempool_address_tx_cache'),
    _openHiveBoxSafe<String>('hyperliquid_markets_cache_v1'),
    _openHiveBoxSafe<String>('hyperliquid_sparklines_v1'),
    _openHiveBoxSafe<String>('polymarket_feed_cache_v1'),
    _openHiveBoxSafe<String>('wallet_transaction_cache'),
    _openHiveBoxSafe<String>('spark_address_ring'),
    // Settings box: plain open, NOT _openHiveBoxSafe — the safe variant
    // deletes a corrupt box from disk, which is right for cache-tier
    // boxes but would silently wipe the WALLET LIST here. A failed open
    // just falls through; initialSettingsProvider retries it and owns
    // the error surface exactly as before.
    Hive.openBox('settings').then((_) {}, onError: (_) {}),
  ]);
}

Future<void> _openHiveBoxSafe<T>(String name) async {
  try {
    await Hive.openBox<T>(name);
  } catch (e) {
    await Hive.deleteBoxFromDisk(name);
    await Hive.openBox<T>(name);
  }
}
