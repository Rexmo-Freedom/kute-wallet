// A range whose own grain leaves too few points to draw (a market opened
// today, read at ALL's 12-hour points) is read again at a finer grain.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';

List<PolymarketPricePoint> _points(int n) => [
      for (var i = 0; i < n; i++)
        PolymarketPricePoint(
            timestamp: DateTime(2026, 10, 4).add(Duration(minutes: i)),
            price: 0.5),
    ];

void main() {
  test('an old market takes one read at the range grain', () async {
    final asked = <int>[];
    final points = await readPolyHistoryAdaptive('max', (fidelity) async {
      asked.add(fidelity);
      return _points(700);
    });
    expect(asked, [720]);
    expect(points, hasLength(700));
  });

  test('a market opened today on ALL: one point, then hourly, then 10 min',
      () async {
    final asked = <int>[];
    final points = await readPolyHistoryAdaptive('max', (fidelity) async {
      asked.add(fidelity);
      return _points(switch (fidelity) { 720 => 1, 60 => 6, _ => 33 });
    });
    expect(asked, [720, 60, 10]);
    expect(points, hasLength(33));
  });

  test('a week-old market stops at the first grain with enough points',
      () async {
    final asked = <int>[];
    final points = await readPolyHistoryAdaptive('max', (fidelity) async {
      asked.add(fidelity);
      return _points(fidelity == 720 ? 14 : 168);
    });
    expect(asked, [720, 60]);
    expect(points, hasLength(168));
  });

  test('a failed first read is a failure; a failed finer read keeps the rest',
      () async {
    expect(await readPolyHistoryAdaptive('max', (_) async => null), isNull);
    final points = await readPolyHistoryAdaptive(
        '1w', (fidelity) async => fidelity == 60 ? _points(3) : null);
    expect(points, hasLength(3));
  });

  test('a finer read with no more points changes nothing', () async {
    final points = await readPolyHistoryAdaptive(
        '1d', (fidelity) async => _points(fidelity == 10 ? 5 : 0));
    expect(points, hasLength(5));
  });

  test('the one-hour range has no finer grain', () async {
    final asked = <int>[];
    await readPolyHistoryAdaptive('1h', (fidelity) async {
      asked.add(fidelity);
      return _points(2);
    });
    expect(asked, [1]);
  });

  group('a market whose age is known', () {
    test('opened two hours ago on ALL: straight to ten-minute points',
        () async {
      final asked = <int>[];
      final points = await readPolyHistoryAdaptive('max', (fidelity) async {
        asked.add(fidelity);
        return _points(switch (fidelity) { 720 => 1, 60 => 2, _ => 12 });
      }, age: const Duration(hours: 2));
      expect(asked, [10]);
      expect(points, hasLength(12));
    });

    test('a week old on ALL: straight to hourly points, the ladder\'s own '
        'answer', () async {
      Future<List<PolymarketPricePoint>?> read(int f) async =>
          _points(f == 720 ? 14 : 168);
      final asked = <int>[];
      final hinted = await readPolyHistoryAdaptive('max', (f) {
        asked.add(f);
        return read(f);
      }, age: const Duration(days: 7));
      expect(asked, [60]);
      expect(hinted, hasLength(
          (await readPolyHistoryAdaptive('max', read))!.length));
    });

    test('an old market reads at the range grain as before', () async {
      final asked = <int>[];
      await readPolyHistoryAdaptive('max', (fidelity) async {
        asked.add(fidelity);
        return _points(700);
      }, age: const Duration(days: 400));
      expect(asked, [720]);
      expect(polyHistoryFirstUsefulFidelity('1d', const Duration(days: 30)),
          isNull);
    });

    test('a first read that comes back short runs the ladder as before',
        () async {
      final asked = <int>[];
      final points = await readPolyHistoryAdaptive('max', (fidelity) async {
        asked.add(fidelity);
        return _points(fidelity == 60 ? 3 : 1);
      }, age: const Duration(days: 7));
      expect(asked, [60, 720, 60, 10]);
      expect(points, hasLength(3));
    });
  });
}
