// The position pages' brag hooks (kute_share_actions.dart): an open
// position's context brags (a third Sal row, "Show off this position";
// the header pill reads Brag and opens the card at once), a settled one
// keeps the send rows and the pill's "Send to a friend".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteSalHeaderButton;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';

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

  group('position page hooks', () {
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

    testWidgets(
        'an open position brags: a third row, Brag on the pill, '
        'a tap opens the card', (tester) async {
      late KuteMarketBarContext bar;
      await pumpShareWidget(tester, env, Builder(builder: (context) {
        bar = barFor(context, open: true);
        return Center(child: KuteSalHeaderButton(barContext: bar));
      }));
      expect(bar.actions, hasLength(3));
      expect(bar.actions.last.label, 'Show off this position');
      expect(bar.actions.last.sublabel, 'A card with your result');
      expect(bar.primaryAction, isNotNull);
      expect(
          bar.boundTo(null),
          isA<KuteMarketBarContext>()
              .having((c) => c.primaryAction, 'primaryAction', isNotNull));
      expect(find.text('Brag'), findsOneWidget);

      await tester.tap(find.byType(KuteSalHeaderButton));
      await settle(tester);
      expect(find.byType(BragPreviewSheet), findsOneWidget);
      expect(find.text('Show off this position'), findsOneWidget);
    });

    testWidgets('a settled position keeps the send rows only', (tester) async {
      late KuteMarketBarContext bar;
      await pumpShareWidget(tester, env, Builder(builder: (context) {
        bar = barFor(context, open: false);
        return Center(child: KuteSalHeaderButton(barContext: bar));
      }));
      expect(bar.actions, hasLength(2));
      expect(bar.primaryAction, isNull);
      expect(find.text('Send to a friend'), findsOneWidget);
    });
  });
}
