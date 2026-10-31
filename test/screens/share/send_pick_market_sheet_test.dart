// Send a prediction or investment from the dollar send (send_pick_market
// _sheet.dart): the picker lists the loaded feeds, a picked market opens
// the side pair with the leading side preselected, Continue opens Send to
// anyone for dollars with the pick, a contact picked before rides along
// as the label, and the created row keeps the number for WhatsApp / SMS
// without it ever reaching the backend or an event.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/share/send_pick_market_sheet.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_link_resend.dart';
import 'package:kute/screens/shared/market_side_toggle.dart';
import 'package:kute/services/share_links_store.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

final _l10n = AppLocalizationsEn();

const _event = PolymarketEvent(
  id: 'e1',
  slug: 'btc-100k',
  title: 'BTC 100k',
  volume: 1000,
  liquidity: 500,
  category: 'crypto',
  conditionId: 'c1',
  outcomes: [
    PolymarketOutcome(name: 'Yes', price: 0.7),
    PolymarketOutcome(name: 'No', price: 0.3),
  ],
);

const _market = HlMarket(
  coin: 'ETH',
  wireCoin: 'ETH',
  assetId: 1,
  kind: HlMarketKind.perp,
  szDecimals: 4,
  maxLeverage: 25,
  onlyIsolated: false,
  markPx: 3000,
  midPx: 3000,
  prevDayPx: 2900,
  dayNtlVlm: 1e9,
);

class _Launcher extends StatelessWidget {
  const _Launcher({this.senderLabel, this.recipientPhone});
  final String? senderLabel;
  final String? recipientPhone;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () => showSendPickMarketSheet(context,
              entrySource: 'dollar_send',
              senderLabel: senderLabel,
              recipientPhone: recipientPhone),
          child: const Text('Pick'),
        ),
      );
}

void main() {
  late ShareTestEnv env;
  final shared = <String>[];
  final launched = <Uri>[];

  setUp(() {
    env = setUpShareTest();
    shared.clear();
    launched.clear();
    SendToAnyoneSheet.debugSharer = (text) async {
      shared.add(text);
      return 'success';
    };
    debugShareLinkResendLauncher = (uri) async {
      launched.add(uri);
      return true;
    };
    SendPickMarketSheet.debugFeeds =
        (predictions: [_event], investing: [_market]);
  });

  tearDown(() {
    tearDownShareTest();
    SendToAnyoneSheet.debugSharer = null;
    debugShareLinkResendLauncher = null;
    SendPickMarketSheet.debugFeeds = null;
  });

  Future<void> open(WidgetTester tester,
      {String? senderLabel, String? recipientPhone}) async {
    await pumpShareWidget(tester, env,
        _Launcher(senderLabel: senderLabel, recipientPhone: recipientPhone));
    await tester.tap(find.text('Pick'));
    await settle(tester);
    expect(find.byType(SendPickMarketSheet), findsOneWidget);
  }

  testWidgets('the picker lists trending predictions and the movers, and '
      'the search filters both', (tester) async {
    await open(tester);
    expect(env.paramsOf('send_pick_market_opened').single,
        containsPair('source', 'send'));
    expect(find.text(_l10n.searchHomeTrendingPredictions), findsOneWidget);
    expect(find.text(_l10n.searchHomeMovingNow), findsOneWidget);
    expect(find.text('BTC 100k'), findsOneWidget);
    expect(find.text('ETH'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('send-pick-market-search')), 'eth');
    await settle(tester);
    expect(find.text('BTC 100k'), findsNothing);
    expect(find.text('ETH'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('send-pick-market-search')), 'zzz');
    await settle(tester);
    expect(find.text(_l10n.sendPickMarketNoResults), findsOneWidget);
  });

  testWidgets(
      'a prediction: Yes preselected as the leading side, then Send to '
      'anyone for dollars with the pick and the contact picked before; the '
      'row keeps the number for WhatsApp, the backend never sees it',
      (tester) async {
    await open(tester,
        senderLabel: 'Maria', recipientPhone: '+351 912 345 678');
    await tester.tap(find.text('BTC 100k'));
    await settle(tester);
    expect(find.text(_l10n.sendPickSideTitle), findsOneWidget);
    final toggle = tester.widget<MarketSideToggle>(
        find.byKey(const ValueKey('send-pick-side-toggle')));
    expect(toggle.isUp, isTrue);
    expect(toggle.upLabel, _l10n.yes);
    expect(toggle.downLabel, _l10n.betNo);

    await tester.tap(kuteBarPrimaryWithText(_l10n.continueLabel));
    await settle(tester);
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('share-pick-line')), findsOneWidget);
    expect(find.text('Yes on BTC 100k'), findsOneWidget);

    await tester.tap(find.text('1'));
    await settle(tester);
    await tester.tap(find.text('2'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText(_l10n.continueLabel));
    await settle(tester);
    // The contact's first name is the label already.
    final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('share-name-field')),
        matching: find.byType(TextField)));
    expect(field.controller!.text, 'Maria');

    await tester.tap(kuteBarPrimaryWithText(_l10n.shareCreateLink));
    await settle(tester);
    final create = env.fake.calls.where((c) => c.$1 == 'create').single.$2;
    expect(create['kind'], 'dollars');
    expect(create['amountMinor'], 1200);
    expect(create['marketSlug'], 'btc-100k');
    expect(create['venue'], 'polymarket');
    expect(create['outcome'], 'Yes');
    expect(create['outcomeIndex'], 0);
    expect(create['side'], 'buy');
    expect(create['senderLabel'], 'Maria');
    expect(create.values.map((v) => '$v').join(' '), isNot(contains('912')));
    final row = ShareLinksStore.all().single;
    expect(row.recipientPhone, '+351 912 345 678');
    expect(row.label, 'Maria');
    for (final e in env.events) {
      expect(e.$2?.values.map((v) => '$v').join(' ') ?? '',
          isNot(contains('912')));
    }
    expect(shared.single, contains('Maria'));

    // The receipt: Send again via WhatsApp opens wa.me with the number and
    // the text; SMS the composer.
    await tester.tap(find.byKey(const ValueKey('share-again-whatsapp')));
    await settle(tester);
    expect(launched.single.host, 'wa.me');
    expect(launched.single.path, '/351912345678');
    expect(launched.single.queryParameters['text'], contains('Maria'));
    await tester.tap(find.byKey(const ValueKey('share-again-sms')));
    await settle(tester);
    expect(launched.last.scheme, 'sms');
    expect(launched.last.path, '+351912345678');
  });

  testWidgets('an investment: Long preselected, then Send this investment',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('ETH'));
    await settle(tester);
    final toggle = tester.widget<MarketSideToggle>(
        find.byKey(const ValueKey('send-pick-side-toggle')));
    expect(toggle.isUp, isTrue);
    expect(toggle.upLabel, _l10n.longLabel);
    // Short it.
    await tester.tap(find.text(_l10n.shortLabel));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText(_l10n.continueLabel));
    await settle(tester);
    expect(find.byType(SendToAnyoneSheet), findsOneWidget);
    expect(find.text(_l10n.sendThisInvestment), findsOneWidget);
    final sheet =
        tester.widget<SendToAnyoneSheet>(find.byType(SendToAnyoneSheet));
    expect(sheet.venue, 'hyperliquid');
    expect(sheet.side, 'short');
    expect(sheet.outcome, _l10n.shortLabel);
    expect(sheet.marketSlug, 'ETH');
    expect(sheet.senderLabel, isNull);
  });
}
