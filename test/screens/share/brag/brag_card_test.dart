// The brag cards (screens/share/brag/), restrained premium: both
// variants render from fake data on one solid colour by the result's
// tone (green, red, navy), always with the real amounts (no toggle), ONE
// huge number (the P&L), the all-time line, the top positions with their
// REAL logos (HlCoinIcon, PolyCrestImage, never a letter tile) or, on a
// prediction, the open-position screen's speedometer, the edgy line built
// from the result, Sal at the top right in the tone's mood, the code, no
// chip, pill, bubble or ring, and no large empty band. Share hands the OS a PNG and the link
// with the referral code (the edgy line is on the card, not repeated),
// and `brag_shared` says which card.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart' show BalanceRange;
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/pnl_share_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/position_speedometer.dart'
    show PolySpeedometerDialPainter, PolySpeedometerNeedlePainter;
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../../helpers/kute_bar_test_support.dart';
import '../share_test_harness.dart';
import 'brag_fixtures.dart';
import 'brag_test_fonts.dart';
import '../cards/share_card_test_fonts.dart';

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
    expect(find.byKey(const ValueKey('brag-card-number')), findsOneWidget);
    expect(find.byKey(const ValueKey('brag-card-sal')), findsOneWidget);
    expect(find.byKey(const ValueKey('brag-card-mark')), findsNothing);
    expect(find.byKey(const ValueKey('brag-card-wordmark')), findsOneWidget);
    expect(find.byKey(const ValueKey('brag-card-code')),
        code ? findsOneWidget : findsNothing);
    for (final gone in const [
      'brag-card-line',
      'brag-card-percent',
      'brag-card-side',
      'brag-card-allocation',
      'brag-card-entry-now',
      'brag-card-sal-shades',
    ]) {
      expect(find.byKey(ValueKey(gone)), findsNothing, reason: gone);
    }
    expect(find.text('Beat me on Kute'), findsNothing);
  }

  group('holdings', () {
    BragTopPosition at(String title, double usd) => BragTopPosition(
        title: title, result: BragResult(usd: usd, text: '$usd'));

    test(
        'the top three by the size of their P&L either way, a tie in the '
        "order they came, never a P&L that is not a number", () {
      final top = bragTopHoldings([
        at('a', 1),
        at('b', -5),
        at('c', 3),
        at('d', 0.5),
        at('e', -2),
        at('f', double.nan),
      ]);
      expect(top.map((p) => p.title), ['b', 'c', 'e']);
      expect(
          bragTopHoldings([at('x', 2), at('y', -2), at('z', 2)])
              .map((p) => p.title),
          ['x', 'y', 'z']);
      expect(bragTopHoldings([at('a', 1)]).map((p) => p.title), ['a']);
      expect(bragTopHoldings(const []), isEmpty);
      expect(kBragTopHoldings, 3);
    });

    test('"+N more" counts the open positions the card does not list', () {
      final five = fakeBragFounderPortfolio();
      expect(five.moreThan(3), 2);
      expect(five.moreThan(1), 4);
      expect(fakeBragFounderPortfolio(holdings: 2, open: 2).moreThan(2), 0);
      // An open count under what is listed is never a negative "more".
      expect(
          const BragPortfolio(title: 'x', link: 'https://x.test', top: [
            BragTopPosition(
                title: 'a', result: BragResult(usd: 1, text: r'+$1.00'))
          ]).moreThan(1),
          0);
    });

    test(
        'the plan: as many rows as fit with the line at its least, the '
        'roomy rows only with no line, the rest in "+N more"', () {
      // The founder's card: +$3.43 with a one-line edgy line leaves 102.
      expect(bragHoldingsPlan(height: 102, listed: 3, open: 5, chart: true),
          (rows: 3, more: 2, style: kBragRowDense));
      expect(bragHoldingsPlan(height: 102, listed: 2, open: 2, chart: true),
          (rows: 2, more: 0, style: kBragRowDense));
      // A two-line edgy line leaves 77: fewer rows, the rest counted.
      expect(bragHoldingsPlan(height: 77, listed: 3, open: 5, chart: true),
          (rows: 1, more: 4, style: kBragRowDense));
      expect(bragHoldingsPlan(height: 77, listed: 2, open: 2, chart: true),
          (rows: 2, more: 0, style: kBragRowDense));
      // No line: roomy when the rows fit, dense to keep all three.
      expect(bragHoldingsPlan(height: 110, listed: 3, open: 3, chart: false),
          (rows: 3, more: 0, style: kBragRowRoomy));
      expect(bragHoldingsPlan(height: 110, listed: 3, open: 6, chart: false),
          (rows: 3, more: 3, style: kBragRowDense));
      // Nothing open: no row.
      expect(bragHoldingsPlan(height: 110, listed: 0, open: 0, chart: true),
          (rows: 0, more: 0, style: kBragRowDense));
    });

    testWidgets(
        'the side a row writes: Long or Short, Yes or No in the language, '
        'a named outcome once, nothing on a holding', (tester) async {
      await pumpShareWidget(tester, env, const SizedBox());
      final en = lookupAppLocalizations(const Locale('en'));
      final de = lookupAppLocalizations(const Locale('de'));
      BragTopPosition row(
              {String title = 'Lakers',
              String? side,
              bool? long,
              bool titleIsSide = false}) =>
          BragTopPosition(
              title: title,
              side: side,
              long: long,
              titleIsSide: titleIsSide,
              result: const BragResult(usd: 1, text: r'+$1.00'));
      expect(bragHoldingSide(en, row(long: false)), 'Short');
      expect(bragHoldingSide(en, row(long: true)), 'Long');
      expect(bragHoldingSide(en, row(side: 'Yes')), 'Yes');
      expect(bragHoldingSide(de, row(side: 'No')), 'Nein');
      expect(bragHoldingSide(en, row(side: 'Gen.G')), 'Gen.G');
      expect(
          bragHoldingSide(en,
              row(title: 'Verstappen', side: 'Verstappen', titleIsSide: true)),
          isNull);
      expect(bragHoldingSide(en, row(title: 'Lakers', side: 'lakers')), isNull);
      expect(bragHoldingSide(en, row()), isNull);
    });
  });

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

    test(
        "Sal's pose by the tone: every win lounging (a small one too), a "
        'big one retired, a loss a flop, flat a side-eye', () {
      BragPosition at(double usd, {double? percent}) => BragPosition(
            title: 'ANTH',
            link: 'https://backend.kutewallet.com/m/investing/ANTH',
            investing: true,
            side: 'Short',
            result: BragResult(usd: usd, text: '', percent: percent),
          );
      expect(bragPose(at(36.9, percent: 42.1)), ShareCardPose.bigWin);
      expect(bragPose(at(5, percent: 9.9)), ShareCardPose.win);
      // The portfolio at +$7.77 with no percent (a small win) and a
      // short in profit by under 2%: the win, never the loss flop.
      expect(bragPose(at(7.77)), ShareCardPose.win);
      expect(bragPose(at(3.1, percent: 1.2)), ShareCardPose.win);
      expect(bragPose(at(-12.4, percent: -6.2)), ShareCardPose.loss);
      expect(bragPose(at(0.001)), ShareCardPose.flat);
      for (final tone in BragTone.values) {
        final d = switch (tone) {
          BragTone.bigWin => at(50, percent: 20),
          BragTone.win => at(50, percent: 5),
          BragTone.smallWin => at(5, percent: 1),
          BragTone.loss => at(-5, percent: -1),
          BragTone.flat => at(0),
        };
        expect(d.tone, tone);
        final pose = bragPose(d);
        final up = tone == BragTone.bigWin ||
            tone == BragTone.win ||
            tone == BragTone.smallWin;
        expect(up, pose == ShareCardPose.win || pose == ShareCardPose.bigWin,
            reason: '$tone -> $pose');
      }
    });

    testWidgets('the edgy line: a pool by sign, built from the result, PG',
        (tester) async {
      await pumpShareWidget(tester, env, const SizedBox());
      final l10n =
          AppLocalizations.of(tester.element(find.byType(SizedBox).first));
      final big = bragEdges(l10n, fakeBragPortfolio());
      expect(big.take(2), [
        'Not luck. Pattern recognition.',
        r'+$412.35 while you were scrolling.',
      ]);
      expect(
          big,
          containsAll([
            r"+$412.35. I'll be unbearable now.",
            'This is me being calm.'
          ]));
      expect(big, isNot(contains('Small win. Still a win.')));
      final small = bragEdges(l10n, fakeBragSmallWinPortfolio());
      expect(small.take(2), [
        'Not luck. Pattern recognition.',
        r'+$7.57 while you were scrolling.',
      ]);
      expect(
          small,
          containsAll([
            'Small win. Still a win.',
            r"+$7.57. Rome wasn't built in a day."
          ]));
      expect(small, isNot(contains('This is me being calm.')));
      // A loss: the amount without its sign.
      final loss = bragEdges(l10n, fakeBragLosingPortfolio());
      expect(loss.take(2), [
        'Down bad, still trading.',
        r'Character building, $23.40 at a time.',
      ]);
      expect(loss, contains(r'Down $23.40. Lessons included.'));
      expect(bragEdges(l10n, fakeBragLosingPosition()).take(2), [
        'Down bad, still trading.',
        r'Character building, $12.40 at a time.',
      ]);
      final flat = bragEdges(l10n, fakeBragFlatPortfolio());
      expect(flat.first, 'Patience is a position.');
      expect(flat, contains('Break-even is undefeated.'));
      // No result yet: nothing that says zero.
      expect(
          bragEdges(
              l10n,
              const BragPortfolio(
                  title: 'My portfolio', link: 'https://x.test')),
          [
            'Patience is a position.',
            "The market blinked. I didn't.",
            'Past results. Not a promise.',
            'Screenshot before it changes.',
          ]);
      for (final pool in [big, small, loss, flat]) {
        expect(pool.length, inInclusiveRange(12, 16));
        for (final line in pool) {
          expect(
              RegExp(r'\bbet(s|ting)?\b', caseSensitive: false).hasMatch(line),
              isFalse,
              reason: line);
        }
      }
      // The seed rotates through the pool, any int.
      final pool = bragEdges(l10n, fakeBragPosition());
      expect({
        for (var i = 0; i < pool.length; i++)
          bragEdge(l10n, fakeBragPosition(), i)
      }, pool.toSet());
      expect(bragEdge(l10n, fakeBragPosition(), -3), isIn(pool));
    });

    testWidgets('the card draws the seed\'s line', (tester) async {
      // Nothing open: the seed's own line, two lines and all.
      const nothingOpen = BragPortfolio(
        title: 'My portfolio',
        link: 'https://backend.kutewallet.com/m/investing',
        referralCode: kBragTestCode,
        allTime: BragResult(usd: 412.35, text: r'+$412.35'),
        returnPercent: 24.6,
      );
      await pumpShareWidget(tester, env,
          const Center(child: BragCard(data: nothingOpen, lineSeed: 1)));
      final t = textAt(tester, 'brag-card-edge');
      expect(t.data, r'+$412.35 while you were scrolling.');
      expect(t.style!.fontSize, kShareCardLineSize);
      expect(t.maxLines, 2);
    });

    testWidgets(
        'a portfolio card listing its holdings takes the first line from '
        "the seed's on that sets on one line, so the rows keep their room",
        (tester) async {
      await tester.runAsync(loadBragFonts);
      await pumpShareWidget(tester, env, const SizedBox());
      final l10n =
          AppLocalizations.of(tester.element(find.byType(SizedBox).first));
      final data = fakeBragPortfolio();
      final pool = bragEdges(l10n, data);
      // Seed 1's own line wraps at the card's width.
      expect(bragEdge(l10n, data, 1), r'+$412.35 while you were scrolling.');
      final picked = bragCardEdge(l10n, data, 1);
      expect(picked, pool[2]);
      await pumpShareWidget(
          tester, env, Center(child: BragCard(data: data, lineSeed: 1)));
      expect(textAt(tester, 'brag-card-edge').data, picked);
      final edge = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('brag-card-edge')));
      expect(edge.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(kShareCardSize.width - 2 * kShareCardPadding));
      // Without holdings, or on a position, the seed's own.
      expect(bragCardEdge(l10n, fakeBragPosition(), 1),
          bragEdge(l10n, fakeBragPosition(), 1));
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
      // The colour and Sal's mood follow the tone.
      expect(bragPalette(fakeBragPortfolio()), ShareCardPalette.win);
      expect(bragPalette(fakeBragLosingPortfolio()), ShareCardPalette.loss);
      expect(bragPalette(fakeBragFlatPortfolio()), ShareCardPalette.flat);
      expect(bragPose(fakeBragPortfolio()), ShareCardPose.bigWin);
      expect(bragPose(fakeBragSmallWinPortfolio()), ShareCardPose.win);
      expect(bragPose(fakeBragLosingPortfolio()), ShareCardPose.loss);
      expect(bragPose(fakeBragFlatPortfolio()), ShareCardPose.flat);
    });
  });

  group('position card', () {
    testWidgets(
        'a prediction: MY POSITION, the market and the side, the '
        'speedometer at the chance now with the P&L under its hub, since '
        'you bought with the percent', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPosition()));
      expectRestrained(tester, code: true);
      expect(textAt(tester, 'brag-card-caps').data, 'MY POSITION');
      expect(resultText(tester), r'+$36.90');
      expect(
          textAt(tester, 'brag-card-fact').data, 'Since you bought · +42.1%');
      expect(textAt(tester, 'brag-card-fact').style!.color,
          ShareCardPalette.win.up);
      final bg = tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('brag-card-bg')))
          .decoration as BoxDecoration;
      expect(bg.color, ShareCardPalette.win.background);
      expect(find.text('LoL Worlds 2026: Gen.G vs T1'), findsOneWidget);
      expect(textAt(tester, 'brag-card-meta').data, 'Gen.G');
      expect(find.byKey(const ValueKey('brag-card-logo')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('brag-card-speedometer')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsNothing);
      final painters = tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byKey(const ValueKey('brag-card-speedometer')),
              matching: find.byType(CustomPaint)))
          .map((w) => w.painter)
          .toList();
      expect(
          painters
              .whereType<PolySpeedometerNeedlePainter>()
              .single
              .needle
              .value,
          closeTo(0.58, 1e-9));
      expect(
          painters.whereType<PolySpeedometerDialPainter>().single.entry, 0.41);
      expect(find.text('CODE  $kBragTestCode', findRichText: true),
          findsOneWidget);
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
          ShareCardPalette.loss.down);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsNothing);
    });
  });

  group('portfolio card', () {
    Finder inRow(int i, Finder f) => find.descendant(
        of: find.byKey(ValueKey('brag-card-top-$i')), matching: f);
    String? rowText(WidgetTester tester, int i, String part) {
      final f = find.byKey(ValueKey('brag-card-top-$i-$part'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    testWidgets(
        'MY PORTFOLIO, the all-time P&L big, All time, the holdings as '
        'plain rows: the name, the side quieter, the P&L in money in its '
        'colour; no percent, no ring', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPortfolio()));
      expectRestrained(tester, code: true);
      expect(textAt(tester, 'brag-card-caps').data, 'MY PORTFOLIO');
      expect(resultText(tester), r'+$412.35');
      expect(textAt(tester, 'brag-card-fact').data, 'All time');
      // The combined return is the tone's, never drawn.
      expect(find.textContaining('24.6'), findsNothing);
      // The rows: "Bitcoin · Long", "Gen.G" (the name is the side),
      // "Fed cuts in December · Yes", each with its P&L in money.
      expect([
        for (var i = 0; i < 3; i++)
          (
            rowText(tester, i, 'name'),
            rowText(tester, i, 'side'),
            rowText(tester, i, 'pnl')
          )
      ], [
        ('Bitcoin', ' · Long', r'+$92.10'),
        ('Gen.G', null, r'+$36.90'),
        ('Fed cuts in December', ' · Yes', '−\$8.20'),
      ]);
      // Money, not percents.
      for (final pct in const ['+18.4%', '+42.1%', '−12.5%']) {
        expect(find.text(pct), findsNothing);
      }
      final pnl = textAt(tester, 'brag-card-top-0-pnl');
      expect(pnl.style!.color, ShareCardPalette.win.up);
      // Alone in the middle (no line): the roomy rows, 28 / 17.
      expect(pnl.style!.fontSize, kBragRowRoomy.text);
      expect(textAt(tester, 'brag-card-top-0-side').style!.color,
          ShareCardPalette.win.muted);
      // Three open, three listed: no "+N more".
      expect(find.byKey(const ValueKey('brag-card-more')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsNothing);
      expect(tester.getSize(find.byType(BragCard)), kBragCardSize);
    });

    testWidgets(
        'on the navy card a gain reads green and a loss red, each with its '
        'sign', (tester) async {
      const data = BragPortfolio(
        title: 'My portfolio',
        link: 'https://backend.kutewallet.com/m/investing',
        referralCode: kBragTestCode,
        allTime: BragResult(usd: 0, text: r'$0.00'),
        top: [
          BragTopPosition(
              title: 'Anthropic',
              long: false,
              investing: true,
              coin: 'ANTH',
              result: BragResult(usd: 4.2, text: r'+$4.20')),
          BragTopPosition(
              title: 'Ethereum',
              long: true,
              investing: true,
              coin: 'ETH',
              result: BragResult(usd: -4.2, text: '−\$4.20')),
        ],
        openCount: 2,
      );
      await pumpShareWidget(tester, env, card(data));
      expect(bragPalette(data), ShareCardPalette.flat);
      expect(rowText(tester, 0, 'side'), ' · Short');
      expect(textAt(tester, 'brag-card-top-0-pnl').style!.color,
          ShareCardPalette.flat.up);
      expect(textAt(tester, 'brag-card-top-1-pnl').data, '−\$4.20');
      expect(textAt(tester, 'brag-card-top-1-pnl').style!.color,
          ShareCardPalette.flat.down);
    });

    testWidgets(
        'the rows carry the REAL logos: the coin icon on Investing, '
        "Polymarket's picture on a prediction, never a letter tile",
        (tester) async {
      await pumpShareWidget(
          tester,
          env,
          card(fakeBragPortfolio(
              gengImage: 'https://polymarket.test/geng.png',
              fedImage: 'https://polymarket.test/fed.png')));
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
        expect(tester.widget<PolyCrestImage>(img).size, kBragRowRoomy.logo);
        expect(inRow(i, find.byType(HlCoinIcon)), findsNothing);
      }
      // No letter tile of the card's own: outside the app's logo widgets
      // (whose own stand-ins show offline), a row's only texts are its
      // name, its side (none where the name is the side) and its P&L.
      for (final (i, texts) in [(0, 3), (1, 2), (2, 3)]) {
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
        expect(all - inLogos, texts, reason: 'row $i');
      }
    });

    testWidgets(
        'nothing open: the all-time line fills the middle as before, no row',
        (tester) async {
      await pumpShareWidget(
          tester, env, card(fakeBragFounderPortfolio(holdings: 0, open: 0)));
      expectRestrained(tester, code: true);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-rows')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-top-0')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-more')), findsNothing);
      final chart =
          tester.getRect(find.byKey(const ValueKey('brag-card-chart')));
      expect(chart.height, greaterThan(kBragCardSize.height * 0.22));
      // Nothing open and no line: the hero alone, as before.
      await pumpShareWidget(tester, env,
          card(fakeBragFounderPortfolio(holdings: 0, open: 0, series: false)));
      expect(find.byKey(const ValueKey('brag-card-graphic')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-top-0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'positions open: the line stays, tightened, over the top three '
        '(dense rows), then a quiet "+2 more"; the card keeps its size',
        (tester) async {
      await tester.runAsync(loadBragFonts);
      await pumpShareWidget(tester, env, card(fakeBragFounderPortfolio()));
      expect(tester.takeException(), isNull);
      expectRestrained(tester, code: true);
      expect(resultText(tester), r'+$3.43');
      expect(textAt(tester, 'brag-card-fact').data, 'All time');
      expect(tester.getSize(find.byType(BragCard)), kBragCardSize);
      final chart =
          tester.getRect(find.byKey(const ValueKey('brag-card-chart')));
      final rows = tester.getRect(find.byKey(const ValueKey('brag-card-rows')));
      expect(chart.height, greaterThanOrEqualTo(kBragChartMin));
      expect(rows.top, greaterThanOrEqualTo(chart.bottom));
      expect([
        for (var i = 0; i < 3; i++)
          (
            rowText(tester, i, 'name'),
            rowText(tester, i, 'side'),
            rowText(tester, i, 'pnl')
          )
      ], [
        ('Anthropic', ' · Short', r'+$2.61'),
        ('Fed cuts in December', ' · No', '−\$1.12'),
        ('Ethereum', ' · Long', r'+$0.84'),
      ]);
      expect(find.byKey(const ValueKey('brag-card-top-3')), findsNothing);
      expect(textAt(tester, 'brag-card-top-0-pnl').style!.fontSize,
          kBragRowDense.text);
      final more = textAt(tester, 'brag-card-more');
      expect(more.data, '+2 more');
      expect(more.style!.color, ShareCardPalette.win.muted);
      expect(more.style!.fontSize, kBragMoreSize);
      // The "+N more" sits under the names, the last thing over the rule.
      expect(
          tester.getRect(find.byKey(const ValueKey('brag-card-more'))).left,
          tester
              .getRect(find.byKey(const ValueKey('brag-card-top-0-name')))
              .left);
      expect(
          tester.getRect(find.byKey(const ValueKey('brag-card-more'))).bottom,
          lessThanOrEqualTo(tester
              .getRect(find.byKey(const ValueKey('brag-card-rule')))
              .top));

      // Two open: two rows, no "+N more", a taller line.
      await pumpShareWidget(
          tester, env, card(fakeBragFounderPortfolio(holdings: 2, open: 2)));
      expect(find.byKey(const ValueKey('brag-card-top-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-top-2')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-more')), findsNothing);
      expect(
          tester.getRect(find.byKey(const ValueKey('brag-card-chart'))).height,
          greaterThan(chart.height));
    });

    testWidgets('German: "+2 weitere", Yes and No and the sides in German',
        (tester) async {
      await tester.runAsync(loadBragFonts);
      await pumpShareWidget(
          tester,
          env,
          Builder(
              builder: (context) => Localizations.override(
                  context: context,
                  locale: const Locale('de'),
                  child: card(fakeBragFounderPortfolio()))));
      expect(tester.takeException(), isNull);
      expect(textAt(tester, 'brag-card-more').data, '+2 weitere');
      expect(rowText(tester, 1, 'side'), ' · Nein');
      expect(rowText(tester, 0, 'side'), ' · Short');
    });

    testWidgets(
        'a long name steps down a size, then is cut; its side and its P&L '
        'stay whole', (tester) async {
      await tester.runAsync(loadBragFonts);
      const long = 'Federal Reserve cuts interest rates by 50 basis points';
      const data = BragPortfolio(
        title: 'My portfolio',
        link: 'https://backend.kutewallet.com/m/investing',
        allTime: BragResult(usd: 12.4, text: r'+$12.40'),
        top: [
          BragTopPosition(
              title: long,
              side: 'Yes',
              result: BragResult(usd: 1234.56, text: r'+$1,234.56')),
        ],
        openCount: 1,
      );
      await pumpShareWidget(tester, env, card(data));
      expect(tester.takeException(), isNull);
      final name = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('brag-card-top-0-name')));
      expect(name.didExceedMaxLines, isTrue, reason: 'cut after stepping down');
      expect(textAt(tester, 'brag-card-top-0-name').style!.fontSize,
          kBragRowRoomy.minText);
      for (final part in const ['side', 'pnl']) {
        final p = tester.renderObject<RenderParagraph>(
            find.byKey(ValueKey('brag-card-top-0-$part')));
        expect(p.didExceedMaxLines, isFalse, reason: part);
      }
      expect(rowText(tester, 0, 'side'), ' · Yes');
      expect(rowText(tester, 0, 'pnl'), r'+$1,234.56');
      // A short one keeps its size.
      expect(bragRowNameSize('Bitcoin · Long', 200, kBragRowDense),
          kBragRowDense.text);
      expect(bragRowNameSize(long, 120, kBragRowDense), kBragRowDense.minText);
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
        // Sal fills the room he stands in: beside the caps line at the top
        // right, or under the hero on the rule; only the part of a gap he
        // does not span counts.
        final sal = tester.getRect(find.byKey(const ValueKey('brag-card-sal')));
        for (var i = 1; i < rects.length; i++) {
          final above = i == 1
              ? math.max(rects[0].bottom, sal.bottom - 24)
              : rects[i - 1].bottom;
          final covered = math.max(
              0.0,
              math.min(rects[i].top, sal.bottom) -
                  math.max(above, sal.top + 24));
          final gap = rects[i].top - above - covered;
          expect(gap, lessThanOrEqualTo(kBragCardSize.height * 0.15),
              reason: '${data.kind} ${data.tone}: gap $i');
          expect(rects[i].top - rects[i - 1].bottom, greaterThanOrEqualTo(0),
              reason: '${data.kind} ${data.tone}: overlap $i');
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
      BragPreviewSheet.debugLineSeed = 1;
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
      expect(env.paramsOf('brag_shared').single,
          {'kind': 'position', 'card': 'position'});
    });

    testWidgets(
        'a long market title reads whole (founder: "try to not cut '
        'titles"), the outcome under it, Sal clear of it', (tester) async {
      await tester.runAsync(loadBragFonts);
      for (final title in const [
        'LoL Worlds 2026 Final: Gen.G vs T1',
        'Will the Federal Reserve cut interest rates by 50 basis points at '
            'its December 2026 meeting?',
      ]) {
        await pumpShareWidget(
            tester, env, card(fakeBragPosition(title: title)));
        expect(tester.takeException(), isNull, reason: title);
        final parts = [
          for (final k in const [
            'brag-card-title-head',
            'brag-card-title-tail'
          ])
            if (find.byKey(ValueKey(k)).evaluate().isNotEmpty)
              tester.renderObject<RenderParagraph>(find.byKey(ValueKey(k)))
        ];
        expect(parts, isNotEmpty, reason: title);
        for (final p in parts) {
          expect(p.didExceedMaxLines, isFalse, reason: title);
        }
        expect(parts.map((p) => p.text.toPlainText()).join(' '), title);
        expect(textAt(tester, 'brag-card-meta').data, 'Gen.G');
      }
    });

    testWidgets('the portfolio card says portfolio', (tester) async {
      BragPreviewSheet.debugSharer = (_, __) async {};
      await pumpShareWidget(
          tester, env, BragPreviewSheet(data: fakeBragFlatPortfolio()));
      expect(find.text('Show off your portfolio'), findsOneWidget);
      await shareAndWait(tester);
      // How many positions are open: an integer, no name, no id.
      expect(env.paramsOf('brag_shared').single,
          {'kind': 'portfolio', 'card': 'portfolio', 'holdings_count': 1});
    });
  });

  // Every line of every tone whole in en, de and ja (founder, 5 November
  // 2026: "add many more variations"), on the brag card and the P&L card.
  group('fits', () {
    for (final locale in const [Locale('en'), Locale('de'), Locale('ja')]) {
      testWidgets(
          'every tone and every line of its pool lays out in '
          '${locale.languageCode}: no overflow, the line whole',
          (tester) async {
        await tester.runAsync(loadShareCardFonts);
        final l10n = lookupAppLocalizations(locale);
        Future<void> check(
            BragData data, Widget Function(int seed) card, String key) async {
          final pool = bragEdges(l10n, data);
          for (var seed = 0; seed < pool.length; seed++) {
            await pumpShareWidget(
                tester,
                env,
                Builder(
                    builder: (context) => Localizations.override(
                        context: context,
                        locale: locale,
                        child: Center(child: card(seed)))));
            expect(tester.takeException(), isNull,
                reason: '${locale.languageCode} ${pool[seed]}');
            final edge =
                tester.renderObject<RenderParagraph>(find.byKey(ValueKey(key)));
            expect(edge.didExceedMaxLines, isFalse,
                reason: '${locale.languageCode}: ${pool[seed]}');
          }
        }

        for (final data in <BragData>[
          fakeBragPosition(),
          fakeBragSmallWinPortfolio(),
          fakeBragLosingPortfolio(),
          fakeBragLosingPosition(),
          fakeBragFlatPortfolio(),
          fakeBragWin(),
        ]) {
          await check(data, (seed) => BragCard(data: data, lineSeed: seed),
              'brag-card-edge');
        }
        for (final usd in const [128.4, -41.2]) {
          final pnl = BragPnl(
            title: 'My P&L',
            link: 'https://x.test',
            referralCode: kBragTestCode,
            range: BalanceRange.month,
            allTime:
                BragResult(usd: usd, text: usd > 0 ? r'+$128.40' : '−\$41.20'),
            series: kFakeBragPortfolioSeries,
          );
          await check(pnl, (seed) => PnlShareCard(data: pnl, lineSeed: seed),
              'pnl-card-edge');
        }
      });
    }
  });
}
