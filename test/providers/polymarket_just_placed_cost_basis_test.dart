// A prediction just placed shows what was really paid for it. The app keeps
// its own Bought row (keyed by the CLOB order id) until the Data API indexes
// the trade under the chain hash; the position's trade-history cost basis
// read both rows, so a 15¢ fill of $2.80 read "Bought 30¢", $5.59 invested
// and -50% until another reader of the box evicted the app's row.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket_optimistic_activity_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;

const _token = 'iran-yes-token';
const _shares = 18.6;
const _paid = 2.80;

Activity _buy({
  required String hash,
  required double usdc,
  required double shares,
  int? timestamp,
}) =>
    Activity(
      proxyWallet: '0xproxy',
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      conditionId: 'iran-condition',
      type: 'TRADE',
      size: shares,
      usdcSize: usdc,
      transactionHash: hash,
      price: usdc / shares,
      asset: _token,
      side: 'BUY',
      title: 'Will the U.S. invade Iran before 2027?',
      outcome: 'Yes',
    );

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('pm_just_placed');
    Hive.init(dir.path);
    await Hive.openBox<String>('polymarket_optimistic_activity');
  });
  tearDown(() async {
    await Hive.box<String>('polymarket_optimistic_activity').clear();
  });
  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  double boughtCents(List<Activity> activity) {
    final held = predictionHeldCostFromActivity(activity, _token);
    final basis = resolvePolymarketCostBasis(
      size: _shares,
      avgPrice: 0.15,
      activity: held,
    );
    return basis / _shares * 100;
  }

  test('the indexed trade replaces the app\'s own Bought row', () {
    // The order's own row, under the CLOB order id.
    PolymarketOptimisticActivityService.record(
        _buy(hash: '0xorderid', usdc: _paid, shares: _shares));
    // A minute later the Data API reports the same fill under its chain hash.
    final api = [_buy(hash: '0xchainhash', usdc: _paid, shares: _shares)];

    final merged = mergeOptimisticPolymarketActivity(api);
    expect(merged, hasLength(1));
    expect(merged.single.transactionHash, '0xchainhash');
    expect(boughtCents(merged), closeTo(15.05, 0.01));
  });

  test('a fill the API lists per maker is still the same trade', () {
    PolymarketOptimisticActivityService.record(
        _buy(hash: '0xorderid', usdc: _paid, shares: _shares));
    final api = [
      _buy(hash: '0xchainhash', usdc: 1.00, shares: 6.64),
      _buy(hash: '0xchainhash', usdc: 1.80, shares: 11.96),
    ];

    final merged = mergeOptimisticPolymarketActivity(api);
    expect(merged, hasLength(2));
    expect(boughtCents(merged), closeTo(15.05, 0.01));
  });

  test('before the API indexes the trade the app\'s row prices it', () {
    PolymarketOptimisticActivityService.record(
        _buy(hash: '0xorderid', usdc: _paid, shares: _shares));
    final merged = mergeOptimisticPolymarketActivity(const []);
    expect(merged, hasLength(1));
    expect(boughtCents(merged), closeTo(15.05, 0.01));
  });

  test('a history that counts the fill twice never reads 30¢', () {
    // The state the owner saw: both rows, 37.2 shares for $5.60, against a
    // position of 18.6 shares.
    final doubled = [
      _buy(hash: '0xorderid', usdc: _paid, shares: _shares),
      _buy(hash: '0xchainhash', usdc: _paid, shares: _shares),
    ];
    final held = predictionHeldCostFromActivity(doubled, _token)!;
    expect(held.cost / _shares * 100, closeTo(30.1, 0.1)); // the bug

    final basis = resolvePolymarketCostBasis(
      size: _shares,
      avgPrice: 0.15,
      activity: held,
    );
    // Falls back to the positions API's own average.
    expect(basis / _shares, closeTo(0.15, 0.0001));
    final value = _shares * 0.15;
    expect((value - basis).abs(), lessThan(0.01));
  });

  test('a history that agrees with the position keeps its exact cost', () {
    final basis = resolvePolymarketCostBasis(
      size: _shares,
      avgPrice: 0.15, // rounded by the API
      activity: (cost: 2.83, shares: _shares),
    );
    expect(basis, 2.83);
  });

  test('a local record still caps at one dollar a share', () {
    expect(
      resolvePolymarketCostBasis(size: 10, avgPrice: 0.2, cachedCost: 25),
      closeTo(2, 1e-9),
    );
  });
}
