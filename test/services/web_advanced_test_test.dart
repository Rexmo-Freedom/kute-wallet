// The temporary web override for Advanced (web_advanced_test.dart): on the
// web Advanced is allowed whatever the backend says and leverage is held at
// 1x; the phones and every other capability still follow the policy.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/web_advanced_test.dart';

import '../helpers/runtime_policy_fixture.dart';

void main() {
  tearDown(() => WebAdvancedTest.debugWeb = null);

  test('the phones: Advanced and leverage are the policy\'s', () async {
    final policy = runtimePolicyFixture(
        blocked: {'trading.advanced'}, maxLeverage: 20);
    addTearDown(policy.dispose);
    await policy.refresh(fresh: true);
    expect(WebAdvancedTest.on, isFalse);
    expect(policy.allows('trading.advanced'), isFalse);
    // Leverage is blocked in the app whatever the policy publishes (20x
    // here): the cap is 1x on the phones too (kHlMaxOfferedLeverage).
    expect(policy.maxLeverage, 1);
    expect(policy.offeredLeverage(50), 1);
    await expectLater(
        policy.ensureAllowed('trading.advanced'), throwsA(anything));
  });

  test('the web: Advanced allowed, leverage 1x, the rest still the policy',
      () async {
    WebAdvancedTest.debugWeb = true;
    final policy = runtimePolicyFixture(
        blocked: {'trading.advanced', 'polymarket.trade'}, maxLeverage: 20);
    addTearDown(policy.dispose);
    await policy.refresh(fresh: true);
    expect(policy.allows('trading.advanced'), isTrue);
    expect(policy.maxLeverage, 1);
    expect(policy.offeredLeverage(50), 1);
    await policy.ensureAllowed('trading.advanced');
    // Not a master key: another withheld capability stays withheld.
    expect(policy.allows('polymarket.trade'), isFalse);
    await expectLater(
        policy.ensureAllowed('polymarket.trade'), throwsA(anything));
  });

  test('the web: the check at placement holds when the policy cannot be '
      'fetched (the backend said off, then stops answering)', () async {
    var fail = false;
    final policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        if (fail) return http.Response('down', 503);
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                'trading.advanced': {
                  'allowed': false,
                  'reason': 'disabled',
                  'comingSoon': false
                },
                'hyperliquid.trade': {
                  'allowed': true,
                  'reason': '',
                  'comingSoon': false
                },
              },
              'fees': <String, Object?>{},
              'investing': {'maxLeverage': null},
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.0.4',
    );
    addTearDown(policy.dispose);
    await policy.refresh(fresh: true);
    fail = true;

    // The phones: the held "off" refuses, as before.
    await expectLater(
        policy.ensureAllowed('trading.advanced'), throwsA(anything));

    // The web: still allowed, so an order whose money already moved is not
    // refused for Advanced.
    WebAdvancedTest.debugWeb = true;
    await policy.ensureAllowed('trading.advanced');
  });
}
