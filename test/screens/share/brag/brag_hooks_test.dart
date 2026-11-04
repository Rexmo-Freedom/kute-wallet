// The position pages' brag hooks (kute_share_actions.dart,
// position_share_card.dart): an open position's context brags (a third
// Sal row, "Show off this position", and a primary action opening the
// card); the share card under the tiles reads "Brag about it" in profit
// and opens the card at once, else "Send to a friend", in the black
// button look (textPrimary fill, white ink); the Investing page's pill
// beside the figure is the header button's look; a settled position
// keeps the send rows only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/position_share_card.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteSalHeaderButton;
import 'package:kute/theme/app_theme.dart';

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

  testWidgets(
      'an open position in profit: a third Sal row, and the share '
      'card reads Brag about it and opens the card', (tester) async {
    late KuteMarketBarContext bar;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      bar = barFor(context, open: true);
      return Center(child: PositionShareCard(bar: bar, brag: true));
    }));
    expect(bar.actions, hasLength(3));
    expect(bar.actions.last.label, 'Show off this position');
    expect(bar.actions.last.sublabel, 'A card with your result');
    expect(bar.primaryAction, isNotNull);
    expect(
        bar.boundTo(null),
        isA<KuteMarketBarContext>()
            .having((c) => c.primaryAction, 'primaryAction', isNotNull));
    expect(find.text('Brag about it'), findsOneWidget);
    expect(
        find.text('Send the market or show off your result'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('position-share-card')));
    await settle(tester);
    expect(find.byType(BragPreviewSheet), findsOneWidget);
    expect(find.text('Show off this position'), findsOneWidget);
  });

  testWidgets('an open position at a loss: Send to a friend on the card',
      (tester) async {
    await pumpShareWidget(
        tester,
        env,
        Builder(
            builder: (context) => Center(
                child: PositionShareCard(
                    bar: barFor(context, open: true), brag: false))));
    expect(find.text('Send to a friend'), findsOneWidget);
    expect(find.text('Brag about it'), findsNothing);
  });

  testWidgets('a settled position keeps the send rows only', (tester) async {
    late KuteMarketBarContext bar;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      bar = barFor(context, open: false);
      // Even asked to brag, a context without the card's action
      // offers the Sal sheet.
      return Center(child: PositionShareCard(bar: bar, brag: true));
    }));
    expect(bar.actions, hasLength(2));
    expect(bar.primaryAction, isNull);
    expect(find.text('Send to a friend'), findsOneWidget);
  });

  testWidgets(
      'the Predictions card is the black button: textPrimary fill, '
      'white title, sub and chevron', (tester) async {
    late BuildContext ctx;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      ctx = context;
      return Center(
          child:
              PositionShareCard(bar: barFor(context, open: true), brag: true));
    }));
    final box = tester.widget<Container>(find
        .descendant(
            of: find.byKey(const ValueKey('position-share-card')),
            matching: find.byType(Container))
        .first);
    expect((box.decoration! as BoxDecoration).color, ctx.colors.textPrimary);
    Color ink(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).style!.color!;
    expect(ink('position-share-card-title'), Colors.white);
    expect(ink('position-share-card-sub').withValues(alpha: 1), Colors.white);
    expect(
        tester
            .widget<Icon>(
                find.byKey(const ValueKey('position-share-card-chevron')))
            .color,
        Colors.white);
  });

  testWidgets(
      'the Investing pill: "Brag about it" in the header button look '
      'opens the card; not in profit it is the header button', (tester) async {
    late BuildContext ctx;
    await pumpShareWidget(tester, env, Builder(builder: (context) {
      ctx = context;
      return Center(
          child:
              PositionSharePill(bar: barFor(context, open: true), brag: true));
    }));
    final pill = find.byKey(const ValueKey('position-share-pill'));
    expect(pill, findsOneWidget);
    expect(find.text('Brag about it'), findsOneWidget);
    expect(tester.getSize(pill).height, KuteSalHeaderButton.height);
    final box = tester.widget<Container>(
        find.descendant(of: pill, matching: find.byType(Container)).first);
    final d = box.decoration! as BoxDecoration;
    expect(d.color, ctx.colors.textPrimary);
    expect(
        d.borderRadius, BorderRadius.circular(KuteSalHeaderButton.height / 2));
    expect(find.byKey(const ValueKey('position-share-card')), findsNothing);
    await tester.tap(pill);
    await settle(tester);
    expect(find.byType(BragPreviewSheet), findsOneWidget);

    await pumpShareWidget(
        tester,
        env,
        Builder(
            builder: (context) => Center(
                child: PositionSharePill(
                    bar: barFor(context, open: true), brag: false))));
    expect(find.byKey(const ValueKey('position-share-pill')), findsNothing);
    expect(find.byType(KuteSalHeaderButton), findsOneWidget);
  });
}
