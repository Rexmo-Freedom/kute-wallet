// The brag cards (screens/share/brag/): both variants render from fake
// data, money is masked until "Show amounts" is on, Share hands the OS a
// PNG and the link with the referral code, and `brag_shared` says which
// card and whether amounts were shown. The position pages' hooks: an open
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

  Widget card(BragData data, {bool amounts = false}) =>
      Center(child: BragCard(data: data, showAmounts: amounts));

  String resultText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('brag-card-result'))).data!;

  group('position card', () {
    testWidgets('amounts hidden: the percent is the big figure, no money',
        (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPosition()));
      expect(resultText(tester), '+42.1%');
      expect(find.textContaining(r'$36.90'), findsNothing);
      expect(find.text('LoL Worlds 2026: Gen.G vs T1'), findsOneWidget);
      expect(find.text('Gen.G'), findsOneWidget);
      expect(find.text('41%'), findsOneWidget);
      expect(find.text('58%'), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-line')), findsOneWidget);
      expect(find.text('Trade it on Kute'), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-code')), findsOneWidget);
      expect(tester.getSize(find.byType(BragCard)), kBragCardSize);
    });

    testWidgets('amounts shown: the amount big, the percent under it',
        (tester) async {
      await pumpShareWidget(
          tester, env, card(fakeBragPosition(), amounts: true));
      expect(resultText(tester), r'+$36.90');
      expect(find.text('+42.1%'), findsOneWidget);
    });

    testWidgets('no cost base, amounts hidden: the amount masked, sign kept',
        (tester) async {
      const data = BragPosition(
        title: 'BTC',
        link: 'https://backend.kutewallet.com/m/investing/BTC',
        investing: false,
        side: 'Long',
        result: BragResult(usd: -5, text: '−\$5.00'),
      );
      await pumpShareWidget(tester, env, card(data));
      expect(resultText(tester), '−\$•••');
      expect(find.byKey(const ValueKey('brag-card-code')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-line')), findsNothing);
      expect(find.byKey(const ValueKey('brag-card-entry-now')), findsNothing);
    });
  });

  group('portfolio card', () {
    testWidgets('amounts hidden: shares and percents only, the P&L masked',
        (tester) async {
      await pumpShareWidget(tester, env, card(fakeBragPortfolio()));
      expect(resultText(tester), r'+$•••');
      expect(find.textContaining('412'), findsNothing);
      expect(find.textContaining('86.10'), findsNothing);
      expect(find.textContaining('92.10'), findsNothing);
      expect(find.text('58%'), findsOneWidget);
      expect(find.text('27%'), findsOneWidget);
      expect(find.text('15%'), findsOneWidget);
      expect(find.text('+18.4%'), findsOneWidget);
      expect(find.text('+42.1%'), findsOneWidget);
      expect(find.text('+12.5%'), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-month')), findsOneWidget);
    });

    testWidgets('amounts shown: the all-time P&L, the month and each result',
        (tester) async {
      await pumpShareWidget(
          tester, env, card(fakeBragPortfolio(), amounts: true));
      expect(resultText(tester), r'+$412.35');
      expect(find.text(r'+$92.10'), findsOneWidget);
      final month = tester.widget<RichText>(find.descendant(
          of: find.byKey(const ValueKey('brag-card-month')),
          matching: find.byType(RichText)));
      expect(month.text.toPlainText(), contains(r'+$86.10'));
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

      expect(
          tester
              .widget<Switch>(find.byKey(const ValueKey('brag-show-amounts')))
              .value,
          isFalse);
      expect(
          tester.widget<BragCard>(find.byType(BragCard)).showAmounts, isFalse);
      expect(kuteBarPrimaryWithText('Share'), findsOneWidget);

      // Hidden first.
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
          {'kind': 'position', 'amounts_shown': false});

      // Then with amounts.
      await tester.tap(find.byKey(const ValueKey('brag-show-amounts')));
      await settle(tester);
      expect(
          tester.widget<BragCard>(find.byType(BragCard)).showAmounts, isTrue);
      await tester.runAsync(() async {
        await tester.tap(kuteBarPrimary);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
      expect(sent, hasLength(2));
      expect(env.paramsOf('brag_shared').last,
          {'kind': 'position', 'amounts_shown': true});
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
          {'kind': 'portfolio', 'amounts_shown': false});
    });
  });
}
