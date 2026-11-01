// The brag cards (screens/share/brag/): both variants render from fake
// data, always with the real amounts (no toggle); the background, Sal's
// still (sunglasses only on a big win) and his one-liner follow the
// result's tone; Share hands the OS a PNG and the link with the referral
// code, and `brag_shared` says which card.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/brag_sal.dart';
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

  Widget card(BragData data, {ui.Image? sal, int seed = 0}) =>
      Center(child: BragCard(data: data, sal: sal, lineSeed: seed));

  String resultText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('brag-card-result'))).data!;

  String lineText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('brag-card-line'))).data!;

  List<Color> background(WidgetTester tester) => (tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('brag-card-bg')))
          .decoration as BoxDecoration)
      .gradient!
      .colors;

  Future<ui.Image> dummyImage(WidgetTester tester) async =>
      (await tester.runAsync(() {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(
            const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.orange);
        return rec.endRecording().toImage(4, 4);
      }))!;

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

    test('sunglasses only on a big win; the loss still is unbothered', () {
      for (final t in BragTone.values) {
        expect(bragSalWearsShades(t), t == BragTone.bigWin, reason: '$t');
      }
      expect(bragSalAsset(BragTone.bigWin), 'lib/assets/sal/brag_shades.webp');
      expect(bragSalAsset(BragTone.win), 'lib/assets/sal/brag_smug.webp');
      expect(bragSalAsset(BragTone.smallWin), 'lib/assets/sal/brag_smug.webp');
      expect(bragSalAsset(BragTone.flat), 'lib/assets/sal/brag_smug.webp');
      expect(
          bragSalAsset(BragTone.loss), 'lib/assets/sal/brag_unbothered.webp');
    });

    testWidgets('every still is bundled and decodes', (tester) async {
      BragSalStills.debugReset();
      for (final t in BragTone.values) {
        final image = await tester.runAsync(() => BragSalStills.load(t));
        expect(image, isNotNull, reason: '$t');
        expect(image!.width / image.height, closeTo(kBragSalAspect, 0.01));
        expect(BragSalStills.peek(t), same(image));
      }
      BragSalStills.debugReset();
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

    testWidgets('the card: background, Sal and his line follow the tone',
        (tester) async {
      final sal = await dummyImage(tester);
      final cases = <BragData, BragTone>{
        fakeBragPortfolio(): BragTone.bigWin,
        fakeBragSmallWinPortfolio(): BragTone.smallWin,
        fakeBragLosingPortfolio(): BragTone.loss,
        fakeBragFlatPortfolio(): BragTone.flat,
        fakeBragPosition(): BragTone.bigWin,
        fakeBragLosingPosition(): BragTone.loss,
      };
      for (final MapEntry(key: data, value: tone) in cases.entries) {
        for (final seed in [0, 1, 2]) {
          await pumpShareWidget(tester, env, card(data, sal: sal, seed: seed));
          expect(background(tester), bragBackground(tone), reason: '$tone');
          final l10n =
              AppLocalizations.of(tester.element(find.byType(BragCard)));
          expect(lineText(tester), bragLine(l10n, tone, seed));
          expect(lineText(tester), isIn(bragLines(l10n, tone)));
          expect(find.byKey(const ValueKey('brag-card-sal-shades')),
              tone == BragTone.bigWin ? findsOneWidget : findsNothing,
              reason: '$tone');
          expect(find.byKey(const ValueKey('brag-card-sal')),
              tone == BragTone.bigWin ? findsNothing : findsOneWidget,
              reason: '$tone');
          expect(tester.takeException(), isNull);
        }
      }
      // Green up, red down, near-black flat.
      final up = bragBackground(BragTone.win).first;
      final down = bragBackground(BragTone.loss).first;
      final flat = bragBackground(BragTone.flat).first;
      expect(up.g, greaterThan(up.r));
      expect(down.r, greaterThan(down.g));
      expect(flat.r, closeTo(flat.g, 0.02));
      expect(flat.computeLuminance(), lessThan(0.05));
    });

    testWidgets('no still: no Sal, the line still says it', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPortfolio()));
      expect(find.byKey(const ValueKey('brag-card-sal')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-sal-shades')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-line')), findsOneWidget);
    });
  });

  group('position card', () {
    testWidgets('the real amount big, the percent beside it, the market',
        (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPosition()));
      expect(resultText(tester), r'+$36.90');
      expect(find.text('+42.1%'), findsOneWidget);
      expect(find.text('LoL Worlds 2026: Gen.G vs T1'), findsOneWidget);
      expect(find.text('Gen.G'), findsOneWidget);
      expect(find.text('PREDICTIONS · SINCE YOU BOUGHT'), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsOneWidget);
      expect(find.text('41%'), findsOneWidget);
      expect(find.text('58%'), findsOneWidget);
      expect(find.text('Beat me on Kute'), findsOneWidget);
      expect(find.textContaining(kBragTestCode, findRichText: true),
          findsOneWidget);
      expect(tester.getSize(find.byType(BragCard)), kBragCardSize);
    });

    testWidgets('no cost base: the amount alone, no code without one',
        (tester) async {
      const data = BragPosition(
        title: 'BTC',
        link: 'https://backend.kutewallet.com/m/investing/BTC',
        investing: false,
        side: 'Long',
        result: BragResult(usd: -5, text: '−\$5.00'),
      );
      await pumpShareWidget(tester, env, card(data));
      expect(resultText(tester), '−\$5.00');
      expect(find.byKey(const ValueKey('brag-card-percent')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-code')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-chart')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-entry-now')), findsNothing);
    });
  });

  group('portfolio card', () {
    testWidgets(
        'the all-time P&L, All time, the ring in the corner and the top '
        'three as chips with their results', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPortfolio()));
      expect(resultText(tester), r'+$412.35');
      expect(find.text('My portfolio'), findsOneWidget);
      expect(find.text('ALL TIME'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('brag-card-allocation')), findsOneWidget);
      // No legend: the ring is shares only, never money.
      expect(find.text('58%'), findsNothing);
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
      expect(find.byKey(const ValueKey('brag-card-code')), findsOneWidget);
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
      expect(
          text,
          'LoL Worlds 2026: Gen.G vs T1 on Kute '
          'https://backend.kutewallet.com/m/predictions/lol-worlds-geng-t1'
          '?ref=$kBragTestCode');
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
