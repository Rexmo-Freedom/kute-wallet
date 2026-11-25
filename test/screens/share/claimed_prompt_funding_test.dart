// "Send now" funding a short Dollars (claimed_prompt_sheet.dart,
// one_balance/gift_funding.dart), as the person sees it. Dollars enough: the
// sheet as it always was. Short: the leg in the steps' words and its fee in
// the slips' row before the tap, the money's steps while it runs, "Sent" at
// the end. Stopped: "Could not send. Kute will ask again next time it opens."
// and the steps showing where the money is. Swap refused: the policy's own
// words. Fakes only. The states are drawn in
// test/render/gift_send_now_render_test.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/share/claimed_prompt_sheet.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show spendingBitcoinLandingUsdProvider;
import 'package:kute/services/one_balance/gift_funding.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show venueCashClosedProvider;
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService, runtimeCapabilitiesProvider;
import 'package:kute/services/share_links_store.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/runtime_policy_fixture.dart';
import 'gift_funding_sheet_harness.dart';
import 'share_test_harness.dart';

const _bitcoinLine = r'Moving $15.00 from Bitcoin → Dollars';
const _failed = 'Could not send. Kute will ask again next time it opens.';

void main() {
  late ShareTestEnv env;
  late GiftSheetWallet wallet;

  setUp(() async {
    final open = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = open;
    await open.refresh();
    env = setUpShareTest();
    GiftFundingRunner.debugReset();
    wallet = GiftSheetWallet();
    ClaimedPromptSheet.debugPayer = wallet.pay;
    AuthGrants.clock = DateTime.now;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    ClaimedPromptSheet.debugPayer = null;
    tearDownShareTest();
  });

  Future<void> pump(WidgetTester tester,
      {double dollars = 5, double bitcoin = 40}) async {
    await pumpShareWidget(
      tester,
      env,
      ClaimedPromptSheet(claim: giftSheetClaim(amountMinor: 2000)),
      dollars: dollars,
      overrides: [
        settingsProvider
            .overrideWith((ref) => SettingsModel(giftSheetSettings)),
        spendingBitcoinLandingUsdProvider.overrideWith((ref) => bitcoin),
        aiEnabledProvider.overrideWith((ref) async => false),
        ...wallet.overrides(),
      ],
    );
  }

  testWidgets('Dollars enough: the sheet as it always was', (tester) async {
    wallet.dollars = 50;
    await pump(tester, dollars: 50);
    expect(find.byKey(const ValueKey('share-claimed-funding')), findsNothing);
    expect(find.byKey(const ValueKey('share-claimed-steps')), findsNothing);
    expect(find.text('Move fee'), findsNothing);
    expect(kuteBarPrimaryWithText('Send now'), findsOneWidget);
    await tester.tap(kuteBarPrimary);
    await settle(tester);
    expect(wallet.legs, 0);
    expect(find.text('Sent'), findsOneWidget);
    expect(ShareLinksStore.byId('lnk_gift')?.paymentId, 'pay_1');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
  });

  testWidgets(
      'short, Bitcoin covers it: the leg and its fee before the tap, '
      'the steps while it runs, Sent at the end', (tester) async {
    wallet.landing = Completer<void>();
    await pump(tester);
    expect(find.text(_bitcoinLine), findsOneWidget);
    expect(find.byKey(const ValueKey('share-claimed-fee')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-claimed-steps')), findsNothing);
    expect(kuteBarPrimaryEnabled(tester), isTrue);

    await tester.tap(kuteBarPrimary);
    await settle(tester);
    expect(find.byKey(const ValueKey('share-claimed-steps')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-claimed-funding')), findsNothing);
    expect(find.text(_bitcoinLine), findsOneWidget);
    expect(kuteBarPrimaryProbe(tester).isLoading, isTrue);
    expect(find.text('Later'), findsOneWidget);
    expect(wallet.payments, isEmpty);

    wallet.landing!.complete();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    expect(wallet.payments, hasLength(1));
    expect(find.text('Sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(env.fake.calls.any((c) => c.$1 == 'markPaid'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'the leg fails: the words, the steps, Send now again; nothing '
      'paid and the prompt keeps the link payable', (tester) async {
    wallet.failLeg = true;
    await pump(tester);
    await tester.tap(kuteBarPrimary);
    await settle(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    expect(find.text(_failed), findsOneWidget);
    expect(find.byKey(const ValueKey('share-claimed-steps')), findsOneWidget);
    expect(wallet.payments, isEmpty);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    expect(ShareLinksStore.byId('lnk_gift')?.paymentId, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a swap blocked and no other source: the policy\'s own words '
      'before the tap, and at it; nothing moves', (tester) async {
    final policy = runtimePolicyFixture(
      blocked: const {'orchestra.swap'},
      reasons: const {'orchestra.swap': 'country_blocked'},
      decorations: const {
        'orchestra.swap': {
          'regions': {'label': 'the places swaps are restricted'}
        },
      },
    );
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);
    wallet.denied = bitcoinToDollarsDenied(policy);
    expect(wallet.denied, isNotNull);
    await pumpShareWidget(
      tester,
      env,
      ClaimedPromptSheet(claim: giftSheetClaim(amountMinor: 2000)),
      dollars: 5,
      overrides: [
        settingsProvider
            .overrideWith((ref) => SettingsModel(giftSheetSettings)),
        spendingBitcoinLandingUsdProvider.overrideWith((ref) => 40.0),
        runtimeCapabilitiesProvider.overrideWithValue(policy),
        venueCashClosedProvider.overrideWith((ref) => const {}),
        aiEnabledProvider.overrideWith((ref) async => false),
        ...wallet.overrides(),
      ],
    );
    expect(find.text(_bitcoinLine), findsNothing);
    final body =
        tester.widget<Text>(find.byKey(const ValueKey('share-claimed-body')));
    expect(body.data, isNot(contains('Send it now')));
    await tester.tap(kuteBarPrimary);
    await settle(tester);
    expect(wallet.legs, 0);
    expect(wallet.payments, isEmpty);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'after a restart with the leg on its way: the steps show it, '
      'and Send now waits for it, no second leg', (tester) async {
    ShareLinksStore.setFunding(
        giftSheetClaim(amountMinor: 2000), giftSheetRunningRecord());
    wallet.landing = Completer<void>();
    await pump(tester, dollars: 5, bitcoin: 40);
    expect(find.byKey(const ValueKey('share-claimed-steps')), findsOneWidget);
    // Its words are the steps', on its way: nothing more has to move.
    expect(find.text(_bitcoinLine), findsOneWidget);
    expect(find.byKey(const ValueKey('share-claimed-funding')), findsNothing);
    await tester.tap(kuteBarPrimary);
    await settle(tester);
    expect(wallet.legs, 0);
    wallet.landing!.complete();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    expect(wallet.legs, 0);
    expect(wallet.payments, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
