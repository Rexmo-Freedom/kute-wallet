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

  test('a pull asks the venues and the policy again on the same network',
      () async {
    await startFreshness();
    expect(await policy.refresh(), isTrue);
    expect(policy.allows('polymarket.trade'), isFalse);
    final requestsBefore = policyRequests;
    blocked = false;
    await RegionFreshness.recheck(RegionRecheckTrigger.pull,
        providers: venues, policy: policy);
    expect(triggers, ['startup', 'pull']);
    expect(policyRequests, requestsBefore + 1);
    expect(venues.cached(InvestmentProvider.polymarket)?.status,
        ProviderAvailabilityStatus.allowed);
    expect(policy.allows('polymarket.trade'), isTrue);
  });

  group('"Check connection" (manual)', () {
    test('distrusts the old region denial at once, refetches the policy and '
        'asks both venues live, reported as trigger manual', () async {
      final reports = <Map<String, Object>>[];
      final venuesSeen = InvestmentProviderAvailability(
        client: MockClient((request) async => request.url.host ==
                'api.hyperliquid.xyz'
            ? http.Response(
                jsonEncode({
                  'acceptedTerms': true,
                  'userAllowed': true,
                  'restrictions': 'n',
                }),
                200)
            : http.Response(jsonEncode({'blocked': blocked}), 200)),
        report: ({
          required String venue,
          required String trigger,
          required bool changed,
          required String result,
        }) =>
            reports.add({
              'venue': venue,
              'trigger': trigger,
              'changed': changed,
              'result': result,
            }),
      );
      addTearDown(venuesSeen.dispose);
      // Polymarket refused earlier this session.
      await venuesSeen.check(InvestmentProvider.polymarket);
      expect(await policy.refresh(), isTrue);
      expect(policy.allows('polymarket.trade'), isFalse);
      expect(
          RegionFreshness.regionRefused(
              capabilities: ['polymarket.trade'],
              providers: venuesSeen,
              policy: policy),
          isTrue);

      // The person switched VPN servers (no path change) and taps.
      blocked = false;
      final requestsBefore = policyRequests;
      await RegionFreshness.checkConnection(
          providers: venuesSeen, policy: policy);
      expect(policyRequests, requestsBefore + 1);
      expect(policy.allows('polymarket.trade'), isTrue);
      expect(
          RegionFreshness.regionRefused(
              capabilities: ['polymarket.trade'],
              providers: venuesSeen,
              policy: policy),
          isFalse);
      final manual = reports.where((r) => r['trigger'] == 'manual').toList();
      // Both venues, asked live, whether or not this session asked them.
      expect(manual.map((r) => r['venue']).toSet(),
          {'polymarket', 'hyperliquid'});
      expect(
          manual.firstWhere((r) => r['venue'] == 'polymarket'),
          {
            'venue': 'polymarket',
            'trigger': 'manual',
            'changed': true,
            'result': 'allowed',
          });
      expect(RegionRecheckTrigger.manual.id, 'manual');
    });

    test('still restricted: a fresh denial from this network stands',
        () async {
      expect(await policy.refresh(), isTrue);
      await RegionFreshness.checkConnection(
          providers: venues, policy: policy);
      expect(policy.allows('polymarket.trade'), isFalse);
      expect(
          RegionFreshness.regionRefused(
              capabilities: ['polymarket.trade'],
              providers: venues,
              policy: policy),
          isTrue);
      expect(triggers, contains('manual'));
    });

    test('a round that runs out of time never shows restricted', () async {
      expect(await policy.refresh(), isTrue);
      final hold = Completer<http.Response>();
      var holding = false;
      final slow = RuntimeCapabilitiesService.forTesting(
        client: MockClient((_) => holding
            ? hold.future
            : Future.value(http.Response(jsonEncode(policyBody()), 200))),
        baseUrl: () => 'https://backend.test',
        sessionToken: () => 'wallet-a',
        store: MemoryRuntimePolicySnapshotStore(),
      );
      addTearDown(slow.dispose);
      expect(await slow.refresh(), isTrue);
      expect(slow.allows('polymarket.trade'), isFalse);
      holding = true;
      // The venues cannot be reached either.
      final unreachable = InvestmentProviderAvailability(
          client: MockClient((_) async => http.Response('', 503)));
      addTearDown(unreachable.dispose);
      await RegionFreshness.checkConnection(
          providers: unreachable,
          policy: slow,
          timeout: const Duration(milliseconds: 50));
      // The refetch is still out: the denial from before the tap is not
      // believed meanwhile.
      expect(slow.allows('polymarket.trade'), isTrue);
      expect(
          RegionFreshness.regionRefused(
              capabilities: ['polymarket.trade'],
              providers: unreachable,
              policy: slow),
          isFalse);
      // It lands, still blocked on this network: the denial stands again.
      hold.complete(http.Response(jsonEncode(policyBody()), 200));
      await Future<void>.delayed(settle);
      expect(slow.allows('polymarket.trade'), isFalse);
    });
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
