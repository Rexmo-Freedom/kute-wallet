import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/http/fresh_connection.dart';
import 'package:kute/l10n/l10n.dart'
    show AppLocalizations, appL10n, l10nForLanguage;
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';
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

  /// Allowed only because the backend allowed it the last time it could be
  /// reached, within [RuntimeCapabilitiesService.offlineGrace]. Screens
  /// may say "offline" next to the control; nothing is blocked.
  bool get offline => reason == 'offline_grace';

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
    if (offline) return l10n.capabilityOfflineGrace;
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
            json['investing'] as Map<String, dynamic>? ?? {}),
        polymarket = Map<String, dynamic>.unmodifiable(
            json['polymarket'] as Map<String, dynamic>? ?? {}) {
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

  /// Polymarket settings published by the backend.
  final Map<String, dynamic> polymarket;

  /// Kute's Polymarket builder (attribution) code, or null when the policy
  /// does not carry one (a backend older than this field). Orders are
  /// signed with it; `RuntimeCapabilitiesService.polymarketBuilderCode`
  /// reads it across the policies on hand.
  String? get polymarketBuilderCode {
    final v = polymarket['builderCode'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }
}

/// The offline defaults: what the app may do while the backend policy
/// cannot be fetched and this device holds no earlier policy for the
/// session (never fetched, or last fetched more than
/// [RuntimeCapabilitiesService.offlineGrace] ago). Everything not listed
/// here is denied with reason `policy_unavailable`.
///
/// With an earlier policy on hand (held in memory or restored from disk),
/// that policy decides instead: a capability it allowed stays allowed with
/// reason `offline_grace`, and one it denied stays denied with its own
/// reason. Only an explicit server deny blocks.
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
/// A denial (or coming-soon) seen in a loaded policy still stands during
/// an outage, including for the ids allowed here. Execution that itself
/// needs Kute's backend (Orchestra routes, the relayer) still fails on its
/// own when the backend is down.
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

/// Backend policy is independent of analytics consent.
///
/// Two policies, layered:
/// * the **session policy** (`/config/capabilities`, wallet session):
///   everything the backend knows, account and wallet rules included.
///   Decides whenever it is fresh;
/// * the **public policy** (`/config/policy`, no session, country, platform
///   and app version rules only): fetched first at boot and whenever no
///   fresh session policy is on hand, so a fresh wallet, a wallet whose
///   sign-in is still pending and a wallet in an outage read the backend's
///   current rules. Account rules it cannot evaluate come back as
///   `affiliate_unknown` / `wallet_unknown`: unknown, never a deny.
///
/// With neither fresh, the last policies fetched decide for [offlineGrace]
/// (saved on disk, so this covers a cold start too), and with none
/// [kOfflineAllowedCapabilities] decides. Explicit restrictions, feature
/// switches, account checks and server execution gates remain authoritative.
class RuntimeCapabilitiesService extends ChangeNotifier
    with WidgetsBindingObserver {
  RuntimeCapabilitiesService._()
      : _client = null,
        _baseUrl =
            (() => dotenv.isInitialized ? dotenv.env['BACKEND'] ?? '' : ''),
        _sessionToken = (() => AffiliateService.sessionToken),
        _sessionOwner = _ownerOfToken,
        _ensureSession = (() => AffiliateService.ensureSession()),
        _renewSession =
            ((token) => AffiliateService.ensureSession(rejected: token)),
        _platform = Platform.isIOS ? 'ios' : 'android',
        _appVersion = (() async => (await PackageInfo.fromPlatform()).version),
        _clock = DateTime.now,
        _store = const HiveRuntimePolicySnapshotStore(),
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
    RuntimePolicySnapshotStore? store,
    String? Function(String? token)? sessionOwner,
  })  : _client = client,
        _baseUrl = baseUrl,
        _sessionToken = sessionToken,
        _sessionOwner = sessionOwner ?? ((token) => token),
        _ensureSession = (() async => sessionToken()),
        _renewSession = ((_) async => null),
        _platform = platform,
        _appVersion = appVersion ?? (() async => '1.0.0'),
        _clock = clock ?? DateTime.now,
        _store = store ?? MemoryRuntimePolicySnapshotStore(),
        _ensureProviderAvailability =
            ensureProviderAvailability ?? ((_) async {});

  static final _instance = RuntimeCapabilitiesService._();
  @visibleForTesting
  static RuntimeCapabilitiesService? debugInstance;
  static RuntimeCapabilitiesService get instance => debugInstance ?? _instance;
  final http.Client? _client;
  int _fetchGeneration = 0;
  final Future<void> Function(Iterable<String>) _ensureProviderAvailability;
  final String Function() _baseUrl;
  final String? Function() _sessionToken;

  /// The stable owner of a session token: the same wallet keeps the same
  /// owner across token renewals, so a renewed token does not drop the
  /// policy that was fetched moments before. Null means no session.
  final String? Function(String? token) _sessionOwner;
  final Future<String?> Function() _ensureSession;
  final Future<String?> Function(String) _renewSession;
  final String _platform;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;
  final RuntimePolicySnapshotStore _store;

  /// The session policy, fresh or not.
  RuntimeCapabilities? _snapshot;

  /// When [_snapshot] was fetched, by this device's clock, so a caller may
  /// reuse a policy it just fetched instead of asking again, and so the
  /// offline grace can be measured from it.
  DateTime? _snapshotFetchedAt;

  /// The session owner [_snapshot] was evaluated for.
  String? _snapshotOwner;

  /// The public policy, fresh or not, and when it was fetched.
  RuntimeCapabilities? _public;
  DateTime? _publicFetchedAt;

  /// Bumped by [networkChanged]. Each policy remembers the epoch its fetch
  /// started in; a region denial from an older network is not trusted
  /// (see [_regionTrusted]). Policies restored from disk carry
  /// [_restoredEpoch]: they were asked before this launch.
  int _networkEpoch = 0;
  static const _restoredEpoch = -1;
  int _snapshotEpoch = _restoredEpoch;
  int _publicEpoch = _restoredEpoch;

  /// False only while [confirmDecision] answers a tap whose fresh policy
  /// did not arrive in time: then a refresh still in flight does not keep
  /// a region denial from another network standing.
  bool _trustWhileRefreshing = true;
  Future<bool>? _refresh;
  Timer? _expiryTimer;
  Timer? _publicExpiryTimer;
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

  /// How long a capability the backend last allowed stays allowed while the
  /// backend cannot be reached (reason `offline_grace`), measured from the
  /// moment that policy was fetched. Past it, [kOfflineAllowedCapabilities]
  /// decides again. A denial never expires into permission.
  static const offlineGrace = Duration(hours: 24);

  /// The session policy while the server's `expiresAt` has not passed.
  /// The server sets the expiry (15 minutes); the once-a-minute refresh
  /// keeps it current while the app is in the foreground.
  RuntimeCapabilities? get snapshot => _fresh(_held);

  /// The public policy while its `expiresAt` has not passed.
  RuntimeCapabilities? get publicSnapshot => _fresh(_public);

  RuntimeCapabilities? _fresh(RuntimeCapabilities? value) {
    if (value == null) return null;
    return _clock().toUtc().isBefore(value.expiresAt) ? value : null;
  }

  /// The session policy fetched for the current session, fresh or not.
  /// Null when none was fetched (or restored) for this session's owner.
  RuntimeCapabilities? get _held {
    final value = _snapshot;
    if (value == null) return null;
    final owner = _sessionOwner(_sessionToken());
    if (owner == null || owner != _snapshotOwner) return null;
    return value;
  }

  /// Whether a policy fetched at [fetchedAt] is still within [offlineGrace].
  bool _withinGrace(DateTime? fetchedAt) {
    if (fetchedAt == null) return false;
    return _clock().toUtc().difference(fetchedAt) <= offlineGrace;
  }

  /// The stable owner of Kute's wallet-session token
  /// (`pubkey|affiliate_id|exp[|iat]`, base64url before the first dot): the
  /// `affiliates.id` (what `AffiliateService.affiliateId` shows in Settings
  /// → Advanced), or, for a token without one, a one-way reference to the
  /// token's identity field. Neither the token nor the key goes to disk.
  static String? _ownerOfToken(String? token) {
    if (token == null || token.isEmpty) return null;
    String reference(String value) =>
        'ref_${sha256.convert(utf8.encode('kute:policy-owner:v1\u0000$value')).toString().substring(0, 16)}';
    try {
      final fields = utf8
          .decode(base64Url.decode(base64Url.normalize(token.split('.').first)))
          .split('|');
      if (fields.length == 3 || fields.length == 4) {
        final id = int.tryParse(fields[1]);
        if (id != null && id > 0) return '$id';
        if (fields.first.isNotEmpty) return reference(fields.first);
      }
    } catch (_) {}
    return reference(token);
  }

  /// On the public route the account and wallet allow lists cannot be
  /// evaluated; the backend answers these reasons. They mean "unknown",
  /// never a deny: the session policy's decision stands, else the offline
  /// table.
  static const _accountUnknownReasons = {'affiliate_unknown', 'wallet_unknown'};

  static bool _isAccountUnknown(CapabilityDecision value) =>
      !value.allowed && _accountUnknownReasons.contains(value.reason);

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
    if (current != null) {
      final value = current.capabilities[id];
      if (value != null) {
        return _regional(_locationDecision(id, value), _snapshotEpoch);
      }
      return const CapabilityDecision(
          allowed: false, reason: 'unknown_capability');
    }
    final public = publicSnapshot;
    if (public != null) {
      final value = public.capabilities[id];
      if (value != null && !_isAccountUnknown(value)) {
        return _regional(_locationDecision(id, value), _publicEpoch);
      }
      // An account rule the public route cannot evaluate, or an id it does
      // not name: the last session policy decides, else the offline table.
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

  /// [value] as it may be shown now: a region denial that is no longer
  /// trusted ([_regionTrusted]) reads as an unknown location, allowed,
  /// the same answer a loaded policy gives when it cannot place the
  /// caller. Every other decision is returned as it is.
  CapabilityDecision _regional(CapabilityDecision value, int epoch) {
    if (value.allowed || value.comingSoon || !value.regionRestricted) {
      return value;
    }
    if (_regionTrusted(epoch)) return value;
    return const CapabilityDecision(allowed: true, reason: 'country_unknown');
  }

  /// Whether a region denial (`country_blocked`, `country_not_allowed`)
  /// fetched in network [epoch] is believed. The backend places the caller
  /// by the connection, so the answer belongs to the network it was asked
  /// on:
  ///   * same network, no change since: believed, through an outage too,
  ///     for as long as the policy itself is (the offline grace); a fresh
  ///     allow replaces it at once;
  ///   * asked before a network change: believed only while the refetch
  ///     on the new network is answering (so a re-check never flickers;
  ///     a tap always waits for that answer). If the refetch fails it is
  ///     an unknown location: a denial from another network says nothing
  ///     about where the person is now;
  ///   * restored from disk at launch: never, until this launch's fetch
  ///     answers. Everything else in a restored policy still applies.
  bool _regionTrusted(int epoch) {
    if (epoch == _networkEpoch) return true;
    if (epoch == _restoredEpoch) return false;
    return _refresh != null &&
        _trustWhileRefreshing &&
        _impatientEpoch != _networkEpoch;
  }

  /// The network epoch whose refetch a "Check connection" tap stopped
  /// waiting for ([connectionCheckTimedOut]).
  int _impatientEpoch = _restoredEpoch;

  /// A "Check connection" tap (lib/services/region_freshness.dart) asked
  /// the policy again ([networkChanged]) and the refetch did not answer in
  /// time: a region denial from before the tap stops counting now rather
  /// than when that refetch gives up, since a check that could not be
  /// made never shows restricted. The refetch still lands: a fresh denial
  /// from this network stands again then. Screens hear it.
  void connectionCheckTimedOut() {
    if (_impatientEpoch == _networkEpoch) return;
    _impatientEpoch = _networkEpoch;
    if (!_disposed) notifyListeners();
  }

  /// The network may have changed (lib/services/region_freshness.dart):
  /// region denials fetched before now stop being trusted, and the
  /// policies are fetched again on the new network. Screens hear both.
  /// Resolves with that fetch's outcome.
  Future<bool> networkChanged() {
    _networkEpoch++;
    if (!_disposed) notifyListeners();
    return refresh(fresh: true);
  }

  /// The decision with no fresh policy: what the policies last fetched said.
  CapabilityDecision _unavailableDecision(String id) {
    // The last decisions on hand for [id], session policy first. Account
    // rules the public route could not evaluate say nothing.
    final previous = <(CapabilityDecision, DateTime?)>[
      if (_held?.capabilities[id] case final value?)
        (
          _regional(_locationDecision(id, value), _snapshotEpoch),
          _snapshotFetchedAt
        ),
      if (_public?.capabilities[id] case final value?
          when !_isAccountUnknown(value))
        (
          _regional(_locationDecision(id, value), _publicEpoch),
          _publicFetchedAt
        ),
    ];
    // A failed refresh must not turn a previously observed admin disablement,
    // version requirement or explicit country block into permission. A
    // country block asked from another network (before a network change,
    // or before this launch) was already read as an unknown location
    // above ([_regionTrusted])...
    for (final (decision, _) in previous) {
      if (!decision.allowed || decision.comingSoon) return decision;
    }
    // ...and must not turn a previous permission into a refusal either, for
    // as long as that policy is recent enough to trust offline.
    for (final (_, fetchedAt) in previous) {
      if (_withinGrace(fetchedAt)) {
        return const CapabilityDecision(allowed: true, reason: 'offline_grace');
      }
    }
    return CapabilityDecision(
        allowed: kOfflineAllowedCapabilities.contains(id),
        reason: 'policy_unavailable');
  }

  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  /// The Investing leverage cap for this region: null when the policy sets
  /// none. Without a fresh policy the last cap seen stands (the session
  /// policy's first, then the public one's), and with none ever seen the
  /// cap is 1x, so an outage can only ever tighten leverage, never loosen
  /// it.
  int? get maxLeverage {
    for (final policy in [snapshot, publicSnapshot, _held, _public]) {
      if (policy != null) return policy.maxLeverage;
    }
    return 1;
  }

  /// Kute's Polymarket builder (attribution) code from the newest policy on
  /// hand, fresh or held: the session policy's first, else the public one's.
  /// Null until a policy that carries one has been fetched. Attribution is
  /// not a permission, so a held copy serves.
  String? get polymarketBuilderCode {
    for (final policy in [snapshot, publicSnapshot, _held, _public]) {
      final code = policy?.polymarketBuilderCode;
      if (code != null) return code;
    }
    return null;
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

  /// Loads the policies saved on disk, then starts the first fetch and the
  /// periodic refresh. Returns the first fetch's outcome (true when a fresh
  /// policy landed) so boot can record whether the backend was reachable.
  /// Needs no session: the public policy goes out at once, and the session
  /// policy joins when a session exists (see [refreshAfterCurrent]).
  /// Idempotent: a second call returns the fetch already in flight.
  Future<bool> start() {
    if (_started) return refresh();
    _started = true;
    restore();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(refresh());
      }
    });
    return refresh();
  }

  /// Adopts the policies saved by the last successful fetches, each if it
  /// is still within [offlineGrace], as the held policies. The session one
  /// is bound to the owner it was fetched for, so another wallet's session
  /// never reads it. A slot already held in memory is left alone.
  void restore() {
    var adopted = false;
    if (_snapshot == null) {
      final stored = _restoreSlot(RuntimePolicySlot.session);
      if (stored != null && stored.$2.owner != kPublicPolicyOwner) {
        _snapshot = stored.$1;
        _snapshotOwner = stored.$2.owner;
        _snapshotFetchedAt = stored.$2.fetchedAt;
        _snapshotEpoch = _restoredEpoch;
        adopted = true;
      }
    }
    if (_public == null) {
      final stored = _restoreSlot(RuntimePolicySlot.public);
      if (stored != null && stored.$2.owner == kPublicPolicyOwner) {
        _public = stored.$1;
        _publicFetchedAt = stored.$2.fetchedAt;
        _publicEpoch = _restoredEpoch;
        adopted = true;
      }
    }
    if (adopted && !_disposed) notifyListeners();
  }

  (RuntimeCapabilities, StoredRuntimePolicy)? _restoreSlot(
      RuntimePolicySlot slot) {
    final stored = _store.read(slot);
    if (stored == null) return null;
    try {
      final value = RuntimeCapabilities.fromJson(stored.policy);
      if (_clock().toUtc().difference(stored.fetchedAt) > offlineGrace) {
        _store.clear(slot);
        return null;
      }
      return (value, stored);
    } catch (_) {
      // Unreadable (schema change, corrupt file): forget it.
      _store.clear(slot);
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  /// [fresh] starts a new fetch even if an earlier request is running.
  /// Only the most recently started fetch may publish a policy.
  Future<bool> refresh({bool fresh = false}) {
    final running = _refresh;
    if (!fresh && running != null) return running;
    final future = _fetch();
    _refresh = future;
    return future.whenComplete(() {
      if (identical(_refresh, future)) _refresh = null;
    }).then((landed) {
      // Nothing new landed after a network change: a region denial from
      // the old network was shown only while this refresh answered, and
      // now reads as unknown. Screens re-read, once per network change.
      // Never on every failed refresh: a listener that refreshes when the
      // policy notifies (aiEnabledProvider) would loop for as long as the
      // backend is unreachable.
      if (!landed &&
          !_disposed &&
          _failureNotifiedEpoch != _networkEpoch &&
          _holdsRegionDenialFromEarlierNetwork) {
        _failureNotifiedEpoch = _networkEpoch;
        notifyListeners();
      }
      return landed;
    });
  }

  /// The network epoch whose failed refetch has already been announced.
  int _failureNotifiedEpoch = _restoredEpoch;

  /// A held policy carries a region denial fetched before the latest
  /// network change (not restored from disk: those are never trusted, so
  /// a failed refresh changes nothing about them).
  bool get _holdsRegionDenialFromEarlierNetwork {
    bool stale(RuntimeCapabilities? policy, int epoch) =>
        policy != null &&
        epoch != _networkEpoch &&
        epoch != _restoredEpoch &&
        policy.capabilities.values
            .any((d) => !d.allowed && !d.comingSoon && d.regionRestricted);
    return stale(_snapshot, _snapshotEpoch) || stale(_public, _publicEpoch);
  }

  /// A refresh that starts after the one in flight, for a caller that has
  /// just made a session available (boot reads the stored token after the
  /// first fetch, which only had the public policy to ask for, went out).
  Future<bool> refreshAfterCurrent() {
    final running = _refresh;
    if (running == null) return refresh();
    return running.then((_) => refresh());
  }

  /// One refresh: the public policy whenever no fresh session policy is on
  /// hand (boot, a fresh wallet, an outage), in parallel with the session
  /// policy; with a fresh session policy, the session policy only. True
  /// when either landed fresh.
  Future<bool> _fetch() async {
    final epoch = _networkEpoch;
    final generation = ++_fetchGeneration;
    final backend = _baseUrl().replaceFirst(RegExp(r'/$'), '');
    if (backend.isEmpty) return false;
    final context = await requestContextHeaders();
    final version = _version;
    if (version == null) return false;
    final query = {'platform': _platform, 'appVersion': version};
    final publicFetch = snapshot == null
        ? _fetchPublic(backend, context, query, epoch, generation)
        : Future<bool>.value(false);
    final sessionLanded =
        await _fetchSession(backend, context, query, epoch, generation);
    final publicLanded = await publicFetch;
    return sessionLanded || publicLanded;
  }

  /// Two attempts: a healthy connection answers well inside the first, and
  /// a slow tunnel gets the time it needs instead of a refusal.
  Future<http.Response> _send(Uri uri, Map<String, String> headers) async {
    Future<http.Response> attempt(Duration timeout) => FreshConnection.send(
          (client) => client.get(uri, headers: headers).timeout(timeout),
          connect: _client == null ? null : () => BorrowedClient(_client),
        );
    try {
      return await attempt(const Duration(seconds: 5));
    } on TimeoutException {
      return attempt(const Duration(seconds: 10));
    }
  }

  /// A policy body the device may adopt: parsed, not already expired by the
  /// device clock, not evaluated in the device's future. Null otherwise.
  RuntimeCapabilities? _acceptable(Map<String, dynamic> body, DateTime now) {
    final value = RuntimeCapabilities.fromJson(body);
    if (!value.expiresAt.isAfter(now) ||
        value.evaluatedAt.isAfter(now.add(const Duration(minutes: 1)))) {
      return null;
    }
    return value;
  }

  Future<bool> _fetchSession(String backend, Map<String, String> context,
      Map<String, String> query, int epoch, int generation) async {
    try {
      var token = await _ensureSession();
      if (token == null || token.isEmpty) return false;
      final uri = Uri.parse('$backend/api/v1/config/capabilities')
          .replace(queryParameters: query);
      Future<http.Response> send(String bearer) =>
          _send(uri, {...context, 'Authorization': 'Bearer $bearer'});
      var response = await send(token);
      if (response.statusCode == 401 && token == _sessionToken()) {
        token = await _renewSession(token);
        if (token == null || token.isEmpty) return false;
        response = await send(token);
      }
      if (response.statusCode != 200 || token != _sessionToken()) return false;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final now = _clock().toUtc();
      final value = _acceptable(body, now);
      if (value == null ||
          epoch != _networkEpoch ||
          generation != _fetchGeneration ||
          _disposed) return false;
      final owner = _sessionOwner(token);
      if (owner == null) return false;
      if (_snapshotOwner == owner &&
          _snapshot != null &&
          value.revision < _snapshot!.revision) {
        return false;
      }
      _snapshot = value;
      _snapshotOwner = owner;
      _snapshotFetchedAt = now;
      _snapshotEpoch = epoch;
      _store.write(RuntimePolicySlot.session,
          StoredRuntimePolicy(owner: owner, fetchedAt: now, policy: body));
      _expiryTimer?.cancel();
      _expiryTimer = _notifyAt(value.expiresAt, now);
      if (!_disposed) notifyListeners();
      return snapshot != null;
    } catch (_) {
      return false;
    }
  }

  /// The public policy. A backend without the route answers 404: then the
  /// session policy alone decides, exactly as before the route existed.
  Future<bool> _fetchPublic(String backend, Map<String, String> context,
      Map<String, String> query, int epoch, int generation) async {
    try {
      final uri = Uri.parse('$backend/api/v1/config/policy')
          .replace(queryParameters: query);
      final response = await _send(uri, context);
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final now = _clock().toUtc();
      final value = _acceptable(body, now);
      if (value == null ||
          epoch != _networkEpoch ||
          generation != _fetchGeneration ||
          _disposed) return false;
      if (_public != null && value.revision < _public!.revision) return false;
      _public = value;
      _publicFetchedAt = now;
      _publicEpoch = epoch;
      _store.write(
          RuntimePolicySlot.public,
          StoredRuntimePolicy(
              owner: kPublicPolicyOwner, fetchedAt: now, policy: body));
      _publicExpiryTimer?.cancel();
      _publicExpiryTimer = _notifyAt(value.expiresAt, now);
      if (!_disposed) notifyListeners();
      return publicSnapshot != null;
    } catch (_) {
      return false;
    }
  }

  /// Wakes listeners when a policy stops being fresh, so a screen showing
  /// its decisions re-reads them.
  Timer _notifyAt(DateTime expiresAt, DateTime now) =>
      Timer(expiresAt.difference(now), () {
        if (!_disposed) notifyListeners();
      });

  Future<void> ensureAllowed(String id, {Duration maxAge = Duration.zero}) =>
      ensureAllAllowed([id], maxAge: maxAge);

  /// Whether the held policy was fetched for this session within [maxAge]
  /// and has not expired, so a re-check moments after a fresh check can
  /// read it instead of asking the backend again.
  bool _reusable(Duration maxAge) {
    if (maxAge <= Duration.zero) return false;
    final held = _held;
    final fetchedAt = _snapshotFetchedAt;
    if (held == null || fetchedAt == null) return false;
    final now = _clock().toUtc();
    return now.difference(fetchedAt) <= maxAge && held.expiresAt.isAfter(now);
  }

  /// How long a tap waits for [confirmDecision]'s fresh policy before it
  /// answers with what it has.
  static const confirmTimeout = Duration(seconds: 4);

  /// Each gated tap starts a policy fetch after the tap, on a dedicated
  /// connection, bounded by [confirmTimeout]. Earlier requests cannot
  /// overwrite its answer.
  /// Never throws.
  Future<CapabilityDecision> confirmDecision(String id) async {
    bool fresh;
    try {
      fresh = await refresh(fresh: true)
          .timeout(confirmTimeout, onTimeout: () => false);
    } catch (_) {
      fresh = false;
    }
    if (fresh) return decision(id);
    // No fresh answer in time: what the last policies said, where a region
    // denial from another network never counts just because a slow
    // refresh is still on its way.
    _trustWhileRefreshing = false;
    try {
      return _unavailableDecision(id);
    } finally {
      _trustWhileRefreshing = true;
    }
  }

  /// Shared setup can support either a new operation or an allowed exit.
  Future<void> ensureAnyAllowed(List<String> ids) async {
    assert(ids.isNotEmpty);
    final fresh = await refresh(fresh: true);
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
    // A refusal is never read from a reused policy: it is asked again.
    final reuse = _reusable(maxAge) &&
        requested
            .every((id) => decision(id).allowed && !decision(id).comingSoon);
    final fresh = reuse ? true : await refresh(fresh: true);
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
    _publicExpiryTimer?.cancel();
    _refreshTimer?.cancel();
    _client?.close();
    super.dispose();
  }
}

/// [policy]'s decision for a door the person just tapped: at once when it
/// allows; a refusal is asked again first
/// ([RuntimeCapabilitiesService.confirmDecision]), so a stale "unavailable"
/// never shuts a door that is open now. A policy that cannot ask again (a
/// test double answering [RuntimeCapabilitiesService.decision] only)
/// keeps its answer. Never throws.
Future<CapabilityDecision> confirmCapability(
    RuntimeCapabilitiesService policy, String id) async {
  final held = policy.decision(id);
  if (held.allowed && !held.comingSoon) return held;
  try {
    return await policy.confirmDecision(id);
  } catch (_) {
    return held;
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
