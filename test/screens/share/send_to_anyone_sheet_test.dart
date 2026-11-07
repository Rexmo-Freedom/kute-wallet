// Send to anyone, dollars: the amount on the keypad, the optional first
// name under the live share card, Create link posting to the backend, the
// card in full with Share as the bar (the PNG and the OS share text), the
// local pending row and the events. Plus the market share sheet's referral link.
//
// THE AMOUNT STEP IS THE SEND'S (founder, 6 November 2026: "this one must
// have the sats and such, like here"): a bitcoin link opens in sats with
// the Send amount step's own pieces (the ₿ figure, the other unit with the
// ⇅ swap, "N sats available · $X", the unit pill and its sheet, 25% · 50%
// · 100%); a dollar link keeps dollars only, "$X available".
// The sheet's Continue / Create link / Done is the floating Sal bar
// (kute_bar_test_support.dart).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money2/money2.dart' show Fixed;
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show
        SendAmountConversionLine,
        SendAmountUnitPill,
        SendBitcoinAmountHero,
        SendTypedAmountHero;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider;
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/services/share_links_store.dart';

import '../../helpers/kute_bar_test_support.dart';
import 'share_test_harness.dart';

final _gemini = PolymarketEvent(
  id: 'gemini',
  slug: 'gemini-carbon',
  title: 'Gemini Carbon',
  volume: 1000,
  liquidity: 1000,
  category: 'tech',
  tags: const [],
  endDate: DateTime(2027),
  conditionId: 'c-g',
  outcomes: const [
    PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'g-y', conditionId: 'c-g'),
    PolymarketOutcome(name: 'No', price: 0.38, tokenId: 'g-n', conditionId: 'c-g'),
  ],
);

final _election = PolymarketEvent(
  id: 'pres',
  slug: 'presidential-election-winner-2028',
  title: 'Presidential Election Winner 2028',
  volume: 1000,
  liquidity: 1000,
  category: 'politics',
  tags: const [],
  endDate: DateTime(2028, 11, 7),
  conditionId: 'c-p',
  outcomes: const [
    PolymarketOutcome(
        name: 'JD Vance', price: 0.30, tokenId: 'v-y', noTokenId: 'v-n', conditionId: 'c-v'),
    PolymarketOutcome(
        name: 'Jon Ossoff', price: 0.21, tokenId: 'o-y', noTokenId: 'o-n', conditionId: 'c-o'),
  ],
);

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

/// Rates without Hive: bitcoin at $100,000.
class _Rates extends StateNotifier<CurrencyState> implements CurrencyNotifier {
  _Rates()
      : super(CurrencyState({
          'USD': Fixed.fromInt(100),
          'BTC': Fixed.parse('0.00001'),
        }));

  @override
  Future<void> updateRates() async {}
}

/// The spending wallet holding [sats], bitcoin at $100,000, sats as the
/// Bitcoin unit and dollars as the currency.
List<Override> _bitcoinWallet({int sats = 328686}) => [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            'spending': WalletBalance(
                onChainBtcBalance: 0, sparkBitcoinbalance: sats),
          })),
      currencyProvider.overrideWith((_) => _Rates()),
    ];

Future<void> _keys(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.text(k).last);
    await tester.pump();
  }
  await settle(tester);
}

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
        'https://web.test/c/lnk_1');
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
        'https://web.test/c/lnk_1');
    expect(find.text('Link sent · waiting to be claimed'), findsOneWidget);
    expect(env.paramsOf('share_link_created').single,
        containsPair('market', 'will-it-rain'));
  });

  testWidgets(
      'a prediction from its slip: the last step at once, titled and worded '
      'as a prediction; the card says it; the pick and amount on the create '
      'request, the prediction share text and the outcome on the event',
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
          amountMinor: 2000,
        ),
        cardVenues: false,
        overrides: [
          polymarketEventDetailsProvider
              .overrideWith((ref, slug) async => _gemini),
        ]);
    // Straight to who it is for: no keypad, the pick's own title and what
    // happens next.
    expect(find.text('Send this prediction'), findsOneWidget);
    expect(find.text('They claim it, then place it with one tap'),
        findsOneWidget);
    expect(find.text('Who is it for?'), findsNothing);
    expect(kuteBarPrimaryWithText('Continue'), findsNothing);
    // The card is the hero: as wide as the sheet allows.
    final card = tester.getRect(find.byKey(const ValueKey('share-card-preview')));
    expect(card.width, greaterThan(390 * 0.7));
    expect(find.byKey(const ValueKey('share-card-send_prediction')),
        findsOneWidget);
    expect(find.text('A PREDICTION FOR YOU'), findsOneWidget);
    // A gift: the amount sent is the hero, the side under it.
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-card-number')))
            .data,
        r'$20');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('share-card-preview')),
            matching: find.text('Yes')),
        findsOneWidget);
    // What the friend gets, in words, the chance read off the market.
    expect(find.byKey(const ValueKey('send-pick-gets')), findsOneWidget);
    expect(find.text('Your friend gets \$20 on Gemini Carbon — Yes at 62%'),
        findsOneWidget);
    // The name waits for a tap: the card leads.
    final field = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('share-name-field')),
        matching: find.byType(EditableText)));
    expect(field.focusNode.hasFocus, isFalse);
    // The bar sends the prediction.
    expect(kuteBarPrimaryWithText('Send prediction'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Create link'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('share-name-field')), 'Ana');
    await tester.pump();
    expect(find.text('ANA, A PREDICTION FOR YOU'), findsOneWidget);
    expect(find.text('Ana gets \$20 on Gemini Carbon — Yes at 62%'),
        findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Send prediction'));
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
    // The card's headline first, then the prediction.
    expect(
        shared.single,
        endsWith('Ana, I sent you a prediction on Kute: Yes on Gemini '
            'Carbon, \$20.00. Claim it: https://web.test/c/lnk_1'));
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

  testWidgets(
      "a candidate's own page: the link names the candidate, the card and "
      'the line the event behind it', (tester) async {
    await pumpShareWidget(
        tester,
        env,
        const SendToAnyoneSheet(
          kind: ShareLinkKind.dollars,
          marketSlug: 'presidential-election-winner-2028',
          marketTitle: 'Jon Ossoff',
          venue: 'polymarket',
          outcome: 'Jon Ossoff',
          side: 'buy',
          amountMinor: 500,
        ),
        cardVenues: false,
        overrides: [
          polymarketEventDetailsProvider
              .overrideWith((ref, slug) async => _election),
        ]);
    // The card names the event; the candidate is the chance and the side
    // (a gift: the amount, then "Yes · Jon Ossoff to win").
    expect(find.text('Chance of Jon Ossoff'), findsOneWidget);
    expect(find.text('Yes · Jon Ossoff to win'), findsOneWidget);
    expect(
        find.text('Your friend gets \$5 on Presidential Election Winner '
            '2028 — Jon Ossoff at 21%'),
        findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Send prediction'));
    await settle(tester);
    expect(env.fake.calls.single.$2['outcome'], 'Jon Ossoff');
    // The row and its message name the event, not the candidate twice.
    expect(ShareLinksStore.byId('lnk_1')!.marketTitle,
        'Presidential Election Winner 2028');
  });

  testWidgets('an investment from its slip says an investment',
      (tester) async {
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
          amountMinor: 500,
        ));
    expect(find.text('Send this investment'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-send_investment')),
        findsOneWidget);
    expect(find.text('AN INVESTMENT FOR YOU'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-card-number')))
            .data,
        r'$5');
    expect(find.text('Long Bitcoin'), findsOneWidget);
    expect(find.text(r'Your friend gets $5 on Bitcoin — Long'), findsOneWidget);
    // No dare on an investment.
    expect(find.byKey(const ValueKey('share-challenge-toggle')), findsNothing);
    await tester.tap(kuteBarPrimaryWithText('Send investment'));
    await settle(tester);
    await shareCardAndWait(tester, shared);
    expect(env.fake.calls.single.$2['side'], 'long');
    expect(env.fake.calls.single.$2['amountMinor'], 500);
    expect(env.fake.calls.single.$2.containsKey('outcomeIndex'), isFalse);
    expect(
        shared.single,
        'I sent you an investment on Kute: Long on BTC, \$5.00. '
        'Claim it: https://web.test/c/lnk_1');
  });

  for (final size in const [Size(375, 667), Size(402, 874)]) {
    testWidgets(
        'the last step with the keyboard up at ${size.width.round()} x '
        '${size.height.round()}: nothing overflows, the field and the '
        'switch scroll into view', (tester) async {
      await pumpShareWidget(
        tester,
        env,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showSendToAnyoneSheet(
                context,
                kind: ShareLinkKind.dollars,
                marketSlug: 'gemini-carbon',
                marketTitle: 'Gemini Carbon',
                venue: 'polymarket',
                outcome: 'Yes',
                outcomeIndex: 0,
                side: 'buy',
                amountMinor: 500,
                entrySource: 'test',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      tester.view.physicalSize = size;
      await tester.pump();
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // The keyboard up (an iPhone's, with its suggestion row), the name
      // field focused.
      tester.view.viewInsets =
          FakeViewPadding(bottom: size.height < 700 ? 260 : 336);
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(find.byKey(const ValueKey('share-name-field')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byKey(const ValueKey('share-name-field')), 'Ana');
      await settle(tester);
      expect(tester.takeException(), isNull);
      // The field sits above the keyboard and clear of the bar riding on
      // it.
      final fieldBox =
          tester.getRect(find.byKey(const ValueKey('share-name-field')));
      final keyboardTop = size.height - (size.height < 700 ? 260 : 336);
      final bar = tester.getRect(kuteBarPrimaryWithText('Send prediction'));
      expect(fieldBox.bottom, lessThanOrEqualTo(bar.top + 1));
      expect(bar.bottom, lessThanOrEqualTo(keyboardTop));
      // The switch scrolls into view too.
      await tester.dragUntilVisible(
          find.byKey(const ValueKey('share-challenge-toggle')),
          find.byKey(const ValueKey('send-to-anyone-scroll')),
          const Offset(0, -80));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets(
      'a bitcoin link\'s amount step is the Send amount step: sats by '
      'default (the sats pill that opens the unit sheet), the ₿ figure, the '
      'dollars under it with the ⇅ swap, "328,686 sats available · '
      '\$328.69", 25% · 50% · 100%; the sats typed are the link\'s',
      (tester) async {
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.bitcoin),
        overrides: _bitcoinWallet());
    expect(tester.takeException(), isNull);
    // The Send's pieces, in sats.
    expect(find.byType(SendBitcoinAmountHero), findsOneWidget);
    final pill = tester.widget<SendAmountUnitPill>(
        find.byKey(const ValueKey('share-amount-unit')));
    expect(pill.code, 'Sats');
    expect(pill.onTap, isNotNull);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('share-amount-unit')),
            matching: find.byIcon(Icons.expand_more_rounded)),
        findsOneWidget);
    expect(find.text('328,686 sats available · \$328.69'), findsOneWidget);
    expect(find.byType(SendAmountConversionLine), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
    for (final p in ['25%', '50%', '100%']) {
      expect(find.text(p), findsOneWidget);
    }
    // The old dollar-typed figure with a "₿ USD" chip is gone.
    expect(find.byType(SendTypedAmountHero), findsNothing);

    // 5,000 sats typed: the figure, and $5.00 under it.
    await _keys(tester, '5000');
    expect(
        tester.widget<SendBitcoinAmountHero>(
            find.byType(SendBitcoinAmountHero)).digits,
        '5000');
    expect(find.text('\$5.00'), findsOneWidget);

    // ⇅: the same amount in dollars, the sats under it; and back.
    await tester.tap(find.byKey(const ValueKey('send-amount-swap')));
    await settle(tester);
    expect(find.byType(SendBitcoinAmountHero), findsNothing);
    expect(
        tester.widget<SendTypedAmountHero>(find.byType(SendTypedAmountHero))
            .typed,
        '5.00');
    expect(find.text('₿5,000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-amount-swap')));
    await settle(tester);
    expect(
        tester.widget<SendBitcoinAmountHero>(
            find.byType(SendBitcoinAmountHero)).digits,
        '5000');

    // 50% of the spending bitcoin; 100% is all of it.
    await tester.tap(find.text('50%'));
    await settle(tester);
    expect(
        tester.widget<SendBitcoinAmountHero>(
            find.byType(SendBitcoinAmountHero)).digits,
        '164343');
    await tester.tap(find.text('100%'));
    await settle(tester);
    expect(
        tester.widget<SendBitcoinAmountHero>(
            find.byType(SendBitcoinAmountHero)).digits,
        '328686');
    expect(find.byKey(const ValueKey('send-amount-warning')), findsNothing);

    // One more digit: more than there is, red, and Continue stays off.
    await _keys(tester, '0');
    expect(find.byKey(const ValueKey('send-amount-warning')), findsOneWidget);
    expect(find.text('That is more than you have available.'), findsOneWidget);
    expect(
        tester
            .widget<SendBitcoinAmountHero>(find.byType(SendBitcoinAmountHero))
            .overBalance,
        isTrue);
    expect(kuteBarPrimaryEnabled(tester), isFalse);
    expect(kuteBarPrimaryWithText('Lower the amount'), findsOneWidget);

    // Back under it: the sats typed are the link's.
    await tester.tap(find.text('50%'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Continue'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);
    expect(env.fake.calls.single.$2['kind'], 'bitcoin');
    expect(env.fake.calls.single.$2['amountMinor'], 164343);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the unit pill opens the Send\'s unit sheet; a dollar figure typed '
      'there goes on the link as its sats', (tester) async {
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.bitcoin),
        overrides: _bitcoinWallet());
    await tester.tap(find.byKey(const ValueKey('share-amount-unit')));
    await settle(tester);
    expect(find.text('USD'), findsWidgets);
    await tester.tap(find.text('USD').last);
    await settle(tester);
    expect(
        tester
            .widget<SendAmountUnitPill>(
                find.byKey(const ValueKey('share-amount-unit')))
            .code,
        'USD');
    await _keys(tester, '12');
    expect(find.text('₿12,000'), findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Continue'));
    await settle(tester);
    await tester.tap(kuteBarPrimaryWithText('Create link'));
    await settle(tester);
    expect(env.fake.calls.single.$2['amountMinor'], 12000);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a dollar link keeps dollars only: the USD pill names the unit (no '
      'sheet), "\$40.00 available", no ⇅; 100% is the balance and over it '
      'is red with Continue off', (tester) async {
    await pumpShareWidget(
        tester, env, const SendToAnyoneSheet(kind: ShareLinkKind.dollars),
        dollars: 40);
    final pill = tester.widget<SendAmountUnitPill>(
        find.byType(SendAmountUnitPill));
    expect(pill.code, 'USD');
    expect(pill.onTap, isNull);
    expect(find.text('\$40.00 available'), findsOneWidget);
    expect(find.byType(SendAmountConversionLine), findsNothing);
    expect(find.byType(SendBitcoinAmountHero), findsNothing);
    // Over the balance: red, and Continue stays off.
    await _keys(tester, '45');
    expect(find.byKey(const ValueKey('send-amount-warning')), findsOneWidget);
    expect(
        tester.widget<SendTypedAmountHero>(find.byType(SendTypedAmountHero))
            .overBalance,
        isTrue);
    expect(kuteBarPrimaryEnabled(tester), isFalse);
    // 100%: the whole balance, to the cent.
    await tester.tap(find.text('100%'));
    await settle(tester);
    expect(
        tester.widget<SendTypedAmountHero>(find.byType(SendTypedAmountHero))
            .typed,
        '40.00');
    expect(find.byKey(const ValueKey('send-amount-warning')), findsNothing);
    expect(kuteBarPrimaryEnabled(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the bitcoin amount step at 375 x 667: nothing overflows, the keypad '
      'and the percent row on screen', (tester) async {
    await pumpShareWidget(
      tester,
      env,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showSendToAnyoneSheet(context,
                kind: ShareLinkKind.bitcoin, entrySource: 'test'),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: _bitcoinWallet(),
    );
    tester.view.physicalSize = const Size(375, 667);
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await _keys(tester, '1234567');
    expect(tester.takeException(), isNull);
    expect(find.text('100%'), findsOneWidget);
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
