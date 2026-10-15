// Region answers follow the network: the native path listener and resume
// (NetworkChangeSignal) drive one round that asks the venues and the Kute
// policy again (RegionFreshness), and every holder of a refusal hears it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/network_change_signal.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settle = Duration(milliseconds: 60);
  late StreamController<Object?> native;
  late NetworkChangeSignal signal;
  late InvestmentProviderAvailability venues;
  late RuntimeCapabilitiesService policy;
  late bool blocked;
  late List<String> triggers;
  late int policyRequests;

  Map<String, dynamic> policyBody() {
    final now = DateTime.now().toUtc();
    return {
      'schemaVersion': 1,
      'revision': 1,
      'evaluatedAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(minutes: 15)).toIso8601String(),
      'capabilities': {
        'polymarket.trade': blocked
            ? {'allowed': false, 'reason': 'country_blocked'}
            : {'allowed': true},
      },
    };
  }

  setUp(() async {
    await RegionFreshness.debugReset();
    native = StreamController<Object?>.broadcast();
    signal = NetworkChangeSignal(
        nativeEvents: () => native.stream,
        debounce: const Duration(milliseconds: 20));
    blocked = true;
    triggers = [];
    policyRequests = 0;
    venues = InvestmentProviderAvailability(
      client: MockClient((_) async =>
          http.Response(jsonEncode({'blocked': blocked}), 200)),
      report: ({
        required String venue,
        required String trigger,
        required bool changed,
        required String result,
      }) =>
          triggers.add(trigger),
    );
    policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        policyRequests++;
        return http.Response(jsonEncode(policyBody()), 200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => 'wallet-a',
      store: MemoryRuntimePolicySnapshotStore(),
    );
  });

  tearDown(() async {
    await RegionFreshness.debugReset();
    await signal.dispose();
    await native.close();
    venues.dispose();
    policy.dispose();
  });

  Future<void> startFreshness() async {
    RegionFreshness.start(signal: signal, providers: venues, policy: policy);
    await Future<void>.delayed(settle);
  }

  test('startup asks Polymarket once for the session', () async {
    await startFreshness();
    expect(triggers, ['startup']);
    expect(venues.cached(InvestmentProvider.polymarket)?.status,
        ProviderAvailabilityStatus.restricted);
  });

  test('resume triggers a re-check', () async {
    await startFreshness();
    blocked = false;
    var rounds = 0;
    void onRound() => rounds++;
    RegionFreshness.answers.addListener(onRound);
    addTearDown(() => RegionFreshness.answers.removeListener(onRound));
    signal.didChangeAppLifecycleState(AppLifecycleState.inactive);
    signal.didChangeAppLifecycleState(AppLifecycleState.hidden);
    signal.didChangeAppLifecycleState(AppLifecycleState.paused);
    signal.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(settle);
    expect(triggers, ['startup', 'resume']);
    expect(venues.cached(InvestmentProvider.polymarket)?.status,
        ProviderAvailabilityStatus.allowed);
    expect(rounds, greaterThanOrEqualTo(1));
  });

  test('a Face ID prompt (inactive only) is not a resume', () async {
    await startFreshness();
    signal.didChangeAppLifecycleState(AppLifecycleState.inactive);
    signal.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(settle);
    expect(triggers, ['startup']);
  });

  test('a blocked answer followed by a network change becomes allowed '
      'everywhere, and a burst is one round', () async {
    await startFreshness();
    expect(await policy.refresh(), isTrue);
    expect(policy.allows('polymarket.trade'), isFalse);
    final requestsBefore = policyRequests;
    blocked = false;
    // The VPN reconnects: three path updates in a row.
    native
      ..add('changed')
      ..add('changed')
      ..add('changed');
    await Future<void>.delayed(settle);
    expect(triggers, ['startup', 'network_change']);
    expect(policyRequests, requestsBefore + 1);
    expect(venues.cached(InvestmentProvider.polymarket)?.status,
        ProviderAvailabilityStatus.allowed);
    expect(policy.allows('polymarket.trade'), isTrue);
    await venues.ensureNewExposure(['polymarket.trade']);
  });

  test('no bridge on this platform: the signal stays quiet and never throws',
      () async {
    final quiet = NetworkChangeSignal(
        nativeEvents: () => Stream<Object?>.error(
            const MissingPluginExceptionLike()),
        debounce: const Duration(milliseconds: 10));
    final seen = <RegionRecheckTrigger>[];
    final sub = quiet.changes.listen(seen.add);
    quiet.start();
    await Future<void>.delayed(settle);
    expect(seen, isEmpty);
    await sub.cancel();
    await quiet.dispose();
  });
}

class MissingPluginExceptionLike implements Exception {
  const MissingPluginExceptionLike();
}
