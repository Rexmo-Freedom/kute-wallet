// The Hyperliquid chart's intervals: seven (1m 5m 15m 1h 4h 1D 1W); a 15m
// or 4h saved by an older build is itself again, and a saved interval the
// picker does not have opens as 1h.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';

void main() {
  test('the row is 1m 5m 15m 1h 4h 1D 1W', () {
    expect(kHlCandleIntervals.map((iv) => iv.label).toList(),
        ['1m', '5m', '15m', '1h', '4h', '1D', '1W']);
    expect(kHlCandleIntervals.map((iv) => iv.interval).toList(),
        ['1m', '5m', '15m', '1h', '4h', '1d', '1w']);
    expect(kHlCandleIntervals.map((iv) => iv.minutes).toList(),
        [1, 5, 15, 60, 240, 1440, 10080]);
  });

  test('an interval the row has is itself; anything else is 1h', () {
    expect(hlCandleInterval('5m').interval, '5m');
    expect(hlCandleInterval('1w').minutes, 10080);
    expect(hlCandleInterval('15m').minutes, 15);
    expect(hlCandleInterval('4h').minutes, 240);
    expect(hlCandleInterval('2h').interval, '1h');
    expect(hlCandleInterval('nonsense').interval, kHlDefaultCandleInterval);
  });

  test('a saved 15m or 4h opens as itself; what the picker lacks as 1h', () {
    expect(hlPickerInterval('15m'), '15m');
    expect(hlPickerInterval('4h'), '4h');
    expect(hlPickerInterval('2h'), '1h');
    expect(hlPickerInterval('3d'), '1h');
    expect(hlPickerInterval('1d'), '1d');
    expect(hlPickerInterval(null), '1h');
    expect(hlPickerInterval(42), '1h');
  });
}
