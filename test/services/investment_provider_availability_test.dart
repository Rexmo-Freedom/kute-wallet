import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/network_change_signal.dart';

void main() {
  for (final restriction in ['n', 'o', 'u', 'a', 'unknown']) {
    test(
        'Hyperliquid maps official restrictions $restriction independently of account setup',
        () async {
      final service = InvestmentProviderAvailability(
          cacheFor: Duration.zero,
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.toString(), 'https://api.hyperliquid.xyz/info');
            expect(jsonDecode(request.body), {
              'type': 'legalCheck',
              'user':
                  InvestmentProviderAvailability.hyperliquidLegalCheckAddress,
            });
            expect(request.headers.keys.map((key) => key.toLowerCase()),
                isNot(contains('authorization')));
            return http.Response(
                jsonEncode({
                  'acceptedTerms': false,
                  'userAllowed': false,
                  'restrictions': restriction,
                }),
                200);
          }));
      final result = await service.hyperliquid();
      expect(
          result.status,
          restriction == 'a'
              ? ProviderAvailabilityStatus.restricted
              : restriction == 'unknown'
                  ? ProviderAvailabilityStatus.unavailable
                  : ProviderAvailabilityStatus.allowed);
    });
  }

  for (final body in [
    '{}',
    '{"restrictions":"n"}',
    '{"acceptedTerms":true,"userAllowed":true}',
    'not json'
  ]) {
    test('malformed Hyperliquid response is not permission: $body', () async {
      final service = InvestmentProviderAvailability(
          client: MockClient((_) async => http.Response(body, 200)));
      expect((await service.hyperliquid()).status,
          ProviderAvailabilityStatus.unavailable);
    });
  }

  for (final blocked in [true, false]) {
    test('Polymarket direct device verdict: blocked=$blocked', () async {
      final service = InvestmentProviderAvailability(
          cacheFor: Duration.zero,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(
                request.url.toString(), 'https://polymarket.com/api/geoblock');
            return http.Response(jsonEncode({'blocked': blocked}), 200);
          }));
      expect(
          (await service.polymarket()).status,
          blocked
              ? ProviderAvailabilityStatus.restricted
              : ProviderAvailabilityStatus.allowed);
    });
  }

  for (final body in ['{}', '{"blocked":"false"}', 'not json']) {
    test('malformed Polymarket response is not permission: $body', () async {
      final service = InvestmentProviderAvailability(
          client: MockClient((_) async => http.Response(body, 200)));
      expect((await service.polymarket()).status,
          ProviderAvailabilityStatus.unavailable);
    });
  }

  test('provider errors and timeouts are unverified rather than a country ban',
      () async {
    for (final failure in ['status', 'network', 'timeout']) {
      final service = InvestmentProviderAvailability(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) async {
          if (failure == 'status') return http.Response('{}', 503);
          if (failure == 'network') throw http.ClientException('offline');
          return Completer<http.Response>().future;
        }),
      );
      for (final result in [
        await service.hyperliquid(),
        await service.polymarket()
      ]) {
        expect(result.status, ProviderAvailabilityStatus.unavailable);
        expect(result.message, contains('Unable to verify'));
        expect(result.message, isNot(contains('current region')));
        expect(result.ensureAllowed, returnsNormally);
      }
    }
  });

  test(
      'trade and deposit are gated; exits and reads never reuse new-investment gate',
      () async {
    final hosts = <String>[];
    final service = InvestmentProviderAvailability(
        cacheFor: Duration.zero,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response(
              request.url.host == 'api.hyperliquid.xyz'
                  ? '{"acceptedTerms":true,"userAllowed":false,"restrictions":"n"}'
                  : '{"blocked":false}',
              200);
        }));
    for (final capability in ['hyperliquid.trade', 'hyperliquid.deposit']) {
      await service.ensureNewExposure([capability]);
      expect(hosts.removeLast(), 'api.hyperliquid.xyz');
    }
    for (final capability in ['polymarket.trade', 'polymarket.deposit']) {
      await service.ensureNewExposure([capability]);
      expect(hosts.removeLast(), 'polymarket.com');
    }
    await service.ensureNewExposure([
      'hyperliquid.browse',
      'hyperliquid.cancel',
      'hyperliquid.close',
      'hyperliquid.withdraw',
      'polymarket.browse',
      'polymarket.cancel',
      'polymarket.close',
      'polymarket.withdraw',
      'crypto.deposit',
    ]);
    expect(hosts, isEmpty);
    // Venue-to-venue withdrawal checks only the destination's new exposure.
    await service
        .ensureNewExposure(['polymarket.withdraw', 'hyperliquid.deposit']);
    expect(hosts, ['api.hyperliquid.xyz']);
  });

  test('a provider block stops new exposure and names the provider', () async {
    final service = InvestmentProviderAvailability(
        client:
            MockClient((_) async => http.Response('{"blocked":true}', 200)));
    await expectLater(
        service.ensureNewExposure(['polymarket.trade']),
        throwsA(
          isA<ProviderAvailabilityException>().having(
              (error) => error.toString(), 'message', contains('Polymarket')),
        ));
  });

  group('freshness', () {
    late DateTime now;
    late bool blocked;
    late bool offline;
    late int requests;
    late List<Map<String, Object>> reports;

    InvestmentProviderAvailability service() => InvestmentProviderAvailability(
          clock: () => now,
          client: MockClient((request) async {
            requests++;
            if (offline) throw http.ClientException('offline');
            return request.url.host == 'polymarket.com'
                ? http.Response(jsonEncode({'blocked': blocked}), 200)
                : http.Response(
                    jsonEncode({
                      'acceptedTerms': true,
                      'userAllowed': true,
                      'restrictions': blocked ? 'a' : 'n',
                    }),
                    200);
          }),
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

    setUp(() {
      now = DateTime.utc(2026, 10, 15, 12);
      blocked = true;
      offline = false;
      requests = 0;
      reports = [];
    });

    test('a blocked answer followed by a network change becomes allowed',
        () async {
      final venues = service();
      var notified = 0;
      venues.addListener(() => notified++);
      expect((await venues.polymarket()).status,
          ProviderAvailabilityStatus.restricted);
      // Landed somewhere predictions are allowed, or the VPN switched.
      blocked = false;
      await venues.recheck(RegionRecheckTrigger.networkChange);
      expect(venues.cached(InvestmentProvider.polymarket)?.status,
          ProviderAvailabilityStatus.allowed);
      expect(notified, 1, reason: 'screens holding the refusal hear it');
      await venues.ensureNewExposure(['polymarket.trade']);
      expect(requests, 3, reason: 'every gated tap checks live');
      expect(reports[1], {
        'venue': 'polymarket',
        'trigger': 'network_change',
        'changed': true,
        'result': 'allowed',
      });
    });

    test('a network change asks Hyperliquid again too, once it was asked',
        () async {
      final venues = service();
      expect((await venues.hyperliquid()).status,
          ProviderAvailabilityStatus.restricted);
      blocked = false;
      await venues.recheck(RegionRecheckTrigger.networkChange);
      expect(venues.cached(InvestmentProvider.hyperliquid)?.status,
          ProviderAvailabilityStatus.allowed);
      expect(venues.cached(InvestmentProvider.polymarket), isNull,
          reason: 'a venue never asked is not asked on its behalf');
      expect(reports.last['venue'], 'hyperliquid');
      expect(reports.last['changed'], isTrue);
    });

    test('a blocked cache is ignored at tap time when the live check allows',
        () async {
      final venues = service();
      expect((await venues.polymarket()).status,
          ProviderAvailabilityStatus.restricted);
      now = now.add(const Duration(seconds: 10));
      blocked = false;
      // Still within the refusal's minute, but the tap asks live first.
      await venues.ensureNewExposure(['polymarket.trade']);
      expect(requests, 2);
      expect(reports.last['trigger'], 'tap');
      expect(reports.last['changed'], isTrue);
    });

    test('a refusal fetched moments ago is asked again at the tap', () async {
      final venues = service();
      await venues.polymarket();
      await expectLater(venues.ensureNewExposure(['polymarket.trade']),
          throwsA(isA<ProviderAvailabilityException>()));
      expect(requests, 2);
    });

    test('a tap supersedes an earlier check and late denial is discarded',
        () async {
      final old = Completer<http.Response>();
      var calls = 0;
      final venues = InvestmentProviderAvailability(client: MockClient((_) {
        if (++calls == 1) return old.future;
        return Future.value(http.Response('{"blocked":false}', 200));
      }));
      addTearDown(venues.dispose);
      final earlier = venues.polymarket();
      await pumpEventQueue();
      await venues.ensureNewExposure(['polymarket.trade']);
      expect(calls, 2);
      old.complete(http.Response('{"blocked":true}', 200));
      await earlier;
      expect(venues.cached(InvestmentProvider.polymarket)?.status,
          ProviderAvailabilityStatus.allowed);
    });

    test('a restricted answer lives a minute, an allowed one five', () async {
      final venues = service();
      await venues.polymarket();
      now = now.add(const Duration(seconds: 61));
      expect(venues.cached(InvestmentProvider.polymarket), isNull);
      blocked = false;
      await venues.polymarket();
      now = now.add(const Duration(minutes: 4));
      expect(venues.cached(InvestmentProvider.polymarket)?.status,
          ProviderAvailabilityStatus.allowed);
    });

    test('a failed check never shows restricted', () async {
      final venues = service();
      await venues.polymarket();
      now = now.add(const Duration(seconds: 10));
      offline = true;
      // The live re-ask at the tap fails: unknown, so the bet goes on.
      await venues.ensureNewExposure(['polymarket.trade']);
      // And the old refusal is gone, not held for the rest of its minute.
      expect(venues.cached(InvestmentProvider.polymarket), isNull);
      await venues.ensureNewExposure(['polymarket.trade']);
      expect(reports.last['result'], 'unknown');
      // A network change with nothing reachable: still never restricted.
      await venues.recheck(RegionRecheckTrigger.networkChange);
      await venues.ensureNewExposure(['polymarket.trade']);
    });

    test('resume drops a refusal and asks again; an allowed answer stays',
        () async {
      final venues = service();
      await venues.polymarket();
      blocked = false;
      await venues.recheck(RegionRecheckTrigger.resume);
      expect(requests, 2);
      expect(reports.last['trigger'], 'resume');
      expect(venues.cached(InvestmentProvider.polymarket)?.status,
          ProviderAvailabilityStatus.allowed);
    });
  });
}
