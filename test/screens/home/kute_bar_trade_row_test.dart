// The trade row (kute_bar_trade_row.dart; kute_bar_context.dart, THE TRADE
// ROW; founder, 4 November 2026): a market page's trade buttons are the
// floating bar, pills in the market's colours side by side with the round
// Sal button at the row's end, inside the screen's 16 px gutters; every
// tap lands on the pill it is drawn on (no translate), the gaps let taps
// through to the page, and the row never folds while the page scrolls.
// An open position's red primary carries the same round button at its
// right, which leaves with the context.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

final _navKey = GlobalKey<NavigatorState>();

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [aiEnabledProvider.overrideWith((_) async => true)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: _navKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) => Stack(children: [
          NotificationListener<ScrollNotification>(
            onNotification: kuteBarScroll.report,
            child: child!,
          ),
          const KuteShellBar(),
        ]),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// A page under the bar: a long list, and a tap anywhere on it counted.
Widget _page(KuteBarContext ctx, {VoidCallback? onPageTap}) =>
    KuteBarContextScope(
      barContext: ctx,
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPageTap,
          child: ListView.builder(
            itemCount: 60,
            itemBuilder: (_, i) => SizedBox(height: 56, child: Text('Row $i')),
          ),
        ),
      ),
    );

Future<void> _push(WidgetTester tester, Widget page) async {
  _navKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'market'), builder: (_) => page));
  await tester.pumpAndSettle();
}

const _market = KuteBarContext(
  label: 'Send to a friend',
  sublabel: 'Send the market',
  clip: 'share',
);

/// Whether a tap at [finder]'s centre reaches its render box.
bool _tapLands(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == box);
}

Finder _trade(String id) => find.byKey(ValueKey('kute-bar-trade-$id'));
final Finder _share = find.byKey(const ValueKey('kute-bar-share'));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
  });

  testWidgets(
      'the row: Invest twice Short\'s width, the round Sal button at the '
      'end, 52 tall in the 16 px gutters, the market colours with white '
      'words, and every tap lands on its own pill', (tester) async {
    await _pump(tester);
    var invest = 0, short = 0, page = 0, shares = 0;
    await _push(
        tester,
        _page(
          KuteBarContext.trade(
            trades: [
              KuteBarTrade(
                  id: 'invest',
                  label: 'Invest',
                  fill: AppColors.marketUp,
                  flex: 2,
                  onTap: () => invest++),
              KuteBarTrade(
                  id: 'short',
                  label: 'Short',
                  fill: AppColors.marketDown,
                  onTap: () => short++),
            ],
            share: KuteBarShare(barContext: _market, brag: () => shares++),
          ),
          onPageTap: () => page++,
        ));
    expect(find.byKey(const ValueKey('kute-bar-trade-row')), findsOneWidget);
    final a = tester.getRect(_trade('invest'));
    final b = tester.getRect(_trade('short'));
    final s = tester.getRect(_share);
    // One line, left to right, the bar's height.
    for (final r in [a, b]) {
      expect(r.height, moreOrLessEquals(KuteBarPrimaryButton.height));
      expect(r.center.dy, moreOrLessEquals(s.center.dy, epsilon: 0.5));
    }
    expect(s.width, moreOrLessEquals(KuteSalPill.collapsedSize));
    expect(a.right, lessThan(b.left));
    expect(b.right, lessThan(s.left));
    expect(a.width, moreOrLessEquals(b.width * 2, epsilon: 1));
    // The screen's 16 px gutters (16 design px at 390 of 430).
    const gutter = 16 * 390 / 430;
    expect(a.left, moreOrLessEquals(gutter, epsilon: 0.5));
    expect(s.right, moreOrLessEquals(390 - gutter, epsilon: 0.5));
    // At the foot, never over the screen's edge.
    expect(s.bottom, lessThanOrEqualTo(844));
    expect(s.bottom, greaterThan(844 - 20));
    // The market's solid colours, the words in white.
    final up = tester.widget<Container>(_trade('invest')).decoration!
        as BoxDecoration;
    expect(up.color, AppColors.marketUp);
    expect(up.borderRadius, KuteBarPrimaryButton.radius);
    final words =
        find.descendant(of: _trade('invest'), matching: find.text('Invest'));
    expect(tester.widget<Text>(words).style!.color, Colors.white);
    // No words on the round button.
    expect(find.descendant(of: _share, matching: find.byType(Text)),
        findsNothing);

    // Taps land where the pills are drawn.
    for (final f in [_trade('invest'), _trade('short'), _share]) {
      expect(_tapLands(tester, f), isTrue, reason: '$f');
    }
    await tester.tap(_trade('invest'));
    await tester.pump();
    await tester.tap(_trade('short'));
    await tester.pump();
    await tester.tap(_share);
    await tester.pump();
    expect((invest, short, shares, page), (1, 1, 1, 0));
    // The air between two pills is the page's.
    await tester.tapAt(Offset((a.right + b.left) / 2, a.center.dy));
    await tester.pump();
    expect(page, 1);
    expect((invest, short), (1, 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a trade with no fill is the light pill; a value follows the words',
      (tester) async {
    await _pump(tester);
    await _push(
        tester,
        _page(KuteBarContext.trade(
          trades: [
            KuteBarTrade(
                id: 'yes',
                label: 'Yes',
                value: '62%',
                fill: AppColors.marketUp,
                onTap: () {}),
            KuteBarTrade(id: 'sell', label: 'Sell', onTap: () {}),
          ],
          share: const KuteBarShare(barContext: _market),
        )));
    final light =
        tester.widget<Container>(_trade('sell')).decoration! as BoxDecoration;
    expect(light.color, Colors.white);
    expect(
        tester
            .widget<Text>(find.descendant(
                of: _trade('sell'), matching: find.text('Sell')))
            .style!
            .color,
        AppColorsExtension.light().textPrimary);
    final yes = tester.getRect(
        find.descendant(of: _trade('yes'), matching: find.text('Yes')));
    final value = tester.getRect(
        find.byKey(const ValueKey('kute-bar-trade-yes-value')));
    expect(value.left, greaterThan(yes.right));
    expect(find.bySemanticsLabel('Yes, 62%'), findsOneWidget);
    expect(find.bySemanticsLabel('Send to a friend'), findsOneWidget);
  });

  testWidgets('the row never folds while the page scrolls down',
      (tester) async {
    await _pump(tester);
    await _push(
        tester,
        _page(KuteBarContext.trade(
          trades: [
            KuteBarTrade(
                id: 'yes',
                label: 'Yes',
                fill: AppColors.marketUp,
                onTap: () {}),
            KuteBarTrade(
                id: 'no',
                label: 'No',
                fill: AppColors.marketDown,
                onTap: () {}),
          ],
          share: const KuteBarShare(barContext: _market),
        )));
    final before = tester.getRect(_trade('yes'));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Row 3')));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(_trade('yes')), before);
    expect(tester.widget<KuteSalPill>(find.descendant(
            of: _share, matching: find.byType(KuteSalPill)))
        .collapsed, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(_trade('yes')), before);
  });

  testWidgets(
      'a position\'s red primary carries the round Sal button at its '
      'right: both take their taps; the button leaves with the context',
      (tester) async {
    await _pump(tester);
    var closes = 0, brags = 0;
    await _push(
        tester,
        _page(KuteBarContext.primary(
          label: 'Close position',
          onPrimary: () => closes++,
          disabledLabel: 'Position closed',
          style: KuteBarPrimaryStyle.destructive,
          share: KuteBarShare(barContext: _market, brag: () => brags++),
        )));
    final primary = find.byKey(const ValueKey('kute-bar-primary-button'));
    expect(primary, findsOneWidget);
    expect(_share, findsOneWidget);
    final p = tester.getRect(primary);
    final s = tester.getRect(_share);
    expect(s.left, greaterThan(p.right));
    expect(s.center.dy, moreOrLessEquals(p.center.dy, epsilon: 0.5));
    // The pair is centred as the button alone was.
    expect((p.left + s.right) / 2, moreOrLessEquals(195, epsilon: 1));
    expect(find.bySemanticsLabel('Brag about it'), findsOneWidget);
    expect(_tapLands(tester, primary), isTrue);
    expect(_tapLands(tester, _share), isTrue);
    await tester.tap(primary);
    await tester.pump();
    await tester.tap(_share);
    await tester.pump();
    expect((closes, brags), (1, 1));

    // A sheet over the page whose button has no share: the circle goes.
    await _push(
        tester,
        _page(KuteBarContext.primary(
            label: 'Close \$12', onPrimary: () {}, disabledLabel: 'Close')));
    expect(find.byKey(const ValueKey('kute-bar-primary-button')),
        findsOneWidget);
    expect(_share, findsNothing);
    _navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_share, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
