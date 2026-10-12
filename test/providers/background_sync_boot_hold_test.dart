// The first background sync of the process waits for the boot loads (the
// first balance on screen and the policy), bounded, so its fetch fan-out
// does not compete with them on a weak link. Later syncs never wait.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

void main() {
  late RuntimeCapabilitiesService policy;

  setUp(() {
    AffiliateService.debugSessionToken = 'session';
    policy = runtimePolicyFixture();
    BackgroundSyncNotifier.policyService = () => policy;
    BackgroundSyncNotifier.bootHoldLimit = const Duration(milliseconds: 400);
  });
  tearDown(() {
    policy.dispose();
    AffiliateService.debugSessionToken = null;
    BackgroundSyncNotifier.policyService =
        () => RuntimeCapabilitiesService.instance;
    BackgroundSyncNotifier.bootHoldLimit = const Duration(seconds: 15);
  });

  ProviderContainer container(Completer<BreezSdkSpark> sdk) {
    final c = ProviderContainer(overrides: [
      breezSDKProvider.overrideWith((_) => sdk.future),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('readiness needs both the balance and the policy', () {
    expect(
        BackgroundSyncNotifier.bootInputsReady(
            balanceShown: true, policyLoaded: true),
        isTrue);
    expect(
        BackgroundSyncNotifier.bootInputsReady(
            balanceShown: false, policyLoaded: true),
        isFalse);
    expect(
        BackgroundSyncNotifier.bootInputsReady(
            balanceShown: true, policyLoaded: false),
        isFalse);
  });

  test('the first sync waits for the boot loads, bounded; the next does not',
      () async {
    final sdk = Completer<BreezSdkSpark>();
    final c = container(sdk);
    final notifier = c.read(backgroundSyncNotifierProvider.notifier);
    final clock = Stopwatch()..start();
    await notifier.holdForBoot();
    // Nothing came in: released at the limit, never stuck.
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(350));
    expect(clock.elapsedMilliseconds, lessThan(1500));

    clock.reset();
    await notifier.holdForBoot();
    expect(clock.elapsedMilliseconds, lessThan(50));
  });

  test('with the balance and the policy in, the first sync starts at once',
      () async {
    await policy.refresh();
    expect(policy.snapshot, isNotNull);
    final sdk = Completer<BreezSdkSpark>()
      ..completeError(StateError('no Spark in this test'));
    final c = container(sdk);
    // Let the SDK provider settle (connect failed: the hero card is no
    // longer waiting on it).
    await c.read(breezSDKProvider.future).then((_) {}, onError: (_) {});
    final notifier = c.read(backgroundSyncNotifierProvider.notifier);
    final clock = Stopwatch()..start();
    await notifier.holdForBoot();
    expect(clock.elapsedMilliseconds, lessThan(300));
  });
}
