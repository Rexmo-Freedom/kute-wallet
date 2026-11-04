// The shared big-square action cards (kute_action_cards.dart): the grid's
// layouts for one to four cards, a disabled card's badge, and the smaller
// option cards under a market's or a position's chart.

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

Future<void> _pump(WidgetTester tester, List<KuteActionCard> cards) async {
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
          children: [KuteActionCardGrid(cards: cards)],
        ),
      ),
    ),
  ));
  await tester.pump();
}

Rect _r(WidgetTester tester, String title) =>
    tester.getRect(find.byKey(ValueKey('card-$title')));

void main() {
  testWidgets('one card is full width, at least 170 tall', (tester) async {
    await _pump(tester, [_card('A', onTap: () {})]);
    final a = _r(tester, 'A');
    expect(a.width, moreOrLessEquals(390));
    expect(a.height, greaterThanOrEqualTo(kKuteActionCardMinHeight));
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
      expect(a.height, lessThan(kKuteActionCardMinHeight));
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

    testWidgets('a lone option card, or an odd last one, keeps its column: '
        'half the width, never a full-width band', (tester) async {
      await _pump(tester, [option('Rules and resolution', sub: 'Ends Nov 5')]);
      final lone = _r(tester, 'Rules and resolution');
      expect(lone.left, moreOrLessEquals(20));
      expect(lone.width, moreOrLessEquals((390 - 12) / 2));
      await _pump(tester, [
        option('View market', sub: 'Chart and odds'),
        option('Details', sub: 'Shares and price paid'),
        option('Closing conditions', sub: 'How it resolves'),
      ]);
      final a = _r(tester, 'View market');
      final c = _r(tester, 'Closing conditions');
      expect(c.top, greaterThan(a.bottom));
      expect(c.left, moreOrLessEquals(a.left));
      expect(c.width, moreOrLessEquals(a.width));
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
