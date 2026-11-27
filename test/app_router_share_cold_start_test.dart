// A COLD START ON A SHARED MARKET LINK (`/s/...`). The saved wallet list is
// read from disk at start; until it is in, "has a wallet" reads false. The
// route must wait for the list: a person with a wallet in this browser goes
// to splash (then the PIN), never to the no-wallet guest page.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/app_router.dart';

void main() {
  late bool walletOnDisk;
  late bool loaded;
  late Completer<void> load;
  // The read fails: the failing future is made where the router asks for it
  // (an error does not cross from the test's zone into the router's).
  var unreadable = false;

  GoRouter router(String initial) {
    GoRoute stub(String path) =>
        GoRoute(path: path, builder: (_, __) => Text(path));
    final r = GoRouter(
      initialLocation: initial,
      redirect: AppRouter.redirectFor(
        sessionLocked: () => true,
        initialRoute: '/splash',
        // What the app reads: nothing until the list is loaded.
        hasWallet: () => loaded && walletOnDisk,
        guestShareView: () => true,
        walletsLoading: () => loaded
            ? null
            : unreadable
                ? Future<void>.delayed(Duration.zero,
                    () => throw StateError('unreadable'))
                : load.future,
      ),
      routes: [
        stub('/splash'),
        stub('/start'),
        stub('/open_pin'),
        GoRoute(
            path: '/s/:venue/:slug', builder: (_, __) => const Text('guest')),
      ],
    );
    addTearDown(r.dispose);
    return r;
  }

  String location(GoRouter r) =>
      r.routerDelegate.currentConfiguration.uri.toString();

  // The completer is made inside each test: one made in setUp belongs to
  // the zone outside the test's fake clock and never completes under pump.
  void begin() {
    loaded = false;
    unreadable = false;
    load = Completer<void>();
  }

  void finishLoading() {
    loaded = true;
    load.complete();
  }

  testWidgets('a wallet on disk: splash once the list is in, never the guest',
      (tester) async {
    begin();
    walletOnDisk = true;
    final r = router('/s/i/BTC');
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pump();
    expect(find.text('guest'), findsNothing,
        reason: 'the list is not loaded: no decision yet');
    finishLoading();
    await tester.pumpAndSettle();
    expect(location(r), '/splash');
    expect(find.text('guest'), findsNothing);
  });

  testWidgets('no wallet on disk: the guest page once the list is in',
      (tester) async {
    begin();
    walletOnDisk = false;
    final r = router('/s/i/BTC');
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pump();
    expect(find.text('guest'), findsNothing);
    finishLoading();
    await tester.pumpAndSettle();
    expect(location(r), '/s/i/BTC');
    expect(find.text('guest'), findsOneWidget);
  });

  testWidgets('a list that cannot be read: splash owns the failure',
      (tester) async {
    begin();
    walletOnDisk = false;
    unreadable = true;
    final r = router('/s/i/BTC');
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    expect(location(r), '/splash');
  });

  testWidgets('the list already loaded: decided at once', (tester) async {
    begin();
    walletOnDisk = false;
    loaded = true;
    final r = router('/s/i/BTC');
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pump();
    expect(find.text('guest'), findsOneWidget);
  });
}
