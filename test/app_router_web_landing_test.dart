// On web the app opens on Dollars (AppRouter.webLandingRedirect): the
// first time an unlocked session reaches the tab shell after the app
// starts, a plain `/home` lands on `/usd`. Anything naming its place goes
// where it points; a strip without Dollars stays on Bitcoin; iOS and
// Android never redirect. The platform flag and the Dollars check are
// injected, so the VM runs the web rule.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/app_router.dart';

void main() {
  late bool locked;

  Future<GoRouter> pump(WidgetTester tester,
      {bool web = true, bool dollars = true}) async {
    GoRoute stub(String path) =>
        GoRoute(path: path, builder: (_, __) => Text(path));
    final r = GoRouter(
      initialLocation: '/splash',
      redirect: AppRouter.redirectFor(
        sessionLocked: () => locked,
        initialRoute: '/splash',
        web: web,
        dollarsShown: (_) => dollars,
      ),
      routes: [
        stub('/splash'),
        stub('/start'),
        stub('/open_pin'),
        stub('/referrer_code'),
        stub('/usd'),
        GoRoute(
            path: '/home',
            builder: (_, __) => const Text('/home'),
            routes: [stub('pay')]),
      ],
    );
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    return r;
  }

  String location(GoRouter r) =>
      r.routerDelegate.currentConfiguration.uri.toString();

  Future<void> go(WidgetTester tester, GoRouter r, String target) async {
    r.go(target);
    await tester.pumpAndSettle();
  }

  testWidgets('the unlock lands on Dollars, once per start', (tester) async {
    locked = true;
    final r = await pump(tester);
    await go(tester, r, '/open_pin');
    locked = false;
    await go(tester, r, '/home');
    expect(location(r), '/usd');
    // The switch afterwards goes where it is asked.
    await go(tester, r, '/home');
    expect(location(r), '/home');
  });

  testWidgets('wallet creation passes its own screens, then lands on Dollars',
      (tester) async {
    locked = true;
    final r = await pump(tester);
    await go(tester, r, '/start');
    locked = false;
    await go(tester, r, '/referrer_code');
    expect(location(r), '/referrer_code');
    await go(tester, r, '/home');
    expect(location(r), '/usd');
  });

  testWidgets('a link naming its place goes there', (tester) async {
    locked = false;
    for (final target in ['/home?tab=activity', '/home/pay', '/usd?tab=x']) {
      final r = await pump(tester);
      await go(tester, r, target);
      expect(location(r), target, reason: target);
      // The first landing is spent: home stays home.
      await go(tester, r, '/home');
      expect(location(r), '/home', reason: target);
    }
  });

  testWidgets('no Dollars tab: Bitcoin', (tester) async {
    locked = false;
    final r = await pump(tester, dollars: false);
    await go(tester, r, '/home');
    expect(location(r), '/home');
  });

  testWidgets('iOS and Android keep their rule', (tester) async {
    locked = false;
    final r = await pump(tester, web: false);
    await go(tester, r, '/home');
    expect(location(r), '/home');
  });
}
