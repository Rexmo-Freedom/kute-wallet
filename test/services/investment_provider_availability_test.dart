import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/investment_provider_availability.dart';

void main() {
  for (final restriction in ['n', 'o', 'u', 'a', 'unknown']) {
    test(
        'Hyperliquid maps official restrictions $restriction independently of account setup',
        () async {
      final service =
          InvestmentProviderAvailability(cacheFor: Duration.zero, client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://api.hyperliquid.xyz/info');
        expect(jsonDecode(request.body), {
          'type': 'legalCheck',
          'user': InvestmentProviderAvailability.hyperliquidLegalCheckAddress,
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
      final service =
          InvestmentProviderAvailability(cacheFor: Duration.zero, client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://polymarket.com/api/geoblock');
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
    final service =
        InvestmentProviderAvailability(cacheFor: Duration.zero, client: MockClient((request) async {
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
}
