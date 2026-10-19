// Receive minimums per route: Flashnet's live route minimum exactly (no
// app floor), the session's last live read when a re-read fails, no
// minimum at all when nothing was ever read, and never $0.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';

final _usdc = RouteKey(
    fromChain: 'base', fromAsset: 'USDC', toChain: 'spark', toAsset: 'USDB');
final _tron = RouteKey(
    fromChain: 'tron', fromAsset: 'USDT', toChain: 'spark', toAsset: 'BTC');

void main() {
  test('the live minimum is shown as read, under a dollar too', () async {
    final answers = <RouteKey, OrchestraRouteLimits>{
      _usdc: const OrchestraRouteLimits(orderMinUsdCents: 80),
      _tron: const OrchestraRouteLimits(orderMinUsdCents: 150),
    };
    final minimums = ReceiveMinimums(fetch: (r) async => answers[r]);
    expect(await minimums.refresh(_usdc),
        const ReceiveMinimum(source: ReceiveMinimumSource.live, usdCents: 80));
    expect((await minimums.refresh(_usdc)).usdText, '\$0.80');
    expect(await minimums.refresh(_tron),
        const ReceiveMinimum(source: ReceiveMinimumSource.live, usdCents: 150));
  });

  test('the larger of the notional and exact-in minimums counts', () async {
    final minimums = ReceiveMinimums(
        fetch: (_) async => const OrchestraRouteLimits(
            orderMinUsdCents: 90, exactInMinUsdCents: 205));
    expect((await minimums.refresh(_usdc)).usdText, '\$2.05');
  });

  test('no read and no usable limits both show no minimum, never \$0',
      () async {
    final failing = ReceiveMinimums(fetch: (_) async => throw StateError('x'));
    expect(await failing.refresh(_usdc), kReceiveMinimumNone);
    expect(kReceiveMinimumNone.usdText, isNull);
    expect(kReceiveMinimumNone.trackingParams, {'min_source': 'none'});
    final empty = ReceiveMinimums(
        fetch: (_) async => const OrchestraRouteLimits(orderMinUsdCents: 0));
    expect(await empty.refresh(_usdc), kReceiveMinimumNone);
    final none = ReceiveMinimums(fetch: (_) async => null);
    expect(await none.refresh(_usdc), kReceiveMinimumNone);
  });

  test('a failed re-read keeps the session\'s last live minimum per route',
      () async {
    var fail = false;
    final minimums = ReceiveMinimums(fetch: (_) async {
      if (fail) throw StateError('x');
      return const OrchestraRouteLimits(orderMinUsdCents: 130);
    });
    expect(minimums.cachedLive(_usdc), isNull);
    await minimums.refresh(_usdc);
    fail = true;
    final again = await minimums.refresh(_usdc);
    expect(again.usdCents, 130);
    expect(again.source, ReceiveMinimumSource.live);
    expect(minimums.cachedLive(_usdc)?.usdCents, 130);
    // Another route has its own memory.
    expect(minimums.cachedLive(_tron), isNull);
    expect(await minimums.refresh(_tron), kReceiveMinimumNone);
  });

  test('every refresh re-reads, one read at a time per route', () async {
    var reads = 0;
    final gate = Completer<OrchestraRouteLimits?>();
    final minimums = ReceiveMinimums(fetch: (_) {
      reads++;
      return gate.future;
    });
    final a = minimums.refresh(_usdc);
    final b = minimums.refresh(_usdc);
    gate.complete(const OrchestraRouteLimits(orderMinUsdCents: 110));
    expect((await a).usdCents, 110);
    expect((await b).usdCents, 110);
    expect(reads, 1);
    await minimums.refresh(_usdc);
    expect(reads, 2);
  });

  test('the live params name the exact minimum shown', () {
    const m = ReceiveMinimum(source: ReceiveMinimumSource.live, usdCents: 150);
    expect(m.trackingParams, {'min_deposit_usd': 1.5, 'min_source': 'live'});
  });
}
