import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/investment_provider_availability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = DateTime.utc(2026, 9, 22, 12);
  late DateTime now;
  late String? session;
  late RuntimeCapabilitiesService service;

  Map<String, dynamic> policy(
          {int revision = 1, bool trade = true, bool comingSoon = false}) =>
      {
        'schemaVersion': 1,
        'revision': revision,
        'evaluatedAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
        'capabilities': {
          'hyperliquid.trade': {
            'allowed': trade,
            'reason': trade ? '' : 'country_blocked'
          },
          'hyperliquid.close': {'allowed': true},
          'hyperliquid.withdraw': {'allowed': true},
          'onramp.bank': {'allowed': true, 'comingSoon': comingSoon},
        },
        'fees': {
          'fiat_deposit': {'bps': 100, 'mode': 'fixed'}
        },
        'ai': {'dailyLimit': 5, 'remaining': 3},
        'security': {'smallActionAllowanceCents': 250},
      };

  void setup(FutureOr<http.Response> Function(http.Request) respond) {
    service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async => respond(request)),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => session,
      clock: () => now,
      appVersion: () async => '2.0.4',
    );
  }

  setUp(() {
    now = origin;
    session = 'wallet-a';
  });
  tearDown(() => service.dispose());

  test('authenticated device context and bounded public fee metadata',
      () async {
    setup((request) {
      expect(request.url.path, '/api/v1/config/capabilities');
      expect(request.url.queryParameters,
          {'platform': 'ios', 'appVersion': '2.0.4'});
      expect(request.headers['Authorization'], 'Bearer wallet-a');
      return http.Response(jsonEncode(policy()), 200);
    });
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.trade'), isTrue);
    expect(service.snapshot!.ai['dailyLimit'], 5);
    expect(service.snapshot!.fees['fiat_deposit']['bps'], 100);
    expect(service.snapshot!.smallActionAllowanceCents, 250);
    now = now.add(const Duration(minutes: 6));
    expect(service.snapshot, isNull);
    // A stale policy is no policy: new exposure waits for a fresh one.
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.allows('hyperliquid.close'), isTrue);
  });

  test('sends the device id and surfaces the reason beside the control',
      () async {
    late http.Request seen;
    service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        seen = request;
        final body = policy();
        body['capabilities'] = <String, dynamic>{
          ...body['capabilities'] as Map,
          'trading.advanced': {
            'allowed': false,
            'reason': 'affiliate_not_allowed',
            'message': 'Advanced trading is in closed beta.',
          },
          'onramp.cashapp': {'allowed': false, 'reason': 'app_update_required'},
          'hardware.wallet': {'allowed': false, 'reason': 'device_blocked'},
          'polymarket.close': {'allowed': false, 'reason': 'wallet_blocked'},
        };
        return http.Response(jsonEncode(body), 200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => session,
      clock: () => now,
      appVersion: () async => '2.0.4',
    );
    expect(await service.refresh(), isTrue);
    expect(seen.headers['X-Kute-App-Version'], '2.0.4');
    expect(seen.url.queryParameters['appVersion'], '2.0.4');
    // The operator's sentence wins; reason codes get Kute's wording.
    expect(service.blockReason('trading.advanced'),
        'Advanced trading is in closed beta.');
    expect(service.blockReason('onramp.cashapp'), contains('Update Kute'));
    expect(service.blockReason('hardware.wallet'), contains('this device'));
    expect(service.blockReason('polymarket.close'), contains('your account'));
    expect(service.blockReason('hyperliquid.close'), isNull);
    expect(service.allows('trading.advanced'), isFalse);
  });

  test('the capabilities request never carries the install id', () async {
    late http.Request seen;
    setup((request) {
      seen = request;
      return http.Response(jsonEncode(policy()), 200);
    });
    expect(await service.refresh(), isTrue);
    expect(seen.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('x-kute-device-id')));
    expect(
        seen.headers.keys.where((k) => k.toLowerCase().contains('device')),
        isEmpty);
    expect(
        seen.url.queryParameters.keys
            .where((k) => k.toLowerCase().contains('device')),
        isEmpty);
    expect((await service.requestContextHeaders()).keys,
        unorderedEquals(['X-Kute-Platform', 'X-Kute-App-Version']));
  });

  test('a policy outage denies new investing exposure but keeps browsing',
      () async {
    var online = true;
    setup((_) =>
        http.Response(online ? jsonEncode(policy()) : '', online ? 200 : 503));
    await service.refresh();
    expect(service.allows('hyperliquid.trade'), isTrue);
    online = false;
    // The held policy is still fresh, so its answer stands for display...
    expect(service.allows('hyperliquid.trade'), isTrue);
    // ...but execution refetches, and with no policy trading is refused.
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'policy_unavailable')));
    await expectLater(
        service.ensureAllowed('onramp.bank'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'policy_unavailable')));
    await service.ensureAllowed('hyperliquid.withdraw');
    now = now.add(const Duration(minutes: 6));
    expect(service.allows('hyperliquid.trade'), isFalse);
    expect(service.allows('hyperliquid.browse'), isTrue);
  });

  const exits = [
    'hyperliquid.cancel',
    'hyperliquid.close',
    'hyperliquid.withdraw',
    'polymarket.cancel',
    'polymarket.close',
    'polymarket.withdraw',
  ];

  test('policy outage never blocks cancelling, closing or withdrawing',
      () async {
    setup((_) => http.Response('', 503));
    expect(await service.refresh(), isFalse);
    for (final id in exits) {
      expect(service.allows(id), isTrue, reason: id);
      expect(service.blockReason(id), isNull, reason: id);
      await service.ensureAllowed(id);
    }
    await service.ensureAllAllowed(exits);
    await service.ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
    await service.ensureAnyAllowed(['onramp.bank', 'polymarket.withdraw']);
  });

  test('the offline table is exactly what an outage allows', () async {
    setup((_) => http.Response('', 503));
    expect(await service.refresh(), isFalse);
    expect(kOfflineAllowedCapabilities, {
      'hyperliquid.browse',
      'polymarket.browse',
      'settings.advanced',
      'export.transactions',
      ...exits,
    });
    for (final id in kOfflineAllowedCapabilities) {
      expect(service.allows(id), isTrue, reason: id);
      expect(service.decision(id).reason, 'policy_unavailable', reason: id);
      await service.ensureAllowed(id);
    }
    for (final id in [
      // New Investing and Predictions exposure and funding.
      'hyperliquid.trade',
      'hyperliquid.deposit',
      'polymarket.trade',
      'polymarket.deposit',
      'trading.advanced',
      'hyperliquid.stocks',
      'polymarket.sports',
      'polymarket.politics',
      // Naming Kute as the Hyperliquid referrer.
      'hyperliquid.referrer',
      // Orchestra swaps and deposit addresses.
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins',
      'crypto.deposit',
      // One-time quoted receive addresses: an outage leaves only the
      // reusable receive options.
      'orchestra.onetime_addresses',
      // Investing and Predictions on a hardware wallet.
      'ledger.hyperliquid',
      'ledger.polymarket',
      // Adding any wallet beyond the spending account.
      'hardware.wallet',
      'wallet.savings',
      'wallet.tracked',
      // Onramps, Earn, referral, Sal.
      'onramp.bank',
      'onramp.cashapp',
      'usd.earn',
      'affiliate.program',
      'ai.ask',
      // Anything the table does not name.
      'hyperliquid.unknown',
      'polymarket.unknown',
    ]) {
      expect(service.allows(id), isFalse, reason: id);
      expect(service.blockReason(id), contains('Unable to check'), reason: id);
      await expectLater(
          service.ensureAllowed(id),
          throwsA(isA<CapabilityUnavailableException>().having(
              (e) => e.decision.reason, 'reason', 'policy_unavailable')),
          reason: id);
    }
    await expectLater(
        service.ensureAllAllowed(['hyperliquid.close', 'trading.advanced']),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.capability, 'capability', 'trading.advanced')));
    await expectLater(
        service.ensureAnyAllowed(['hyperliquid.trade', 'polymarket.deposit']),
        throwsA(isA<CapabilityUnavailableException>()));
  });

  test('a hardware-wallet denial seen this session survives an outage',
      () async {
    var online = true;
    setup((_) {
      final value = policy();
      (value['capabilities'] as Map)['hardware.wallet'] = {
        'allowed': false,
        'reason': 'device_blocked'
      };
      return http.Response(online ? jsonEncode(value) : '', online ? 200 : 503);
    });
    expect(await service.refresh(), isTrue);
    online = false;
    now = now.add(const Duration(minutes: 6));
    await expectLater(
        service.ensureAllowed('hardware.wallet'),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.decision.reason, 'reason', 'device_blocked')));
  });

  test('an explicit exit denial from a loaded policy survives an outage',
      () async {
    var online = true;
    setup((_) {
      final value = policy();
      final capabilities = value['capabilities'] as Map;
      for (final id in exits) {
        capabilities[id] = {'allowed': false, 'reason': 'disabled'};
      }
      return http.Response(online ? jsonEncode(value) : '', online ? 200 : 503);
    });
    expect(await service.refresh(), isTrue);
    for (final id in exits) {
      expect(service.allows(id), isFalse, reason: id);
    }
    online = false;
    for (final at in [Duration.zero, const Duration(minutes: 6)]) {
      now = origin.add(at);
      for (final id in exits) {
        expect(service.allows(id), isFalse, reason: '$id +$at');
        await expectLater(
            service.ensureAllowed(id),
            throwsA(isA<CapabilityUnavailableException>()
                .having((e) => e.decision.reason, 'reason', 'disabled')),
            reason: '$id +$at');
      }
    }
  });

  for (final reason in ['country_blocked', 'disabled', 'app_update_required']) {
    test('policy outage preserves previously observed $reason', () async {
      var online = true;
      setup((_) {
        final value = policy(trade: false);
        (value['capabilities'] as Map)['hyperliquid.trade']['reason'] = reason;
        return http.Response(
            online ? jsonEncode(value) : '', online ? 200 : 503);
      });
      await service.refresh();
      online = false;
      now = now.add(const Duration(minutes: 6));
      await expectLater(
          service.ensureAllowed('hyperliquid.trade'),
          throwsA(isA<CapabilityUnavailableException>()
              .having((error) => error.decision.reason, 'reason', reason)));
    });
  }

  test('unknown location passes while a missing capability stays disabled',
      () async {
    setup((_) {
      final value = policy(trade: false);
      (value['capabilities'] as Map)['hyperliquid.trade']['reason'] =
          'country_unknown';
      return http.Response(jsonEncode(value), 200);
    });
    await service.ensureAllowed('hyperliquid.trade');
    await expectLater(
        service.ensureAllowed('polymarket.trade'),
        throwsA(isA<CapabilityUnavailableException>().having(
            (error) => error.decision.reason, 'reason', 'unknown_capability')));
  });

  test('navigation scopes observe updates without disposing the app service',
      () async {
    var revision = 1;
    setup((_) => http.Response(jsonEncode(policy(revision: revision)), 200));
    RuntimeCapabilitiesService.debugInstance = service;
    addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
    final first = ProviderContainer();
    final revisions = <int?>[];
    first.listen(
        runtimeCapabilitiesProvider.select((p) => p.snapshot?.revision),
        (_, value) => revisions.add(value));
    await service.refresh();
    expect(revisions, [1]);
    first.dispose();
    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.listen(
        runtimeCapabilitiesProvider.select((p) => p.snapshot?.revision),
        (_, value) => revisions.add(value));
    revision = 2;
    await service.refresh();
    expect(revisions, [1, 2]);
    expect(second.read(runtimeCapabilitiesProvider).allows('hyperliquid.trade'),
        isTrue);
  });

  test('country block preserves separately permitted close and withdrawal',
      () async {
    setup((_) => http.Response(jsonEncode(policy(trade: false)), 200));
    await expectLater(service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<CapabilityUnavailableException>()));
    await service.ensureAllowed('hyperliquid.close');
    await service.ensureAllowed('hyperliquid.withdraw');
    await service.ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
  });

  test(
      'provider check precedes fresh Kute policy; either may independently deny',
      () async {
    final calls = <String>[];
    var providerAllowed = true;
    var kuteAllowed = false;
    final provider = InvestmentProviderAvailability(
        cacheFor: Duration.zero,
        client: MockClient((request) async {
          calls.add('provider');
          return http.Response(
              jsonEncode({
                'acceptedTerms': true,
                'userAllowed': false,
                'restrictions': providerAllowed ? 'u' : 'a',
              }),
              200);
        }));
    service = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        calls.add('kute');
        return http.Response(jsonEncode(policy(trade: kuteAllowed)), 200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => session,
      clock: () => now,
      ensureProviderAvailability: provider.ensureNewExposure,
    );
    await expectLater(
        service.ensureAllowed('hyperliquid.trade'),
        throwsA(
          // Kute's own policy denial, not the provider's (which names the
          // provider): the generic feature wording, with no provider name.
          isA<CapabilityUnavailableException>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('This feature is restricted'),
                  isNot(contains('Hyperliquid')))),
        ));
    expect(calls, ['provider', 'kute']);
    calls.clear();
    providerAllowed = false;
    kuteAllowed = true;
    await expectLater(service.ensureAllowed('hyperliquid.trade'),
        throwsA(isA<ProviderAvailabilityException>()));
    expect(calls, ['provider']);
    calls.clear();
    await service.ensureAllowed('hyperliquid.close');
    await service.ensureAllowed('hyperliquid.withdraw');
    await service.ensureAnyAllowed(['hyperliquid.trade', 'hyperliquid.close']);
    expect(calls, ['kute', 'kute', 'kute']);
    calls.clear();
    providerAllowed = true;
    await service.ensureAllowed('hyperliquid.trade');
    await service.ensureAllowed('hyperliquid.trade');
    expect(calls, ['provider', 'kute', 'provider', 'kute']);
  });

  test('unknown capabilities and coming-soon rails cannot start operations',
      () async {
    setup((_) => http.Response(jsonEncode(policy(comingSoon: true)), 200));
    await expectLater(service.ensureAllowed('missing'),
        throwsA(isA<CapabilityUnavailableException>()));
    await expectLater(service.ensureAllowed('onramp.bank'),
        throwsA(isA<CapabilityUnavailableException>()));
  });

  test('wallet changes invalidate cached policy and discard in-flight response',
      () async {
    final response = Completer<http.Response>();
    setup((_) => response.future);
    final request = service.refresh();
    await Future<void>.delayed(Duration.zero);
    session = 'wallet-b';
    response.complete(http.Response(jsonEncode(policy()), 200));
    expect(await request, isFalse);
    expect(service.snapshot, isNull);
  });

  test('no session does not make an unauthenticated request', () async {
    setup((_) => throw StateError('must not fetch'));
    session = null;
    expect(await service.refresh(), isFalse);
    // Without a session the policy is unavailable, so the offline table
    // decides (see 'the offline table is exactly what an outage allows').
    // Neither path fetches without a session.
    for (final id in ['onramp.bank', 'hyperliquid.trade']) {
      await expectLater(
          service.ensureAllowed(id),
          throwsA(isA<CapabilityUnavailableException>().having(
              (e) => e.decision.reason, 'reason', 'policy_unavailable')),
          reason: id);
    }
    await service.ensureAllowed('hyperliquid.withdraw');
  });

  test('revision rollback is rejected without dropping the latest display',
      () async {
    var revision = 4;
    setup((_) => http.Response(jsonEncode(policy(revision: revision)), 200));
    await service.refresh();
    revision = 3;
    expect(await service.refresh(), isFalse);
    expect(service.snapshot!.revision, 4);
  });

  test('one fresh request checks multiple requirements', () async {
    var calls = 0;
    setup((_) {
      calls++;
      return http.Response(jsonEncode(policy()), 200);
    });
    await service.ensureAllAllowed(['hyperliquid.trade', 'hyperliquid.close']);
    expect(calls, 1);
  });

  test('a re-check within maxAge reads the policy it just fetched', () async {
    var calls = 0;
    setup((_) {
      calls++;
      return http.Response(jsonEncode(policy()), 200);
    });
    await service.ensureAllowed('hyperliquid.trade');
    expect(calls, 1);
    // Moments later, the same gate may read the held policy.
    await service.ensureAllowed('hyperliquid.trade',
        maxAge: const Duration(seconds: 60));
    expect(calls, 1);
    // Without a reuse window it asks again, as before.
    await service.ensureAllowed('hyperliquid.trade');
    expect(calls, 2);
    // A window shorter than the policy's age asks again too.
    await service.ensureAllowed('hyperliquid.trade', maxAge: Duration.zero);
    expect(calls, 3);
  });

  test('malformed or expired policy cannot allow an operation', () async {
    setup((_) =>
        http.Response(jsonEncode({...policy(), 'schemaVersion': 2}), 200));
    expect(await service.refresh(), isFalse);
    expect(service.snapshot, isNull);
  });

  test('the leverage cap is read from the snapshot for this region', () async {
    Map<String, dynamic> withInvesting(Object? cap, {bool present = true}) => {
          ...policy(),
          if (present) 'investing': {'maxLeverage': cap},
        };
    setup((_) => http.Response(jsonEncode(withInvesting(null)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, isNull, reason: 'null means the venue max');
    expect(service.offeredLeverage(40), 40);
    service.ensureLeverageAllowed(40);
    service.dispose();

    setup((_) => http.Response(jsonEncode(withInvesting(2)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 2);
    expect(service.offeredLeverage(40), 2);
    expect(service.offeredLeverage(1), 1);
    service.ensureLeverageAllowed(2);
    expect(
        () => service.ensureLeverageAllowed(3),
        throwsA(isA<LeverageCapExceededException>()
            .having((e) => e.maxLeverage, 'cap', 2)));
    expect(const LeverageCapExceededException(2).toString(), contains('2x'));
    service.dispose();

    // A snapshot that says nothing about leverage is read as the most
    // conservative cap, never as no cap.
    setup((_) =>
        http.Response(jsonEncode(withInvesting(null, present: false)), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 1);
    service.dispose();

    setup((_) => http.Response(jsonEncode(withInvesting('x')), 200));
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 1, reason: 'malformed reads as 1x');
  });

  test('an outage can only tighten the leverage cap', () async {
    var fail = false;
    setup((_) => fail
        ? http.Response('down', 503)
        : http.Response(
            jsonEncode({
              ...policy(),
              'investing': {'maxLeverage': 5},
            }),
            200));
    // Never fetched: 1x.
    expect(service.maxLeverage, 1);
    expect(service.offeredLeverage(40), 1);
    expect(await service.refresh(), isTrue);
    expect(service.maxLeverage, 5);
    // Expired and unreachable: the last cap seen for this session holds.
    now = now.add(const Duration(minutes: 6));
    fail = true;
    expect(await service.refresh(), isFalse);
    expect(service.snapshot, isNull);
    expect(service.maxLeverage, 5);
    // Another session inherits nothing: back to 1x.
    session = 'wallet-b';
    expect(service.maxLeverage, 1);
  });

  test('the jurisdiction gates fail closed while exits stay open', () async {
    setup((_) => http.Response('down', 503));
    expect(await service.refresh(), isFalse);
    for (final gate in [
      'hyperliquid.stocks',
      'hyperliquid.referrer',
      'polymarket.sports',
      'polymarket.politics',
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins',
    ]) {
      expect(service.allows(gate), isFalse, reason: gate);
      expect(service.decision(gate).reason, 'policy_unavailable');
      expect(service.blockReason(gate), contains('Unable to check'));
    }
    for (final exit in [
      'hyperliquid.close',
      'hyperliquid.cancel',
      'hyperliquid.withdraw',
      'polymarket.close',
      'polymarket.cancel',
      'polymarket.withdraw',
    ]) {
      expect(service.allows(exit), isTrue, reason: exit);
    }
    // And with a policy loaded that names a gate, its answer is used as is.
    service.dispose();
    setup((_) => http.Response(
        jsonEncode({
          ...policy(),
          'capabilities': {
            ...policy()['capabilities'] as Map<String, dynamic>,
            'hyperliquid.stocks': {
              'allowed': false,
              'reason': 'country_blocked'
            },
            'hyperliquid.referrer': {
              'allowed': false,
              'reason': 'country_blocked'
            },
            'polymarket.sports': {'allowed': true, 'reason': 'allowed'},
            'polymarket.politics': {
              'allowed': false,
              'reason': 'country_unknown'
            },
          },
        }),
        200));
    expect(await service.refresh(), isTrue);
    expect(service.allows('hyperliquid.stocks'), isFalse);
    expect(service.decision('hyperliquid.stocks').regionRestricted, isTrue);
    expect(service.allows('hyperliquid.referrer'), isFalse);
    expect(service.allows('polymarket.sports'), isTrue);
    expect(service.allows('polymarket.politics'), isFalse,
        reason: 'an unknown country is not advisory for a narrow gate');
  });
}
