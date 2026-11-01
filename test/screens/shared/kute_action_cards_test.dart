// The shared big-square action cards (kute_action_cards.dart): the grid's
// layouts for one to four cards, and a disabled card's badge.

import 'package:flutter/material.dart';
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
}
