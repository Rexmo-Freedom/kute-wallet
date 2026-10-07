// The Over token beside a match (polyGameOverTokenProvider): the event and
// its "more markets" sibling are read at once, and the event is not read
// again while the game's lines read of it is fresh.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';

Map<String, dynamic> _totals(String token) => {
      'markets': [
        {
          'sportsMarketType': 'totals',
          'closed': false,
          'spread': 0.01,
          'outcomes': '["Over", "Under"]',
          'outcomePrices': '["0.49", "0.51"]',
          'clobTokenIds': '["$token", "$token-under"]',
        },
      ],
    };

void main() {
  late GameEventRead original;
  late List<String> calls;
  late Map<String, Completer<Map<String, dynamic>?>> pending;

  setUp(() {
    original = gameOverEventRead;
    calls = [];
    pending = {};
    gameOverEventRead = (slug) {
      calls.add(slug);
      return (pending[slug] = Completer()).future;
    };
  });
  tearDown(() => gameOverEventRead = original);

  ProviderContainer withLines(PolyGameLines lines) {
    final c = ProviderContainer(overrides: [
      polyGameLinesProvider.overrideWith((ref, slug) async => lines),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  int now() => DateTime.now().millisecondsSinceEpoch;

  test('the parser finds the fixture line', () {
    expect(pickOverToken(_totals('o')), 'o');
  });

  test('a fresh lines read with a line reads nothing else', () async {
    final c = withLines(PolyGameLines(overToken: 'own', readAtMs: now()));
    expect(await c.read(polyGameOverTokenProvider('epl-ars-che').future),
        'own');
    expect(calls, isEmpty);
  });

  test('a fresh lines read with no line reads only the sibling', () async {
    final c = withLines(PolyGameLines(readAtMs: now()));
    final sub = c.listen(polyGameOverTokenProvider('epl-ars-che'), (_, __) {});
    await pumpEventQueue();
    expect(calls, ['epl-ars-che-more-markets'],
        reason: 'the event itself was just read by the lines read');
    pending['epl-ars-che-more-markets']!.complete(_totals('sibling'));
    expect(await c.read(polyGameOverTokenProvider('epl-ars-che').future),
        'sibling');
    sub.close();
  });

  test('a stale lines read reads the event and its sibling at once',
      () async {
    final c = withLines(PolyGameLines(
        overToken: 'old', readAtMs: now() - 5 * 60 * 1000));
    final sub = c.listen(polyGameOverTokenProvider('epl-ars-che'), (_, __) {});
    await pumpEventQueue();
    // Both reads are under way before either has answered.
    expect(calls, unorderedEquals(['epl-ars-che', 'epl-ars-che-more-markets']));
    pending['epl-ars-che-more-markets']!.complete(_totals('sibling'));
    pending['epl-ars-che']!.complete(_totals('own'));
    expect(await c.read(polyGameOverTokenProvider('epl-ars-che').future),
        'own', reason: 'the event\'s own line comes first');
    sub.close();
  });

  test('a failed read falls back to the other', () async {
    final c = withLines(PolyGameLines.empty);
    final sub = c.listen(polyGameOverTokenProvider('epl-ars-che'), (_, __) {});
    await pumpEventQueue();
    pending['epl-ars-che']!.completeError(Exception('down'));
    pending['epl-ars-che-more-markets']!.complete(_totals('sibling'));
    expect(await c.read(polyGameOverTokenProvider('epl-ars-che').future),
        'sibling');
    sub.close();
  });
}
