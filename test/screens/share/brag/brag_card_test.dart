// The brag cards (screens/share/brag/), restrained premium: both
// variants render from fake data on one near-black background, always
// with the real amounts (no toggle), ONE big number (the P&L), the footer
// mark and code, no chip, pill, bubble, ring or Sal pose. Sal's one-liner
// follows the result's tone in the share MESSAGE; Share hands the OS a
// PNG and the link with the referral code, and `brag_shared` says which
// card.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardPalette;
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

    testWidgets('one-liner pool by sign, PG', (tester) async {
      await pumpShareWidget(tester, env, const SizedBox());
      final l10n =
          AppLocalizations.of(tester.element(find.byType(SizedBox).first));
      final wins = bragLines(l10n, BragTone.win);
      expect(wins, [
        'Beat that.',
        'Not luck. Talent.',
        'Your move.',
        'Told you so.',
        'I make this look easy.',
        'Up only.',
      ]);
      expect(bragLines(l10n, BragTone.bigWin), wins);
      expect(bragLines(l10n, BragTone.smallWin),
          ['Small wins still count. Still better than you.']);
      expect(bragLines(l10n, BragTone.loss), [
        'Down bad. Back soon.',
        'Character building.',
        'Buy the dip, they said.',
      ]);
      expect(bragLines(l10n, BragTone.flat), ['Patience is a position.']);
      // The seed rotates through the pool, any int.
      expect({for (var i = 0; i < 12; i++) bragLine(l10n, BragTone.win, i)},
          wins.toSet());
      expect(bragLine(l10n, BragTone.loss, -4),
          isIn(bragLines(l10n, BragTone.loss)));
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
      expect(textAt(tester, 'brag-card-fact').data, 'Since you bought · +42.1%');
      expect(textAt(tester, 'brag-card-fact').style!.color,
          ShareCardPalette.dark.up);
      expect(find.text('LoL Worlds 2026: Gen.G vs T1'), findsOneWidget);
      expect(textAt(tester, 'brag-card-meta').data, 'Gen.G');
      expect(find.byKey(const ValueKey('brag-card-logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsOneWidget);
      expect(find.text('CODE $kBragTestCode'), findsOneWidget);
      expect(tester.getSize(find.byType(BragCard)), kBragCardSize);
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
      expect(
          tester.widget<Text>(find.text('+18.4%')).style!.color,
          ShareCardPalette.dark.up);
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
      // The link first, Sal's line for the tone (big win, seed 3) after it.
      expect(
          text,
          'LoL Worlds 2026: Gen.G vs T1 on Kute '
          'https://backend.kutewallet.com/m/predictions/lol-worlds-geng-t1'
          '?ref=$kBragTestCode\n'
          'Told you so.');
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
