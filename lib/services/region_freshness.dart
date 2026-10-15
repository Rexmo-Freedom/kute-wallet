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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/network_change_signal.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

abstract final class RegionFreshness {
  static StreamSubscription<RegionRecheckTrigger>? _subscription;
  static final ValueNotifier<int> _rounds = ValueNotifier<int>(0);

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
    final venues = providers ?? InvestmentProviderAvailability.instance;
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
  /// [answers] notifies. Never throws.
  static Future<void> recheck(
    RegionRecheckTrigger trigger, {
    InvestmentProviderAvailability? providers,
    RuntimeCapabilitiesService? policy,
  }) async {
    final venues = providers ?? InvestmentProviderAvailability.instance;
    final capabilities = policy ?? RuntimeCapabilitiesService.instance;
    try {
      await Future.wait([
        venues.recheck(trigger),
        if (trigger == RegionRecheckTrigger.networkChange)
          capabilities.networkChanged().then<void>((_) {}),
      ]);
    } catch (_) {
      // A round that could not finish leaves the tap-time re-check.
    }
    _rounds.value++;
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
