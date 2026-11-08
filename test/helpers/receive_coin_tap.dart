// The Dollars Receive lists its coins in the coin sheet, through two
// doors (usd_receive_screen.dart): "Dollars" on top (the dollar coins; one
// coin goes straight to its networks or its address, as a coin tapped on a
// grid does) and "Another crypto" (every other coin). The Bitcoin
// receive's other coins keep their grid. A test that taps a coin goes
// through its door when the coin is not on screen yet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/usd/usd_receive_screen.dart'
    show kUsdReceiveDollarsKey;
import 'package:kute/services/orchestra/onetime_receive.dart'
    show isOneDollarCoin;

/// The Dollars Receive's "Dollars" card (a square beside Another crypto,
/// the grid's lead alone).
final Finder receiveDollarsLead = find.byKey(kUsdReceiveDollarsKey);

/// The Dollars Receive's "Another crypto" card.
final Finder receiveFromAnotherRow =
    find.byKey(const ValueKey('usd-receive-from-another'));

/// Opens the coin sheet from the Dollars Receive when no coin tile is on
/// screen yet: through "Another crypto" for a [symbol] that is not a
/// dollar coin, else through "Dollars" (or, without it, Another crypto).
Future<void> openReceiveCoins(WidgetTester tester, {String? symbol}) async {
  if (find.byType(CoinAssetTile).evaluate().isNotEmpty) return;
  final other = symbol != null && !isOneDollarCoin(symbol.toUpperCase());
  final door = !other && receiveDollarsLead.evaluate().isNotEmpty
      ? receiveDollarsLead
      : receiveFromAnotherRow;
  if (door.evaluate().isEmpty) return;
  await tester.tap(door);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Taps [symbol]'s coin tile, opening the coin sheet first if needed. The
/// lead's only coin needs no tile: its door already picked it.
Future<void> tapReceiveCoin(WidgetTester tester, String symbol) async {
  await openReceiveCoins(tester, symbol: symbol);
  final tile = find.widgetWithText(CoinAssetTile, symbol);
  if (tile.evaluate().isEmpty) return;
  await tester.tap(tile.first);
}
