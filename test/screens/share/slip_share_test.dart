// A slip in SEND MODE (slip_share.dart, send_pick_session.dart; founder,
// 7 November 2026: "only in Send should it be to send to someone"). Its
// primary is the send ([slipSendCta]): "Send $5 · Yes", "Send $25 · Long
// Bitcoin"; disabled with the step to take while the amount or the side
// cannot be sent; refused here, disabled and no link ever, the slip saying
// why (founder, 8 November 2026: "only on the last screen, the bet slip,
// show this error"); "Send the market" only where nothing but the card can
// go (a spot sale). What a tap does with what the slip hands it
// ([sendFromSlip]):
// THIS pick and amount straight into Send to anyone's last step (the
// gift card as the hero, "Send prediction"), the contact picked on Send
// as the name; a spot sale, the market's card only; a link created closes
// the whole send ([SendPickSession.finish]). The slips' own wiring is in
// bet_slip_check_connection_test.dart and
// order_slip_check_connection_test.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_de.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/share/slip_share.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

final _en = AppLocalizationsEn();

SlipSharePick _pick({
  bool investing = false,
  String? outcome = 'Yes',
  String? sideLabel,
  double amountUsd = 5,
  bool blocked = false,
  bool cardOnly = false,
}) =>
    SlipSharePick(
      investing: investing,
      slug: investing ? 'BTC' : 'will-it-rain',
      title: investing ? 'Bitcoin' : 'Will it rain?',
      outcome: investing ? 'Long' : outcome,
      outcomeIndex: investing || outcome == null ? null : 0,
      side: investing ? 'long' : 'buy',
      sideLabel: sideLabel ?? (investing ? 'Long' : 'Jon Ossoff'),
      amountUsd: amountUsd,
      minUsd: 1,
      minLabel: r'$1.00',
      blocked: blocked,
      cardOnly: cardOnly,
      marketChance: investing ? null : 62,
      price: investing ? r'$60,000' : null,
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

  group('the primary in send mode', () {
    test('a pick: "Send \$5 · Yes", "Send \$25 · Long Bitcoin", enabled',
        () {
      final yes = slipSendCta(_en, _pick(sideLabel: 'Yes'));
      expect(yes.label, r'Send $5 · Yes');
      expect(yes.enabled, isTrue);
      expect(yes.route, SlipSendRoute.pick);
      final long = slipSendCta(_en, _pick(investing: true, amountUsd: 25));
      expect(long.label, r'Send $25 · Long Bitcoin');
      expect(long.enabled, isTrue);
      final cents = slipSendCta(
          _en, _pick(investing: true, amountUsd: 12.5, sideLabel: 'Short'));
      expect(cents.label, r'Send $12.50 · Short Bitcoin');
      // The locale's own words and numbers.
      expect(slipSendCta(AppLocalizationsDe(), _pick(sideLabel: 'Ja')).label,
          contains('senden'));
    });

    test('disabled, saying what to do: nothing typed, under the minimum, '
        'No on a candidate', () {
      final empty = slipSendCta(_en, _pick(amountUsd: 0, sideLabel: 'Yes'));
      expect(empty.enabled, isFalse);
      expect(empty.disabledLabel, 'Enter an amount to send');
      final under = slipSendCta(_en, _pick(amountUsd: 0.5));
      expect(under.enabled, isFalse);
      expect(under.disabledLabel, r'Enter at least $1.00 to send');
      final no = slipSendCta(_en, _pick(outcome: null));
      expect(no.enabled, isFalse);
      expect(no.disabledLabel, 'Only Yes on Jon Ossoff can be sent');
    });

    test('refused here: disabled, the send\'s own words, whatever else holds',
        () {
      for (final refused in [
        _pick(blocked: true, sideLabel: 'Yes'),
        _pick(investing: true, blocked: true),
        _pick(investing: true, blocked: true, cardOnly: true),
        _pick(blocked: true, amountUsd: 0),
      ]) {
        final cta = slipSendCta(_en, refused);
        expect(cta.enabled, isFalse);
        expect(cta.route, SlipSendRoute.refused);
        expect(cta.label, isNot('Send the market'));
      }
    });

    test('a spot sale, nothing but the card to send: "Send the market"', () {
      final market = slipSendCta(_en, _pick(investing: true, cardOnly: true));
      expect(market.label, 'Send the market');
      expect(market.enabled, isTrue);
      expect(market.route, SlipSendRoute.market);
    });
  });

  Future<void> tapSend(WidgetTester tester, SlipSharePick pick,
      {SendPickSession? session}) async {
    await pumpShareWidget(
      tester,
      env,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => sendFromSlip(context, pick, session: session),
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
    // The gift card: the amount sent is the hero, the side under it.
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-card-number')))
            .data,
        r'$5');
    expect(find.byKey(const ValueKey('share-card-plain')), findsNothing);
    expect(find.byKey(const ValueKey('share-name-field')), findsOneWidget);
    expect(kuteBarPrimaryWithText('Send prediction'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Continue'), findsNothing);
    expect(find.byType(ShareMarketSheet), findsNothing);
  });

  testWidgets(
      'from Send with a contact picked: the name and the number prefilled; '
      'the entry is the send-mode slip', (tester) async {
    await tapSend(tester, _pick(),
        session: SendPickSession(
            entrySource: 'dollar_send',
            recipientName: 'Ana',
            recipientPhone: '+351 912 345 678'));
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.senderLabel, 'Ana');
    expect(sheet.recipientPhone, '+351 912 345 678');
    expect(_pick().entrySource, kSendModeSlipSource);
    expect(find.textContaining('ANA, A PREDICTION FOR YOU'), findsOneWidget);
  });

  testWidgets(
      'a gift that went out closes the whole send: the slip and the pages '
      'over the search sheet, and the sheet', (tester) async {
    final session = SendPickSession(entrySource: 'dollar_send');
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Text('send screen'),
    ));
    Route<void> page(String name) =>
        MaterialPageRoute(builder: (_) => Text(name));
    final sheet = page('search sheet');
    unawaited(nav.currentState!.push(sheet));
    unawaited(nav.currentState!.push(page('market page')));
    unawaited(nav.currentState!.push(page('slip')));
    await tester.pumpAndSettle();
    session.attach(sheet);
    expect(session.sent, isFalse);
    session.finish(nav.currentState!);
    await tester.pumpAndSettle();
    expect(session.sent, isTrue);
    expect(find.text('send screen'), findsOneWidget);
    for (final gone in ['search sheet', 'market page', 'slip']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
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

  for (final (name, refused) in [
    ('a prediction', _pick(blocked: true)),
    ('an investment', _pick(investing: true, blocked: true)),
    ('a spot sale', _pick(investing: true, blocked: true, cardOnly: true)),
  ]) {
    testWidgets('$name refused here: no sheet opens, no link is created',
        (tester) async {
      await tapSend(tester, refused);
      expect(routes, [SlipSendRoute.refused]);
      expect(find.byType(SendToAnyoneSheet), findsNothing);
      expect(find.byType(ShareMarketSheet), findsNothing);
      expect(env.fake.calls, isEmpty);
    });
  }

  testWidgets(
      'no slug to name, not refused: the market send sheet, its card '
      'only; no pick, no money, nothing that says a prediction is attached',
      (tester) async {
    await tapSend(
        tester,
        SlipSharePick(
          investing: false,
          slug: '',
          marketLinkSlug: 'will-it-rain',
          title: 'Will it rain?',
          outcome: 'Yes',
          side: 'buy',
          sideLabel: 'Yes',
          amountUsd: 5,
          minUsd: 1,
          minLabel: r'$1.00',
          blocked: false,
          marketChance: 62,
        ));
    expect(routes, [SlipSendRoute.market]);
    expect(find.byType(SendToAnyoneSheet), findsNothing);
    expect(find.byType(ShareMarketSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-prediction_market')),
        findsOneWidget);
    expect(find.textContaining('A PREDICTION FOR YOU'), findsNothing);
    expect(find.text(r'$5'), findsNothing);
    expect(kuteBarPrimaryWithText('Share'), findsOneWidget);
    expect(env.fake.calls, isEmpty);
  });

  testWidgets('a spot sale: the market send sheet with the stock',
      (tester) async {
    await tapSend(tester, _pick(investing: true, cardOnly: true));
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
