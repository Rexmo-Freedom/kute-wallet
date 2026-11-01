// The share card family (cards/): each card draws its data, the
// headline follows the market's topic and the locale's numbers, the
// right card is chosen per entry point, every card lays out in German
// and Japanese, and a pending link's Share again shows the card first
// and hands the OS the PNG.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_de.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart';
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/share/share_market_sheet.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../../helpers/kute_bar_test_support.dart';
import '../share_test_harness.dart';
import 'share_card_fixtures.dart';
import 'share_card_test_fonts.dart';

final _en = AppLocalizationsEn();
final _de = AppLocalizationsDe();

T _noWatch<T>(Object _) => throw StateError('no providers here');

void main() {
  late ShareTestEnv env;

  setUp(() => env = setUpShareTest());
  tearDown(tearDownShareTest);

  group('headlines', () {
    test('a stock: the price and today\'s change, in the locale', () {
      final h = investmentHeadline(_en, fakeTeslaPick())!;
      expect(h.text, r'Tesla is $242.10, up 3.4% today');
      expect(h.emphasis, [r'$242.10', '3.4%']);
      final de = investmentHeadline(_de, fakeTeslaPick())!;
      expect(de.emphasis.first, contains('242,10'));
      expect(investmentHeadline(_en, fakeNasdaqMarket())!.text,
          r'Nasdaq 100 is $21,483.50, down 0.6% today');
    });

    test('oil by the barrel, gold by the ounce, pre-IPO implied', () {
      expect(investmentHeadline(_en, fakeOilMarket())!.text,
          r'Crude oil at $102.50 a barrel');
      expect(
          investmentHeadline(
                  _en,
                  const InvestmentCardData(
                      title: 'Gold', coin: 'GOLD', category: 'commodities',
                      price: 2410))!
              .text,
          r'Gold at $2,410.00 an ounce');
      expect(
          investmentHeadline(
                  _en,
                  const InvestmentCardData(
                      title: 'OpenAI', coin: 'OAI', category: 'preipo',
                      price: 612.4))!
              .text,
          r'OpenAI trades at an implied $612.40');
    });

    test('no price: no headline (never estimated)', () {
      expect(
          investmentHeadline(
              _en, const InvestmentCardData(title: 'Tesla', coin: 'TSLA')),
          isNull);
    });

    test('predictions by topic, the market\'s odds', () {
      expect(predictionHeadline(_en, fakePredictionPick())!.text,
          'Gen.G are 47% favourites vs T1');
      expect(predictionHeadline(_en, fakePredictionMarket())!.text,
          'Markets give Lula a 41% chance');
      PredictionCardData p(ShareCardTopic t,
              {String outcome = 'Yes', bool binary = true, double c = 18}) =>
          PredictionCardData(
              question: 'Q', outcome: outcome, chance: c, binary: binary,
              topic: t);
      expect(predictionHeadline(_en, p(ShareCardTopic.crypto))!.text,
          '18% odds it happens');
      expect(
          predictionHeadline(_en,
                  p(ShareCardTopic.economy, outcome: '25 bps cut', binary: false, c: 71))!
              .text,
          '71% chance of 25 bps cut');
      expect(predictionHeadline(_en, p(ShareCardTopic.other, c: 47))!.text,
          '47% say yes');
      expect(
          predictionHeadline(_en, p(ShareCardTopic.other, outcome: 'No', c: 60))!
              .text,
          '60% say no');
      // The politics yes/no reads the Yes side even on a No pick.
      expect(
          predictionHeadline(
                  _en, p(ShareCardTopic.politics, outcome: 'No', c: 70))!
              .text,
          'Markets give it a 30% chance');
      expect(
          predictionHeadline(
                  _en, p(ShareCardTopic.other, outcome: 'Ana', binary: false))!
              .text,
          'Ana: 18% chance');
      expect(
          predictionHeadline(
              _en,
              const PredictionCardData(question: 'Q', outcome: 'Yes')),
          isNull);
    });
  });

  group('the card per entry point', () {
    test('a link: money without a pick, the pick\'s card with one', () {
      final money = shareCardForLink(_noWatch,
          locale: 'en', kind: ShareLinkKind.dollars, amountMinor: 1000,
          recipient: 'Ana');
      expect(money, isA<MoneyCardData>());
      expect((money as MoneyCardData).amount, r'$10.00');
      final btc = shareCardForLink(_noWatch,
          locale: 'en', kind: ShareLinkKind.bitcoin, amountMinor: 12000,
          bitcoinAmount: '₿12,000', bitcoinFiat: r'$9.40');
      expect(btc, isA<MoneyCardData>());
      expect((btc as MoneyCardData).bitcoin, isTrue);
      expect(btc.amountSub, r'$9.40');
    });

    testWidgets('the market sheet: the actual stock on Investing, the odds '
        'on Predictions', (tester) async {
      await pumpShareWidget(
          tester,
          env,
          const ShareMarketSheet(
            title: 'Tesla',
            subtitle: null,
            deepLink: 'https://web.test/m/investing/TSLA',
            marketSlug: 'TSLA',
            price: r'$242.10',
            venue: 'hyperliquid',
            ticker: 'TSLA',
          ));
      expect(find.byKey(const ValueKey('share-card-investment_market')),
          findsOneWidget);
      expect(find.text('Tesla'), findsOneWidget);
      expect(find.text('Trade it on Kute'), findsOneWidget);
    });

    testWidgets('a link with a pick, from the providers\' fallbacks',
        (tester) async {
      late ShareCardData pick;
      late ShareCardData invest;
      await pumpShareWidget(
          tester,
          env,
          Consumer(builder: (context, ref, _) {
            pick = shareCardForLink(<T>(p) => ref.watch(p),
                locale: 'en', kind: ShareLinkKind.dollars, amountMinor: 1000,
                marketSlug: 'lol-worlds', marketTitle: 'LoL Worlds',
                venue: 'polymarket', outcome: 'Gen.G');
            invest = shareCardForLink(<T>(p) => ref.watch(p),
                locale: 'en', kind: ShareLinkKind.dollars, amountMinor: 2550,
                marketSlug: 'TSLA', marketTitle: 'Tesla',
                venue: 'hyperliquid', outcome: 'Short');
            return const SizedBox();
          }));
      expect(pick, isA<PredictionCardData>());
      final p = pick as PredictionCardData;
      expect(p.picked, isTrue);
      expect(p.amount, r'$10');
      expect(p.outcome, 'Gen.G');
      expect(invest, isA<InvestmentCardData>());
      final i = invest as InvestmentCardData;
      expect(i.side, 'short');
      expect(i.amount, r'$25.50');
    });
  });

  group('cards', () {
    Future<void> pumpIn(WidgetTester tester, ShareCardData data,
        Locale locale) async {
      await tester.runAsync(loadShareCardFonts);
      await pumpShareWidget(
          tester,
          env,
          Builder(
              builder: (context) => Localizations.override(
                    context: context,
                    locale: locale,
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: ShareCard(data: data)),
                  )));
    }

    testWidgets('money: the line over the big amount and the claim chip',
        (tester) async {
      await pumpIn(tester, fakeBitcoinCard(), const Locale('en'));
      expect(find.text('Daniel, I sent you'), findsOneWidget);
      expect(find.text('₿12,000'), findsOneWidget);
      expect(find.text(r'$9.40'), findsOneWidget);
      expect(find.text('Claim on Kute'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-code')), findsOneWidget);
      expect(find.text('Join me on Kute'), findsOneWidget);
    });

    testWidgets('a prediction pick: question, headline, pill, amount, line',
        (tester) async {
      await pumpIn(tester, fakePredictionPick(), const Locale('en'));
      expect(find.text('LoL Worlds 2026 Final: Gen.G vs T1'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-headline')), findsOneWidget);
      expect(find.text('Gen.G · 47%'), findsOneWidget);
      expect(find.text(r'$10 on it'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-chart')), findsOneWidget);
      expect(find.text('Place it on Kute'), findsOneWidget);
      expect(find.text('Trust me on this one.'), findsOneWidget);
    });

    testWidgets('a stock: name, ticker, change pill, side, chart',
        (tester) async {
      await pumpIn(tester, fakeTeslaPick(), const Locale('en'));
      expect(find.text('Tesla'), findsOneWidget);
      expect(find.text('TSLA'), findsOneWidget);
      expect(find.text('+3.4% today'), findsOneWidget);
      expect(find.text('Long'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-chart')), findsOneWidget);
      expect(find.text('Trade it on Kute'), findsOneWidget);
    });

    testWidgets('a prediction market: no pick, make your call',
        (tester) async {
      await pumpIn(tester, fakePredictionMarket(), const Locale('en'));
      expect(find.byKey(const ValueKey('share-card-pick')), findsNothing);
      expect(find.text('Make your call on Kute'), findsOneWidget);
      expect(find.text('What do you think?'), findsOneWidget);
    });

    testWidgets('missing data is left out', (tester) async {
      await pumpIn(
          tester,
          const InvestmentCardData(title: 'Tesla', coin: 'TSLA'),
          const Locale('en'));
      expect(find.byKey(const ValueKey('share-card-headline')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-change')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-chart')), findsNothing);
    });

    for (final locale in const [Locale('de'), Locale('ja')]) {
      testWidgets('every card lays out in ${locale.languageCode}',
          (tester) async {
        for (final data in <ShareCardData>[
          fakeBitcoinCard(),
          fakeDollarsCard(),
          fakePredictionPick(),
          fakePredictionMarket(),
          fakeTeslaPick(),
          fakeNasdaqMarket(),
          fakeOilMarket(),
          fakeBitcoinCard().recipientCopy(),
          fakePredictionPick().recipientCopy(),
        ]) {
          await pumpIn(tester, data, locale);
          expect(tester.takeException(), isNull,
              reason: '${data.kind} overflowed in ${locale.languageCode}');
        }
      });
    }
  });

  testWidgets('pending link: Share again shows the card, Share hands the OS '
      'the PNG with the text', (tester) async {
    final sent = <(XFile, String)>[];
    ShareCardShare.debugSharer = (image, text) async {
      sent.add((image, text));
      return 'success';
    };
    final row = PendingShareLink(
      id: 'lnk_3',
      kind: ShareLinkKind.dollars,
      amountMinor: 1000,
      label: 'Ana',
      url: 'https://web.test/c/lnk_3',
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
    await tester.tap(kuteBarPrimaryWithText('Share again'));
    await settle(tester);
    expect(find.text('Your card is ready'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-card-send_dollars')),
        findsOneWidget);
    expect(sent, isEmpty);
    await shareCardAndWait(tester, sent,
        button: kuteBarPrimaryWithText('Share'));
    final (image, text) = sent.single;
    expect(image.mimeType, 'image/png');
    final bytes = await tester.runAsync(image.readAsBytes) as Uint8List;
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(text,
        r'Ana, I sent you $10.00 with Kute. Claim it here: https://web.test/c/lnk_3');
    expect(env.paramsOf('share_link_shared').single,
        {'kind': 'dollars', 'result': 'success'});
  });
}

extension on ShareCardData {
  /// The same card as the recipient's claim hero.
  ShareCardData recipientCopy() => switch (this) {
        final MoneyCardData d => MoneyCardData(
            bitcoin: d.bitcoin,
            amount: d.amount,
            amountSub: d.amountSub,
            recipient: d.recipient,
            audience: ShareCardAudience.recipient),
        final PredictionCardData d => PredictionCardData(
            question: d.question,
            outcome: d.outcome,
            chance: d.chance,
            binary: d.binary,
            topic: d.topic,
            opponent: d.opponent,
            picked: true,
            amount: d.amount,
            series: d.series,
            recipient: d.recipient,
            audience: ShareCardAudience.recipient),
        final InvestmentCardData d => d,
      };
}
