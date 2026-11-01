// The brag cards (screens/share/brag/), restrained premium: both
// variants render from fake data on one near-black background, always
// with the real amounts (no toggle), ONE huge number (the P&L), the
// all-time line or the top positions with their REAL logos (HlCoinIcon,
// PolyCrestImage, never a letter tile), the edgy line built from the
// result, the footer mark and code, no chip, pill, bubble, ring or Sal
// pose, and no large empty band. Share hands the OS a PNG and the link
// with the referral code (the edgy line is on the card, not repeated),
// and `brag_shared` says which card.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../../helpers/kute_bar_test_support.dart';
import '../share_test_harness.dart';
import 'brag_fixtures.dart';
import 'brag_test_fonts.dart';

void main() {
  late ShareTestEnv env;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadBragFonts();
  });
  setUp(() => env = setUpShareTest());
  tearDown(() {
    tearDownShareTest();
    BragPreviewSheet.debugSharer = null;
    BragPreviewSheet.debugLineSeed = null;
  });

  Widget card(BragData data) => Center(child: BragCard(data: data));

  String resultText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('brag-card-number'))).data!;

  Text textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key)));

  void expectRestrained(WidgetTester tester, {required bool code}) {
    final box = tester
        .widget<DecoratedBox>(find.byKey(const ValueKey('brag-card-bg')))
        .decoration as BoxDecoration;
    expect(box.gradient, isNull);
    expect(box.color, ShareCardPalette.dark.background);
    expect(find.byKey(const ValueKey('brag-card-number')), findsOneWidget);
    expect(find.byKey(const ValueKey('brag-card-mark')), findsOneWidget);
    expect(find.byKey(const ValueKey('brag-card-wordmark')), findsOneWidget);
    expect(find.byKey(const ValueKey('brag-card-code')),
        code ? findsOneWidget : findsNothing);
    for (final gone in const [
      'brag-card-line',
      'brag-card-percent',
      'brag-card-side',
      'brag-card-allocation',
      'brag-card-entry-now',
      'brag-card-sal',
      'brag-card-sal-shades',
    ]) {
      expect(find.byKey(ValueKey(gone)), findsNothing, reason: gone);
    }
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('Beat me on Kute'), findsNothing);
  }

  group('tone', () {
    test('the tone follows the sign and the size of the result', () {
      expect(bragTone(36.9, percent: 42.1), BragTone.bigWin);
      expect(bragTone(5, percent: 10), BragTone.bigWin);
      expect(bragTone(5, percent: 9.9), BragTone.win);
      expect(bragTone(5, percent: 1.9), BragTone.smallWin);
      expect(bragTone(7.57), BragTone.smallWin);
      expect(bragTone(412), BragTone.win, reason: 'no percent: never big');
      expect(bragTone(-5, percent: -2), BragTone.loss);
      expect(bragTone(-5, percent: 30), BragTone.loss);
      expect(bragTone(0.001), BragTone.flat);
      expect(fakeBragPortfolio().tone, BragTone.bigWin);
      expect(fakeBragSmallWinPortfolio().tone, BragTone.smallWin);
      expect(fakeBragLosingPortfolio().tone, BragTone.loss);
      expect(fakeBragFlatPortfolio().tone, BragTone.flat);
      expect(fakeBragPosition().tone, BragTone.bigWin);
      expect(fakeBragLosingPosition().tone, BragTone.loss);
    });

    testWidgets('the edgy line: a pool by sign, built from the result, PG',
        (tester) async {
      await pumpShareWidget(tester, env, const SizedBox());
      final l10n =
          AppLocalizations.of(tester.element(find.byType(SizedBox).first));
      expect(bragEdges(l10n, fakeBragPortfolio()), [
        'Not luck. Pattern recognition.',
        r'+$412.35 while you were scrolling.',
      ]);
      expect(bragEdges(l10n, fakeBragSmallWinPortfolio()), [
        'Not luck. Pattern recognition.',
        r'+$7.57 while you were scrolling.',
      ]);
      // A loss: the amount without its sign.
      expect(bragEdges(l10n, fakeBragLosingPortfolio()), [
        'Down bad, still trading.',
        r'Character building, $23.40 at a time.',
      ]);
      expect(bragEdges(l10n, fakeBragLosingPosition()), [
        'Down bad, still trading.',
        r'Character building, $12.40 at a time.',
      ]);
      expect(bragEdges(l10n, fakeBragFlatPortfolio()),
          ['Patience is a position.']);
      // The seed rotates through the pool, any int.
      final pool = bragEdges(l10n, fakeBragPosition());
      expect(
          {for (var i = 0; i < 6; i++) bragEdge(l10n, fakeBragPosition(), i)},
          pool.toSet());
      expect(bragEdge(l10n, fakeBragPosition(), -3), isIn(pool));
    });

    testWidgets('the card draws the seed\'s line', (tester) async {
      await pumpShareWidget(tester, env,
          Center(child: BragCard(data: fakeBragPortfolio(), lineSeed: 1)));
      final t = textAt(tester, 'brag-card-edge');
      expect(t.data, r'+$412.35 while you were scrolling.');
      expect(t.style!.fontSize, kShareCardLineSize);
      expect(t.maxLines, 2);
    });

    testWidgets('every tone: the same restrained card, laid out',
        (tester) async {
      for (final data in <BragData>[
        fakeBragPortfolio(),
        fakeBragSmallWinPortfolio(),
        fakeBragLosingPortfolio(),
        fakeBragFlatPortfolio(),
        fakeBragPosition(),
        fakeBragLosingPosition(),
      ]) {
        await pumpShareWidget(tester, env, card(data));
        expectRestrained(tester, code: true);
        expect(tester.takeException(), isNull, reason: '${data.tone}');
      }
    });
  });

  group('position card', () {
    testWidgets(
        'MY POSITION, the market and the side, the P&L big, since you '
        'bought with the percent in colour, the line', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPosition()));
      expectRestrained(tester, code: true);
      expect(textAt(tester, 'brag-card-caps').data, 'MY POSITION');
      expect(resultText(tester), r'+$36.90');
      expect(
          textAt(tester, 'brag-card-fact').data, 'Since you bought · +42.1%');
      expect(textAt(tester, 'brag-card-fact').style!.color,
          ShareCardPalette.dark.up);
      expect(find.text('LoL Worlds 2026: Gen.G vs T1'), findsOneWidget);
      expect(textAt(tester, 'brag-card-meta').data, 'Gen.G');
      expect(find.byKey(const ValueKey('brag-card-logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsOneWidget);
      expect(find.text('CODE $kBragTestCode'), findsOneWidget);
      expect(tester.getSize(find.byType(BragCard)), kBragCardSize);
      // Entry and now as the plain fact line.
      expect(textAt(tester, 'brag-card-plain').data, '41% → 58%');
      expect(tester.getSize(find.byKey(const ValueKey('brag-card-logo'))),
          const Size.square(36));
    });

    testWidgets('a loss reads red; no cost base, no line, no code',
        (tester) async {
      const data = BragPosition(
        title: 'BTC',
        link: 'https://backend.kutewallet.com/m/investing/BTC',
        investing: false,
        side: 'Long',
        result: BragResult(usd: -5, text: '−\$5.00'),
      );
      await pumpShareWidget(tester, env, card(data));
      expectRestrained(tester, code: false);
      expect(resultText(tester), '−\$5.00');
      expect(textAt(tester, 'brag-card-fact').data, 'Since you bought');
      expect(textAt(tester, 'brag-card-fact').style!.color,
          ShareCardPalette.dark.down);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsNothing);
    });
  });

  group('portfolio card', () {
    testWidgets(
        'MY PORTFOLIO, the all-time P&L big, All time, the top three as '
        'plain rows with their results, no ring', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPortfolio()));
      expectRestrained(tester, code: true);
      expect(textAt(tester, 'brag-card-caps').data, 'MY PORTFOLIO');
      expect(resultText(tester), r'+$412.35');
      expect(textAt(tester, 'brag-card-fact').data, 'All time');
      // The combined return is the tone's, never drawn.
      expect(find.textContaining('24.6'), findsNothing);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('brag-card-top-$i')), findsOneWidget);
      }
      expect(find.text('BTC'), findsOneWidget);
      expect(find.text('Gen.G'), findsOneWidget);
      expect(find.text('Fed cuts rates in December?'), findsOneWidget);
      expect(find.text('+18.4%'), findsOneWidget);
      expect(find.text('+42.1%'), findsOneWidget);
      expect(find.text('+12.5%'), findsOneWidget);
      expect(tester.widget<Text>(find.text('+18.4%')).style!.color,
          ShareCardPalette.dark.up);
      expect(tester.widget<Text>(find.text('+18.4%')).style!.fontSize, 17);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsNothing);
    });

    testWidgets(
        'the rows carry the REAL logos (28): the coin icon on Investing, '
        "Polymarket's picture on a prediction, never a letter tile",
        (tester) async {
      await pumpShareWidget(
          tester,
          env,
          card(fakeBragPortfolio(
              gengImage: 'https://polymarket.test/geng.png',
              fedImage: 'https://polymarket.test/fed.png')));
      Finder inRow(int i, Finder f) => find.descendant(
          of: find.byKey(ValueKey('brag-card-top-$i')), matching: f);
      final coin = inRow(0, find.byType(HlCoinIcon));
      expect(coin, findsOneWidget);
      expect(tester.widget<HlCoinIcon>(coin).coin, 'BTC');
      expect(inRow(0, find.byType(PolyCrestImage)), findsNothing);
      for (final (i, url) in [
        (1, 'https://polymarket.test/geng.png'),
        (2, 'https://polymarket.test/fed.png'),
      ]) {
        final img = inRow(i, find.byType(PolyCrestImage));
        expect(img, findsOneWidget);
        expect(tester.widget<PolyCrestImage>(img).url, url);
        expect(tester.widget<PolyCrestImage>(img).size, kBragRowLogo);
        expect(inRow(i, find.byType(HlCoinIcon)), findsNothing);
      }
      // No letter tile of the card's own: outside the app's logo widgets
      // (whose own stand-ins show offline), a row's only texts are its
      // name and its result.
      for (var i = 0; i < 3; i++) {
        final all = inRow(i, find.byType(Text)).evaluate().length;
        final inLogos = find
                .descendant(
                    of: inRow(i, find.byType(HlCoinIcon)),
                    matching: find.byType(Text))
                .evaluate()
                .length +
            find
                .descendant(
                    of: inRow(i, find.byType(PolyCrestImage)),
                    matching: find.byType(Text))
                .evaluate()
                .length;
        expect(all - inLogos, 2, reason: 'row $i');
      }
    });

    testWidgets(
        'the all-time line, when there is one, fills the middle in '
        'place of the rows', (tester) async {
      await pumpShareWidget(tester, env,
          card(fakeBragPortfolio(series: kFakeBragPortfolioSeries)));
      expectRestrained(tester, code: true);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-rows')), findsNothing);
      final chart =
          tester.getRect(find.byKey(const ValueKey('brag-card-chart')));
      expect(chart.height, greaterThan(kBragCardSize.height * 0.3));
    });

    testWidgets('no band left mostly empty, with or without the line',
        (tester) async {
      for (final data in <BragData>[
        fakeBragPortfolio(),
        fakeBragPortfolio(series: kFakeBragPortfolioSeries),
        fakeBragSmallWinPortfolio(),
        fakeBragLosingPortfolio(),
        fakeBragPosition(),
        fakeBragLosingPosition(),
      ]) {
        await pumpShareWidget(tester, env, card(data));
        final all = [
          for (final k in const [
            'caps',
            'identity',
            'hero',
            'graphic',
            'plain',
            'edge',
            'footer',
          ])
            if (find.byKey(ValueKey('brag-card-$k')).evaluate().isNotEmpty)
              tester.getRect(find.byKey(ValueKey('brag-card-$k'))),
        ];
        // A part inside another (the plain fact in the hero) is no band.
        final rects = [
          for (final r in all)
            if (!all.any(
                (o) => o != r && o.contains(r.center) && o.height > r.height))
              r
        ];
        for (var i = 1; i < rects.length; i++) {
          final gap = rects[i].top - rects[i - 1].bottom;
          expect(gap, inInclusiveRange(0, kBragCardSize.height * 0.15),
              reason: '${data.kind} ${data.tone}: gap $i');
        }
      }
    });
  });

  group('preview sheet', () {
    // Share: the capture and the PNG run on real time; wait (up to 5 s,
    // a loaded machine) until brag_shared has fired.
    Future<void> shareAndWait(WidgetTester tester) async {
      final before = env.paramsOf('brag_shared').length;
      await tester.runAsync(() async {
        await tester.tap(kuteBarPrimary);
        for (var i = 0;
            i < 100 && env.paramsOf('brag_shared').length == before;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester);
    }

    testWidgets(
        'no switch, the real amounts; Share sends a PNG with the '
        'referral link and fires brag_shared', (tester) async {
      final sent = <(XFile, String)>[];
      BragPreviewSheet.debugSharer =
          (file, text) async => sent.add((file, text));
      BragPreviewSheet.debugLineSeed = 3;
      await pumpShareWidget(
          tester, env, BragPreviewSheet(data: fakeBragPosition()));

      expect(find.byType(Switch), findsNothing);
      expect(kuteBarPrimaryWithText('Share'), findsOneWidget);

      await shareAndWait(tester);
      expect(sent, hasLength(1));
      final (file, text) = sent.single;
      expect(file.mimeType, 'image/png');
      final bytes = await tester.runAsync(file.readAsBytes) as Uint8List;
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // The link alone: the edgy line is on the card.
      expect(
          text,
          'LoL Worlds 2026: Gen.G vs T1 on Kute '
          'https://backend.kutewallet.com/m/predictions/lol-worlds-geng-t1'
          '?ref=$kBragTestCode');
      expect(textAt(tester, 'brag-card-edge').data,
          r'+$36.90 while you were scrolling.');
      expect(env.paramsOf('brag_shared').single, {'kind': 'position'});
    });

    testWidgets('the portfolio card says portfolio', (tester) async {
      BragPreviewSheet.debugSharer = (_, __) async {};
      await pumpShareWidget(
          tester, env, BragPreviewSheet(data: fakeBragFlatPortfolio()));
      expect(find.text('Show off your portfolio'), findsOneWidget);
      await shareAndWait(tester);
      expect(env.paramsOf('brag_shared').single, {'kind': 'portfolio'});
    });
  });
}
