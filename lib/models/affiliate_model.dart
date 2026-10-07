import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/revenue/provider_event_outbox.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

/// AffiliateService — wallet-native affiliate program client.
///
/// On first launch (after WalletIdentityService.initialize):
///   1. Call [authWallet] with the wallet's paykute address. Backend mints
///      or fetches the affiliate row keyed on wallet_pubkey, returns the
///      affiliate_code + tier + revshare_pct + signup_bonus_sats + session
///      token. We persist the session token and affiliate_code locally.
///
/// Provider orders are attributed server-side via [logProviderEvent]
/// (session-token authed → `provider_events.affiliate_code`); no per-order
/// signed headers are sent.
///
/// Late-entry referrer flow:
///   - Within 7 days of wallet creation, the user can enter a friend's
///     code via [setReferrerByCode] from the Earn tab banner.
///
/// Earnings:
///   - [getMe] returns the full dashboard payload.
///   - [claim] triggers the user-initiated payout to the paykute address.
class AffiliateService {
  AffiliateService._();

  static String get _baseUrl => '${dotenv.env['BACKEND']!}/api/v1/affiliate';

  static const _storage = secureStorage;
  static const _sessionKey = 'kute_affiliate_session';
  static const _codeKey = 'kute_affiliate_code';
  static const _pendingReferrerKey = 'kute_pending_referrer';
  static const _sessionAddressKey = 'kute_affiliate_session_address';
  static const _attributionPendingKey = 'kute_install_attribution_pending';
  static const _attributionSentKey = 'kute_install_attribution_sent';

  static String? _sessionToken;
  static String? _affiliateCode;

  /// The referee fee discount the backend currently applies, in basis
  /// points off every positive Kute fee, as the backend last said in this
  /// app run (`/auth/wallet`, `/me`, `/program-status`, the capability
  /// policy). Null until one of those has answered: the app never assumes
  /// a discount, and copy that would quote one leaves it out instead.
  /// Fees themselves always come from the provider quote; display only.
  static int? _refereeDiscountBps;
  static int? _refereeDiscountPct;
  static double? _commissionTopRatePct;
  static Future<int?>? _programTermsInFlight;

  /// Best known referee discount (bps) this run, or null when unknown.
  static int? get refereeDiscountBps {
    final cached = _refereeDiscountBps;
    if (cached != null) return cached;
    final policy = RuntimeCapabilitiesService.instance.snapshot;
    return policy != null && policy.referral.containsKey('refereeDiscountBps')
        ? policy.refereeDiscountBps
        : null;
  }

  /// The discount as a whole percentage of the headline Kute fee, which is
  /// what every piece of referral copy quotes ("40% off Kute fees"). The
  /// backend computes it against the fee it publishes; the app never
  /// divides two figures it read at different times. Null when unknown;
  /// zero when the backend publishes no discount.
  static int? get refereeDiscountPct {
    final cached = _refereeDiscountPct;
    if (cached != null) return cached;
    final policy = RuntimeCapabilitiesService.instance.snapshot;
    return policy != null && policy.referral.containsKey('refereeDiscountPct')
        ? policy.refereeDiscountPct
        : null;
  }

  /// The highest automatic commission rate an inviter can reach, in
  /// percent, from the backend's public program terms. Null until read.
  static double? get commissionTopRatePct => _commissionTopRatePct;

  @visibleForTesting
  static set debugRefereeDiscountBps(int? bps) => _refereeDiscountBps = bps;

  @visibleForTesting
  static set debugRefereeDiscountPct(int? pct) => _refereeDiscountPct = pct;

  static void _rememberRefereeDiscount(Object? bps, Object? pct) {
    if (bps is num && bps.isFinite && bps >= 0 && bps <= 10000) {
      _refereeDiscountBps = bps.toInt();
    }
    if (pct is num && pct.isFinite && pct >= 0 && pct <= 100) {
      _refereeDiscountPct = pct.toInt();
    }
  }

  /// Public program terms (no session needed), for onboarding copy before
  /// the wallet has a session: the referee discount share and the top
  /// commission rate. Resolves to the discount share known this run (null
  /// when the backend has not said), so copy never blocks on the network.
  static Future<int?> programRefereeDiscountPct() {
    final cached = _refereeDiscountPct;
    if (cached != null && _commissionTopRatePct != null) {
      return Future.value(cached);
    }
    return _programTermsInFlight ??= () async {
      try {
        final r = await http
            .get(Uri.parse('$_baseUrl/program-status'))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) {
          final body = jsonDecode(r.body);
          if (body is Map) {
            _rememberRefereeDiscount(
                body['refereeDiscountBps'], body['refereeDiscountPct']);
            _rememberCommissionTopRate(body['commissionTopRatePct']);
          }
        }
      } catch (_) {
        // Best-effort: copy that needs these figures leaves them out.
      } finally {
        _programTermsInFlight = null;
      }
      return refereeDiscountPct;
    }();
  }

  static void _rememberCommissionTopRate(Object? pct) {
    if (pct is num && pct.isFinite && pct > 0 && pct <= 100) {
      _commissionTopRatePct = pct.toDouble();
    }
  }

  @visibleForTesting
  static set debugCommissionTopRatePct(double? pct) =>
      _commissionTopRatePct = pct;

  /// Cached affiliate code (the user's own). Available after [authWallet].
  static String? get affiliateCode => _affiliateCode;


  /// Cached session token. Available after [authWallet].
  static String? get sessionToken => _sessionToken;

  @visibleForTesting
  static set debugSessionToken(String? token) => _sessionToken = token;

  /// The app container, kept from [startBackgroundRegistration] so a
  /// protected call can prime the hot wallet identity, read the @paykute
  /// address and localize its error without a BuildContext.
  static ProviderContainer? _container;

  /// The in-flight session mint shared by concurrent protected calls.
  static Future<String?>? _sessionMint;

  /// Returns the wallet-session bearer, minting one with the hot wallet
  /// identity (the Spark wallet key, also for flows paying a cold or
  /// watch-only destination) when none is cached. [rejected] is a token
  /// the backend just answered 401 for; it is replaced, never returned.
  /// Null when there is no hot wallet identity or @paykute address to sign
  /// with, or the backend refused the signature.
  static Future<String?> ensureSession({String? rejected}) {
    final current = _sessionToken;
    if (current != null && current.isNotEmpty && current != rejected) {
      return Future.value(current);
    }
    return _sessionMint ??=
        _mintSession().whenComplete(() => _sessionMint = null);
  }

  /// Called before a Ledger operation scope starts (Phase 5 plan B12).
  /// Minting a session signs with the hot wallet identity, which
  /// `LedgerOperationScope` refuses, so a missing session, or one whose
  /// readable expiry falls within [minRemaining], is minted here, outside
  /// the scope. A token the backend revokes can still answer 401 inside the
  /// scope; that re-auth is refused and the call fails with
  /// [WalletSessionUnavailable] without signing anything.
  static Future<void> prepareSessionForLedgerOperation({
    Duration minRemaining = const Duration(minutes: 30),
  }) async {
    final token = _sessionToken;
    if (token == null || token.isEmpty) {
      await ensureSession();
      return;
    }
    final expiry = sessionTokenExpiry(token);
    if (expiry == null || expiry.isAfter(DateTime.now().add(minRemaining))) {
      return;
    }
    await ensureSession(rejected: token);
  }

  /// Expiry of our backend's base64url pipe-delimited token. Also accepts
  /// JSON payloads for compatibility with earlier callers/tests. This is
  /// scheduling only; the backend always verifies the token signature.
  @visibleForTesting
  static DateTime? sessionTokenExpiry(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final candidates =
        parts.length == 3 ? [parts[1], parts[0]] : [parts[0], parts[1]];
    for (final part in candidates) {
      try {
        final payload = utf8.decode(base64Url.decode(base64Url.normalize(part)));
        final fields = payload.split('|');
        if (fields.length == 3 || fields.length == 4 || fields.length == 5) {
          final seconds = int.tryParse(fields[2]);
          if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        }
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final exp = decoded['exp'] ?? decoded['expires_at'];
        if (exp is num) {
          final ms = exp > 1e12 ? exp.toInt() : (exp * 1000).toInt();
          return DateTime.fromMillisecondsSinceEpoch(ms);
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _mintSession() async {
    try {
      final container = _container;
      if (!WalletIdentityService.isReady && container != null) {
        final sdk = (await container
                .read(breezSDKProvider.future)
                .timeout(const Duration(seconds: 20)))
            .instance;
        if (sdk != null) await WalletIdentityService.initFromBreez(sdk);
      }
      if (!WalletIdentityService.isReady) return null;
      final address = await _sessionAddress();
      if (address == null) return null;
      if (await authWallet(paykuteAddress: address) == null) return null;
      final token = _sessionToken;
      return token != null && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  /// The @paykute address to sign a session with: the live provider value,
  /// else the address of the last successful [authWallet] for this same
  /// identity, else a freshly provisioned one.
  static Future<String?> _sessionAddress() async {
    final container = _container;
    final live = container?.read(lnAddressProvider).valueOrNull;
    if (live != null && live.isNotEmpty) return live;
    try {
      final raw = await _storage.read(key: _sessionAddressKey);
      if (raw != null) {
        final stored = jsonDecode(raw) as Map<String, dynamic>;
        final address = stored['address'] as String?;
        if (stored['pubkey'] == WalletIdentityService.pubkey &&
            address != null &&
            address.isNotEmpty) {
          return address;
        }
      }
    } catch (_) {/* fall through */}
    if (container == null) return null;
    try {
      final lnurl = await container
          .read(setupLnAddressProvider.future)
          .timeout(const Duration(seconds: 20));
      final address = lnurl.lightningAddress;
      return address != null && address.isNotEmpty ? address : null;
    } catch (_) {
      return null;
    }
  }

  /// Localized copy for a protected call that could not get a session.
  static String sessionUnavailableMessage() {
    var language = 'en';
    try {
      language = _container?.read(settingsProvider).language ?? 'en';
    } catch (_) {/* English */}
    return l10nForLanguage(language).walletSessionUnavailable;
  }

  /// Sends one request to a wallet-session route (Orchestra, the Polymarket
  /// relay, the Hyperliquid deposit routes). [send] builds the request from
  /// the Authorization header it is given and must rebuild it identically,
  /// including any idempotency key, on every call. A 401 re-authenticates
  /// once and sends once more, which is safe even for payments because the
  /// session middleware rejects before the handler runs. Any other status or
  /// a transport error is returned or thrown as is and never retried.
  ///
  /// Throws [WalletSessionUnavailable] with localized copy, without calling
  /// the route, when no session can be obtained, and when the re-auth after
  /// a 401 fails. [route] labels the `wallet_session_auth` event.
  static Future<http.Response> sendWithSession(
    String route,
    Future<http.Response> Function(Map<String, String> auth) send,
  ) async {
    final token = await ensureSession();
    if (token == null) {
      TrackingService.walletSessionAuth(route: route, outcome: 'unavailable');
      throw WalletSessionUnavailable(sessionUnavailableMessage());
    }
    final device = await RuntimeCapabilitiesService.instance.requestContextHeaders();
    final res = await send({...device, 'Authorization': 'Bearer $token'});
    if (res.statusCode != 401) return res;
    final fresh = await ensureSession(rejected: token);
    if (fresh == null) {
      TrackingService.walletSessionAuth(route: route, outcome: 'reauth_failed');
      throw WalletSessionUnavailable(sessionUnavailableMessage());
    }
    TrackingService.walletSessionAuth(route: route, outcome: 'reauth');
    return send({...device, 'Authorization': 'Bearer $fresh'});
  }

  /// Restore cached session from secure storage. Call on app boot before
  /// [authWallet] so subsequent calls reuse the existing token.
  static Future<void> restore() async {
    try {
      _sessionToken = await _storage.read(key: _sessionKey);
      _affiliateCode = await _storage.read(key: _codeKey);
    } catch (_) {
      // Non-fatal
    }
  }

  /// True while a background registration loop is in flight, so we
  /// don't start two of them on rapid wallet swaps / app resumes.
  static bool _backgroundRegistrationActive = false;

  /// Kick off affiliate registration in the background with retries.
  /// Called from [BackgroundSyncService.start] after the wallet boots
  /// so the user doesn't have to open the Earn screen to get an
  /// affiliate row minted on first launch (the previous behaviour was
  /// lazy-on-tap, which left a wallet unattributable to its referrer
  /// until the user discovered the screen). On wallet recovery the
  /// pubkey is deterministic from the seed, so the backend finds the
  /// existing row by `wallet_pubkey` and the user gets their
  /// original affiliate code back instead of a fresh one.
  ///
  /// Self-terminates once a session token is minted. On failure
  /// (SDK not ready, paykute address not yet provisioned, network
  /// hiccup, backend down), backs off and retries up to ~3 hours of
  /// wall-clock — covers the typical SDK warm-up + LN-address mint
  /// window without burning the radio if the device is offline.
  static void startBackgroundRegistration(ProviderContainer container) {
    _container = container;
    _revenueFlushTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(flushProviderEvents());
    });
    unawaited(flushProviderEvents());
    unawaited(flushInstallAttribution());
    if (_backgroundRegistrationActive) return;
    // Already minted on a prior launch. We DON'T re-run the registration
    // loop, but several things that used to happen ONLY inside the first
    // authWallet must still run on EVERY boot — otherwise they silently
    // stay off for the whole session:
    //   - WalletIdentityService is unprimed (its initFromBreez only ran
    //     inside the registration loop), so `isReady` is false →
    //     authWallet/buildAuthChallenge can't sign and syncPayoutAddress
    //     can't run;
    //   - the live PostHog session isn't linked to the affiliate_code;
    //   - an in-session @paykute edit that couldn't reach the backend
    //     (identity wasn't ready) leaves payout_address stale.
    // _refreshRegisteredSession re-establishes all three.
    if (_sessionToken != null &&
        _sessionToken!.isNotEmpty &&
        _affiliateCode != null &&
        _affiliateCode!.isNotEmpty) {
      unawaited(_refreshRegisteredSession(container));
      return;
    }
    _backgroundRegistrationActive = true;
    unawaited(_runBackgroundRegistration(container));
  }

  /// Per-boot refresh for an already-registered wallet. Primes wallet
  /// identity, re-links the PostHog session to the affiliate code, and
  /// re-syncs the backend payout_address against the current @paykute
  /// address. Best-effort: the Earn screen and the next boot retry.
  static Future<void> _refreshRegisteredSession(
      ProviderContainer container) async {
    // 1. Re-link PostHog FIRST — it only needs the restored affiliate_code
    //    (no SDK, no identity), so it must not be gated behind identity
    //    priming. Re-asserts the device-UUID→affiliate_code person property
    //    + one-time alias so backend revenue events merge into this person.
    final code = _affiliateCode;
    if (code != null && code.isNotEmpty) {
      try {
        await TrackingService.identifyWithAffiliate(code);
      } catch (_) {/* best-effort */}
    }

    // 2. Prime wallet identity — required for the authWallet payout re-sync
    //    below (it signs the auth challenge). initFromBreez awaits the SDK
    //    and retries getInfo internally, so one call is enough.
    try {
      if (!WalletIdentityService.isReady) {
        final sdkWrapper = await container.read(breezSDKProvider.future);
        final sdk = sdkWrapper.instance;
        if (sdk == null) return;
        await WalletIdentityService.initFromBreez(sdk);
      }
    } catch (_) {
      // Identity couldn't be primed this pass — the payout re-sync below
      // needs it, so stop here. Next boot / Earn-screen open retries.
      return;
    }

    // 3. Re-auth with the current @paykute address: refreshes the session
    //    token, re-applies affiliate person properties, and upserts
    //    payout_address so a stale address self-heals.
    try {
      final addr = container.read(lnAddressProvider).valueOrNull;
      if (addr != null && addr.isNotEmpty) {
        await authWallet(paykuteAddress: addr);
      }
    } catch (_) {/* best-effort */}
  }

  static Future<void> _runBackgroundRegistration(
      ProviderContainer container) async {
    // Constant 5s retry cadence so registration lands as soon as the paykute
    // address is provisioned (usually within the first minute of a fresh
    // wallet) instead of stalling on an exponential backoff. The loop bails
    // the instant it succeeds; the attempt cap is just a safety net so a
    // permanently-misconfigured backend doesn't poll forever.
    const retryDelay = Duration(seconds: 5);
    const maxAttempts = 120; // ~10 minutes of 5s retries

    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        // Bail if a foreground caller (e.g. the Earn screen) already
        // got the registration through.
        if (_sessionToken != null && _affiliateCode != null) {
          if (kDebugMode) debugPrint('[affiliate.bg] registration completed externally');
          return;
        }
        try {
          final sdkWrapper = await container.read(breezSDKProvider.future);
          final sdk = sdkWrapper.instance;
          if (sdk == null) {
            throw StateError('Breez SDK instance null');
          }
          await WalletIdentityService.initFromBreez(sdk);
          if (!WalletIdentityService.isReady) {
            throw StateError('WalletIdentityService not ready');
          }
          var addr = container.read(lnAddressProvider).valueOrNull;
          if (addr == null || addr.isEmpty) {
            // The @paykute (LN) address registers lazily (Receive screen).
            // Provision it here so the affiliate row mints on init instead of
            // only after the user opens Receive. Idempotent server-side.
            try {
              final lnurl =
                  await container.read(setupLnAddressProvider.future);
              addr = lnurl.lightningAddress ??
                  container.read(lnAddressProvider).valueOrNull;
            } catch (_) {/* retried on the next loop iteration */}
          }
          if (addr == null || addr.isEmpty) {
            throw StateError('paykute address not provisioned yet');
          }
          final resp = await authWallet(paykuteAddress: addr);
          if (resp == null) throw StateError('authWallet returned null');
          if (kDebugMode) debugPrint('[affiliate.bg] OK on attempt $attempt');
          TrackingService.affiliateBackgroundRegistrationAttempt(
            attemptNumber: attempt,
            success: true,
          );
          return;
        } catch (e) {
          if (kDebugMode) debugPrint('[affiliate.bg] attempt $attempt failed: $e — '
              'retrying in ${retryDelay.inSeconds}s');
          TrackingService.affiliateBackgroundRegistrationAttempt(
            attemptNumber: attempt,
            success: false,
          );
          await Future.delayed(retryDelay);
        }
      }
      if (kDebugMode) debugPrint('[affiliate.bg] giving up after $maxAttempts attempts');
    } finally {
      _backgroundRegistrationActive = false;
    }
  }

  /// Record a referrer code captured during onboarding (the manual entry
  /// screen) or from an AppsFlyer deferred-deeplink install (wired via
  /// [AppsFlyerService.onReferrerCaptured] in main.dart). Persisted durably so
  /// every [authWallet] re-sends it via [_peekPendingReferrer] until the
  /// backend confirms the bind, then it's dropped by [_clearPendingReferrer].
  static Future<void> setPendingReferrer(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return;
    try {
      await _storage.write(key: _pendingReferrerKey, value: trimmed);
    } catch (_) {/* non-fatal */}
  }

  /// CodeCheck is the response shape of [checkCode].
  ///
  ///   exists=true  → code is bound to an active affiliate. tier and
  ///                  tierLevel populated so the UI can render a small
  ///                  "Silver partner invite" confirmation.
  ///   exists=false → code not found OR account paused. UI should
  ///                  reject the entry and let the user try again.
  ///   exists=null  → request failed (network down, server error).
  ///                  UI should treat as inconclusive: ask the user to
  ///                  retry instead of silently accepting/rejecting.
  // ignore: lines_longer_than_80_chars
  /// Returns new participation is allowed by the published runtime policy.
  /// Existing earned balances and payout requests keep their own backend rules.
  static Future<bool> isProgramLive() async {
    final policy = RuntimeCapabilitiesService.instance;
    await policy.refresh();
    return policy.allows('affiliate.program');
  }

  static Future<({bool? exists, String? tier, String? tierLevel})> checkCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return (exists: false, tier: null, tierLevel: null);
    }
    try {
      final r = await http
          .get(Uri.parse('$_baseUrl/code/${Uri.encodeComponent(trimmed)}/check'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 404) {
        return (exists: false, tier: null, tierLevel: null);
      }
      if (r.statusCode != 200) {
        return (exists: null, tier: null, tierLevel: null);
      }
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final exists = body['exists'] == true;
      return (
        exists: exists,
        tier: body['tier'] as String?,
        tierLevel: body['tier_level'] as String?,
      );
    } catch (_) {
      return (exists: null, tier: null, tierLevel: null);
    }
  }

  /// Fetches a single-use v2 challenge and signs it bound to [fields],
  /// the exact auth body values about to be posted. Any non-200 answer,
  /// 404 and 405 included, is a failure: the app never signs a legacy
  /// challenge. Empty map means nothing was signed.
  static Future<Map<String, String>> _signedAuthChallenge(
      Map<String, String> fields) async {
    final pubkey = WalletIdentityService.pubkey;
    if (pubkey == null) return const {};
    final http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('$_baseUrl/auth/challenge'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pubkey': pubkey}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[affiliate.authWallet] challenge fetch failed: $e');
      return const {};
    }
    if (r.statusCode != 200) {
      if (kDebugMode) debugPrint('[affiliate.authWallet] challenge HTTP ${r.statusCode}');
      return const {};
    }
    String? challenge;
    try {
      challenge = (jsonDecode(r.body) as Map<String, dynamic>)['challenge']
          as String?;
    } catch (_) {}
    if (challenge == null || challenge.isEmpty) return const {};
    final signed = await WalletIdentityService.buildAuthChallengeV2(
      challenge,
      bodyDigest: WalletIdentityService.canonicalAuthBodyDigest(
        paykuteAddress: fields['paykute_address'] ?? '',
        referredByCode: fields['referred_by_code'],
        appsflyerId: fields['appsflyer_id'],
        afPlatform: fields['af_platform'],
      ),
    );
    if (signed.isNotEmpty) TrackingService.walletAuthChallenge(mode: 'v2');
    return signed;
  }

  /// Read the pending referrer code WITHOUT clearing it. authWallet sends it
  /// on every attempt and only clears (via [_clearPendingReferrer]) once the
  /// backend confirms the bind — so a failed call, or a mint that beat the
  /// AppsFlyer callback, doesn't lose the code.
  static Future<String?> _peekPendingReferrer() async {
    try {
      final v = await _storage.read(key: _pendingReferrerKey);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {/* non-fatal */}
    return null;
  }

  /// Drop the durable pending referrer once it's bound on the backend.
  static Future<void> _clearPendingReferrer() async {
    try {
      await _storage.delete(key: _pendingReferrerKey);
    } catch (_) {/* non-fatal */}
  }

  /// Explicitly forget any durable pending referrer — used when the user
  /// REJECTS the code pre-filled from an AppsFlyer deferred deep link (or it
  /// fails verification) on the onboarding confirmation screen. Clearing
  /// [AppsFlyerService.capturedReferrer] alone only drops the in-memory copy;
  /// without this the durable copy [setPendingReferrer] persisted from the
  /// AppsFlyer callback would still be re-sent by [authWallet] via
  /// [_peekPendingReferrer] and the rejected code would bind anyway.
  static Future<void> clearPendingReferrer() => _clearPendingReferrer();

  /// Authenticate the wallet against the backend. Creates the affiliate
  /// row on first call, syncs payout_address on every call.
  ///
  /// [paykuteAddress] = the wallet's `user@paykute.com` Lightning address.
  /// [referredByCode] = an optional code entered in onboarding or the
  /// 7-day late-entry banner.
  ///
  /// Identity comes from Breez (sdk.getInfo().identityPubkey, derived from
  /// the wallet's seed). On wallet recovery, same seed → same pubkey →
  /// same affiliate row.
  ///
  /// Returns the full response map on success, null on failure.
  static Future<Map<String, dynamic>?> authWallet({
    required String paykuteAddress,
    String? referredByCode,
  }) async {
    // Diagnostic logging — every silent return path now leaves a
    // breadcrumb in the device log so we can tell auth failures
    // apart from "request never fired" failures. The prior version
    // swallowed every error and returned null, which is why the
    // backend showed no access logs at all when auth was broken.
    final backend = dotenv.env['BACKEND'];
    if (backend == null || backend.isEmpty) {
      if (kDebugMode) debugPrint('[affiliate.authWallet] FAIL: BACKEND env var not set');
      return null;
    }
    if (!WalletIdentityService.isReady) {
      if (kDebugMode) debugPrint('[affiliate.authWallet] FAIL: WalletIdentityService not ready '
          '(Breez SDK has not initialized yet)');
      return null;
    }
    // Resolve the referrer to bind, in priority order:
    //   1. an explicit code passed by the caller (late-entry flow);
    //   2. the code AppsFlyer captured from a deferred-deeplink install
    //      (the user installed via a friend's OneLink) — backs up the
    //      onboarding confirmation screen in case the user never reached it;
    //   3. a legacy pending value in secure storage (older installs, and the
    //      durable copy the onboarding confirmation screen writes on accept).
    // PEEK (don't consume): the captured code is cleared only once the backend
    // confirms it bound (resp.referred_by_code, below). Clearing on read — the
    // old behaviour — burned the code if this authWallet then failed, or if it
    // minted the row before AppsFlyer's late callback delivered the referrer.
    // Leaving it in place lets later retries / future boots re-send it until it
    // sticks, within the backend's 7-day late-bind grace window.
    final referrer = (referredByCode != null && referredByCode.isNotEmpty)
        ? referredByCode
        : (AppsFlyerService.capturedReferrer ?? await _peekPendingReferrer());
    // AppsFlyer install id + platform: the backend stores them on the
    // affiliate row and uses them to post S2S af_purchase events with
    // exact revenue (provider_events) attributed to this install. Null
    // on debug builds / opted-out users — the keys are simply omitted.
    final afId = AppsFlyerService.appsflyerId;
    final fields = <String, String>{
      'paykute_address': paykuteAddress,
      if (referrer != null && referrer.isNotEmpty)
        'referred_by_code': referrer,
      if (afId != null && afId.isNotEmpty) ...{
        'appsflyer_id': afId,
        'af_platform': AppsFlyerService.platform,
      },
    };
    final challenge = await _signedAuthChallenge(fields);
    if (challenge.isEmpty) {
      if (kDebugMode) debugPrint('[affiliate.authWallet] FAIL: no signed challenge '
          '(challenge fetch, check or signature failed)');
      return null;
    }
    final body = {...challenge, ...fields};

    final url = '$_baseUrl/auth/wallet';
    if (kDebugMode) debugPrint('[affiliate.authWallet] POST $url '
        '(paykute=${paykuteAddress.length > 16 ? paykuteAddress.substring(0, 16) + "…" : paykuteAddress}, '
        'referrer=${referrer ?? "none"})');

    try {
      final r = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        if (kDebugMode) debugPrint('[affiliate.authWallet] FAIL: HTTP ${r.statusCode} '
            'body=${r.body.length > 200 ? r.body.substring(0, 200) + "…" : r.body}');
        return null;
      }
      final resp = jsonDecode(r.body) as Map<String, dynamic>;
      _sessionToken = resp['session_token'] as String?;
      unawaited(RuntimeCapabilitiesService.instance.refresh());
      _affiliateCode = resp['affiliate_code'] as String?;
      _rememberRefereeDiscount(
          resp['referee_discount_bps'], resp['referee_discount_pct']);
      unawaited(flushProviderEvents());
      if (_sessionToken != null) {
        await _storage.write(key: _sessionKey, value: _sessionToken!);
        try {
          await _storage.write(
            key: _sessionAddressKey,
            value: jsonEncode({
              'pubkey': challenge['pubkey'],
              'address': paykuteAddress,
            }),
          );
        } catch (_) {/* non-fatal */}
      }
      if (_affiliateCode != null) {
        await _storage.write(key: _codeKey, value: _affiliateCode!);
      }

      // Mirror affiliate context into PostHog as person properties so
      // every downstream event is attributable to this affiliate + their
      // referrer. distinct_id is the affiliate_code itself.
      await _setAffiliateProperties(
        affiliateCode: _affiliateCode,
        referredByCode: resp['referred_by_code'] as String?,
        tierLevel: resp['tier_level'] as String?,
      );

      // Wire the real affiliate_code into the LIVE PostHog session now that
      // it exists. distinct_id stays the stable device UUID (set at cold
      // start in main.dart, so the user is counted from first open even
      // before any code exists). identifyWithAffiliate attaches the code as
      // a person property AND aliases it onto the device identity — so the
      // backend's affiliate_code-keyed `revenue_recorded` events merge into
      // THIS same person. Without this call the link wouldn't form until the
      // next launch (when restore() reads the cached code).
      if (_affiliateCode != null && _affiliateCode!.isNotEmpty) {
        await TrackingService.identifyWithAffiliate(_affiliateCode!);
      }

      // Flush any transaction count accumulated BEFORE this session existed.
      // _bumpAffiliateActivity only reports while a session token is live, so
      // transactions made before the token minted (the token provisions lazily
      // behind the @paykute address) bumped the local counter but never
      // reached the backend. Now that we have a session, push the cumulative
      // count so those transactions finally count toward the ">10 transactions"
      // activation rule — otherwise a referee who transacted early and then
      // went quiet would show 10+ txs in-app yet stay unactivated. Idempotent
      // + monotonic server-side, so running it on every boot's re-auth is safe.
      TrackingService.flushAffiliateActivity();
      // Install attribution captured before this session existed.
      unawaited(flushInstallAttribution());

      if (kDebugMode) debugPrint('[affiliate.authWallet] OK: code=$_affiliateCode '
          'tier=${resp['tier_level']} referrer=${resp['referred_by_code']}');
      final hasReferrer = (resp['referred_by_code'] as String?)?.isNotEmpty ?? false;
      // The referrer is now durably bound on the backend row — only now is it
      // safe to drop the captured/pending sources so they can't re-apply (and
      // so a later boot doesn't keep re-sending a code that's already stuck).
      if (hasReferrer) {
        AppsFlyerService.clearCapturedReferrer();
        await _clearPendingReferrer();
      }
      TrackingService.affiliateAuthWalletCompleted(
        success: true,
        referrerBound: hasReferrer,
      );
      return resp;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[affiliate.authWallet] FAIL: $e\n$st');
      TrackingService.affiliateAuthWalletCompleted(
        success: false,
        reason: e.runtimeType.toString(),
      );
      return null;
    }
  }

  /// Push the wallet's current `user@paykute.com` Lightning address to the
  /// backend so the affiliate `payout_address` stays in sync after the user
  /// edits it. The backend upserts `payout_address` on every [authWallet]
  /// call, so this is simply an [authWallet] with the new address.
  ///
  /// Best-effort and safe to fire-and-forget: if wallet identity isn't ready
  /// yet, or the network call fails, the address is re-synced by the next
  /// boot's background registration (which reads the now-updated
  /// `lnAddressProvider`). Never throws.
  static Future<void> syncPayoutAddress(String paykuteAddress) async {
    if (paykuteAddress.isEmpty) return;
    // authWallet needs the seed-derived identity; if it isn't ready the
    // boot-time background registration will sync from lnAddressProvider.
    if (!WalletIdentityService.isReady) {
      if (kDebugMode) {
        debugPrint('[affiliate.syncPayoutAddress] identity not ready — '
            'deferring to background registration');
      }
      return;
    }
    try {
      await authWallet(paykuteAddress: paykuteAddress);
    } catch (_) {
      // authWallet already swallows its own errors; this is belt-and-braces.
    }
  }

  /// Late-entry referrer binding. Returns the HTTP status code so the UI
  /// can show typed errors:
  ///   200 — set successfully
  ///   400 — invalid code OR self-referral
  ///   404 — code not found
  ///   409 — referrer already set
  ///   410 — past 7-day grace window
  static Future<int> setReferrerByCode(String code) async {
    if (_sessionToken == null) return 401;
    try {
      await RuntimeCapabilitiesService.instance.ensureAllowed('affiliate.program');
      final device = await RuntimeCapabilitiesService.instance.requestContextHeaders();
      final r = await http
          .post(
            Uri.parse('$_baseUrl/set-referrer-by-code'),
            headers: {..._authedHeaders(), ...device},
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 10));
      return r.statusCode;
    } catch (_) {
      return 0;
    }
  }

  /// Fetch the dashboard payload (code, rate, counters, accrued/paid,
  /// payments, rules). Returns null on auth failure or network error.
  ///
  /// Also reconciles a backend code RENAME: if `/me` returns a different
  /// affiliate_code than we have cached (an admin renamed it), we update
  /// local storage + re-identify PostHog so the device tracks the new
  /// code and the share link/QR regenerate. The backend keeps the OLD
  /// code resolvable via its alias map, so links already shared still work.
  static Future<Map<String, dynamic>?> getMe() async {
    if (_sessionToken == null) return null;
    try {
      final r = await http
          .get(Uri.parse('$_baseUrl/me'), headers: _authedHeaders())
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      await _syncAffiliateCode(body['affiliate_code'] as String?);
      _rememberRefereeDiscount(
          body['referee_discount_bps'], body['referee_discount_pct']);
      return body;
    } catch (_) {
      return null;
    }
  }

  /// Reconcile a changed affiliate code (admin rename) into local state +
  /// PostHog. No-op when unchanged. The wallet pubkey is never sent; the
  /// code travels as a person property and is aliased onto the device
  /// identity in [TrackingService.identifyWithAffiliate].
  static Future<void> _syncAffiliateCode(String? newCode) async {
    if (newCode == null || newCode.isEmpty) return;
    if (newCode == _affiliateCode) return;
    _affiliateCode = newCode;
    try {
      await _storage.write(key: _codeKey, value: newCode);
    } catch (_) {/* non-fatal */}
    try {
      await TrackingService.identifyWithAffiliate(newCode);
    } catch (_) {/* best-effort */}
    try {
      await _setAffiliateProperties(affiliateCode: newCode);
    } catch (_) {/* best-effort */}
    TrackingService.affiliateCodePulled();
  }

  /// Report the wallet's lifetime send/receive count so the backend can
  /// apply the ">10 transactions" activation rule (the backend can't see
  /// wallet txs by design). Monotonic + idempotent server-side. Best-effort.
  static Future<void> reportActivity(int txCount) async {
    if (_sessionToken == null || txCount <= 0) return;
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/activity'),
            headers: _authedHeaders(),
            body: jsonEncode({'tx_count': txCount}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {/* best-effort */}
  }

  // ─── Install attribution ─────────────────────────────────────────
  //
  // AppsFlyer's first-launch attribution (campaign names + install time)
  // goes to POST /attribution once per install, with the wallet session.
  // The backend keeps the first value it receives. Queued in secure
  // storage until a session exists; a failed send retries on the next
  // session; a secure-storage flag stops it after the first accepted send.
  // Skipped while analytics are off (the user's opt-out), queued meanwhile.

  static Future<void>? _attributionFlush;

  /// Queue [attribution] (from `AppsFlyerService`) and try to send it.
  /// The first queued value wins. The backend needs `af_status` or
  /// `af_media_source`; without either nothing is queued. Never throws.
  static Future<void> queueInstallAttribution(
      Map<String, String> attribution) async {
    if (!attribution.containsKey('af_status') &&
        !attribution.containsKey('af_media_source')) {
      return;
    }
    try {
      if (await _storage.read(key: _attributionSentKey) != null) return;
      if (await _storage.read(key: _attributionPendingKey) == null) {
        await _storage.write(
            key: _attributionPendingKey, value: jsonEncode(attribution));
      }
    } catch (_) {
      return;
    }
    await flushInstallAttribution();
  }

  /// Send the queued install attribution when a wallet session exists.
  /// Concurrent calls share one attempt. Never throws.
  static Future<void> flushInstallAttribution() {
    final pending = _attributionFlush;
    if (pending != null) return pending;
    final run = _sendInstallAttribution();
    _attributionFlush = run;
    return run.whenComplete(() {
      if (identical(_attributionFlush, run)) _attributionFlush = null;
    });
  }

  static Future<void> _sendInstallAttribution() async {
    try {
      if (_sessionToken == null || TrackingService.isDisabled) return;
      if (await _storage.read(key: _attributionSentKey) != null) return;
      final queued = await _storage.read(key: _attributionPendingKey);
      if (queued == null) return;
      final body = jsonDecode(queued);
      if (body is! Map<String, dynamic>) {
        await _storage.delete(key: _attributionPendingKey);
        return;
      }
      final r = await http
          .post(
            Uri.parse('$_baseUrl/attribution'),
            headers: _authedHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (!installAttributionSettled(r.statusCode)) return;
      await _storage.write(key: _attributionSentKey, value: '1');
      await _storage.delete(key: _attributionPendingKey);
    } catch (_) {/* retried on the next session */}
  }

  /// Whether a response to POST /attribution ends the retries: accepted,
  /// already set (409), or a body the backend will never accept (400,
  /// 422). Auth, rate-limit and server errors retry next session.
  @visibleForTesting
  static bool installAttributionSettled(int status) =>
      (status >= 200 && status < 300) ||
      status == 400 ||
      status == 409 ||
      status == 422;

  /// Fetch the daily earnings time series for the chart. Default 30-day
  /// window. Returns null on error.
  static Future<List<dynamic>?> getHistory({int days = 30}) async {
    if (_sessionToken == null) return null;
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/me/history?days=$days'),
            headers: _authedHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return body['history'] as List<dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the earnings breakdown by source_type for a window. Returns
  /// rows of the form {source_type, sats, share_pct} ordered by sats desc.
  static Future<Map<String, dynamic>?> getBreakdown({int days = 30}) async {
    if (_sessionToken == null) return null;
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/me/breakdown?days=$days'),
            headers: _authedHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the anonymized referee list. Returns null on error.
  static Future<List<dynamic>?> getReferees({int limit = 50}) async {
    if (_sessionToken == null) return null;
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/me/referees?limit=$limit'),
            headers: _authedHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return body['referees'] as List<dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Trigger a payout claim. Returns:
  ///   { ok: true, sats, claim_id, tx_id, payout_to }                on success
  ///   { ok: false, reason: 'below_minimum', min_sats: N }            no balance
  ///   { ok: false, reason: 'payout_send_failed', claim_id: N }       address stale
  ///   { ok: false, reason: 'unauthorized' | 'network' }              other
  ///
  /// On 'payout_send_failed', the caller should re-call [authWallet] with
  /// the wallet's current paykute_address to resync, then retry the claim
  /// with a fresh idempotency key.
  static Future<Map<String, dynamic>> claim({required String idempotencyKey}) async {
    if (_sessionToken == null) {
      return {'ok': false, 'reason': 'unauthorized'};
    }
    try {
      final r = await http
          .post(
            Uri.parse('$_baseUrl/claim'),
            headers: _authedHeaders(),
            body: jsonEncode({'idempotency_key': idempotencyKey}),
          )
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200) {
        return {
          'ok': true,
          ...body,
        };
      }
      return {
        'ok': false,
        'status': r.statusCode,
        'reason': body['reason'] ?? 'error',
        ...body,
      };
    } catch (_) {
      return {'ok': false, 'reason': 'network'};
    }
  }

  /// Stable Kute identity for accounting, never the selected Ledger address.
  static String? get revenueIdentity =>
      WalletIdentityService.pubkey ?? _tokenIdentity(_sessionToken);

  /// This wallet's affiliate id (the backend's `affiliates.id`), read from
  /// the cached wallet session token (`pubkey|affiliate_id|exp[|iat]`).
  /// Shown in Settings → Advanced so support can find the account; it is
  /// not a secret. Null before the wallet has a session, or for a token
  /// that carries no affiliate.
  static String? get affiliateId => affiliateIdFromToken(_sessionToken);

  @visibleForTesting
  static String? affiliateIdFromToken(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final fields = utf8.decode(base64Url.decode(
          base64Url.normalize(token.split('.').first))).split('|');
      if (fields.length != 3 && fields.length != 4) return null;
      final id = int.tryParse(fields[1]);
      return id != null && id > 0 ? '$id' : null;
    } catch (_) {
      return null;
    }
  }

  static String? _tokenIdentity(String? token) {
    try {
      final fields = utf8.decode(base64Url.decode(
          base64Url.normalize(token!.split('.').first))).split('|');
      if (fields.length != 3 && fields.length != 4) return null;
      return fields.first;
    } catch (_) { return null; }
  }

  static Timer? _revenueFlushTimer;

  static Future<void> flushProviderEvents() async {
    final identity = revenueIdentity;
    if (identity == null || identity.isEmpty) return;
    await ProviderEventOutbox.flush(
      identity: identity,
      send: (body) async {
        if (revenueIdentity != identity) return ProviderEventDelivery.retryLater;
        try {
          final response = await sendWithSession('provider_events', (auth) {
            final token = auth['Authorization']?.substring(7);
            if (revenueIdentity != identity || _tokenIdentity(token) != identity) {
              throw StateError('Accounting identity changed');
            }
            return http.post(
              Uri.parse('${dotenv.env['BACKEND']!}/api/v1/provider-events/log'),
              headers: {'Content-Type': 'application/json', ...auth},
              body: jsonEncode(body),
            ).timeout(const Duration(seconds: 6));
          });
          if (response.statusCode == 200 || response.statusCode == 202) {
            return ProviderEventDelivery.delivered;
          }
          if (response.statusCode == 400 || response.statusCode == 422) {
            return ProviderEventDelivery.rejected;
          }
          return ProviderEventDelivery.retryLater;
        } catch (_) {
          return ProviderEventDelivery.retryLater;
        }
      },
    );
  }

  /// Queue accounting durably before sending. Failures never change a trade's
  /// result. The same provider/order key is replayed so the backend can dedup.
  static Future<bool> logProviderEvent({
    required String provider,
    required String providerOrderId,
    required String status,
    double? fiatAmountEur,
    String? sourceAsset,
    double? sourceAmount,
    String? destinationAsset,
    double? destinationAmount,
    String? paykuteAddressForFallbackAuth,
    double? builderFeeUsd,
    String? expectedIdentity,
  }) async {
    if (provider.isEmpty || providerOrderId.isEmpty) return false;
    var identity = revenueIdentity;
    if (identity == null && paykuteAddressForFallbackAuth != null) {
      await authWallet(paykuteAddress: paykuteAddressForFallbackAuth);
      identity = revenueIdentity;
    }
    if (identity == null || identity.isEmpty ||
        (expectedIdentity != null && identity != expectedIdentity)) return false;
    final body = <String, dynamic>{
      'provider': provider,
      'provider_order_id': providerOrderId,
      'status': status,
      if (builderFeeUsd != null) 'builder_fee_usd': builderFeeUsd,
      if (fiatAmountEur != null && fiatAmountEur.isFinite && fiatAmountEur > 0)
        'fiat_amount_eur': fiatAmountEur,
      if (sourceAsset != null && sourceAsset.isNotEmpty) 'source_asset': sourceAsset,
      if (sourceAmount != null && sourceAmount.isFinite && sourceAmount > 0)
        'source_amount': sourceAmount,
      if (destinationAsset != null && destinationAsset.isNotEmpty)
        'destination_asset': destinationAsset,
      if (destinationAmount != null && destinationAmount.isFinite && destinationAmount > 0)
        'destination_amount': destinationAmount,
    };
    final queued = await ProviderEventOutbox.enqueue(identity, body);
    if (queued) unawaited(flushProviderEvents());
    return queued;
  }

  /// Clear local affiliate state on new-wallet creation. Clears the session
  /// and code, and resets the background-registration
  /// gate so the new wallet registers cleanly.
  ///
  /// Deliberately does NOT touch the durable pending referrer: it is
  /// install-scoped attribution (not wallet-scoped state), and wipe() runs
  /// during first-wallet onboarding (passkey_choice) BEFORE the referrer binds.
  /// Deleting it here re-opened the cross-boot referrer-loss bug the durable
  /// copy exists to prevent. It is cleared instead on a confirmed bind
  /// ([authWallet]) or an explicit user reject ([clearPendingReferrer]).
  static Future<void> wipe() async {
    _revenueFlushTimer?.cancel();
    _revenueFlushTimer = null;
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _sessionAddressKey);
    await _storage.delete(key: _codeKey);
    _sessionToken = null;
    _affiliateCode = null;
    // Let the freshly created wallet start its OWN registration loop. Without
    // this, a loop still in flight for the previous wallet leaves the gate set
    // and startBackgroundRegistration() would no-op the new wallet's pass.
    _backgroundRegistrationActive = false;
  }

  // ─── Internal helpers ────────────────────────────────────────────

  static Map<String, String> _authedHeaders() => {
        'Content-Type': 'application/json',
        if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken',
      };

  /// Push affiliate context to PostHog as person properties so every
  /// downstream event is filterable by `affiliate_code` /
  /// `referred_by_code`. These attach to the current distinct_id (the
  /// stable device UUID); the affiliate_code is additionally aliased onto
  /// that identity in `TrackingService.identifyWithAffiliate` so the
  /// backend's code-keyed events resolve to the same person. The wallet
  /// pubkey is deliberately kept out of third-party analytics per the
  /// 2026-05 telemetry audit.
  static Future<void> _setAffiliateProperties({
    String? affiliateCode,
    String? referredByCode,
    String? tierLevel,
  }) async {
    try {
      if (affiliateCode != null) {
        TrackingService.setUserProperty('affiliate_code', affiliateCode);
      }
      TrackingService.setUserProperty(
        'referred_by_code',
        (referredByCode != null && referredByCode.isNotEmpty)
            ? referredByCode
            : 'none',
      );
      if (tierLevel != null) {
        TrackingService.setUserProperty('affiliate_tier', tierLevel);
      }
    } catch (_) {
      // Non-fatal — analytics is best-effort.
    }
  }
}

/// No wallet session could be obtained for a route that requires one.
/// [message] is localized copy for the user; nothing was sent.
class WalletSessionUnavailable implements Exception {
  const WalletSessionUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
