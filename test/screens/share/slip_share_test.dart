// The slip's round Sal button (slip_share.dart; founder, 5 November 2026:
// "the share button should be on this bet slip page actually, it carries
// all the information, even the amount"). What a tap does with what the
// slip hands it: THIS pick and amount straight into Send to anyone's last
// step (the card as the hero, "Send prediction"); the venue closed to
// this person, the market's card only ("he cannot also send the actual
// prediction, just the card"); nothing typed, under the minimum, or No on
// a candidate, a toast saying what to do, never a silent no-op. The slips'
// own wiring is in bet_slip_check_connection_test.dart and
// order_slip_check_connection_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/share/slip_share.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

SlipSharePick _pick({
  bool investing = false,
  String? outcome = 'Yes',
  double amountUsd = 5,
  bool blocked = false,
}) =>
    SlipSharePick(
      investing: investing,
      slug: investing ? 'BTC' : 'will-it-rain',
      title: investing ? 'Bitcoin' : 'Will it rain?',
      outcome: investing ? 'Long' : outcome,
      outcomeIndex: investing || outcome == null ? null : 0,
      side: investing ? 'long' : 'buy',
      sideLabel: investing ? 'Long' : 'Jon Ossoff',
      amountUsd: amountUsd,
      minUsd: 1,
      minLabel: r'$1.00',
      blocked: blocked,
      marketChance: investing ? null : 62,
      price: investing ? r'$60,000' : null,
      entrySource: 'bet_slip',
    );

void main() {
  late ShareTestEnv env;
  late List<SlipSendRoute> routes;

  setUp(() {
    env = setUpShareTest();
    routes = [];
    SlipShare.debugRoute = (r, _) => routes.add(r);
  });

  tearDown(() {
    tearDownShareTest();
    SlipShare.debugRoute = null;
  });

  Future<void> tapSend(WidgetTester tester, SlipSharePick pick) async {
    await pumpShareWidget(
      tester,
      env,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => sendFromSlip(context, pick),
            child: const Text('send'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('send'));
    await settle(tester);
  }

  testWidgets(
      'a prediction with its amount: Send to anyone on its last step, the '
      'pick and the amount prefilled, "Send prediction" the bar',
      (tester) async {
    await tapSend(tester, _pick());
    expect(routes, [SlipSendRoute.pick]);
    final sheet = tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.marketSlug, 'will-it-rain');
    expect(sheet.marketTitle, 'Will it rain?');
    expect(sheet.venue, 'polymarket');
    expect(sheet.outcome, 'Yes');
    expect(sheet.outcomeIndex, 0);
    expect(sheet.side, 'buy');
    expect(sheet.amountMinor, 500);
    expect(find.text('Send this prediction'), findsOneWidget);
    expect(find.text(r'$5 on Yes'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-name-field')), findsOneWidget);
    expect(kuteBarPrimaryWithText('Send prediction'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Continue'), findsNothing);
    expect(find.byType(ShareMarketSheet), findsNothing);
  });

  testWidgets('an investment with its amount: "Send investment"',
      (tester) async {
    await tapSend(tester, _pick(investing: true, amountUsd: 25));
    final sheet = tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.venue, 'hyperliquid');
    expect(sheet.side, 'long');
    expect(sheet.amountMinor, 2500);
    expect(find.text('Send this investment'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Send investment'), findsOneWidget);
  });

  testWidgets(
      'the venue closed to this person: the market send sheet, its card '
      'only; no pick, no money, nothing that says a prediction is attached',
      (tester) async {
    await tapSend(tester, _pick(blocked: true));
    expect(routes, [SlipSendRoute.market]);
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(find.byType(ShareMarketSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-prediction_market')),
        findsOneWidget);
    expect(find.textContaining('A PREDICTION FOR YOU'), findsNothing);
    expect(find.text(r'$5 on Yes'), findsNothing);
    expect(kuteBarPrimaryWithText('Share'), findsOneWidget);
    expect(env.fake.calls, isEmpty);
  });

  testWidgets('Investing closed: the market send sheet with the stock',
      (tester) async {
    await tapSend(tester, _pick(investing: true, blocked: true));
    expect(routes, [SlipSendRoute.market]);
    expect(find.byType(ShareMarketSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-investment_market')),
        findsOneWidget);
  });

  for (final (name, pick, route, toast) in [
    (
      'nothing typed',
      _pick(amountUsd: 0),
      SlipSendRoute.enterAmount,
      'Enter an amount to send',
    ),
    (
      'under the minimum',
      _pick(amountUsd: 0.5),
      SlipSendRoute.minimum,
      r'Enter at least $1.00 to send',
    ),
    (
      'No on a candidate',
      _pick(outcome: null),
      SlipSendRoute.yesOnly,
      'Only Yes on Jon Ossoff can be sent. Switch to Yes to send it.',
    ),
  ]) {
    testWidgets('$name: a toast says what to do, nothing opens',
        (tester) async {
      await tapSend(tester, pick);
      expect(routes, [route]);
      expect(find.text(toast), findsOneWidget);
      expect(find.byType(SendToAnyoneSheet), findsNothing);
      expect(find.byType(ShareMarketSheet), findsNothing);
      // The toast goes by itself.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
  }
}
