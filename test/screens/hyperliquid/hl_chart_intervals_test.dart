// The Hyperliquid chart's interval row: five pills (1m 5m 1h 1D 1W), and
// a saved interval the row no longer has (15m, 4h from older builds)
// opening as 1h.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';

void main() {
  test('the row is 1m 5m 1h 1D 1W', () {
    expect(kHlCandleIntervals.map((iv) => iv.label).toList(),
        ['1m', '5m', '1h', '1D', '1W']);
    expect(kHlCandleIntervals.map((iv) => iv.interval).toList(),
        ['1m', '5m', '1h', '1d', '1w']);
  });

  test('an interval the row has is itself; anything else is 1h', () {
    expect(hlCandleInterval('5m').interval, '5m');
    expect(hlCandleInterval('1w').minutes, 10080);
    expect(hlCandleInterval('15m').interval, '1h');
    expect(hlCandleInterval('4h').interval, '1h');
    expect(hlCandleInterval('nonsense').interval, kHlDefaultCandleInterval);
  });

  test('a saved 15m or 4h opens as 1h', () {
    expect(hlPickerInterval('15m'), '1h');
    expect(hlPickerInterval('4h'), '1h');
    expect(hlPickerInterval('1d'), '1d');
    expect(hlPickerInterval(null), '1h');
    expect(hlPickerInterval(42), '1h');
  });
}
