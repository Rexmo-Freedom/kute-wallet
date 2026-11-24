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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/kute_wide_frames.dart';
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

/// [open] as a top bar action opens it: armed first.
Future<void> Function(BuildContext) _fromTopBar(
        Future<void> Function(BuildContext) open) =>
    (context) {
      KuteSideFlow.arm();
      return open(context);
    };

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
