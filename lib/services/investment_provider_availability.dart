import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart' show AppLocalizations, appL10n, l10nForLanguage;
import 'package:kute/services/network_change_signal.dart';
import 'package:kute/services/tracking_service.dart';

enum InvestmentProvider { hyperliquid, polymarket }

enum ProviderAvailabilityStatus { allowed, restricted, unavailable }

class ProviderAvailability {
  const ProviderAvailability(this.provider, this.status);

  final InvestmentProvider provider;
  final ProviderAvailabilityStatus status;

  String get providerName =>
      provider == InvestmentProvider.hyperliquid ? 'Hyperliquid' : 'Polymarket';

  /// The sentence for this answer in the app language. See [messageIn].
  String get message => messageIn(appL10n());

  String messageIn(AppLocalizations l10n) =>
      status == ProviderAvailabilityStatus.restricted
          ? l10n.providerRegionRestricted(providerName)
          : l10n.providerAvailabilityUnknown(providerName);

  void ensureAllowed() {
    if (status == ProviderAvailabilityStatus.restricted) {
      throw ProviderAvailabilityException(this);
    }
  }
}

/// Where a live location check goes for analytics: the venue (`polymarket`
/// or `hyperliquid`), why it was asked, whether the answer flipped and
/// what it was.
typedef RegionCheckReporter = void Function({
  required String venue,
  required String trigger,
  required bool changed,
  required String result,
});

class ProviderAvailabilityException implements Exception {
  const ProviderAvailabilityException(this.availability);
  final ProviderAvailability availability;

  /// English on purpose: exception text feeds error categories and logs.
  /// Screens show the availability's [ProviderAvailability.messageIn].
  @override
  String toString() => availability.messageIn(l10nForLanguage('en'));
}

/// These requests must originate on the user's device. A backend proxy would
/// check the server's country instead. Results authorize only new exposure;
/// providers still enforce account, terms and transaction-level restrictions.
///
/// FRESHNESS. A venue's location answer follows the network the phone is
/// on, so it is never trusted longer than that network:
///   * an allowed answer is reused for five minutes ([defaultCacheFor]);
///   * a restricted answer for one minute at most
///     ([defaultRestrictedCacheFor]), and it is dropped on resume;
///   * a network change drops every answer and asks again
///     (lib/services/region_freshness.dart);
///   * an unavailable check (timeout, error, malformed body) is never
///     cached, never reads as restricted, and drops a held refusal;
///   * before a cached refusal stops an action ([ensureNewExposure]) the
///     venue is asked again live, with a short timeout, unless that
///     refusal was itself fetched moments ago ([defaultTapReuse]). A live
///     "allowed" proceeds; a live failure is unknown, which never blocks.
/// Listeners hear every change of answer, so a screen showing a refusal
/// lifts it without a restart.
class InvestmentProviderAvailability extends ChangeNotifier {
  InvestmentProviderAvailability({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
    Duration cacheFor = defaultCacheFor,
    Duration restrictedCacheFor = defaultRestrictedCacheFor,
    Duration tapTimeout = defaultTapTimeout,
    Duration tapReuse = defaultTapReuse,
    DateTime Function()? clock,
    RegionCheckReporter? report,
  })  : _client = client ?? http.Client(),
        _timeout = timeout,
        _cacheFor = cacheFor,
        _restrictedCacheFor = restrictedCacheFor,
        _tapTimeout = tapTimeout,
        _tapReuse = tapReuse,
        _clock = clock ?? DateTime.now,
        _report = report ?? TrackingService.regionChecked;

  static final instance = InvestmentProviderAvailability();
  final http.Client _client;
  final Duration _timeout;
  final DateTime Function() _clock;
  final RegionCheckReporter _report;

  /// How long an allowed answer is reused. Zero disables the cache.
  static const defaultCacheFor = Duration(minutes: 5);

  /// How long a restricted answer is reused: never more than a minute.
  static const defaultRestrictedCacheFor = Duration(seconds: 60);

  /// The live re-ask before a cached refusal is shown at a tap: short, so
  /// a stale "restricted" costs at most this much before the bet goes on.
  static const defaultTapTimeout = Duration(seconds: 3);

  /// A refusal fetched this recently was itself a live answer: a tap right
  /// after it does not ask again.
  static const defaultTapReuse = Duration(seconds: 2);

  final Duration _cacheFor;
  final Duration _restrictedCacheFor;
  final Duration _tapTimeout;
  final Duration _tapReuse;

  /// Definite answers and when they were fetched.
  final Map<InvestmentProvider, (ProviderAvailability, DateTime)> _cache = {};

  /// The last answer each provider gave a live check, unknown included:
  /// what the analytics `changed` compares against.
  final Map<InvestmentProvider, ProviderAvailabilityStatus> _lastAnswer = {};

  /// The live ask in flight per provider, with the network epoch it
  /// started in.
  final Map<InvestmentProvider, (Future<ProviderAvailability>, int)>
      _inFlight = {};

  /// Providers asked at least once this session: the ones a resume or a
  /// network change asks again.
  final Set<InvestmentProvider> _asked = {};

  /// Bumped by every network change: an answer that lands from an older
  /// network is returned to its caller but not cached.
  int _epoch = 0;
  final Map<InvestmentProvider, Timer> _restrictedTimers = {};

  /// Set by RegionFreshness: a restricted answer is asked again once it
  /// is a minute old, while a screen listens (a refusal is on screen)
  /// and the app is in the foreground.
  bool autoRecheck = false;
  bool _disposed = false;

  Duration _lifetime(ProviderAvailabilityStatus status) =>
      status == ProviderAvailabilityStatus.restricted &&
              _restrictedCacheFor < _cacheFor
          ? _restrictedCacheFor
          : _cacheFor;

  (ProviderAvailability, DateTime)? _entry(InvestmentProvider provider) {
    final entry = _cache[provider];
    if (entry == null) return null;
    final lifetime = _lifetime(entry.$1.status);
    if (lifetime <= Duration.zero ||
        _clock().difference(entry.$2) > lifetime) {
      return null;
    }
    return entry;
  }

  /// The answer on hand for [provider] without asking, or null.
  ProviderAvailability? cached(InvestmentProvider provider) =>
      _entry(provider)?.$1;

  /// Drops every answer (a network change): the next call asks again, and
  /// an ask still in flight from the old network is not cached.
  void invalidate() {
    _epoch++;
    _cache.clear();
    _cancelRestrictedTimers();
  }

  /// Drops the refusals only (a resume): allowed answers keep their five
  /// minutes.
  void dropRestricted() {
    _cache.removeWhere(
        (_, e) => e.$1.status == ProviderAvailabilityStatus.restricted);
    _cancelRestrictedTimers();
  }

  void _cancelRestrictedTimers() {
    for (final timer in _restrictedTimers.values) {
      timer.cancel();
    }
    _restrictedTimers.clear();
  }

  /// Asks again, live, for [trigger]: [providers], or every provider this
  /// session has asked about. A network change (or a "Check connection"
  /// tap, which is one the person reports) drops every answer first; a
  /// resume drops the refusals. Never throws.
  Future<void> recheck(RegionRecheckTrigger trigger,
      {Iterable<InvestmentProvider>? providers}) async {
    if (trigger == RegionRecheckTrigger.networkChange ||
        trigger == RegionRecheckTrigger.manual) {
      invalidate();
    } else if (trigger == RegionRecheckTrigger.resume ||
        trigger == RegionRecheckTrigger.pull) {
      dropRestricted();
    }
    final targets = providers?.toSet() ?? _asked.toSet();
    await Future.wait([
      for (final provider in targets)
        check(provider, trigger: trigger, live: true)
            .then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  /// [provider]'s answer: the cached one while it is good, else a live
  /// ask (one at a time per provider and network). [live] skips the
  /// cache. Never throws: a failed ask is
  /// [ProviderAvailabilityStatus.unavailable].
  Future<ProviderAvailability> check(InvestmentProvider provider,
      {RegionRecheckTrigger trigger = RegionRecheckTrigger.tap,
      bool live = false,
      Duration? timeout}) {
    _asked.add(provider);
    if (!live) {
      final cached = this.cached(provider);
      if (cached != null) return Future.value(cached);
    }
    final running = _inFlight[provider];
    if (running != null && running.$2 == _epoch) return running.$1;
    final epoch = _epoch;
    final future = _fetch(provider, timeout ?? _timeout)
        .then((value) => _record(value, trigger, epoch));
    _inFlight[provider] = (future, epoch);
    future.whenComplete(() {
      if (identical(_inFlight[provider]?.$1, future)) {
        _inFlight.remove(provider);
      }
    }).ignore();
    return future;
  }

  ProviderAvailability _record(
      ProviderAvailability value, RegionRecheckTrigger trigger, int epoch) {
    final provider = value.provider;
    final previous = _lastAnswer[provider];
    final changed = previous != null && previous != value.status;
    _lastAnswer[provider] = value.status;
    if (value.status == ProviderAvailabilityStatus.unavailable) {
      // Unknown never stands in for a refusal: a held "restricted" goes.
      if (_cache[provider]?.$1.status ==
          ProviderAvailabilityStatus.restricted) {
        _cache.remove(provider);
      }
    } else if (epoch == _epoch) {
      _cache[provider] = (value, _clock());
    }
    _restrictedTimers.remove(provider)?.cancel();
    if (value.status == ProviderAvailabilityStatus.restricted &&
        autoRecheck &&
        !_disposed) {
      _restrictedTimers[provider] = Timer(_restrictedCacheFor, () {
        _restrictedTimers.remove(provider);
        if (_disposed || !hasListeners || !_foreground()) return;
        unawaited(recheck(RegionRecheckTrigger.timer, providers: [provider]));
      });
    }
    try {
      _report(
        venue: provider.name,
        trigger: trigger.id,
        changed: changed,
        result: switch (value.status) {
          ProviderAvailabilityStatus.allowed => 'allowed',
          ProviderAvailabilityStatus.restricted => 'restricted',
          ProviderAvailabilityStatus.unavailable => 'unknown',
        },
      );
    } catch (_) {}
    if (changed && !_disposed) notifyListeners();
    return value;
  }

  static bool _foreground() {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  Future<ProviderAvailability> _fetch(
          InvestmentProvider provider, Duration timeout) =>
      provider == InvestmentProvider.hyperliquid
          ? _fetchHyperliquid(timeout)
          : _fetchPolymarket(timeout);

  // The official Hyperliquid app uses this address for a disconnected legal
  // check. Country eligibility depends on restrictions, not wallet ownership.
  static const hyperliquidLegalCheckAddress =
      '0x4FaEC93ff98ab58bacb93dDA550bcB8294e590eE';

  /// Hyperliquid's own location answer, with the same reuse as
  /// Polymarket's below: every Investing deposit quote asked this again,
  /// in series before the policy fetch and the quote itself.
  Future<ProviderAvailability> hyperliquid(
          {RegionRecheckTrigger trigger = RegionRecheckTrigger.tap}) =>
      check(InvestmentProvider.hyperliquid, trigger: trigger);

  Future<ProviderAvailability> _fetchHyperliquid(Duration timeout) async {
    const provider = InvestmentProvider.hyperliquid;
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.hyperliquid.xyz/info'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': 'legalCheck',
              'user': hyperliquidLegalCheckAddress,
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        return const ProviderAvailability(
            provider, ProviderAvailabilityStatus.unavailable);
      }
      final data = jsonDecode(response.body);
      if (data is! Map ||
          data['acceptedTerms'] is! bool ||
          data['userAllowed'] is! bool) {
        return const ProviderAvailability(
            provider, ProviderAvailabilityStatus.unavailable);
      }
      // Official app ipAllowed mapping: n = unrestricted, a = block actions,
      // o = hide outcomes, u = UK. The latter two do not ban perpetual trading.
      // userAllowed / acceptedTerms are separate account setup checks. Never
      // infer a country ban from them or automatically accept terms.
      return ProviderAvailability(
          provider,
          switch (data['restrictions']) {
            'n' || 'o' || 'u' => ProviderAvailabilityStatus.allowed,
            'a' => ProviderAvailabilityStatus.restricted,
            _ => ProviderAvailabilityStatus.unavailable,
          });
    } catch (_) {
      return const ProviderAvailability(
          provider, ProviderAvailabilityStatus.unavailable);
    }
  }

  /// Polymarket's own geoblock answer.
  Future<ProviderAvailability> polymarket(
          {RegionRecheckTrigger trigger = RegionRecheckTrigger.tap}) =>
      check(InvestmentProvider.polymarket, trigger: trigger);

  Future<ProviderAvailability> _fetchPolymarket(Duration timeout) async {
    const provider = InvestmentProvider.polymarket;
    try {
      final response = await _client
          .get(Uri.parse('https://polymarket.com/api/geoblock'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['blocked'] is bool) {
          return ProviderAvailability(
              provider,
              data['blocked'] == true
                  ? ProviderAvailabilityStatus.restricted
                  : ProviderAvailabilityStatus.allowed);
        }
      }
    } catch (_) {
      // An unavailable location check is advisory. Only an explicit provider
      // restriction blocks here; transaction and account checks still apply.
    }
    return const ProviderAvailability(
        provider, ProviderAvailabilityStatus.unavailable);
  }

  /// The execution-time gate for new exposure. A refusal is only ever
  /// shown from a live answer: a cached "restricted" older than
  /// [defaultTapReuse] is asked again first, with the short tap timeout,
  /// and only a live "restricted" throws.
  Future<void> ensureNewExposure(Iterable<String> capabilities) async {
    final venues = providersFor(capabilities);
    if (venues.contains(InvestmentProvider.hyperliquid)) {
      (await _refusalOnlyIfLive(InvestmentProvider.hyperliquid))
          .ensureAllowed();
    }
    if (venues.contains(InvestmentProvider.polymarket)) {
      (await _refusalOnlyIfLive(InvestmentProvider.polymarket))
          .ensureAllowed();
    }
  }

  /// The venues whose own location answer gates [capabilities]: new
  /// exposure only (a trade or a deposit), never a read, a close or a
  /// withdrawal.
  static Set<InvestmentProvider> providersFor(Iterable<String> capabilities) {
    final requested = capabilities.toSet();
    return {
      if (requested.any(const {'hyperliquid.trade', 'hyperliquid.deposit'}
          .contains))
        InvestmentProvider.hyperliquid,
      if (requested.any(const {'polymarket.trade', 'polymarket.deposit'}
          .contains))
        InvestmentProvider.polymarket,
    };
  }

  Future<ProviderAvailability> _refusalOnlyIfLive(InvestmentProvider provider) {
    final entry = _entry(provider);
    if (entry != null &&
        entry.$1.status == ProviderAvailabilityStatus.restricted &&
        _clock().difference(entry.$2) > _tapReuse) {
      return check(provider, live: true, timeout: _tapTimeout);
    }
    return check(provider);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRestrictedTimers();
    super.dispose();
  }
}
