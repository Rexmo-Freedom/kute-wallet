// Route minimums: the live `/limits` read with its floor, cache and the
// quote's `amount_too_small` feedback.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart';

OrchestraRouteLimits _limits(int minCents) => OrchestraRouteLimits.fromLimitsJson(
      {
        'orderNotionalUsd': {'minCents': minCents, 'maxCents': 10760000},
      },
      sweepRouteOf(OneBalanceVenue.predictions),
    )!;

void main() {
  test('the sweep routes are the two swap-back pairs', () {
    final pm = sweepRouteOf(OneBalanceVenue.predictions);
    expect(pm.label, 'polygon_usdc.e>spark_usdb');
    final hl = sweepRouteOf(OneBalanceVenue.investing);
    expect(hl.label, 'hypercore_usdc>spark_usdb');
  });

  test('the live minimum wins over the floor, the floor over a lower read',
      () async {
    final asked = <RouteKey>[];
    final minimums = RouteMinimums(fetch: (route) async {
      asked.add(route);
      return route.fromChain == 'polygon' ? _limits(80) : _limits(250);
    });
    expect(await minimums.minimumUsd(OneBalanceVenue.predictions), 1);
    expect(await minimums.minimumUsd(OneBalanceVenue.investing), 2.5);
    expect(asked.map((r) => r.fromChain), ['polygon', 'hypercore']);
  });

  test('a read is cached ten minutes, then refreshed', () async {
    var clock = DateTime(2026, 10, 12, 12);
    var reads = 0;
    final minimums = RouteMinimums(
      fetch: (_) async {
        reads++;
        return _limits(300);
      },
      clock: () => clock,
    );
    expect(await minimums.minimumUsd(OneBalanceVenue.predictions), 3);
    expect(minimums.cachedMinimumUsd(OneBalanceVenue.predictions), 3);
    clock = clock.add(const Duration(minutes: 9));
    await minimums.minimumUsd(OneBalanceVenue.predictions);
    expect(reads, 1);
    clock = clock.add(const Duration(minutes: 2));
    await minimums.minimumUsd(OneBalanceVenue.predictions);
    expect(reads, 2);
  });

  test('a failed read falls back to the floor and retries after a minute',
      () async {
    var clock = DateTime(2026, 10, 12, 12);
    var reads = 0;
    final minimums = RouteMinimums(
      fetch: (_) async {
        reads++;
        throw StateError('offline');
      },
      clock: () => clock,
    );
    expect(await minimums.minimumUsd(OneBalanceVenue.investing), 1);
    await minimums.minimumUsd(OneBalanceVenue.investing);
    expect(reads, 1);
    clock = clock.add(const Duration(minutes: 1));
    await minimums.minimumUsd(OneBalanceVenue.investing);
    expect(reads, 2);
    expect(minimums.cachedMinimumUsd(OneBalanceVenue.predictions), isNull);
  });

  test('concurrent asks share one read', () async {
    var reads = 0;
    final minimums = RouteMinimums(fetch: (_) async {
      reads++;
      await Future<void>.delayed(Duration.zero);
      return _limits(120);
    });
    final results = await Future.wait([
      minimums.minimumUsd(OneBalanceVenue.predictions),
      minimums.minimumUsd(OneBalanceVenue.predictions),
    ]);
    expect(results, [1.2, 1.2]);
    expect(reads, 1);
  });

  test('a refused amount raises the minimum just above it for the cache life',
      () async {
    var clock = DateTime(2026, 10, 12, 12);
    final minimums = RouteMinimums(
        fetch: (_) async => _limits(80), clock: () => clock);
    expect(await minimums.minimumUsd(OneBalanceVenue.predictions), 1);
    minimums.noteAmountTooSmall(OneBalanceVenue.predictions, 2.4);
    expect(await minimums.minimumUsd(OneBalanceVenue.predictions),
        closeTo(2.41, 1e-9));
    // A smaller refusal does not lower it.
    minimums.noteAmountTooSmall(OneBalanceVenue.predictions, 1.5);
    expect(await minimums.minimumUsd(OneBalanceVenue.predictions),
        closeTo(2.41, 1e-9));
    clock = clock.add(const Duration(minutes: 10));
    expect(await minimums.minimumUsd(OneBalanceVenue.predictions), 1);
  });
}
