// Orchestra under a region block (backend f9bab95, 27 October 2026):
//   * bitcoin to bitcoin (bitcoin, Lightning or Spark on both legs, no
//     dollars) is plain bitcoin: the backend ignores country rules on
//     `orchestra.swap` for it, and so does the app. Only the master
//     switched off for everyone stops it;
//   * every Orchestra call carries X-Kute-Platform and X-Kute-App-Version,
//     the values the capabilities fetch sends, so the backend evaluates
//     the same platform rules on both.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

final _quoteBody = jsonEncode({
  'quoteId': 'q_1',
  'depositAddress': 'deposit',
  'amountIn': '10000',
  'estimatedOut': '9900',
  'feeAmount': '0',
  'feeBps': 0,
  'expiresAt': '2026-10-27T12:02:00Z',
});

Future<RuntimeCapabilitiesService> _policy(String swapReason) async {
  final policy = runtimePolicyFixture(
      blocked: {'orchestra.swap'}, reasons: {'orchestra.swap': swapReason});
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await policy.refresh(), isTrue);
  return policy;
}

List<String> _needs(String from, String fromAsset, String to, String toAsset,
        RuntimeCapabilitiesService policy) =>
    orchestraCapabilityRequirements(
        sourceChain: from,
        sourceAsset: fromAsset,
        destinationChain: to,
        destinationAsset: toAsset,
        policy: policy);

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
  });
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  group('bitcoin to bitcoin is exempt from a country block on swaps', () {
    test('a country refusal of orchestra.swap asks nothing of BTC to BTC',
        () async {
      for (final reason in ['country_blocked', 'country_not_allowed']) {
        final policy = await _policy(reason);
        for (final (from, to) in [
          ('spark', 'lightning'),
          ('spark', 'bitcoin'),
          ('lightning', 'spark'),
          ('bitcoin', 'spark'),
        ]) {
          expect(orchestraBitcoinOnlyRoute(
                  sourceChain: from,
                  sourceAsset: 'BTC',
                  destinationChain: to,
                  destinationAsset: 'BTC'),
              isTrue);
          expect(_needs(from, 'BTC', to, 'BTC', policy), isEmpty,
              reason: '$reason $from→$to');
        }
        // Dollars and other coins still answer to the swap gates.
        expect(_needs('spark', 'BTC', 'spark', 'USDB', policy),
            ['orchestra.swap']);
        expect(_needs('ethereum', 'USDT', 'spark', 'BTC', policy),
            ['orchestra.swap', 'orchestra.swap.stablecoins']);
        policy.dispose();
        RuntimeCapabilitiesService.debugInstance = null;
      }
    });

    test('the master switched off for everyone still stops BTC to BTC',
        () async {
      final policy = await _policy('disabled');
      expect(_needs('spark', 'BTC', 'lightning', 'BTC', policy),
          ['orchestra.swap']);
    });

    test('allowed: BTC to BTC answers to the master as before', () async {
      final policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
      await policy.refresh();
      expect(_needs('spark', 'BTC', 'lightning', 'BTC', policy),
          ['orchestra.swap']);
    });
  });

  group('quotes', () {
    late List<http.BaseRequest> sent;
    MockClient backend() => MockClient((request) async {
          sent.add(request);
          return http.Response(_quoteBody, 200);
        });
    setUp(() => sent = []);

    Future<dynamic> quote(String to, String toAsset) => http.runWithClient(
        () => OrchestraService.createQuote(
              sourceChain: 'spark',
              sourceAsset: 'BTC',
              destinationChain: to,
              destinationAsset: toAsset,
              amount: '10000',
              recipientAddress: 'recipient',
              refundAddress: 'refund',
            ),
        backend);

    test(
        'under a country block a BTC to BTC quote goes out, with the '
        'platform and app version headers', () async {
      await _policy('country_blocked');
      final result = await quote('lightning', 'BTC');
      expect(result.data, isNotNull);
      final request = sent.single;
      expect(request.url.path, '/api/v1/orchestra/quote');
      expect(request.headers['X-Kute-Platform'], 'ios');
      expect(request.headers['X-Kute-App-Version'], '2.0.4');
      expect(request.headers['Authorization'], 'Bearer test-session');
    });

    test('a quote into Dollars is refused before any request, with the '
        'region decision', () async {
      await _policy('country_blocked');
      final result = await quote('spark', 'USDB');
      expect(result.data, isNull);
      expect(sent, isEmpty);
      expect(
          result.cause,
          isA<CapabilityUnavailableException>()
              .having((e) => e.capability, 'capability', 'orchestra.swap')
              .having((e) => e.decision.regionRestricted, 'region', isTrue));
    });

    test('route limits from the backend carry the same headers', () async {
      await _policy('country_blocked');
      await OrchestraService.getRouteLimits(
          RouteKey(
              fromChain: 'spark',
              fromAsset: 'BTC',
              toChain: 'lightning',
              toAsset: 'BTC'),
          client: MockClient((request) async {
            sent.add(request);
            return http.Response('{}', 404);
          }));
      final limits = sent.firstWhere(
          (r) => r.url.host == 'backend.test' && r.url.path.endsWith('/limits'));
      expect(limits.headers['X-Kute-Platform'], 'ios');
      expect(limits.headers['X-Kute-App-Version'], '2.0.4');
    });
  });
}
