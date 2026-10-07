import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart' show AppLocalizations, appL10n, l10nForLanguage;
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:package_info_plus/package_info_plus.dart';

class CapabilityDecision {
  const CapabilityDecision(
      {required this.allowed,
      this.reason = '',
      this.comingSoon = false,
      this.serverMessage = ''});
  final bool allowed;
  final String reason;
  final bool comingSoon;

  /// The operator's own explanation for a denial, when the policy carries
  /// one. Shown verbatim next to the disabled control.
  final String serverMessage;

  bool get regionRestricted =>
      reason == 'country_blocked' || reason == 'country_not_allowed';

  bool get updateRequired =>
      reason == 'app_update_required' ||
      reason == 'app_version_blocked' ||
      reason == 'app_version_unknown';

  bool get deviceRestricted =>
      reason == 'platform_not_allowed' ||
      reason == 'device_blocked' ||
      reason == 'device_not_allowed' ||
      reason == 'device_unknown';

  bool get accountRestricted =>
      reason.startsWith('affiliate_') || reason.startsWith('wallet_');

  /// Kute's sentence for this decision in the app language. See
  /// [messageIn].
  String get message => messageIn(appL10n());

  /// The operator's own words when the policy carries some; otherwise
  /// Kute's wording for the reason code, in [l10n]'s language.
  String messageIn(AppLocalizations l10n) {
    if (serverMessage.trim().isNotEmpty) return serverMessage.trim();
    if (comingSoon) return l10n.capabilityComingSoon;
    if (regionRestricted) {
      // Names the mechanism, not a verdict on the person: the block is
      // decided from where the connection appears to be, which is the
      // one thing a mislocated traveller or VPN user can check.
      return l10n.capabilityRegionRestricted;
    }
    if (updateRequired) return l10n.capabilityUpdateRequired;
    if (deviceRestricted) return l10n.capabilityDeviceRestricted;
    if (accountRestricted) return l10n.capabilityAccountRestricted;
    if (reason == 'country_unknown') return l10n.capabilityCountryUnknown;
    if (reason == 'policy_unavailable') {
      return l10n.capabilityPolicyUnavailable;
    }
    return l10n.capabilityUnavailable;
  }
}

/// Thrown when an order asks for more leverage than the policy allows in
/// the caller's region. Carries the cap so the ticket can name it.
class LeverageCapExceededException implements Exception {
  const LeverageCapExceededException(this.maxLeverage);
  final int maxLeverage;
  String messageIn(AppLocalizations l10n) =>
      l10n.leverageCapExceeded(maxLeverage);
  /// English on purpose: exception text feeds error categories and logs.
  /// Screens show [messageIn] through userErrorCopy.
  @override
  String toString() => messageIn(l10nForLanguage('en'));
}

class CapabilityUnavailableException implements Exception {
  const CapabilityUnavailableException(this.capability, this.decision);
  final String capability;
  final CapabilityDecision decision;
  /// English on purpose: exception text feeds error categories and logs.
  /// Screens show the decision's [CapabilityDecision.messageIn].
  @override
  String toString() => decision.messageIn(l10nForLanguage('en'));
}

/// Public, non-secret policy metadata. Fee amounts are never computed from this
/// display configuration: the backend/provider quote remains authoritative.
class RuntimeCapabilities {
  RuntimeCapabilities.fromJson(Map<String, dynamic> json)
      : revision = json['revision'] as int,
        evaluatedAt = DateTime.parse(json['evaluatedAt'] as String).toUtc(),
        expiresAt = DateTime.parse(json['expiresAt'] as String).toUtc(),
        capabilities =
            (json['capabilities'] as Map<String, dynamic>).map((key, value) {
          final decision = value as Map<String, dynamic>;
          if (decision['allowed'] is! bool) {
            throw const FormatException('Invalid capability');
          }
          return MapEntry(
              key,
              CapabilityDecision(
                allowed: decision['allowed'] == true,
                reason: decision['reason'] as String? ?? '',
                comingSoon: decision['comingSoon'] == true,
                serverMessage: decision['message'] as String? ?? '',
              ));
        }),
        fees = Map<String, dynamic>.unmodifiable(
            json['fees'] as Map<String, dynamic>? ?? {}),
        ai = Map<String, dynamic>.unmodifiable(
            json['ai'] as Map<String, dynamic>? ?? {}),
        referral = Map<String, dynamic>.unmodifiable(
            json['referral'] as Map<String, dynamic>? ?? {}),
        security = Map<String, dynamic>.unmodifiable(
            json['security'] as Map<String, dynamic>? ?? {}),
        investing = Map<String, dynamic>.unmodifiable(
            json['investing'] as Map<String, dynamic>? ?? {}) {
    if (json['schemaVersion'] != 1 ||
        revision < 0 ||
        !expiresAt.isAfter(evaluatedAt)) {
      throw const FormatException('Invalid capability policy');
    }
  }
  final int revision;
  final DateTime evaluatedAt;
  final DateTime expiresAt;
  final Map<String, CapabilityDecision> capabilities;
  final Map<String, dynamic> fees;
  final Map<String, dynamic> ai;

  /// Public referral terms: the referee fee discount the backend currently
  /// applies (basis points off every positive Kute fee) and whether this
  /// session belongs to a referred account. Display only; the discounted
  /// fee always comes from the provider quote.
  final Map<String, dynamic> referral;

  int get refereeDiscountBps {
    final v = referral['refereeDiscountBps'];
    if (v is num && v.isFinite && v >= 0) return v.toInt().clamp(0, 10000);
    return 0;
  }

  /// The same discount as a whole percentage of the headline Kute fee
  /// (20 bps off a 0.5% fee reads as 40% off). This is what copy quotes.
  int get refereeDiscountPct {
    final v = referral['refereeDiscountPct'];
    if (v is num && v.isFinite && v >= 0) return v.toInt().clamp(0, 100);
    return 0;
  }

  bool get isReferred => referral['isReferred'] == true;

  /// App-side security settings published by the backend runtime policy.
  /// The only source for these: no analytics remote value or feature flag
  /// may steer them.
  final Map<String, dynamic> security;

  /// Small-action step-up allowance (D-11): a Polymarket bet or Hyperliquid
  /// spot buy at or below this many US cents may skip the PIN or biometric
  /// check while the session is unlocked. 0, absent or malformed means off.
  /// `SmallActionAllowance` applies its own per-action and per-session caps
  /// on top.
  int get smallActionAllowanceCents {
    final v = security['smallActionAllowanceCents'];
    if (v is num && v.isFinite && v > 0) return v.toInt();
    return 0;
  }

  /// Investing settings resolved by the backend for this connection's
  /// region.
  final Map<String, dynamic> investing;

  /// The leverage cap for new Investing positions, already resolved for
  /// the caller's country, or null when the policy publishes none (the
  /// venue maximum applies). The key must be present: an absent section
  /// reads as the most conservative cap, never as "no cap".
  int? get maxLeverage {
    final v = investing['maxLeverage'];
    if (v == null) return investing.containsKey('maxLeverage') ? null : 1;
    if (v is num && v.isFinite && v >= 1) return v.toInt().clamp(1, 100);
    return 1;
  }
}

/// The offline defaults: what the app may do while the backend policy
/// cannot be fetched and no denial was seen for this session. Everything
/// not listed here is denied with reason `policy_unavailable`.
///
/// Allowed while the backend is unreachable:
/// * `hyperliquid.browse`, `polymarket.browse`: Investing and Predictions
///   markets stay visible (read only).
/// * `settings.advanced`, `export.transactions`: the custom Electrum
///   server in Settings → Advanced and the CSV/PDF transaction export are
///   local.
/// * `hyperliquid.cancel`, `hyperliquid.close`, `hyperliquid.withdraw`,
///   `polymarket.cancel`, `polymarket.close`, `polymarket.withdraw`: the
///   exits, so an outage never traps money in an open order or position
///   (Polymarket sells and claims use `polymarket.close`).
/// * `polymarket.protocol_v2`: the Protocol V2 order path, so a V2
///   position can still be sold (a buy also needs `polymarket.trade`).
///
/// Denied while the backend is unreachable (not exhaustive; anything new
/// is denied too):
/// * `hyperliquid.trade`, `hyperliquid.deposit`, `polymarket.trade`,
///   `polymarket.deposit`: no new exposure and no new venue funding.
/// * `trading.advanced`, `hyperliquid.stocks`, `polymarket.sports`,
///   `polymarket.politics`.
/// * `hyperliquid.referrer`: naming Kute as the Hyperliquid referrer of a
///   new Investing account waits for a loaded policy.
/// * `orchestra.swap`, `orchestra.swap.stablecoins`,
///   `orchestra.swap.altcoins`, `crypto.deposit`.
/// * `orchestra.onetime_addresses`: one-time quoted receive addresses;
///   only the reusable receive options remain.
/// * `ledger.hyperliquid`, `ledger.polymarket` (Investing and Predictions
///   on a hardware wallet).
/// * `hardware.wallet`, `wallet.savings`, `wallet.tracked`: adding any
///   wallet beyond the spending account (founder decision, October 2026).
///   Wallets already added keep working.
/// * `onramp.*`, `usd.earn`, `affiliate.program`, `ai.ask`.
///
/// A denial (or coming-soon) seen in a loaded policy earlier this session
/// still stands during an outage, including for the ids allowed here.
/// Execution that itself needs Kute's backend (Orchestra routes, the
/// relayer) still fails on its own when the backend is down.
const kOfflineAllowedCapabilities = <String>{
  'hyperliquid.browse',
  'polymarket.browse',
  'settings.advanced',
  'export.transactions',
  'hyperliquid.cancel',
  'hyperliquid.close',
  'hyperliquid.withdraw',
  'polymarket.cancel',
  'polymarket.close',
  'polymarket.withdraw',
  // The Protocol V2 order path switch is not exposure on its own (buys
  // still need polymarket.trade); allowed offline so a V2 position stays
  // sellable during an outage unless a loaded policy switched it off.
  'polymarket.protocol_v2',
};

/// Backend policy is independent of analytics consent. With no usable
/// policy, [kOfflineAllowedCapabilities] decides; explicit restrictions,
/// feature switches, account checks and server execution gates remain
/// authoritative.
class RuntimeCapabilitiesService extends ChangeNotifier
    with WidgetsBindingObserver {
  RuntimeCapabilitiesService._()
      : _client = http.Client(),
        _baseUrl =
            (() => dotenv.isInitialized ? dotenv.env['BACKEND'] ?? '' : ''),
        _sessionToken = (() => AffiliateService.sessionToken),
        _ensureSession = (() => AffiliateService.ensureSession()),
        _renewSession =
            ((token) => AffiliateService.ensureSession(rejected: token)),
        _platform = Platform.isIOS ? 'ios' : 'android',
        _appVersion = (() async => (await PackageInfo.fromPlatform()).version),
        _clock = DateTime.now,
        _ensureProviderAvailability =
            InvestmentProviderAvailability.instance.ensureNewExposure;

  @visibleForTesting
  RuntimeCapabilitiesService.forTesting({
    required http.Client client,
    required String Function() baseUrl,
    required String? Function() sessionToken,
    String platform = 'ios',
    Future<String> Function()? appVersion,
    DateTime Function()? clock,
    Future<void> Function(Iterable<String>)? ensureProviderAvailability,
  })  : _client = client,
        _baseUrl = baseUrl,
        _sessionToken = sessionToken,
        _ensureSession = (() async => sessionToken()),
        _renewSession = ((_) async => null),
        _platform = platform,
        _appVersion = appVersion ?? (() async => '1.0.0'),
        _clock = clock ?? DateTime.now,
        _ensureProviderAvailability =
            ensureProviderAvailability ?? ((_) async {});

  static final _instance = RuntimeCapabilitiesService._();
  @visibleForTesting
  static RuntimeCapabilitiesService? debugInstance;
  static RuntimeCapabilitiesService get instance => debugInstance ?? _instance;
  final http.Client _client;
  final Future<void> Function(Iterable<String>) _ensureProviderAvailability;
  final String Function() _baseUrl;
  final String? Function() _sessionToken;
  final Future<String?> Function() _ensureSession;
  final Future<String?> Function(String) _renewSession;
  final String _platform;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;
  RuntimeCapabilities? _snapshot;

  /// When [_snapshot] was fetched, by this device's clock, so a caller may
  /// reuse a policy it just fetched instead of asking again.
  DateTime? _snapshotFetchedAt;
  String? _snapshotSession;
  Future<bool>? _refresh;
  Timer? _expiryTimer;
  Timer? _refreshTimer;
  bool _started = false;
  bool _disposed = false;
  String? _version;

  Future<Map<String, String>> requestContextHeaders() async {
    try {
      _version ??= await _appVersion();
    } catch (_) {}
    // Platform and app version only. The install id (the analytics device
    // uuid) never goes to Kute's backend.
    return {
      'X-Kute-Platform': _platform,
      if (_version != null) 'X-Kute-App-Version': _version!,
    };
  }

  // A long server expiry must not keep stale country/device policy in the UI.
  static const maxDisplayAge = Duration(minutes: 5);
  RuntimeCapabilities? get snapshot {
    final value = _snapshot;
    if (value == null || _snapshotSession != _sessionToken()) return null;
    final now = _clock().toUtc();
    if (!now.isBefore(value.expiresAt) ||
        now.difference(value.evaluatedAt) > maxDisplayAge) {
      return null;
    }
    return value;
  }

  /// With a loaded policy that could not place the caller
  /// (`country_unknown`), these investment capabilities pass. This applies
  /// to a loaded policy only; an unreachable backend follows
  /// [kOfflineAllowedCapabilities].
  static const _locationAdvisoryCapabilities = {
    'hyperliquid.browse',
    'hyperliquid.trade',
    'hyperliquid.deposit',
    'polymarket.browse',
    'polymarket.trade',
    'polymarket.deposit',
  };

  CapabilityDecision decision(String id) {
    final current = snapshot;
    final value = current?.capabilities[id];
    if (value != null) return _locationDecision(id, value);
    if (current != null) {
      return const CapabilityDecision(
          allowed: false, reason: 'unknown_capability');
    }
    return _unavailableDecision(id);
  }

  CapabilityDecision _locationDecision(String id, CapabilityDecision value) {
    if (_locationAdvisoryCapabilities.contains(id) &&
        value.reason == 'country_unknown' &&
        !value.comingSoon) {
      return const CapabilityDecision(allowed: true, reason: 'country_unknown');
    }
    return value;
  }

  CapabilityDecision _unavailableDecision(String id) {
    // A failed refresh must not turn a previously observed admin disablement,
    // version requirement or explicit country block into permission.
    final previous = _snapshotSession == _sessionToken()
        ? _snapshot?.capabilities[id]
        : null;
    if (previous != null) {
      final decision = _locationDecision(id, previous);
      if (!decision.allowed || decision.comingSoon) return decision;
    }
    return CapabilityDecision(
        allowed: kOfflineAllowedCapabilities.contains(id),
        reason: 'policy_unavailable');
  }

  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  /// The Investing leverage cap for this region: null when the policy sets
  /// none. Without a usable policy the last cap seen for this session
  /// stands, and with none ever seen the cap is 1x, so an outage can only
  /// ever tighten leverage, never loosen it.
  int? get maxLeverage {
    final current = snapshot;
    if (current != null) return current.maxLeverage;
    final previous = _snapshotSession == _sessionToken() ? _snapshot : null;
    if (previous != null) return previous.maxLeverage;
    return 1;
  }

  /// The leverage a ticket may offer for [venueMax]: the venue's own
  /// maximum, tightened to the policy cap when one applies.
  int offeredLeverage(int venueMax) {
    final cap = maxLeverage;
    final venue = venueMax < 1 ? 1 : venueMax;
    return cap == null || cap >= venue ? venue : cap;
  }

  /// Refuses an order that asks for more leverage than the policy allows.
  /// Hot and Ledger order paths call this at the same point, so the cap
  /// is one rule with one wording wherever the order is signed.
  void ensureLeverageAllowed(int leverage) {
    final cap = maxLeverage;
    if (cap != null && leverage > cap) {
      throw LeverageCapExceededException(cap);
    }
  }

  /// Null when [id] is allowed; otherwise the sentence to show beside the
  /// control this capability disables. Screens keep their gated surfaces
  /// reachable and use this for the one committing button.
  String? blockReason(String id) {
    final value = decision(id);
    return value.allowed && !value.comingSoon ? null : value.message;
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(refresh());
      }
    });
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<bool> refresh() {
    final running = _refresh;
    if (running != null) return running;
    final future = _fetch();
    _refresh = future;
    return future.whenComplete(() {
      if (identical(_refresh, future)) _refresh = null;
    });
  }

  Future<bool> _fetch() async {
    final backend = _baseUrl().replaceFirst(RegExp(r'/$'), '');
    if (backend.isEmpty) return false;
    try {
      var token = await _ensureSession();
      if (token == null || token.isEmpty) return false;
      final context = await requestContextHeaders();
      final version = _version;
      if (version == null) return false;
      final uri = Uri.parse('$backend/api/v1/config/capabilities')
          .replace(queryParameters: {
        'platform': _platform,
        'appVersion': version,
      });
      // Two attempts: a healthy connection answers well inside the first,
      // and a slow tunnel gets the time it needs instead of a refusal.
      Future<http.Response> send(String bearer) async {
        final headers = {...context, 'Authorization': 'Bearer $bearer'};
        try {
          return await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 5));
        } on TimeoutException {
          return await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 10));
        }
      }

      var response = await send(token);
      if (response.statusCode == 401 && token == _sessionToken()) {
        token = await _renewSession(token);
        if (token == null || token.isEmpty) return false;
        response = await send(token);
      }
      if (response.statusCode != 200 || token != _sessionToken()) return false;
      final value = RuntimeCapabilities.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
      final now = _clock().toUtc();
      if (!value.expiresAt.isAfter(now) ||
          value.evaluatedAt.isAfter(now.add(const Duration(minutes: 1)))) {
        return false;
      }
      if (_snapshotSession == token &&
          _snapshot != null &&
          value.revision < _snapshot!.revision) {
        return false;
      }
      _snapshot = value;
      _snapshotSession = token;
      _snapshotFetchedAt = now;
      _expiryTimer?.cancel();
      final expiry =
          value.expiresAt.isBefore(value.evaluatedAt.add(maxDisplayAge))
              ? value.expiresAt
              : value.evaluatedAt.add(maxDisplayAge);
      _expiryTimer = Timer(expiry.difference(now), () {
        if (!_disposed) notifyListeners();
      });
      if (!_disposed) notifyListeners();
      return snapshot != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureAllowed(String id, {Duration maxAge = Duration.zero}) =>
      ensureAllAllowed([id], maxAge: maxAge);

  /// Whether the held policy was fetched for this session within [maxAge]
  /// and has not expired, so a re-check moments after a fresh check can
  /// read it instead of asking the backend again.
  bool _reusable(Duration maxAge) {
    if (maxAge <= Duration.zero) return false;
    final held = _snapshot;
    final fetchedAt = _snapshotFetchedAt;
    if (held == null || fetchedAt == null) return false;
    if (_snapshotSession != _sessionToken()) return false;
    final now = _clock().toUtc();
    return now.difference(fetchedAt) <= maxAge && held.expiresAt.isAfter(now);
  }

  /// Shared setup can support either a new operation or an allowed exit.
  Future<void> ensureAnyAllowed(List<String> ids) async {
    assert(ids.isNotEmpty);
    final fresh = await refresh();
    CapabilityDecision value(String id) =>
        fresh ? decision(id) : _unavailableDecision(id);
    if (ids.any((id) => value(id).allowed && !value(id).comingSoon)) return;
    throw CapabilityUnavailableException(ids.first, value(ids.first));
  }

  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    final requested = ids.toList(growable: false);
    // Direct provider location checks precede the authenticated Kute policy.
    // Hot-wallet, Ledger and funding callers share this execution-time gate.
    // Read/cancel/close/withdraw capabilities never use the new-exposure gate.
    // A caller re-checking moments after a fresh check may read the policy
    // it just fetched ([maxAge]) instead of fetching it again.
    await _ensureProviderAvailability(requested);
    final fresh = _reusable(maxAge) ? true : await refresh();
    for (final id in requested) {
      final value = fresh ? decision(id) : _unavailableDecision(id);
      if (!value.allowed || value.comingSoon) {
        throw CapabilityUnavailableException(id, value);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _refreshTimer?.cancel();
    _client.close();
    super.dispose();
  }
}

// The app owns this singleton. A nested navigation scope must only detach its
// listener, never dispose the shared HTTP client or foreground refresh timer.
final runtimeCapabilitiesProvider = Provider<RuntimeCapabilitiesService>((ref) {
  final service = RuntimeCapabilitiesService.instance;
  service.addListener(ref.notifyListeners);
  ref.onDispose(() => service.removeListener(ref.notifyListeners));
  return service;
});
