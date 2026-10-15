// lib/services/region_freshness.dart
//
// Every "available in your region" answer the app holds, kept as fresh as
// the network it was asked on. Founder report (October 2026): after
// landing in a country where predictions are allowed, the app kept saying
// they were restricted until it was restarted, and that cost bets.
//
// The answers, and what now refreshes them:
//   * Polymarket's geoblock and Hyperliquid's legal check
//     (InvestmentProviderAvailability): asked live at startup (Polymarket)
//     and on every resume and network change for each venue asked this
//     session; a refusal lives a minute at most and is re-asked live
//     before it stops a tap;
//   * Kute's runtime policy, session and public (RuntimeCapabilitiesService):
//     fetched on resume (its own observer) and on every network change,
//     where its region denials also stop being trusted until the new
//     network answers (a failed refetch reads as an unknown location; on
//     the same network a denial still stands through an outage, and one
//     restored at launch waits for the launch fetch). A tap on a refused
//     door asks again before it is shown (`confirmDecision`,
//     `ensureAllAllowed`).
//
// One signal drives them: [NetworkChangeSignal] (the native path listener
// plus resume, debounced). After each round, [answers] notifies, so a
// screen holding a refusal it worked out when it opened (the bet slip,
// the order ticket, the Builder) asks again and lifts it without a
// restart. Screens that watch the policy follow it on their own.
//
// No new chrome: a lifted refusal just goes away.
//
// "Check connection" (founder decision, October 2026): on iOS, switching
// servers inside one VPN app may not change the network path, so nothing
// above fires. Every region restriction the app shows (the bet slip, the
// order ticket, the Builder, the unavailable sheet) makes its one button
// "Check connection", never a dead one. A tap is the person telling us
// their connection changed: [checkConnection] runs a
// [RegionRecheckTrigger.manual] round (both venues asked live, Kute's
// region denials from before it distrusted and the policy fetched again),
// at most [checkConnectionTimeout], and the screen reads what stands with
// [regionRefused]. Allowed: the restriction goes and the screen carries on.
// Still restricted: the message stays, with a soft failure tap. A check
// that failed or ran out of time never shows restricted.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/network_change_signal.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

abstract final class RegionFreshness {
  static StreamSubscription<RegionRecheckTrigger>? _subscription;
  static final ValueNotifier<int> _rounds = ValueNotifier<int>(0);

  /// Test seam: the venues a round asks when its caller names none.
  @visibleForTesting
  static InvestmentProviderAvailability? debugVenues;

  static InvestmentProviderAvailability get _venues =>
      debugVenues ?? InvestmentProviderAvailability.instance;

  /// Notifies after every re-check round and whenever a venue's answer
  /// changes. Screens that hold a refusal listen and ask again.
  static final Listenable answers =
      Listenable.merge([_rounds, InvestmentProviderAvailability.instance]);

  /// Starts the signal and the rounds, and asks Polymarket once for the
  /// session (`startup`), so the first slip opens on a fresh answer.
  /// Idempotent. Never throws.
  static void start({
    NetworkChangeSignal? signal,
    InvestmentProviderAvailability? providers,
    RuntimeCapabilitiesService? policy,
  }) {
    if (_subscription != null) return;
    final source = signal ?? NetworkChangeSignal.instance;
    final venues = providers ?? _venues;
    venues.autoRecheck = true;
    try {
      source.start();
      _subscription = source.changes.listen((trigger) => unawaited(
          recheck(trigger, providers: venues, policy: policy)));
    } catch (_) {}
    unawaited(venues
        .recheck(RegionRecheckTrigger.startup,
            providers: const [InvestmentProvider.polymarket])
        .catchError((Object _) {}));
  }

  /// One round for [trigger]: the venues asked again (a network change
  /// drops every answer, a resume drops the refusals), the policy fetched
  /// again on a network change (a resume already fetches it), then
  /// [answers] notifies. A manual round ("Check connection") is a network
  /// change the person reports, and asks both venues whether or not this
  /// session asked them yet. Never throws.
  static Future<void> recheck(
    RegionRecheckTrigger trigger, {
    InvestmentProviderAvailability? providers,
    RuntimeCapabilitiesService? policy,
  }) async {
    final venues = providers ?? _venues;
    final capabilities = policy ?? RuntimeCapabilitiesService.instance;
    final manual = trigger == RegionRecheckTrigger.manual;
    try {
      await Future.wait([
        venues.recheck(trigger,
            providers: manual ? InvestmentProvider.values : null),
        if (trigger == RegionRecheckTrigger.networkChange || manual)
          capabilities.networkChanged().then<void>((_) {}),
        if (trigger == RegionRecheckTrigger.pull)
          capabilities.refresh().then<void>((_) {}),
      ]);
    } catch (_) {
      // A round that could not finish leaves the tap-time re-check.
    }
    _rounds.value++;
  }

  /// How long a "Check connection" tap waits for its round.
  static const checkConnectionTimeout = Duration(seconds: 5);

  /// The "Check connection" tap on a region restriction: one
  /// [RegionRecheckTrigger.manual] round, at most [timeout]. A round that
  /// does not finish in time is a check that could not be made, and that
  /// never shows restricted: Kute's region denials from before the tap
  /// stop counting at once
  /// ([RuntimeCapabilitiesService.connectionCheckTimedOut]; the venues'
  /// answers were already dropped), and [answers] notifies. What the round
  /// still fetches afterwards lands as usual. Never throws.
  static Future<void> checkConnection({
    InvestmentProviderAvailability? providers,
    RuntimeCapabilitiesService? policy,
    Duration timeout = checkConnectionTimeout,
  }) async {
    final capabilities = policy ?? RuntimeCapabilitiesService.instance;
    try {
      await recheck(RegionRecheckTrigger.manual,
              providers: providers, policy: capabilities)
          .timeout(timeout);
      return;
    } catch (_) {
      // Out of time: read as a check that could not be made.
    }
    try {
      capabilities.connectionCheckTimedOut();
    } catch (_) {}
    _rounds.value++;
  }

  /// Whether a region refusal stands for [capabilities] in the answers on
  /// hand, without asking (after [checkConnection], the fresh ones): a
  /// venue's own "restricted" for one of [venues] or for a venue gating
  /// [capabilities] ([InvestmentProviderAvailability.providersFor]), or
  /// Kute's region denial (`country_blocked`, `country_not_allowed`) of
  /// one of [capabilities]. Null [capabilities] reads every capability the
  /// policy names. A failed or timed-out check leaves neither. Never
  /// throws.
  static bool regionRefused({
    Iterable<String>? capabilities,
    Iterable<InvestmentProvider> venues = const [],
    InvestmentProviderAvailability? providers,
    RuntimeCapabilitiesService? policy,
  }) {
    final answers = providers ?? _venues;
    final rules = policy ?? RuntimeCapabilitiesService.instance;
    final asked = {
      ...venues,
      if (capabilities != null)
        ...InvestmentProviderAvailability.providersFor(capabilities),
    };
    for (final venue in asked) {
      try {
        if (answers.cached(venue)?.status ==
            ProviderAvailabilityStatus.restricted) {
          return true;
        }
      } catch (_) {}
    }
    Iterable<String> ids;
    try {
      ids = capabilities ??
          (rules.snapshot ?? rules.publicSnapshot)?.capabilities.keys ??
          const <String>[];
    } catch (_) {
      ids = const <String>[];
    }
    for (final id in ids) {
      try {
        final decision = rules.decision(id);
        if (!decision.allowed &&
            !decision.comingSoon &&
            decision.regionRestricted) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
