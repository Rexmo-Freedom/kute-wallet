import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/advisor/sal_chip_templates.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

/// Unified analytics wrapper.
///
/// PostHog (EU)            -> events, screen views, person properties.
///                            distinct_id = a stable per-device UUID (set
///                            in [initialize]); the affiliate_code travels
///                            as a person PROPERTY, not the identity.
///                            Replay stays OFF; sensitive screens are
///                            pre-masked in the router.
/// Firebase Crashlytics   -> uncaught crashes via `recordCrash` ->
///                            `recordError` with a sanitized error object.
///                            Crashlytics is the ONLY crash sink; PostHog
///                            is product-analytics only. AppsFlyer handles
///                            install attribution / ROAS. There is NO
///                            Firebase Analytics in this app.
///
/// Privacy: No addresses, invoices, keys, seed phrases, txids, raw order
/// ids, whole-wallet balances or PII are ever tracked; [track], the
/// PostHog beforeSend hook and every Crashlytics path run the shared
/// [scrubString] redactor as a backstop. Money OUTCOME events carry exact
/// values (amount_usd, amount + asset, fee_shown_* = the fee the user saw)
/// beside the legacy buckets — see [moneyParams]; intermediate UI events
/// carry none. Revenue and fee estimates are never emitted here: revenue
/// reaches PostHog only from the database through the warehouse sync, and
/// money events carry `order_ref` / `quote_ref` ([orderRef]) to join to it.
/// Users are identified by a random device UUID stored in secure storage,
/// with the affiliate code aliased onto it.
///
/// HARD RULE — anything seed-, mnemonic-, key-, or address-derived
/// stays out of every event payload. That includes secondary signals
/// people sometimes add by reflex: word count, first/last word, hash
/// of the seed, derivation path with the public key inline, etc. If
/// you need to know "did the user reveal a seed", emit a parameterless
/// event from a code site that doesn't even see the bytes. Treat the
/// `params:` map of `track(...)` as a public broadcast channel.
class TrackingService {
  TrackingService._();

  /// Tracking is enabled by default on release builds and DISABLED on
  /// debug builds. Hot-reloads while developing used to show up in the
  /// realtime view and inflate active-user counts on prod dashboards;
  /// muting at the source keeps `flutter run` invisible. Override at
  /// runtime via [setDisabled] (pass `false` in a debug session to
  /// verify wiring, or `true` on release for a privacy QA pass).
  static bool _disabled = kDebugMode;

  /// The user's own analytics choice (the `analytics_opt_in` setting),
  /// kept apart from [_disabled] so opting back in can never un-mute a
  /// debug build. Crash reporting ignores it.
  static bool _optedOut = false;

  /// True when nothing may reach PostHog: debug mute or the user's opt-out.
  static bool get _muted => _disabled || _optedOut;

  static String? _deviceId;

  /// Last code handed to [identifyWithAffiliate], kept so opting back in
  /// can identify again without waiting for the next boot.
  static String? _lastAffiliateCode;

  /// Manual override for the auto debug-mute. Pass `false` to opt a
  /// debug session into analytics; pass `true` to mute a release
  /// build (e.g. for a privacy-sensitive QA pass). Defaults to
  /// `kDebugMode`; callers rarely need this.
  static void setDisabled(bool value) => _disabled = value;

  static const _storage = secureStorage;
  static const _deviceIdKey = 'kute_device_uuid';

  // ─── Initialization ──────────────────────────────────────────────

  static Future<void> initialize() async {
    await loadSeedWordlist();
    // Phase 5 B12: report hot entry points refused inside a Ledger
    // operation. Tests may install their own reporter first.
    LedgerOperationScope.onBlocked ??=
        (action) => hotSigningBlocked(action.analyticsName);
    // Debug builds:
    //   * `_disabled = kDebugMode` short-circuits our `track` /
    //     `screenView` / `setUserProperty` wrappers so `flutter run`
    //     sessions never appear in PostHog.
    //   * Crashlytics is also DISABLED so dev stack traces don't
    //     pollute the prod issue tracker.
    //   To verify event wiring against PostHog Activity during
    //   development, call `TrackingService.setDisabled(false)`
    //   manually from a one-off in `main.dart`.
    // User opt-out (GDPR/UK-DPA), applied before anything below can
    // queue a property. main.dart already applied it the moment Hive
    // opened; this repeat covers any other entry point.
    applyStoredOptOut();

    if (!kDebugMode) {
      setUserProperty('app_environment', 'release');
    }

    // Generate or restore device UUID
    await _initDeviceId();

    // Crash context: keep the previous session's screen/flow snapshot for
    // the post-mortem crash markers, then start persisting this one's.
    await initCrashContext();

    // No feature-flag fetch here: nothing in the app reads PostHog flags
    // (analytics never steer the app, see [isDisabled]), so the old early
    // `reloadFeatureFlags()` only cost a network round-trip on boot.

    // Set default user properties on first launch
    await _setDefaultUserProperties();
  }

  /// Generate a UUID v4 on first launch and persist in secure storage.
  /// On iOS this survives reinstalls (Keychain-backed). On Android it
  /// resets on reinstall (acceptable trade-off). The uuid IS the PostHog
  /// distinct_id (and the Crashlytics user id); the affiliate_code is
  /// only aliased onto it by [identifyWithAffiliate] once
  /// `AffiliateService` restores it on boot.
  static Future<void> _initDeviceId() async {
    try {
      String? existing = await _storage.read(key: _deviceIdKey);
      if (existing == null || existing.isEmpty) {
        existing = generateUuidV4();
        await _storage.write(key: _deviceIdKey, value: existing);
      }
      _deviceId = existing;
    } catch (e) {
      // silently ignore
    }
    // Tag Crashlytics as early as possible so even a crash during boot
    // (before AffiliateService restores) carries the same id as PostHog.
    _setCrashlyticsUser(_deviceId);
  }

  /// Crashlytics user id = the PostHog distinct_id (device UUID). Never the
  /// affiliate code: when the UUID is missing the id is 'unknown'.
  /// Release-only; not gated on the analytics opt-out (crash reports are
  /// covered by privacy policy §6.3, not by the analytics choice).
  static void _setCrashlyticsUser(String? deviceId) {
    final id = crashlyticsUserId(
        deviceId == null || deviceId.isEmpty ? 'unknown' : deviceId);
    debugCrashlyticsObserver?.call('user', 'user_id', id);
    if (kDebugMode) return;
    try {
      unawaited(FirebaseCrashlytics.instance
          .setUserIdentifier(id)
          .catchError((Object _) {}));
    } catch (_) {}
  }

  /// Identify the user to PostHog using the STABLE per-device UUID as
  /// distinct_id. Call once `TrackingService.initialize()` (which sets
  /// `_deviceId`) has run on boot.
  ///
  /// Why the device UUID and not the affiliate_code: the affiliate_code
  /// only exists after `AffiliateService.authWallet` completes a network
  /// round-trip, which most FIRST opens haven't done yet (offline, slow,
  /// pre-auth). The old code identified every such boot under the shared
  /// sentinel `'unknown'`, collapsing all pre-auth users into a SINGLE
  /// PostHog person — which (with PostHog's default `identified_only`
  /// person mode dropping anonymous installs) is why installs vastly
  /// outnumbered unique users. The device UUID exists from the very first
  /// launch, so every install becomes its own unique person on first open
  /// even with no internet (the `$identify` event queues to disk and
  /// flushes on reconnect).
  ///
  /// The device UUID is a random v4 in secure storage — NOT the wallet
  /// pubkey — so this still honours the 2026-05 telemetry audit: the
  /// Lightning identity never enters third-party analytics. The
  /// affiliate_code travels as a person PROPERTY (not the identity) so a
  /// late-arriving code updates the same person instead of re-keying
  /// (fragmenting) it.
  static Future<void> identifyWithAffiliate(String affiliateCode) async {
    // Stable identity: device UUID first, then affiliate_code, then the
    // 'unknown' sentinel only if secure storage failed to yield a uuid.
    final id = _deviceId ?? (affiliateCode.isEmpty ? 'unknown' : affiliateCode);
    // Tag Crashlytics with the device UUID (not gated on analytics opt-in)
    // so a user's crashes (Firebase) and product events (PostHog)
    // cross-reference. Never the affiliate code: 'unknown' without a UUID.
    _setCrashlyticsUser(_deviceId);
    final previousCode = _lastAffiliateCode;
    _lastAffiliateCode = affiliateCode;
    if (_muted) return;
    // Tag AppsFlyer with the same affiliate_code so its rows are filterable
    // by the same id as PostHog + the backend. Set before the PostHog call
    // so it lands even if the PostHog SDK is still warming up.
    if (affiliateCode.isNotEmpty) {
      AppsFlyerService.setAffiliateCode(affiliateCode);
    }
    try {
      // A code rename (admin rename reaching this device through /me or
      // /auth/wallet) with no device UUID: the identity IS the code, so
      // identifying under the new one would start a second person. Alias
      // the new code onto the current (old-code) identity first so both
      // stay one person. With a device UUID the alias below does the same.
      if (_deviceId == null &&
          previousCode != null &&
          previousCode.isNotEmpty &&
          affiliateCode.isNotEmpty &&
          previousCode != affiliateCode) {
        await _aliasAffiliateOnce(affiliateCode)
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      }
      await Posthog().identify(
        userId: id,
        userProperties: {
          if (_deviceId != null) 'device_uuid': _deviceId!,
          if (affiliateCode.isNotEmpty) 'affiliate_code': affiliateCode,
          'affiliate_status': affiliateCode.isEmpty ? 'unknown' : 'assigned',
        },
      ).timeout(const Duration(seconds: 2), onTimeout: () {});
      // The Go backend fires `revenue_recorded` keyed by affiliate_code
      // (it only learns the code from the wallet session — it never sees
      // this device UUID). Without a link those land on a SEPARATE PostHog
      // person from the app's events, splitting one real user in two and
      // skewing per-event unique counts. Alias the affiliate_code onto this
      // device's identity so backend events merge into the same person.
      // Only meaningful when the device UUID is the distinct_id (else the
      // identity already IS the affiliate_code and aliasing is a no-op).
      // This is also what merges a RENAMED code: identifying with the new
      // code aliases it onto the same device person the old code already
      // points to, once per code.
      if (affiliateCode.isNotEmpty && _deviceId != null) {
        await _aliasAffiliateOnce(affiliateCode)
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      }
    } catch (_) {/* SDK not ready — next session catches up */}
  }

  /// Alias [affiliateCode] -> current distinct_id (the device UUID) so the
  /// backend's affiliate-code-keyed events collapse into the same PostHog
  /// person. Persisted-guarded so we emit the alias only once per code
  /// instead of an `$create_alias` event on every boot.
  static Future<void> _aliasAffiliateOnce(String affiliateCode) async {
    try {
      const key = 'kute_aliased_affiliate';
      final prev = await _storage.read(key: key);
      if (prev == affiliateCode || _muted) return;
      await Posthog().alias(alias: affiliateCode);
      await _storage.write(key: key, value: affiliateCode);
    } catch (_) {/* alias is best-effort; retried next boot if it failed */}
  }

  // ─── Website → app identity link ─────────────────────────────────
  //
  // The website puts the visitor's PostHog distinct id on every store /
  // download link as `af_sub2` (and inside the Play install referrer).
  // AppsFlyer hands it back in the install conversion data or a deep-link
  // payload; aliasing it onto this device's distinct_id stitches the
  // pre-install web journey and the app journey into one PostHog person.
  // The id is only ever a PostHog anonymous UUID or an affiliate code the
  // website already aliased — it is never a referral code and never binds
  // a referrer.

  static const _webVisitorAliasKey = 'kute_aliased_web_visitor';
  static Future<void>? _webVisitorAlias;

  static final RegExp _uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final RegExp _affiliateCodePattern = RegExp(r'^[A-Z0-9]{3,32}$');

  /// True when [raw] can be a website PostHog distinct id: a UUID (the
  /// anonymous id) or an affiliate code (upper-case, the partner the site
  /// identified). Anything else (URLs, emails, bech32 / base58 addresses,
  /// sentinel strings) is refused.
  static bool looksLikeWebVisitorId(String? raw) {
    if (raw == null) return false;
    final id = raw.trim();
    if (id.isEmpty || id.length > 64) return false;
    if (_uuidPattern.hasMatch(id)) return true;
    return _affiliateCodePattern.hasMatch(id);
  }

  /// Alias the website visitor id [webId] onto this install's distinct_id,
  /// once per install. Fire-and-forget: never awaited by startup, capped
  /// at 2 s, skipped while muted (debug build or opt-out) and when the
  /// id is not a plausible PostHog distinct id. Sets the person property
  /// `web_visitor_linked` so linked installs can be segmented. The id
  /// itself is never sent as an event property.
  static Future<void> aliasWebVisitor(String? webId) {
    final pending = _webVisitorAlias;
    if (pending != null) return pending;
    final run = _aliasWebVisitorOnce(webId);
    _webVisitorAlias = run;
    return run.whenComplete(() {
      if (identical(_webVisitorAlias, run)) _webVisitorAlias = null;
    });
  }

  static Future<void> _aliasWebVisitorOnce(String? webId) async {
    if (_muted || !looksLikeWebVisitorId(webId)) return;
    final id = webId!.trim();
    // The install's own distinct_id is not a web visitor.
    if (id == _deviceId) return;
    try {
      if (await _storage.read(key: _webVisitorAliasKey) != null) return;
      if (_muted) return;
      await Posthog()
          .alias(alias: id)
          .timeout(const Duration(seconds: 2));
      // Persisted only after the SDK accepted the alias, so a failure
      // retries on the next payload instead of being lost.
      await _storage.write(key: _webVisitorAliasKey, value: 'done');
      setUserPropertyValue('web_visitor_linked', true);
    } catch (_) {/* best-effort; retried on the next payload */}
  }

  /// Returns the device UUID (available after initialize()).
  static String? get deviceId => _deviceId;

  /// Simple UUID v4 generator — no external package needed.
  @visibleForTesting
  static String generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    // Set version (4) and variant (10xx) bits per RFC 4122
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  // ─── Wallet Category Helper ────────────────────────────────────

  /// `wallet_kind` for money events: 'ledger' for a Ledger, else the
  /// [walletCategory] value (hot | signer | hardware | watch_only |
  /// external_address). Dashboards split hot vs Ledger volume on this.
  static String walletKind({
    required bool isLedger,
    required bool isHardware,
    required bool isWatchOnly,
    required bool isSigner,
    required bool isExternalAddress,
  }) =>
      isLedger
          ? 'ledger'
          : walletCategory(
              isHardware: isHardware,
              isWatchOnly: isWatchOnly,
              isSigner: isSigner,
              isExternalAddress: isExternalAddress,
            );

  /// Returns a normalized wallet category for analytics segmentation.
  /// Categories: 'hot', 'signer', 'hardware', 'watch_only', 'external_address'
  static String walletCategory({
    required bool isHardware,
    required bool isWatchOnly,
    required bool isSigner,
    required bool isExternalAddress,
  }) {
    if (isExternalAddress) return 'external_address';
    if (isSigner) return 'signer';
    if (isHardware) return 'hardware';
    if (isWatchOnly) return 'watch_only';
    return 'hot';
  }

  // ─── User Properties (Fintech-standard) ──────────────────────────

  static Future<void> _setDefaultUserProperties() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion ??= '${info.version}+${info.buildNumber}';
      _packageVersion = info.version;
      _packageBuild = info.buildNumber;
      setUserProperty('app_version', info.version);
      setUserProperty('build_number', info.buildNumber);
    } catch (_) {}
    setUserProperty('platform', Platform.isIOS ? 'ios' : 'android');
  }

  /// Call after wallet creation / login to tag the user session.
  static void setWalletProperties({
    required String
        walletType, // 'hot', 'signer', 'hardware', 'watch_only', 'external_address'
    required int walletCount,
    String? preferredCurrency,
    String? language,
    String? theme,
  }) {
    setUserProperty('wallet_type', walletType);
    setUserPropertyValue('wallet_count', walletCount);
    if (preferredCurrency != null) {
      setUserProperty('preferred_currency', preferredCurrency);
    }
    if (language != null) setUserProperty('language', language);
    if (theme != null) setUserProperty('theme', theme);
  }

  /// Set the primary wallet category the user interacts with most.
  static void setActiveWalletCategory(String category) {
    setUserProperty('active_wallet_category', category);
  }

  // ─── Core Tracking Methods ───────────────────────────────────────

  /// Scrub a freeform `reason` string before it leaves the device.
  /// Strips long hex tokens (Ethereum/Polygon/tx-hash style),
  /// bech32 LN/BTC strings, and base58 Bitcoin addresses, then caps
  /// total length. Catches the audit's biggest leak: dozens of
  /// `*Failed` events pass `e.toString()` from SDK exceptions whose
  /// messages inline deposit addresses, refund addresses, and
  /// invoices. Static reasons ("no orders found") survive the scrub
  /// intact so debugging signal is preserved.
  static String? _safeReason(String? raw) {
    if (raw == null) return null;
    // The shared redactor first (keys, descriptors, addresses, invoices,
    // phrases), so a later, looser rule can never leave a fragment behind.
    // PostHog properties, PostHog exceptions and every Crashlytics path go
    // through [scrubString]; this adds the stricter free-text rules.
    var s = scrubString(raw);
    // 12+ char hex runs (with optional 0x prefix) cover Eth/Polygon
    // addresses (40 chars), tx hashes (64), condition ids (64),
    // builder signatures (130), and most BDK/Breez derivation-path
    // dumps.
    s = s.replaceAll(RegExp(r'\b(?:0x)?[0-9a-fA-F]{12,}\b'), '<hex>');
    // Bech32 LN invoices / segwit addresses.
    s = s.replaceAll(
        RegExp(r'\b(?:bc1|tb1|lnbc|lntb|lnbcrt)[0-9a-z]{20,}\b'), '<addr>');
    // Any other bech32/bech32m string, whatever the human-readable part
    // and whatever the case. The rule above only knows the Bitcoin and
    // Lightning prefixes in lower case, so it misses Spark addresses
    // (sp1, sprt1), lnurl1, offers (lno1), and every QR-form address,
    // which is upper case by spec. The data part has its own alphabet
    // (no 1, b, i or o), which is what keeps this off ordinary words.
    s = s.replaceAll(
        RegExp(r'\b[A-Za-z]{2,8}1[QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L]{20,}\b',
            caseSensitive: false),
        '<addr>');
    // Base58 Bitcoin addresses (P2PKH/P2SH).
    s = s.replaceAll(RegExp(r'\b[1-9A-HJ-NP-Za-km-z]{26,}\b'), '<addr>');
    // Opaque high-entropy tokens: base64 and base64url blobs, which cover
    // passkey/PRF material, JWTs and provider keys. Nothing here sends one
    // today; the rule exists so that the day something does, it is caught.
    // Only runs that mix upper, lower and digits qualify, so ordinary long
    // identifiers in an exception message survive intact.
    s = s.replaceAllMapped(RegExp(r'\b[A-Za-z0-9+/_-]{24,}={0,2}'), (match) {
      final token = match[0]!;
      final mixed = RegExp(r'[0-9]').hasMatch(token) &&
          RegExp(r'[A-Z]').hasMatch(token) &&
          RegExp(r'[a-z]').hasMatch(token);
      return mixed ? '<token>' : token;
    });
    // Recovery phrase fragments, then PINs and one-time codes.
    s = _redactSeedWordRuns(s);
    s = redactErrorNumbers(s);
    if (s.length > 80) s = '${s.substring(0, 77)}...';
    return s;
  }

  static final RegExp _decimalAmount =
      RegExp(r'(?<![0-9A-Za-z.])[0-9]+[.,][0-9]+(?![0-9.])');
  static final RegExp _longNumber = RegExp(r'(?<![0-9])[0-9]{5,}(?![0-9])');

  /// Error text only (reasons, exception messages, crash text), never
  /// analytics money properties: decimal amounts become `<amount>` and
  /// numbers of 5 or more digits (sats, PINs, one-time codes, ids) become
  /// `<digits>`. Short integers (HTTP codes, counts) survive.
  @visibleForTesting
  static String redactErrorNumbers(String s) => s
      .replaceAll(_decimalAmount, '<amount>')
      .replaceAll(_longNumber, '<digits>');

  static const _seedWordlistAsset = 'lib/assets/bip39_english.txt';
  static Set<String>? _seedWordlist;
  static final _letterRun = RegExp(r'[A-Za-z]+');

  /// Loads the BIP39 English wordlist used to redact recovery phrase
  /// fragments. Until it has loaded, runs of short lowercase words are
  /// redacted instead.
  static Future<void> loadSeedWordlist([AssetBundle? bundle]) async {
    try {
      final text = await (bundle ?? rootBundle).loadString(_seedWordlistAsset);
      final words = text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w.toLowerCase())
          .toSet();
      if (words.isNotEmpty) _seedWordlist = words;
    } catch (_) {/* keep the fallback heuristic */}
  }

  @visibleForTesting
  static void debugSetSeedWordlist(Set<String>? words) => _seedWordlist = words;

  /// Replaces every run of 3 or more consecutive BIP39 words (any case,
  /// separated only by spaces or punctuation) with `<words>`. Before the
  /// wordlist loads, a word counts when it is 3 to 8 lowercase letters.
  static String _redactSeedWordRuns(String s, {int? minRun}) {
    final wordlist = _seedWordlist;
    // Before the wordlist loads, a word counts when it is 3 to 8 letters
    // and either all lower case or capitalised. Capitalised has to count:
    // a phrase typed into a field that auto-capitalises would otherwise
    // walk straight past the fallback during the boot window. Mixed case
    // and all caps still do not count, so identifiers survive.
    bool seedLike(String token) {
      if (wordlist != null) return wordlist.contains(token.toLowerCase());
      if (token.length < 3 || token.length > 8) return false;
      final rest = token.substring(1);
      return rest == rest.toLowerCase();
    }

    final out = StringBuffer();
    var copied = 0;
    var runStart = -1;
    var runEnd = 0;
    var runLength = 0;
    void closeRun() {
      // Three words is the bar once the wordlist is loaded and a match
      // means a real BIP39 word. Before then, every short lower-case or
      // capitalised word qualifies, so three would swallow ordinary error
      // text, and did. A phrase is twelve or twenty four words, so six
      // still catches one while leaving prose alone.
      if (runStart >= 0 && runLength >= (minRun ?? (wordlist != null ? 3 : 6))) {
        out
          ..write(s.substring(copied, runStart))
          ..write('<words>');
        copied = runEnd;
      }
      runStart = -1;
      runLength = 0;
    }

    for (final match in _letterRun.allMatches(s)) {
      if (!seedLike(match.group(0)!)) {
        closeRun();
        continue;
      }
      // A digit between two words no longer ends the run. It used to, and
      // that alone defeated the whole rule for a numbered phrase such as
      // "1 abandon 2 ability 3 able", where every gap carries an index and
      // the run therefore never reached three.
      if (runStart < 0) runStart = match.start;
      runEnd = match.end;
      runLength++;
    }
    closeRun();
    if (copied == 0) return s;
    out.write(s.substring(copied));
    return out.toString();
  }

  /// Map a USD amount to a coarse bucket label for analytics. We
  /// keep funnel signal ("did the user deposit > $100?") while
  /// killing the financial-profile-grade precision that any analytics
  /// sink (PostHog here) would otherwise retain keyed on the stable
  /// pseudonymous distinct_id. Buckets follow log-ish steps so each
  /// bucket has roughly equal user-population coverage.
  ///
  /// Negative inputs (e.g. losses) get the same bucketing applied to
  /// the absolute value — callers can pair this with a `direction`
  /// field (`gain` / `loss`) when sign matters.
  static String _usdBucket(double usd) {
    final v = usd.abs();
    if (v < 1) return '0-1';
    if (v < 10) return '1-10';
    if (v < 100) return '10-100';
    if (v < 1000) return '100-1k';
    if (v < 10000) return '1k-10k';
    return '10k+';
  }

  /// Public wrapper around the bucketing helper so call sites outside
  /// `tracking_service.dart` can attach a coarse `amount_bucket`
  /// property to ad-hoc `track()` events without duplicating the
  /// bucketing logic. Same buckets as every internal call: `0-1,
  /// 1-10, 10-100, 100-1k, 1k-10k, 10k+`.
  static String usdBucket(double usd) => _usdBucket(usd);

  /// Public wrapper around [_safeReason] so ad-hoc `track()` call sites
  /// outside this file can scrub freeform error/reason strings (raw
  /// `e.toString()` can inline addresses, invoices, amounts) before they
  /// leave the device, instead of passing the exception text verbatim.
  static String? safeReason(String? raw) => _safeReason(raw);

  /// Fixed, low-cardinality failure class for dashboards. The free-text
  /// `reason` (scrubbed) stays on legacy events for continuity; group and
  /// alert on `error_category` instead. Never carries any part of the text.
  static const Set<String> errorCategories = {
    'user_cancelled', 'insufficient_funds', 'below_minimum', 'above_limit',
    'invalid_destination', 'expired', 'quote_rejected', 'fee_unavailable',
    'timeout', 'network', 'hardware_wallet', 'rate_limited', 'no_route',
    'settlement', 'unknown',
  };

  static String errorCategory(Object? error) {
    if (error == null) return 'unknown';
    final t = error.toString().toLowerCase();
    // Idempotent: a value that already is a category (or a settlement_*
    // stop reason) passes through, so classifying twice never changes it.
    if (errorCategories.contains(t) || t.startsWith('settlement_')) return t;
    bool has(List<String> needles) => needles.any(t.contains);
    if (has(['cancel', 'declined', 'user rejected', 'denied by user'])) {
      return 'user_cancelled';
    }
    if (has(['insufficient', 'not enough', 'balance too low'])) {
      return 'insufficient_funds';
    }
    if (has(['below minimum', 'minimum', 'too small', 'dust'])) {
      return 'below_minimum';
    }
    if (has(['above maximum', 'maximum', 'too large', 'limit'])) {
      return 'above_limit';
    }
    if (has(['invalid address', 'invalid invoice', 'invalid destination',
        'invalid recipient', 'bad address', 'unsupported address'])) {
      return 'invalid_destination';
    }
    if (has(['expired', 'expiry'])) return 'expired';
    if (has(['quote'])) return 'quote_rejected';
    if (has(['fee'])) return 'fee_unavailable';
    if (has(['timeout', 'timed out', 'deadline'])) return 'timeout';
    if (has(['socket', 'network', 'connection', 'host lookup',
        'unreachable', 'offline'])) {
      return 'network';
    }
    if (has(['ledger', 'hardware', 'device'])) return 'hardware_wallet';
    if (has(['rate limit', '429'])) return 'rate_limited';
    if (has(['route', 'no path', 'liquidity'])) return 'no_route';
    if (has(['settle', 'refund'])) return 'settlement';
    return 'unknown';
  }

  /// Public latency bucket ('<500ms' .. '5s+') for call sites.
  static String latencyBucket(int ms) => _latencyBucket(ms);

  /// Coarse latency bucket for reliability/perf events. We bucket so a
  /// precise per-user millisecond timing tied to the pseudonymous
  /// distinct_id can't be used to fingerprint a device's hardware /
  /// network profile, while still preserving "is this getting slower?"
  /// signal. Buckets: '<500ms' | '500ms-1s' | '1-3s' | '3-5s' | '5s+'.
  static String _latencyBucket(int ms) {
    if (ms < 500) return '<500ms';
    if (ms < 1000) return '500ms-1s';
    if (ms < 3000) return '1-3s';
    if (ms < 5000) return '3-5s';
    return '5s+';
  }

  // ─── Outbound scrubber (HARD RULE) ───────────────────────────────
  //
  // Runs on EVERY property that leaves the device: track() params, screen
  // properties, person properties ($set) and, through the beforeSend hook,
  // every event the SDK itself builds ($exception included). It redacts
  // extended keys (xpub/ypub/zpub/tpub/vpub/upub/Ypub/Zpub and the *prv
  // family), private keys (64-hex, WIF), output descriptors, BIP39 phrases,
  // Bitcoin/EVM/Spark addresses, Lightning invoices, LNURLs and lightning
  // addresses. Exact amounts are allowed; none of these ever are.

  static const String redacted = '[redacted]';

  static final List<RegExp> _keyMaterialPatterns = [
    // Output descriptors, whole token (descriptors carry no spaces), with
    // or without the key origin [fingerprint/path] and checksum.
    RegExp(
        r'\b(?:sh|wsh|wpkh|pkh|tr|rawtr|combo|multi|sortedmulti|multi_a|sortedmulti_a|addr|raw)\(\S*'),
    // Extended public/private keys of every SLIP-132 flavour.
    RegExp(r'\b[xyzYZtuvUV](?:pub|prv)[1-9A-HJ-NP-Za-km-z]{100,}'),
    // WIF private keys (mainnet 5/K/L, testnet 9/c).
    RegExp(r'\b[5KLc9][1-9A-HJ-NP-Za-km-z]{50,51}\b'),
  ];

  static final List<RegExp> _addressPatterns = [
    // Lightning addresses and e-mail addresses.
    RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
    // Any bech32/bech32m string: bc1/tb1/bcrt1 addresses, Spark (sp1,
    // sprt1, spark1), bolt11 invoices (lnbc…), bolt12 offers, lnurl1…,
    // either case (QR form is upper case).
    // The human-readable part may carry digits (lnbc2500u…).
    RegExp(r'\b[A-Za-z][A-Za-z0-9]{1,15}1[QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L]{20,}\b',
        caseSensitive: false),
    // Legacy/P2SH/testnet base58 addresses.
    RegExp(r'\b[123mn][1-9A-HJ-NP-Za-km-z]{25,34}\b'),
    // EVM addresses.
    RegExp(r'\b0x[0-9a-fA-F]{40}\b'),
  ];

  // Private keys and tx hashes in hex. Public market ids use the same
  // shape (Polymarket condition ids), so the keys that carry one are exempt
  // from this single rule and from nothing else.
  static final RegExp _hex64 = RegExp(r'\b(?:0x)?[0-9a-fA-F]{64}\b');
  static const Set<String> _publicHexKeys = {
    'market_id',
    'condition_id',
    'market_slug',
    'token_id',
  };

  // UUIDs (order, session, request and device ids). The device UUID is
  // the pseudonymous identity itself, so the keys that carry it on
  // purpose are exempt from this rule only.
  static final RegExp _uuid = RegExp(
      r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b');
  static const Set<String> _uuidKeys = {'device_uuid'};

  // URLs keep scheme and host only: paths and queries carry tokens,
  // addresses, usernames and order ids.
  static final RegExp _url =
      RegExp(r"""\b(?:https?|wss?)://[^\s"'<>]+""", caseSensitive: false);
  static final RegExp _urlTrailingPunctuation = RegExp(r'[).,;:\]!?]+$');

  static String _redactUrls(String s) {
    if (!s.contains('://')) return s;
    return s.replaceAllMapped(_url, (m) {
      var token = m[0]!;
      final trailing = _urlTrailingPunctuation.firstMatch(token)?.group(0) ?? '';
      token = token.substring(0, token.length - trailing.length);
      final uri = Uri.tryParse(token);
      final scheme = token.substring(0, token.indexOf('://')).toLowerCase();
      if (uri == null || uri.host.isEmpty) return '$scheme://$redacted$trailing';
      final hasMore = (uri.path.isNotEmpty && uri.path != '/') ||
          uri.hasQuery ||
          uri.hasFragment;
      return '$scheme://${uri.host}${hasMore ? '/…' : ''}$trailing';
    });
  }

  static String _redactKeyMaterial(String s) {
    var out = s;
    for (final re in _keyMaterialPatterns) {
      out = out.replaceAll(re, redacted);
    }
    return out;
  }

  /// Redacts key material, addresses, invoices and BIP39 phrases from one
  /// string. Unlike [safeReason] it keeps ordinary text and length intact,
  /// so market titles, symbols and categories survive.
  ///
  /// Also: URLs keep scheme + host only, and UUIDs are redacted unless
  /// [keepUuids] (the Crashlytics user id and `device_uuid` only).
  static String scrubString(String s,
      {bool allowPublicHex = false, bool keepUuids = false}) {
    if (s.length < 20 &&
        !s.contains('@') &&
        !s.contains(' ') &&
        !s.contains('://')) {
      return s;
    }
    var out = _redactUrls(s);
    out = _redactKeyMaterial(out);
    if (!keepUuids) out = out.replaceAll(_uuid, redacted);
    for (final re in _addressPatterns) {
      out = out.replaceAll(re, redacted);
    }
    if (!allowPublicHex) out = out.replaceAll(_hex64, redacted);
    // A recovery phrase is 12+ words; shorter runs of common English words
    // (market titles) must survive, so the bar here is a whole phrase.
    if (out.contains(' ')) {
      out = _redactSeedWordRuns(out, minRun: 12)
          .replaceAll('<words>', redacted);
    }
    return out;
  }

  /// Recursively scrubs every string in a property value (maps, lists).
  @visibleForTesting
  static Object? scrubValue(Object? value, {String? key}) {
    if (value is String) {
      return scrubString(value,
          allowPublicHex: key != null && _publicHexKeys.contains(key),
          keepUuids: key != null && _uuidKeys.contains(key));
    }
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key: scrubValue(e.value, key: e.key is String ? e.key as String : null),
      };
    }
    if (value is List) return [for (final v in value) scrubValue(v, key: key)];
    return value;
  }

  /// [scrubValue] over a property map, keeping its type.
  @visibleForTesting
  static Map<String, Object> scrubProperties(Map<String, Object> props) => {
        for (final e in props.entries)
          e.key: scrubValue(e.value, key: e.key) ?? e.value,
      };

  // ─── Exact money properties ──────────────────────────────────────
  //
  // Founder decision (2026-09): money OUTCOME events carry exact values
  // beside the legacy buckets (kept so dashboards do not break):
  // amount_usd (2 dp), amount (native units) + asset, currency/amount_fiat
  // for fiat-entered flows, and the fee the USER SAW before confirming as
  // fee_shown_usd + fee_shown_basis (shown_at_quote | network_fee). These
  // are UX analytics, never Kute revenue: revenue reaches PostHog only from
  // the database through the warehouse sync, and no app event carries it
  // or an estimate of it. Never balances, addresses, txids, order ids or
  // keys.

  static double _round(double v, int dp) {
    final f = pow(10, dp);
    return (v * f).roundToDouble() / f;
  }

  static int _assetDecimals(String? asset) {
    switch ((asset ?? '').toLowerCase()) {
      case 'btc':
      case 'sats':
        return 8;
      default:
        return 6;
    }
  }

  /// Exact money properties for an outcome event. Null/non-finite values
  /// are dropped. [amountUsd] also emits the legacy `amount_bucket`.
  /// [feeUsd] is the fee shown to the user (`fee_shown_usd`); [feeBasis]
  /// becomes `fee_shown_basis`.
  static Map<String, Object> moneyParams({
    double? amountUsd,
    double? amount,
    String? asset,
    int? amountSats,
    String? currency,
    double? amountFiat,
    double? feeUsd,
    double? networkFeeUsd,
    int? feeSats,
    String? feeTier,
    String feeBasis = 'shown_at_quote',
  }) {
    bool ok(double? v) => v != null && v.isFinite;
    return {
      if (ok(amountUsd)) 'amount_usd': _round(amountUsd!, 2),
      if (ok(amountUsd)) 'amount_bucket': _usdBucket(amountUsd!),
      if (ok(amount)) 'amount': _round(amount!, _assetDecimals(asset)),
      if (asset != null) 'asset': asset.toLowerCase(),
      if (amountSats != null) 'amount_sats': amountSats,
      if (currency != null) 'currency': currency.toUpperCase(),
      if (ok(amountFiat)) 'amount_fiat': _round(amountFiat!, 2),
      if (ok(feeUsd)) 'fee_shown_usd': _round(feeUsd!, 2),
      if (ok(networkFeeUsd)) 'network_fee_usd': _round(networkFeeUsd!, 2),
      if (feeSats != null) 'fee_sats': feeSats,
      if (feeTier != null) 'fee_tier': feeTier,
      if (ok(feeUsd) || ok(networkFeeUsd) || feeSats != null)
        'fee_shown_basis': feeBasis,
    };
  }

  /// Leverage bucket for dashboards ('1x' .. '21x+').
  static String leverageBucket(int lev) {
    if (lev <= 1) return '1x';
    if (lev <= 3) return '2-3x';
    if (lev <= 5) return '4-5x';
    if (lev <= 10) return '6-10x';
    if (lev <= 20) return '11-20x';
    return '21x+';
  }

  /// Activation: the first completed money action on this install. Emits
  /// `first_money_action` once and stamps the `first_money_action_at`
  /// person property. [action]: send | receive | swap | buy | bet |
  /// hl_order | deposit. Call from money OUTCOME helpers only.
  static void markMoneyAction(String action, {String? venue}) {
    if (!OnceFlagsService.claimOnce('first_money_action')) return;
    final now = DateTime.now().toUtc().toIso8601String();
    setUserProperty('first_money_action_at', now);
    setUserProperty('first_money_action', action);
    track('first_money_action', params: {
      'action': action,
      if (venue != null) 'venue': venue,
    });
  }

  /// Wrap a thrown error so downstream sinks (PostHog Error Tracking,
  /// the legacy Firebase Crashlytics fallback) receive only the
  /// runtime type + a scrubbed message. Raw `error.toString()` from
  /// Breez, BDK, and our own SDK adapters frequently inlines
  /// descriptor fragments, UTXO ids, deposit addresses, and LN
  /// invoices into the message body — all of which would land in
  /// the issue title verbatim. Returning a fresh exception means
  /// grouping by runtimeType (still meaningful) while the leaky
  /// payload stays on the device.
  static Object sanitizedErrorEnvelope(Object error) {
    final type = error.runtimeType.toString();
    final scrubbed = _safeReason(error.toString()) ?? '';
    return _SanitizedError(type, scrubbed);
  }

  /// Record a crash to Firebase Crashlytics (the single crash backend —
  /// PostHog is product-analytics only now). Crashes are NOT gated on the
  /// product-analytics opt-in (`_disabled`); they're gated only on debug
  /// builds + Crashlytics' own `setCrashlyticsCollectionEnabled`. We send a
  /// SANITIZED error object (real type name + PII-scrubbed message) with the
  /// FULL real stack trace, so addresses / invoices / amounts never leave the
  /// device while the stack (the part that matters) stays intact.
  ///
  /// [information] is extra context (e.g. FlutterError's "while building
  /// X"); every line is scrubbed like error text (no amounts, long
  /// numbers, URLs paths, addresses) and capped.
  static void recordCrash(Object error, StackTrace? stack,
      {String? reason, bool fatal = false, Iterable<String>? information}) {
    // Everything Crashlytics receives passes the shared redactor: the
    // message (via the envelope), the reason, the breadcrumb log line and
    // the stack text (frames keep their shape; only a key, address or
    // invoice interpolated into one is replaced).
    final envelope = sanitizedErrorEnvelope(error);
    final safeStack =
        stack == null ? null : StackTrace.fromString(scrubString(stack.toString()));
    final safeReason = _safeReason(reason);
    final log = _breadcrumbs.isEmpty
        ? null
        : scrubString('route: ${_breadcrumbs.join(' > ')}');
    final safeInformation = <String>[
      for (final line in information ?? const <String>[])
        if (line.trim().isNotEmpty) scrubErrorText(line, maxLength: 200),
    ];
    debugCrashObserver?.call(envelope, safeStack, safeReason, log);
    debugCrashExtrasObserver?.call(safeInformation, fatal);
    if (kDebugMode) return;
    try {
      if (log != null) FirebaseCrashlytics.instance.log(log);
      FirebaseCrashlytics.instance.recordError(
        envelope,
        safeStack,
        reason: safeReason,
        information: safeInformation,
        fatal: fatal,
      );
    } catch (_) {/* Crashlytics not ready — boot-time race; safe to drop */}
  }

  /// Scrubs free error text (exception messages, crash context lines)
  /// with every error-text rule: the shared redactor, then the stricter
  /// [safeReason] rules (hex runs, amounts, long numbers), capped at
  /// [maxLength].
  static String scrubErrorText(String raw, {int maxLength = 200}) {
    var s = scrubString(raw);
    s = s.replaceAll(RegExp(r'\b(?:0x)?[0-9a-fA-F]{12,}\b'), '<hex>');
    s = _redactSeedWordRuns(s);
    s = redactErrorNumbers(s);
    if (s.length > maxLength) s = '${s.substring(0, maxLength - 3)}...';
    return s;
  }

  /// Test-only tap on exactly what [recordCrash] hands Crashlytics.
  @visibleForTesting
  static void Function(Object error, StackTrace? stack, String? reason,
      String? log)? debugCrashObserver;

  /// Test-only tap on [recordCrash]'s scrubbed `information` and `fatal`.
  @visibleForTesting
  static void Function(List<String> information, bool fatal)?
      debugCrashExtrasObserver;

  // ─── Handled failures → Crashlytics non-fatals ───────────────────
  //
  // A failure the user cannot cause (our bug, a provider/settlement
  // problem, a hardware-wallet transport failure, a route or quote the
  // backend rejected) is worth an issue even though the UI handled it.
  // User-side categories (cancelled, insufficient funds, below minimum,
  // invalid destination, network, timeout, …) are product signal only
  // and stay in PostHog. Deduped per session so one broken provider
  // can't flood Crashlytics.

  static const Set<String> handledCrashCategories = {
    'unknown',
    'settlement',
    'hardware_wallet',
    'no_route',
    'quote_rejected',
  };
  static const int _handledMax = 20;
  static final Set<String> _handledSeen = <String>{};

  /// Records a handled, non-user failure as a Crashlytics non-fatal.
  /// [category] is an [errorCategories] value (anything else is
  /// classified with [errorCategory]); only [handledCrashCategories] are
  /// recorded. Deduped per session on category + flow + stage + error
  /// type, at most 20 per session. Returns whether it was recorded.
  static bool recordHandled(
    String category,
    Object? error,
    StackTrace? stackTrace, {
    String? flow,
    String? stage,
  }) {
    try {
      var cat = errorCategory(category);
      if (cat.startsWith('settlement_')) cat = 'settlement';
      if (!handledCrashCategories.contains(cat)) return false;
      if (_handledSeen.length >= _handledMax) return false;
      final type = error == null ? 'none' : error.runtimeType.toString();
      final key = '$cat|${flow ?? ''}|${stage ?? ''}|$type';
      if (!_handledSeen.add(key)) return false;
      final ctx = [
        if (flow != null) 'flow=${_contextValue(flow)}',
        if (stage != null) 'stage=${_contextValue(stage)}',
        'category=$cat',
      ].join(' ');
      recordCrash(
        error is String || error == null
            ? HandledFailure(cat, flow: flow, stage: stage)
            : error,
        stackTrace ?? StackTrace.current,
        reason: 'handled $ctx',
        information: [
          'handled: $ctx',
          if (error is String) 'detail: $error',
          ...crashContextLines(),
        ],
        fatal: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void debugResetHandled() => _handledSeen.clear();

  /// Crashlytics user id: pseudonymous only (the device UUID, else 'unknown'),
  /// scrubbed so an address or key can never become the identifier.
  static String crashlyticsUserId(String id) {
    final scrubbed = scrubString(id, keepUuids: true);
    return scrubbed.contains(redacted) ? 'redacted' : scrubbed;
  }

  // ─── Crash Breadcrumbs ───────────────────────────────────────────
  //
  // Fixed-size ring buffer of the last [_breadcrumbMax] screen NAMES the
  // user visited. Names only — no params, amounts, or ids — so the trail
  // is PII-free per the hard rule. Fed by a NavigatorObserver in
  // app_widget.dart and read by [recordCrash] to give each Issue a
  // navigation trail.
  static const int _breadcrumbMax = 15;
  static final List<String> _breadcrumbs = <String>[];

  /// Append a screen name to the crash breadcrumb ring buffer. Caps at
  /// [_breadcrumbMax] (drops oldest). Pass screen NAMES only — never
  /// event params. Called from the NavigatorObserver in app_widget.dart.
  static void pushBreadcrumb(String screenName) {
    if (screenName.isEmpty) return;
    _breadcrumbs.add(screenName);
    if (_breadcrumbs.length > _breadcrumbMax) {
      _breadcrumbs.removeAt(0);
    }
  }

  // ─── Crash context: current screen / flow / step ─────────────────
  //
  // What the user was doing when the app died. Kept in memory for crash
  // markers raised in this session (unhandled_exception_caught), mirrored
  // into Crashlytics custom keys (release only), and persisted (throttled)
  // to the small `crash_context` Hive box so a native crash, ANR or OOM
  // kill that bypasses every Dart handler can still be attributed on the
  // NEXT launch (app_crash_detected / app_previous_exit_abnormal).
  // Categorical values only: names, never amounts, ids or addresses.

  static const String crashContextBox = 'crash_context';
  static const String _snapshotKey = 'snapshot';
  static const Duration _persistThrottle = Duration(seconds: 1);

  static String? _lastScreen;
  static String? _shellTab;
  static String? _flow;
  static String? _step;
  static String? _venue;
  static String? _network;
  static String? _walletKind;
  static String? _appVersion;
  static Map<String, Object?>? _previousSnapshot;
  static Box<dynamic>? _crashBox;
  static Timer? _persistTimer;
  static DateTime? _lastPersist;
  static final Map<String, Object> _crashKeys = {};

  /// Categorical context values: scrubbed, trimmed, capped at 64 chars.
  static String _contextValue(String v) {
    final s = scrubString(v.trim());
    return s.length > 64 ? s.substring(0, 64) : s;
  }

  /// Start (or replace) the flow the user is in. Call at `<flow>_started`
  /// and whenever a new flow takes over. Any venue/network/wallet_kind
  /// from a previous flow is dropped. [flow] is the event prefix
  /// (send, receive, swap, polymarket_bet, hl_order, …); [step] the
  /// current step name (same vocabulary as `<flow>_step`).
  static void setFlowContext({
    required String flow,
    String? step,
    String? venue,
    String? network,
    String? walletKind,
  }) {
    _flow = _contextValue(flow);
    _step = step == null ? null : _contextValue(step);
    _venue = venue == null ? null : _contextValue(venue);
    _network = network == null ? null : _contextValue(network);
    _walletKind = walletKind == null ? null : _contextValue(walletKind);
    _setCrashKey('flow', _flow);
    _setCrashKey('step', _step);
    _setCrashKey('venue', _venue);
    _setCrashKey('network', _network);
    _setCrashKey('wallet_kind', _walletKind);
    _schedulePersist();
  }

  /// Move the current flow to [step] (a real step transition only).
  static void setFlowStep(String step) {
    final v = _contextValue(step);
    if (v == _step) return;
    _step = v;
    _setCrashKey('step', _step);
    _schedulePersist();
  }

  /// Leave [flow] (completed, failed or abandoned). A no-op when another
  /// flow has since taken over, so a late dispose can't wipe it.
  static void clearFlowContext(String flow) {
    if (_flow == null || _flow != _contextValue(flow)) return;
    _flow = _step = _venue = _network = _walletKind = null;
    for (final k in const ['flow', 'step', 'venue', 'network', 'wallet_kind']) {
      _setCrashKey(k, null);
    }
    _schedulePersist();
  }

  /// Route/screen hook: the screen now on top (GoRoute name or the shell
  /// tab's route name). Fed from app_widget.dart's route tracking.
  static void recordScreen(String? name) {
    if (name == null || name.isEmpty) return;
    final v = _contextValue(name);
    if (v == _lastScreen) return;
    _lastScreen = v;
    _setCrashKey('route', v);
    _schedulePersist();
  }

  /// The nav-shell tab on screen (home, usd, predictions, trading, …).
  static void setShellTab(String tab) {
    final v = _contextValue(tab);
    if (v == _shellTab) return;
    _shellTab = v;
    _setCrashKey('shell_tab', v);
    _schedulePersist();
  }

  /// Once-per-session Crashlytics keys (breez_connected, backend_reachable,
  /// locale, low_ram). Release-gated, deduped on value, never throws.
  static void setSessionKey(String key, Object value) =>
      _setCrashKey(key, value is String ? _contextValue(value) : value);

  static void _setCrashKey(String key, Object? value) {
    final v = value ?? '';
    if (_crashKeys[key] == v) return;
    _crashKeys[key] = v;
    debugCrashlyticsObserver?.call('key', key, v);
    if (kDebugMode) return;
    try {
      unawaited(FirebaseCrashlytics.instance
          .setCustomKey(key, v)
          .catchError((Object _) {}));
    } catch (_) {/* Crashlytics not ready */}
  }

  /// Test-only tap on Crashlytics custom keys ('key') and log lines ('log').
  @visibleForTesting
  static void Function(String kind, String name, Object? value)?
      debugCrashlyticsObserver;

  /// The current session's crash context (always every field; 'none'
  /// when no flow is active, 'unknown' when not known yet).
  static Map<String, String> get crashContext => {
        'last_screen': _lastScreen ?? 'unknown',
        'last_flow': _flow ?? 'none',
        'last_step': _step ?? 'none',
        'app_version': _appVersion ?? 'unknown',
      };

  /// The snapshot persisted by the PREVIOUS session (null on first run or
  /// when it could not be read). Loaded once by [initialize].
  static Map<String, Object?>? get previousSessionSnapshot => _previousSnapshot;

  /// Crash context as Crashlytics `information` lines.
  static List<String> crashContextLines() => [
        for (final e in crashContext.entries) '${e.key}: ${e.value}',
        if (_shellTab != null) 'shell_tab: $_shellTab',
        if (_venue != null) 'venue: $_venue',
        if (_network != null) 'network: $_network',
        if (_walletKind != null) 'wallet_kind: $_walletKind',
      ];

  /// Properties every crash marker event carries. [crashType]:
  /// native_crash | anr | oom | dart_fatal | dart_nonfatal. With
  /// [snapshot] (a previous session's), last_* come from it and its
  /// version is sent as `crashed_app_version`; `app_version` is always
  /// the running build's.
  static Map<String, Object> crashMarkerParams({
    required String crashType,
    required String errorClass,
    Map<String, Object?>? snapshot,
  }) {
    String pick(String key, String fallback) {
      final v = snapshot?[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    final current = crashContext;
    return {
      'crash_type': crashType,
      'error_class': _contextValue(errorClass),
      if (snapshot == null) ...current,
      if (snapshot != null) ...{
        'last_screen': pick('last_screen', 'unknown'),
        'last_flow': pick('last_flow', 'none'),
        'last_step': pick('last_step', 'none'),
        'app_version': current['app_version']!,
        'crashed_app_version': pick('app_version', 'unknown'),
        if (snapshot['shell_tab'] is String) 'shell_tab': snapshot['shell_tab']!,
        if (snapshot['venue'] is String) 'venue': snapshot['venue']!,
        if (snapshot['network'] is String) 'network': snapshot['network']!,
        if (snapshot['wallet_kind'] is String)
          'wallet_kind': snapshot['wallet_kind']!,
      },
      if (snapshot == null && _shellTab != null) 'shell_tab': _shellTab!,
    };
  }

  static Map<String, Object?> _snapshot() => {
        'last_screen': _lastScreen,
        'last_flow': _flow,
        'last_step': _step,
        'app_version': _appVersion,
        'shell_tab': _shellTab,
        'venue': _venue,
        'network': _network,
        'wallet_kind': _walletKind,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

  /// Opens the crash-context box, keeps the previous session's snapshot in
  /// [previousSessionSnapshot], then starts persisting this session's.
  /// Called from [initialize] (Hive is initialised by then); never throws.
  @visibleForTesting
  static Future<void> initCrashContext({String? appVersion}) async {
    if (appVersion != null) _appVersion = appVersion;
    if (_appVersion == null) {
      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {}
    }
    _setCrashKey('app_version', _appVersion);
    try {
      final box = Hive.isBoxOpen(crashContextBox)
          ? Hive.box<dynamic>(crashContextBox)
          : await Hive.openBox<dynamic>(crashContextBox);
      final prev = box.get(_snapshotKey);
      if (prev is Map) {
        _previousSnapshot = {
          for (final e in prev.entries) e.key.toString(): e.value,
        };
      }
      _crashBox = box;
      await _persistNow();
    } catch (_) {/* no crash context this session; never block boot */}
  }

  static void _schedulePersist() {
    if (_crashBox == null || _persistTimer != null) return;
    final last = _lastPersist;
    final wait = last == null
        ? Duration.zero
        : _persistThrottle - DateTime.now().difference(last);
    if (wait <= Duration.zero) {
      unawaited(_persistNow());
      return;
    }
    _persistTimer = Timer(wait, () {
      _persistTimer = null;
      unawaited(_persistNow());
    });
  }

  static Future<void> _persistNow() async {
    final box = _crashBox;
    if (box == null) return;
    _lastPersist = DateTime.now();
    try {
      await box.put(_snapshotKey, _snapshot());
    } catch (_) {}
  }

  /// Test-only: write the pending snapshot now.
  @visibleForTesting
  static Future<void> debugFlushCrashContext() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistNow();
  }

  /// Test-only: forget all crash context (simulates a fresh process).
  @visibleForTesting
  static void debugResetCrashContext() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _lastPersist = null;
    _crashBox = null;
    _previousSnapshot = null;
    _lastScreen = _shellTab = _flow = _step = null;
    _venue = _network = _walletKind = _appVersion = null;
    _crashKeys.clear();
  }

  // Categorical Crashlytics breadcrumbs from track(): the event name and
  // whitelisted categorical properties only. Never amounts or ids.
  static const List<String> _breadcrumbProps = [
    'flow', 'stage', 'step', 'venue', 'network', 'wallet_kind',
    'error_category', 'outcome', 'provider', 'asset',
  ];

  static void _crashlyticsBreadcrumb(String event, Map<String, Object>? params) {
    final b = StringBuffer(event);
    if (params != null) {
      for (final k in _breadcrumbProps) {
        final v = params[k];
        if (v is String && v.isNotEmpty) b.write(' $k=${_contextValue(v)}');
      }
    }
    final line = b.toString();
    debugCrashlyticsObserver?.call('log', event, line);
    if (kDebugMode) return;
    try {
      unawaited(
          FirebaseCrashlytics.instance.log(line).catchError((Object _) {}));
    } catch (_) {/* Crashlytics not ready */}
  }

  /// PostHog `beforeSend` hook (registered in `_initPostHog`). Strips the
  /// human-readable message out of every `$exception` event so addresses,
  /// invoices, xpubs, and typed seeds that Breez / BDK / our SDK adapters
  /// inline into `error.toString()` never leave the device.
  ///
  /// The exception TYPE (runtimeType) and the stack frames are left
  /// intact: Error Tracking groups Issues by those and they are never
  /// PII. Handles both the structured `$exception_list` payload that
  /// `captureException` produces and any legacy flat `$exception_message`
  /// prop, so it stays correct even if a caller emits the old shape.
  static PostHogEvent? sanitizeExceptionEvent(PostHogEvent event) {
    final props = event.properties;
    if (props == null) return event;
    if (event.event != r'$exception') {
      // Every other event, including SDK-built ones ($screen, $set,
      // $identify): scrub app properties and person-property maps, but
      // leave the SDK's own `$` bookkeeping (session/device ids) alone.
      for (final key in props.keys.toList()) {
        if (key.startsWith(r'$') &&
            key != r'$set' &&
            key != r'$set_once' &&
            key != r'$screen_name') {
          continue;
        }
        final value = props[key];
        if (value != null) props[key] = scrubValue(value, key: key) ?? value;
      }
      return event;
    }

    // PostHog is not the error monitor (Crashlytics is): an exception that
    // reaches it keeps only its class. Message and stack never leave.
    final list = props[r'$exception_list'];
    if (list is List) {
      for (final entry in list) {
        if (entry is Map) {
          entry['value'] = '';
          entry.remove('stacktrace');
        }
      }
    }
    props.remove(r'$exception_message');
    props.remove(r'$exception_stack_trace_raw');
    return event;
  }

  /// Log a named event with optional parameters.
  ///
  /// Offline-safe: every PostHog primitive is wrapped in try/catch so
  /// a network failure / SDK-not-ready / corrupted-payload condition
  /// can never throw into the call site. The SDK itself buffers
  /// events to disk and retries on the next online window, so dropped
  /// events recover automatically; the try/catch is belt-and-suspenders
  /// for anything the SDK doesn't handle gracefully.
  static void track(String event, {Map<String, Object>? params}) {
    params = sanitizeParams(params);
    if (params != null) params = scrubProperties(params);
    debugTrackObserver?.call(event, params);
    // Crash breadcrumb (categorical only). Crash reporting is not covered
    // by the analytics opt-out (privacy policy §6.3), so this runs first.
    _crashlyticsBreadcrumb(event, params);
    if (_muted) return;
    if (isCompletedMoneyAction(event, params)) _recordMoneyAction();
    try {
      Posthog().capture(eventName: event, properties: params);
    } catch (_) {/* never crash on tracking */}
  }

  /// Property keys whose raw value identifies an order, payment or claim.
  /// A provider order id, quote id or claim id is joinable to a person's
  /// money on the provider's side, so the raw value never leaves; the key
  /// keeps its name (dashboards already group by it) and carries a stable
  /// one-way reference instead. The same order always yields the same
  /// reference, which is what dashboards need to count each order once.
  static const Set<String> _orderRefKeys = {
    'order_id',
    'provider_order_id',
    'quote_id',
    'claim_id',
    // The database join keys (see [orderJoinParams]).
    'order_ref',
    'quote_ref',
  };

  /// Replaces raw order/quote/claim ids in [params] with [orderRef]. Every
  /// [track] call goes through this, so no call site can leak one.
  @visibleForTesting
  static Map<String, Object>? sanitizeParams(Map<String, Object>? params) {
    if (params == null) return null;
    if (!params.keys.any(_orderRefKeys.contains)) return params;
    return {
      for (final e in params.entries)
        e.key: _orderRefKeys.contains(e.key) && e.value is String
            ? orderRef(e.value as String)
            : e.value,
    };
  }

  /// Stable, one-way reference for an order/quote/claim id: the first 16
  /// hex chars of a namespaced SHA-256. Idempotent: a value that already
  /// is a reference is returned unchanged.
  ///
  /// It is also the database join key: the backend stores the same value in
  /// `who_did_what.order_ref`, so a money event's `order_ref` / `quote_ref`
  /// joins to its row. Shared test vectors (the backend asserts the same):
  /// `ord_01J8ZK4M7Q2X9V3T5R6W8Y0ABC` -> `ref_504973ad6ad3e596`,
  /// `quote_01J8ZK4M7Q2X9V3T5R6W8Y0ABC` -> `ref_8c85af203cbafb1d`,
  /// `é` -> `ref_9abda7604872f36a`. Keep the format exactly as it is.
  static String orderRef(String id) {
    if (id.isEmpty || id.startsWith('ref_')) return id;
    final digest =
        sha256.convert(utf8.encode('kute:analytics-order-ref:v1\u0000$id'));
    return 'ref_${digest.toString().substring(0, 16)}';
  }

  /// `order_ref` for a provider order id (Polymarket CLOB order id, or any
  /// non-Orchestra provider id), or nothing when there is none.
  static Map<String, Object> orderJoinParams(String? providerOrderId) =>
      providerOrderId == null || providerOrderId.isEmpty
          ? const {}
          : {'order_ref': orderRef(providerOrderId)};

  /// Join keys for an Orchestra id: `order_ref` for a real order (`ord_…`),
  /// `quote_ref` for a quote (`q_…`, when the order id is not known yet).
  /// [quoteId] (a known quote id) adds `quote_ref`. Synthetic local ids
  /// (`acu-…`) carry nothing: the database never saw them.
  static Map<String, Object> orchestraJoinParams(String? id, {String? quoteId}) {
    final params = <String, Object>{};
    if (id != null && id.startsWith('ord_')) params['order_ref'] = orderRef(id);
    if (id != null && id.startsWith('q_')) params['quote_ref'] = orderRef(id);
    if (quoteId != null && quoteId.isNotEmpty) {
      params.putIfAbsent('quote_ref', () => orderRef(quoteId));
    }
    return params;
  }

  /// Log a screen view (the `PosthogObserver` on GoRouter autocaptures
  /// these, but call this manually for non-routed surfaces).
  static void screenView(String screenName, {String? screenClass}) {
    if (_muted) return;
    try {
      Posthog().screen(
        screenName: scrubString(screenName),
        properties: {
          if (screenClass != null) 'screen_class': screenClass,
        },
      );
    } catch (_) {/* never crash on tracking */}
  }

  // Person-property writes are coalesced: at startup ~20 of these fire
  // back-to-back (splash + init + profile), and one `$set` event PER
  // property floods the event stream ("Set person properties" x20). We
  // buffer them and flush a SINGLE `$set` carrying every property on a
  // short debounce instead.
  static final Map<String, Object> _pendingUserProps = {};
  static Timer? _userPropsFlushTimer;

  /// Set a person property for segmentation. Applied to whichever
  /// distinct_id is currently active (anonymous pre-identify, then
  /// the affiliate_code post-identify; PostHog aliases the events).
  /// Coalesced — see [_pendingUserProps].
  static void setUserProperty(String name, String value) =>
      setUserPropertyValue(name, value);

  /// [setUserProperty] for a typed value: a bool, a number, a string or a
  /// list of strings, so PostHog stores booleans and counters as such
  /// (filters and cohorts on `true` / `>= 3` then work without casts).
  /// Coalesced into the same single `$set` batch.
  static void setUserPropertyValue(String name, Object value) {
    if (_muted) return;
    _pendingUserProps[name] = value;
    _userPropsFlushTimer?.cancel();
    _userPropsFlushTimer =
        Timer(const Duration(milliseconds: 500), _flushUserProperties);
  }

  static void _flushUserProperties() {
    _userPropsFlushTimer = null;
    if (_pendingUserProps.isEmpty || _muted) return;
    final batch = scrubProperties(Map<String, Object>.from(_pendingUserProps));
    _pendingUserProps.clear();
    try {
      Posthog().capture(
        eventName: r'$set',
        properties: {r'$set': batch},
      );
    } catch (_) {/* never crash on tracking */}
  }

  /// Identify a user. Prefer [identifyWithAffiliate] — this overload
  /// is kept for legacy callers and routes through PostHog identify
  /// with whatever id the caller passes.
  static void identify(String userId) {
    if (_muted) return;
    if (userId.isEmpty) return;
    try {
      Posthog().identify(userId: userId);
    } catch (_) {/* never crash on tracking */}
  }

  // ─── Fintech Event Helpers ───────────────────────────────────────

  // -- Onboarding Funnel --

  static void onboardingStarted() => track('onboarding_started');

  static void onboardingCtaTapped(String cta) {
    track('onboarding_cta_tapped', params: {'cta': cta});
  }

  static void onboardingCompleted({String? authMode, int? durationSeconds}) {
    track('onboarding_completed', params: {
      if (authMode != null) 'auth_mode': authMode,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    });
  }

  /// Funnel start: the first-run welcome screen, once per install. Every
  /// re-visit of /start (back from set PIN, a failed restore) is the same
  /// funnel, so it must not restart it.
  static void onboardingStartedOnce() {
    if (OnceFlagsService.claimOnce('onboarding_started')) onboardingStarted();
  }

  /// Funnel end, once per install, whichever path finishes it (create via
  /// the referrer screen or share screen, or a first-wallet restore). An
  /// extra wallet added later is not onboarding.
  static void onboardingCompletedOnce({String? authMode}) {
    if (OnceFlagsService.claimOnce('onboarding_completed')) {
      onboardingCompleted(authMode: authMode);
    }
  }

  static void pinEntryStarted() => track('pin_entry_started');

  static void pinConfirmed() => track('pin_confirmed');

  static void pinSet() => track('pin_set');

  // -- Wallet Lifecycle --

  static void walletCreated({
    required String
        type, // 'hot', 'imported', 'signer', 'hardware', 'watch_only', 'external_address'
    String? hardwareDevice, // 'ledger', 'jade', 'keystone', etc.
    String?
        authMode, // 'passkey', 'mnemonic', 'imported', 'signer', 'watch_only'
  }) {
    track('wallet_created', params: {
      'type': type,
      if (hardwareDevice != null) 'hardware_device': hardwareDevice,
      if (authMode != null) 'auth_mode': authMode,
    });
    // AppsFlyer registration milestone (once per device, gated inside).
    AppsFlyerService.completeRegistration(method: type);
  }

  static void walletAddStarted() => track('wallet_add_started');

  static void walletAddFailed({String? reason, String? errorCode}) {
    track('wallet_add_failed', params: {
      if (reason != null) 'reason': _safeReason(reason)!,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void walletWiped({int? walletCount, bool? wasPasskey}) {
    track('wallet_wiped', params: {
      if (walletCount != null) 'wallet_count': walletCount,
      if (wasPasskey != null) 'was_passkey': wasPasskey,
    });
  }

  // -- Backup & Security --

  static void backupCompleted() => track('backup_completed');

  // -- Backup Safety Funnel (Phase 2) --
  // Parameterless by policy: these call sites sit next to the user's
  // mnemonic in memory, so the safest payload is no payload (mirrors
  // backupRevealViewed's policy note). Funnel = shown → started →
  // completed → verified, with skipped as the drop-off branch.

  /// The "Back up your recovery phrase" prompt/banner became visible.
  static void backupPromptShown() => track('backup_prompt_shown');

  static final Set<String> _backupPromptSeen = {};

  /// The backup reminder actually rendered on [surface] (home |
  /// wallet_detail). Once per surface+wallet per app session: the card
  /// remounts on every Home rebuild and sliver scroll, which counted one
  /// sighting many times, and it used to fire even when it rendered nothing.
  static void backupPromptShownOnce({
    required String surface,
    required String walletKey,
  }) {
    if (!_backupPromptSeen.add('$surface:$walletKey')) return;
    track('backup_prompt_shown', params: {'surface': surface});
  }

  /// The user tapped the backup reminder on [surface].
  static void backupPromptTapped({required String surface}) =>
      track('backup_prompt_tapped', params: {'surface': surface});

  /// User entered the backup flow (tapped through from the prompt).
  static void backupStarted() => track('backup_started');

  /// User finished writing down / acknowledging the recovery phrase.
  /// Also flips the `is_backed_up` person property to true.
  static void backupCompletedFunnel() {
    track('backup_completed');
    setUserProperty('is_backed_up', 'true');
  }

  /// User passed the verification quiz confirming they saved the phrase.
  static void backupVerified() => track('backup_verified');

  /// User dismissed / postponed the backup prompt without completing.
  static void backupSkipped() => track('backup_skipped');

  /// The whole recovery phrase was copied. [surface] is the screen
  /// ('seed_words', 'backup_wallet' or 'wallets'); never the phrase or its
  /// length.
  static void seedPhraseCopied({required String surface}) =>
      track('seed_phrase_copied', params: {'surface': surface});

  static void seedBackupPromptResponse(String decision) {
    track('seed_backup_prompt_response', params: {'decision': decision});
  }

  /// Post-PIN iCloud / cloud-backup choice screen viewed.
  static void cloudBackupChoiceViewed() {
    screenView('CloudBackupChoice');
    track('cloud_backup_choice_viewed');
  }

  /// User accepted (toggle ON) iCloud / cloud backup on the choice
  /// screen. [platform] is `ios` or `android` so we can split funnels.
  static void cloudBackupAccepted({required String platform}) {
    track('cloud_backup_accepted', params: {'platform': platform});
  }

  /// User declined (toggle OFF) — they take ownership of the seed.
  static void cloudBackupDeclined({required String platform}) {
    track('cloud_backup_declined', params: {'platform': platform});
  }

  /// Recovery-phrase reveal sub-step of /backup_wallet (the new
  /// "show seed → then quiz" flow). Fires when the user lands on the
  /// reveal step.
  ///
  /// POLICY — NEVER ADD A PARAMETER HERE. This call site sits next to
  /// the user's mnemonic in memory; anything we pass in could be a
  /// developer accidentally derivative of seed material (length,
  /// first-letter histogram, hash of the words, etc.). Keep the
  /// event payload empty so the worst-case mistake is a duplicate
  /// event, not a leaked seed.
  static void backupRevealViewed() {
    screenView('BackupWalletReveal');
    track('backup_reveal_viewed');
  }

  /// User ticked "I've written down my recovery phrase" and tapped
  /// Continue to advance to the verification quiz.
  static void backupRevealAcknowledged() {
    track('backup_reveal_acknowledged');
  }

  /// User landed on the verification quiz sub-step.
  static void backupVerifyViewed() {
    screenView('BackupWalletVerify');
    track('backup_verify_viewed');
  }

  static void pinFailed({required int attemptNumber}) {
    track('pin_failed', params: {'attempt_number': attemptNumber});
  }

  static void accountLocked({required int lockoutSeconds}) {
    track('account_locked', params: {'lockout_seconds': lockoutSeconds});
  }

  static void biometricFailed({String? reason, String? errorCode}) {
    track('biometric_failed', params: {
      if (reason != null) 'reason': _safeReason(reason)!,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  /// A wrong PIN in a confirmation sheet. [surface] names the sheet
  /// ('step_up', 'seed_words', 'wallets', 'change_pin').
  static void pinGateFailed({required String surface, required int attempt}) {
    track('pin_gate_failed', params: {'surface': surface, 'attempt': attempt});
  }

  /// A confirmation sheet reached the attempt threshold and locked the app.
  static void pinSheetLockout() => track('pin_sheet_lockout');

  /// The raw `biometric_pin` copy was deleted because no stored wallet
  /// needs the PIN to read its seed.
  static void biometricPinRemoved() => track('biometric_pin_removed');

  /// Change PIN stopped before writing because some PIN-encrypted copies
  /// could not be read.
  static void changePinBlocked({required int walletCount}) {
    track('change_pin_blocked', params: {
      'wallet_count_bucket': walletCount <= 1
          ? '1'
          : walletCount <= 3
              ? '2-3'
              : '4+',
    });
  }

  /// Cold-start secure storage classification ('ok', 'preBinding',
  /// 'bindingMismatch', 'secretsMissing', 'storageUnavailable', ...).
  static void seedStorageState({required String state}) {
    track('seed_storage_state', params: {'state': state});
  }

  static void storageUnavailableRetry() => track('storage_unavailable_retry');

  /// The Restore wallets screen opened. [reason] is how it was reached.
  static void seedRestoreScreenShown({required String reason}) {
    track('seed_restore_screen_shown', params: {'reason': reason});
  }

  /// [method] is 'phrase', 'legacy_copy' or 'passkey'.
  static void seedRestoreStarted({required String method}) {
    track('seed_restore_started', params: {'method': method});
  }

  /// [matched] is true when the phrase or copy matched the wallet's stored
  /// recovery check address.
  static void seedRestoreCompleted(
      {required String method, required bool matched}) {
    track('seed_restore_completed',
        params: {'method': method, 'matched': matched});
  }

  static void seedRestoreStartFresh() => track('seed_restore_start_fresh');

  /// The home banner for a spending wallet whose seed this phone can't
  /// read.
  static void seedUnavailableBannerShown() =>
      track('seed_unavailable_banner_shown');

  static void seedUnavailableBannerTapped() =>
      track('seed_unavailable_banner_tapped');

  /// iOS replaced the recovery phrase on [surface] with a notice because
  /// the screen is being recorded or mirrored.
  static void seedCaptureHidden({required String surface}) {
    track('seed_capture_hidden', params: {'surface': surface});
  }

  /// A screenshot was taken while [surface] showed a recovery phrase.
  static void seedScreenshotWarningShown({required String surface}) {
    track('seed_screenshot_warning_shown', params: {'surface': surface});
  }

  /// The Wallets screen recovery phrase sheet showed its QR code after an
  /// explicit tap.
  static void walletsQrRevealed() => track('wallets_qr_revealed');

  /// The note that phone backups and transfers don't carry the wallet key
  /// was shown on [surface].
  static void deviceBoundExplainerViewed({required String surface}) {
    track('device_bound_explainer_viewed', params: {'surface': surface});
  }

  // -- App Unlock --

  static void appUnlocked({required String method}) {
    track('app_unlocked', params: {'method': method});
  }

  // -- Navigation & Engagement --

  static void qrScanned(String type) {
    track('qr_scanned', params: {'type': type});
  }

  /// One scrub gesture on an analytics chart. [chart]: the tab
  /// (balance | valuation | price); [view]: line | candles | hourly.
  /// Nothing about the value under the finger.
  static void analyticsChartScrubbed(
      {required String chart, required String view}) {
    track('analytics_chart_scrubbed', params: {'chart': chart, 'view': view});
  }

  static void homeCardTapped(String card) {
    track('home_card_tapped', params: {'card': card});
  }

  static void homeActionTapped(String action) {
    track('home_action_tapped', params: {'action': action});
  }

  // -- Nav / Search redesign (bottom "+" bar + unified search) --
  //
  // The redesigned bottom action bar (`KuteBottomActionBar`) is mounted on
  // Home / Predictions / Portfolio / wallet-detail with its own contextual
  // "+" overlay quick-actions and a "Search kute" field. [source] is the
  // categorical screen the bar is mounted on ('home' | 'predictions' |
  // 'portfolio' | 'wallet_detail') so each event can be broken down per
  // surface. All categorical — no wallet id, no amount.

  /// One of the bottom "+" overlay quick-actions was tapped (Send /
  /// Receive / Scan / Add funds / Deposit / Withdraw / Add wallet). [action]
  /// is the lowercased action key; [source] is the mounting screen.
  /// [venue] ('polymarket' | 'hyperliquid') names the venue a venue's own
  /// button acts on (its top Deposit button); omitted elsewhere.
  static void quickAction(String action,
      {required String source, String? venue}) {
    track('quick_action_tapped', params: {
      'action': action,
      'source': source,
      if (venue != null) 'venue': venue,
    });
  }

  /// The "+" FAB was tapped and the quick-actions overlay opened.
  static void quickActionsOpened({required String source}) {
    track('quick_actions_opened', params: {'source': source});
  }

  /// A distinct affordance of the bottom action bar was tapped. [element] is
  /// the categorical control ('dock_search' since the square became search
  /// everywhere; 'search_icon' | 'ask_sal' | 'fab' before); [source] is
  /// the mounting screen ('home' | 'predictions' | 'trading' | 'portfolio' |
  /// 'wallet_detail'). Measures per-affordance engagement on the bar itself —
  /// distinct from the downstream destination events (`search_opened`,
  /// `exchange_opened`, `quick_actions_opened`), which fire when the surface
  /// the tap opens actually mounts.
  static void bottomBarTapped({
    required String element,
    required String source,
  }) {
    track('bottom_bar_tapped', params: {
      'element': element,
      'source': source,
    });
  }

  /// The unified "Search kute" surface was opened. [source] is the mounting
  /// screen; [initialCategory] is the section it was seeded to ('all' |
  /// 'transactions' | 'predictions' | 'support').
  static void searchOpened({
    required String source,
    required String initialCategory,
  }) {
    screenView('search');
    track('search_opened', params: {
      'source': source,
      'initial_category': initialCategory,
    });
  }

  /// The search category-filter chip changed (All / Transactions /
  /// Predictions / Support). [category] is the newly-selected section.
  static void searchCategoryChanged(String category) {
    track('search_category_changed', params: {'category': category});
  }

  /// A search result row was tapped. [resultType] is the categorical row
  /// kind ('transaction' | 'owned_position' | 'global_market' | 'balance' |
  /// 'support' | 'crypto_send' | 'crypto_receive'). No query, no ids.
  static void searchResultTapped(String resultType) {
    track('search_result_tapped', params: {'result_type': resultType});
  }

  /// A row in the unified-search "Quick actions" group was tapped
  /// (add_funds / send / receive / exchange / add_wallet). Distinct from
  /// [searchResultTapped] (which is a matched result), so the launcher use
  /// of search reads as its own funnel.
  static void searchQuickActionTapped(String action) {
    track('search_quick_action_tapped', params: {'action': action});
  }

  // -- Add Funds method picker (Bitcoin / Bank transfer / From crypto) --

  /// A method was chosen in the Add Funds picker. [method] is categorical
  /// ('bitcoin' | 'bank_transfer' | 'from_crypto'). The downstream deposit
  /// COMPLETION still fires the AppsFlyer purchase/funded conversions — this
  /// is the PostHog funnel step (intent), deliberately PostHog-only.
  static void addFundsMethodSelected({
    required String method,
    required String source,
  }) {
    track('add_funds_method_selected', params: {
      'method': method,
      'source': source,
    });
  }

  // -- Cash App bitcoin purchase (Flashnet Lightning onramp) --

  /// A Cash App onramp order was created (invoice minted, handoff shown).
  /// Amount is BUCKETED, matching the move/deposit funnels. Completion
  /// analytics stay with background sync's Orchestra pending→terminal
  /// transition — this is the intent step.
  /// [destination] distinguishes where the purchased bitcoin lands:
  /// 'spending' (Spark spending wallet, the default) or 'cold_onchain'
  /// (on-chain delivery straight to a hardware / watch-only / tracked
  /// wallet's own address).
  static void cashAppPurchaseCreated(
      {required double amountUsd, String destination = 'spending'}) {
    track('cashapp_purchase_created', params: {
      'amount_bucket': usdBucket(amountUsd),
      'destination': destination,
    });
  }

  /// The user tapped through to Cash App (the paymentLinks.cashApp
  /// external handoff). Superseded by [cashAppLinkLaunched], which
  /// also covers the automatic launch Continue now performs; kept so
  /// historical dashboards on this event name still resolve.
  static void cashAppPaymentLinkOpened() {
    track('cashapp_payment_link_opened');
  }

  /// The Cash App payment link was launched. [auto] is true when
  /// Continue launched it straight after creating the onramp (the
  /// default flow, no intermediate page) and false when the user
  /// tapped "Open Cash App again". [opened] is whether the OS
  /// accepted the launch; false means the sheet fell back to the
  /// in-app handoff page (QR + copy invoice).
  static void cashAppLinkLaunched({required bool auto, required bool opened}) {
    track('cashapp_link_launched', params: {
      'auto': auto,
      'opened': opened,
    });
  }

  /// The user started a fresh Cash App purchase after an unpaid order's
  /// payment window ended. This only opens the amount screen; no order is
  /// created. [source] is 'move_sheet' or 'activity'.
  static void cashAppNewPurchaseTapped({required String source}) {
    track('cashapp_new_purchase_tapped', params: {'source': source});
  }

  /// The user tapped Check status after the payment window ended.
  static void cashAppEndedWindowStatusChecked() {
    track('cashapp_ended_window_status_checked');
  }

  /// The Exchange (move-funds) sheet opened. [source] is the surface it was
  /// launched from ('home' | 'wealth' | 'search' | 'predictions').
  static void exchangeOpened({required String source}) {
    track('exchange_opened', params: {'source': source});
  }

  /// Support was opened from the bottom bar's support icon or the search
  /// "Contact support" row. [source] is where it was opened from
  /// ('bottom_bar' | 'search').
  static void supportOpened({required String source}) {
    track('support_opened', params: {'source': source});
  }

  /// Fired when the user taps the BTC vs USDC card to the front of the
  /// home wallet deck — the gateway that flips
  /// `selectedWalletCardProvider` and routes every USDC home action
  /// (Receive / Deposit). [cardType] is the categorical asset label
  /// ('usdc' | 'bitcoin' | 'bank') — no amount, no wallet id.
  static void homeWalletCardSelected(String cardType) {
    track('home_wallet_card_selected', params: {'card_type': cardType});
  }

  /// Fired when the account-switcher pill picks a different pool. [asset]
  /// is the categorical destination pool ('usdc' | 'bitcoin') — switching
  /// to 'usdc' is the toggle that makes Receive/Deposit route to USDC.
  /// Categorical only — no wallet id, no amount.
  static void accountPoolSwitched(String asset) {
    track('account_pool_switched', params: {'asset': asset});
  }

  /// Fired when the user taps the BTC+USDC spending-wallet tile in the
  /// portfolio (setActiveWallet + open Home). No wallet id (leaky
  /// correlator — see portfolio_wallet_opened fix), no amount.
  static void portfolioSpendingWalletOpened() =>
      track('portfolio_spending_wallet_opened');

  static void settingsActionTapped(String feature) {
    track('settings_action_tapped', params: {'feature': feature});
  }

  // -- Receive --

  static void receiveOpened({String? network}) {
    track('receive_opened', params: {
      if (network != null) 'network': network,
    });
  }

  static void addressCopied(String type) {
    track('address_copied', params: {'type': type});
  }

  static void addressShared(String type) {
    track('address_shared', params: {'type': type});
  }

  // -- Transactions --

  /// Tracks an outgoing transaction. We tag the coarse `network`
  /// (lightning / spark / bitcoin) and `wallet_category` so the
  /// `transaction_sent` event can be counted and broken down by type
  /// in PostHog. Amounts, fees, and passkey-ness stay withheld —
  /// `network` is a category, not PII, but a precise `amountSats`
  /// paired with the pseudonymous user_id would let someone rebuild
  /// the user's ledger (see the 2026-05 telemetry audit), so it's
  /// deliberately not emitted.
  static void transactionSent({
    String? network,
    int? amountSats,
    String? walletCategory,
    int? feeSats,
    int? latencyMs,
    bool? isPasskeyWallet,
    double? amountUsd,
    String? walletKind,
    String asset = 'btc',
    String? feeTier,
    double? feeUsd,
    // 'transfer' (a user send) | 'conversion_leg' (the funding leg of a
    // swap/deposit, already counted by that flow's own events).
    String purpose = 'transfer',
  }) {
    track('transaction_sent', params: {
      if (network != null) 'network': network,
      if (walletCategory != null) 'wallet_category': walletCategory,
      if (walletKind != null) 'wallet_kind': walletKind,
      'purpose': purpose,
      ...moneyParams(
        amountUsd: (amountUsd != null && amountUsd > 0) ? amountUsd : null,
        amount: asset == 'btc' && amountSats != null
            ? amountSats / 100000000
            : null,
        asset: asset,
        amountSats: asset == 'btc' ? amountSats : null,
        feeSats: feeSats,
        feeUsd: feeUsd,
        feeTier: feeTier,
        feeBasis: 'network_fee',
      ),
    });
    // A conversion leg is one side of a swap/deposit that its own flow
    // already counts: it is not a second transaction for activation.
    if (purpose == 'conversion_leg') return;
    markMoneyAction('send', venue: network);
    // Affiliate activation: count this send toward the ">10 transactions" rule.
    _bumpAffiliateActivity();
    // First-send funnel milestone — fires exactly once per device.
    if (OnceFlagsService.claimOnce('first_send_completed')) {
      track('first_send_completed', params: {
        if (network != null) 'network': network,
      });
    }
  }

  /// Tracks an incoming transaction. Same payload policy as
  /// `transactionSent`: coarse `network` + `wallet_category` for
  /// counting/breakdown, no amount.
  static void transactionReceived({
    String? network,
    int? amountSats,
    String? walletCategory,
    bool? isPasskeyWallet,
    double? amountUsd,
    String? walletKind,
    String asset = 'btc',
    String purpose = 'transfer',
  }) {
    track('transaction_received', params: {
      if (network != null) 'network': network,
      if (walletCategory != null) 'wallet_category': walletCategory,
      if (walletKind != null) 'wallet_kind': walletKind,
      'purpose': purpose,
      ...moneyParams(
        amountUsd: (amountUsd != null && amountUsd > 0) ? amountUsd : null,
        amount: asset == 'btc' && amountSats != null
            ? amountSats / 100000000
            : null,
        asset: asset,
        amountSats: asset == 'btc' ? amountSats : null,
      ),
    });
    if (purpose == 'conversion_leg') return;
    markMoneyAction('receive', venue: network);
    // AppsFlyer activation milestone — first incoming funds (once per
    // device, gated inside). Historical txs are seeded without emitting
    // transactionReceived, so this only fires on a genuinely new receive.
    AppsFlyerService.walletFunded();
    // Affiliate activation: count this receive toward the ">10 transactions"
    // rule.
    _bumpAffiliateActivity();
  }

  // ─── Affiliate activity counter ──────────────────────────────────
  //
  // Persistent running count of the user's genuine transactions across ALL
  // types — Bitcoin sends/receives, swaps, buys/sells, and Polymarket bets /
  // sells / redeems (seeded history doesn't reach these hooks, so it never
  // inflates). Reported to the backend on EVERY transaction (from the very
  // first, not only past 10): the backend stores it monotonically and uses it
  // for the ">10 transactions" activation rule, and it can't see wallet/
  // Polymarket txs by design, so this is the only source. Runs regardless of
  // analytics opt-in (it's program logic, not analytics) and is best-effort.
  static void _bumpAffiliateActivity() {
    try {
      if (!Hive.isBoxOpen('settings')) return;
      final box = Hive.box('settings');
      final n = ((box.get('affiliate_tx_count') as int?) ?? 0) + 1;
      box.put('affiliate_tx_count', n);
      if (AffiliateService.sessionToken != null) {
        AffiliateService.reportActivity(n);
        if (OnceFlagsService.claimOnce('affiliate_activity_reported')) {
          affiliateActivityReported();
        }
      }
    } catch (_) {/* never break a tx report over the activity counter */}
  }

  /// Push the ALREADY-accumulated affiliate transaction count to the backend.
  ///
  /// [_bumpAffiliateActivity] only reports when a session token exists AT THE
  /// MOMENT of the transaction. A referee's session token mints lazily (it
  /// waits on the @paykute LN address being provisioned), so every transaction
  /// made before that token existed bumped the local `affiliate_tx_count` in
  /// Hive but was never sent. If the referee then goes quiet, the backend
  /// permanently sees a low count and never applies the ">10 transactions"
  /// activation rule — the wallet shows 10+ txs in-app but stays unactivated.
  ///
  /// [AffiliateService.authWallet] calls this the instant it mints/refreshes a
  /// session so the stranded count finally lands. Reporting is monotonic and
  /// idempotent server-side, so running it on every boot (via the per-boot
  /// re-auth) is safe and also re-sends the cumulative count if an earlier
  /// [reportActivity] POST failed on the network. Best-effort; never throws.
  static void flushAffiliateActivity() {
    try {
      if (AffiliateService.sessionToken == null) return;
      if (!Hive.isBoxOpen('settings')) return;
      final box = Hive.box('settings');
      final n = (box.get('affiliate_tx_count') as int?) ?? 0;
      if (n <= 0) return;
      AffiliateService.reportActivity(n);
      if (OnceFlagsService.claimOnce('affiliate_activity_reported')) {
        affiliateActivityReported();
      }
    } catch (_) {/* best-effort — never break auth over the activity flush */}
  }

  // -- Deposit Claims --

  // amountSats param removed (was never emitted) per the 2026-05
  // telemetry audit / no-amount rule — a raw sats value tied to the
  // pseudonymous user_id is ledger-rebuild-grade telemetry.
  // [outcome] is submitted, already_received or no_longer_pending. [status]
  // is the SDK payment status of a submitted claim, usually pending.
  static void sparkDepositClaimed({
    required String outcome,
    String? status,
    int? amountSats,
    double? amountUsd,
    int? feeSats,
    String? trigger, // manual | auto
  }) {
    track('spark_deposit_claimed', params: {
      'outcome': outcome,
      if (status != null) 'status': status,
      if (trigger != null) 'trigger': trigger,
      'network': 'bitcoin',
      ...moneyParams(
        amountUsd: amountUsd,
        amount: amountSats != null ? amountSats / 100000000 : null,
        asset: 'btc',
        amountSats: amountSats,
        feeSats: feeSats,
        feeBasis: 'network_fee',
      ),
    });
  }

  static void sparkDepositClaimFailed({required String reason}) {
    track('spark_deposit_claim_failed', params: {
      'reason': _safeReason(reason) ?? '',
    });
  }

  static void sparkDepositClaimFeeConfirmed() =>
      track('spark_deposit_claim_fee_confirmed');

  static void sparkDepositRefunded() => track('spark_deposit_refunded');

  static void sparkDepositRefundFailed({required String reason}) {
    track('spark_deposit_refund_failed', params: {
      'reason': _safeReason(reason) ?? '',
    });
  }

  // -- Swaps / Exchange --

  static void swapInitiated({
    required String fromCoin,
    required String toCoin,
    required String provider, // 'orchestra', etc.
    double? fromAmount,
    double? amountUsd,
    String? fromNetwork,
    String? toNetwork,
    String? venue,
  }) {
    track('swap_initiated', params: {
      'from_coin': fromCoin,
      'to_coin': toCoin,
      'provider': provider,
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
      ..._swapLegParams(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
          fromAmount: fromAmount,
          amountUsd: amountUsd,
          venue: venue),
    });
  }

  /// Exact legs of a swap/conversion: from/to asset and network, amount in
  /// and out (native units) and their USD value, plus the venue it funds.
  static Map<String, Object> _swapLegParams({
    required String fromCoin,
    required String toCoin,
    String? fromNetwork,
    String? toNetwork,
    double? fromAmount,
    double? toAmount,
    double? amountUsd,
    double? amountOutUsd,
    String? venue,
  }) {
    bool ok(double? v) => v != null && v.isFinite;
    return {
      'from_asset': fromCoin.toLowerCase(),
      'to_asset': toCoin.toLowerCase(),
      if (fromNetwork != null) 'from_network': fromNetwork.toLowerCase(),
      if (toNetwork != null) 'to_network': toNetwork.toLowerCase(),
      if (ok(fromAmount))
        'amount_in': _round(fromAmount!, _assetDecimals(fromCoin)),
      if (ok(amountUsd)) 'amount_in_usd': _round(amountUsd!, 2),
      if (ok(amountUsd)) 'amount_usd': _round(amountUsd!, 2),
      if (ok(toAmount)) 'amount_out': _round(toAmount!, _assetDecimals(toCoin)),
      if (ok(amountOutUsd)) 'amount_out_usd': _round(amountOutUsd!, 2),
      if (venue != null) 'venue': venue,
    };
  }

  static void swapCompleted({
    required String fromCoin,
    required String toCoin,
    required String provider,
    double? fromAmount,
    double? toAmount,
    double? amountUsd,
    int? latencyMs,

    /// REAL provider order id (e.g. Orchestra's `ord_...`). Used
    /// as the backend `provider_events.provider_order_id` UNIQUE dedup
    /// key — synthetic-id fallbacks multiplied revshare on the
    /// backend because each poll cycle created a "new" order. Always
    /// pass the real id when emitting from the polling loop.
    String? providerOrderId,
    String? fromNetwork,
    String? toNetwork,
    String? venue,
    double? amountOutUsd,
  }) {
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    markMoneyAction('swap', venue: venue ?? provider);
    track('swap_completed', params: {
      'from_coin': fromCoin,
      'to_coin': toCoin,
      'provider': provider,
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
      // No fee here: the old post-settlement spread estimate was never
      // shown to the user and read like Kute revenue, which reaches
      // PostHog only from the database.
      ..._swapLegParams(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
          fromAmount: fromAmount,
          toAmount: toAmount,
          amountUsd: amountUsd,
          amountOutUsd: amountOutUsd,
          venue: venue),
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (latencyMs != null) 'latency_bucket': _latencyBucket(latencyMs),
      // Sent as its one-way reference (see [sanitizeParams]), never raw.
      if (providerOrderId != null) 'provider_order_id': providerOrderId,
      // Database join key (see [orderRef]).
      ...(provider.toLowerCase() == 'orchestra'
          ? orchestraJoinParams(providerOrderId)
          : orderJoinParams(providerOrderId)),
    });
    // First-swap funnel milestone. Gated once-per-device.
    if (OnceFlagsService.claimOnce('first_swap_completed')) {
      track('first_swap_completed', params: {
        'from_coin': fromCoin,
        'to_coin': toCoin,
        'provider': provider,
        if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
      });
    }
    // Referee conversion signal — only fires the first time after the
    // user has been bound to a referrer code.
    affiliateRefereeConverted(provider: provider, amountUsd: amountUsd);
    // Report completion + leg amounts to the backend so it records the
    // order state and computes our earnings (rate × USD-stable leg). Covers
    // the swap providers that flow through swapCompleted; Polymarket
    // reports from polymarketBetPlaced.
    final lp = provider.toLowerCase();
    // AppsFlyer conversion signal — completed swaps only (this method
    // only fires on completion; initiated/failed swaps never reach it).
    if (_backendSwapProviders.contains(lp)) {
      AppsFlyerService.purchaseCompleted(provider: lp);
    }
    if (_backendSwapProviders.contains(lp) && providerOrderId != null) {
      AffiliateService.logProviderEvent(
        provider: lp,
        providerOrderId: providerOrderId,
        status: 'completed',
        fiatAmountEur: amountUsd != null ? amountUsd * 0.92 : null,
        sourceAsset: fromCoin,
        sourceAmount: fromAmount,
        destinationAsset: toCoin,
        destinationAmount: toAmount,
      );
    }
  }

  /// Swap providers whose order state + earnings we report to the
  /// backend from the transaction-side completion/failure hooks.
  /// Polymarket reports via its bet flow.
  static const _backendSwapProviders = {'orchestra'};

  static void swapFailed({
    required String fromCoin,
    required String toCoin,
    required String provider,
    required String reason,
    String? errorCode,
    String? providerOrderId,
    String? fromNetwork,
    String? toNetwork,
    String? venue,
    double? fromAmount,
    double? amountUsd,
    StackTrace? stackTrace,
  }) {
    recordHandled(errorCategory(reason), reason, stackTrace,
        flow: 'swap', stage: provider.toLowerCase());
    track('swap_failed', params: {
      'from_coin': fromCoin,
      'to_coin': toCoin,
      'provider': provider,
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
      ..._swapLegParams(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
          fromAmount: fromAmount,
          amountUsd: amountUsd,
          venue: venue),
      'reason': _safeReason(reason) ?? '',
      'error_category': errorCategory(reason),
      if (errorCode != null) 'error_code': errorCode,
    });
    // Report the terminal failure to the backend so the order's row reflects
    // "not completed". Earnings stay null on non-completion.
    final lp = provider.toLowerCase();
    if (_backendSwapProviders.contains(lp) && providerOrderId != null) {
      AffiliateService.logProviderEvent(
        provider: lp,
        providerOrderId: providerOrderId,
        status: reason,
        sourceAsset: fromCoin,
        destinationAsset: toCoin,
      );
    }
  }

  static void swapAssetSelected({required String flow, required String asset}) {
    track('swap_asset_selected', params: {'flow': flow, 'asset': asset});
  }

  /// Fired the moment a stablecoin shortcut (USDC / USDT) is tapped on
  /// the Send screen — captures the entry intent (and abandonment before
  /// a network is picked), which `swap_asset_selected` only sees LATER
  /// once a network resolves. [assetCode] is a categorical label
  /// ('usdc' | 'usdt'); [flow] is 'send'. No amount.
  static void sendAssetShortcutTapped(String assetCode) {
    track('send_asset_shortcut_tapped',
        params: {'asset_code': assetCode, 'flow': 'send'});
  }

  /// Fired when a stablecoin shortcut (USDC / USDT) is tapped on the
  /// Receive screen — the entry intent for receiving stablecoins.
  /// [assetCode] is a categorical label ('usdc' | 'usdt'); [flow] is
  /// 'receive'. No amount.
  static void receiveAssetShortcutTapped(String assetCode) {
    track('receive_asset_shortcut_tapped',
        params: {'asset_code': assetCode, 'flow': 'receive'});
  }

  // The Yield / Earn (USDB) helpers were removed with the Flashnet Earn
  // product. Their server-side events (earn_*, usdb_*, yield_*) should
  // be retired in the PostHog UI separately.

  // -- Signer / PSBT Signing --

  static void signerPsbtScanned() => track('signer_psbt_scanned');

  static void signerTransactionSigned() => track('signer_transaction_signed');

  static void signerSignFailed(
      {required String reason, String? errorCode, StackTrace? stackTrace}) {
    recordHandled(errorCategory(reason), reason, stackTrace,
        flow: 'signer', stage: 'sign');
    track('signer_sign_failed', params: {
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  // -- Polymarket --

  /// Single market-view event. Previously split across the bare
  /// `polymarket_viewed` (market_id only) and a raw
  /// `prediction_market_viewed` (enriched) fired from the same call
  /// site — consolidated here so market-view analytics live under one
  /// event name. [liquidityUsd] is bucketed (never the raw value);
  /// [outcomeCount] is collapsed to a coarse cardinality bucket.
  ///
  /// The event is named by its public Gamma data: `event_id`,
  /// `event_slug` and `event_title` (80 characters). `market_id` stays
  /// what it was (the opened event's id; for one outcome opened as its
  /// own Yes/No screen, that screen's id), so `event_id` is the key that
  /// ties a slip, a bet, a sale and a claim back to this view.
  static void polymarketViewed({
    required String marketId,
    String? category,
    double? liquidityUsd,
    int? outcomeCount,
    String? source, // feed_card | search | sal | hot_events | group_landing
    String? eventSlug,
    String? eventTitle,
    Map<String, Object>? extra,
  }) {
    track('polymarket_viewed', params: {
      ...VenueAnalytics.pmKindParams([marketId], fallbackCategory: category),
      ...VenueAnalytics.pmEventParams([marketId, eventSlug],
          eventSlug: eventSlug, eventTitle: eventTitle),
      ...?extra,
      'market_id': marketId,
      if (source != null) 'source': source,
      if (category != null && category.isNotEmpty)
        'category': category.toLowerCase(),
      if (liquidityUsd != null) 'liquidity_bucket': _usdBucket(liquidityUsd),
      if (outcomeCount != null)
        'outcome_count_bucket': outcomeCount <= 2
            ? 'binary'
            : (outcomeCount <= 10 ? 'multi_small' : 'multi_large'),
    });
  }

  static void polymarketBetPlaced({
    required String marketId,
    required String outcome,
    required double amount,
    required double price,
    required int shares,
    String? category, // 'crypto' | 'sports' | 'politics' | 'science' | 'other'
    String? marketTitle, // first 80 chars truncated; analytics-only
    String? source, // 'btc_pool' | 'usdc_pool' — funding source
    String? walletCategory, // 'spending' | 'savings' — wallet that funded
    String? betType, // moneyline | yes_no | over_under | spread | ... | other
    // Polymarket's real order hash from the CLOB submit response (orderID).
    // Sent as provider_order_id so the backend can join it to the builder
    // trade (taker_order_hash) and attribute the EXACT fee_usdc we earned.
    // Falls back to a synthetic id only if the CLOB didn't return one.
    String? providerOrderId,
    // Market SELLS pass false: the sell sheet logs the canonical
    // provider_events row via `polymarketPositionSold` (correct
    // pm_shares → USDC direction) with the SAME orderID, so logging here
    // too produced two backend rows per sell order (the "double
    // [affiliate.logProviderEvent] OK" bug). Limit (GTC) sells keep the
    // default true — they never reach `polymarketPositionSold` (no fill
    // at placement time), so this is their only provider event.
    bool logAffiliateEvent = true,
    // false for SELL orders routed through placeOrder: a sell is reported
    // by polymarket_position_sold (or polymarket_limit_sell_placed), so
    // emitting a "bet placed" too counted one sell as a bet and a sale,
    // and fired first-bet, referee-conversion and AppsFlyer signals for
    // it. Backend logging above still runs (it needs the order hash).
    bool emitAnalytics = true,
    String side = 'buy', // buy | sell
    String? orderType, // market | limit
    String? entrySource, // feed_card | search | sal | hot_events | ...
    String? walletKind, // hot | ledger
    String? marketOutcome, // the outcome name the user backed (yes/no/team)
    String? marketSlug, // public market identifier
    Map<String, Object>? extra, // ticket settings, origin (autofire)
  }) {
    // Derive funding_currency from the funding source enum. `btc_pool`
    // means BTC was swapped in to top up the Polymarket Safe;
    // `usdc_pool` means the existing USDC.e balance was sufficient.
    final String? fundingCurrency =
        source == 'btc_pool' ? 'BTC' : (source == 'usdc_pool' ? 'USDC' : null);
    if (!emitAnalytics) {
      if (logAffiliateEvent) {
        AffiliateService.logProviderEvent(
          provider: 'polymarket',
          providerOrderId:
              (providerOrderId != null && providerOrderId.isNotEmpty)
                  ? providerOrderId
                  : 'pm_${marketId}_${outcome}_'
                      '${DateTime.now().millisecondsSinceEpoch}',
          status: 'completed',
          fiatAmountEur: amount * 0.92,
          sourceAsset: source ?? 'USDC',
          sourceAmount: amount,
          destinationAsset: 'pm_shares:$outcome',
          destinationAmount: shares.toDouble(),
        );
      }
      return;
    }
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    markMoneyAction('bet', venue: 'polymarket');
    track('polymarket_bet_placed', params: {
      ...VenueAnalytics.staged('pm', marketId),
      ...VenueAnalytics.pmKindParams([marketId, marketSlug],
          fallbackCategory: category),
      // The parent event (event_id, event_slug), the key the funnel
      // joins a view, a slip and a bet on.
      ...VenueAnalytics.pmEventParams([marketId, marketSlug],
          eventSlug: marketSlug, title: false),
      ...?extra,
      'venue': 'polymarket',
      'side': side,
      if (orderType != null) 'order_type': orderType,
      if (entrySource != null) 'entry_source': entrySource,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (marketOutcome != null) 'market_outcome': marketOutcome.toLowerCase(),
      if (marketSlug != null) 'market_slug': marketSlug,
      'shares': shares,
      if (amount.isFinite) 'amount_usd': _round(amount, 2),
      if (amount.isFinite) 'notional_usd': _round(amount, 2),
      'market_id': marketId,
      'outcome': outcome,
      'amount_bucket': _usdBucket(amount),
      'price': price,
      if (category != null) 'category': category,
      if (marketTitle != null && marketTitle.isNotEmpty)
        'market_title': VenueAnalytics.title80(marketTitle),
      if (source != null) 'source': source,
      if (fundingCurrency != null) 'funding_currency': fundingCurrency,
      if (walletCategory != null) 'wallet_category': walletCategory,
      if (betType != null) 'bet_type': betType,
      // Database join key: the real CLOB order id only, never the
      // synthetic fallback below (the database cannot hold it).
      ...orderJoinParams(providerOrderId),
    });
    // First-bet referee-conversion signal — gates once per device so
    // we don't double-count attribution after the first qualifying bet.
    affiliateRefereeConverted(provider: 'polymarket', amountUsd: amount);
    // AppsFlyer conversion signal — a placed bet is a completed
    // revenue-bearing order (builder fee).
    AppsFlyerService.purchaseCompleted(provider: 'polymarket');
    // Affiliate-aware backend logging. provider_order_id is Polymarket's real
    // order hash (orderID) so the backend can join it to the builder trade and
    // attribute the exact fee_usdc. If the CLOB didn't return one, fall back to
    // a synthetic marketId+timestamp id (won't match a trade — the row keeps
    // the backend's provisional estimate, which is fine).
    if (logAffiliateEvent) {
      AffiliateService.logProviderEvent(
        provider: 'polymarket',
        providerOrderId: (providerOrderId != null && providerOrderId.isNotEmpty)
            ? providerOrderId
            : 'pm_${marketId}_${outcome}_'
                '${DateTime.now().millisecondsSinceEpoch}',
        status: 'completed',
        fiatAmountEur: amount * 0.92, // USD → EUR rough
        sourceAsset: source ?? 'USDC',
        sourceAmount: amount,
        destinationAsset: 'pm_shares:$outcome',
        destinationAmount: shares.toDouble(),
      );
    }
  }

  static void polymarketBetFailed({
    required String marketId,
    required String reason,
    String? errorCode,
    String? side,
    String? orderType,
    double? amountUsd,
    String? walletKind,
    String? marketSlug,
    StackTrace? stackTrace,
    String? entrySource,
    Map<String, Object>? extra,
  }) {
    recordHandled(errorCategory(reason), reason, stackTrace,
        flow: 'polymarket_bet', stage: orderType);
    track('polymarket_bet_failed', params: {
      ...VenueAnalytics.staged('pm', marketId),
      ...VenueAnalytics.pmKindParams([marketId, marketSlug]),
      ...?extra,
      if (entrySource != null) 'entry_source': entrySource,
      'market_id': marketId,
      'venue': 'polymarket',
      if (side != null) 'side': side,
      if (orderType != null) 'order_type': orderType,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (marketSlug != null) 'market_slug': marketSlug,
      if (amountUsd != null && amountUsd.isFinite) ...{
        'amount_usd': _round(amountUsd, 2),
        'amount_bucket': _usdBucket(amountUsd),
      },
      'error_category': errorCategory(reason),
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void polymarketPositionSold({
    required String marketId,
    required double shares,
    required double price,
    double? pnl,
    // Polymarket's real order hash (orderID) from the sell's CLOB submit
    // response. Same role as in polymarketBetPlaced: lets the backend join to
    // the builder trade and attribute the exact fee_usdc on the sell.
    String? providerOrderId,
    String? orderType, // market | limit
    String? walletKind,
    String? marketSlug,
    String? category,
    Map<String, Object>? extra,
  }) {
    final usdcOut = shares * price;
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    track('polymarket_position_sold', params: {
      ...VenueAnalytics.staged('pm_sell', marketId),
      ...VenueAnalytics.pmKindParams([marketId, marketSlug],
          fallbackCategory: category),
      ...VenueAnalytics.pmEventParams([marketId, marketSlug],
          eventSlug: marketSlug, title: false),
      ...?extra,
      'market_id': marketId,
      'venue': 'polymarket',
      'side': 'sell',
      if (orderType != null) 'order_type': orderType,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (marketSlug != null) 'market_slug': marketSlug,
      if (category != null) 'category': category.toLowerCase(),
      'shares': _round(shares, 6),
      if (usdcOut.isFinite) 'amount_usd': _round(usdcOut, 2),
      if (usdcOut.isFinite) 'notional_usd': _round(usdcOut, 2),
      if (pnl != null && pnl.isFinite) 'pnl_usd': _round(pnl, 2),
      'price': price,
      'payout_bucket': _usdBucket(usdcOut),
      if (pnl != null) 'pnl_bucket': _usdBucket(pnl),
      if (pnl != null) 'pnl_direction': pnl >= 0 ? 'gain' : 'loss',
      ...orderJoinParams(providerOrderId),
    });
    // AppsFlyer conversion signal — sells carry a builder fee too.
    AppsFlyerService.purchaseCompleted(provider: 'polymarket');
    // Backend provider_events row for the "withdrawal" side of a bet
    // (sell → USDC). provider_order_id is the sell's real order hash so the
    // backend attributes the exact fee_usdc; synthetic fallback (which dedups
    // on (provider, provider_order_id)) only if the CLOB returned no orderID.
    AffiliateService.logProviderEvent(
      provider: 'polymarket',
      providerOrderId: (providerOrderId != null && providerOrderId.isNotEmpty)
          ? providerOrderId
          : 'pm_sold_${marketId}_'
              '${DateTime.now().millisecondsSinceEpoch}',
      status: 'completed',
      fiatAmountEur: usdcOut * 0.92, // USD → EUR rough
      sourceAsset: 'pm_shares',
      sourceAmount: shares,
      destinationAsset: 'USDC',
      destinationAmount: usdcOut,
    );
  }

  static void polymarketPositionRedeemed({
    required String marketId,
    required String outcome,
    required double shares,
    required double payout,
    String? trigger, // auto | manual
    String? surface,
    String? walletKind,
    Map<String, Object>? extra,
  }) {
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    track('polymarket_position_redeemed', params: {
      ...VenueAnalytics.pmKindParams([marketId]),
      ...VenueAnalytics.pmEventParams([marketId], title: false),
      ...?extra,
      'market_id': marketId,
      'venue': 'polymarket',
      'outcome': outcome,
      'payout_bucket': _usdBucket(payout),
      if (payout.isFinite) 'amount_usd': _round(payout, 2),
      'shares': _round(shares, 6),
      'won': payout > 0,
      if (trigger != null) 'trigger': trigger,
      if (surface != null) 'surface': surface,
      if (walletKind != null) 'wallet_kind': walletKind,
    });
    // Backend provider_events row for the redeem (winning-position payout).
    // Symmetric with polymarketBetPlaced + polymarketPositionSold so the
    // admin/dashboards see the full bet → sell/redeem lifecycle.
    //
    // No real order hash here on purpose: a redeem is an on-chain payout
    // claim, not a CLOB order, so it earns no builder fee and has nothing to
    // join against in polymarket_builder_trades. The synthetic id is correct.
    AffiliateService.logProviderEvent(
      provider: 'polymarket',
      providerOrderId: 'pm_redeem_${marketId}_${outcome}_'
          '${DateTime.now().millisecondsSinceEpoch}',
      status: 'completed',
      fiatAmountEur: payout * 0.92,
      sourceAsset: 'pm_shares:$outcome',
      sourceAmount: shares,
      destinationAsset: 'USDC',
      destinationAmount: payout,
    );
  }

  static void polymarketFundingAction(String action, {double? amountUsd}) {
    track('polymarket_funding_action', params: {
      'action': action,
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
    });
  }

  static void polymarketTradingEnabled() => track('polymarket_trading_enabled');

  // -- Buy / Sell (Fiat <-> BTC) --

  static void buyFailed({String? reason, String? provider, String? errorCode}) {
    track('buy_failed', params: {
      if (reason != null) 'reason': _safeReason(reason)!,
      if (provider != null) 'provider': provider,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void sellInitiated({
    required String currency,
    required double amount,
    String? provider,
  }) {
    track('sell_initiated', params: {
      'currency': currency,
      'amount_bucket': _usdBucket(amount),
      if (provider != null) 'provider': provider,
    });
  }

  static void sellCompleted({
    required String currency,
    required double fiatAmount,
    required double btcAmount,
    String? provider,
  }) {
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    track('sell_completed', params: {
      'currency': currency,
      'amount_bucket': _usdBucket(fiatAmount),
      if (provider != null) 'provider': provider,
    });
  }

  static void sellFailed(
      {String? reason, String? provider, String? errorCode}) {
    track('sell_failed', params: {
      if (reason != null) 'reason': _safeReason(reason)!,
      if (provider != null) 'provider': provider,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  // -- Orchestra / Flashnet Smart Routing --

  static void crossChainQuoteRequested({
    required String sourceChain,
    required String sourceAsset,
    required String destinationChain,
    required String destinationAsset,
    String? quoteId,
    double? amountUsd,
  }) {
    track('cross_chain_quote_requested', params: {
      'source_chain': sourceChain,
      'source_asset': sourceAsset,
      'destination_chain': destinationChain,
      'destination_asset': destinationAsset,
      if (quoteId != null) 'quote_id': quoteId,
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
    });
  }

  static void crossChainOrderSubmitted({
    required String quoteId,
    required String orderId,
    required String sourceChain,
    required String destinationChain,
  }) {
    track('cross_chain_order_submitted', params: {
      'quote_id': quoteId,
      'order_id': orderId,
      'source_chain': sourceChain,
      'destination_chain': destinationChain,
    });
  }

  static void crossChainOrderCompleted({
    required String orderId,
    required String sourceChain,
    required String destinationChain,
    int? latencyMs,
  }) {
    track('cross_chain_order_completed', params: {
      'order_id': orderId,
      'source_chain': sourceChain,
      'destination_chain': destinationChain,
      if (latencyMs != null) 'latency_ms': latencyMs,
    });
  }

  static void crossChainOrderFailed({
    required String orderId,
    required String reason,
    required String sourceChain,
    required String destinationChain,
    String? errorCode,
  }) {
    track('cross_chain_order_failed', params: {
      'order_id': orderId,
      'reason': _safeReason(reason) ?? '',
      'source_chain': sourceChain,
      'destination_chain': destinationChain,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void crossChainProviderFallback({
    required String sourceAsset,
    required String reason,
  }) {
    track('cross_chain_provider_fallback', params: {
      'source_asset': sourceAsset,
      'reason': _safeReason(reason) ?? '',
    });
  }

  // -- Accumulation Addresses (Receive) --

  static void reusableDepositAddressCreated({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
  }) {
    track('reusable_deposit_address_created', params: {
      'source_chain': sourceChain,
      'source_asset': sourceAsset,
      'destination_asset': destinationAsset,
    });
  }

  static void reusableDepositAddressReused({
    required String sourceChain,
    required String sourceAsset,
  }) {
    track('reusable_deposit_address_reused', params: {
      'source_chain': sourceChain,
      'source_asset': sourceAsset,
    });
  }

  /// A cached accumulation address was parked under the retired prefix
  /// because its (chain, asset) pair fell off Orchestra's receive
  /// catalog.
  static void reusableDepositAddressRetired({
    required String sourceChain,
    required String sourceAsset,
  }) {
    track('reusable_deposit_address_retired', params: {
      'source_chain': sourceChain,
      'source_asset': sourceAsset,
    });
  }

  /// User tapped the supported-asset picker button on the
  /// "receiving this asset is temporarily unavailable" notice.
  static void receiveUnsupportedAssetPickerOpened({
    required String asset,
    required String network,
  }) {
    track('receive_unsupported_asset_picker_opened', params: {
      'asset': asset,
      'network': network,
    });
  }

  // -- Cash App Buy --

  static void cashAppBuyInitiated({required double amountUsd}) {
    track('cashapp_buy_initiated',
        params: {'amount_bucket': _usdBucket(amountUsd)});
  }

  static void cashAppBuyCompleted({
    double? amountUsd,
    String? orderId,
    int? amountSats,
    String? currency,
    double? amountFiat,
    double? feeUsd,
    String? walletKind,
  }) {
    track('cashapp_buy_completed', params: {
      'venue': 'cashapp',
      if (walletKind != null) 'wallet_kind': walletKind,
      // One-way reference (see [sanitizeParams]); counts each order once.
      if (orderId != null) 'order_id': orderId,
      ...orchestraJoinParams(orderId),
      ...moneyParams(
        amountUsd: amountUsd,
        amount: amountSats != null ? amountSats / 100000000 : null,
        asset: 'btc',
        amountSats: amountSats,
        currency: currency,
        amountFiat: amountFiat,
        feeUsd: feeUsd,
      ),
    });
    markMoneyAction('buy', venue: 'cashapp');
  }

  static void cashAppBuyFailed(
      {double? amountUsd, required String reason, String? errorCode}) {
    track('cashapp_buy_failed', params: {
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
      if (amountUsd != null && amountUsd.isFinite)
        'amount_usd': _round(amountUsd, 2),
      'venue': 'cashapp',
      'error_category': errorCategory(reason),
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void cashAppLimitReached({required double remaining}) {
    track('cashapp_limit_reached',
        params: {'remaining_bucket': _usdBucket(remaining)});
  }

  // The USDB External Deposit and Flashnet USDB Earn screen event
  // helpers lived here until the Earn product was removed.

  // -- Payment Links --

  static void paymentLinkCreated({double? amountUsd}) {
    track('payment_link_created', params: {
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
    });
  }

  static void paymentLinkShared() => track('payment_link_shared');

  // -- Polymarket Funding --

  static void polymarketDepositInitiated({
    String? route, // btc_spending | btc_savings | usd
    double? amountUsd,
    String? entrySource, // bet_slip | predictions_screen | move_sheet
    String? walletKind,
  }) {
    if (route != null ||
        amountUsd != null ||
        entrySource != null ||
        walletKind != null) {
      track('polymarket_deposit_initiated', params: {
        if (route != null) 'route': route,
        if (entrySource != null) 'entry_source': entrySource,
        if (walletKind != null) 'wallet_kind': walletKind,
        ...moneyParams(amountUsd: amountUsd),
      });
      return;
    }
    // `amount_sats` dropped (and the unused param removed) per the
    // 2026-05 telemetry audit / no-amount rule — a pseudonymous
    // user_id tied to a precise sats value would be
    // financial-profile-grade telemetry. Bucket is computed by the
    // caller when it has a USD-side conversion (use
    // `polymarketFundingAction('deposit', amountUsd: …)`).
    track('polymarket_deposit_initiated');
  }

  static void polymarketDepositCompleted({
    String? orderId,
    double? amountUsd,
    String? route,
  }) {
    track('polymarket_deposit_completed', params: {
      if (orderId != null) 'order_id': orderId, // one-way ref, see sanitizeParams
      ...orchestraJoinParams(orderId),
      'venue': 'polymarket',
      if (route != null) 'route': route,
      ...moneyParams(amountUsd: amountUsd, asset: 'usdc', amount: amountUsd),
    });
    markMoneyAction('deposit', venue: 'polymarket');
  }

  /// The deposit was SUBMITTED (the Move sheet handed it to Orchestra).
  /// Settlement is reported separately by polymarket_deposit_completed
  /// from the background sync, so the two are never summed.
  static void polymarketDepositSubmitted({
    String? orderId,
    double? amountUsd,
    String? route,
    String? walletKind,
  }) =>
      track('polymarket_deposit_submitted', params: {
        if (orderId != null) 'order_id': orderId,
        ...orchestraJoinParams(orderId),
        'venue': 'polymarket',
        if (route != null) 'route': route,
        if (walletKind != null) 'wallet_kind': walletKind,
        ...moneyParams(amountUsd: amountUsd),
      });

  /// USDC.e that reached the Predictions deposit wallet was converted to
  /// pUSD, the only collateral an order can use. [trigger] says which path
  /// converted it: 'arrival' (the deposit's order completed, or the Move
  /// sheet's watch saw it land), 'open' (Predictions opened or the account
  /// started), 'resume' (the app came back), 'order' (a buy needed it
  /// before signing) or 'refusal' (the order book refused a buy for it).
  /// A coarse bucket only: the figure is the wallet's USDC.e at that
  /// moment.
  static void polymarketDepositConverted({
    required double amountUsd,
    required String trigger,
  }) =>
      track('polymarket_deposit_converted', params: {
        'venue': 'polymarket',
        'trigger': trigger,
        'amount_bucket': _usdBucket(amountUsd),
      });

  /// Withdraw handed to Orchestra; see [polymarketDepositSubmitted].
  static void polymarketWithdrawSubmitted({
    String? orderId,
    double? amountUsd,
    String? destination,
  }) =>
      track('polymarket_withdraw_submitted', params: {
        if (orderId != null) 'order_id': orderId,
        ...orchestraJoinParams(orderId),
        'venue': 'polymarket',
        if (destination != null) 'destination': destination,
        ...moneyParams(amountUsd: amountUsd, asset: 'usdc', amount: amountUsd),
      });

  static void polymarketWithdrawInitiated({required double amountUsdc}) {
    track('polymarket_withdraw_initiated',
        params: {'amount_bucket': _usdBucket(amountUsdc), 'venue': 'polymarket'});
  }

  static void polymarketWithdrawCompleted({
    String? orderId,
    double? amountUsd,
  }) {
    track('polymarket_withdraw_completed', params: {
      if (orderId != null) 'order_id': orderId, // one-way ref
      ...orchestraJoinParams(orderId),
      'venue': 'polymarket',
      ...moneyParams(amountUsd: amountUsd, asset: 'usdc', amount: amountUsd),
    });
  }

  // -- Receive Flow --

  static void receiveSourceSelected({
    required String asset,
    required String network,
    required String provider, // 'orchestra'
  }) {
    track('receive_source_selected', params: {
      'asset': asset,
      'network': network,
      'provider': provider,
    });
  }

  static void receiveAddressGenerated({
    required String asset,
    required String network,
    required String provider,
  }) {
    track('receive_address_generated', params: {
      'asset': asset,
      'network': network,
      'provider': provider,
    });
  }

  /// A Lightning invoice was generated on the receive screen (the
  /// "Request amount → Generate Invoice" control). `has_amount` flags
  /// whether a specific amount was requested — the amount value itself
  /// is never sent (no-amount telemetry rule).
  static void receiveInvoiceGenerated({required bool hasAmount}) {
    track('receive_invoice_generated', params: {
      'has_amount': hasAmount ? 1 : 0,
    });
  }

  // -- Payment Outcomes --

  // -- Send outcome (one pair per user-initiated send) --
  //
  // `transaction_sent` is a ledger observation: it diffs the ACTIVE
  // wallet's history, so it misses sends from other wallets and also sees
  // hidden funding legs of swaps/deposits. `send_completed`/`send_failed`
  // are the user-action outcome: exactly one per send the user confirmed,
  // from the flow that ran it. Dashboards count sends on these.
  static final Set<String> _sendOutcomeSeen = {};

  /// One completed user send. [flow]: pay | usd_send | watch_only |
  /// bitcoin_software | ledger | ... . [network]: lightning | spark |
  /// bitcoin | polygon | ... . [asset]: btc | usdc | usdt. [walletKind]:
  /// see [walletKind]. [provider]: breez | bdk | psbt | orchestra |
  /// native. [dedupeKey] (e.g. a payment id) is hashed and only used to
  /// fire once per send across retries/rebuilds; its reference travels
  /// as `send_ref`.
  static void sendCompleted({
    required String flow,
    required String network,
    required String asset,
    String? walletKind,
    String? provider,
    double? amountUsd,
    String? dedupeKey,
    double? amount,
    int? amountSats,
    String? currency,
    double? amountFiat,
    double? feeUsd,
    double? networkFeeUsd,
    int? feeSats,
    String? feeTier,
  }) {
    final ref = dedupeKey == null ? null : orderRef(dedupeKey);
    if (ref != null && !_sendOutcomeSeen.add('ok:$ref')) return;
    track('send_completed', params: {
      'flow': flow,
      'network': network,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (provider != null) 'provider': provider,
      if (ref != null) 'send_ref': ref,
      ...moneyParams(
        amountUsd: amountUsd,
        amount: amount ??
            (amountSats != null ? amountSats / 100000000 : null),
        asset: asset,
        amountSats: amountSats,
        currency: currency,
        amountFiat: amountFiat,
        feeUsd: feeUsd,
        networkFeeUsd: networkFeeUsd,
        feeSats: feeSats,
        feeTier: feeTier,
      ),
    });
    markMoneyAction('send', venue: network);
  }

  /// One failed user send. [error] is classified into `error_category`;
  /// its text never leaves. [stage]: validate | quote | sign | broadcast |
  /// settle.
  static void sendFailed({
    required String flow,
    required String network,
    required String asset,
    required Object? error,
    String? walletKind,
    String? provider,
    double? amountUsd,
    String? stage,
    double? amount,
    int? amountSats,
    String? currency,
    double? amountFiat,
    double? feeUsd,
    int? feeSats,
    String? feeTier,
    StackTrace? stackTrace,
  }) {
    recordHandled(errorCategory(error), error, stackTrace,
        flow: 'send_$flow', stage: stage);
    track('send_failed', params: {
      'flow': flow,
      'network': network,
      'error_category': errorCategory(error),
      if (walletKind != null) 'wallet_kind': walletKind,
      if (provider != null) 'provider': provider,
      if (stage != null) 'stage': stage,
      ...moneyParams(
        amountUsd: amountUsd,
        amount: amount ??
            (amountSats != null ? amountSats / 100000000 : null),
        asset: asset,
        amountSats: amountSats,
        currency: currency,
        amountFiat: amountFiat,
        feeUsd: feeUsd,
        feeSats: feeSats,
        feeTier: feeTier,
      ),
    });
  }

  static void paymentFailed(
      {required String network,
      required String reason,
      int? amountSats,
      String? errorCode,
      StackTrace? stackTrace}) {
    recordHandled(errorCategory(reason), reason, stackTrace,
        flow: 'payment', stage: network);
    track('payment_failed', params: {
      'network': network,
      'reason': _safeReason(reason) ?? '',
      'error_category': errorCategory(reason),
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void paymentCancelled({required String network}) {
    track('payment_cancelled', params: {'network': network});
  }

  // -- Settings --

  static void settingsChanged(
      {required String setting, String? value, String? previousValue}) {
    track('settings_changed', params: {
      'setting': setting,
      if (value != null) 'value': value,
      if (previousValue != null) 'previous_value': previousValue,
    });
  }

  // -- Notifications --

  static void notificationSubscribed({required String type}) {
    track('notification_subscribed', params: {'type': type});
  }

  // -- Coming Soon / Feature Discovery --

  static void comingSoonViewed({required String feature}) {
    track('coming_soon_viewed', params: {'feature': feature});
  }

  // -- Flow Tracking --

  static void sendFlowStarted({required String network}) {
    track('send_flow_started', params: {'network': network});
  }

  static void sendFlowAbandoned({required String network, String? step}) {
    track('send_flow_abandoned', params: {
      'network': network,
      if (step != null) 'step': step,
    });
  }

  static void receiveFlowCompleted({required String network}) {
    track('receive_flow_completed', params: {'network': network});
  }

  // -- Buy/Sell Flow --

  static void buyKycPreferenceSelected(String preference) {
    track('buy_kyc_preference_selected', params: {'preference': preference});
  }

  static void buyCurrencySelected(String currency) {
    track('buy_currency_selected', params: {'currency': currency});
  }

  static void buyMethodSelected(String method) {
    track('buy_method_selected', params: {'method': method});
  }

  static void currencyChanged({required String currency}) {
    track('currency_changed', params: {'currency': currency});
  }

  static void paymentMethodSelected({required String method}) {
    track('payment_method_selected', params: {'method': method});
  }

  // -- Errors --

  static void errorDisplayed(
      {required String screen, required String message}) {
    track('error_displayed', params: {
      'screen': screen,
      'message': message.length > 100 ? message.substring(0, 100) : message,
    });
  }

  // -- Settings Modals & Toggles --

  static void settingsModalOpened(String modal) {
    track('settings_modal_opened', params: {'modal': modal});
  }

  static void simpleModeToggled(bool enabled) {
    track('simple_mode_toggled', params: {'enabled': enabled ? 1 : 0});
  }

  // -- Affiliate Program --

  // Affiliate flow now lives entirely on kutewallet.com/affiliate. The app
  // only tracks: (1) the user landing on the affiliate intro screen, (2)
  // them tapping "Open dashboard", and (3) the prompt sheet that nudges
  // users to check out the program. Everything else (signups, claims,
  // referrer cuts) is server-side and tracked there.

  static void affiliateScreenViewed() {
    track('affiliate_screen_viewed');
  }

  static void affiliateDashboardOpened() {
    track('affiliate_dashboard_opened');
  }

  static void affiliatePromptShown() {
    track('affiliate_prompt_shown');
  }

  static void affiliatePromptDismissed() {
    track('affiliate_prompt_dismissed');
  }

  static void affiliatePromptCtaTapped() {
    track('affiliate_prompt_cta_tapped');
  }

  // -- P2P Trading --

  static void p2pBuyTapped() {
    track('p2p_buy_tapped');
  }

  static void p2pSellTapped() {
    track('p2p_sell_tapped');
  }

  static void electrumNodeSelected(String node) {
    track('electrum_node_selected', params: {'node': node});
    // Also persist the CURRENT node as a person property so we can segment
    // the whole base ("how many users are on a custom node right now"), not
    // just count change events. `custom` vs the named preset is the signal.
    setUserProperty('electrum_node', node);
    setUserProperty('uses_custom_electrum', (node == 'custom').toString());
  }

  /// Sets the Electrum-node person properties from the CURRENT stored setting
  /// at startup, so users who picked their node long ago (or never changed it)
  /// still report it — not only those who change it this session. [node] is
  /// the preset key, or 'custom' for a user-supplied server.
  static void reportElectrumNode(String node) {
    if (node.isEmpty) return;
    final n = node.toLowerCase();
    setUserProperty('electrum_node', n);
    setUserProperty('uses_custom_electrum', (n == 'custom').toString());
  }

  static void externalLinkOpened(String url) {
    track('external_link_opened', params: {
      'url': url.length > 100 ? url.substring(0, 100) : url,
    });
  }

  // -- Pay/Send Flow --

  static void payInputMethodChanged(String method) {
    track('pay_input_method_changed', params: {'method': method});
  }

  static void payAdvancedToggled(bool expanded) {
    // Encoded as 1/0 (not a bool) to keep this event's schema stable in
    // PostHog dashboards; the numeric convention predates the move off
    // Firebase Analytics and is kept so historical rows stay comparable.
    track('pay_advanced_toggled', params: {'expanded': expanded ? 1 : 0});
  }

  static void payFeePickerOpened() => track('pay_fee_picker_opened');

  static void payWalletPickerOpened() => track('pay_wallet_picker_opened');

  static void utxoSelected(int count) {
    track('utxo_selected', params: {'count': count});
  }

  // -- Buy/Sell Flow --

  static void buyCurrencyPickerOpened() => track('buy_currency_picker_opened');

  static void buyPaymentMethodPickerOpened() =>
      track('buy_payment_method_picker_opened');

  static void sellMaxAmountTapped() => track('sell_max_amount_tapped');

  static void sellBankDetailsSaved() => track('sell_bank_details_saved');

  static void consentCheckboxToggled(String flow, bool value) {
    track('consent_checkbox_toggled',
        params: {'flow': flow, 'value': value.toString()});
  }

  // -- Receive --

  /// A chain tap on the receive picker's chains rail ('all', or an
  /// Orchestra chain slug like 'tron' / 'ton'). The picker no longer
  /// carries native bitcoin/lightning entries (they live on the main
  /// receive screen), so `receive_native_rail_selected` was retired
  /// with them.
  static void receiveChainFilterSelected(String chain) =>
      track('receive_chain_filter_selected', params: {'chain': chain});

  /// A chain tap on the SEND destination picker's chains rail ('all',
  /// or an Orchestra chain slug like 'tron' / 'arbitrum'). Twin of
  /// [receiveChainFilterSelected] for the two-pane send picker.
  static void sendChainFilterSelected(String chain) =>
      track('send_chain_filter_selected', params: {'chain': chain});

  static void receiveUsernameEditOpened() =>
      track('receive_username_edit_opened');

  // -- Polymarket Extra --

  static void polymarketHelpOpened() => track('polymarket_help_opened');

  /// The slip opened on one outcome of a market. `market_id` is that
  /// outcome's token id, as the placement events send it. The parent
  /// event is named by `event_id`, `event_slug` and `event_title`, the
  /// market by `market_title` (its question, 80 characters) and the side
  /// by `outcome` (the outcome's name: "Yes", "Chiefs"): public Gamma
  /// data, each sent only when the caller or the registry has it.
  static void polymarketBetSlipOpened(
    String marketId, {
    String? source,
    String? category,
    String? walletKind,
    String? eventId,
    String? eventSlug,
    String? eventTitle,
    String? marketTitle,
    String? outcome,
    Map<String, Object>? extra,
  }) {
    track('polymarket_bet_slip_opened', params: {
      ...VenueAnalytics.pmKindParams([marketId], fallbackCategory: category),
      ...VenueAnalytics.pmEventParams([marketId, eventSlug],
          eventId: eventId, eventSlug: eventSlug, eventTitle: eventTitle),
      if (marketTitle != null && marketTitle.trim().isNotEmpty)
        'market_title': VenueAnalytics.title80(marketTitle),
      if (outcome != null && outcome.trim().isNotEmpty)
        'outcome': outcome.trim(),
      ...?extra,
      'market_id': marketId,
      if (source != null) 'source': source,
      if (category != null) 'category': category.toLowerCase(),
      if (walletKind != null) 'wallet_kind': walletKind,
    });
  }

  static void polymarketSellAllTapped(String marketId) {
    track('polymarket_sell_all_tapped', params: {'market_id': marketId});
  }

  static void polymarketTabChanged(String tab) {
    track('polymarket_tab_changed', params: {'tab': tab});
  }

  static void polymarketUseMaxTapped() => track('polymarket_use_max_tapped');

  // -- Transactions --

  static void transactionDetailViewed(String type) {
    track('transaction_detail_viewed', params: {'type': type});
  }

  static void transactionIdCopied() => track('transaction_id_copied');

  /// The notifications hub (trade results) was opened from its bell button.
  /// [unread] is how many results were unread, capped at 10. [entrySource]
  /// is where the bell sits: 'financial_hub' (the hub's header).
  static void tradeNotificationsOpened(
      {required int unread, String? entrySource}) {
    track('trade_notifications_opened', params: {
      'unread': unread > 10 ? 10 : unread,
      if (entrySource != null) 'entry_source': entrySource,
    });
  }

  /// A result in the notifications hub was tapped to open its receipt.
  /// [product] is the stored product key ('predictions' | 'trading'), never an id.
  static void tradeNotificationTapped({
    required String product,
    required bool wasUnread,
  }) {
    track('trade_notification_tapped', params: {
      'product': product,
      'was_unread': wasUnread,
    });
  }

  static void transactionFilterChanged(String filter) {
    track('transaction_filter_changed', params: {'filter': filter});
  }

  // -- Hardware Wallets --

  static void hardwareDeviceSelected(String device) {
    track('hardware_device_selected', params: {'device': device});
  }

  static void hardwareConnectionStarted(String device) {
    track('hardware_connection_started', params: {'device': device});
  }

  /// Transport picked in the Ledger device picker ('bluetooth' | 'usb').
  /// No device name or identifier is sent.
  static void ledgerTransportSelected(String transport) {
    track('ledger_transport_selected', params: {'transport': transport});
  }

  // -- Ledger account UI (Wallet hardening Phase 4a) --

  /// Ledger account screen opened (`tab`: bitcoin | investing | predictions).
  static void ledgerAccountViewed(String tab) {
    track('ledger_account_viewed', params: {'tab': tab});
  }

  static void ledgerTabSwitched(String tab) {
    track('ledger_tab_switched', params: {'tab': tab});
  }

  static void ledgerInvestingSetupViewed() =>
      track('ledger_investing_setup_viewed');

  static void ledgerEvmVerifyStarted() => track('ledger_evm_verify_started');

  /// `outcome`: success | cancelled | a LedgerFailureCode name
  /// (rejected, wrongDevice, unsupportedAppVersion, disconnected, ...).
  static void ledgerEvmVerifyResult(String outcome) {
    track('ledger_evm_verify_result', params: {'outcome': outcome});
  }

  static void ledgerBitcoinOnlyChosen() => track('ledger_bitcoin_only_chosen');

  /// Plan B10: `ledger_connect_started{transport, reason}`. [reason] is the
  /// LedgerActionKind name the connection is for.
  static void ledgerConnectStarted({
    required String transport,
    required String reason,
  }) =>
      track('ledger_connect_started',
          params: {'transport': transport, 'reason': reason});

  /// Plan B10: `ledger_connect_result{outcome, model}`. [outcome] is
  /// `connected` or a LedgerFailureCode name; [model] the device type name.
  static void ledgerConnectResult({
    required String outcome,
    required String model,
  }) =>
      track('ledger_connect_result',
          params: {'outcome': outcome, 'model': model});

  /// Plan B10: `ledger_approval_requested{action, clarity}`.
  static void ledgerApprovalRequested({
    required String action,
    required String clarity,
  }) =>
      track('ledger_approval_requested',
          params: {'action': action, 'clarity': clarity});

  /// Plan B10: `ledger_approval_result{action, outcome}`. [outcome] is
  /// approved, signed (funding sheets; their failures go through
  /// `ledgerFundingResult`), submitted_unknown, cancelled,
  /// app_auth_declined, a LedgerFailureCode name or a LedgerApprovalError
  /// name.
  static void ledgerApprovalResult({
    required String action,
    required String outcome,
  }) =>
      track('ledger_approval_result',
          params: {'action': action, 'outcome': outcome});

  /// Plan B10: `ledger_action_submitted{action, amount_bucket}`. Pass
  /// [amountUsd] (bucketed here) or an already bucketed [amountBucket];
  /// never an exact amount. Funding [action]s: `btc_to_hypercore`,
  /// `hypercore_to_btc`.
  static void ledgerActionSubmitted({
    required String action,
    double? amountUsd,
    String? amountBucket,
  }) =>
      track('ledger_action_submitted', params: {
        'action': action,
        if (amountUsd != null)
          'amount_bucket': usdBucket(amountUsd)
        else if (amountBucket != null)
          'amount_bucket': amountBucket,
      });

  /// A Ledger action sheet opened: pm_sell, pm_claim, pm_withdraw,
  /// hl_order, hl_transfer, hl_builder_fee.
  static void ledgerActionSheetOpened({required String action}) =>
      track('ledger_action_sheet_opened', params: {'action': action});

  /// "Check status" on a pending Ledger submission (read only, no prompt).
  /// [outcome]: confirmed, rejected or unknown.
  static void ledgerPendingChecked({
    required String action,
    required String outcome,
  }) =>
      track('ledger_pending_checked',
          params: {'action': action, 'outcome': outcome});

  /// A Ledger claim was refused before any prompt because the oracle
  /// result is not final on chain yet.
  static void ledgerClaimNotReady() => track('ledger_claim_not_ready');

  /// P4.8: the Cash App purchase into a Ledger asked for an on-device
  /// address check. [addressChanged] is false the first time a wallet is
  /// checked, true when the address differs from the last verified one.
  static void ledgerCashAppAddressCheckStarted({required bool addressChanged}) {
    track('ledger_cashapp_address_check_started',
        params: {'address_changed': addressChanged});
  }

  /// P4.8: outcome of the on-device check. [result] is one of verified,
  /// mismatch, cancelled, failed, unavailable. [failureCode] is the
  /// LedgerFailureCode name. Never an address or an amount.
  static void ledgerCashAppAddressCheckResult({
    required String result,
    String? failureCode,
  }) {
    track('ledger_cashapp_address_check_result', params: {
      'result': result,
      if (failureCode != null) 'failure_code': failureCode,
    });
  }

  // -- Wallet Creation/Import --

  static void walletTypeSelected(String type) {
    track('wallet_type_selected', params: {'type': type});
  }

  /// Parameterless: the chosen phrase length is seed-derived and never
  /// leaves the device.
  static void recoveryWordCountToggled() =>
      track('recovery_word_count_toggled');

  static void recoveryQrScannerOpened() => track('recovery_qr_scanner_opened');

  static void xpubImportMethodSelected(String method) {
    track('xpub_import_method_selected', params: {'method': method});
  }

  static void xpubAddressTypeSelected(String type) {
    track('xpub_address_type_selected', params: {'type': type});
  }

  static void signerStepCompleted(int step) {
    track('signer_step_completed', params: {'step': step});
  }

  static void signerQrDisplayed() => track('signer_qr_displayed');

  // -- Navigation --

  static void backButtonTapped(String screen) {
    track('back_button_tapped', params: {'screen': screen});
  }

  static void torchToggled(bool on) {
    track('torch_toggled', params: {'on': on});
  }

  // -- Session Lifecycle --

  static void appBackgrounded() => track('app_backgrounded');

  /// Coarse foreground-session-length bucket emitted when the app goes
  /// to background. Pairs with `app_backgrounded` to chart how long
  /// users actually stay in a session without shipping a raw
  /// fingerprintable duration. Buckets: '<10s' | '10-30s' | '30s-2m' |
  /// '2-10m' | '10m+'.
  static void appSession({required int durationSeconds}) {
    track('app_session',
        params: {'duration_bucket': _sessionBucket(durationSeconds)});
  }

  static String _sessionBucket(int seconds) {
    final s = seconds.abs();
    if (s < 10) return '<10s';
    if (s < 30) return '10-30s';
    if (s < 120) return '30s-2m';
    if (s < 600) return '2-10m';
    return '10m+';
  }

  static void appForegrounded({int? sessionGapSeconds}) {
    track('app_foregrounded', params: {
      if (sessionGapSeconds != null) 'session_gap_seconds': sessionGapSeconds,
    });
  }

  // ─── Toggle Tracking ─────────────────────────────────────────────

  /// Applies the persisted `analytics_opt_in` choice. main.dart calls this
  /// the moment Hive opens, before any event can fire. Synchronous for the
  /// Dart gates; the SDK opt-out is fire-and-forget, so startup never waits
  /// on it. The SDK also keeps its own opt-out across restarts, which covers
  /// the lifecycle events it sends before Dart runs.
  static void applyStoredOptOut() {
    if (isOptedIn) {
      _optedOut = false;
      return;
    }
    _optedOut = true;
    _dropPendingUserProperties();
    try {
      unawaited(Posthog().disable().catchError((Object _) {}));
    } catch (_) {}
  }

  /// The user opted out. From here nothing reaches PostHog: events,
  /// screens, person properties, identify, alias and flag reloads are all
  /// skipped, the pending person-property batch is dropped, and the SDK's
  /// unsent queue and identity are cleared. Crashlytics is unaffected.
  static Future<void> disableTracking() async {
    _optedOut = true;
    _dropPendingUserProperties();
    // reset() below clears the SDK's super properties too.
    _registeredAppLanguage = null;
    // Persist first: the choice holds even if an SDK call below hangs.
    await _persistOptIn(false);
    try {
      // reset() before disable(): reset clears the unsent event queue
      // (Android), identity and flag cache, and also drops the SDK's stored
      // opt-out, so disable() must come after it to persist.
      await Posthog()
          .reset()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      await Posthog()
          .disable()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {}
    // AppsFlyer shares the same opt-out: stop() halts all SDK traffic.
    await AppsFlyerService.setEnabled(false);
  }

  /// The user opted back in: tracking resumes and this install is
  /// identified again under its device UUID. A debug build stays muted.
  static Future<void> enableTracking() async {
    _optedOut = false;
    // Persisted opt-in FIRST — if the app booted opted-out, AppsFlyer
    // was never initialized and setEnabled(true) runs the full init,
    // which re-reads the flag.
    await _persistOptIn(true);
    if (!_disabled) {
      try {
        await Posthog()
            .enable()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      } catch (_) {}
      unawaited(identifyWithAffiliate(_lastAffiliateCode ?? '')
          .catchError((Object _) {}));
      unawaited(_setDefaultUserProperties().catchError((Object _) {}));
      final language = _appLanguage;
      if (language != null) setAppLanguage(language);
    }
    await AppsFlyerService.setEnabled(true);
  }

  static void _dropPendingUserProperties() {
    _userPropsFlushTimer?.cancel();
    _userPropsFlushTimer = null;
    _pendingUserProps.clear();
  }

  /// PostHog `beforeSend` hook: drops every event captured through the Dart
  /// SDK while tracking is off, a backstop behind the wrappers' own gates
  /// (it also catches the router's autocaptured screen views).
  static PostHogEvent? dropWhenMuted(PostHogEvent event) =>
      _muted ? null : event;

  /// True while product analytics are off (debug builds, the user's opt-out,
  /// or [disableTracking]).
  ///
  /// Analytics never steer the app: there are no PostHog feature-flag or
  /// remote-value readers. Business settings (fees, builder settings, the
  /// small-action allowance) come only from the backend runtime policy.
  static bool get isDisabled => _muted;

  /// Read the user's persisted opt-in choice for the Settings analytics
  /// toggle. Returns `true` (opted-in) when no explicit choice exists
  /// yet — matches the analytics-by-default policy on release builds.
  static bool get isOptedIn {
    try {
      if (Hive.isBoxOpen('settings')) {
        final v = Hive.box('settings').get('analytics_opt_in');
        if (v is bool) return v;
      }
    } catch (_) {}
    return true;
  }

  /// Test seam: the person properties waiting for the next coalesced
  /// `$set`.
  @visibleForTesting
  static Map<String, Object> get debugPendingUserProperties =>
      Map.unmodifiable(_pendingUserProps);

  /// Test seam: forget the in-memory opt-out and pending properties.
  @visibleForTesting
  static void debugResetOptOut() {
    _optedOut = false;
    _lastAffiliateCode = null;
    _dropPendingUserProperties();
  }

  static Future<void> _persistOptIn(bool optedIn) async {
    try {
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox('settings');
      }
      await Hive.box('settings').put('analytics_opt_in', optedIn);
    } catch (_) {}
  }

  /// GoRouter screen tracking is handled by `PosthogObserver` wired
  /// directly in `app_widget.dart`. This getter returns a no-op
  /// observer kept so legacy callers (router setup, tests) compile
  /// without conditional branches — remove once those references
  /// migrate.
  static NavigatorObserver get routeObserver => NavigatorObserver();

  // ═══════════════════════════════════════════════════════════════════
  // NEW EVENTS — funnel & retention expansion. All follow the existing
  // param style: numerics + enums, never PII.
  // ═══════════════════════════════════════════════════════════════════

  // ─── Onboarding (extra) ──────────────────────────────────────────
  /// Parameterless on purpose: the length of a recovery phrase is
  /// seed-derived and never leaves the device (see the class HARD RULE).
  static void recoveryPhraseDisplayed() => track('recovery_phrase_displayed');

  static void recoveryQuizStarted() => track('recovery_quiz_started');

  static void recoveryQuizCompleted() => track('recovery_quiz_completed');

  static void recoveryQuizFailed({int? failedAtWord}) {
    track('recovery_quiz_failed', params: {
      if (failedAtWord != null) 'failed_at_word': failedAtWord,
    });
  }

  static void mnemonicGenerated() => track('mnemonic_generated');

  /// Parameterless: the phrase length is seed-derived (see the HARD RULE).
  /// [evmFormat] is categorical only (legacy | standard | unchecked): which
  /// EVM format the recovered wallet got. [legacySignal], for legacy only,
  /// is what proved the legacy account in use (venue | polygon_balance |
  /// arbitrum_balance | nonce). Never an address or a balance.
  static void recoverySeedEntered({String? evmFormat, String? legacySignal}) =>
      track('recovery_seed_entered',
          params: evmFormat == null
              ? null
              : {
                  'evm_format': evmFormat,
                  if (legacySignal != null) 'legacy_signal': legacySignal,
                });

  /// The unlock-time retry of a recovery EVM format check that did not
  /// finish. [result]: switched_legacy | kept_standard | standard_active |
  /// incomplete; [legacySignal] as on `recovery_seed_entered`, with
  /// switched_legacy only.
  static void recoveryEvmFormatRechecked(
          {required String result, String? legacySignal}) =>
      track('recovery_evm_format_rechecked', params: {
        'result': result,
        if (legacySignal != null) 'legacy_signal': legacySignal,
      });

  static void firstAppLaunch() {
    if (OnceFlagsService.claimOnce('first_app_launch')) {
      track('first_app_launch');
    }
  }

  static void passkeyRestorePromptShown() =>
      track('passkey_restore_prompt_shown');

  static void pinEntryAbandoned() => track('pin_entry_abandoned');

  static void referrerCodeValidated({String? tierLevel}) {
    track('referrer_code_validated', params: {
      if (tierLevel != null) 'tier_level': tierLevel,
    });
  }

  // ─── Send / Receive (extra) ──────────────────────────────────────
  static void sendAmountEntered({required String network}) =>
      track('send_amount_entered', params: {'network': network});

  static void sendMaxTapped({required String network}) =>
      track('send_max_tapped', params: {'network': network});

  static void sendFeeSelected(
      {required String network, required String feeTier}) {
    track('send_fee_selected',
        params: {'network': network, 'fee_tier': feeTier});
  }

  static void sendReviewShown({required String network, int? amountSats}) {
    track('send_review_shown', params: {
      'network': network,
    });
  }

  static void sendValidationFailed({
    required String network,
    required String reason,
    int? amountSats,
  }) {
    track('send_validation_failed', params: {
      'network': network,
      'reason': _safeReason(reason) ?? '',
    });
  }

  static void receiveAmountEntered({required String network, int? amountSats}) {
    track('receive_amount_entered', params: {
      'network': network,
    });
  }

  static void paymentLinkPaid({double? amountUsd}) {
    track('payment_link_paid', params: {
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
    });
  }

  static void paymentLinkOpened() => track('payment_link_opened');

  static void lightningAddressRegistered() =>
      track('lightning_address_registered');

  // amountSats removed (never emitted, no callers) per the 2026-05
  // telemetry audit / no-amount rule.
  static void unclaimedDepositViewed() => track('unclaimed_deposit_viewed');

  static void autoClaimStarted() => track('auto_claim_started');

  static void autoClaimFailed({required int amountSats, String? reason}) {
    track('auto_claim_failed', params: {
      if (reason != null) 'reason': _safeReason(reason)!,
    });
  }

  static void qrScanFailed({String? type, String? reason}) {
    track('qr_scan_failed', params: {
      if (type != null) 'type': type,
      if (reason != null) 'reason': _safeReason(reason)!,
    });
  }

  // ─── Swap / Exchange (extra) ─────────────────────────────────────
  static void moveSheetAbandoned({String? step}) {
    track('move_sheet_abandoned', params: {
      if (step != null) 'step': step,
    });
  }

  /// Polymarket-specific deposit/withdraw failure events. Distinct from
  /// the generic `swap_failed` because the Polymarket revenue dashboard
  /// keys off these to break out P2 funnel drop-off (BTC→USDC.e deposit
  /// failed vs USDC→BTC withdrawal failed).
  static void polymarketDepositFailed({
    required double amountUsd,
    required String provider,
    required String reason,
    String? errorCode,
    String? stage, // pre_send | post_send
  }) {
    track('polymarket_deposit_failed', params: {
      'amount_bucket': _usdBucket(amountUsd),
      if (amountUsd.isFinite) 'amount_usd': _round(amountUsd, 2),
      'venue': 'polymarket',
      'provider': provider,
      if (stage != null) 'stage': stage,
      'error_category': errorCategory(reason),
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void polymarketWithdrawFailed({
    required double amountUsd,
    required String provider,
    required String reason,
    String? errorCode,
    String? stage, // pre_send | post_send
  }) {
    track('polymarket_withdraw_failed', params: {
      'amount_bucket': _usdBucket(amountUsd),
      if (amountUsd.isFinite) 'amount_usd': _round(amountUsd, 2),
      'venue': 'polymarket',
      'provider': provider,
      if (stage != null) 'stage': stage,
      'error_category': errorCategory(reason),
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  /// Fired after a hardware wallet has been successfully imported and
  /// the spawned wallet entry persisted to Hive. Distinct from
  /// `hardware_device_selected` (picker tap — user may abandon) and
  /// `wallet_created` (which fires for every wallet type including hot
  /// & watch-only).
  static void hardwareWalletAdded({
    required String device, // 'jade' | 'ledger' | 'keystone' | ...
    required String
        scriptType, // 'segwit' | 'taproot' | 'nested_segwit' | 'legacy'
    required int walletCount,
  }) {
    track('hardware_wallet_added', params: {
      'device': device,
      'script_type': scriptType,
      'wallet_count': walletCount,
    });
  }

  /// Fired on the first qualifying provider event when the user was
  /// referred. Backend already tracks this via `logProviderEvent`, but
  /// emitting client-side gives us a Firebase funnel signal for
  /// referee → revenue conversion without round-tripping through BQ.
  /// Only a referred account counts, per the backend's referral flag in the
  /// latest runtime capabilities; with no policy loaded nothing is sent and
  /// the once-per-device flag ([OnceFlagsService]) stays unclaimed, so a
  /// later qualifying event can still fire it.
  static void affiliateRefereeConverted({
    required String provider,
    double? amountUsd,
  }) {
    try {
      if (RuntimeCapabilitiesService.instance.snapshot?.isReferred != true) {
        return;
      }
    } catch (_) {
      return;
    }
    if (!OnceFlagsService.claimOnce('affiliate_referee_converted')) return;
    track('affiliate_referee_converted', params: {
      'provider': provider,
      if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
    });
  }

  /// Fired when the bet-slip sheet is dismissed without a placed order.
  /// The slip's State tracks `_orderPlaced` and only fires this event
  /// on dispose if the flag is false. `marketId` here is the slip's
  /// market question truncated to 80 chars (analytics-safe; the
  /// question is shown publicly on Polymarket already).
  static void betSlipAbandoned({
    required String marketId,
    required bool hadAmount,
    required bool hadOutcomeSelected,
    Map<String, Object>? extra,
  }) {
    track('bet_slip_abandoned', params: {
      ...?extra,
      'market_id': marketId.length > 80 ? marketId.substring(0, 80) : marketId,
      'had_amount': hadAmount ? 1 : 0,
      'had_outcome_selected': hadOutcomeSelected ? 1 : 0,
    });
  }

  // ─── Polymarket (extra) ──────────────────────────────────────────
  static void polymarketTabOpened() => track('polymarket_tab_opened');

  static void polymarketSearchOpened({int? queryLength}) {
    track('polymarket_search_opened', params: {
      if (queryLength != null) 'query_length': queryLength,
    });
  }

  /// Browse-depth engagement on the Predictions list. [depthPct] is the
  /// scroll progress 0-100; we bucket it to a coarse [depth_bucket]
  /// ('25' | '50' | '75' | '100') so a raw pixel/percent offset tied to
  /// the pseudonymous id never leaves the device. Callers fire once per
  /// threshold crossed.
  static void polymarketListScrolled({required int depthPct}) {
    final String bucket = depthPct >= 100
        ? '100'
        : depthPct >= 75
            ? '75'
            : depthPct >= 50
                ? '50'
                : '25';
    track('polymarket_list_scrolled', params: {'depth_bucket': bucket});
  }

  static void polymarketOutcomeChipTapped({
    required String marketId,
    required String outcome,
  }) {
    track('polymarket_outcome_chip_tapped', params: {
      'market_id': marketId,
      'outcome': outcome,
    });
  }

  static void polymarketBetAmountEntered({required String marketId}) =>
      track('polymarket_bet_amount_entered', params: {'market_id': marketId});

  static void polymarketBetConfirmationShown({
    required String marketId,
    required double amountUsdc,
  }) {
    track('polymarket_bet_confirmation_shown', params: {
      'market_id': marketId,
      'amount_bucket': _usdBucket(amountUsdc),
    });
  }

  static void polymarketBetDepositFailed({
    required String reason,
    String? provider,
  }) {
    track('polymarket_bet_deposit_failed', params: {
      'reason': _safeReason(reason) ?? '',
      if (provider != null) 'provider': provider,
    });
  }

  static void polymarketClobOrderFailed({
    required String marketId,
    required String reason,
    StackTrace? stackTrace,
  }) {
    recordHandled(errorCategory(reason), reason, stackTrace,
        flow: 'polymarket_clob', stage: 'order');
    track('polymarket_clob_order_failed', params: {
      'market_id': marketId,
      'reason': _safeReason(reason) ?? '',
    });
  }

  static void polymarketSlippageAdjusted({
    double? oldSlippage,
    double? newSlippage,
  }) {
    track('polymarket_slippage_adjusted', params: {
      if (oldSlippage != null) 'old_slippage': oldSlippage,
      if (newSlippage != null) 'new_slippage': newSlippage,
    });
  }

  static void polymarketRedeemInitiated({
    required String marketId,
    String? trigger, // auto | manual
    String? surface, // home | portfolio_card | position_detail | activity
  }) =>
      track('polymarket_redeem_initiated', params: {
        ...VenueAnalytics.pmKindParams([marketId]),
        'market_id': marketId,
        if (trigger != null) 'trigger': trigger,
        if (surface != null) 'surface': surface,
      });

  static void polymarketRedeemFailed({
    required String marketId,
    required String reason,
    String? trigger,
    String? surface,
  }) {
    track('polymarket_redeem_failed', params: {
      ...VenueAnalytics.pmKindParams([marketId]),
      'market_id': marketId,
      'reason': _safeReason(reason) ?? '',
      'error_category': errorCategory(reason),
      if (trigger != null) 'trigger': trigger,
      if (surface != null) 'surface': surface,
    });
  }

  static void polymarketGeoblockedShown() =>
      track('polymarket_geoblocked_shown');

  static void polymarketSellInitiated({
    required String marketId,
    String? category,
    String? walletKind,
    Map<String, Object>? extra,
  }) =>
      track('polymarket_sell_initiated', params: {
        ...VenueAnalytics.pmKindParams([marketId], fallbackCategory: category),
        ...?extra,
        'market_id': marketId,
        if (category != null) 'category': category.toLowerCase(),
        if (walletKind != null) 'wallet_kind': walletKind,
      });

  static void polymarketSellAmountEntered({required String marketId}) =>
      track('polymarket_sell_amount_entered', params: {'market_id': marketId});

  static void polymarketPartialSold({
    required String marketId,
    required double pctSold,
  }) {
    track('polymarket_partial_sold', params: {
      'market_id': marketId,
      'pct_sold': pctSold,
    });
  }

  static void polymarketFirstBetPlaced() {
    if (OnceFlagsService.claimOnce('polymarket_first_bet_placed')) {
      track('polymarket_first_bet_placed');
    }
  }

  static void polymarketFirstProfitableRedeem({required double pnl}) {
    if (OnceFlagsService.claimOnce('polymarket_first_profitable_redeem')) {
      // Bucket the P&L — an exact profit value tied to the pseudonymous
      // distinct_id builds a financial profile. Mirrors the
      // polymarketPositionSold pattern (pnl_bucket + pnl_direction).
      track('polymarket_first_profitable_redeem', params: {
        'pnl_bucket': _usdBucket(pnl.abs()),
        'pnl_direction': pnl >= 0 ? 'profit' : 'loss',
      });
    }
  }

  static void polymarketPositionWinLoss({
    required String marketId,
    required double pnl,
    required String outcome,
  }) {
    // Bucket the P&L rather than sending the exact profit/loss value
    // alongside market_id (no-exact-amount rule). `outcome` already
    // carries the win/loss direction.
    track('polymarket_position_win_loss', params: {
      'market_id': marketId,
      'pnl_bucket': _usdBucket(pnl.abs()),
      'outcome': outcome,
    });
  }

  static void polymarketBuilderCodeRegistered({required bool success}) =>
      track('polymarket_builder_code_registered',
          params: {'success': success ? 1 : 0});

  // ─── Hyperliquid (Trading tab) ───────────────────────────────────
  // Mirrors the Polymarket event set: amounts always bucketed via
  // _usdBucket, freeform errors scrubbed via _safeReason, real trades
  // feed the affiliate pipeline exactly like bets do.

  static void hyperliquidTabOpened() => track('hyperliquid_tab_opened');

  /// A market row/detail opened from the Trading tab. [kind] is
  /// 'perp' | 'spot'; coin symbols are public market data.
  static void hyperliquidMarketViewed({
    required String coin,
    required String kind,
    Map<String, Object>? extra,
  }) {
    track('hyperliquid_market_viewed', params: {
      ...VenueAnalytics.hlAssetParams(coin, kind: kind),
      ...?extra,
      'coin': coin,
      'kind': kind,
    });
  }

  static void hyperliquidOrderSlipOpened({
    required String coin,
    required String kind,
    String? source, // 'market_detail' | 'advisor' | 'position_card'
    String? walletKind,
    Map<String, Object>? extra,
  }) {
    track('hyperliquid_order_slip_opened', params: {
      ...VenueAnalytics.hlAssetParams(coin, kind: kind),
      ...?extra,
      'coin': coin,
      'kind': kind,
      if (source != null) 'source': source,
      if (walletKind != null) 'wallet_kind': walletKind,
    });
  }

  /// A perp/spot order accepted by the exchange (resting or filled).
  /// Activity only. Revenue is reported from matched exchange fills, never
  /// from acceptance or the requested order notional.
  ///
  /// No `order_ref`: the database holds no Hyperliquid order id to join
  /// to, and an `oid` is a public sequential number, so even its hash could
  /// be reversed and looked up on the public exchange to find the account.
  static void hyperliquidOrderPlaced({
    required String coin,
    required String kind, // 'perp' | 'spot'
    required bool isBuy, // long/buy = true, short/sell = false
    required int leverage, // 1 for spot
    required double marginUsd,
    required double notionalUsd,
    String? source, // 'market' | 'advisor' | 'autofire'
    String? providerOrderId,
    String? orderType, // market | limit | tp | sl | scale | twap | trailing
    bool reduceOnly = false,
    bool? isCross,
    bool hasTp = false,
    bool hasSl = false,
    bool? filled,
    String walletKind = 'hot',
    String? marketType, // perp | spot | <hip3 builder dex name>
    bool? builderFeeApplied,
    double? limitPrice,
    // Intent source behind an autofired order (sal | advisor | market…);
    // `source` stays 'autofire' so both survive.
    String? origin,
    Map<String, Object>? extra,
  }) {
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    markMoneyAction('hl_order', venue: 'hyperliquid');
    track('hyperliquid_order_placed', params: {
      ...VenueAnalytics.staged('hl', coin),
      ...VenueAnalytics.hlAssetParams(coin, kind: kind),
      ...?extra,
      if (origin != null) 'origin': origin,
      'venue': 'hyperliquid',
      'coin': coin,
      'market': coin,
      'kind': kind,
      'market_type': marketType ?? kind,
      // Spot has buy/sell, perps long/short; `side` keeps its legacy
      // long/short values, `trade_side` is the venue-native word.
      'side': isBuy ? 'long' : 'short',
      'trade_side': kind == 'spot'
          ? (isBuy ? 'buy' : 'sell')
          : (isBuy ? 'long' : 'short'),
      'intent': reduceOnly ? 'close' : 'open',
      if (orderType != null) 'order_type': orderType,
      'leverage': leverage,
      'leverage_bucket': leverageBucket(leverage),
      if (isCross != null) 'margin_mode': isCross ? 'cross' : 'isolated',
      'reduce_only': reduceOnly,
      'has_tp': hasTp,
      'has_sl': hasSl,
      if (filled != null) 'fill_status': filled ? 'filled' : 'resting',
      'wallet_kind': walletKind,
      if (builderFeeApplied != null) 'builder_fee_applied': builderFeeApplied,
      'margin_bucket': _usdBucket(marginUsd),
      'notional_bucket': _usdBucket(notionalUsd),
      if (marginUsd.isFinite) 'margin_usd': _round(marginUsd, 2),
      if (notionalUsd.isFinite) 'notional_usd': _round(notionalUsd, 2),
      if (notionalUsd.isFinite) 'amount_usd': _round(notionalUsd, 2),
      if (limitPrice != null && limitPrice.isFinite) 'limit_price': limitPrice,
      if (source != null) 'source': source,
    });
    // Accounting is emitted per confirmed fill by HyperliquidRevenue.
    // An accepted/resting order is activity, not earned builder revenue.
  }

  static void hyperliquidOrderFailed({
    required String coin,
    required String reason,
    String? errorCode,
    String? action, // open | close | modify | trigger | twap | trailing
    String? orderType,
    bool? isBuy,
    double? notionalUsd,
    int? leverage,
    String? walletKind,
    StackTrace? stackTrace,
    Map<String, Object>? extra,
  }) {
    recordHandled(errorCategory(reason), reason, stackTrace,
        flow: 'hl_order', stage: action);
    track('hyperliquid_order_failed', params: {
      ...VenueAnalytics.staged('hl', coin),
      ...VenueAnalytics.hlAssetParams(coin),
      ...?extra,
      'venue': 'hyperliquid',
      'coin': coin,
      'market': coin,
      if (action != null) 'action': action,
      if (orderType != null) 'order_type': orderType,
      if (isBuy != null) 'side': isBuy ? 'long' : 'short',
      if (leverage != null) 'leverage': leverage,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (notionalUsd != null && notionalUsd.isFinite) ...{
        'notional_usd': _round(notionalUsd, 2),
        'notional_bucket': _usdBucket(notionalUsd),
      },
      'error_category': errorCategory(reason),
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  /// A position (fully or partially) closed. [fractionPct] ∈ (0, 100].
  /// No `order_ref`, for the reason given on [hyperliquidOrderPlaced].
  static void hyperliquidPositionClosed({
    required String coin,
    required int fractionPct,
    required double payoutUsd,
    double? pnlUsd,
    String? providerOrderId,
    bool? wasLong,
    int? leverage,
    String walletKind = 'hot',
    String? orderType, // market | limit
    double? notionalUsd,
    Map<String, Object>? extra,
  }) {
    _bumpAffiliateActivity(); // count toward affiliate activity (all tx types)
    track('hyperliquid_position_closed', params: {
      ...VenueAnalytics.hlAssetParams(coin),
      ...?extra,
      'venue': 'hyperliquid',
      'coin': coin,
      'market': coin,
      if (wasLong != null) 'side': wasLong ? 'long' : 'short',
      if (leverage != null) 'leverage': leverage,
      if (leverage != null) 'leverage_bucket': leverageBucket(leverage),
      'wallet_kind': walletKind,
      if (orderType != null) 'order_type': orderType,
      'close_scope': fractionPct >= 100 ? 'full' : 'partial',
      if (payoutUsd.isFinite) 'amount_usd': _round(payoutUsd, 2),
      if (pnlUsd != null && pnlUsd.isFinite) 'pnl_usd': _round(pnlUsd, 2),
      if (notionalUsd != null && notionalUsd.isFinite)
        'notional_usd': _round(notionalUsd, 2),
      'fraction_pct': fractionPct,
      'payout_bucket': _usdBucket(payoutUsd),
      if (pnlUsd != null) 'pnl_bucket': _usdBucket(pnlUsd),
      if (pnlUsd != null) 'pnl_direction': pnlUsd >= 0 ? 'gain' : 'loss',
    });
    // Accounting is emitted per confirmed fill by HyperliquidRevenue.
    // An accepted/resting order is activity, not earned builder revenue.
  }

  static void hyperliquidLeverageAdjusted({
    required String coin,
    required int leverage,
    String? source, // user | order_auto
    bool? isCross,
  }) =>
      track('hyperliquid_leverage_adjusted', params: {
        ...VenueAnalytics.hlAssetParams(coin),
        'coin': coin,
        'leverage': leverage,
        'leverage_bucket': leverageBucket(leverage),
        if (source != null) 'source': source,
        if (isCross != null) 'margin_mode': isCross ? 'cross' : 'isolated',
      });

  static void hyperliquidOrderCancelled({
    required String coin,
    String? scope, // single | all | twap
    String? orderType,
    String? walletKind,
    Map<String, Object>? extra,
  }) =>
      track('hyperliquid_order_cancelled', params: {
        ...VenueAnalytics.hlAssetParams(coin),
        ...?extra,
        'coin': coin,
        'venue': 'hyperliquid',
        if (scope != null) 'scope': scope,
        if (orderType != null) 'order_type': orderType,
        if (walletKind != null) 'wallet_kind': walletKind,
      });

  static void hyperliquidTradingEnabled({String? walletKind}) =>
      track('hyperliquid_trading_enabled', params: {
        if (walletKind != null) 'wallet_kind': walletKind,
      });

  static void hyperliquidGeoblockedShown() =>
      track('hyperliquid_geoblocked_shown');

  // The old vault "Earn" helpers were removed with that integration, and
  // the Flashnet USDB Earn funnel that replaced them was removed with the
  // Earn product itself. Retire both sets of event names (earn_*, usdb_*,
  // yield_*) in the PostHog UI separately.

  static void hyperliquidCategoryChanged(String category) =>
      track('hyperliquid_category_changed', params: {'category': category});

  static void hyperliquidDepositInitiated({
    double? amountUsd,
    String? sourceAsset, // btc | usd
    String? walletKind,
    String? route, // direct | eoa_sweep
  }) =>
      track('hyperliquid_deposit_initiated', params: {
        'venue': 'hyperliquid',
        if (sourceAsset != null) 'source_asset': sourceAsset,
        if (walletKind != null) 'wallet_kind': walletKind,
        if (route != null) 'route': route,
        ...moneyParams(amountUsd: amountUsd),
      });

  /// [orderId] / [quoteId]: the Orchestra order (and quote) that moved the
  /// money, sent only as the database join keys (see [orchestraJoinParams]).
  static void hyperliquidDepositCompleted({
    double? amountUsd,
    String? route, // direct | eoa_sweep
    String? walletKind,
    String? sourceAsset,
    String? orderId,
    String? quoteId,
  }) {
    track('hyperliquid_deposit_completed', params: {
      'venue': 'hyperliquid',
      ...orchestraJoinParams(orderId, quoteId: quoteId),
      if (route != null) 'route': route,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (sourceAsset != null) 'source_asset': sourceAsset,
      ...moneyParams(amountUsd: amountUsd, asset: 'usdc', amount: amountUsd),
    });
    markMoneyAction('deposit', venue: 'hyperliquid');
  }

  static void hyperliquidDepositFailed({
    required String reason,
    double? amountUsd,
    String? route,
    String? walletKind,
  }) =>
      track('hyperliquid_deposit_failed', params: {
        'venue': 'hyperliquid',
        'reason': _safeReason(reason) ?? '',
        'error_category': errorCategory(reason),
        if (route != null) 'route': route,
        if (walletKind != null) 'wallet_kind': walletKind,
        ...moneyParams(amountUsd: amountUsd),
      });

  static void hyperliquidWithdrawInitiated({
    double? amountUsd,
    String? destination, // btc | usd
    String? walletKind,
  }) =>
      track('hyperliquid_withdraw_initiated', params: {
        'venue': 'hyperliquid',
        if (destination != null) 'destination': destination,
        if (walletKind != null) 'wallet_kind': walletKind,
        ...moneyParams(amountUsd: amountUsd),
      });

  /// [orderId] / [quoteId]: as on [hyperliquidDepositCompleted].
  static void hyperliquidWithdrawCompleted({
    double? amountUsd,
    String? destination,
    String? walletKind,
    String? route,
    String? orderId,
    String? quoteId,
  }) =>
      track('hyperliquid_withdraw_completed', params: {
        'venue': 'hyperliquid',
        ...orchestraJoinParams(orderId, quoteId: quoteId),
        if (destination != null) 'destination': destination,
        if (walletKind != null) 'wallet_kind': walletKind,
        if (route != null) 'route': route,
        ...moneyParams(amountUsd: amountUsd, asset: 'usdc', amount: amountUsd),
      });

  static void hyperliquidWithdrawFailed({
    required String reason,
    double? amountUsd,
    String? destination,
    String? walletKind,
  }) =>
      track('hyperliquid_withdraw_failed', params: {
        'venue': 'hyperliquid',
        'reason': _safeReason(reason) ?? '',
        'error_category': errorCategory(reason),
        if (destination != null) 'destination': destination,
        if (walletKind != null) 'wallet_kind': walletKind,
        ...moneyParams(amountUsd: amountUsd),
      });

  // ─── Predictions (Phase 5 engagement) ────────────────────────────

  /// Fired when the position-detail sheet opens (the per-position
  /// breakdown / value-chart sheet). Distinct from
  /// `prediction_market_viewed` (a market in the browse list) — this is
  /// a user inspecting one of their own held positions. No market id /
  /// amount: a coarse engagement signal only.
  static void predictionsPositionDetailViewed() =>
      track('predictions_position_detail_viewed');

  /// Fired when the user triggers the "Claim winnings → convert to BTC"
  /// flow from the claim sheet. [result] is the coarse outcome:
  /// 'initiated' (sweep started) | 'failed' (the trigger threw). The
  /// on-chain redeem of a *winning* position is covered separately by
  /// `polymarket_position_redeemed`; this tracks the user-initiated
  /// cash-out-to-Bitcoin action. No amount / market id.
  static void predictionsClaim({required String result}) =>
      track('predictions_claim', params: {'result': result});

  // ─── Affiliate / Earn (extra) ────────────────────────────────────
  static void affiliateCodeShared({String? method, String? result, String? surface}) =>
      track('affiliate_code_shared', params: {
        if (method != null) 'method': method, // sheet | image
        if (result != null) 'result': result, // success | dismissed | unavailable
        if (surface != null) 'surface': surface,
      });

  static void affiliateCodeCopied({String? surface}) =>
      track('affiliate_code_copied', params: {
        if (surface != null) 'surface': surface,
      });

  // ── Affiliate v2 (Earn screen) ──
  // Coarse, PII-free engagement + funnel events for the rebuilt Earn
  // screen. No amounts (owed/paid USD stay off the wire per the no-amount
  // rule); counts are coarse program metrics, not per-user financials.

  /// Earn screen (v2) opened. `state` = 'dashboard' | 'coming_soon' | 'error'.
  static void affiliateEarnViewed({required String state}) {
    screenView('Affiliate');
    track('affiliate_earn_viewed', params: {'state': state});
  }

  /// Share-link/QR surface opened (the share sheet or QR reveal).
  static void affiliateShareOpened({required String method}) =>
      track('affiliate_share_opened', params: {'method': method});

  /// The AppsFlyer OneLink share link was generated for the QR/share.
  /// `linkType` = 'local' (instant template link) | 'branded' (short link).
  static void affiliateShareLinkGenerated({required String linkType}) =>
      track('affiliate_share_link_generated', params: {'link_type': linkType});

  /// The earnings-graph window selector changed. `days` = 7 | 30 | 90.
  static void affiliateHistoryWindowChanged({required int days}) =>
      track('affiliate_history_window_changed', params: {'days': days});

  /// The anonymized referee list was expanded/viewed.
  static void affiliateRefereesViewed({required int boundCount}) =>
      track('affiliate_referees_viewed', params: {'bound_count': boundCount});

  /// The app reported its lifetime tx-count activity milestone to the
  /// backend (powers the >10-transactions activation rule). Fires once
  /// per device when crossing the threshold.
  static void affiliateActivityReported() =>
      track('affiliate_activity_reported');

  /// The wallet pulled a changed affiliate code from the backend (admin
  /// rename propagated to this device). No code value sent — just the
  /// event so we can see rename propagation working.
  static void affiliateCodePulled() => track('affiliate_code_pulled');

  /// The in-app late-entry referrer card was submitted. `result` =
  /// 'ok' | 'not_found' | 'already_set' | 'past_window' | 'self' | 'error'.
  static void affiliateLateEntrySubmitted({required String result}) =>
      track('affiliate_late_entry_submitted', params: {'result': result});

  /// A referrer code was auto-bound from an AppsFlyer deferred-deeplink
  /// install (no manual entry). Parameterless: the code itself never goes
  /// to analytics, only the fact that auto-attribution fired.
  static void affiliateReferrerAutoBound() =>
      track('affiliate_referrer_auto_bound');

  static void affiliateTierUnlocked({required String tierLevel}) =>
      track('affiliate_tier_unlocked', params: {'tier_level': tierLevel});

  // amount_sats removed from the payload per the 2026-05 telemetry
  // audit / no-amount rule — raw sats keyed to the pseudonymous
  // user_id is ledger-rebuild-grade telemetry. Fire with no amount.
  static void affiliateClaimAvailable() => track('affiliate_claim_available');

  static void affiliateClaimInitiated() => track('affiliate_claim_initiated');

  static void affiliateClaimCompleted(
      {required int amountSats, String? claimId}) {
    track('affiliate_claim_completed', params: {
      if (claimId != null) 'claim_id': claimId,
    });
  }

  static void affiliateClaimFailed(
      {required String reason, String? errorCode}) {
    track('affiliate_claim_failed', params: {
      'reason': _safeReason(reason) ?? '',
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static void affiliateReferrerCodeSubmitted({
    required int statusCode,
    String? tierLevel,
  }) {
    track('affiliate_referrer_code_submitted', params: {
      'status_code': statusCode,
      if (tierLevel != null) 'tier_level': tierLevel,
    });
  }

  static void affiliateReferrerCodeValidationFailed({required String reason}) =>
      track('affiliate_referrer_code_validation_failed',
          params: {'reason': _safeReason(reason) ?? ''});

  static void affiliateBackgroundRegistrationAttempt({
    required int attemptNumber,
    required bool success,
  }) {
    track('affiliate_background_registration_attempt', params: {
      'attempt_number': attemptNumber,
      'success': success ? 1 : 0,
    });
  }

  static void affiliateAuthWalletCompleted({
    required bool success,
    bool? referrerBound,
    String? reason,
  }) {
    track('affiliate_auth_wallet_completed', params: {
      'success': success ? 1 : 0,
      if (referrerBound != null) 'referrer_bound': referrerBound ? 1 : 0,
      if (reason != null) 'reason': _safeReason(reason)!,
    });
  }

  // ─── Settings / Wallet Management (extra) ────────────────────────
  static void secureKeyMaterialViewed({required String materialType}) =>
      track('secure_key_material_viewed',
          params: {'material_type': materialType});

  static void secureKeyMaterialCopied({required String materialType}) =>
      track('secure_key_material_copied',
          params: {'material_type': materialType});

  static void pinChangeCompleted() => track('pin_change_completed');

  static void pinChangeFailed({String? reason}) {
    track('pin_change_failed', params: {
      if (reason != null) 'reason': _safeReason(reason)!,
    });
  }

  static void transactionPdfExported({required int walletCount}) =>
      track('transaction_pdf_exported', params: {'wallet_count': walletCount});

  static void transactionPdfExportFailed({
    required int walletCount,
    String? reason,
  }) {
    track('transaction_pdf_export_failed', params: {
      'wallet_count': walletCount,
      if (reason != null) 'reason': _safeReason(reason)!,
    });
  }

  static void walletDeleteInitiated() => track('wallet_delete_initiated');

  static void walletRenamed() => track('wallet_renamed');

  // ─── App Lifecycle / Errors / Retention (extra) ──────────────────
  static void appColdStartCompleted({
    required int startupMs,
    required bool hasWallet,
    String? walletCategory,
  }) {
    track('app_cold_start_completed', params: {
      'startup_ms': startupMs,
      'has_wallet': hasWallet ? 1 : 0,
      if (walletCategory != null) 'wallet_category': walletCategory,
    });
  }

  static void appWarmResumeCompleted({
    required int gapSeconds,
    required String sessionType,
  }) {
    track('app_warm_resume_completed', params: {
      'gap_seconds': gapSeconds,
      'session_type': sessionType,
    });
  }

  static void appFirstOpenOfDay() => track('app_first_open_of_day');

  static void sparkSdkConnectFailed(
      {String? errorCode, int? attempt, Object? error, StackTrace? stackTrace}) {
    recordHandled(errorCategory(error ?? errorCode), error ?? errorCode,
        stackTrace,
        flow: 'spark_sdk', stage: 'connect');
    track('spark_sdk_connect_failed', params: {
      if (errorCode != null) 'error_code': errorCode,
      if (attempt != null) 'attempt': attempt,
    });
  }

  static void syncPipelineFailed({
    required String pipeline,
    String? errorCode,
    int? lastSuccessAgoSeconds,
    Object? error,
    StackTrace? stackTrace,
  }) {
    recordHandled(errorCategory(error ?? errorCode), error ?? errorCode,
        stackTrace,
        flow: 'sync', stage: pipeline);
    track('sync_pipeline_failed', params: {
      'pipeline': pipeline,
      if (errorCode != null) 'error_code': errorCode,
      if (lastSuccessAgoSeconds != null)
        'last_success_ago_seconds': lastSuccessAgoSeconds,
    });
  }

  static void backgroundSyncExecuted({
    required int durationMs,
    required int failedPipelineCount,
  }) {
    track('background_sync_executed', params: {
      'duration_ms': durationMs,
      'failed_pipeline_count': failedPipelineCount,
    });
  }

  static void deepLinkOpened({
    required String linkType,
    required bool wasColdStart,
  }) {
    track('deep_link_opened', params: {
      'link_type': linkType,
      'was_cold_start': wasColdStart ? 1 : 0,
    });
  }

  static void pushNotificationReceived({String? notificationType}) {
    track('push_notification_received', params: {
      if (notificationType != null) 'notification_type': notificationType,
    });
  }

  static void pushNotificationOpened({String? notificationType}) {
    track('push_notification_opened', params: {
      if (notificationType != null) 'notification_type': notificationType,
    });
  }

  /// Fired immediately before the OS push-permission prompt is shown
  /// (the `FirebaseMessaging.requestPermission()` call). [surface] is
  /// where the ask came from: `onboarding_home` (the automatic once-per-
  /// install prompt on the first Home after onboarding) or `settings`.
  static void pushPermissionRequested({required String surface}) =>
      track('push_permission_requested', params: {'surface': surface});

  /// Fired with the resolved permission outcome. [status] is the
  /// `NotificationSettings.authorizationStatus` bucketed to
  /// `granted` / `provisional` / `denied` (notDetermined counts as
  /// denied: the sheet was dismissed without an answer). `granted` keeps
  /// the coarse 1/0 the existing dashboards chart. No token / PII.
  static void pushPermissionResult({required String status}) =>
      track('push_permission_result', params: {
        'status': status,
        'granted': status == 'granted' || status == 'provisional' ? 1 : 0,
      });

  static void pullToRefreshExecuted({required String screen}) =>
      track('pull_to_refresh_executed', params: {'screen': screen});

  static void homeActivityRowTapped({required String activityType}) =>
      track('home_activity_row_tapped',
          params: {'activity_type': activityType});

  static void networkStatusChanged({required bool online}) =>
      track('network_status_changed', params: {'online': online ? 1 : 0});

  // ─── Reliability / Perf (Phase 1) ────────────────────────────────

  /// Cold-start latency from the first line of `main()` to the first
  /// home render. Fired once per process from the first home route push.
  /// Only the coarse [_latencyBucket] is emitted — never the raw ms.
  static void appColdStart({required int latencyMs}) {
    track('app_cold_start',
        params: {'latency_bucket': _latencyBucket(latencyMs)});
  }

  /// Spark SDK (`BreezSdkSparkLib.init`) connect outcome + latency. The
  /// init's own error reporting stays; this adds a success/timeout/error
  /// signal so we can chart connect reliability. `result` is one of
  /// 'ok' | 'timeout' | 'error'.
  static void sparkSdkConnect(
      {required String result, required int latencyMs}) {
    track('spark_sdk_connect', params: {
      'result': result,
      'latency_bucket': _latencyBucket(latencyMs),
    });
  }

  /// BDK scoped Electrum scan outcome + latency. `result` is 'ok' |
  /// 'error'; `source` is the surface that triggered the scan
  /// ('wallet_detail' | 'move' | 'unknown'). No wallet id / balance.
  static void bdkScan({
    required String result,
    required int latencyMs,
    required String source,
  }) {
    track('bdk_scan', params: {
      'result': result,
      'latency_bucket': _latencyBucket(latencyMs),
      'source': source,
    });
  }

  static void biometricPromptCancelled() => track('biometric_prompt_cancelled');

  /// Top-level uncaught exception capture. Wired to `FlutterError.onError`
  /// + `PlatformDispatcher.instance.onError` in main.dart. Param hygiene
  /// matters here — error messages can leak user input (typed seeds,
  /// addresses), so we only emit the exception class name and an
  /// optional opaque error code, never the message text or stack.
  ///
  /// Carries the crash context (crash_type, error_class, last_screen,
  /// last_flow, last_step, app_version). [crashType] is 'dart_fatal' for
  /// zone / PlatformDispatcher errors and 'dart_nonfatal' for framework
  /// (FlutterError) errors.
  static void unhandledExceptionCaught({
    required String errorClass,
    String? screenName,
    String? errorCode,
    String crashType = 'dart_fatal',
  }) {
    track('unhandled_exception_caught', params: {
      ...crashMarkerParams(crashType: crashType, errorClass: errorClass),
      if (screenName != null) 'screen_name': screenName,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  /// Unified post-mortem crash marker, fired on the next launch for a
  /// native crash, ANR or OOM kill of the previous process. Carries the
  /// previous session's persisted screen/flow snapshot. [source]:
  /// exit_info (Android ApplicationExitInfo) | crashlytics (iOS
  /// didCrashOnPreviousExecution).
  static void appCrashDetected({
    required String crashType,
    required String errorClass,
    required String source,
    Map<String, Object?>? snapshot,
    String? exitReason,
    bool? inForeground,
    String? rssMb,
  }) {
    track('app_crash_detected', params: {
      ...crashMarkerParams(
          crashType: crashType, errorClass: errorClass, snapshot: snapshot ?? const {}),
      'source': source,
      'snapshot_available': snapshot != null,
      if (exitReason != null) 'exit_reason': exitReason,
      if (inForeground != null) 'in_foreground': inForeground,
      if (rssMb != null) 'rss_mb': rssMb,
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // REVENUE — the BACKEND is the sole source of revenue in analytics.
  // It records our earnings server-side via S2S, deduped per order:
  //   - PostHog `revenue_recorded` (analytics/posthog.go), keyed by
  //     affiliate_code (aliased onto the device-UUID person), and
  //   - AppsFlyer `af_purchase` with af_revenue (analytics/appsflyer.go).
  //
  // The app emits NO revenue/value event. It previously fired a GA4
  // `purchase` event with the transaction value, but there is no Firebase
  // Analytics/GA4 in this app (only firebase_core + messaging +
  // crashlytics), so that event had no GA4 destination and only put
  // per-transaction volume into PostHog, duplicating the backend's
  // `revenue_recorded`. Removed. The app keeps only product/conversion
  // signals (AppsFlyer `purchaseCompleted`) and the activation
  // user-properties below.
  // ═══════════════════════════════════════════════════════════════════

  /// Call once a revenue-generating provider action settles (swap / bet /
  /// onramp). Emits NO revenue or `purchase` value event — revenue is
  /// recorded server-side. It only bumps lifetime activation user
  /// properties so cohorts like "5+ swaps in 30 days" stay queryable.
  /// Params are retained for call-site compatibility and future
  /// per-provider segmentation; their values are intentionally not sent.
  static void revenueEventCompleted({
    required String transactionId,
    required String provider,
    required double valueUsd,
    String? sourceAsset,
    String? destinationAsset,
  }) {
    final newCount = _bumpCounter('lifetime_swap_count');
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    refreshLifetimeProps(
      lifetimeSwapCount: newCount,
      lastSwapAtEpochSec: nowSec,
      isFunded: true,
    );
  }

  /// Tiny in-memory counter mirror so we don't have to read the Hive
  /// store on every increment. Source-of-truth still lives in
  /// Firebase user-property storage server-side; this is a write-through
  /// cache to avoid round-tripping.
  static final Map<String, int> _lifetimeCounters = {};
  static int _bumpCounter(String key) {
    // Persisted: the in-memory map restarted at 0 on every cold start, so
    // the first swap/bet of each session overwrote lifetime_*_count with 1.
    var current = _lifetimeCounters[key];
    if (current == null) {
      try {
        current = Hive.isBoxOpen('settings')
            ? (Hive.box('settings').get('lc_$key') as int? ?? 0)
            : 0;
      } catch (_) {
        current = 0;
      }
    }
    final next = current + 1;
    _lifetimeCounters[key] = next;
    try {
      if (Hive.isBoxOpen('settings')) Hive.box('settings').put('lc_$key', next);
    } catch (_) {}
    return next;
  }

  /// Public alias — bumps the lifetime bet counter. Callers should
  /// pass the returned value into [refreshLifetimeProps].
  static int bumpBetCount() => _bumpCounter('lifetime_bet_count');

  // ═══════════════════════════════════════════════════════════════════
  // LIFETIME USER PROPERTIES — these survive across sessions, drive
  // cohort segmentation in Firebase admin, and are how analysts answer
  // "did the user activate?" / "what rail do they prefer?" questions.
  // Call [refreshLifetimeProps] after any event that could change them
  // (balance sync, swap complete, bet place, redeem). Idempotent and
  // cheap — Firebase only sends a write if the value differs.
  // ═══════════════════════════════════════════════════════════════════

  /// Update the per-device lifetime properties used by Firebase cohort
  /// segmentation. Call after any balance refresh / completed swap /
  /// completed bet. Pass only the props you know — `null` skips that
  /// property (won't overwrite a previously-set value with empty).
  static void refreshLifetimeProps({
    bool? isFunded,
    int? lifetimeSwapCount,
    int? lifetimeBetCount,
    int? lastSwapAtEpochSec,
    int? lastDepositAtEpochSec,
    String? affiliateTierLevel,
    String? primaryRail,
  }) {
    if (_muted) return;
    if (isFunded != null) {
      setUserProperty('is_funded_user', isFunded ? 'true' : 'false');
    }
    if (lifetimeSwapCount != null) {
      setUserProperty('lifetime_swap_count', lifetimeSwapCount.toString());
    }
    if (lifetimeBetCount != null) {
      setUserProperty('lifetime_bet_count', lifetimeBetCount.toString());
    }
    if (lastSwapAtEpochSec != null) {
      setUserProperty('last_swap_at', lastSwapAtEpochSec.toString());
    }
    if (lastDepositAtEpochSec != null) {
      setUserProperty('last_deposit_at', lastDepositAtEpochSec.toString());
    }
    if (affiliateTierLevel != null) {
      setUserProperty('affiliate_tier_level', affiliateTierLevel);
    }
    if (primaryRail != null) {
      setUserProperty('primary_rail', primaryRail);
    }
  }

  /// Set the user-settings / configuration person properties used for
  /// segmentation. Call on boot (in [initialize], once settings are
  /// loaded) and whenever a relevant setting changes. Each arg is
  /// optional — `null` skips that property so callers can update just
  /// the one that changed. All values are coarse enums — no PII. The
  /// wallet, security and platform properties live in
  /// [refreshPersonProperties], the single writer for them.
  static void refreshSettingsProps({
    String? selectedCurrency,
    String? btcFormat,
    String? theme,
  }) {
    if (_muted) return;
    if (selectedCurrency != null) {
      setUserProperty('selected_currency', selectedCurrency);
    }
    if (btcFormat != null) setUserProperty('btc_format', btcFormat);
    if (theme != null) setUserProperty('theme', theme);
  }

  // ─── App language ────────────────────────────────────────────────

  /// The app language in use (last value handed to [setAppLanguage]).
  static String? _appLanguage;

  /// The value the PostHog SDK holds as the `app_language` super property
  /// (null when nothing is registered, e.g. while muted).
  static String? _registeredAppLanguage;

  /// The app language in use: the language code of the locale the app
  /// actually resolved (`de`, `pt`, …), never a display name. Registered
  /// as the super property `app_language`, so every event carries it, and
  /// kept on the person as `language`. PostHog's own `$locale` is the
  /// DEVICE language, which differs whenever the user picks another
  /// language in Settings. The app widget calls this with the resolved
  /// locale, so startup and every language change are covered. Deduped on
  /// value, skipped while muted (debug build or opt-out), never throws.
  static void setAppLanguage(String code) {
    final v = appLanguageCode(code);
    if (v == null) return;
    _appLanguage = v;
    if (_muted || v == _registeredAppLanguage) return;
    _registeredAppLanguage = v;
    try {
      unawaited(
          Posthog().register('app_language', v).catchError((Object _) {}));
    } catch (_) {/* never crash on tracking */}
    setUserProperty('language', v);
  }

  /// The bare language code for [raw] (`de_DE`, `pt-PT`, `DE` -> `de`,
  /// `pt`, `de`), or null when it is not a 2-3 letter language code.
  @visibleForTesting
  static String? appLanguageCode(String raw) {
    final code = raw.trim().split(RegExp('[-_]')).first.toLowerCase();
    return RegExp(r'^[a-z]{2,3}$').hasMatch(code) ? code : null;
  }

  /// Test seam: forget the app language and its registration.
  @visibleForTesting
  static void debugResetAppLanguage() {
    _appLanguage = null;
    _registeredAppLanguage = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // PERSON PROPERTIES FOR SEGMENTATION — booleans, counters and coarse
  // strings only. No amounts, no balances, no identifiers, no location
  // from the device (country comes only from the backend policy answer,
  // and today's policy carries none, so it is skipped).
  // ═══════════════════════════════════════════════════════════════════

  static String? _packageVersion;
  static String? _packageBuild;
  static String? _personPropsFingerprint;
  static DateTime? _personPropsSentAt;

  /// Unchanged properties are re-sent at most this often.
  static const Duration personPropertiesRefreshInterval = Duration(hours: 6);

  static const _firstMoneyActionKey = 'analytics_first_money_action_at';
  static const _lifetimeMoneyActionsKey = 'analytics_lifetime_money_actions';

  /// Money OUTCOME events that each stand for one completed money action
  /// (a payment left, a payment landed, an order filled, a conversion or
  /// venue transfer settled). Wrappers of these (`first_*`, the Move
  /// sheet's `move_completed`, which the settlement pipeline reports
  /// again) are left out so one action counts once.
  static const Set<String> completedMoneyEvents = {
    'send_completed',
    'usd_send_completed',
    'receive_flow_completed',
    'quoted_receive_completed',
    'swap_completed',
    'buy_completed',
    'sell_completed',
    'cashapp_buy_completed',
    'cross_chain_order_completed',
    'polymarket_deposit_completed',
    'polymarket_withdraw_completed',
    'hyperliquid_deposit_completed',
    'hyperliquid_withdraw_completed',
    'polymarket_bet_placed',
    'polymarket_position_sold',
    'polymarket_position_redeemed',
    'combo_placed',
    'combo_closed',
    'combo_claimed',
    'hyperliquid_order_placed',
    'hyperliquid_position_closed',
  };

  /// True when [event] (with [params]) reports a completed money action.
  static bool isCompletedMoneyAction(
          String event, Map<String, Object>? params) =>
      completedMoneyEvents.contains(event);

  /// Called from [track] for every completed money action: stamps the
  /// first one's date once and bumps the lifetime counter, both persisted
  /// in Hive and mirrored as person properties. Local bookkeeping only
  /// happens while tracking is on, so an opted-out session leaves no
  /// trace to be sent later.
  static void _recordMoneyAction() {
    if (_muted) return;
    try {
      if (!Hive.isBoxOpen('settings')) return;
      final box = Hive.box('settings');
      final previous = box.get(_lifetimeMoneyActionsKey);
      final count = (previous is int ? previous : 0) + 1;
      box.put(_lifetimeMoneyActionsKey, count);
      var first = box.get(_firstMoneyActionKey);
      if (first is! String || first.isEmpty) {
        first = _isoDate(DateTime.now().toUtc());
        box.put(_firstMoneyActionKey, first);
      }
      setUserPropertyValue('lifetime_money_actions', count);
      setUserPropertyValue('first_money_action_at', first);
    } catch (_) {/* bookkeeping is best-effort */}
  }

  static String _isoDate(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';

  /// Persisted money-action counter (0 before the first).
  static int get lifetimeMoneyActions {
    try {
      if (!Hive.isBoxOpen('settings')) return 0;
      final v = Hive.box('settings').get(_lifetimeMoneyActionsKey);
      return v is int ? v : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Persisted ISO date (UTC, `YYYY-MM-DD`) of the first money action.
  static String? get firstMoneyActionAt {
    try {
      if (!Hive.isBoxOpen('settings')) return null;
      final v = Hive.box('settings').get(_firstMoneyActionKey);
      return v is String && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Publish the segmentation person properties. Call after boot (once
  /// settings are loaded) and after a relevant change (wallet added or
  /// removed, backup done, PIN or biometrics changed, passkey set up).
  /// Throttled: an unchanged set is re-sent at most once per
  /// [personPropertiesRefreshInterval]; a changed set goes out at once
  /// (through the coalesced `$set` batch). `null` for [pinSet],
  /// [hasReferrer] or [country] leaves that property untouched.
  ///
  /// Properties: platform, app_version, build_number, country (backend
  /// policy only), wallet_count, has_hardware_wallet,
  /// hardware_wallet_kinds, has_referrer, backed_up, has_passkey, pin_set,
  /// biometrics_enabled, first_money_action_at, lifetime_money_actions.
  static void refreshPersonProperties({
    required int walletCount,
    required Iterable<String> hardwareWalletKinds,
    required bool backedUp,
    required bool hasPasskey,
    required bool biometricsEnabled,
    bool? pinSet,
    bool? hasReferrer,
    String? country,
    bool force = false,
  }) {
    if (_muted) return;
    final kinds = hardwareWalletKinds
        .map((k) => k.trim().toLowerCase())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final firstMoneyAction = firstMoneyActionAt;
    final props = <String, Object>{
      'platform': Platform.isIOS ? 'ios' : 'android',
      if (_packageVersion != null) 'app_version': _packageVersion!,
      if (_packageBuild != null) 'build_number': _packageBuild!,
      if (country != null && country.isNotEmpty) 'country': country,
      'wallet_count': walletCount,
      'has_hardware_wallet': kinds.isNotEmpty,
      'hardware_wallet_kinds': kinds,
      if (hasReferrer != null) 'has_referrer': hasReferrer,
      'backed_up': backedUp,
      'has_passkey': hasPasskey,
      if (pinSet != null) 'pin_set': pinSet,
      'biometrics_enabled': biometricsEnabled,
      if (firstMoneyAction != null) 'first_money_action_at': firstMoneyAction,
      'lifetime_money_actions': lifetimeMoneyActions,
    };
    final fingerprint = jsonEncode(props);
    final now = DateTime.now();
    final sentAt = _personPropsSentAt;
    if (!force &&
        fingerprint == _personPropsFingerprint &&
        sentAt != null &&
        now.difference(sentAt) < personPropertiesRefreshInterval) {
      return;
    }
    _personPropsFingerprint = fingerprint;
    _personPropsSentAt = now;
    props.forEach(setUserPropertyValue);
  }

  /// Test seam: forget the throttle so the next refresh always sends.
  @visibleForTesting
  static void debugResetPersonProperties() {
    _personPropsFingerprint = null;
    _personPropsSentAt = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // UTM / MARKETING ATTRIBUTION — captured from every incoming deep link
  // (the router) and from AppsFlyer's direct and deferred link payloads,
  // and persisted as user properties so every downstream event is
  // attributable to its acquisition source. Required for any
  // performance-marketing spend or affiliate-attribution audit.
  // ═══════════════════════════════════════════════════════════════════

  /// The only link parameters that become person properties.
  static const List<String> utmKeys = [
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
  ];

  /// Capture the UTM parameters of a deep link as person properties
  /// (sticky across sessions). Only the `utm_*` values leave the device:
  /// never the URL, host, path, referral code or any other parameter.
  /// The router's `deep_link_opened` event is separate.
  static void captureUtmFromUri(Uri uri) {
    if (_muted) return;
    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } catch (_) {
      return; // malformed query encoding: nothing to capture
    }
    captureUtmParams(query);
  }

  /// Same as [captureUtmFromUri] for a parameter map, such as an AppsFlyer
  /// click event or install conversion payload. Every key other than
  /// [utmKeys] is ignored; values are trimmed and capped, and the
  /// person-property flush scrubs them like any other property.
  static void captureUtmParams(Map<dynamic, dynamic>? params) {
    if (_muted || params == null) return;
    for (final key in utmKeys) {
      final raw = params[key];
      if (raw is! String && raw is! num) continue;
      var value = raw.toString().trim();
      if (value.isEmpty) continue;
      if (value.length > 100) value = value.substring(0, 100);
      setUserProperty(key, value);
    }
  }

  /// The AppsFlyer install-attribution person properties. Campaign NAMES
  /// only: AppsFlyer's campaign / adset / ad ids are never read.
  static const List<String> installAttributionKeys = [
    'af_media_source',
    'af_campaign',
    'af_adset',
    'af_ad',
    'af_channel',
    'af_status',
  ];

  /// Writes the install's AppsFlyer attribution as person properties with
  /// `$set_once`, so the first campaign an install came from is never
  /// overwritten. Keys outside [installAttributionKeys] are ignored. Skipped
  /// while muted (debug build or the user's opt-out).
  static void setInstallAttributionOnce(Map<String, String> attribution) {
    if (_muted) return;
    final props = <String, Object>{
      for (final key in installAttributionKeys)
        if (attribution[key] case final value? when value.isNotEmpty)
          key: value,
    };
    if (props.isEmpty) return;
    try {
      Posthog().capture(
        eventName: r'$set',
        userPropertiesSetOnce: scrubProperties(props),
      );
    } catch (_) {/* never crash on tracking */}
  }

  // ─── Sal (AI advisor) ───────────────────────────────────────────
  //
  // Never the question or answer text: lengths and counts are bucketed.
  // The backend separately emits ai_question_accepted / ai_daily_limit_reached
  // (server truth for quota); these are the product funnel.

  static String _llmLatencyBucket(int ms) => ms < 3000
      ? '<3s'
      : ms < 10000
          ? '3-10s'
          : ms < 30000
              ? '10-30s'
              : '30s+';

  static String _lengthBucket(int n) => n <= 20
      ? '1-20'
      : n <= 60
          ? '21-60'
          : n <= 200
              ? '61-200'
              : '200+';

  /// Sal sheet/chat opened. [entry]: chip (the round dog button) |
  /// header_button (the round dog widening into a capsule; no screen
  /// sends it any more, see Legacy) | market_capsule (the question capsule
  /// under a market screen's headline figure, Predictions and Investing,
  /// asking it on open) | position_capsule (the same capsule under an
  /// open-position screen's value, Predictions and Investing, asking the
  /// position's market its top question on open) | full_chat | search |
  /// bottom_bar.
  /// Legacy, no longer sent: insight_row (the market question row the
  /// header button replaced, October 2026); market_row (the Investing
  /// market screen's question row above About) and header_button from
  /// either market screen, both replaced by market_capsule, and
  /// header_button from either open-position screen, replaced by
  /// position_capsule; position_card (the round dog on an Open tab
  /// position card, removed: Sal lives on the position screen) (October
  /// 2026).
  /// [expanded] (header_button only): whether the button was open as the
  /// capsule showing the question when it was tapped.
  static void salOpened(
          {required String entry, String? surface, bool? expanded}) =>
      track('sal_opened', params: {
        'entry': entry,
        if (surface != null) 'surface': surface,
        if (expanded != null) 'expanded': expanded,
      });

  /// A question was sent. [input]: typed | suggested. Legacy, no longer
  /// sent: followup (a tapped "Ask Sal next" row; the rows were removed in
  /// October 2026 and a follow-up is typed, so it reports typed). Kept here
  /// for dashboards that still group on it.
  /// [template] (an allowlisted chip template id) and [chipIndex] (the
  /// chip's 0-based position) are sent only for a chip ('suggested').
  static void salQuestionAsked({
    required String input,
    String? surface,
    required int queryLength,
    required int turnIndex,
    String? venue,
    String? template,
    int? chipIndex,
  }) =>
      track('sal_question_asked', params: {
        'input': input,
        if (surface != null) 'surface': surface,
        'query_length_bucket': _lengthBucket(queryLength),
        'turn': turnIndex == 0 ? '1' : (turnIndex < 3 ? '2-3' : '4+'),
        if (venue != null) 'venue': venue,
        if (input == 'suggested' && kSalChipTemplates.contains(template))
          'template': template!,
        if (input == 'suggested' && chipIndex != null && chipIndex >= 0)
          'chip_index': chipIndex,
      });

  /// Exactly one per answered turn (never per stream chunk).
  static void salAnswerReceived({
    String? surface,
    required int blockCount,
    required int marketCards,
    required int latencyMs,
  }) =>
      track('sal_answer_received', params: {
        if (surface != null) 'surface': surface,
        'block_count': blockCount,
        'market_cards': marketCards,
        'latency_bucket': _llmLatencyBucket(latencyMs),
      });

  /// [category]: quota_daily | rate_limited | already_accepted |
  /// private_input | private_input_local | unavailable | no_response |
  /// too_long | cancelled.
  static void salAnswerFailed({
    String? surface,
    required String category,
    int? latencyMs,
  }) =>
      track('sal_answer_failed', params: {
        if (surface != null) 'surface': surface,
        'error_category': category,
        if (latencyMs != null) 'latency_bucket': _llmLatencyBucket(latencyMs),
      });

  /// A card or action button in an answer was tapped.
  static void salCardTapped({
    required String action,
    required String card, // market | action_button
    String? venue, // polymarket | hyperliquid
    String? section,
  }) =>
      track('sal_card_tapped', params: {
        'action': action,
        'card': card,
        if (venue != null) 'venue': venue,
        if (section != null) 'section': section,
      });

  /// What happened after a Sal action: opened | unavailable | error | applied.
  static void salActionResult({required String action, required String result}) =>
      track('sal_action_result', params: {'action': action, 'result': result});

  /// An evidence/source link in an answer was opened (never the URL).
  static void salSourceOpened({required bool opened}) =>
      track('sal_source_opened', params: {'opened': opened});

  // ─── Wallets added ───────────────────────────────────────────────

  /// A wallet was added to the app. Never the xpub, fingerprint, descriptor
  /// or any address. [walletKind]: hot | hardware | watch_only | ledger |
  /// jade | keystone | signer | external_address | bitcoin_onchain.
  /// [importMethod]: create | seed | passkey | xpub | qr | file | usb | ble.
  static void walletAdded({
    required String walletKind,
    required String importMethod,
    String? vendor,
    String? scriptType, // native_segwit | taproot | nested_segwit | legacy
    String? network, // bitcoin | testnet | signet | spark
    String? source, // onboarding | add_wallet
  }) =>
      track('wallet_added', params: {
        'wallet_kind': walletKind,
        'import_method': importMethod,
        if (vendor != null) 'vendor': vendor,
        if (scriptType != null) 'script_type': scriptType,
        if (network != null) 'network': network,
        if (source != null) 'source': source,
      });

  // ─── Wallet guards ───────────────────────────────────────────────

  /// Test-only tap on every [track] call, including muted debug builds.
  @visibleForTesting
  static void Function(String event, Map<String, Object>? params)?
      debugTrackObserver;

  /// [route] is a chain/asset label such as `spark_btc>polygon_usdc.e`;
  /// [reason] is a `WalletGuardReason.code`.
  @visibleForTesting
  static Map<String, Object> orchestraQuoteRejectedParams({
    required String flow,
    required String route,
    required String reason,
  }) =>
      {'flow': flow, 'route': route, 'reason': reason};

  static void orchestraQuoteRejected({
    required String flow,
    required String route,
    required String reason,
  }) {
    track('orchestra_quote_rejected',
        params: orchestraQuoteRejectedParams(
            flow: flow, route: route, reason: reason));
  }

  /// A settlement record could not be decoded. No params: the record's
  /// ids and addresses never leave the device.
  static void settlementRecordCorrupt() {
    track('settlement_record_corrupt');
  }

  // ─── Settlement operations (Phase 5 plan B15) ───
  // Flow, route and stage labels plus buckets only. Never ids, addresses,
  // txids or exact amounts.

  @visibleForTesting
  static String settlementAttemptBucket(int attempts) {
    if (attempts <= 1) return '1';
    if (attempts == 2) return '2';
    if (attempts <= 5) return '3-5';
    return '6+';
  }

  @visibleForTesting
  static String settlementDurationBucket(Duration d) {
    if (d < const Duration(minutes: 5)) return '<5m';
    if (d < const Duration(hours: 1)) return '5m-1h';
    if (d < const Duration(hours: 24)) return '1h-24h';
    if (d < const Duration(days: 14)) return '1d-14d';
    return '14d+';
  }

  @visibleForTesting
  static Map<String, Object> settlementOperationStartedParams({
    required String flow,
    required String? routeVersion,
    required double? amountUsd,
  }) =>
      {
        'flow': flow,
        'route_version': routeVersion ?? 'none',
        if (amountUsd != null) 'amount_bucket': _usdBucket(amountUsd),
      };

  static void settlementOperationStarted({
    required String flow,
    required String? routeVersion,
    required double? amountUsd,
  }) {
    track('settlement_operation_started',
        params: settlementOperationStartedParams(
            flow: flow, routeVersion: routeVersion, amountUsd: amountUsd));
  }

  @visibleForTesting
  static Map<String, Object> settlementRouteUnavailableParams({
    required String route,
    required String reason,
  }) =>
      {'route': route, 'reason': reason};

  static void settlementRouteUnavailable({
    required String route,
    required String reason,
  }) {
    track('settlement_route_unavailable',
        params: settlementRouteUnavailableParams(route: route, reason: reason));
  }

  @visibleForTesting
  static Map<String, Object> settlementQuoteRefreshedParams({
    required String flow,
    required String moment,
    required bool afterReview,
    required bool withinGrant,
  }) =>
      {
        'flow': flow,
        'moment': moment,
        'after_review': afterReview,
        'within_grant': withinGrant,
      };

  static void settlementQuoteRefreshed({
    required String flow,
    required String moment,
    required bool afterReview,
    required bool withinGrant,
  }) {
    track('settlement_quote_refreshed',
        params: settlementQuoteRefreshedParams(
            flow: flow,
            moment: moment,
            afterReview: afterReview,
            withinGrant: withinGrant));
  }

  /// The user confirmed a refreshed quote again (user action).
  static void settlementRereviewConfirmed(String flow) {
    track('settlement_rereview_confirmed', params: {'flow': flow});
  }

  /// A quote was replaced before anything was sent and the flow went back
  /// to review for another confirm tap.
  static void settlementRereviewRequired(String flow) {
    track('settlement_rereview_required', params: {'flow': flow});
  }

  @visibleForTesting
  static Map<String, Object> settlementFundingRecordedParams({
    required String flow,
    required String fundingKind,
  }) =>
      {'flow': flow, 'funding_kind': fundingKind};

  static void settlementFundingRecorded({
    required String flow,
    required String fundingKind,
  }) {
    track('settlement_funding_recorded',
        params: settlementFundingRecordedParams(
            flow: flow, fundingKind: fundingKind));
  }

  @visibleForTesting
  static Map<String, Object> settlementSubmitAttemptParams({
    required String flow,
    required int attempts,
    required String outcome,
  }) =>
      {
        'flow': flow,
        'attempt_bucket': settlementAttemptBucket(attempts),
        'outcome': outcome,
      };

  static void settlementSubmitAttempt({
    required String flow,
    required int attempts,
    required String outcome,
  }) {
    track('settlement_submit_attempt',
        params: settlementSubmitAttemptParams(
            flow: flow, attempts: attempts, outcome: outcome));
  }

  static void settlementFundingUnknown(String flow) {
    track('settlement_funding_unknown', params: {'flow': flow});
  }

  static void settlementFundingResolved({
    required String flow,
    required String outcome,
  }) {
    track('settlement_funding_resolved',
        params: {'flow': flow, 'outcome': outcome});
  }

  static void settlementLateDeposit(String route) {
    track('settlement_late_deposit', params: {'route': route});
  }

  @visibleForTesting
  static Map<String, Object> settlementTerminalParams({
    required String route,
    required String outcome,
    required Duration duration,
  }) =>
      {
        'route': route,
        'outcome': outcome,
        'duration_bucket': settlementDurationBucket(duration),
      };

  static void settlementTerminal({
    required String route,
    required String outcome,
    required Duration duration,
    String? flow,
    String? walletKind,
    double? amountUsd,
  }) {
    track('settlement_terminal', params: {
      ...settlementTerminalParams(
          route: route, outcome: outcome, duration: duration),
      if (flow != null) 'flow': flow,
      if (walletKind != null) 'wallet_kind': walletKind,
      ...moneyParams(amountUsd: amountUsd),
    });
  }

  static void settlementNeedsAttention(String route) {
    track('settlement_needs_attention', params: {'route': route});
  }

  /// The user opened the Ledger account from a pending Ledger settlement
  /// in Activity detail (user action). [stage] is the operation stage
  /// name. No ids, addresses or amounts.
  static void settlementOpenLedgerAccountTapped({required String stage}) {
    track('settlement_open_ledger_account_tapped', params: {'stage': stage});
  }

  // ─── Phase 5b: hot signing guard, compromise tools, pause switches ───
  // Fixed labels and buckets only. Never ids, addresses or amounts.

  /// A hot signing or seed entry point was refused inside a Ledger
  /// operation (plan B12). [action] is a fixed label.
  static void hotSigningBlocked(String action) {
    track('hot_signing_blocked', params: {'action': action});
  }

  static void compromiseChecklistViewed() {
    track('compromise_checklist_viewed');
  }

  /// [step] is `new_wallet`, `move_funds`, `positions`, `revoke` or
  /// `rotate`.
  static void compromiseStepOpened(String step) {
    track('compromise_step_opened', params: {'step': step});
  }

  /// [venue] is `investing` or `predictions`.
  static void compromisePositionsOpened(String venue) {
    track('compromise_positions_opened', params: {'venue': venue});
  }

  /// [outcome] is `active`, `none_active`, `read_only`, `no_account` or
  /// `unavailable`.
  static void pmApprovalsChecked(String outcome) {
    track('pm_approvals_checked', params: {'outcome': outcome});
  }

  /// [accountKind] is `hot_deposit_wallet` today.
  static void pmApprovalsRevokeStarted(String accountKind) {
    track('pm_approvals_revoke_started', params: {'account_kind': accountKind});
  }

  /// [outcome] is `success`, `declined` or `failed`.
  static void pmApprovalsRevokeResult(String outcome) {
    track('pm_approvals_revoke_result', params: {'outcome': outcome});
  }

  @visibleForTesting
  static String compromiseCountBucket(int count) {
    if (count <= 0) return '0';
    if (count == 1) return '1';
    if (count <= 5) return '2-5';
    return '6+';
  }

  /// Old deposit addresses were retired from the compromise checklist.
  /// [count] is null when retiring failed.
  static void compromiseAddressesRetired(int? count) {
    track('compromise_addresses_retired', params: {
      'outcome': count == null ? 'failed' : 'success',
      if (count != null) 'count_bucket': compromiseCountBucket(count),
    });
  }

  /// A new operation was refused by a remote pause switch. [route] is the
  /// switch label.
  static void routePausedShown(String route) {
    track('route_paused_shown', params: {'route': route});
  }

  @visibleForTesting
  static Map<String, Object> orchestraDecimalsMismatchParams({
    required String chain,
    required String asset,
  }) =>
      {'chain': chain, 'asset': asset};

  static void orchestraDecimalsMismatch({
    required String chain,
    required String asset,
  }) {
    track('orchestra_decimals_mismatch',
        params: orchestraDecimalsMismatchParams(chain: chain, asset: asset));
  }

  @visibleForTesting
  static Map<String, Object> hlBuilderConfigRejectedParams(
          {required String reason}) =>
      {'reason': reason};

  static void hlBuilderConfigRejected({required String reason}) {
    track('hl_builder_config_rejected',
        params: hlBuilderConfigRejectedParams(reason: reason));
  }

  /// [kind] is `accumulation`, `own_eoa` or `withdraw3` (the signing
  /// backstop).
  @visibleForTesting
  static Map<String, Object> hlWithdrawDestinationRejectedParams(
          {required String kind}) =>
      {'kind': kind};

  static void hlWithdrawDestinationRejected({required String kind}) {
    track('hl_withdraw_destination_rejected',
        params: hlWithdrawDestinationRejectedParams(kind: kind));
  }

  /// The user confirmed a quote that was refreshed after the stored one
  /// expired or no longer matched the amount.
  @visibleForTesting
  static Map<String, Object> orchestraQuoteRequotedParams(
          {required String flow}) =>
      {'flow': flow};

  static void orchestraQuoteRequoted({required String flow}) {
    track('orchestra_quote_requoted',
        params: orchestraQuoteRequotedParams(flow: flow));
  }

  /// [reason] names the failed check (`destination_asset`, `recipient`,
  /// `recipient_format`, `deposit_format`).
  @visibleForTesting
  static Map<String, Object> accumulationAddressReverifyFailedParams(
          {required String reason}) =>
      {'reason': reason};

  static void accumulationAddressReverifyFailed({required String reason}) {
    track('accumulation_address_reverify_failed',
        params: accumulationAddressReverifyFailedParams(reason: reason));
  }

  /// [mode] is `v2`, the only challenge the app signs.
  @visibleForTesting
  static Map<String, Object> walletAuthChallengeParams(
          {required String mode}) =>
      {'mode': mode};

  static void walletAuthChallenge({required String mode}) {
    track('wallet_auth_challenge',
        params: walletAuthChallengeParams(mode: mode));
  }

  /// A wallet-session route needed a new session. [route] is `orchestra`,
  /// `pm_relay` or `hl`; [outcome] is `unavailable` (nothing sent),
  /// `reauth` (a 401 was answered by one re-auth and retry) or
  /// `reauth_failed`.
  @visibleForTesting
  static Map<String, Object> walletSessionAuthParams(
          {required String route, required String outcome}) =>
      {'route': route, 'outcome': outcome};

  static void walletSessionAuth(
      {required String route, required String outcome}) {
    track('wallet_session_auth',
        params: walletSessionAuthParams(route: route, outcome: outcome));
  }

  // ---------------------------------------------------------------------------
  // Phase 4b: Ledger funding routes (P4.10 HyperCore, P4.11 Polymarket).
  // No addresses, txids, quote ids or exact amounts: amounts only as
  // `amount_bucket` via [usdBucket].
  // ---------------------------------------------------------------------------

  /// A Ledger funding route started. [route] is a route version id, e.g.
  /// `ledger_btc_to_hypercore_v1` or `ledger_btc_to_polygon_usdce_v1`.
  static void ledgerFundingStarted({required String route}) {
    track('ledger_funding_started', params: {'route': route});
  }

  /// An expired or stale quote was replaced for re-review.
  static void ledgerFundingQuoteRefreshed({required String route}) {
    track('ledger_funding_quote_refreshed', params: {'route': route});
  }

  /// Funds left the Ledger account (BTC broadcast or relayer transfer
  /// accepted).
  static void ledgerFundingBroadcast({
    required String route,
    required String amountBucket,
  }) {
    track('ledger_funding_broadcast', params: {
      'route': route,
      'amount_bucket': amountBucket,
    });
  }

  /// Terminal result of a Ledger funding attempt. [outcome] is submitted,
  /// submit_pending, quote_expired, outcome_unknown, funding_unknown or a
  /// failure code (`ledger_<LedgerFailureCode>`, a refusal name, a guard
  /// reason code, a LedgerBtcSendError or LedgerFundingError code).
  static void ledgerFundingResult({
    required String route,
    required String outcome,
    String? amountBucket,
  }) {
    track('ledger_funding_result', params: {
      'route': route,
      'outcome': outcome,
      if (amountBucket != null) 'amount_bucket': amountBucket,
    });
  }

  /// The user left a Ledger funding sheet before finishing at [step].
  static void ledgerFundingCancelled({
    required String route,
    required String step,
  }) {
    track('ledger_funding_cancelled', params: {'route': route, 'step': step});
  }

  /// A Ledger address was displayed on the device and matched.
  /// [context]: `funding_refund` | `withdraw_recipient`.
  static void ledgerAddressVerified({required String context}) {
    track('ledger_address_verified', params: {'context': context});
  }

  /// The Polymarket deposit wallet for a Ledger was created after the user
  /// explicitly confirmed it.
  static void ledgerPmDepositWalletCreated() {
    track('ledger_pm_deposit_wallet_created');
  }

  /// The "make funds available" batch (approve plus wrap) was accepted.
  static void ledgerPmFundsMadeAvailable({required String amountBucket}) {
    track('ledger_pm_funds_made_available',
        params: {'amount_bucket': amountBucket});
  }

  /// pUSD was unwrapped to USDC.e before a withdrawal.
  static void ledgerPmCollateralUnwrapped({required String amountBucket}) {
    track('ledger_pm_collateral_unwrapped',
        params: {'amount_bucket': amountBucket});
  }

  /// The Polymarket funding explainer opened. [direction]: to_predictions |
  /// to_ledger_bitcoin. [available] is false while withdrawals are off.
  static void ledgerPmFundingExplainerViewed({
    required String direction,
    required bool requiresDeploy,
    required bool available,
  }) {
    track('ledger_pm_funding_explainer_viewed', params: {
      'direction': direction,
      'requires_deploy': requiresDeploy,
      'available': available,
    });
  }

  static void ledgerPmFundingExplainerContinued({
    required String direction,
    required bool deployConfirmed,
  }) {
    track('ledger_pm_funding_explainer_continued', params: {
      'direction': direction,
      'deploy_confirmed': deployConfirmed,
    });
  }

  static void ledgerPmFundingExplainerDismissed({required String direction}) {
    track('ledger_pm_funding_explainer_dismissed',
        params: {'direction': direction});
  }

  /// The "Make funds available" sheet for a Ledger Predictions account
  /// opened. [available] is false when no arrived USDC.e was readable.
  static void ledgerPmMakeAvailableViewed({required bool available}) {
    track('ledger_pm_make_available_viewed', params: {'available': available});
  }

  /// Result of a "Make funds available" attempt. [outcome]: submitted,
  /// pending, cancelled, failed or a refusal name. Amounts only bucketed.
  static void ledgerPmMakeAvailableResult({
    required String outcome,
    String? amountBucket,
  }) {
    track('ledger_pm_make_available_result', params: {
      'outcome': outcome,
      if (amountBucket != null) 'amount_bucket': amountBucket,
    });
  }

  /// P4.12 route choice for an Investing move. [direction]: deposit |
  /// withdraw. [outcome]: `direct`, or `fallback_<reason>` (flag_off,
  /// pending_v0, account_unavailable, route_unavailable, quote_failed,
  /// reverse_not_ready). No amounts or addresses.
  static void directHypercoreRoute({
    required String direction,
    required String outcome,
  }) {
    track('direct_hypercore_route',
        params: {'direction': direction, 'outcome': outcome});
  }

  // ─── Money flows: send / receive / move / buy / transactions ─────
  //
  // <flow>_started → <flow>_step → <flow>_submitted → outcome, or
  // <flow>_abandoned once per started instance (never after an outcome).

  static final Map<String, DateTime> _mfStartedAt = {};
  static final Map<String, String> _mfStep = {};
  static final Map<String, String> _mfLastError = {};
  static final Map<String, String> _mfAbandonEvent = {};
  static final Map<String, String> _mfPendingEntry = {};
  static final Set<String> _mfOutcomeSeen = {};

  /// Where the next [flow] is being opened from (home, scanner, search,
  /// deep_link, portfolio, …). Consumed by [takeEntrySource].
  static void markEntrySource(String flow, String source) =>
      _mfPendingEntry[flow] = source;

  static String takeEntrySource(String flow, {String fallback = 'unknown'}) =>
      _mfPendingEntry.remove(flow) ?? fallback;

  static String timeInFlowBucket(Duration d) {
    final s = d.inSeconds;
    if (s < 10) return '<10s';
    if (s < 30) return '10-30s';
    if (s < 120) return '30s-2m';
    if (s < 600) return '2-10m';
    return '10m+';
  }

  /// Abandon reason from the last error the flow showed.
  static String abandonReasonFor(String? errorCategory) {
    switch (errorCategory) {
      case null:
        return 'user_closed';
      case 'insufficient_funds':
        return 'insufficient_balance';
      case 'below_minimum':
        return 'below_minimum';
      case 'above_limit':
        return 'above_limit';
      case 'quote_rejected':
      case 'expired':
        return 'quote_failed';
      case 'no_route':
        return 'route_unavailable';
      case 'network':
      case 'timeout':
      case 'rate_limited':
        return 'backend_unreachable';
      case 'user_cancelled':
      case 'hardware_wallet':
        return 'signing_declined';
      case 'fee_unavailable':
        return 'fee_unavailable';
      case 'invalid_destination':
        return 'invalid_destination';
      default:
        return 'error_shown';
    }
  }

  static bool moneyFlowActive(String flow) => _mfStartedAt.containsKey(flow);

  static void moneyFlowStarted(
    String flow, {
    required String entrySource,
    String? event,
    String? abandonEvent,
    String? walletKind,
    String? network,
    String? venue,
    Map<String, Object>? props,
  }) {
    _mfStartedAt[flow] = DateTime.now();
    _mfStep[flow] = 'started';
    _mfLastError.remove(flow);
    if (abandonEvent != null) {
      _mfAbandonEvent[flow] = abandonEvent;
    } else {
      _mfAbandonEvent.remove(flow);
    }
    setFlowContext(
        flow: flow,
        step: 'started',
        venue: venue,
        network: network,
        walletKind: walletKind);
    track(event ?? '${flow}_started', params: {
      'entry_source': entrySource,
      if (walletKind != null) 'wallet_kind': walletKind,
      if (network != null) 'network': network,
      if (venue != null) 'venue': venue,
      ...?props,
    });
  }

  /// A real step transition. Repeating the current step is a no-op.
  static void moneyFlowStep(String flow, String step,
      {Map<String, Object>? props}) {
    if (_mfStep[flow] == step) return;
    _mfStep[flow] = step;
    if (_flow == _contextValue(flow)) setFlowStep(step);
    track('${flow}_step', params: {'step': step, ...?props});
  }

  static void moneyFlowSubmitted(String flow,
      {String? event, Map<String, Object>? props}) {
    _mfStep[flow] = 'submitted';
    if (_flow == _contextValue(flow)) setFlowStep('submitted');
    track(event ?? '${flow}_submitted', params: {...?props});
  }

  /// Remember the last error shown in [flow] (abandon reason).
  static void moneyFlowError(String flow, Object? error) {
    if (!_mfStartedAt.containsKey(flow)) return;
    _mfLastError[flow] = errorCategory(error);
  }

  /// The flow reached an outcome: no abandon will fire for it.
  static void moneyFlowFinished(String flow) {
    _mfStartedAt.remove(flow);
    _mfStep.remove(flow);
    _mfLastError.remove(flow);
    _mfAbandonEvent.remove(flow);
    clearFlowContext(flow);
  }

  /// `<flow>_failed` for flows without a legacy failure event. Ends the flow.
  static void moneyFlowFailed(
    String flow, {
    required Object? error,
    required String stage,
    Map<String, Object>? props,
    StackTrace? stackTrace,
  }) {
    final category = errorCategory(error);
    recordHandled(category, error, stackTrace, flow: flow, stage: stage);
    track('${flow}_failed', params: {
      'error_category': category,
      'stage': stage,
      ...?props,
    });
    moneyFlowFinished(flow);
  }

  static void moneyFlowAbandoned(String flow,
      {String? reason, Map<String, Object>? props}) {
    final started = _mfStartedAt.remove(flow);
    if (started == null) return;
    final step = _mfStep.remove(flow) ?? 'started';
    final lastError = _mfLastError.remove(flow);
    final event = _mfAbandonEvent.remove(flow) ?? '${flow}_abandoned';
    clearFlowContext(flow);
    track(event, params: {
      'step': step,
      'reason': reason ?? abandonReasonFor(lastError),
      'time_in_flow_bucket':
          timeInFlowBucket(DateTime.now().difference(started)),
      if (lastError != null) 'last_error_category': lastError,
      ...?props,
    });
  }

  /// True the first time [key] is seen for [event] this session (one
  /// outcome per real action; the key is hashed and never sent).
  static bool claimOutcome(String event, String key) =>
      _mfOutcomeSeen.add('$event|${orderRef(key)}');

  /// Route properties for conversions and cross-chain sends.
  static Map<String, Object> routeParams({
    String? fromAsset,
    String? fromNetwork,
    String? toAsset,
    String? toNetwork,
    String? provider,
    String? venue,
  }) =>
      {
        if (fromAsset != null) 'from_asset': fromAsset.toLowerCase(),
        if (fromNetwork != null) 'from_network': fromNetwork.toLowerCase(),
        if (toAsset != null) 'to_asset': toAsset.toLowerCase(),
        if (toNetwork != null) 'to_network': toNetwork.toLowerCase(),
        if (provider != null) 'provider': provider.toLowerCase(),
        if (venue != null) 'venue': venue,
      };

  /// Transaction history export. [format]: pdf | csv. [period]: the
  /// picked range. [outcome]: exported | failed | cancelled.
  static void transactionsExported({
    required String format,
    required String outcome,
    String? period,
    int? walletCount,
    String? errorCategoryValue,
  }) {
    track('transactions_exported', params: {
      'format': format,
      'outcome': outcome,
      if (period != null) 'period': period,
      if (walletCount != null) 'wallet_count': walletCount,
      if (errorCategoryValue != null) 'error_category': errorCategoryValue,
    });
  }

  @visibleForTesting
  static void debugResetMoneyFlows() {
    _mfStartedAt.clear();
    _mfStep.clear();
    _mfLastError.clear();
    _mfAbandonEvent.clear();
    _mfPendingEntry.clear();
    _mfOutcomeSeen.clear();
  }
}

/// Wrapper exception type emitted by `TrackingService.sanitizedErrorEnvelope`
/// before raw errors are forwarded to Crashlytics. Carries the
/// original runtime type as the class name (via the static `type`
/// field) and a scrubbed message — no addresses, invoices, or hex
/// fragments survive.
class _SanitizedError implements Exception {
  final String type;
  final String message;
  const _SanitizedError(this.type, this.message);

  @override
  String toString() => message.isEmpty ? type : '$type: $message';
}

/// Stand-in error for a handled failure that has no exception object
/// (only a category or reason string). The type name is stable so
/// Crashlytics groups these by call site; the message is categorical.
class HandledFailure implements Exception {
  final String category;
  final String? flow;
  final String? stage;
  const HandledFailure(this.category, {this.flow, this.stage});

  // No type prefix: the crash envelope adds the type name itself.
  @override
  String toString() => '$category'
      '${flow == null ? '' : ' flow=$flow'}'
      '${stage == null ? '' : ' stage=$stage'}';
}
