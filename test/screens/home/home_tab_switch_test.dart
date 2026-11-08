// The top of the homes (founder, 8 November 2026, option A): the Bitcoin |
// Dollars switch, its thumb on the shell's own page position, centred on the
// screen with an empty slot left of the round +-and-gear. Everything runs in
// the real AppShell:
//
//   * a tap slides the thumb and switches the branch, reporting as it did;
//     Reduce Motion moves it at once;
//   * a swipe drags the thumb under the finger, with no animation of its
//     own; it lands, or springs back, with the page;
//   * the switch is centred, its items equal, nothing overflows at 320, in
//     a long locale, at large text; each target is 44 pt at least;
//   * screen readers hear a tab bar of tabs with their selection;
//   * the round button keeps its glyph, its press, its door and its tracking;
//   * the bar still slides away with the page's scroll;
//   * any other wallet keeps its own strip, up to the button;
//   * with no pager, the thumb springs to the active tab by itself.

import 'dart:ui' show SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/screens/home/components/home_tab_switch.dart';
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/screens/shared/service_tab_strip.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import 'top_switch_harness.dart';
import 'package:kute/screens/shared/open_once.dart';

final _thumb = find.byKey(const ValueKey('home-tab-switch-thumb'));
final _switch = find.byType(HomeTabSwitch);
final _track = find.byKey(const ValueKey('home-tab-switch-track'));
final _bitcoin = find.text('Bitcoin');
final _dollars = find.text('Dollars');

/// The thumb's place along the track: 0 under Bitcoin, 1 under Dollars.
double _place(WidgetTester tester) {
  final thumb = tester.getRect(_thumb);
  final track = tester.getRect(_track);
  const inset = 0.0;
  final travel = track.width - 2 * inset - thumb.width;
  return (thumb.left - track.left - inset) / travel;
}

Color _colorOf(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style!.color!;

List<(String, Map<String, Object>?)> _events() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}

/// Lets the page's spring land, and the hub glyph's first play end.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(KuteTopNavBar)))
        .routeInformationProvider
        .value
        .uri
        .path;

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  testWidgets('a tap slides the thumb on the page and switches the branch',
      (tester) async {
    final events = _events();
    await pumpTopSwitchShell(tester);
    await _settle(tester);
    expect(_place(tester), moreOrLessEquals(0));
    final c = tester.element(_switch).colors;
    expect(_colorOf(tester, _bitcoin), c.textPrimary);
    expect(_colorOf(tester, _dollars), c.textTertiary);

    await tester.tap(_dollars);
    // Mid-way: it travels, it does not jump.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_place(tester), inExclusiveRange(0.0, 1.0));
    await _settle(tester);
    expect(_place(tester), moreOrLessEquals(1));
    expect(_location(tester), '/usd');
    expect(_colorOf(tester, _dollars), c.textPrimary);
    expect(_colorOf(tester, _bitcoin), c.textTertiary);
    expect(events, contains(predicate<(String, Map<String, Object>?)>((e) =>
        e.$1 == 'shell_tab_changed' &&
        e.$2!['method'] == 'tap' &&
        e.$2!['from_tab'] == 'home' &&
        e.$2!['to_tab'] == 'usd')));
    expect(events.map((e) => e.$1), contains('usd_tab_opened'));

    await tester.tap(_bitcoin);
    await _settle(tester);
    expect(_place(tester), moreOrLessEquals(0));
    expect(_location(tester), '/home');
    expect(tester.takeException(), isNull);
  });

  testWidgets('under Reduce Motion the thumb moves at once', (tester) async {
    await pumpTopSwitchShell(tester, reduceMotion: true);
    await tester.pump();
    await tester.tap(_dollars);
    await tester.pump();
    await tester.pump();
    expect(_place(tester), moreOrLessEquals(1));
    await _settle(tester);
    expect(_location(tester), '/usd');
  });

  testWidgets('a swipe drags the thumb under the finger and lands with it',
      (tester) async {
    final events = _events();
    await pumpTopSwitchShell(tester);
    await _settle(tester);

    final finger = await tester.startGesture(const Offset(350, 500));
    await finger.moveBy(const Offset(-40, 0));
    await tester.pump();
    final first = _place(tester);
    expect(first, greaterThan(0));
    await finger.moveBy(const Offset(-129, 0));
    await tester.pump();
    // 129 px of a 430 wide screen is 0.3 of a page, and no animation runs.
    expect(_place(tester) - first, moreOrLessEquals(0.3, epsilon: 0.001));
    // Held still: exactly where the finger put it, with no frame scheduled
    // to carry it anywhere.
    final held = _place(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_place(tester), moreOrLessEquals(held));
    // The colours ride it; the selection is still the tab the shell is on.
    final c = tester.element(_switch).colors;
    expect(_colorOf(tester, _dollars), isNot(c.textTertiary));
    expect(_colorOf(tester, _dollars), isNot(c.textPrimary));
    expect(_location(tester), '/home');

    await finger.moveBy(const Offset(-60, 0));
    await tester.pump();
    await finger.up();
    await _settle(tester);
    expect(_place(tester), moreOrLessEquals(1));
    expect(_location(tester), '/usd');
    expect(events, contains(predicate<(String, Map<String, Object>?)>((e) =>
        e.$1 == 'shell_tab_changed' && e.$2!['method'] == 'swipe')));
  });

  testWidgets('a swipe that does not land springs the thumb back',
      (tester) async {
    final events = _events();
    await pumpTopSwitchShell(tester);
    await _settle(tester);
    final finger = await tester.startGesture(const Offset(350, 500));
    await finger.moveBy(const Offset(-40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await finger.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await finger.up();
    await _settle(tester);
    expect(_place(tester), moreOrLessEquals(0));
    expect(_location(tester), '/home');
    expect(events.map((e) => e.$1), isNot(contains('shell_tab_changed')));
  });

  testWidgets('a link moves the thumb with the page', (tester) async {
    await pumpTopSwitchShell(tester);
    await _settle(tester);
    GoRouter.of(tester.element(find.byType(KuteTopNavBar))).go('/usd');
    await _settle(tester);
    expect(_place(tester), moreOrLessEquals(1));
  });

  for (final (size, locale, scale) in [
    (const Size(320, 568), null, 1.0),
    (const Size(320, 568), const Locale('ja'), 1.0),
    (const Size(320, 568), const Locale('de'), 1.3),
    (const Size(320, 568), const Locale('de'), 3.0),
    (const Size(375, 812), null, 1.3),
    (const Size(430, 932), null, 1.0),
    (const Size(430, 932), const Locale('el'), 2.0),
  ]) {
    testWidgets('centred, equal and in clear room at $size, $locale, ${scale}x',
        (tester) async {
      await pumpTopSwitchShell(tester,
          size: size, locale: locale, textScale: scale);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final track = tester.getRect(_track);
      expect(track.center.dx, moreOrLessEquals(size.width / 2, epsilon: 0.01));
      final button = tester
          .getRect(find.byKey(const ValueKey('financial-hub-square')));
      // Clear of the button, and as clear of the left edge, the
      // button's whole slot and more.
      expect(track.right, lessThan(button.left));
      expect(button.right, lessThanOrEqualTo(size.width));
      expect(track.left, greaterThan(size.width - button.left));
      // Equal halves, each the target of 44 pt at least.
      final halves = tester
          .renderObjectList<RenderBox>(find.descendant(
              of: _switch,
              matching: find.byWidgetPredicate((w) =>
                  w is Semantics && w.properties.role == SemanticsRole.tab)))
          .toList();
      expect(halves, hasLength(2));
      expect(halves[0].size.width, moreOrLessEquals(halves[1].size.width));
      expect(halves[0].size.height, greaterThanOrEqualTo(44));
      expect(_place(tester), moreOrLessEquals(0));
    });
  }

  testWidgets('the words that fit keep their size; the row is not squeezed',
      (tester) async {
    await pumpTopSwitchShell(tester);
    await _settle(tester);
    // The fitted box leaves the words at their own size.
    expect(tester.getRect(_bitcoin).width,
        moreOrLessEquals(tester.getSize(_bitcoin).width));
    expect(tester.getRect(_dollars).width,
        moreOrLessEquals(tester.getSize(_dollars).width));
  });

  testWidgets('screen readers hear a tab bar of tabs with their selection',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTopSwitchShell(tester);
    await _settle(tester);

    final bitcoin = tester.getSemantics(find.bySemanticsLabel('Bitcoin'));
    final dollars = tester.getSemantics(find.bySemanticsLabel('Dollars'));
    expect(bitcoin.getSemanticsData().role, SemanticsRole.tab);
    expect(dollars.getSemanticsData().role, SemanticsRole.tab);
    expect(bitcoin.parent!.getSemanticsData().role, SemanticsRole.tabBar);
    expect(bitcoin.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue);
    expect(dollars.getSemanticsData().flagsCollection.isSelected,
        Tristate.isFalse);

    // The accessibility tap goes where a finger does.
    tester.semantics.tap(find.semantics.byLabel('Dollars'));
    await _settle(tester);
    expect(_location(tester), '/usd');
    expect(
        tester
            .getSemantics(find.bySemanticsLabel('Dollars'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue);
    // The validity checks a tab bar's role carries raised nothing.
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('the round button: its glyph, press, door and tracking',
      (tester) async {
    final events = _events();
    await pumpTopSwitchShell(tester);
    await _settle(tester);

    expect(find.byType(HubPlusGearGlyph), findsOneWidget);
    expect(find.bySemanticsLabel('Financial hub and settings'), findsOneWidget);
    // The neutral square chip, not a circle.
    final square = tester.widget<Container>(
        find.byKey(const ValueKey('financial-hub-square')));
    expect((square.decoration! as BoxDecoration).borderRadius,
        AppRadius.buttonBorder);
    expect(tester.getSize(find.byKey(const ValueKey('financial-hub-square'))).width,
        moreOrLessEquals(46.w));

    // A press plays the glyph's quick swap as the finger lands.
    final glyph = find.descendant(
        of: find.byType(HubPlusGearGlyph),
        matching: find.byType(AnimatedBuilder));
    final finger =
        await tester.startGesture(tester.getCenter(find.byType(HubPlusGearGlyph)));
    await tester.pump(const Duration(milliseconds: 120));
    final controller =
        tester.widget<AnimatedBuilder>(glyph).listenable as AnimationController;
    expect(controller.isAnimating, isTrue);
    await finger.up();
    await _settle(tester);

    expect(find.text('Financial hub'), findsOneWidget);
    expect(
        events,
        contains(predicate<(String, Map<String, Object>?)>((e) =>
            e.$1 == 'wallet_actions_opened' && e.$2!['source'] == 'home_plus')));
  });

  testWidgets('the source names the home it was opened on', (tester) async {
    final events = _events();
    await pumpTopSwitchShell(tester, location: '/usd');
    await _settle(tester);
    await tester.tap(find.byType(HubPlusGearGlyph));
    await _settle(tester);
    expect(
        events,
        contains(predicate<(String, Map<String, Object>?)>((e) =>
            e.$1 == 'wallet_actions_opened' && e.$2!['source'] == 'usd_plus')));
  });

  testWidgets('on a narrow phone the square scales, its target stays 44',
      (tester) async {
    await pumpTopSwitchShell(tester, size: const Size(320, 568));
    await _settle(tester);
    final centre = tester.getCenter(find.byType(HubPlusGearGlyph));
    // Just past the drawn square (about 34 here), inside the 44 pt target.
    await tester.tapAt(centre + const Offset(-21, 0));
    await _settle(tester);
    expect(find.text('Financial hub'), findsOneWidget);
  });

  testWidgets('the bar still slides away with the scroll and comes back',
      (tester) async {
    await pumpTopSwitchShell(tester);
    await _settle(tester);
    final container = ProviderScope.containerOf(tester.element(_switch));
    container.read(navBarHiddenProvider.notifier).state = true;
    await _settle(tester);
    expect(tester.getRect(_track).bottom, lessThanOrEqualTo(0));
    await tester.tapAt(const Offset(160, 5));
    await tester.pump();
    expect(_location(tester), '/home');
    container.read(navBarHiddenProvider.notifier).state = false;
    await _settle(tester);
    expect(tester.getRect(_track).top, greaterThan(0));
  });

  testWidgets('a Ledger keeps its own strip up to the round button, no slot',
      (tester) async {
    await pumpTopSwitchShell(tester,
        wallets: [kTopSwitchSpending, kTopSwitchLedger],
        shellWalletId: 'ledger');
    await _settle(tester);
    expect(_switch, findsNothing);
    final strip = tester.getRect(find.byType(ServiceTabStrip));
    expect(strip.left, moreOrLessEquals(12.w));
    expect(find.byType(HubPlusGearGlyph), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no pager the thumb springs to the active tab by itself',
      (tester) async {
    var dollarsActive = false;
    late StateSetter set;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(builder: (context, setState) {
              set = setState;
              return HomeTabSwitch(tabs: [
                ServiceTabData(
                    icon: Icons.currency_bitcoin_rounded,
                    label: 'Bitcoin',
                    active: !dollarsActive,
                    onTap: () {}),
                ServiceTabData(
                    icon: Icons.attach_money_rounded,
                    label: 'Dollars',
                    active: dollarsActive,
                    onTap: () {}),
              ]);
            }),
          ),
        ),
      ),
    ));
    expect(_place(tester), moreOrLessEquals(0));
    set(() => dollarsActive = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_place(tester), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(_place(tester), moreOrLessEquals(1));
  });
}
