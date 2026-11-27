// The temporary web test switch for Advanced (web_advanced_test.dart): on
// only in a browser that opened the link, Advanced allowed there, leverage
// held at 1x, every other capability still the policy's.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/app_router.dart';
import 'package:kute/platform/plain_web_storage.dart';
import 'package:kute/services/web_advanced_test.dart';

import '../helpers/runtime_policy_fixture.dart';

void main() {
  setUp(() {
    PlainWebStorage.debugValues = {};
    WebAdvancedTest.debugWeb = true;
  });
  tearDown(() {
    PlainWebStorage.debugValues = null;
    WebAdvancedTest.debugWeb = null;
  });

  test('off until the link is opened; on, then off again by the link', () {
    expect(WebAdvancedTest.on, isFalse);
    AppRouter.rootReferralRedirect(Uri.parse('/?advanced=on'), locked: true);
    expect(WebAdvancedTest.on, isTrue);
    // A root link without it, or with another value, changes nothing.
    AppRouter.rootReferralRedirect(Uri.parse('/'), locked: true);
    AppRouter.rootReferralRedirect(Uri.parse('/?advanced=yes'), locked: true);
    expect(WebAdvancedTest.on, isTrue);
    AppRouter.rootReferralRedirect(Uri.parse('/?advanced=off'), locked: true);
    expect(WebAdvancedTest.on, isFalse);
  });

  test('never on the phones', () {
    WebAdvancedTest.debugWeb = false;
    PlainWebStorage.debugValues = {WebAdvancedTest.storageKey: 'on'};
    AppRouter.rootReferralRedirect(Uri.parse('/?advanced=on'), locked: true);
    expect(WebAdvancedTest.on, isFalse);
  });

  test('Advanced allowed and leverage 1x while on; the rest is the policy',
      () async {
    final policy = runtimePolicyFixture(
        blocked: {'trading.advanced', 'polymarket.trade'}, maxLeverage: 20);
    addTearDown(policy.dispose);
    await policy.refresh(fresh: true);
    expect(policy.allows('trading.advanced'), isFalse);
    expect(policy.maxLeverage, 20);

    PlainWebStorage.debugValues = {WebAdvancedTest.storageKey: 'on'};
    expect(policy.allows('trading.advanced'), isTrue);
    expect(policy.maxLeverage, 1);
    expect(policy.offeredLeverage(50), 1);
    // Not a master key: another withheld capability stays withheld.
    expect(policy.allows('polymarket.trade'), isFalse);
    await policy.ensureAllowed('trading.advanced');
    await expectLater(policy.ensureAllowed('polymarket.trade'), throwsA(anything));

    PlainWebStorage.debugValues = {WebAdvancedTest.storageKey: 'off'};
    expect(policy.allows('trading.advanced'), isFalse);
    expect(policy.maxLeverage, 20);
  });
}
