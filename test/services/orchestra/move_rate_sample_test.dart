import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/orchestra/move_rate_sample.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

void main() {
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  MoveRateSample withdrawal({required bool investing, bool ledger = false}) =>
      moveRateSample(
          ledger: ledger,
          venueSource: true,
          fromHyperliquid: investing,
          investing: investing,
          buyingDollars: false);

  MoveRateSample deposit({required bool investing}) => moveRateSample(
      ledger: false,
      venueSource: false,
      fromHyperliquid: false,
      investing: investing,
      buyingDollars: false);

  List<String> caps(MoveRateSample s) => orchestraCapabilityRequirements(
      sourceChain: s.sourceChain,
      sourceAsset: s.sourceAsset,
      destinationChain: s.destinationChain,
      destinationAsset: s.destinationAsset);

  test('a venue withdrawal samples the exit leg, gated on withdraw alone', () {
    expect(caps(withdrawal(investing: true)), ['hyperliquid.withdraw']);
    expect(caps(withdrawal(investing: false)), ['polymarket.withdraw']);
    expect(caps(withdrawal(investing: true, ledger: true)),
        ['hyperliquid.withdraw']);
    expect(caps(deposit(investing: true)), ['hyperliquid.deposit']);
    expect(caps(deposit(investing: false)), ['polymarket.deposit']);
  });

  test('a GB policy blocking venue trade and deposit still prices a withdrawal',
      () async {
    // The UK: Investing (UK group) and Predictions (POLYMARKET_RESTRICTED)
    // refuse new trades and deposits; exits stay open everywhere.
    final uk = runtimePolicyFixture(blocked: {
      'hyperliquid.trade',
      'hyperliquid.deposit',
      'polymarket.trade',
      'polymarket.deposit',
    });
    addTearDown(uk.dispose);
    expect(await uk.refresh(), isTrue);

    await uk.ensureAllAllowed(caps(withdrawal(investing: true)));
    await uk.ensureAllAllowed(caps(withdrawal(investing: false)));
    await expectLater(uk.ensureAllAllowed(caps(deposit(investing: true))),
        throwsA(isA<CapabilityUnavailableException>()));
    await expectLater(uk.ensureAllAllowed(caps(deposit(investing: false))),
        throwsA(isA<CapabilityUnavailableException>()));
  });

  test('both directions read dollars per bitcoin', () {
    // 100 000 sats in, 100 dollars out: 100 000 dollars per bitcoin.
    final forward = deposit(investing: false);
    expect(forward.amount, '100000');
    expect(forward.usdPerBtc('100000000'), closeTo(100000, 0.01));
    // 100 dollars in, 100 000 sats out: the same price.
    final reverse = withdrawal(investing: false);
    expect(int.parse(reverse.amount), greaterThan(0));
    expect(reverse.usdPerBtc('100000'), closeTo(100000, 0.01));
    expect(reverse.usdPerBtc('0'), isNull);
  });
}
