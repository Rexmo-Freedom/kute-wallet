// While no session is unlocked, the top-level redirect keeps navigation on
// the cold-start and PIN routes: a deep link (or a stale stack) into a
// money or seed route lands on splash. An unlocked session is never
// redirected, and cold start and onboarding keep their routes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/app_router.dart';

void main() {
  group('lockRedirect', () {
    test('unlocked never redirects', () {
      for (final location in ['/home', '/seed_words', '/home/pay', '/splash']) {
        expect(AppRouter.lockRedirect(locked: false, location: location),
            isNull);
      }
    });

    test('locked allows only the cold-start and PIN routes', () {
      for (final location in AppRouter.lockedAllowlist) {
        expect(AppRouter.lockRedirect(locked: true, location: location), isNull,
            reason: location);
      }
      for (final location in [
        '/home',
        '/home/pay/confirm_send',
        '/seed_words',
        '/backup_wallet',
        '/receive',
        '/settings',
        '/recover_wallet/seed',
        '/wallet/abc',
        '/open_pin/extra',
        '/seed_words?x=1',
      ]) {
        expect(AppRouter.lockRedirect(locked: true, location: location),
            '/splash',
            reason: location);
      }
    });

    test('the allowlist is exactly what cold start and onboarding reach', () {
      expect(AppRouter.lockedAllowlist, {
        '/splash',
        '/start',
        '/open_pin',
        '/set_pin',
        '/confirm_pin',
        '/restore_secrets',
        '/storage_unavailable',
      });
    });
  });

  group('router', () {
    late bool locked;

    GoRouter router() {
      GoRoute stub(String path) =>
          GoRoute(path: path, builder: (_, __) => Text(path));
      final r = GoRouter(
        initialLocation: '/splash',
        redirect: AppRouter.redirectFor(
            sessionLocked: () => locked, initialRoute: '/splash'),
        routes: [
          stub('/splash'),
          stub('/start'),
          stub('/open_pin'),
          stub('/set_pin'),
          stub('/seed_words'),
          GoRoute(
              path: '/home',
              builder: (_, __) => const Text('/home'),
              routes: [stub('pay')]),
        ],
      );
      addTearDown(r.dispose);
      return r;
    }

    Future<GoRouter> pump(WidgetTester tester) async {
      final r = router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      return r;
    }

    String location(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('a deep link into a money or seed route while locked lands '
        'on splash', (tester) async {
      locked = true;
      final r = await pump(tester);
      for (final target in ['/home/pay', '/seed_words', '/home']) {
        r.go(target);
        await tester.pumpAndSettle();
        expect(location(r), '/splash', reason: target);
        expect(find.text('/splash'), findsOneWidget);
      }
    });

    testWidgets('cold start and onboarding routes stay reachable while locked',
        (tester) async {
      locked = true;
      final r = await pump(tester);
      for (final target in ['/start', '/set_pin', '/open_pin', '/splash']) {
        r.go(target);
        await tester.pumpAndSettle();
        expect(location(r), target);
      }
    });

    testWidgets('an unlocked session goes anywhere', (tester) async {
      locked = false;
      final r = await pump(tester);
      for (final target in ['/home', '/seed_words', '/home/pay']) {
        r.go(target);
        await tester.pumpAndSettle();
        expect(location(r), target);
      }
    });

    testWidgets('an absolute deep link returns to the last good location, '
        'or splash when that needs a session', (tester) async {
      locked = false;
      final r = await pump(tester);
      r.go('/home');
      await tester.pumpAndSettle();
      r.go('kute://open?c=CODE');
      await tester.pumpAndSettle();
      expect(location(r), '/home');

      locked = true;
      r.go('kute://open?c=CODE');
      await tester.pumpAndSettle();
      expect(location(r), '/splash');
    });

    testWidgets('locking after the fact redirects the next navigation only',
        (tester) async {
      locked = false;
      final r = await pump(tester);
      r.go('/home');
      await tester.pumpAndSettle();
      locked = true;
      r.go('/seed_words');
      await tester.pumpAndSettle();
      expect(location(r), '/splash');
    });
  });
}
