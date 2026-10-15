// The step graph runner on its own (founder, 15 October 2026: "make all
// steps clear in the sub steps ... make it in parallel most of the things
// that can be parallel"): every step whose dependencies allow it starts at
// once, readiness opens on the FIRST money landing, the order waits on
// readiness, a failed step names itself and blocks only what depends on
// it, a retry restarts only that branch, a fallback replaces one step.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/one_balance/money_steps.dart';

MoneyStep _leg(String id, {List<String> after = const []}) => MoneyStep(
    id: id,
    kind: MoneyStepKind.leg,
    from: MoneyPlace.bitcoin,
    usd: 5,
    after: after);

void main() {
  test(
      'legs start together; readiness opens on the first landing; the order '
      'waits on readiness, not on the slowest leg', () async {
    final gates = {
      'leg:a': Completer<MoneyStepOutcome>(),
      'leg:b': Completer<MoneyStepOutcome>(),
      'ready': Completer<MoneyStepOutcome>(),
      'place': Completer<MoneyStepOutcome>(),
    };
    final started = <String>[];
    final graph = MoneyStepGraph([
      _leg('leg:a'),
      _leg('leg:b'),
      const MoneyStep(
          id: 'ready',
          kind: MoneyStepKind.confirm,
          after: ['leg:a', 'leg:b'],
          afterAny: true),
      const MoneyStep(id: 'place', kind: MoneyStepKind.place, after: ['ready']),
    ]);
    final changes = <MoneyStepGraph>[];
    final runner = MoneyStepRunner(
      graph: graph,
      actionFor: (s) => (step, _) {
        started.add(step.id);
        return gates[step.id]!.future;
      },
      onChange: changes.add,
    );
    final done = runner.run();
    await pumpEventQueue();
    // Both legs at the same moment, nothing else.
    expect(started, ['leg:a', 'leg:b']);
    expect(runner.graph.byId('ready')!.status, MoneyStepStatus.waiting);

    // The fast leg lands: readiness starts while the slow one still runs.
    gates['leg:b']!.complete(const MoneyStepDone());
    await pumpEventQueue();
    expect(started, ['leg:a', 'leg:b', 'ready']);
    expect(runner.graph.byId('leg:a')!.status, MoneyStepStatus.running);
    expect(runner.graph.byId('leg:b')!.status, MoneyStepStatus.done);

    gates['ready']!.complete(const MoneyStepDone());
    await pumpEventQueue();
    expect(started.last, 'place');
    gates['place']!.complete(const MoneyStepDone());
    await pumpEventQueue();
    // The order went while leg a is still landing.
    expect(runner.graph.byId('place')!.status, MoneyStepStatus.done);
    expect(runner.graph.byId('leg:a')!.status, MoneyStepStatus.running);

    gates['leg:a']!.complete(const MoneyStepDone(usd: 4.5));
    final end = await done;
    expect(end.allDone, isTrue);
    expect(end.byId('leg:a')!.usd, 4.5);
    expect(changes, isNotEmpty);
    expect(end.byId('leg:a')!.ms, isNotNull);
  });

  test(
      'a failed step names itself and blocks only its dependents; retry '
      'restarts that branch alone', () async {
    var tries = 0;
    final ran = <String>[];
    final graph = MoneyStepGraph([
      _leg('leg:a'),
      _leg('leg:b'),
      const MoneyStep(id: 'onward', kind: MoneyStepKind.leg, after: ['leg:a']),
      const MoneyStep(
          id: 'place', kind: MoneyStepKind.place, after: ['onward', 'leg:b']),
    ]);
    final runner = MoneyStepRunner(
      graph: graph,
      actionFor: (s) => (step, _) async {
        ran.add(step.id);
        if (step.id == 'leg:a' && tries++ == 0) {
          return const MoneyStepFailed('refunded');
        }
        return const MoneyStepDone();
      },
    );
    var g = await runner.run();
    expect(g.byId('leg:a')!.status, MoneyStepStatus.failed);
    expect(g.byId('leg:a')!.reason, 'refunded');
    expect(g.firstFailed!.id, 'leg:a');
    expect(g.byId('leg:b')!.status, MoneyStepStatus.done);
    expect(g.byId('onward')!.status, MoneyStepStatus.waiting);
    expect(g.byId('place')!.status, MoneyStepStatus.waiting);
    expect(g.branchOf('leg:a'), {'leg:a', 'onward', 'place'});

    ran.clear();
    g = await runner.retry('leg:a');
    // leg:b is not run again.
    expect(ran, ['leg:a', 'onward', 'place']);
    expect(g.allDone, isTrue);
  });

  test(
      'a fallback keeps the step (fell back), runs its replacements and '
      're-points what waited on it', () async {
    final ran = <String>[];
    final graph = MoneyStepGraph([
      _leg('leg:bitcoin'),
      const MoneyStep(
          id: 'ready',
          kind: MoneyStepKind.credit,
          after: ['leg:bitcoin'],
          afterAny: true),
    ]);
    final runner = MoneyStepRunner(
      graph: graph,
      actionFor: (s) => (step, _) async {
        ran.add(step.id);
        if (step.id == 'leg:bitcoin') {
          return const MoneyStepFellBack('route_unavailable', [
            MoneyStep(
                id: 'leg:bitcoin>dollars',
                kind: MoneyStepKind.leg,
                from: MoneyPlace.bitcoin,
                to: MoneyPlace.dollars),
            MoneyStep(
                id: 'leg:dollars:onward',
                kind: MoneyStepKind.leg,
                from: MoneyPlace.dollars,
                after: ['leg:bitcoin>dollars']),
          ]);
        }
        return const MoneyStepDone();
      },
    );
    final g = await runner.run();
    expect(ran,
        ['leg:bitcoin', 'leg:bitcoin>dollars', 'leg:dollars:onward', 'ready']);
    expect(g.byId('leg:bitcoin')!.status, MoneyStepStatus.fellBack);
    expect(g.byId('leg:bitcoin')!.reason, 'route_unavailable');
    expect(g.byId('ready')!.after, ['leg:dollars:onward']);
    expect([
      for (final s in g.steps) s.id
    ], [
      'leg:bitcoin',
      'leg:bitcoin>dollars',
      'leg:dollars:onward',
      'ready',
    ]);
  });

  test(
      'a step with no work completes at once; a skipped one satisfies its '
      'dependents; a throw is a failure', () async {
    final graph = MoneyStepGraph([
      const MoneyStep(id: 'noop', kind: MoneyStepKind.arrive),
      const MoneyStep(id: 'skip', kind: MoneyStepKind.convert, after: ['noop']),
      const MoneyStep(id: 'boom', kind: MoneyStepKind.buy, after: ['skip']),
    ]);
    final runner = MoneyStepRunner(
      graph: graph,
      actionFor: (s) => switch (s.id) {
        'noop' => null,
        'skip' => (_, __) async => const MoneyStepSkipped(),
        _ => (_, __) async => throw StateError('x'),
      },
    );
    final g = await runner.run();
    expect(g.byId('noop')!.status, MoneyStepStatus.done);
    expect(g.byId('skip')!.status, MoneyStepStatus.skipped);
    expect(g.byId('boom')!.status, MoneyStepStatus.failed);
  });

  test('a running step records what it learned; the graph persists as JSON',
      () async {
    final graph = MoneyStepGraph([_leg('leg:a')]);
    final runner = MoneyStepRunner(
      graph: graph,
      actionFor: (s) => (step, update) async {
        update((s) => s.copyWith(ref: 'ord_1'));
        return const MoneyStepDone();
      },
    );
    final g = await runner.run();
    expect(g.byId('leg:a')!.ref, 'ord_1');
    final back = MoneyStepGraph.fromJson(g.toJson());
    expect(back.byId('leg:a')!.status, MoneyStepStatus.done);
    expect(back.byId('leg:a')!.ref, 'ord_1');
    expect(back.byId('leg:a')!.from, MoneyPlace.bitcoin);
    expect(MoneyStepGraph.fromJson('nonsense').isEmpty, isTrue);
  });

  test(
      'stage status: running while any runs, done once all shown are, '
      'failed when one failed, skipped never counted', () {
    MoneyStep s(MoneyStepStatus st) =>
        MoneyStep(id: '$st', kind: MoneyStepKind.convert, status: st);
    expect(stageStatusOf([s(MoneyStepStatus.done), s(MoneyStepStatus.running)]),
        MoneyStepStatus.running);
    expect(stageStatusOf([s(MoneyStepStatus.done), s(MoneyStepStatus.skipped)]),
        MoneyStepStatus.done);
    expect(stageStatusOf([s(MoneyStepStatus.failed), s(MoneyStepStatus.done)]),
        MoneyStepStatus.failed);
    expect(
        stageStatusOf([s(MoneyStepStatus.waiting)]), MoneyStepStatus.waiting);
    expect(stageStatusOf([s(MoneyStepStatus.skipped)]), isNull);
  });
}
