// The position pages' brag hooks (kute_share_actions.dart,
// position_share_card.dart): an open position's context brags (a third
// Sal row, "Show off this position", and a primary action opening the
// card); the round Sal button beside Close position or Sell
// (positionBarShare, kute_bar_trade_row.dart) opens the card at once in
// profit and reads "Brag about it", else it opens the Sal sheet and reads
// "Send to a friend"; a settled position keeps the send rows only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/position_share_card.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/home/components/kute_bar_trade_row.dart'
    show KuteBarShareButton;

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
  tearDown(tearDownShareTest);

  KuteMarketBarContext barFor(BuildContext context, {required bool open}) =>
      marketBarContext(
        context,
        title: 'LoL Worlds 2026: Gen.G vs T1',
        venue: kMarketLinkPredictions,
        slug: 'lol-worlds-geng-t1',
        position: true,
        category: SearchCategory.predictions,
        searchHint: null,
        source: 'predictions',
        placement: KuteBarPlacement.header,
        brag: open ? fakeBragPosition : null,
      ) as KuteMarketBarContext;

  /// The round Sal button for [share]; a tap runs what the shell bar
  /// runs: the brag card where there is one, else (here) [onSheet].
  Widget button(KuteBarShare share, VoidCallback onSheet) => Center(
        child: KuteBarShareButton(
          share: share,
          onTap: (_) => (share.brag ?? onSheet)(),
        ),
      );

  testWidgets(
      'an open position in profit: a third Sal row, and the round Sal '
      'button reads Brag about it and opens the card', (tester) async {
    late KuteMarketBarContext bar;
    var sheets = 0;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      bar = barFor(context, open: true);
      return button(positionBarShare(bar, brag: true), () => sheets++);
    }));
    expect(bar.actions, hasLength(3));
    expect(bar.actions.last.label, 'Show off this position');
    expect(bar.actions.last.sublabel, 'A card with your result');
    expect(bar.primaryAction, isNotNull);
    expect(
        bar.boundTo(null),
        isA<KuteMarketBarContext>()
            .having((c) => c.primaryAction, 'primaryAction', isNotNull));
    expect(positionBarShare(bar, brag: true).brag, bar.primaryAction);
    final share = find.byKey(const ValueKey('kute-bar-share'));
    expect(share, findsOneWidget);
    // No words on it; read aloud as what it does.
    expect(find.descendant(of: share, matching: find.byType(Text)),
        findsNothing);
    expect(find.bySemanticsLabel('Brag about it'), findsOneWidget);

    await tester.tap(share);
    await settle(tester);
    expect(sheets, 0);
    expect(find.byType(BragPreviewSheet), findsOneWidget);
    expect(find.text('Show off this position'), findsOneWidget);
  });

  testWidgets(
      'an open position at a loss: the round button reads Send to a friend '
      'and opens the Sal sheet', (tester) async {
    late KuteMarketBarContext bar;
    var sheets = 0;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      bar = barFor(context, open: true);
      return button(positionBarShare(bar, brag: false), () => sheets++);
    }));
    expect(positionBarShare(bar, brag: false).brag, isNull);
    expect(positionBarShare(bar, brag: false).barContext, same(bar));
    expect(find.bySemanticsLabel('Send to a friend'), findsOneWidget);
    expect(find.bySemanticsLabel('Brag about it'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('kute-bar-share')));
    await settle(tester);
    expect(sheets, 1);
    expect(find.byType(BragPreviewSheet), findsNothing);
  });

  testWidgets('a settled position keeps the send rows only', (tester) async {
    late KuteMarketBarContext bar;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      bar = barFor(context, open: false);
      // Even asked to brag, a context without the card's action offers
      // the Sal sheet.
      return button(positionBarShare(bar, brag: true), () {});
    }));
    expect(bar.actions, hasLength(2));
    expect(bar.primaryAction, isNull);
    expect(positionBarShare(bar, brag: true).brag, isNull);
    expect(find.bySemanticsLabel('Send to a friend'), findsOneWidget);
  });
}
