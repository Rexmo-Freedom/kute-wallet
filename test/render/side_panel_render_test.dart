// The money flows at the side on a laptop (founder, 24 November 2026, of
// Receive and the Bitcoin receive opened from the top bar as centred
// panels: "these ones should open to the side like on fullscreen mode";
// kute_wide_frames.dart, KuteSideFlow). A flow armed as the top bar arms
// it opens at the window's right edge, full height, `kuteSidePanelWidth`
// wide, and a step opened from it shows in the same place; unarmed, a
// sheet keeps the centred panel; a phone keeps its bottom sheet. The
// scanner in a panel draws one close and no drag handle.
//
// Also a look by eye, light and dark, at 1440x900, 1180x820, 1920x1080
// and 430x932 (a phone, as before), written only when asked:
//   SIDE_PANEL_RENDER=<dir> flutter test test/render/side_panel_render_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/shared/kute_dialog.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/scanner/scanner_sheet.dart'
    show showRoutingScannerSheet;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

import '../helpers/bitcoin_receive_harness.dart';
import '../helpers/fake_scanner_camera.dart';
import '../helpers/runtime_policy_fixture.dart';

final _dir = Platform.environment['SIDE_PANEL_RENDER'];

const _card = ValueKey('kute-dialog-card');

Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

/// [open] as a top bar action opens it: in the action's side zone.
Future<void> Function(BuildContext) _fromTopBar(
        Future<void> Function(BuildContext) open) =>
    (context) => KuteSideFlow.run(() => open(context));

/// A page that opens a panel as the router builds it (the way the
/// scanner's hand-off reaches Send: `router.push`, the route built in the
/// next frame).
class _PanelPage extends Page<void> {
  const _PanelPage({super.key, required this.label});

  final String label;

  @override
  Route<void> createRoute(BuildContext context) => KuteDialogRoute<void>(
        settings: this,
        builder: (_) => SizedBox(height: 300, child: Text(label)),
      );
}

/// A laptop window with a router: `/` holds [home], `/next` is a panel
/// page.
Future<GoRouter> _pumpRouter(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
        path: '/next',
        pageBuilder: (_, state) =>
            _PanelPage(key: state.pageKey, label: 'next panel')),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(const Size(1440, 900)),
      builder: (_, __) => MaterialApp.router(
        theme: buildLightTheme(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pump();
  return router;
}

/// Opens a centred-or-side panel that says [label].
Future<void> _panel(BuildContext context, String label,
        {WidgetBuilder? builder}) =>
    showKuteDialog<void>(
      context: context,
      builder: builder ?? (_) => SizedBox(height: 300, child: Text(label)),
    );

/// Whether the panel holding [label] sits at the window's right edge.
bool _atSide(WidgetTester tester, String label) {
  final card = find.ancestor(of: find.text(label), matching: find.byKey(_card));
  final rect = tester.getRect(card.first);
  return rect.right == 1440 && rect.top == 0 && rect.height == 900;
}

/// The panel sits at the window's right edge, full height.
void _expectSide(WidgetTester tester, Size window, {int count = 1}) {
  final cards = find.byKey(_card);
  expect(cards, findsNWidgets(count));
  final rect = tester.getRect(cards.last);
  expect(rect.right, window.width);
  expect(rect.top, 0);
  expect(rect.height, window.height);
  expect(rect.width, kuteSidePanelWidth);
}

void main() {
  setUp(() async {
    KuteSideFlow.reset();
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    await policy.refresh();
    TrackingService.debugTrackObserver = (_, __) {};
  });

  tearDown(() {
    KuteSideFlow.reset();
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
  });

  const laptop = Size(1440, 900);

  testWidgets('Receive from the top bar opens at the side, its steps too',
      (tester) async {
    await openBitcoinReceive(tester, ReceiveWorld(),
        size: laptop, open: _fromTopBar(showBitcoinQrReceiveSheet));
    await tester.pump(const Duration(milliseconds: 400));
    _expectSide(tester, laptop);
    // Request amount: a step from a step, in the same place.
    await tester.tap(find.byKey(const ValueKey('receive-request-amount')));
    await settleReceive(tester);
    await tester.pump(const Duration(milliseconds: 400));
    _expectSide(tester, laptop, count: 2);
    expect(tester.takeException(), isNull);
    await closeBitcoinReceive(tester);
  });

  testWidgets('a sheet opened elsewhere keeps the centred panel',
      (tester) async {
    await openBitcoinReceive(tester, ReceiveWorld(), size: laptop);
    await tester.pump(const Duration(milliseconds: 400));
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.center.dx, laptop.width / 2);
    expect(rect.top, greaterThan(0));
    await closeBitcoinReceive(tester);
  });

  testWidgets('a phone keeps its bottom sheet', (tester) async {
    await openBitcoinReceive(tester, ReceiveWorld(),
        size: const Size(430, 932),
        open: _fromTopBar(showBitcoinQrReceiveSheet));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_card), findsNothing);
    await closeBitcoinReceive(tester);
  });

  testWidgets('the scanner in a side panel: one close, no drag handle',
      (tester) async {
    final cameras = FakeScannerCameras();
    await openBitcoinReceive(tester, ReceiveWorld(),
        size: laptop,
        overrides: [cameras.override],
        open: _fromTopBar(showRoutingScannerSheet));
    await tester.pump(const Duration(milliseconds: 400));
    _expectSide(tester, laptop);
    expect(find.byKey(const ValueKey('scanner-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('kute-dialog-close')), findsNothing);
    await closeBitcoinReceive(tester);
  });

  group('arming is causal', () {
    late BuildContext home;
    Widget homePage() => Builder(builder: (context) {
          home = context;
          return const Scaffold(body: SizedBox.expand());
        });

    /// A panel's slide in or out, whole.
    Future<void> opened(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> frames(WidgetTester tester, [int n = 3]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('an action that opens nothing does not capture the next '
        'unrelated panel', (tester) async {
      await _pumpRouter(tester, homePage());
      KuteSideFlow.run(() {});
      await frames(tester);
      unawaited(_panel(home, 'unrelated'));
      await opened(tester);
      expect(_atSide(tester, 'unrelated'), isFalse);
    });

    testWidgets('an action still awaiting does not capture a panel opened '
        'elsewhere meanwhile; what it opens itself is at the side',
        (tester) async {
      await _pumpRouter(tester, homePage());
      final policy = Completer<void>();
      // Purchase: the policy first, then its panel.
      KuteSideFlow.run(() async {
        await policy.future;
        await _panel(home, 'purchase');
      });
      await frames(tester);
      unawaited(_panel(home, 'unrelated'));
      await opened(tester);
      expect(_atSide(tester, 'unrelated'), isFalse);
      Navigator.of(home, rootNavigator: true).pop();
      await opened(tester);
      await frames(tester);

      policy.complete();
      await tester.pump();
      await opened(tester);
      expect(_atSide(tester, 'purchase'), isTrue);
    });

    testWidgets('a top bar action that pushes a route: the route built in '
        'the next frame is at the side', (tester) async {
      final router = await _pumpRouter(tester, homePage());
      KuteSideFlow.run(() => router.push('/next'));
      await tester.pump();
      await opened(tester);
      expect(_atSide(tester, 'next panel'), isTrue);
    });

    testWidgets('the scanner hands off to Send: closing its side panel and '
        'pushing the next lands at the side', (tester) async {
      final router = await _pumpRouter(tester, homePage());
      KuteSideFlow.run(() => _panel(home, 'scanner',
          builder: (context) => SizedBox(
                height: 300,
                child: TextButton(
                  // _pushToConfirmSend: close, then push through the router.
                  onPressed: () {
                    final r = GoRouter.of(context);
                    Navigator.of(context).pop();
                    unawaited(r.push('/next'));
                  },
                  child: const Text('scanner'),
                ),
              )));
      await tester.pump();
      await opened(tester);
      expect(_atSide(tester, 'scanner'), isTrue);
      // Long after the action: only the hand-off can put it at the side.
      await frames(tester, 10);
      await tester.tap(find.text('scanner'));
      await tester.pump();
      await opened(tester);
      expect(find.text('scanner'), findsNothing);
      expect(_atSide(tester, 'next panel'), isTrue);
      expect(router.state.uri.path, '/next');

      // Once that flow is over, an unrelated panel is centred again.
      Navigator.of(home, rootNavigator: true).pop();
      await opened(tester);
      await frames(tester);
      unawaited(_panel(home, 'unrelated'));
      await opened(tester);
      expect(_atSide(tester, 'unrelated'), isFalse);
    });

    testWidgets('a panel opened from inside a side panel is at the side; '
        'one closed long ago hands nothing off', (tester) async {
      await _pumpRouter(tester, homePage());
      KuteSideFlow.run(() => _panel(home, 'flow'));
      await tester.pump();
      await opened(tester);
      await frames(tester, 10);
      unawaited(_panel(home, 'step'));
      await opened(tester);
      expect(_atSide(tester, 'step'), isTrue);
      Navigator.of(home, rootNavigator: true).pop();
      await opened(tester);
      Navigator.of(home, rootNavigator: true).pop();
      await opened(tester);
      await frames(tester);
      unawaited(_panel(home, 'later'));
      await opened(tester);
      expect(_atSide(tester, 'later'), isFalse);
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: side panels $mode', skip: _dir == null,
        (tester) async {
      await loadReceiveFonts(tester);
      for (final (tag, size) in [
        ('1440x900', laptop),
        ('1180x820', const Size(1180, 820)),
        ('1920x1080', const Size(1920, 1080)),
        ('430x932', const Size(430, 932)),
      ]) {
        Future<void> shot(String name) async {
          await tester.pump(const Duration(milliseconds: 500));
          await _shoot(tester, '${name}_${tag}_$mode');
          expect(tester.takeException(), isNull, reason: '$name $tag');
        }

        KuteSideFlow.reset();
        await openBitcoinReceive(tester, ReceiveWorld(),
            dark: dark,
            size: size,
            open: _fromTopBar(showBitcoinReceiveSheet));
        await shot('receive_chooser');
        await closeBitcoinReceive(tester, reopen: true);

        KuteSideFlow.reset();
        await openBitcoinReceive(tester, ReceiveWorld(),
            dark: dark,
            size: size,
            open: _fromTopBar(showBitcoinQrReceiveSheet));
        await shot('receive_bitcoin');
        await tester.tap(find.byKey(const ValueKey('receive-request-amount')));
        await settleReceive(tester);
        await shot('receive_request_amount');
        await closeBitcoinReceive(tester, reopen: true);

        KuteSideFlow.reset();
        await openBitcoinReceive(tester, ReceiveWorld(),
            dark: dark,
            size: size,
            overrides: [FakeScannerCameras().override],
            open: _fromTopBar(showRoutingScannerSheet));
        await shot('scanner');
        await closeBitcoinReceive(tester, reopen: true);
      }
      RuntimeCapabilitiesService.instance.dispose();
    });
  }
}
