// The Dollars Add lists its coins in the coin sheet (founder, 1 November
// 2026: "From another wallet or exchange" opens it, no inline grid); the
// Bitcoin receive's other coins keep their grid. A test that taps a coin
// goes through the row when the coin is not on screen yet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';

/// The Dollars Add's "From another wallet or exchange" row.
final Finder receiveFromAnotherRow =
    find.byKey(const ValueKey('usd-receive-from-another'));

/// Opens the coin sheet from the Dollars Add when no coin tile is on
/// screen yet.
Future<void> openReceiveCoins(WidgetTester tester) async {
  if (find.byType(CoinAssetTile).evaluate().isNotEmpty) return;
  if (receiveFromAnotherRow.evaluate().isEmpty) return;
  await tester.tap(receiveFromAnotherRow);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Taps [symbol]'s coin tile, opening the coin sheet first if needed.
Future<void> tapReceiveCoin(WidgetTester tester, String symbol) async {
  await openReceiveCoins(tester);
  await tester.tap(find.widgetWithText(CoinAssetTile, symbol).first);
}
