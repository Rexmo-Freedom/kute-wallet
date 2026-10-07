// Hyperliquid prices: up to 5 significant figures, whole numbers in full,
// never more decimals than the market allows (6 − szDecimals perps,
// 8 − szDecimals spot). Two neighbouring ticks must never print the same.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';

void main() {
  setUp(() => Intl.defaultLocale = 'en_US');

  test('five significant figures across magnitudes', () {
    expect(formatHlPrice(110234), r'$110,234');
    expect(formatHlPrice(85267), r'$85,267');
    expect(formatHlPrice(3912.4), r'$3,912.4');
    expect(formatHlPrice(371.55), r'$371.55');
    expect(formatHlPrice(12.345), r'$12.345');
    expect(formatHlPrice(1.7493), r'$1.7493');
    expect(formatHlPrice(0.37621), r'$0.37621');
    expect(formatHlPrice(0.012345, decimalCap: 6), r'$0.012345');
  });

  test('prices from 1 to 999 keep their ticks (no duplicate ladder rows)',
      () {
    // Before: both read "$371.52" / "$12.34".
    expect(formatHlPrice(371.52), isNot(formatHlPrice(371.53)));
    expect(formatHlPrice(12.341), isNot(formatHlPrice(12.342)));
    expect(formatHlPrice(1.0001), isNot(formatHlPrice(1.0002)));
  });

  test('capped by the market decimals', () {
    // A perp with szDecimals 4 allows 2 decimals.
    expect(formatHlPrice(12.3456, decimalCap: 2), r'$12.35');
    // BTC (szDecimals 5) allows 1 decimal; 5 sig figs need none.
    expect(formatHlPrice(110234.5, decimalCap: 1), r'$110,235');
  });

  test('trailing zeros drop to two decimals, powers of ten are exact', () {
    expect(formatHlPrice(12.3), r'$12.30');
    expect(formatHlPrice(1000), r'$1,000.0');
    expect(formatHlPrice(100), r'$100.00');
    expect(hlPriceDecimals(1000), 1);
    expect(hlPriceDecimals(999.99), 2);
  });

  test('nothing to show', () {
    expect(formatHlPrice(0), '—');
    expect(formatHlPrice(-1), '—');
    expect(formatHlPrice(double.nan), '—');
  });
}
