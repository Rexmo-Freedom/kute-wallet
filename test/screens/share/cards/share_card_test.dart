// The share card family (cards/), restrained premium: each card is one
// solid background, the caps line, the identity row, ONE huge number
// (sized to its width, never overflowing) with its fact line, at most one
// graphic, one plain line, the edgy line built from the card's figures,
// and the footer (Sal's small mark, the wordmark, the code); no chip, no
// bubble, no headline on the image. The three bands leave no large empty
// gap. The headline follows the market's topic and the locale's numbers
// and leads the share message (the edgy line is on the card only); the
// right card is chosen per entry point, every card lays out in German and
// Japanese, and a pending link's Share again shows the card first and
// hands the OS the PNG.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_de.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
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
                      title: 'Gold',
                      coin: 'GOLD',
                      category: 'commodities',
                      price: 2410))!
              .text,
          r'Gold at $2,410.00 an ounce');
      expect(
          investmentHeadline(
                  _en,
                  const InvestmentCardData(
                      title: 'OpenAI',
                      coin: 'OAI',
                      category: 'preipo',
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
              question: 'Q',
              outcome: outcome,
              chance: c,
              binary: binary,
              topic: t);
      expect(predictionHeadline(_en, p(ShareCardTopic.crypto))!.text,
          '18% odds it happens');
      expect(
          predictionHeadline(
                  _en,
                  p(ShareCardTopic.economy,
                      outcome: '25 bps cut', binary: false, c: 71))!
              .text,
          '71% chance of 25 bps cut');
      expect(predictionHeadline(_en, p(ShareCardTopic.other, c: 47))!.text,
          '47% say yes');
      expect(
          predictionHeadline(
                  _en, p(ShareCardTopic.other, outcome: 'No', c: 60))!
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
              _en, const PredictionCardData(question: 'Q', outcome: 'Yes')),
          isNull);
    });
  });

  group('the card per entry point', () {
    test('a link: money without a pick, the pick\'s card with one', () {
      final money = shareCardForLink(_noWatch,
          locale: 'en',
          kind: ShareLinkKind.dollars,
          amountMinor: 1000,
          recipient: 'Ana');
      expect(money, isA<MoneyCardData>());
      expect((money as MoneyCardData).amount, r'$10.00');
      final btc = shareCardForLink(_noWatch,
          locale: 'en',
          kind: ShareLinkKind.bitcoin,
          amountMinor: 12000,
          bitcoinAmount: '₿12,000',
          bitcoinFiat: r'$9.40');
      expect(btc, isA<MoneyCardData>());
      expect((btc as MoneyCardData).bitcoin, isTrue);
      expect(btc.amountSub, r'$9.40');
    });

    testWidgets(
        'the market sheet: the actual stock on Investing, the odds '
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
      expect(find.text('INVESTING'), findsOneWidget);
    });

    testWidgets('a link with a pick, from the providers\' fallbacks',
        (tester) async {
      late ShareCardData pick;
      late ShareCardData invest;
      await pumpShareWidget(tester, env, Consumer(builder: (context, ref, _) {
        pick = shareCardForLink(<T>(p) => ref.watch(p),
            locale: 'en',
            kind: ShareLinkKind.dollars,
            amountMinor: 1000,
            marketSlug: 'lol-worlds',
            marketTitle: 'LoL Worlds',
            venue: 'polymarket',
            outcome: 'Gen.G');
        invest = shareCardForLink(<T>(p) => ref.watch(p),
            locale: 'en',
            kind: ShareLinkKind.dollars,
            amountMinor: 2550,
            marketSlug: 'TSLA',
            marketTitle: 'Tesla',
            venue: 'hyperliquid',
            outcome: 'Short');
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
    Future<void> pumpIn(
        WidgetTester tester, ShareCardData data, Locale locale) async {
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

    String textOf(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    Color background(WidgetTester tester) => (tester
            .widget<DecoratedBox>(find.byKey(const ValueKey('share-card-bg')))
            .decoration as BoxDecoration)
        .color!;

    /// What every card shares: one solid background (no gradient), one
    /// big number, the footer's mark and wordmark, and none of the old
    /// chrome (chips, bubbles, pills, headline, Sal's poses).
    void expectRestrained(WidgetTester tester, {required bool code}) {
      final box = tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('share-card-bg')))
          .decoration as BoxDecoration;
      expect(box.gradient, isNull);
      expect(find.byKey(const ValueKey('share-card-number')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-mark')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-wordmark')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-code')),
          code ? findsOneWidget : findsNothing);
      if (code) {
        expect(find.text('CODE $kShareTestCode'), findsOneWidget);
      }
      for (final gone in const [
        'share-card-chip',
        'share-card-line',
        'share-card-headline',
        'share-card-pick',
        'share-card-change',
        'share-card-side',
        'share-card-amount-sub',
      ]) {
        expect(find.byKey(ValueKey(gone)), findsNothing, reason: gone);
      }
      expect(find.byType(RawImage), findsNothing, reason: 'no Sal pose');
      for (final cta in const [
        'Claim on Kute',
        'Trade it on Kute',
        'Place it on Kute',
        'Beat me on Kute',
        'Join me on Kute',
      ]) {
        expect(find.text(cta), findsNothing, reason: cta);
      }
    }

    testWidgets(
        'money: FOR DANIEL, the value huge and centred, in bitcoin under '
        'it, the ₿ watermark, the edgy line, Claim it on Kute', (tester) async {
      await pumpIn(tester, fakeBitcoinCard(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(textOf(tester, 'share-card-caps'), 'FOR DANIEL');
      expect(textOf(tester, 'share-card-number'), r'$9.40');
      expect(textOf(tester, 'share-card-fact'), 'in bitcoin · ₿12,000');
      expect(find.byKey(const ValueKey('share-card-graphic')), findsNothing);
      expect(background(tester), ShareCardPalette.dark.background);
      // Each figure once.
      expect(find.textContaining('₿12,000'), findsOneWidget);
      // Centred across the card.
      final number =
          tester.getCenter(find.byKey(const ValueKey('share-card-number')));
      expect(number.dx, closeTo(kShareCardSize.width / 2, 1));
      // The asset's mark, huge and faint, at the bottom right.
      final mark = tester
          .widget<Text>(find.byKey(const ValueKey('share-card-watermark')));
      expect(mark.data, '₿');
      expect(mark.style!.color!.a, closeTo(0.04, 0.005));
      expect(mark.style!.fontSize! / kShareCardSize.height,
          greaterThanOrEqualTo(0.7));
      expect(textOf(tester, 'share-card-edge'),
          isIn(shareCardEdges(_en, fakeBitcoinCard())));
      expect(textOf(tester, 'share-card-quiet'), 'Claim it on Kute');
    });

    testWidgets('dollars: the amount huge, no fact, the \$ watermark',
        (tester) async {
      await pumpIn(tester, fakeDollarsCard(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(textOf(tester, 'share-card-caps'), 'FOR ANA');
      expect(textOf(tester, 'share-card-number'), r'$10.00');
      expect(find.byKey(const ValueKey('share-card-fact')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-graphic')), findsNothing);
      expect(textOf(tester, 'share-card-watermark'), r'$');
    });

    testWidgets(
        'a prediction pick: white, the question, the chance big, the odds '
        'bar with both outcomes, the amount on the pick', (tester) async {
      await pumpIn(tester, fakePredictionPick(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(background(tester), ShareCardPalette.light.background);
      expect(textOf(tester, 'share-card-caps'), 'ANA, A PICK FOR YOU');
      expect(find.text('LoL Worlds 2026 Final: Gen.G vs T1'), findsOneWidget);
      expect(textOf(tester, 'share-card-number'), '47%');
      expect(textOf(tester, 'share-card-fact'), 'Chance of Gen.G');
      expect(find.byKey(const ValueKey('share-card-odds')), findsOneWidget);
      // Both sides named, each with its own percent.
      expect(find.text('Gen.G'), findsWidgets);
      expect(find.text(' 47%'), findsOneWidget);
      expect(find.text('T1'), findsOneWidget);
      expect(find.text(' 53%'), findsOneWidget);
      expect(
          tester
              .getSize(find.byKey(const ValueKey('share-card-odds-bar')))
              .height,
          ShareCardOddsBar.barHeight);
      expect(textOf(tester, 'share-card-plain'), r'$10 on Gen.G');
      // The chance at its largest.
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('share-card-number')))
              .style!
              .fontSize,
          kShareCardHeroMax);
      // The line is the stock card's graphic, never a second one here.
      expect(find.byKey(const ValueKey('share-card-chart')), findsNothing);
    });

    testWidgets(
        'a stock pick: logo, name, ticker, the price big, today in '
        'colour, the line, Long · amount', (tester) async {
      await pumpIn(tester, fakeTeslaPick(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(background(tester), ShareCardPalette.dark.background);
      expect(textOf(tester, 'share-card-caps'), 'ANA, A PICK FOR YOU');
      expect(find.text('Tesla'), findsOneWidget);
      expect(find.text('TSLA'), findsOneWidget);
      expect(textOf(tester, 'share-card-number'), r'$242.10');
      expect(textOf(tester, 'share-card-fact'), '+3.4% today');
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('share-card-fact')))
              .style!
              .color,
          ShareCardPalette.dark.up);
      expect(find.byKey(const ValueKey('share-card-chart')), findsOneWidget);
      expect(textOf(tester, 'share-card-plain'), r'Long · $25');
      expect(find.text('Long'), findsNothing, reason: 'the side once');
      expect(textOf(tester, 'share-card-edge'),
          'Some of us buy before the headlines.');
      // The logo is the real coin icon, 36.
      expect(tester.getSize(find.byKey(const ValueKey('share-card-logo'))),
          const Size.square(kShareLogoSize));
      expect(
          find.byKey(const ValueKey('share-card-logo-coin')), findsOneWidget);
    });

    testWidgets('a prediction market: the venue on top, no pick line',
        (tester) async {
      await pumpIn(tester, fakePredictionMarket(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(textOf(tester, 'share-card-caps'), 'PREDICTIONS');
      expect(textOf(tester, 'share-card-number'), '41%');
      expect(find.byKey(const ValueKey('share-card-plain')), findsNothing);
    });

    testWidgets('the claim hero: a friend sent you, tap claim, no code',
        (tester) async {
      await pumpIn(tester, fakeBitcoinCard().asRecipient(), const Locale('en'));
      expectRestrained(tester, code: false);
      expect(textOf(tester, 'share-card-caps'), 'DANIEL, A FRIEND SENT YOU');
      expect(textOf(tester, 'share-card-quiet'), "It's yours. Tap claim.");
    });

    testWidgets('missing data is left out', (tester) async {
      await pumpIn(
          tester,
          const InvestmentCardData(title: 'Tesla', coin: 'TSLA'),
          const Locale('en'));
      expect(find.byKey(const ValueKey('share-card-number')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-fact')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-chart')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-mark')), findsOneWidget);
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
          fakeBitcoinCard().asRecipient(),
          fakePredictionPick().asRecipient(),
          fakeTeslaPick().asRecipient(),
        ]) {
          await pumpIn(tester, data, locale);
          expect(tester.takeException(), isNull,
              reason: '${data.kind} overflowed in ${locale.languageCode}');
        }
      });
    }
  });

  group('layout', () {
    Future<void> pump(WidgetTester tester, ShareCardData data) async {
      await tester.runAsync(loadShareCardFonts);
      await pumpShareWidget(tester, env,
          Align(alignment: Alignment.topLeft, child: ShareCard(data: data)));
    }

    testWidgets(
        'the hero number: 80 short, 72, 64 long, shrunk to fit, '
        'never under 48', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      const w = 312.0;
      expect(shareCardHeroSize('47%', w), kShareCardHeroMax);
      expect(shareCardHeroSize(r'$242.10', w), 72);
      expect(shareCardHeroSize(r'+$412.35', w), 64);
      final long = shareCardHeroSize(r'$1,234,567.89', w);
      expect(long, lessThan(64));
      expect(long, greaterThanOrEqualTo(kShareCardHeroMin));
      expect(shareCardHeroSize(r'$1,234,567,890,123.45', w), kShareCardHeroMin);
    });

    testWidgets('a long amount never overflows the card', (tester) async {
      for (final amount in [
        r'$1,234,567.89',
        r'$1,234,567,890,123.45',
        '₿2,100,000,000,000,000',
      ]) {
        await pump(
            tester,
            MoneyCardData(
                bitcoin: false,
                amount: amount,
                recipient: 'Daniel',
                referralCode: kShareTestCode));
        expect(tester.takeException(), isNull, reason: amount);
        final r =
            tester.getRect(find.byKey(const ValueKey('share-card-number')));
        expect(r.left, greaterThanOrEqualTo(kShareCardPadding - 0.5),
            reason: amount);
        expect(r.right,
            lessThanOrEqualTo(kShareCardSize.width - kShareCardPadding + 0.5),
            reason: amount);
      }
    });

    // The card's bands top to bottom: no gap between two of them over 15%
    // of the card, and a centred hero sits mid-way in its band.
    List<Rect> bands(WidgetTester tester, String prefix) {
      final all = [
        for (final k in const [
          'caps',
          'identity',
          'hero',
          'graphic',
          'plain',
          'edge',
          'quiet',
          'footer',
        ])
          if (find.byKey(ValueKey('$prefix-$k')).evaluate().isNotEmpty)
            tester.getRect(find.byKey(ValueKey('$prefix-$k'))),
      ];
      // A part inside another (the plain fact in the hero) is no band.
      return [
        for (final r in all)
          if (!all.any(
              (o) => o != r && o.contains(r.center) && o.height > r.height))
            r
      ];
    }

    void expectBalanced(WidgetTester tester, String name,
        {String prefix = 'share-card'}) {
      final rects = bands(tester, prefix);
      for (var i = 1; i < rects.length; i++) {
        final gap = rects[i].top - rects[i - 1].bottom;
        expect(gap, lessThanOrEqualTo(kShareCardSize.height * 0.15),
            reason: '$name: gap $i is ${gap.toStringAsFixed(1)}');
        expect(gap, greaterThanOrEqualTo(0), reason: '$name: overlap at $i');
      }
      expect(rects.last.bottom,
          closeTo(kShareCardSize.height - kShareCardPadding, 1),
          reason: '$name: the footer on the bottom edge');
    }

    testWidgets('stock: the chart fills the bottom band, nothing empty',
        (tester) async {
      await pump(tester, fakeTeslaPick());
      expectBalanced(tester, 'stock');
      final chart =
          tester.getRect(find.byKey(const ValueKey('share-card-chart')));
      expect(chart.height, greaterThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'prediction: the hero centred between the identity and the '
        'odds, nothing empty', (tester) async {
      for (final data in [fakePredictionPick(), fakePredictionMarket()]) {
        await pump(tester, data);
        expectBalanced(tester, data.kind);
        final above =
            tester.getRect(find.byKey(const ValueKey('share-card-identity')));
        final hero =
            tester.getRect(find.byKey(const ValueKey('share-card-hero')));
        final below =
            tester.getRect(find.byKey(const ValueKey('share-card-graphic')));
        expect(hero.top - above.bottom, closeTo(below.top - hero.bottom, 1),
            reason: data.kind);
      }
    });

    testWidgets('money: the watermark fills the space the hero leaves',
        (tester) async {
      for (final data in [fakeBitcoinCard(), fakeDollarsCard()]) {
        await pump(tester, data);
        final mark =
            tester.getRect(find.byKey(const ValueKey('share-card-watermark')));
        // Clipped at the card's bottom right, about 70% of its height.
        final visible = mark.intersect(Offset.zero & kShareCardSize);
        expect(
            visible.height, greaterThanOrEqualTo(kShareCardSize.height * 0.6),
            reason: data.kind);
        expect(visible.right, closeTo(kShareCardSize.width, 0.5));
        expect(visible.bottom, closeTo(kShareCardSize.height, 0.5));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('edgy line', () {
    test('built from the card\'s own figures, a pool per sign and topic', () {
      // A stock up: today's change interpolated, the name.
      expect(shareCardEdges(_en, fakeTeslaPick()), [
        'Some of us buy before the headlines.',
        "Up 3.4%. You're welcome.",
        'Told you Tesla.',
      ]);
      // Down.
      expect(shareCardEdges(_en, fakeNasdaqMarket()),
          ['Discount, not disaster.', 'Buying while you panic.']);
      // No change known.
      expect(
          shareCardEdges(
              _en, const InvestmentCardData(title: 'Crude oil', price: 102.5)),
          ['Some of us buy before the headlines.', 'Patience is a position.']);
      // A sports pick under 50%: early, the crowd, the dare, the team.
      expect(shareCardEdges(_en, fakePredictionPick()), [
        "47% says I'm early, not wrong.",
        'The crowd is 53% wrong.',
        'Bet against me. I dare you.',
        'Gen.G or bust.',
      ]);
      // Politics.
      expect(shareCardEdges(_en, fakePredictionMarket()),
          contains('Polls are opinions. This is money.'));
      // Money: bitcoin has its own.
      expect(shareCardEdges(_en, fakeBitcoinCard()), [
        "Spend it wisely. Or don't.",
        'Consider this a flex.',
        'Free bitcoin. Rare sight.',
      ]);
      expect(shareCardEdges(_en, fakeDollarsCard()),
          ["Spend it wisely. Or don't.", 'Consider this a flex.']);
      // German numbers.
      expect(shareCardEdges(_de, fakeTeslaPick())[1], contains('3,4'));
    });

    test('the seed picks one, any int', () {
      final pool = shareCardEdges(_en, fakeTeslaPick());
      expect(
          {for (var i = 0; i < 9; i++) shareCardEdge(_en, fakeTeslaPick(), i)},
          pool.toSet());
      expect(shareCardEdge(_en, fakeTeslaPick(), -7), isIn(pool));
    });

    testWidgets('the card draws the seed\'s line, 20 w600, two lines at most',
        (tester) async {
      await tester.runAsync(loadShareCardFonts);
      await pumpShareWidget(
          tester,
          env,
          Align(
              alignment: Alignment.topLeft,
              child: ShareCard(data: fakeTeslaPick(), lineSeed: 1)));
      final t =
          tester.widget<Text>(find.byKey(const ValueKey('share-card-edge')));
      expect(t.data, "Up 3.4%. You're welcome.");
      expect(t.style!.fontSize, kShareCardLineSize);
      expect(t.style!.fontWeight, FontWeight.w600);
      expect(t.maxLines, 2);
    });
  });

  group('share message', () {
    test(
        'the headline first, then the text and link; the edgy line is on '
        'the card, never repeated', () {
      expect(
          shareCardMessage(_en, fakeTeslaPick(), 'Look https://x.test'),
          'Tesla is \$242.10, up 3.4% today\n'
          'Look https://x.test');
      expect(
          shareCardMessage(_en, fakePredictionPick(), 'Pick https://x.test')
              .split('\n'),
          ['Gen.G are 47% favourites vs T1', 'Pick https://x.test']);
    });

    test('money: no headline, the text alone', () {
      expect(
          shareCardMessage(_en, fakeDollarsCard(), 'I sent you'), 'I sent you');
    });

    test('no figure: no headline, never estimated', () {
      expect(
          shareCardMessage(
              _en, const InvestmentCardData(title: 'Tesla', coin: 'TSLA'), 'T'),
          'T');
    });
  });

  testWidgets(
      'pending link: Share again shows the card, Share hands the OS '
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
    expect(
        find.byKey(const ValueKey('share-card-send_dollars')), findsOneWidget);
    expect(sent, isEmpty);
    await shareCardAndWait(tester, sent,
        button: kuteBarPrimaryWithText('Share'));
    final (image, text) = sent.single;
    expect(image.mimeType, 'image/png');
    final bytes = await tester.runAsync(image.readAsBytes) as Uint8List;
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(
        text,
        'Ana, I sent you \$10.00 with Kute. Claim it here: '
        'https://web.test/c/lnk_3');
    expect(env.paramsOf('share_link_shared').single,
        {'kind': 'dollars', 'result': 'success'});
  });
}
