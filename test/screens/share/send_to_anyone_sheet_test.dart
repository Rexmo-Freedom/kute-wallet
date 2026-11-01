// Send to anyone, dollars: the amount on the keypad, the optional first
// name under the live share card, Create link posting to the backend, the
// card in full with Share as the bar (the PNG and the OS share text), the
// local pending row and the events. Plus the market share sheet's referral link.
// The sheet's Continue / Create link / Done is the floating Sal bar
// (kute_bar_test_support.dart).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/services/share_links_store.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

void main() {
  late ShareTestEnv env;
  late List<String> shared;
  late List<XFile> images;

  setUp(() {
    env = setUpShareTest();
    shared = [];
    images = [];
    ShareCardShare.debugSharer = (image, text) async {
      images.add(image);
      shared.add(text);
      return 'success';
    };
  });

  tearDown(tearDownShareTest);

  testWidgets(
      'amount, name, Create link: the backend row, the share text, '
      'the receipt and the events', (tester) async {
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.dollars));

    // Continue is off until an amount is typed: the bar says so.
    final enterAmount = kuteBarPrimaryWithText('Enter an amount');
    expect(enterAmount, findsOneWidget);
    await tester.tap(enterAmount);
    await settle(tester);
    expect(find.byKey(const ValueKey('share-name-field')), findsNothing);

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await settle(tester);
    final continueButton = kuteBarPrimaryWithText('Continue');
    await tester.tap(continueButton);
    await settle(tester);

    expect(find.text('Who is it for?'), findsOneWidget);
    // The money card, live above the field.
    expect(find.byKey(const ValueKey('share-live-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-send_dollars')),
        findsOneWidget);
    expect(find.text('\$12.00'), findsOneWidget);
    expect(find.text('FOR YOU'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('share-name-field')), 'Ana');
    await tester.pump();
    expect(find.text('FOR ANA'), findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);
    // The card first: nothing shared until Share.
    expect(shared, isEmpty);
    expect(find.text('Your card is ready'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-done')), findsOneWidget);
    await shareCardAndWait(tester, shared);

    // The backend got the pending send; nothing moved.
    expect(env.fake.calls.single.$1, 'create');
    expect(env.fake.calls.single.$2, {
      'kind': 'dollars',
      'asset': 'USDB',
      'amountMinor': 1200,
      'marketSlug': null,
      'senderLabel': 'Ana',
    });
    // The OS share sheet got the card as a PNG with the message and link.
    expect(
        shared.single,
        'Ana, I sent you \$12.00 with Kute. Claim it here: '
        'https://web.test/c/lnk_1\n'
        'Claim it before I change my mind.');
    expect(images.single.mimeType, 'image/png');
    final bytes = await tester.runAsync(images.single.readAsBytes) as Uint8List;
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // The receipt row.
    expect(find.text('\$12.00 · Ana'), findsOneWidget);
    expect(find.text('Link sent · waiting for Ana to claim'), findsOneWidget);
    final row = ShareLinksStore.byId('lnk_1')!;
    expect(row.status, ShareLinkStatus.open);
    expect(row.label, 'Ana');
    expect(row.url, 'https://web.test/c/lnk_1');
    // Exact amount, categories, nothing identifying.
    expect(env.paramsOf('share_link_created').single,
        {'kind': 'dollars', 'asset': 'USDB', 'amount': 12.0});
    expect(env.paramsOf('share_link_shared').single,
        {'kind': 'dollars', 'result': 'success'});
    for (final e in env.events) {
      final values = e.$2?.values.map((v) => '$v') ?? const <String>[];
      expect(values, isNot(anyElement(contains('lnk_1'))));
      expect(values, isNot(anyElement(contains('Ana'))));
      expect(values, isNot(anyElement(contains('web.test'))));
    }
  });

  testWidgets(
      'no name: the unnamed message and receipt; the market slug rides along',
      (tester) async {
    await pumpShareWidget(
        tester,
        env,
        const SendToAnyoneSheet(
            kind: ShareLinkKind.dollars, marketSlug: 'will-it-rain'));
    await tester.tap(find.text('5'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Continue'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);
    await shareCardAndWait(tester, shared);

    expect(env.fake.calls.single.$2['marketSlug'], 'will-it-rain');
    expect(env.fake.calls.single.$2['senderLabel'], isNull);
    expect(
        shared.single,
        'I sent you \$5.00 with Kute. Claim it here: '
        'https://web.test/c/lnk_1\n'
        'Claim it before I change my mind.');
    expect(find.text('Link sent · waiting to be claimed'), findsOneWidget);
    expect(env.paramsOf('share_link_created').single,
        containsPair('market', 'will-it-rain'));
  });

  testWidgets(
      'a prediction pick: the pick line, the pick on the create request, '
      'the prediction share text and the outcome on the event',
      (tester) async {
    await pumpShareWidget(
        tester,
        env,
        const SendToAnyoneSheet(
          kind: ShareLinkKind.dollars,
          marketSlug: 'gemini-carbon',
          marketTitle: 'Gemini Carbon',
          venue: 'polymarket',
          outcome: 'Yes',
          outcomeIndex: 0,
          side: 'buy',
        ));
    // The sheet is titled by the pick and shows it above the amount.
    expect(find.text('Send this prediction'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-pick-line')), findsOneWidget);
    expect(find.text('Yes on Gemini Carbon'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Continue'));
    await settle(tester);
    // The pick's card, live: the prediction with the pick and amount.
    expect(find.byKey(const ValueKey('share-card-send_prediction')),
        findsOneWidget);
    expect(find.text(r'$20 on Yes'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('share-name-field')), 'Ana');
    await tester.pump();
    expect(find.text('ANA, A PICK FOR YOU'), findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);
    await shareCardAndWait(tester, shared);

    expect(env.fake.calls.single.$2, {
      'kind': 'dollars',
      'asset': 'USDB',
      'amountMinor': 2000,
      'marketSlug': 'gemini-carbon',
      'senderLabel': 'Ana',
      'venue': 'polymarket',
      'outcome': 'Yes',
      'outcomeIndex': 0,
      'side': 'buy',
    });
    expect(
        shared.single,
        'Ana, I sent you a prediction on Kute: Yes on Gemini Carbon, '
        '\$20.00. Claim it: https://web.test/c/lnk_1\n'
        'Trust me on this one.');
    final row = ShareLinksStore.byId('lnk_1')!;
    expect(row.outcome, 'Yes');
    expect(row.marketTitle, 'Gemini Carbon');
    expect(row.venue, 'polymarket');
    // The label only, never the index or an id.
    expect(env.paramsOf('share_link_created').single, {
      'kind': 'dollars',
      'asset': 'USDB',
      'amount': 20.0,
      'market': 'gemini-carbon',
      'outcome': 'Yes',
    });
  });

  testWidgets('an investment pick says an investment', (tester) async {
    await pumpShareWidget(
        tester,
        env,
        const SendToAnyoneSheet(
          kind: ShareLinkKind.dollars,
          marketSlug: 'BTC',
          marketTitle: 'BTC',
          venue: 'hyperliquid',
          outcome: 'Long',
          side: 'long',
        ));
    expect(find.text('Send this investment'), findsOneWidget);
    expect(find.text('Long on BTC'), findsOneWidget);
    await tester.tap(find.text('5'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Continue'));
    await settle(tester);
    expect(find.byKey(const ValueKey('share-card-send_investment')),
        findsOneWidget);
    expect(find.text(r'Long · $5'), findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);
    await shareCardAndWait(tester, shared);
    expect(env.fake.calls.single.$2['side'], 'long');
    expect(env.fake.calls.single.$2.containsKey('outcomeIndex'), isFalse);
    expect(
        shared.single,
        'I sent you an investment on Kute: Long on BTC, \$5.00. '
        'Claim it: https://web.test/c/lnk_1\n'
        "This one's going places.");
  });

  testWidgets('a backend failure keeps the name step with a note',
      (tester) async {
    env.fake.failNext['create'] = Exception('down');
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.dollars));
    await tester.tap(find.text('3'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Continue'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);

    expect(find.text('Could not create the link. Try again.'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Create link'), findsOneWidget);
    expect(shared, isEmpty);
    expect(ShareLinksStore.all(), isEmpty);
    expect(env.paramsOf('share_link_created'), isEmpty);
  });

  test('the market link carries the referral code as ref', () {
    expect(
        shareLinkWithReferral('https://kute.app/m/will-it-rain',
            code: 'KUTE42'),
        'https://kute.app/m/will-it-rain?ref=KUTE42');
    expect(
        shareLinkWithReferral('https://kute.app/m/x?utm_source=a', code: 'K1'),
        'https://kute.app/m/x?utm_source=a&ref=K1');
    expect(shareLinkWithReferral('https://kute.app/m/x', code: null),
        'https://kute.app/m/x');
  });
}
