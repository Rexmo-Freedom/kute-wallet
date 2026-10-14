// Receive opens as a tall bottom sheet. The dock opens it directly
// (kute_bottom_action_bar_test.dart covers both docks); the old routes stay
// for deep links and present the very same sheet over the screen beneath,
// so there is no second, full-screen receive.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/theme/app_theme.dart';

const _home = 'home underneath';

Future<GoRouter> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ReceiveSheets.debugBitcoinBody = (_) => const _Body('btc');
  ReceiveSheets.debugUsdBody = (_) => const _Body('usd');
  addTearDown(() {
    ReceiveSheets.debugBitcoinBody = null;
    ReceiveSheets.debugUsdBody = null;
  });
  // The app's shape: the receive routes sit on the home route, so a link
  // lands with home beneath the sheet.
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: Center(child: Text(_home))),
      routes: [
        GoRoute(
          path: 'receive',
          name: kBitcoinReceiveRouteName,
          pageBuilder: (_, state) => ReceiveSheetPage(
              key: state.pageKey, name: state.name, usd: false),
        ),
        GoRoute(
          path: 'receive_dollars',
          name: kUsdReceiveRouteName,
          pageBuilder: (_, state) =>
              ReceiveSheetPage(key: state.pageKey, name: state.name, usd: true),
        ),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()]),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// Stands in for a receive: the real sheet frame around a QR plate.
class _Body extends StatelessWidget {
  const _Body(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => ReceiveSheetFrame(
        leading: const SizedBox.shrink(),
        title: Text(label),
        child: const Align(
          alignment: Alignment.topCenter,
          child: ReceiveQrPlate(child: SizedBox.expand()),
        ),
      );
}

Size _plate(WidgetTester tester) => tester.getSize(find
    .descendant(
        of: find.byType(ReceiveQrPlate), matching: find.byType(Container))
    .first);

void main() {
  testWidgets(
      'a /receive deep link opens the Bitcoin receive as the sheet over '
      'the screen beneath, and a swipe down closes it', (tester) async {
    final router = await _pump(tester);
    router.go('/receive');
    await tester.pumpAndSettle();
    expect(find.text('btc'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.text('btc')));
    expect(route, isA<ModalBottomSheetRoute<void>>());
    expect(route!.settings.name, kBitcoinReceiveRouteName);
    // Home stays beneath: the sheet is not a full-screen page.
    expect(find.text(_home), findsOneWidget);
    final frame = tester.getRect(find.byType(ReceiveSheetFrame));
    expect(frame.bottom, 844);
    expect(frame.height, lessThanOrEqualTo(844 * kReceiveSheetMaxHeight + 0.5));

    await tester.fling(find.text('btc'), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(find.text('btc'), findsNothing);
    expect(find.text(_home), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets(
      'pushing receiveDollars (a link, or the Investments deposit\'s '
      'Receive row) opens the Investments receive as the same sheet',
      (tester) async {
    final router = await _pump(tester);
    router.pushNamed(kUsdReceiveRouteName);
    await tester.pumpAndSettle();
    expect(find.text('usd'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('usd'))),
        isA<ModalBottomSheetRoute<void>>());
    expect(find.text(_home), findsOneWidget);

    // Tapping the scrim closes it too.
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(find.text('usd'), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('the QR plate is as large as fits, between 260 and 380pt',
      (tester) async {
    final router = await _pump(tester);
    router.go('/receive');
    await tester.pumpAndSettle();
    // 87% of a 390pt-wide sheet: at least 330pt, never over 380.
    final side = _plate(tester);
    expect(side.width, side.height);
    expect(side.width, closeTo(390 * 0.87, 0.5));
    expect(side.width, greaterThanOrEqualTo(330));
    expect(side.width, lessThanOrEqualTo(380));

    // A small phone keeps the 260 floor, a large one stops at 380.
    tester.view.physicalSize = const Size(280, 640);
    await tester.pumpAndSettle();
    expect(_plate(tester).width, 260);
    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    expect(_plate(tester).width, 380);
  });
}
