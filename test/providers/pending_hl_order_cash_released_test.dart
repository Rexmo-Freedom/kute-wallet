// Which Investing fills free venue cash for the sweeper: closes, reduces,
// flips, liquidations and spot sells do; opens and buys commit cash.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';

HlFill _fill(String dir, {bool liquidated = false}) => HlFill(
      coin: 'BTC',
      px: 60000,
      sz: 0.001,
      side: 'A',
      time: 1,
      closedPnl: 0,
      fee: 0.01,
      feeToken: 'USDC',
      oid: 1,
      hash: '0x1',
      dir: dir,
      cloid: null,
      liquidated: liquidated,
    );

void main() {
  test('closes, reduces, flips, liquidations and sells release cash', () {
    expect(hlFillReleasesCash(_fill('Close Long')), isTrue);
    expect(hlFillReleasesCash(_fill('Close Short')), isTrue);
    expect(hlFillReleasesCash(_fill('Long > Short')), isTrue);
    expect(hlFillReleasesCash(_fill('Sell')), isTrue);
    expect(hlFillReleasesCash(_fill('Open Long', liquidated: true)), isTrue);
  });

  test('opens and buys do not', () {
    expect(hlFillReleasesCash(_fill('Open Long')), isFalse);
    expect(hlFillReleasesCash(_fill('Open Short')), isFalse);
    expect(hlFillReleasesCash(_fill('Buy')), isFalse);
  });
}
