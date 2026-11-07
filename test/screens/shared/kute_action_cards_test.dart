// The shared big-square action cards (kute_action_cards.dart): the grid's
// layouts for one to four cards (as tall as their content, no floor; the
// lone card or an odd last one full width and compact, the visual at its
// left and a chevron at its right), a disabled card's badge, and the
// smaller option cards under a market's or a position's chart, never one
// alone in half the width: the lone card and an odd last one alike one
// compact full-width row, as tall as a list row, with no preview.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/theme/app_theme.dart';

KuteActionCard _card(String title, {String? sub, VoidCallback? onTap,
        String? badge}) =>
    KuteActionCard(
      key: ValueKey('card-$title'),
      visual: const Icon(Icons.star_rounded, size: 40),
      title: title,
      subtitle: sub,
      badge: badge,
      onTap: onTap,
    );

Future<void> _pump(WidgetTester tester, List<KuteActionCard> cards,
    {KuteActionCard? lead, bool oneLineTitles = false}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            KuteActionCardGrid(
                cards: cards, lead: lead, oneLineTitles: oneLineTitles)
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
}

Rect _r(WidgetTester tester, String title) =>
    tester.getRect(find.byKey(ValueKey('card-$title')));

void main() {
  Finder chevronOf(String title) => find.descendant(
      of: find.byKey(ValueKey('card-$title')),
      matching: find.byIcon(Icons.chevron_right_rounded));

  testWidgets(
      'one card is full width and compact (founder: "no need to be as '
      'big"): the visual at its left, the title over its line beside it, a '
      'chevron at its right; as tall as that, no taller', (tester) async {
    var taps = 0;
    await _pump(tester, [
      _card('Also sends to', sub: 'USDC, USDT, ETH and 19 more',
          onTap: () => taps++),
    ]);
    final a = _r(tester, 'Also sends to');
    expect(a.left, moreOrLessEquals(20));
    expect(a.width, moreOrLessEquals(390));
    final visual = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('card-Also sends to')),
        matching: find.byIcon(Icons.star_rounded)));
    final title = tester.getRect(find.text('Also sends to'));
    final line = tester.getRect(find.text('USDC, USDT, ETH and 19 more'));
    final chevron = tester.getRect(chevronOf('Also sends to'));
    // The visual inside the padding and the hairline, at the left; the
    // text beside it, the title over its line; the chevron at the right.
    expect(visual.left - a.left, moreOrLessEquals(kKuteActionCardPadding + 1));
    expect(title.left, greaterThanOrEqualTo(visual.right));
    expect(line.top, greaterThanOrEqualTo(title.bottom));
    expect(line.left, moreOrLessEquals(title.left));
    expect(a.right - chevron.right,
        moreOrLessEquals(kKuteActionCardPadding + 1));
    expect(chevron.center.dy, moreOrLessEquals(a.center.dy, epsilon: 1));
    // As tall as its taller side (the 40 visual or the text) and the
    // padding, nothing more: far from a square across the whole width.
    final content = math.max(kKuteActionCardVisualSlot, line.bottom - title.top);
    expect(a.height,
        moreOrLessEquals(content + 2 * (kKuteActionCardPadding + 1),
            epsilon: 1));
    expect(a.height, lessThan(100));
    expect(
        tester.getSemantics(find.byKey(const ValueKey('card-Also sends to'))),
        matchesSemantics(
            label: 'Also sends to, USDC, USDT, ETH and 19 more',
            isButton: true));
    await tester.tap(find.byKey(const ValueKey('card-Also sends to')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the lone card\'s words wrap whole beside the visual, the card grows '
      'with them; a disabled lone card reads its badge in the chevron\'s '
      'place', (tester) async {
    const long = 'A line long enough that it needs a second line and a '
        'third one beside the visual at this width, never cut';
    await _pump(tester, [_card('Lone', sub: long, badge: 'SOON')]);
    final a = _r(tester, 'Lone');
    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
    expect(tester.getRect(find.text(long)).bottom,
        lessThanOrEqualTo(a.bottom - kKuteActionCardPadding));
    expect(a.height, greaterThan(kKuteActionCardVisualSlot + 2 * kKuteActionCardPadding + 2));
    expect(find.text('SOON'), findsOneWidget);
    expect(chevronOf('Lone'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two squares are as tall as their content, the taller one setting the '
      'row: no floor, no half-empty card', (tester) async {
    await _pump(tester, [
      _card('A', sub: 'One line', onTap: () {}),
      _card('B', sub: 'Two', onTap: () {}),
    ]);
    final a = _r(tester, 'A');
    final line = tester.getRect(find.text('One line'));
    expect(a.bottom - line.bottom,
        moreOrLessEquals(kKuteActionCardPadding + 1, epsilon: 1));
    expect(a.height, lessThan(170));
    expect(chevronOf('A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two cards: equal, side by side, 12 apart, equally tall',
      (tester) async {
    await _pump(tester, [
      _card('A', sub: 'One line', onTap: () {}),
      _card('B', sub: 'A longer line that takes two lines here', onTap: () {}),
    ]);
    final a = _r(tester, 'A');
    final b = _r(tester, 'B');
    expect(a.top, b.top);
    expect(a.width, moreOrLessEquals(b.width));
    expect(a.height, b.height);
    expect(b.left - a.right, moreOrLessEquals(12));
  });

  testWidgets(
      'a lead card goes on top, full width, larger than the cards under it '
      '(a larger title, its chevron); two under it are squares, one is '
      'compact full width, none leaves it alone', (tester) async {
    await _pump(tester, [_card('Dollars'), _card('Wallet')],
        lead: _card('Bitcoin', sub: 'Bitcoin and Lightning'));
    final top = _r(tester, 'Bitcoin');
    expect(top.width, moreOrLessEquals(390));
    expect(chevronOf('Bitcoin'), findsOneWidget);
    final a = _r(tester, 'Dollars'), b = _r(tester, 'Wallet');
    expect(a.top, greaterThan(top.bottom));
    expect(a.top, moreOrLessEquals(b.top));
    expect(a.width, moreOrLessEquals(b.width));
    expect(chevronOf('Dollars'), findsNothing);
    double size(String title) =>
        tester.widget<Text>(find.text(title)).style!.fontSize!;
    expect(size('Bitcoin'), greaterThan(size('Dollars')));

    await _pump(tester, [_card('Dollars')], lead: _card('Bitcoin'));
    expect(_r(tester, 'Dollars').width, moreOrLessEquals(390));
    expect(chevronOf('Dollars'), findsOneWidget);
    expect(_r(tester, 'Dollars').height,
        lessThan(_r(tester, 'Bitcoin').height));

    await _pump(tester, const [], lead: _card('Bitcoin'));
    expect(_r(tester, 'Bitcoin').width, moreOrLessEquals(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'oneLineTitles: two squares where both titles read on one line, else '
      'two compact full-width cards, never a squeezed font', (tester) async {
    await _pump(tester, [_card('Bitcoin'), _card('Wallet')],
        oneLineTitles: true);
    expect(_r(tester, 'Bitcoin').top, moreOrLessEquals(_r(tester, 'Wallet').top));
    expect(_r(tester, 'Bitcoin').right, lessThan(_r(tester, 'Wallet').left));

    const long = 'From another wallet or exchange';
    await _pump(tester, [_card('Bitcoin'), _card(long)], oneLineTitles: true);
    final a = _r(tester, 'Bitcoin'), b = _r(tester, long);
    expect(b.top, greaterThan(a.bottom));
    for (final r in [a, b]) {
      expect(r.width, moreOrLessEquals(390));
    }
    expect(chevronOf('Bitcoin'), findsOneWidget);
    expect(chevronOf(long), findsOneWidget);
    // The same title size as ever.
    expect(tester.widget<Text>(find.text(long)).style!.fontSize,
        tester.widget<Text>(find.text('Bitcoin')).style!.fontSize);

    // Without the rule the long title wraps in its square, as before.
    await _pump(tester, [_card('Bitcoin'), _card(long)]);
    expect(_r(tester, 'Bitcoin').top, moreOrLessEquals(_r(tester, long).top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('three short labels sit three across', (tester) async {
    await _pump(tester, [
      _card('Buy', onTap: () {}),
      _card('Send', onTap: () {}),
      _card('Get', onTap: () {}),
    ]);
    final a = _r(tester, 'Buy');
    final c = _r(tester, 'Get');
    expect(a.top, c.top);
    expect(c.left, greaterThan(_r(tester, 'Send').right));
  });

  testWidgets('three labels that do not fit: two over one full width',
      (tester) async {
    await _pump(tester, [
      _card('Send the market', sub: 'A link they can open, with your code',
          onTap: () {}),
      _card('Send this prediction', sub: 'They get your pick, ready to place',
          onTap: () {}),
      _card('Show off this position', sub: 'A card with your result',
          onTap: () {}),
    ]);
    final a = _r(tester, 'Send the market');
    final b = _r(tester, 'Send this prediction');
    final c = _r(tester, 'Show off this position');
    expect(a.top, b.top);
    expect(c.top, greaterThan(a.bottom));
    expect(c.width, moreOrLessEquals(390));
    // The full-width one is the compact card: a chevron, the visual at
    // its left, lower than the squares; the squares show no chevron.
    expect(chevronOf('Show off this position'), findsOneWidget);
    expect(chevronOf('Send the market'), findsNothing);
    expect(c.height, lessThan(a.height));
    expect(tester.getRect(find.text('Show off this position')).left,
        greaterThan(c.left + kKuteActionCardPadding + 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('four cards: a 2 x 2 grid', (tester) async {
    await _pump(tester, [
      for (final t in ['A', 'B', 'C', 'D']) _card(t, onTap: () {}),
    ]);
    expect(_r(tester, 'A').top, _r(tester, 'B').top);
    expect(_r(tester, 'C').top, _r(tester, 'D').top);
    expect(_r(tester, 'C').top, greaterThan(_r(tester, 'A').bottom));
    expect(_r(tester, 'C').left, moreOrLessEquals(_r(tester, 'A').left));
  });

  testWidgets('a disabled card shows its badge and ignores taps',
      (tester) async {
    var taps = 0;
    await _pump(tester, [
      _card('A', badge: 'SELECTED'),
      _card('B', onTap: () => taps++),
    ]);
    expect(find.text('SELECTED'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('card-A')));
    await tester.tap(find.byKey(const ValueKey('card-B')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  group('option cards', () {
    KuteActionCard option(String title, {String? sub, VoidCallback? onTap}) =>
        KuteActionCard.option(
          key: ValueKey('card-$title'),
          icon: Icons.shield_outlined,
          title: title,
          subtitle: sub,
          onTap: onTap ?? () {},
        );

    testWidgets('smaller than the sheets\' cards: two side by side, at least '
        '112 tall, the icon at the top left, the value on one line',
        (tester) async {
      await _pump(tester, [
        option('Add margin', sub: 'Further from liquidation'),
        option('Protect it',
            sub: 'Stop loss, a value far too long for one line of the card'),
      ]);
      final a = _r(tester, 'Add margin');
      final b = _r(tester, 'Protect it');
      expect(a.top, b.top);
      expect(a.height, b.height);
      expect(a.height, greaterThanOrEqualTo(kKuteOptionCardMinHeight));
      expect(b.left - a.right, moreOrLessEquals(12));
      final card = tester.widget<KuteActionCard>(
          find.byKey(const ValueKey('card-Add margin')));
      expect(card.compact, isTrue);
      final icon = tester.getRect(find.descendant(
          of: find.byKey(const ValueKey('card-Add margin')),
          matching: find.byIcon(Icons.shield_outlined)));
      // Inside the padding and the 1 px hairline.
      expect(icon.left - a.left, moreOrLessEquals(kKuteOptionCardPadding + 1));
      expect(icon.top, lessThan(a.top + kKuteOptionCardPadding + 3));
      // The title over its value, both at the top: the titles of a row sit
      // level.
      final titleA = tester.getRect(find.text('Add margin'));
      final titleB = tester.getRect(find.text('Protect it'));
      expect(titleA.top, titleB.top);
      expect(titleA.top, greaterThan(icon.bottom));
      final value = tester.widget<Text>(find.textContaining('Stop loss'));
      expect(value.maxLines, 1);
      expect(tester.takeException(), isNull);
    });

    KuteActionCard rulesCard() => KuteActionCard.option(
          key: const ValueKey('card-Rules and resolution'),
          icon: Icons.gavel_rounded,
          title: 'Rules and resolution',
          subtitle: 'Ends Apr 1, 2027',
          onTap: () {},
        );
    Finder chevronIn(String title) => find.descendant(
        of: find.byKey(ValueKey('card-$title')),
        matching: find.byIcon(Icons.chevron_right_rounded));

    /// [title]'s card is one compact full-width row (founder, 7 November
    /// 2026, the lone rules card: "way too much"): the icon at its left
    /// at the squares' size, the title over its value beside it, the
    /// chevron at its right, all level with the card's middle; as tall as
    /// a list row.
    void expectRow(WidgetTester tester, String title, String value,
        IconData iconData) {
      final card = _r(tester, title);
      expect(card.left, moreOrLessEquals(20));
      expect(card.width, moreOrLessEquals(390));
      final icon = tester.getRect(find.descendant(
          of: find.byKey(ValueKey('card-$title')),
          matching: find.byIcon(iconData)));
      final text = tester.getRect(find.text(title));
      final line = tester.getRect(find.text(value));
      final chevron = tester.getRect(chevronIn(title));
      expect(icon.width, kKuteOptionCardIconSize);
      expect(icon.left - card.left,
          moreOrLessEquals(kKuteOptionCardPadding + 1));
      expect(icon.center.dy, moreOrLessEquals(card.center.dy, epsilon: 1));
      expect(text.left, greaterThan(icon.right));
      expect(line.left, moreOrLessEquals(text.left));
      expect(line.top, greaterThanOrEqualTo(text.bottom));
      expect(tester.widget<Text>(find.text(title)).style!.fontSize, 15);
      expect(tester.widget<Text>(find.text(value)).maxLines, 1);
      expect(card.right - chevron.right,
          moreOrLessEquals(kKuteOptionCardPadding + 1));
      expect(chevron.center.dy, moreOrLessEquals(card.center.dy, epsilon: 1));
      expect(text.right, lessThanOrEqualTo(chevron.left));
      // The title over its value and the padding, nothing more: a list
      // row's height (the real page's is checked with Inter loaded, in
      // market_send_cards_test.dart), far under a square's floor.
      expect(card.height,
          moreOrLessEquals(
              line.bottom - text.top + 2 * (kKuteOptionCardPadding + 1),
              epsilon: 1));
      expect(card.height, lessThan(kKuteOptionCardMinHeight));
    }

    testWidgets('a lone option card is one compact full-width row: the '
        'icon at its left, the title over its date, a chevron; no preview',
        (tester) async {
      await _pump(tester, [rulesCard()]);
      expectRow(tester, 'Rules and resolution', 'Ends Apr 1, 2027',
          Icons.gavel_rounded);
      expect(
          tester.getSemantics(find.byKey(
              const ValueKey('card-Rules and resolution'))),
          matchesSemantics(
              label: 'Rules and resolution, Ends Apr 1, 2027',
              isButton: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a position\'s lone action is the same row; two are still '
        'squares side by side', (tester) async {
      await _pump(tester, [option('Protect it', sub: 'Sell at your price')]);
      expectRow(
          tester, 'Protect it', 'Sell at your price', Icons.shield_outlined);
      await _pump(tester, [option('Add margin'), option('Protect it')]);
      expect(_r(tester, 'Add margin').top, _r(tester, 'Protect it').top);
      expect(chevronOf('Protect it'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('three: two squares over one full-width row, at the '
        'squares\' sizes, with a chevron; a square has none', (tester) async {
      await _pump(tester, [
        option('View market', sub: 'Chart and odds'),
        option('Details', sub: 'Shares and price paid'),
        KuteActionCard.option(
          key: const ValueKey('card-Closing conditions'),
          icon: Icons.gavel_rounded,
          title: 'Closing conditions',
          subtitle: 'How it resolves',
          onTap: () {},
        ),
      ]);
      final a = _r(tester, 'View market');
      final b = _r(tester, 'Details');
      final c = _r(tester, 'Closing conditions');
      expect(a.top, b.top);
      expect(a.height, b.height);
      expect(a.width, moreOrLessEquals((390 - 12) / 2));
      expect(c.top - a.bottom, moreOrLessEquals(12));
      expect(chevronIn('View market'), findsNothing);
      expect(chevronIn('Details'), findsNothing);
      expectRow(tester, 'Closing conditions', 'How it resolves',
          Icons.gavel_rounded);
      // The squares' sizes: one family under the chart.
      expect(tester.widget<Text>(find.text('Closing conditions')).style,
          tester.widget<Text>(find.text('View market')).style);
      expect(c.height, lessThan(a.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets('four: a 2 x 2 grid of squares; five: the same over one '
        'full-width card', (tester) async {
      const titles = ['Add margin', 'Protect it', 'Advanced chart', 'Details'];
      await _pump(tester, [for (final t in titles) option(t, sub: 'A line')]);
      for (final t in titles) {
        expect(_r(tester, t).width, moreOrLessEquals((390 - 12) / 2));
        expect(chevronIn(t), findsNothing);
      }
      expect(_r(tester, 'Advanced chart').top,
          greaterThan(_r(tester, 'Add margin').bottom));
      await _pump(tester, [
        for (final t in titles) option(t, sub: 'A line'),
        rulesCard(),
      ]);
      final last = _r(tester, 'Rules and resolution');
      expect(last.width, moreOrLessEquals(390));
      expect(last.top - _r(tester, 'Details').bottom, moreOrLessEquals(12));
      expect(chevronIn('Rules and resolution'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap runs the option with the rows\' selection click',
        (tester) async {
      final haptics = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String?);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      var taps = 0;
      await _pump(tester, [option('Details', onTap: () => taps++)]);
      await tester.tap(find.byKey(const ValueKey('card-Details')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });
  });
}
