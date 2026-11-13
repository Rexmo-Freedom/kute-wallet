// The share sheets' primary buttons are the floating Sal bar
// (kute_bar_context.dart, KuteBarContext.primary; founder, 1 November
// 2026: every big black button adapts from Sal like the search pill
// does): the market share sheet's Share (the card first), the claimed prompt's
// Send now and the pending link detail's Share again. The sheets draw no
// AppButton of their own; their second button stays as a text button.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/claimed_prompt_sheet.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/services/share_links_store.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

void main() {
  late ShareTestEnv env;

  setUp(() {
    env = setUpShareTest();
  });

  tearDown(() {
    tearDownShareTest();
    ClaimedPromptSheet.debugPayer = null;
  });

  testWidgets('market share sheet: the card first, Share is the bar, the '
      'market only (a prediction is sent from its slip)', (tester) async {
    final shared = <String>[];
    final names = <String>[];
    ShareCardShare.debugSharer = (image, text) async {
      names.add(image.name);
      shared.add(text);
      return 'success';
    };
    await pumpShareWidget(
        tester,
        env,
        const ShareMarketSheet(
          title: 'Will it rain',
          subtitle: null,
          deepLink: 'https://web.test/m/will-it-rain',
          marketSlug: 'will-it-rain',
          chance: 60,
          venue: 'polymarket',
        ));

    expect(find.byType(AppButton), findsNothing);
    expect(find.byKey(const ValueKey('share-card-prediction_market')),
        findsOneWidget);
    expect(kuteBarPrimaryWithText('Share'), findsOneWidget);
    expect(find.text('Send this prediction'), findsNothing);
    expect(find.text('Send a prediction'), findsNothing);
    expect(kuteBarPrimaryEnabled(tester), isTrue);

    await shareCardAndWait(tester, shared);
    expect(shared.single, contains('https://web.test/m/will-it-rain'));
    expect(env.paramsOf('share_market_link_shared').single,
        containsPair('result', 'success'));
  });

  testWidgets('claimed prompt: Send now is the bar, busy while the payment '
      'runs; Later stays a text button', (tester) async {
    final pay = Completer<String?>();
    ClaimedPromptSheet.debugPayer = (_, __, ___) => pay.future;
    await pumpShareWidget(
        tester,
        env,
        const ClaimedPromptSheet(
          claim: ClaimedShareLink(
            id: 'lnk_1',
            kind: ShareLinkKind.dollars,
            amountMinor: 500,
            claimDestination: 'sp1qtest',
          ),
        ));

    expect(find.byType(AppButton), findsNothing);
    expect(kuteBarPrimaryWithText('Send now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isTrue);

    await tester.tap(kuteBarPrimary);
    await settle(tester);
    expect(kuteBarPrimaryProbe(tester).isLoading, isTrue);
    expect(kuteBarPrimaryProbe(tester).onPressed, isNull);

    pay.complete('pay_1');
    await settle(tester);
    expect(find.text('Sent'), findsOneWidget);
    expect(ShareLinksStore.byId('lnk_1')?.status, ShareLinkStatus.paid);
    // The sheet closes itself after the confirmation.
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
  });

  testWidgets('pending link detail: Share again is the bar, Cancel link '
      'stays a text button', (tester) async {
    final row = PendingShareLink(
      id: 'lnk_2',
      kind: ShareLinkKind.dollars,
      amountMinor: 1000,
      label: 'Ana',
      url: 'https://web.test/c/lnk_2',
      createdAt: DateTime(2026, 11, 1),
      status: ShareLinkStatus.open,
    );
    ShareLinksStore.put(row);
    await pumpShareWidget(
        tester,
        env,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPendingShareLinkDetail(context, row),
            child: const Text('open'),
          ),
        ));
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(find.byType(AppButton), findsNothing);
    expect(kuteBarPrimaryWithText('Share again'), findsOneWidget);
    expect(find.text('Cancel link'), findsOneWidget);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    // The receipt's one structure: the hero with the amount and the
    // status under it, the recipient and the date as tiles.
    expect(find.byKey(const ValueKey('receipt-hero')), findsOneWidget);
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.text('Link sent · waiting for Ana to claim'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-tile-To')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-tile-Date')), findsOneWidget);
  });
}
