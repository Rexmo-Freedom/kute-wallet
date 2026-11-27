// The temporary web override for Advanced (web_advanced_test.dart): on the
// web Advanced is allowed whatever the backend says and leverage is held at
// 1x; the phones and every other capability still follow the policy.

import 'package:flutter_test/flutter_test.dart';
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
    expect(policy.maxLeverage, 20);
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
}
