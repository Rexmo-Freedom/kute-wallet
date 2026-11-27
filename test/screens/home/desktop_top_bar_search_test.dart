// The web's desktop top bar (founder, 27 November 2026: "search and manage
// should be in the centre"): on a window with the room, the search field
// sits in the bar, centred on the window, and the page has no search row;
// on a narrower one the field moves to its own row under the bar and the
// bar never overlaps. (The web is forced with KuteBarPane.debugWeb.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;
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
  });
  tearDown(() {
    KuteBarPane.debugWeb = false;
    kuteTopSearchInBar.value = false;
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        size: size,
        designSize: KuteLayout.designSizeFor(size),
        child: Theme(
          data: buildLightTheme().copyWith(
              textTheme:
                  buildLightTheme().textTheme.apply(fontFamily: 'Inter')),
          child: const Stack(children: [
            Positioned.fill(child: UsdAccountScreen()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: KuteTopNavBar(activeTab: ActiveNavTab.usd),
            ),
          ]),
        ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final field = find.byKey(const ValueKey('kute-top-search-field'));
  final bar = find.byKey(const ValueKey('kute-desktop-top-bar'));

  testWidgets('wide: the field in the bar, centred on the window, no row',
      (tester) async {
    // Wider than the real threshold: the balance's rolling digits draw in
    // the test's own font here, much wider than Inter.
    await pump(tester, const Size(2200, 1080));
    expect(kuteTopSearchInBar.value, isTrue);
    // One field, the bar's (the page's row is gone).
    expect(field, findsOneWidget);
    expect(find.descendant(of: bar, matching: field), findsOneWidget);
    final rect = tester.getRect(field);
    expect(rect.center.dx, moreOrLessEquals(1100, epsilon: 1));
    expect(rect.width, inInclusiveRange(280, 560));
    await unmountInvestments(tester);
  });

  for (final width in [1100.0, 1280.0]) {
    testWidgets('$width wide: the field on its own row, the bar one row',
        (tester) async {
      await pump(tester, Size(width, 800));
      expect(kuteTopSearchInBar.value, isFalse);
      // The bar keeps no visible field (laid out at no size).
      final inBar = find.descendant(of: bar, matching: field);
      expect(inBar.evaluate().every((e) => tester.getSize(find.byWidget(e.widget)).isEmpty),
          isTrue);
      final row = find.byWidgetPredicate((w) =>
          w.key == const ValueKey('kute-top-search-field') &&
          !find.descendant(of: bar, matching: find.byWidget(w)).evaluate().isNotEmpty);
      expect(row, findsOneWidget);
      expect(tester.getRect(row).top,
          greaterThanOrEqualTo(tester.getRect(bar).bottom));
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }
}
