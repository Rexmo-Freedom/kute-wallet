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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_de.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider, polymarketMarketHistoryProvider;
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show kPolyOutcomeColors;
import 'package:kute/screens/polymarket/components/position_speedometer.dart'
    show PolySpeedometerNeedlePainter;
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_market_chart.dart';
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

  group("a market's chart from its real history", () {
    final event = PolymarketEvent(
      id: 'br',
      slug: 'brazil-presidential-election',
      title: 'Brazil Presidential Election',
      description: '',
      volume: 1000000,
      liquidity: 50000,
      category: 'politics',
      conditionId: '0xbr',
      endDate: DateTime.now().add(const Duration(days: 30)),
      outcomes: const [
        PolymarketOutcome(
            gammaMarketId: 'm1',
            name: 'Luiz Inácio Lula da Silva',
            price: 0.41,
            tokenId: 'lula'),
        PolymarketOutcome(
            gammaMarketId: 'm2',
            name: 'Flávio Bolsonaro',
            price: 0.35,
            tokenId: 'flavio'),
        PolymarketOutcome(
            gammaMarketId: 'm3',
            name: 'Ciro Gomes',
            price: 0.04,
            tokenId: 'ciro'),
      ],
    );
    final t0 = DateTime.utc(2026, 10, 3);
    List<PolymarketPricePoint> history(List<double> ps) => [
          for (var i = 0; i < ps.length; i++)
            PolymarketPricePoint(
                timestamp: t0.add(Duration(days: i)), price: ps[i]),
        ];

    /// The providers with [histories] by token, read once loaded.
    Future<ShareCardWatch> watcher(
        Map<String, List<PolymarketPricePoint>> histories) async {
      final container = ProviderContainer(overrides: [
        polymarketEventDetailsProvider
            .overrideWith((ref, slug) async => event),
        polymarketMarketHistoryProvider.overrideWith(
            (ref, key) async => histories[key.tokenId] ?? const []),
      ]);
      addTearDown(container.dispose);
      container.listen(polymarketEventDetailsProvider(event.slug), (_, __) {});
      await container.read(polymarketEventDetailsProvider(event.slug).future);
      for (final o in event.outcomes) {
        for (final range in const ['1w', '1m', 'max']) {
          final key = (tokenId: o.tokenId!, interval: range);
          container.listen(polymarketMarketHistoryProvider(key), (_, __) {});
          await container.read(polymarketMarketHistoryProvider(key).future);
        }
      }
      return <T>(ProviderListenable<T> p) => container.read(p);
    }

    test(
        'the page\'s top lines in its colours, the newest point at the '
        'price now; a third under 10% left out', () async {
      final watch = await watcher({
        'lula': history([0.33, 0.36, 0.40, 0.40]),
        'flavio': history([0.39, 0.37, 0.36, 0.36]),
        'ciro': history([0.05, 0.04, 0.04, 0.04]),
      });
      final card = predictionCardFor(watch,
          slug: event.slug, title: '', referralCode: kShareTestCode);
      expect(card.charted, isTrue);
      final lines = card.lines!;
      expect([for (final l in lines) l.name],
          ['Luiz Inácio Lula da Silva', 'Flávio Bolsonaro']);
      expect([for (final l in lines) l.color],
          [kPolyOutcomeColors[0], kPolyOutcomeColors[1]]);
      expect(lines[0].chance, closeTo(41, 1e-9));
      expect(lines[0].points.length, 4);
      expect(lines[0].points.first.p, 0.33);
      // Pinned to the price now, as the page pins its newest point.
      expect(lines[0].points.last.p, 0.41);
      expect(lines[0].points.first.t, t0.millisecondsSinceEpoch);
    });

    test('no history for a leading line: no chart (the speedometer)',
        () async {
      final watch = await watcher({
        'lula': history([0.33, 0.36, 0.40, 0.40]),
      });
      final card = predictionCardFor(watch,
          slug: event.slug, title: '', referralCode: kShareTestCode);
      expect(card.lines, isNull);
      expect(card.charted, isFalse);
    });

    test('a pick never reads the chart', () async {
      final watch = await watcher({
        'lula': history([0.33, 0.36, 0.40, 0.40]),
        'flavio': history([0.39, 0.37, 0.36, 0.36]),
      });
      final card = predictionCardFor(watch,
          slug: event.slug,
          title: '',
          outcome: 'Flávio Bolsonaro',
          picked: true,
          amount: r'$10');
      expect(card.lines, isNull);
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
    /// big number, Sal at the top right in his pose (the footer then has
    /// no small mark), the wordmark, and none of the old chrome (chips,
    /// bubbles, pills, headline).
    void expectRestrained(WidgetTester tester,
        {required bool code, bool number = true}) {
      final box = tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('share-card-bg')))
          .decoration as BoxDecoration;
      expect(box.gradient, isNull);
      expect(find.byKey(const ValueKey('share-card-number')),
          number ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('share-card-sal')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-mark')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-watermark')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-wordmark')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-code')),
          code ? findsOneWidget : findsNothing);
      if (code) {
        expect(find.text('CODE  $kShareTestCode', findRichText: true),
            findsOneWidget);
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
        'money: bitcoin on the app\'s ink, FOR DANIEL, the value huge in '
        'orange at the left, in bitcoin under it, Sal with the coin on the '
        'rule, the edgy line, Claim it on Kute',
        (tester) async {
      await pumpIn(tester, fakeBitcoinCard(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(textOf(tester, 'share-card-caps'), 'FOR DANIEL');
      expect(textOf(tester, 'share-card-number'), r'$9.40');
      expect(textOf(tester, 'share-card-fact'), 'in bitcoin · ₿12,000');
      expect(find.byKey(const ValueKey('share-card-graphic')), findsNothing);
      expect(background(tester), ShareCardPalette.bitcoinClaim.background);
      expect(shareCardPose(fakeBitcoinCard()), ShareCardPose.claim);
      // Each figure once.
      expect(find.textContaining('₿12,000'), findsOneWidget);
      // At the left, the same edge as every line on the card.
      final number =
          tester.getRect(find.byKey(const ValueKey('share-card-number')));
      expect(number.left, closeTo(kShareCardPadding, 1));
      // Sal standing on the rule at the right, his feet on it.
      final sal = tester.getRect(find.byKey(const ValueKey('share-card-sal')));
      final rule =
          tester.getRect(find.byKey(const ValueKey('share-card-rule')));
      expect(sal.width, kShareCardSalFloorSize);
      expect(sal.right, kShareCardSize.width - kShareCardSalFloorEnd);
      expect(sal.bottom, closeTo(rule.top + kShareCardSalFeet, 0.5));
      // No disc behind him: his own soft shadow on the ink.
      expect(find.byKey(const ValueKey('share-card-sal-plate')), findsNothing);
      expect(
          tester
              .widget<ShareCardSalStill>(
                  find.byKey(const ValueKey('share-card-sal')))
              .shadow,
          ShareCardPalette.bitcoinClaim.salShadow);
      expect(textOf(tester, 'share-card-edge'),
          isIn(shareCardEdges(_en, fakeBitcoinCard())));
      expect(textOf(tester, 'share-card-quiet'), 'Claim it on Kute');
    });

    testWidgets('dollars: green, the amount huge, no fact', (tester) async {
      await pumpIn(tester, fakeDollarsCard(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(textOf(tester, 'share-card-caps'), 'FOR ANA');
      expect(textOf(tester, 'share-card-number'), r'$10.00');
      expect(find.byKey(const ValueKey('share-card-fact')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-graphic')), findsNothing);
      expect(background(tester), ShareCardPalette.dollars.background);
      expect(find.byKey(const ValueKey('share-card-sal-plate')), findsNothing);
    });

    testWidgets(
        'a prediction pick: blue, the question, the speedometer with the '
        'chance big under its hub, the amount on the pick', (tester) async {
      await pumpIn(tester, fakePredictionPick(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(background(tester), ShareCardPalette.prediction.background);
      expect(shareCardPose(fakePredictionPick()), ShareCardPose.predict);
      // It says it is a prediction (founder, 5 November 2026).
      expect(textOf(tester, 'share-card-caps'), 'ANA, A PREDICTION FOR YOU');
      expect(find.text('LoL Worlds 2026 Final: Gen.G vs T1'), findsOneWidget);
      expect(textOf(tester, 'share-card-number'), '47%');
      expect(textOf(tester, 'share-card-fact'), 'Chance of Gen.G');
      expect(find.byKey(const ValueKey('share-card-odds')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-speedometer')),
          findsOneWidget);
      // The open-position screen's own painters, the needle at 47%.
      final needle = tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byKey(const ValueKey('share-card-odds')),
              matching: find.byType(CustomPaint)))
          .map((w) => w.painter)
          .whereType<PolySpeedometerNeedlePainter>()
          .single;
      expect(needle.needle.value, closeTo(0.47, 1e-9));
      expect(needle.color, ShareCardPalette.prediction.ink);
      // The figure under the hub.
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('share-card-number'))).dy,
          greaterThan(tester
              .getBottomLeft(find.byKey(const ValueKey('share-card-logo')))
              .dy));
      expect(textOf(tester, 'share-card-plain'), r'$10 on Gen.G');
      // What was sent, in big type, the full ink.
      final plain = tester.widget<Text>(
          find.byKey(const ValueKey('share-card-plain')));
      expect(plain.style!.fontSize, kShareCardPlainStrongSize);
      expect(plain.style!.fontWeight, FontWeight.w800);
      // The line is the stock card's graphic, never a second one here.
      expect(find.byKey(const ValueKey('share-card-chart')), findsNothing);
    });

    testWidgets(
        'a stock pick: logo, name, ticker, the price big, today in '
        'colour, the line, Long · amount', (tester) async {
      await pumpIn(tester, fakeTeslaPick(), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(background(tester), ShareCardPalette.investment.background);
      expect(shareCardPose(fakeTeslaPick()), ShareCardPose.win);
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
          ShareCardPalette.investment.up);
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

    testWidgets(
        'a prediction market: the venue on top, the market page\'s two '
        'lines, each labelled with its name and chance, no pick line',
        (tester) async {
      await pumpIn(tester, fakePredictionMarket(), const Locale('en'));
      expectRestrained(tester, code: true, number: false);
      expect(textOf(tester, 'share-card-caps'), 'PREDICTIONS');
      expect(find.byKey(const ValueKey('share-card-speedometer')),
          findsNothing);
      final paint = tester.widget<CustomPaint>(
          find.byKey(const ValueKey('share-card-market-chart')));
      final chart = paint.painter! as ShareCardMarketChartPainter;
      expect(chart.lines.length, 2);
      // Named as the page's tags name them: the surname-first short
      // names, the chances as the card writes them.
      expect(chart.names, ['Lula da Silva', 'Bolsonaro']);
      expect(chart.pcts, ['41%', '35%']);
      // The page's colours, lifted only as far as the blue needs.
      for (final c in chart.colors) {
        expect(shareCardContrast(c, ShareCardPalette.prediction.background),
            greaterThanOrEqualTo(kShareCardLineContrast));
      }
      expect(chart.colors[0], isNot(chart.colors[1]));
      expect(find.byKey(const ValueKey('share-card-plain')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a prediction market before its history is read: the speedometer, '
        'never a made-up line', (tester) async {
      await pumpIn(
          tester, fakePredictionMarket(chart: false), const Locale('en'));
      expectRestrained(tester, code: true);
      expect(textOf(tester, 'share-card-number'), '41%');
      expect(find.byKey(const ValueKey('share-card-speedometer')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-market-chart')),
          findsNothing);
    });

    testWidgets('a pick keeps the speedometer, lines or not', (tester) async {
      final m = fakePredictionMarket();
      final pick = PredictionCardData(
          question: m.question,
          outcome: m.outcome,
          chance: m.chance,
          binary: false,
          picked: true,
          amount: r'$10',
          lines: m.lines);
      expect(pick.charted, isFalse);
      await pumpIn(tester, pick, const Locale('en'));
      expect(find.byKey(const ValueKey('share-card-speedometer')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-market-chart')),
          findsNothing);
    });

    testWidgets('the claim hero: a friend sent you, tap claim, no code',
        (tester) async {
      await pumpIn(tester, fakeBitcoinCard().asRecipient(), const Locale('en'));
      expectRestrained(tester, code: false);
      expect(textOf(tester, 'share-card-caps'), 'DANIEL, A FRIEND SENT YOU');
      expect(textOf(tester, 'share-card-quiet'), "It's yours. Tap claim.");
      // Its own colour (founder: "just for this card"): the app's ink,
      // white text, the amount in the bitcoin orange; Sal with the coin
      // balanced on her head.
      expect(background(tester), ShareCardPalette.bitcoinClaim.background);
      expect(ShareCardPalette.bitcoinClaim.background,
          isNot(ShareCardPalette.bitcoin.background));
      expect(ShareCardPalette.bitcoinClaim.ink, const Color(0xFFFFFFFF));
      final number = tester
          .widget<Text>(find.byKey(const ValueKey('share-card-number')));
      expect(number.style!.color, ShareCardPalette.bitcoinClaim.hero);
      expect(
          tester
              .widget<ShareCardSalStill>(
                  find.byKey(const ValueKey('share-card-sal')))
              .pose,
          ShareCardPose.claim);
    });

    testWidgets(
        'the ink colour and the coin pose are every bitcoin send\'s: the '
        'send card and the claim hero; a dollars claim hero and the rest '
        'keep theirs',
        (tester) async {
      expect(
          shareCardPalette(fakeBitcoinCard()), ShareCardPalette.bitcoinClaim);
      expect(shareCardPalette(fakeDollarsCard().asRecipient()),
          ShareCardPalette.dollars);
      expect(shareCardPalette(fakePredictionPick().asRecipient()),
          ShareCardPalette.prediction);
      expect(shareCardPose(fakeBitcoinCard()), ShareCardPose.claim);
      expect(shareCardPose(fakeDollarsCard().asRecipient()),
          ShareCardPose.claim);
      expect(shareCardPose(fakeBitcoinCard().asRecipient()),
          ShareCardPose.claim);
      // The send card's amount is the orange hero too.
      await pumpIn(tester, fakeBitcoinCard(), const Locale('en'));
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('share-card-number')))
              .style!
              .color,
          ShareCardPalette.bitcoinClaim.hero);
    });

    testWidgets('missing data is left out', (tester) async {
      await pumpIn(
          tester,
          const InvestmentCardData(title: 'Tesla', coin: 'TSLA'),
          const Locale('en'));
      expect(find.byKey(const ValueKey('share-card-number')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-fact')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-chart')), findsNothing);
      expect(find.byKey(const ValueKey('share-card-sal')), findsOneWidget);
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

  group("Sal's pose", () {
    test(
        'by the card: the briefcase on a dollars send, the coin on her head '
        "on every bitcoin send, weighing a prediction, a stock by today's "
        'change', () {
      expect(shareCardPose(fakeBitcoinCard()), ShareCardPose.claim);
      expect(shareCardPose(fakeDollarsCard()), ShareCardPose.claim);
      expect(shareCardPose(fakePredictionPick()), ShareCardPose.predict);
      expect(shareCardPose(fakePredictionMarket()), ShareCardPose.predict);
      InvestmentCardData stock(double? change) => InvestmentCardData(
            title: 'Tesla',
            ticker: 'TSLA',
            coin: 'TSLA',
            price: 242.1,
            change: change,
          );
      expect(shareCardPose(stock(0.034)), ShareCardPose.win);
      expect(shareCardPose(stock(kShareCardBigChange)), ShareCardPose.bigWin);
      expect(shareCardPose(stock(0.25)), ShareCardPose.bigWin);
      expect(shareCardPose(stock(-0.034)), ShareCardPose.loss);
      expect(shareCardPose(stock(0.0001)), ShareCardPose.flat);
      expect(shareCardPose(stock(null)), ShareCardPose.flat);
    });

    test('every pose is a purpose-made still in the manifest card group',
        () {
      final m = jsonDecode(File('lib/assets/sal/manifest.json')
          .readAsStringSync()) as Map<String, dynamic>;
      final cards = m.entries
          .where((e) => (e.value as Map)['group'] == 'card')
          .map((e) => e.key)
          .toSet();
      expect(cards, {for (final p in ShareCardPose.values) p.clip});
      for (final p in ShareCardPose.values) {
        final files = (m[p.clip] as Map)['files'] as Map;
        for (final f in files.values) {
          expect(File('lib/assets/sal/${(f as Map)['file']}').existsSync(),
              isTrue,
              reason: p.clip);
        }
      }
    });
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
      // A pick: "Long · \$25", the rule and a two-line edgy line under it.
      expect(chart.height, greaterThan(50));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'prediction: the speedometer fills the band between the identity '
        'and the bottom, nothing empty', (tester) async {
      for (final data in [
        fakePredictionPick(),
        fakePredictionMarket(chart: false)
      ]) {
        await pump(tester, data);
        expectBalanced(tester, data.kind);
        final dial = tester
            .getRect(find.byKey(const ValueKey('share-card-speedometer')));
        expect(dial.height, greaterThan(150), reason: data.kind);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'money: the amount under the caps line, Sal standing on the rule '
        'filling the room under it, the bottom band on the bottom edge',
        (tester) async {
      for (final data in [fakeBitcoinCard(), fakeDollarsCard()]) {
        await pump(tester, data);
        final caps =
            tester.getRect(find.byKey(const ValueKey('share-card-caps')));
        final sal =
            tester.getRect(find.byKey(const ValueKey('share-card-sal')));
        final hero =
            tester.getRect(find.byKey(const ValueKey('share-card-hero')));
        final rule =
            tester.getRect(find.byKey(const ValueKey('share-card-rule')));
        final edge =
            tester.getRect(find.byKey(const ValueKey('share-card-edge')));
        expect(hero.top - caps.bottom, lessThanOrEqualTo(32),
            reason: data.kind);
        // Sal spans the room between the hero and the rule.
        expect(sal.top, lessThan(hero.bottom + 40), reason: data.kind);
        expect(sal.bottom, closeTo(rule.top + kShareCardSalFeet, 0.5),
            reason: data.kind);
        expect(edge.top - rule.bottom, kShareCardRuleGap, reason: data.kind);
        final footer =
            tester.getRect(find.byKey(const ValueKey('share-card-footer')));
        expect(footer.bottom,
            closeTo(kShareCardSize.height - kShareCardPadding, 1));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'a market\'s chart fills the card under Sal, the bottom band intact',
        (tester) async {
      await tester.runAsync(loadShareCardSal);
      addTearDown(ShareCardSal.debugReset);
      for (final data in [fakePredictionMarket(), fakeMichiganMarket()]) {
        await pump(tester, data);
        final chart = tester
            .getRect(find.byKey(const ValueKey('share-card-market-chart')));
        final sal =
            tester.getRect(find.byKey(const ValueKey('share-card-sal')));
        final rule =
            tester.getRect(find.byKey(const ValueKey('share-card-rule')));
        expect(chart.top,
            greaterThanOrEqualTo(sal.top + sal.height * 0.86 - 1),
            reason: data.question);
        expect(chart.height, greaterThan(150), reason: data.question);
        expect(chart.bottom, lessThanOrEqualTo(rule.top),
            reason: data.question);
        expect(find.byKey(const ValueKey('share-card-edge')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'long titles read whole on every card kind, in en, de and ja: 18 on '
        'two lines, smaller on three, never cut, no overflow', (tester) async {
      await tester.runAsync(loadShareCardSal);
      addTearDown(ShareCardSal.debugReset);
      const titles = [
        'LoL Worlds 2026 Final: Gen.G vs T1',
        r'Will Bitcoin hit $150k by March 2026?',
        'Brazil presidential election 2026',
        'Michigan Senate Election Winner',
        kShareLongQuestion,
      ];
      for (final locale in const [Locale('en'), Locale('de'), Locale('ja')]) {
        for (final t in titles) {
          for (final data in <ShareCardData>[
            fakePredictionPick(question: t),
            fakeBinaryPick(question: t),
            PredictionCardData(
                question: t,
                outcome: 'Lula',
                chance: 41,
                binary: false,
                lines: fakePredictionMarket().lines),
            InvestmentCardData(title: t, price: 10, change: 0.01,
                series: const [1, 2, 3]),
          ]) {
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
            expect(tester.takeException(), isNull,
                reason: '$locale ${data.kind}: $t');
            for (final k in const [
              'share-card-title-head',
              'share-card-title-tail'
            ]) {
              final f = find.byKey(ValueKey(k));
              if (f.evaluate().isEmpty) continue;
              final para = tester.renderObject<RenderParagraph>(f);
              expect(para.didExceedMaxLines, isFalse,
                  reason: '$locale ${data.kind} $k: $t');
            }
            expect(find.byKey(const ValueKey('share-card-edge')),
                findsOneWidget);
            expect(find.byKey(const ValueKey('share-card-footer')),
                findsOneWidget);
          }
        }
      }
    });

    testWidgets('the title steps: short at 18 beside Sal, long smaller, the '
        'lines under him the full width', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      const wide = 312.0 - 48;
      final full = shareCardSalFloat(kShareCardSalSize);
      final short = shareCardTitleFit('Michigan Senate Election Winner',
          narrow: wide - full.width, wide: wide, floatHeight: full.height);
      expect(short.size, 18);
      expect(short.fits, isTrue);
      expect(short.lines, lessThanOrEqualTo(2));
      expect(shareCardSalTopSize('Michigan Senate Election Winner'),
          kShareCardSalSize);
      // The 92-character question: Sal sits compact, two lines beside
      // him, the rest under him at the full width, whole on three.
      expect(shareCardSalTopSize(kShareLongQuestion), kShareCardSalCompactSize);
      final compact = shareCardSalFloat(kShareCardSalCompactSize);
      final long = shareCardTitleFit(kShareLongQuestion,
          narrow: wide - compact.width,
          wide: wide,
          floatHeight: compact.height);
      expect(long.fits, isTrue);
      expect(long.lines, 3);
      expect(long.headLines, 2);
      expect(long.tail, isNotEmpty);
      expect('${long.head} ${long.tail}', kShareLongQuestion);
      expect(long.size, lessThan(18));
      expect(long.size, greaterThanOrEqualTo(kShareCardTitleSteps.last.$1));
    });

    testWidgets('Sal never sits on the text', (tester) async {
      await tester.runAsync(loadShareCardSal);
      addTearDown(ShareCardSal.debugReset);
      for (final data in <ShareCardData>[
        fakeBitcoinCard(),
        fakeDollarsCard(),
        fakePredictionPick(),
        fakePredictionMarket(),
        fakeTeslaPick(),
        fakeNasdaqMarket(),
        fakeOilMarket(),
        fakePredictionPick(question: kShareLongQuestion),
        fakeBinaryPick(),
        fakeMichiganMarket(),
      ]) {
        await pump(tester, data);
        // The dog inside his cell (the render's transparent margin off).
        final cell =
            tester.getRect(find.byKey(const ValueKey('share-card-sal')));
        final dog = Rect.fromLTRB(
            cell.left + cell.width * 0.22,
            cell.top + cell.height * kShareCardSalHeadroom,
            cell.right - 8,
            cell.top + cell.height * 0.86);
        for (final k in const [
          'share-card-caps',
          'share-card-title-head',
          'share-card-title-tail',
          'share-card-meta',
          'share-card-number',
          'share-card-fact',
        ]) {
          final f = find.byKey(ValueKey(k));
          if (f.evaluate().isEmpty) continue;
          final r = tester.getRect(f);
          expect(r.overlaps(dog), isFalse, reason: '${data.kind}: $k');
        }
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
        'Take the other side. I dare you.',
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

    testWidgets('the card draws the seed\'s line, 22 w700, two lines at most',
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
      expect(t.style!.fontWeight, FontWeight.w700);
      expect(t.style!.color, ShareCardPalette.investment.ink);
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
