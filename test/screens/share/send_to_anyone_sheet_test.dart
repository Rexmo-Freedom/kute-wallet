// Send to anyone, dollars: the amount on the keypad, the optional first
// name, Create link posting to the backend, the OS share text, the local
// pending row and the events. Plus the market share sheet's referral link.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/services/share_links_store.dart';

import 'share_test_harness.dart';

void main() {
  late ShareTestEnv env;
  late List<String> shared;

  setUp(() {
    env = setUpShareTest();
    shared = [];
    SendToAnyoneSheet.debugSharer = (text) async {
      shared.add(text);
      return 'success';
    };
  });

  tearDown(() {
    tearDownShareTest();
    SendToAnyoneSheet.debugSharer = null;
  });

  testWidgets(
      'amount, name, Create link: the backend row, the share text, '
      'the receipt and the events', (tester) async {
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.dollars));

    // Continue is off until an amount is typed.
    final continueButton = find.byKey(const ValueKey('share-amount-continue'));
    expect(continueButton, findsOneWidget);
    await tester.tap(continueButton);
    await settle(tester);
    expect(find.byKey(const ValueKey('share-name-field')), findsNothing);

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(continueButton);
    await settle(tester);

    expect(find.text('Who is it for?'), findsOneWidget);
    expect(find.text('\$12.00'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('share-name-field')), 'Ana');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-create-link')));
    await settle(tester);

    // The backend got the pending send; nothing moved.
    expect(env.fake.calls.single.$1, 'create');
    expect(env.fake.calls.single.$2, {
      'kind': 'dollars',
      'asset': 'USDB',
      'amountMinor': 1200,
      'marketSlug': null,
      'senderLabel': 'Ana',
    });
    // The OS share sheet got the message with the link.
    expect(shared.single,
        'Ana, I sent you \$12.00 with Kute. Claim it here: https://web.test/c/lnk_1');
    // The receipt row.
    expect(find.text('\$12.00 · Ana'), findsOneWidget);
    expect(find.text('Link sent · waiting for Ana to claim'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-done')), findsOneWidget);
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-amount-continue')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('share-create-link')));
    await settle(tester);

    expect(env.fake.calls.single.$2['marketSlug'], 'will-it-rain');
    expect(env.fake.calls.single.$2['senderLabel'], isNull);
    expect(shared.single,
        'I sent you \$5.00 with Kute. Claim it here: https://web.test/c/lnk_1');
    expect(find.text('Link sent · waiting to be claimed'), findsOneWidget);
    expect(env.paramsOf('share_link_created').single,
        containsPair('market', 'will-it-rain'));
  });

  testWidgets('a backend failure keeps the name step with a note',
      (tester) async {
    env.fake.failNext['create'] = Exception('down');
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.dollars));
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-amount-continue')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('share-create-link')));
    await settle(tester);

    expect(find.text('Could not create the link. Try again.'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-create-link')), findsOneWidget);
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
