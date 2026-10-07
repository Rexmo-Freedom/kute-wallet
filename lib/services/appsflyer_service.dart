import 'dart:async';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking/appsflyer_uninstall_token.dart';
import 'package:kute/services/tracking_service.dart';

/// AppsFlyer wrapper — install attribution + ad-campaign ROAS ONLY.
///
/// Role split (do not blur it):
///   PostHog      -> product analytics (funnels, retention, DAU).
///   Go backend   -> exact revenue ledger (provider_events).
///   AppsFlyer    -> which ad campaign drove the install, and did that
///                   install convert. Nothing else.
///
/// The client fires only OCCURRENCE events (registration / funded /
/// purchase happened) with NO amounts — the on-device no-precise-amount
/// rule from the 2026-05 telemetry audit applies here exactly as it
/// does to PostHog. Exact `af_purchase` revenue is posted server-side
/// (S2S) from the backend's provider_events, keyed to this install via
/// [appsflyerId], which `AffiliateService.authWallet` hands to the
/// backend. So: client = counts + SKAdNetwork signal, backend = money.
///
/// Identity: customerUserId is set to the SAME device UUID PostHog uses
/// as distinct_id (TrackingService.deviceId), BEFORE the SDK starts, so
/// every AppsFlyer raw-data row joins 1:1 to a PostHog person.
class AppsFlyerService {
  AppsFlyerService._();

  static AppsFlyerSdk? _sdk;
  static Future<void>? _initialization;
  static bool _sessionReadyPending = false;

  static bool get _canTrack =>
      !kDebugMode && !TrackingService.isDisabled && TrackingService.isOptedIn;
  static String? _appsflyerId;
  static String? _affiliateCode;

  /// Referrer code captured from a deferred-deeplink install (set by the
  /// onInstallConversionData callback on first launch). Consumed by
  /// AffiliateService.authWallet and bound as the wallet's referrer. Stored
  /// here (not pushed into AffiliateService) to avoid an import cycle.
  static String? _capturedReferrer;

  /// Sink for a captured referrer, wired in main.dart to
  /// AffiliateService.setPendingReferrer. The conversion-data callback fires
  /// asynchronously (an AppsFlyer network round-trip) and can land AFTER the
  /// first authWallet has already minted the affiliate row — so the in-memory
  /// [_capturedReferrer] alone races and is lost (it's never repopulated on a
  /// 2nd launch, when is_first_launch is false). Persisting the code durably
  /// here lets every later authWallet — this session's retries AND future
  /// boots within the backend's 7-day late-bind grace window — pick it up.
  /// A callback (not a direct import) keeps AffiliateService out of this file.
  static Future<void> Function(String code)? onReferrerCaptured;

  /// Sink for the install attribution captured on first launch, wired in
  /// main.dart to `AffiliateService.queueInstallAttribution`, which sends it
  /// once to the backend when a wallet session exists. A callback for the
  /// same import-cycle reason as [onReferrerCaptured].
  static Future<void> Function(Map<String, String> attribution)?
      onInstallAttributionCaptured;

  /// AppsFlyer's own install id — the join key the backend needs to
  /// post S2S revenue events for this device. Available after [init].
  static String? get appsflyerId => _appsflyerId;

  static String get platform => Platform.isIOS ? 'ios' : 'android';

  /// Tag every AppsFlyer event with the affiliate_code so its rows are
  /// filterable by the SAME id used in PostHog (person property) and the
  /// backend (provider_events key) — i.e. you can check everything from the
  /// affiliate id. Privacy-safe: affiliate_code is a random code, NOT the
  /// wallet pubkey (kept out of third-party analytics per the 2026-05
  /// telemetry audit). Idempotent; safe to call every boot.
  static void setAffiliateCode(String affiliateCode) {
    if (affiliateCode.isEmpty) return;
    _affiliateCode = affiliateCode;
    // setAdditionalData forwards it to integrated partners; the per-event
    // `af_affiliate_code` param (added in [_log]) is what makes it show up
    // and filter in AppsFlyer raw-data reports.
    try {
      _sdk?.setAdditionalData({'affiliate_code': affiliateCode});
    } catch (_) {/* best-effort */}
  }

  /// Boot-time init. Call AFTER TrackingService.initialize() (the
  /// device UUID must exist so it can be set as customerUserId before
  /// the SDK's first launch event).
  ///
  /// Debug builds never init — `flutter run` sessions must not create
  /// installs / pollute attribution. Opted-out users (the same
  /// `analytics_opt_in` flag that gates PostHog) never init either, so
  /// no AppsFlyer traffic leaves the device at all (GDPR-clean).
  static Future<void> init() async {
    if (!_canTrack) return;
    final pending = _initialization;
    if (pending != null) return pending;
    if (_sdk != null) return;
    final initialization = _initialize();
    _initialization = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_initialization, initialization)) _initialization = null;
    }
  }

  static Future<void> _initialize() async {
    try {
      // SDK dev key, from .env. AppsFlyer accounts share one dev key
      // across apps BY DEFAULT, but the "unique Dev key per app"
      // account setting gives newly added apps their own — so allow a
      // per-platform override and fall back to the shared key. The key
      // authenticates SDK traffic only; the backend's S2S API uses a
      // separate token from the AppsFlyer Security Center
      // (APPSFLYER_S2S_TOKEN on the server).
      final devKey = (Platform.isIOS
              ? dotenv.env['APPSFLYER_DEV_KEY_IOS']
              : dotenv.env['APPSFLYER_DEV_KEY_ANDROID']) ??
          dotenv.env['APPSFLYER_DEV_KEY'] ??
          '';
      if (devKey.isEmpty) return;
      // iOS needs the numeric App Store id; Android keys off the
      // package name. APP_STORE_ID may carry an "id" prefix — strip it.
      final appStoreId =
          (dotenv.env['APP_STORE_ID'] ?? '').replaceFirst(RegExp(r'^id'), '');
      // v7 flow: the SDK is a process singleton, init() does NOT send the
      // session (start() does) — the old manualStart semantics are the
      // default now, which is what keeps the PostHog join lossless
      // (customerUserId attaches before the first launch event).
      final sdk = AppsFlyerSdk.instance;
      // Android decides whether to resolve deferred links during init.
      // The UDL listener must exist first; other listeners follow init.
      await sdk.registerDeepLinkListener(onDeepLinking: (result) {
        if (_canTrack) _onDeepLink(result);
      });
      if (!_canTrack) return;
      await sdk.init(devKey: devKey, appId: appStoreId);
      await sdk.registerConversionListener(
        onConversionDataSuccess: (result) {
          if (_canTrack) _onConversionData(result);
        },
      );
      final deviceId = TrackingService.deviceId;
      if (deviceId != null && deviceId.isNotEmpty) {
        // Attached BEFORE start() so customerUserId rides the install
        // event. The app does not request ATT authorization.
        await sdk.setCustomerUserId(deviceId);
      }
      // V7 requires a start for each ready foreground session. All callbacks
      // re-check consent, including one delivered while Settings opts out.
      await sdk.registerSessionReadyListener(() {
        _sessionReadyPending = true;
        unawaited(_startReadySession(sdk));
      });
      _sdk = sdk;
      // A native callback may arrive before listener registration returns.
      await _startReadySession(sdk);
      if (!_canTrack) {
        await sdk.stop(true);
        return;
      }
      _appsflyerId = await sdk.getAppsFlyerUID();
      // Uninstall measurement: hand over the push token when notification
      // permission is already granted. Fire-and-forget, never prompts.
      unawaited(AppsFlyerUninstallToken.register());
    } catch (_) {/* attribution is best-effort — never block boot */}
  }

  /// Mirror of the Settings → Privacy analytics toggle. Off stops all
  /// SDK traffic (AppsFlyer `stop`); on resumes, or runs the full init
  /// when the app booted opted-out (so [_sdk] was never created).
  static Future<void> setEnabled(bool enabled) async {
    try {
      // Finish any initialization before applying stop, so a late init cannot
      // undo the user's opt-out. Native requests already sent cannot be recalled.
      await _initialization;
      if (enabled && _sdk == null) {
        await init();
        return;
      }
      final sdk = _sdk;
      if (sdk == null) return;
      await sdk.stop(!enabled || !_canTrack);
      if (enabled && _canTrack) {
        // A readiness callback received while opted out can resume only if
        // the native SDK still identifies this foreground cycle as ready.
        if (await sdk.isSessionReady()) await _startReadySession(sdk);
      }
    } catch (_) {/* attribution must not block a privacy setting */}
  }

  static Future<void> _startReadySession(AppsFlyerSdk sdk) async {
    if (!_sessionReadyPending || !_canTrack || !identical(_sdk, sdk)) return;
    // Consume before awaiting: a concurrent privacy resume cannot send this
    // same readiness notification a second time.
    _sessionReadyPending = false;
    try {
      await sdk.start();
    } catch (_) {/* retry only when the SDK next reports session readiness */}
  }

  /// Handle the AppsFlyer install conversion data. On a FIRST launch from a
  /// referral OneLink, pull the referrer code out of the custom params and
  /// stash it for authWallet to bind. Defensive parsing — any shape mismatch
  /// just means no auto-bind (the manual late-entry card remains a fallback).
  static void _onConversionData(dynamic res) {
    try {
      Map data;
      if (res is Map && res['payload'] is Map) {
        // The REAL appsflyer_sdk envelope: the plugin json-decodes the native
        // conversion data and rewraps it as {'status': 'success'|'failure',
        // 'payload': <map>} (6.18.0 lib/src/callbacks.dart). is_first_launch /
        // deep_link_value / af_sub1 sit at the top level of 'payload'. Reading
        // 'data' here (the old bug) made the first-launch gate always fail and
        // silently dropped every deferred referral.
        if (res['status'] != null && res['status'] != 'success') return;
        data = res['payload'] as Map;
      } else if (res is Map && res['data'] is Map) {
        data = res['data'] as Map;
      } else if (res is Map) {
        data = res;
      } else {
        return;
      }
      final firstLaunch = data['is_first_launch'];
      final isFirst = firstLaunch == true || firstLaunch == 'true';
      if (!isFirst) return;
      // Install campaign: only utm_* values, as person properties.
      TrackingService.captureUtmParams(data);
      _captureInstallAttribution(data);
      // Website visitor id (af_sub2, also folded into the Play install
      // referrer): an identity link only, never a referral code.
      _linkWebVisitor(webVisitorIdFrom(data));
      final raw =
          (data['deep_link_value'] ?? data['af_sub1'] ?? data['referral_code'])
              ?.toString();
      _captureReferrerCode(raw);
    } catch (_) {/* no auto-bind on parse failure */}
  }

  /// The AppsFlyer conversion keys each install-attribution field is read
  /// from, first present key wins. These are the names AppsFlyer documents
  /// for the conversion data (the plugin passes the native map through
  /// unchanged); Meta reports the ad set and ad as `adset` / `adgroup`.
  /// Ids (`campaign_id`, `adset_id`, `ad_id`, `af_siteid`) are never read.
  static const Map<String, List<String>> _attributionSources = {
    'af_media_source': ['media_source'],
    'af_campaign': ['campaign'],
    'af_adset': ['af_adset', 'adset'],
    'af_ad': ['af_ad', 'adgroup'],
    'af_channel': ['af_channel'],
    'af_status': ['af_status'],
  };

  /// The install attribution in a conversion payload: the campaign names
  /// of [TrackingService.installAttributionKeys] plus `af_install_at`
  /// (AppsFlyer's `install_time`, UTC, as ISO 8601). Values are trimmed and
  /// capped at 100 characters; empty and `null` values are dropped.
  @visibleForTesting
  static Map<String, String> installAttributionFrom(Map<dynamic, dynamic> data) {
    String? read(String key) {
      final raw = data[key];
      if (raw is! String && raw is! num) return null;
      var value = raw.toString().trim();
      if (value.isEmpty || value.toLowerCase() == 'null') return null;
      if (value.length > 100) value = value.substring(0, 100);
      return value;
    }

    final out = <String, String>{};
    _attributionSources.forEach((field, keys) {
      for (final key in keys) {
        final value = read(key);
        if (value != null) {
          out[field] = value;
          break;
        }
      }
    });
    final installAt = _installTimeIso(read('install_time'));
    if (installAt != null) out['af_install_at'] = installAt;
    return out;
  }

  /// AppsFlyer's `install_time` ("2026-10-01 12:34:56.789", UTC) as ISO
  /// 8601 UTC, or null when it does not parse.
  static String? _installTimeIso(String? raw) {
    if (raw == null) return null;
    var text = raw.replaceFirst(' ', 'T');
    if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text)) text = '${text}Z';
    return DateTime.tryParse(text)?.toUtc().toIso8601String();
  }

  /// First launch: the campaign names become `$set_once` person
  /// properties, and the whole attribution goes to the backend once (see
  /// [onInstallAttributionCaptured]). Never blocks; never throws.
  static void _captureInstallAttribution(Map<dynamic, dynamic> data) {
    final attribution = installAttributionFrom(data);
    if (attribution.isEmpty) return;
    TrackingService.setInstallAttributionOnce(attribution);
    final sink = onInstallAttributionCaptured;
    if (sink == null) return;
    try {
      unawaited(sink(attribution).catchError((Object _) {}));
    } catch (_) {/* best-effort */}
  }

  /// The website's PostHog distinct id carried by an attribution payload:
  /// `af_sub2` directly, or `af_sub2=<id>` inside a raw Play install
  /// referrer string when the SDK did not split it. Never `af_sub1` /
  /// `deep_link_value`, which are referral codes.
  @visibleForTesting
  static String? webVisitorIdFrom(Map<dynamic, dynamic> data) {
    final direct = data['af_sub2'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    for (final key in const ['install_referrer', 'referrer']) {
      final referrer = data[key];
      if (referrer is! String || referrer.isEmpty) continue;
      final fromReferrer = _webVisitorIdFromReferrer(referrer);
      if (fromReferrer != null) return fromReferrer;
    }
    return null;
  }

  static String? _webVisitorIdFromReferrer(String referrer) {
    try {
      // The referrer is a query string; Play may deliver it URL-encoded.
      final query = referrer.contains('%') ? Uri.decodeFull(referrer) : referrer;
      final id = Uri.splitQueryString(query)['af_sub2'];
      return id == null || id.trim().isEmpty ? null : id.trim();
    } catch (_) {
      return null;
    }
  }

  /// Hand a website visitor id to the identity link. Fire-and-forget: the
  /// alias is once per install, capped at 2 s and skipped when opted out.
  static void _linkWebVisitor(String? webId) {
    if (webId == null || !TrackingService.looksLikeWebVisitorId(webId)) return;
    unawaited(TrackingService.aliasWebVisitor(webId).catchError((Object _) {}));
  }

  /// Unified Deep Linking (UDL): fires for BOTH deferred-deeplink installs AND
  /// DIRECT deep links (a tapped invite link on an ALREADY-INSTALLED app) — the
  /// case the first-launch-only onInstallConversionData path misses. This is
  /// what lets an existing user who taps a friend's link still get attributed.
  static void _onDeepLink(DeepLinkResult res) {
    try {
      if (res.status != DeepLinkStatus.found) return;
      final dl = res.deepLink;
      if (dl == null) return;
      // Deferred or direct link campaign: only utm_* values, as person
      // properties.
      TrackingService.captureUtmParams(dl.clickEvent);
      _linkWebVisitor(webVisitorIdFrom(dl.clickEvent));
      _captureReferrerCode(
          dl.deepLinkValue ?? dl.afSub1 ?? dl.getStringValue('referral_code'));
    } catch (_) {/* no auto-bind on parse failure */}
  }

  /// Capture a referral code from an APP-SIDE deep link the router received
  /// (kute://open?deep_link_value=...). Works even without the AppsFlyer SDK
  /// (so it fires in debug builds too), complementing the SDK's UDL /
  /// conversion callbacks. Validates + persists the code for authWallet to sync;
  /// does NOT navigate.
  static void ingestReferrerFromDeepLink(String? code) =>
      _captureReferrerCode(code);

  /// Link the website visitor id an APP-SIDE link carried as `af_sub2`
  /// (a OneLink opened straight into an installed app). Identity only:
  /// the value is never treated as a referral code.
  static void ingestWebVisitorFromDeepLink(String? webId) =>
      _linkWebVisitor(webId);

  /// Test seam: run the real UDL handler against a [DeepLinkResult] so the
  /// referrer-capture path (identical for direct + deferred deep links) can be
  /// unit-tested without a live SDK. Not for production use.
  @visibleForTesting
  static void handleDeepLinkForTest(DeepLinkResult res) => _onDeepLink(res);

  /// Test seam: run the real conversion-data handler against a raw envelope
  /// exactly as the plugin delivers it ({'status', 'payload'}), so the
  /// deferred-install capture path can be unit-tested without a live SDK.
  @visibleForTesting
  static void handleConversionDataForTest(dynamic res) =>
      _onConversionData(res);

  /// Validate + capture a referral code from a deep-link payload (deferred
  /// conversion data OR a UDL direct link): stash it in memory and persist it
  /// durably (so a late callback still binds on a later authWallet, in this
  /// session or a future boot), then fire the auto-bound analytics event.
  /// Best-effort; never throws into the SDK callback.
  static void _captureReferrerCode(String? raw) {
    if (raw == null) return;
    final code = raw.trim().toUpperCase();
    if (code.length < 3 ||
        code.length > 32 ||
        !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
      return;
    }
    _capturedReferrer = code;
    try {
      onReferrerCaptured?.call(code);
    } catch (_) {/* persistence is best-effort */}
    TrackingService.affiliateReferrerAutoBound();
  }

  /// Non-consuming peek at the referrer captured from a deferred-deeplink
  /// install. Onboarding's ReferrerCodeScreen reads this to pre-fill its
  /// "<CODE> recommended you" confirmation, and [AffiliateService.authWallet]
  /// reads it to auto-bind the referrer. Peeking must NOT clear it — only an
  /// explicit [clearCapturedReferrer] drops it.
  static String? get capturedReferrer => _capturedReferrer;

  /// Clear the IN-MEMORY captured referrer. Called once the referrer is durably
  /// bound on the backend, or when the user rejects the code pre-filled on the
  /// onboarding confirmation screen. authWallet peeks (not consumes)
  /// [capturedReferrer], so this is the only thing that drops the in-memory
  /// copy. NOTE: the durable copy lives in AffiliateService's pending-referrer
  /// storage and must be cleared separately via
  /// [AffiliateService.clearPendingReferrer].
  static void clearCapturedReferrer() {
    _capturedReferrer = null;
  }

  static void _log(String name, [Map<String, Object?>? values]) {
    try {
      // Stamp the affiliate_code on every event so AppsFlyer is filterable
      // by the same id as PostHog + the backend.
      final params = <String, Object?>{
        if (_affiliateCode != null && _affiliateCode!.isNotEmpty)
          'af_affiliate_code': _affiliateCode,
        ...?values,
      };
      _sdk?.logEvent(name, eventValues: params);
    } catch (_) {/* never crash on tracking */}
  }

  // ─── Conversion events (the complete set — add nothing casually) ──
  //
  // Each is claimed via OnceFlagsService only when the SDK is live, so
  // a debug/opted-out session can't burn a once-flag without sending.

  /// First wallet created on this device → `af_complete_registration`
  /// (standard name: Meta/Google map it to their registration events).
  static void completeRegistration({String? method}) {
    if (_sdk == null) return;
    if (!OnceFlagsService.claimOnce('af_complete_registration')) return;
    _log('af_complete_registration', {
      if (method != null) 'af_registration_method': method,
    });
  }

  /// First incoming transaction → the activation signal. Fires early
  /// enough to land inside the SKAdNetwork measurement window, where
  /// revenue usually doesn't.
  static void walletFunded() {
    if (_sdk == null) return;
    if (!OnceFlagsService.claimOnce('af_wallet_funded')) return;
    _log('wallet_funded');
  }

  /// A revenue-relevant order COMPLETED (never initiated/pending):
  /// swaps (orchestra), Polymarket bet placed
  /// or position sold.
  ///
  /// Deliberately NOT named `af_purchase`: the backend posts that via
  /// S2S with exact `af_revenue`, and a same-named client event would
  /// double-count purchases in AppsFlyer.
  static void purchaseCompleted({required String provider}) {
    if (_sdk == null) return;
    _log('purchase_completed', {'af_content_type': provider});
    if (OnceFlagsService.claimOnce('af_first_purchase')) {
      _log('first_purchase', {'af_content_type': provider});
    }
  }

  // ─── Affiliate share links (OneLink) ─────────────────────────────

  /// Build the affiliate's OneLink URL LOCALLY (no network) so the Earn
  /// screen can render its QR INSTANTLY. Carries the code as the deep-link
  /// value + af_sub1 so a deferred-deeplink install can auto-bind the
  /// referrer. Returns null when no OneLink template is configured (we do
  /// NOT fall back to a website link); the Earn screen then hides the QR/
  /// share until a branded link resolves.
  static String? shareLink(String code) {
    final tpl = (dotenv.env['APPSFLYER_ONELINK_TEMPLATE'] ?? '').trim();
    if (tpl.isEmpty || code.isEmpty) return null;
    final c = Uri.encodeComponent(code);
    final base = tpl.startsWith('http') ? tpl : 'https://$tpl';
    return '$base?pid=affiliate&c=$c&deep_link_value=$c&af_sub1=$c';
  }

  /// Ask AppsFlyer to mint a BRANDED short OneLink (nicer to share than the
  /// long [shareLink]). Async + best-effort: returns null on any failure or
  /// after a short timeout, so callers render [shareLink] instantly and swap
  /// to this when/if it resolves. Never throws.
  static Future<String?> brandedInviteLink(String code) async {
    final sdk = _sdk;
    if (sdk == null) return null;
    try {
      // v7: generateInviteLink returns the URL directly (no callbacks;
      // customParams renamed userParams).
      final url = await sdk
          .generateInviteLink(
            parameters: AppsFlyerInviteLinkParams(
              channel: 'affiliate',
              campaign: code,
              userParams: {
                'referral_code': code,
                'deep_link_value': code,
                'af_sub1': code,
              },
            ),
          )
          .timeout(const Duration(seconds: 6));
      // Accept ONLY a real OneLink. When the OneLink template can't be
      // resolved the SDK falls back to a broken
      // `app.appsflyer.com/id<AppStoreID>` URL that 404s with "Application
      // ID not found" — it passes a naive startsWith('http') check but must
      // never reach the UI. Rejecting it returns null so callers fall back
      // to the locally-built [shareLink] when an APPSFLYER_ONELINK_TEMPLATE
      // is configured (otherwise the UI shows a code-only share with no QR).
      return _isOneLink(url) ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// True only for a real OneLink — host is `onelink.me` or a subdomain of it
  /// (e.g. `kute.onelink.me`). Guards against the AppsFlyer SDK's broken
  /// fallback: when the OneLink template isn't resolvable, generateInviteLink
  /// returns an `app.appsflyer.com/id<AppStoreID>` URL (the dashboard host)
  /// that 404s with "Application ID not found". That URL passes a naive
  /// `startsWith('http')` test, so we validate the parsed host instead and let
  /// rejected links fall back to the local [shareLink]. Match on the domain
  /// hierarchy, not a substring, so look-alikes like `notonelink.me` or
  /// `onelink.me.evil.com` are rejected too.
  static bool _isOneLink(String? url) {
    if (url == null || url.isEmpty) return false;
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    return host == 'onelink.me' || host.endsWith('.onelink.me');
  }
}
