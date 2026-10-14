// The rubber band the Send button wears from the tap until the money is
// out (founder request, 14 October 2026). These cases drive the Review
// step's own wiring: `runSendTapBusy` around a route that raises and
// clears the same flags the bitcoin send keeps (`isProcessing`,
// `_paymentAuthInFlight`, `_sendCompleted`), with `SendRubberBand`
// around `SendReviewAction` exactly as `confirm_send.dart` renders it,
// and the success screen held until the snap has played
// (`_letSendBandSnap`).
//
// The button spins and a waiting band breathes, so nothing here settles:
// time is pumped in fixed steps instead of `pumpAndSettle`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/pay/components/confirm_send.dart'
    show runSendTapBusy;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/theme/app_theme.dart';

/// One send route, as the bitcoin send's routes run: the SDK prepare,
/// the face scan (`_approveSend` raises and clears the auth flag around
/// it), the broadcast, and `_sendCompleted` set before busy comes down.
class _Route {
  final prepared = Completer<void>();
  final approved = Completer<bool>();
  final broadcast = Completer<void>();
  Object? failureShown;

  /// `showFullscreenTransactionSendModal` was reached.
  bool successShown = false;

  Future<void> call(_ReviewState s) async {
    await prepared.future;
    s.update(() => s.paymentAuthInFlight = true);
    final bool ok;
    try {
      ok = await approved.future;
    } finally {
      s.update(() => s.paymentAuthInFlight = false);
    }
    if (!ok) return; // a declined scan
    try {
      await broadcast.future;
      // Set, then the band is let snap before the success screen
      // (`_letSendBandSnap`), as the real routes do.
      s.sendCompleted = true;
      await s.letBandSnap();
      successShown = true;
    } catch (e) {
      failureShown = e; // `_showSendFailed`
    }
  }
}

class _Review extends StatefulWidget {
  const _Review({required this.route});

  final _Route route;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool isProcessing = false;
  bool paymentAuthInFlight = false;
  bool sendCompleted = false;

  void update(VoidCallback f) {
    if (mounted) setState(f);
  }

  /// `_letSendBandSnap`.
  Future<void> letBandSnap() async {
    if (!mounted) return;
    setState(() {});
    await RubberBand.settle(context);
  }

  Future<void> _handleSend() async {
    if (isProcessing || paymentAuthInFlight || sendCompleted) return;
    await runSendTapBusy(
      setBusy: (busy) => setState(() => isProcessing = busy),
      releaseBusy: () => mounted && isProcessing,
      dispatch: () => widget.route(this),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SendRubberBand(
            busy: isProcessing,
            authorising: paymentAuthInFlight,
            succeeded: sendCompleted,
            child: SendReviewAction(
              label: isProcessing ? 'Sending…' : 'Send',
              loading: isProcessing,
              onPressed: isProcessing ? null : _handleSend,
              footnote: 'Funds leave your wallet immediately',
            ),
          ),
        ),
      );
}

Future<void> _pump(WidgetTester tester, _Route route,
    {bool reduceMotion = false}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: _Review(route: route),
    ),
  ));
}

RubberBandProgressState _band(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(find.byType(RubberBandProgress));

SendRubberBandState _send(WidgetTester tester) =>
    tester.state<SendRubberBandState>(find.byType(SendRubberBand));

/// Lets time pass in frames (the spinner and the breathing never settle).
Future<void> _wait(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += frame) {
    await tester.pump(frame);
  }
}

/// Records the light taps the band gives.
List<MethodCall> _hapticLog(WidgetTester tester) {
  ContinuousHaptics.debugReset();
  ContinuousHaptics.debugLog = [];
  addTearDown(() => ContinuousHaptics.debugLog = null);
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

/// The whoosh and the snap, through the haptics bridge's test seam (the
/// pull before a release never snaps).
int _snapImpacts(List<MethodCall> calls) =>
    ContinuousHaptics.debugLog!.where((c) => c.method == 'snap').length;

/// Taps Send and walks the route to the broadcast wait, checking the
/// pull grows with each phase on the way.
Future<void> _toBroadcast(WidgetTester tester, _Route route) async {
  expect(_band(tester).ticking, isFalse, reason: 'at rest before the tap');
  expect(_band(tester).stretch, 0);

  await tester.tap(find.text('Send'));
  await tester.pump();
  // The tap's first pull is felt at once: at least 4% of the block
  // within 300 ms.
  for (var i = 0; i < 18; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(_band(tester).stretch, greaterThanOrEqualTo(0.04));
  // Readying the send: eased up, not yet at the approval hold.
  await _wait(tester, const Duration(seconds: 1));
  final preparing = _send(tester).progress;
  expect(preparing, greaterThan(0));
  expect(preparing, lessThan(SendRubberBand.approvalProgress));
  expect(_send(tester).easing, isTrue);
  expect(_band(tester).stretch, greaterThan(0), reason: 'pulled up');

  // The face scan: held, at least the approval level, nothing easing.
  route.prepared.complete();
  await _wait(tester, const Duration(milliseconds: 500));
  final approving = _send(tester).progress;
  expect(approving, greaterThanOrEqualTo(SendRubberBand.approvalProgress));
  expect(_send(tester).easing, isFalse);

  // Approved: the broadcast pulls harder the longer it runs.
  route.approved.complete(true);
  await _wait(tester, const Duration(seconds: 1));
  final early = _send(tester).progress;
  expect(early, greaterThanOrEqualTo(SendRubberBand.afterApprovalProgress));
  await _wait(tester, const Duration(seconds: 4));
  final late = _send(tester).progress;
  expect(late, greaterThan(early));
  expect(late, closeTo(SendRubberBand.ceiling, 0.011));
  expect(_band(tester).stretch,
      closeTo(rubberBandStretchFor(late), RubberBandProgress.breath + 1e-3));
  expect(_band(tester).stretch,
      lessThanOrEqualTo(RubberBandProgress.defaultMaxStretch));
}

void main() {
  testWidgets(
      'sent: the band snaps back past rest with one light tap, and the '
      'success screen waits for it', (tester) async {
    final calls = _hapticLog(tester);
    final route = _Route();
    await _pump(tester, route);
    await _toBroadcast(tester, route);

    calls.clear();
    route.broadcast.complete();
    await tester.pump();
    expect(_send(tester).outcome, RubberBandOutcome.success);
    var min = double.infinity;
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      if (s < min) min = s;
      expect(route.successShown, isFalse,
          reason: 'not before the snap has played');
    }
    // Still the send's button, spinning, while it snaps.
    expect(tester.state<_ReviewState>(find.byType(_Review)).isProcessing,
        isTrue);
    expect(min, lessThan(0), reason: 'the snap overshoots past rest');
    // Bounded: the success screen follows once the snap's moment is over.
    await tester.pump(RubberBand.snapSettle);
    await tester.pump();
    expect(route.successShown, isTrue);
    await _wait(tester, const Duration(seconds: 2));
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(_send(tester).easing, isFalse);
    expect(_snapImpacts(calls), 1);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('failed: the band lets go softly, never past rest',
      (tester) async {
    final calls = _hapticLog(tester);
    final route = _Route();
    await _pump(tester, route);
    await _toBroadcast(tester, route);

    calls.clear();
    final pulled = _band(tester).stretch;
    route.broadcast.completeError(StateError('broadcast refused'));
    await tester.pump();
    expect(route.failureShown, isA<StateError>());
    expect(_send(tester).outcome, RubberBandOutcome.failure);
    var previous = _band(tester).stretch;
    expect(previous, lessThanOrEqualTo(pulled + 1e-9));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      expect(s, greaterThanOrEqualTo(-1e-9), reason: 'never past rest');
      expect(s, lessThanOrEqualTo(previous + 1e-9), reason: 'only toward rest');
      previous = s;
    }
    await _wait(tester, const Duration(seconds: 1));
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(_snapImpacts(calls), 0, reason: 'no success tap on a failure');
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('a declined face scan lets go softly too', (tester) async {
    final route = _Route();
    await _pump(tester, route);
    await tester.tap(find.text('Send'));
    await tester.pump();
    route.prepared.complete();
    await _wait(tester, const Duration(seconds: 1));
    expect(_band(tester).stretch, greaterThan(0));

    route.approved.complete(false);
    await tester.pump();
    expect(_send(tester).outcome, RubberBandOutcome.failure);
    var previous = _band(tester).stretch;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      expect(s, greaterThanOrEqualTo(-1e-9));
      expect(s, lessThanOrEqualTo(previous + 1e-9));
      previous = s;
    }
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
  });

  testWidgets('a second send after a failure pulls again from rest',
      (tester) async {
    final first = _Route();
    await _pump(tester, first);
    await tester.tap(find.text('Send'));
    await tester.pump();
    first.prepared.complete();
    await tester.pump();
    first.approved.complete(false);
    await _wait(tester, const Duration(seconds: 1));
    expect(_band(tester).stretch, 0);

    // The same Review, a new attempt: the route object is swapped by
    // re-pumping the screen with it.
    final second = _Route();
    await _pump(tester, second);
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(_send(tester).outcome, RubberBandOutcome.none);
    await _wait(tester, const Duration(seconds: 1));
    expect(_band(tester).stretch, greaterThan(0));
  });

  testWidgets('Reduce Motion: nothing moves or ticks through a whole send',
      (tester) async {
    final route = _Route();
    await _pump(tester, route, reduceMotion: true);
    final band = find.descendant(
        of: find.byType(SendRubberBand),
        matching: find.byType(FractionalTranslation));

    Future<void> still() async {
      await _wait(tester, const Duration(milliseconds: 500));
      expect(_band(tester).stretch, 0);
      expect(_band(tester).ticking, isFalse);
      expect(_send(tester).easing, isFalse);
      expect(band, findsNothing);
    }

    await tester.tap(find.text('Send'));
    await tester.pump();
    await still();
    route.prepared.complete();
    await still();
    route.approved.complete(true);
    await still();
    route.broadcast.complete();
    await tester.pump();
    expect(_send(tester).outcome, RubberBandOutcome.success);
    // Nothing waits for a snap that is not drawn.
    await tester.pump();
    expect(route.successShown, isTrue);
    await still();
  });

  testWidgets('dollars: a stop releases softly', (tester) async {
    // The dollar send passes `busy: _processing`, `authorising:
    // _approving` and `succeeded: _sent`.
    var busy = true;
    var approving = false;
    late StateSetter set;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: StatefulBuilder(builder: (context, setState) {
          set = setState;
          return Scaffold(
            body: SendRubberBand(
              busy: busy,
              authorising: approving,
              expected: const Duration(seconds: 6),
              child: const SizedBox(height: 80, child: Text('Send')),
            ),
          );
        }),
      ),
    ));
    await _wait(tester, const Duration(seconds: 2));
    expect(_band(tester).stretch, greaterThan(0));
    set(() => approving = true);
    await _wait(tester, const Duration(milliseconds: 500));
    set(() => approving = false);
    await _wait(tester, const Duration(seconds: 2));
    expect(
        _send(tester).progress,
        greaterThanOrEqualTo(SendRubberBand.afterApprovalProgress));

    set(() => busy = false);
    await tester.pump();
    expect(_send(tester).outcome, RubberBandOutcome.failure);
    var previous = _band(tester).stretch;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      expect(s, greaterThanOrEqualTo(-1e-9));
      expect(s, lessThanOrEqualTo(previous + 1e-9));
      previous = s;
    }
    expect(_band(tester).ticking, isFalse);
  });

  testWidgets('dollars: sent snaps while the button still spins',
      (tester) async {
    final calls = _hapticLog(tester);
    var sent = false;
    late StateSetter set;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: StatefulBuilder(builder: (context, setState) {
          set = setState;
          return Scaffold(
            body: SendRubberBand(
              busy: true,
              succeeded: sent,
              expected: const Duration(seconds: 6),
              child: const SizedBox(height: 80, child: Text('Send')),
            ),
          );
        }),
      ),
    ));
    await _wait(tester, const Duration(seconds: 2));
    expect(_band(tester).stretch, greaterThan(0.06));
    calls.clear();
    set(() => sent = true);
    await tester.pump();
    expect(_send(tester).outcome, RubberBandOutcome.success);
    var min = double.infinity;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      if (s < min) min = s;
    }
    expect(min, lessThan(0), reason: 'the snap overshoots past rest');
    expect(_snapImpacts(calls), 1);
    await _wait(tester, const Duration(seconds: 1));
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
  });
}
