// The web's top bar on the home tabs (founder, 27 November 2026): one row
// at every width, never a search row under it. As the window narrows the
// actions lose their words, then the field shrinks to its narrowest, then
// it is one icon button after the balance; nothing overlaps. The compact
// balance has a short fixed mask when hidden. (The web is forced with
// KuteBarPane.debugWeb and KuteLayout.debugWeb.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;
import 'package:kute/screens/home/components/desktop_top_bar_money.dart'
    show KuteTopBarBalance;
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/theme/app_theme.dart' show buildLightTheme;

import '../usd/investments_harness.dart';

void main() {
  // The app's own font, as the bar measures it (the test font is wider).
  setUpAll(() async {
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarPane.debugWeb = true;
    KuteLayout.debugWeb = true;
    kuteTopBarMode.value = KuteTopBarMode.labels;
  });
  tearDown(() {
    KuteBarPane.debugWeb = false;
    KuteLayout.debugWeb = false;
    kuteTopSearchInBar.value = true;
    kuteTopBarMode.value = KuteTopBarMode.labels;
  });

  Future<void> pump(WidgetTester tester, Size size,
      {ActiveNavTab tab = ActiveNavTab.usd}) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        size: size,
        designSize: KuteLayout.designSizeFor(size),
        child: Theme(
          data: buildLightTheme().copyWith(
              textTheme:
                  buildLightTheme().textTheme.apply(fontFamily: 'Inter')),
          child: Stack(children: [
            const Positioned.fill(child: UsdAccountScreen()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: KuteTopNavBar(activeTab: tab),
            ),
          ]),
        ));
    // The mode settles over a frame or two (measured, then drawn).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final field = find.byKey(const ValueKey('kute-top-search-field'));
  final button = find.byKey(const ValueKey('kute-top-search-button'));
  final bar = find.byKey(const ValueKey('kute-desktop-top-bar'));

  /// Nothing in the bar's row overlaps: the left group, the search and the
  /// drawn actions stand apart, all inside the bar.
  void expectOneCleanRow(WidgetTester tester, Finder search) {
    final barRect = tester.getRect(bar);
    final s = tester.getRect(search);
    final lockup = tester.getRect(
        find.byKey(const ValueKey('kute-top-bar-lockup')).first);
    final actions = tester.getRect(find
        .descendant(
            of: bar,
            matching: find.byKey(const ValueKey('kute-top-bar-actions')))
        .hitTestable()
        .first);
    expect(s.top, greaterThanOrEqualTo(barRect.top));
    expect(s.bottom, lessThanOrEqualTo(barRect.bottom));
    expect(s.left, greaterThan(lockup.right));
    expect(s.right, lessThan(actions.left));
    expect(actions.right, lessThanOrEqualTo(barRect.right));
  }

  testWidgets('wide: labelled actions, the field in the row, centred',
      (tester) async {
    await pump(tester, const Size(2200, 1080));
    expect(kuteTopBarMode.value, KuteTopBarMode.labels);
    expect(find.descendant(of: bar, matching: field), findsOneWidget);
    expect(button, findsNothing);
    final rect = tester.getRect(field);
    expect(rect.center.dx, moreOrLessEquals(1100, epsilon: 1));
    expect(rect.width, moreOrLessEquals(420, epsilon: 0.5));
    expectOneCleanRow(tester, field);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('narrower: icon actions, the field shrunk, still in the row',
      (tester) async {
    await pump(tester, const Size(1400, 800));
    expect(kuteTopBarMode.value, KuteTopBarMode.icons);
    expect(find.descendant(of: bar, matching: field), findsOneWidget);
    expect(tester.getSize(field).width, inInclusiveRange(240, 420));
    expectOneCleanRow(tester, field);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  for (final width in [640.0, 840.0]) {
    testWidgets('$width wide: the search is an icon button in the row',
        (tester) async {
      await pump(tester, Size(width, 800));
      expect(kuteTopBarMode.value, KuteTopBarMode.button);
      expect(field, findsNothing);
      expect(find.descendant(of: bar, matching: button), findsOneWidget);
      expect(tester.getSize(button), const Size(38, 38));
      expectOneCleanRow(tester, button);
      // Never a search row under the bar.
      expect(find.byKey(const ValueKey('kute-top-search-field')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }

  test('the mode: one threshold each way, a little hysteresis', () {
    const l = KuteTopBarMode.labels, i = KuteTopBarMode.icons;
    const b = KuteTopBarMode.button;
    expect(kuteTopBarModeFor(l, 420, 600), l);
    expect(kuteTopBarModeFor(l, 419, 600), i);
    // Back to labels only with the margin.
    expect(kuteTopBarModeFor(i, 425, 600), i);
    expect(kuteTopBarModeFor(i, 432, 600), l);
    expect(kuteTopBarModeFor(i, 0, 240), i);
    expect(kuteTopBarModeFor(i, 0, 239), b);
    expect(kuteTopBarModeFor(b, 0, 245), b);
    expect(kuteTopBarModeFor(b, 0, 252), i);
  });

  testWidgets('a hidden balance is a short fixed mask, never wider',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: const Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: KuteTopBarBalance(
            mark: r'$',
            hidden: true,
            figure: Text(r'$1,234,567.89'),
            line: Text('Available ••••••••••••'),
          ),
        ),
      ),
    ));
    final mask = find.byKey(const ValueKey('top-bar-balance-hidden'));
    expect(mask, findsOneWidget);
    expect(find.text(r'$••••'), findsOneWidget);
    expect(find.text('••••'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('top-bar-compact-balance')))
            .width,
        lessThanOrEqualTo(120));
  });

  testWidgets('a seven-figure balance never passes the block\'s cap',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: KuteTopBarBalance(
            mark: r'$',
            figure: Text(r'$12,345,678.90',
                style: KuteTopBarBalance.figureStyle(Colors.black)),
            line: const Text('▲ \$123,456.78 (+12.3%) · Available \$9,999,999.99'),
          ),
        ),
      ),
    ));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('top-bar-compact-balance')))
            .width,
        lessThanOrEqualTo(KuteTopBarBalance.maxWidth));
    expect(tester.takeException(), isNull);
  });
}
