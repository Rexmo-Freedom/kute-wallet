// The brag cards (screens/share/brag/): both variants render from fake
// data, always with the real amounts (no toggle), Share hands the OS a
// PNG and the link with the referral code, and `brag_shared` says which
// card. The position pages' hooks: an open
// position's context brags (a third Sal row, the header pill reads Brag
// and opens the card), a settled one does not.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
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
  });

  Widget card(BragData data) => Center(child: BragCard(data: data));

  String resultText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('brag-card-result'))).data!;

  group('position card', () {
    testWidgets('the amount big, the percent under it', (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPosition()));
      expect(resultText(tester), r'+$36.90');
      expect(find.text('+42.1%'), findsOneWidget);
      expect(find.text('LoL Worlds 2026: Gen.G vs T1'), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-code')), findsOneWidget);
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
      expect(find.byKey(const ValueKey('brag-card-code')), findsNothing);
    });
  });

  group('portfolio card', () {
    testWidgets('the all-time P&L, the month and each result',
        (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPortfolio()));
      expect(resultText(tester), r'+$412.35');
      expect(find.text(r'+$92.10'), findsOneWidget);
      expect(find.text('58%'), findsOneWidget);
    });
  });

  group('preview sheet', () {
    testWidgets(
        'amounts are off by default; Share sends a PNG with the '
        'referral link and fires brag_shared', (tester) async {
      final sent = <(XFile, String)>[];
      BragPreviewSheet.debugSharer =
          (file, text) async => sent.add((file, text));
      await pumpShareWidget(
          tester, env, BragPreviewSheet(data: fakeBragPosition()));

      expect(find.byType(Switch), findsNothing);
      expect(kuteBarPrimaryWithText('Share'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(kuteBarPrimary);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
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
      expect(env.paramsOf('brag_shared').single,
          {'kind': 'position'});

    });

    testWidgets('the portfolio card says portfolio', (tester) async {
      BragPreviewSheet.debugSharer = (_, __) async {};
      await pumpShareWidget(
          tester, env, BragPreviewSheet(data: fakeBragPortfolio()));
      expect(find.text('Show off your portfolio'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(kuteBarPrimary);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
      expect(env.paramsOf('brag_shared').single,
          {'kind': 'portfolio'});
    });
  });
}
