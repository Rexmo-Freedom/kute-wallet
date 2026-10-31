// The Claim screen's states against the fake backend: ready (headline,
// market line), claimed ("On its way", Open the market), already claimed,
// not found, and a wallet that is not ready yet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/claim_screen.dart';
import 'package:kute/services/share_links_store.dart';

import 'share_test_harness.dart';

ShareLink _link({
  String id = 'lnk_1',
  ShareLinkKind kind = ShareLinkKind.dollars,
  int amountMinor = 1250,
  String? sender = 'Ana',
  String? market,
  ShareLinkStatus status = ShareLinkStatus.open,
}) =>
    ShareLink(
      id: id,
      kind: kind,
      amountMinor: amountMinor,
      senderLabel: sender,
      marketSlug: market,
      status: status,
      rawStatus: status.name,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );

void main() {
  late ShareTestEnv env;

  setUp(() {
    env = setUpShareTest();
    ClaimScreen.debugDestination = (_) async => 'spark1recipient';
  });

  tearDown(() {
    tearDownShareTest();
    ClaimScreen.debugDestination = null;
  });

  testWidgets('ready: who sent what, the market line, one Claim button',
      (tester) async {
    env.fake.seed(_link(market: 'will-it-rain-in-lisbon'));
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));

    expect(find.text('Ana sent you \$12.50'), findsOneWidget);
    expect(find.text('to bet on will it rain in lisbon'), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-button')), findsOneWidget);
    expect(env.fake.callNames, ['read']);
  });

  testWidgets('no sender name reads as Someone; bitcoin says in Bitcoin',
      (tester) async {
    env.fake.seed(
        _link(kind: ShareLinkKind.bitcoin, amountMinor: 5000, sender: null));
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));

    final headline =
        tester.widget<Text>(find.byKey(const ValueKey('claim-headline')));
    expect(headline.data, startsWith('Someone sent you '));
    expect(headline.data, endsWith(' in Bitcoin'));
  });

  testWidgets('claim posts the wallet destination and says it is on its way',
      (tester) async {
    env.fake.seed(_link(market: 'will-it-rain'));
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));

    await tester.tap(find.byKey(const ValueKey('claim-button')));
    await settle(tester);

    expect(env.fake.claimDestinations['lnk_1'], 'spark1recipient');
    expect(find.text('On its way'), findsOneWidget);
    expect(find.text('It arrives when Ana opens Kute.'), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-open-market')), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-button')), findsNothing);
    expect(env.paramsOf('share_link_claimed').single,
        {'kind': 'dollars', 'asset': 'USDB', 'amount': 12.5});
    // Nothing identifying went out.
    for (final e in env.events) {
      expect(e.$2?.values.map((v) => '$v'),
          isNot(anyElement(contains('spark1recipient'))));
      expect(
          e.$2?.values.map((v) => '$v'), isNot(anyElement(contains('lnk_1'))));
    }
  });

  testWidgets('without a market the claimed state offers Done', (tester) async {
    env.fake.seed(_link());
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));
    await tester.tap(find.byKey(const ValueKey('claim-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('claim-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-open-market')), findsNothing);
  });

  testWidgets('already claimed: the message, no Claim button', (tester) async {
    env.fake.seed(_link(status: ShareLinkStatus.claimed));
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));
    expect(find.text('This link was already claimed.'), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-button')), findsNothing);
    expect(find.byKey(const ValueKey('claim-done')), findsOneWidget);
  });

  testWidgets('unknown link: not available', (tester) async {
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'nope'));
    expect(find.text('This link is not available.'), findsOneWidget);
  });

  testWidgets('a claim the backend refuses as taken reads as already claimed',
      (tester) async {
    env.fake.seed(_link());
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));
    // Someone else claimed it between the read and the tap.
    env.fake.seed(_link(status: ShareLinkStatus.claimed));
    await tester.tap(find.byKey(const ValueKey('claim-button')));
    await settle(tester);
    expect(find.text('This link was already claimed.'), findsOneWidget);
    expect(env.paramsOf('share_link_claimed'), isEmpty);
  });

  testWidgets('wallet not ready: stays claimable with a note', (tester) async {
    ClaimScreen.debugDestination = (_) async => throw StateError('no wallet');
    env.fake.seed(_link());
    await pumpShareWidget(tester, env, const ClaimScreen(id: 'lnk_1'));
    await tester.tap(find.byKey(const ValueKey('claim-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('claim-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-button')), findsOneWidget);
    expect(env.fake.callNames, ['read']);
    expect(ShareLinksStore.parkedClaimId, isNull);
  });
}
