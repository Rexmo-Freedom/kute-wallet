// afterRouteTransition / requestFocusAfterTransition: the action (the
// focus) waits for the route's slide to finish, runs on a route that is
// already settled, and never runs once cancelled.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/after_route_transition.dart';

class _Field extends StatefulWidget {
  final void Function(int)? onRun;
  const _Field({this.onRun});
  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final node = FocusNode();
  VoidCallback? cancel;
  var runs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cancel = afterRouteTransition(context, () {
        runs++;
        widget.onRun?.call(runs);
        node.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    cancel?.call();
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(focusNode: node, key: const ValueKey('field'));
}

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const _Field(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
  }

  bool focused(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const ValueKey('field'))).focusNode!
          .hasFocus;

  testWidgets('a sheet sliding in: nothing until the slide ends, then focus',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Open'));
    await tester.pump();
    // The sheet's 250 ms slide: on screen, no focus yet.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('field')), findsOneWidget);
    expect(focused(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(focused(tester), isFalse);
    // Settled: focused, once.
    await tester.pumpAndSettle();
    expect(focused(tester), isTrue);
    expect(tester.state<_FieldState>(find.byType(_Field)).runs, 1);
  });

  testWidgets('a settled route: the action runs at once', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Field())));
    await tester.pump();
    expect(tester.state<_FieldState>(find.byType(_Field)).runs, 1);
    expect(focused(tester), isTrue);
  });

  testWidgets('cancelled before the slide ends: the action never runs',
      (tester) async {
    var runs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => _Field(onRun: (n) => runs = n),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Gone mid-slide (its cancel runs from dispose).
    Navigator.of(tester.element(find.byType(_Field))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(_Field), findsNothing);
    expect(runs, 0);
    expect(tester.takeException(), isNull);
  });
}
