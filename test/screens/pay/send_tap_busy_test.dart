// The Send button on Review spins from the tap itself. A route used to
// raise its busy flag only after its first await — a 100% cross-chain
// send synced the Spark balance first (up to 20 s) — so the button sat
// idle until the face scan appeared. `runSendTapBusy` is what
// `_handleSend` wraps every route in; these cases drive it through the
// same `SendReviewAction` the Review step renders.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/pay/components/confirm_send.dart'
    show runSendTapBusy;
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// The Review step's busy wiring, minus the rest of the screen: the
/// button spins while `isProcessing` is up and is dead meanwhile.
class _Review extends StatefulWidget {
  const _Review({required this.route});

  /// One send route. Receives the screen's `isProcessing` setter so a
  /// route can clear it itself, as the real ones do.
  final Future<void> Function(void Function(bool) setProcessing) route;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool isProcessing = false;
  int dispatches = 0;

  Future<void> _handleSend() async {
    if (isProcessing) return;
    dispatches++;
    await runSendTapBusy(
      setBusy: (busy) => setState(() => isProcessing = busy),
      releaseBusy: () => mounted && isProcessing,
      dispatch: () => widget.route((v) => setState(() => isProcessing = v)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SendReviewAction(
          label: isProcessing ? 'Sending…' : 'Send',
          loading: isProcessing,
          onPressed: isProcessing ? null : _handleSend,
          footnote: 'Funds leave your wallet immediately',
        ),
      );
}

Future<_ReviewState> _pump(WidgetTester tester,
    Future<void> Function(void Function(bool)) route) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      home: _Review(route: route),
    ),
  ));
  return tester.state<_ReviewState>(find.byType(_Review));
}

Finder get _spinner => find.byWidgetPredicate(
    (w) => w.runtimeType.toString().contains('StaggeredDotsWave'));

void main() {
  test('busy goes up before the route runs and comes down after', () async {
    final log = <String>[];
    await runSendTapBusy(
      setBusy: (b) => log.add('busy=$b'),
      releaseBusy: () => true,
      dispatch: () async => log.add('route'),
    );
    expect(log, ['busy=true', 'route', 'busy=false']);
  });

  test('a throwing route still clears busy', () async {
    final log = <bool>[];
    await expectLater(
      runSendTapBusy(
        setBusy: log.add,
        releaseBusy: () => true,
        dispatch: () async => throw StateError('quote failed'),
      ),
      throwsStateError,
    );
    expect(log, [true, false]);
  });

  test('busy owned elsewhere (a newer build) is left alone', () async {
    final log = <bool>[];
    await runSendTapBusy(
      setBusy: log.add,
      releaseBusy: () => false,
      dispatch: () async {},
    );
    expect(log, [true]);
  });

  testWidgets('100% cross-chain: spins on the tap, before the balance sync',
      (tester) async {
    // The draining route's first await: `sparkDrainBalanceSats`, a
    // wallet sync that can take seconds.
    final sync = Completer<int>();
    var quoted = false;
    final state = await _pump(tester, (setProcessing) async {
      final sats = await sync.future;
      quoted = sats > 0;
      setProcessing(true); // `_handleOrchestraFromBtc` raises it again.
      setProcessing(false); // …and clears it in its finally.
    });
    expect(_spinner, findsNothing);

    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(state.isProcessing, isTrue);
    expect(_spinner, findsOneWidget);
    expect(quoted, isFalse, reason: 'the sync is still out');

    // A second tap while it spins dispatches nothing.
    await tester.tap(find.byType(SendReviewAction));
    await tester.pump();
    expect(state.dispatches, 1);

    sync.complete(21000);
    await tester.pumpAndSettle();
    expect(quoted, isTrue);
    expect(state.isProcessing, isFalse);
    expect(_spinner, findsNothing);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('an early return (no route, bad address) clears busy',
      (tester) async {
    final state = await _pump(tester, (_) async {
      // e.g. `_handleSwapSend`: route unavailable → snackbar → return,
      // never touching `isProcessing` itself.
    });
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(state.isProcessing, isFalse);
    expect(_spinner, findsNothing);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('a dismissed face scan clears busy', (tester) async {
    final prompt = Completer<bool>();
    final state = await _pump(tester, (_) async {
      if (!await prompt.future) return; // `_approveSend` → declined
    });
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(_spinner, findsOneWidget);
    prompt.complete(false);
    await tester.pumpAndSettle();
    expect(state.isProcessing, isFalse);
    expect(find.text('Send'), findsOneWidget);
  });

  test('LoadingAnimationWidget is the spinner the button shows', () {
    // Guards the finder above against a rename of the dots widget.
    expect(
        LoadingAnimationWidget.staggeredDotsWave(color: Colors.black, size: 24)
            .runtimeType
            .toString(),
        contains('StaggeredDotsWave'));
  });
}
