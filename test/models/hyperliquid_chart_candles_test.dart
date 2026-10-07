// What the Investing chart ends on: the live price folded into the
// leading bar on a market that trades, the last traded price on one that
// hardly does (its mid is not a print).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';

HyperliquidCandle _bar(int i, double close) => HyperliquidCandle(
      openTime: DateTime.utc(2026, 10, 4, 12, i * 5),
      closeTime: DateTime.utc(2026, 10, 4, 12, i * 5 + 5),
      open: close - 2,
      high: close + 3,
      low: close - 4,
      close: close,
      volume: 1,
    );

void main() {
  // GOOGL spot on 2026-10-05: last prints near $300, the mid at $335.61.
  final thin = [_bar(0, 302), _bar(1, 301), _bar(2, 300)];
  // BTC: the live mid a few dollars from the last close.
  final btc = [_bar(0, 86500), _bar(1, 86520), _bar(2, 86522)];

  test('a low-liquidity market ends on its last traded price', () {
    final out = chartCandlesWithLive(thin, 335.61, lowLiquidity: true);
    expect(out.last.close, 300);
    expect(out.last.high, 303);
    expect(out, thin);
  });

  test('a liquid market ticks with the header, as it always has', () {
    final out = chartCandlesWithLive(btc, 86655, lowLiquidity: false);
    expect(out.last.close, 86655);
    expect(out.last.high, 86655);
    expect(out.last.open, btc.last.open);
    expect(out.sublist(0, 2), btc.sublist(0, 2));
    final folded = foldDisplayPxIntoLastCandle(btc, 86655).last;
    expect(out.last.close, folded.close);
    expect(out.last.high, folded.high);
    expect(out.last.low, folded.low);
  });

  test('the same liquid market with the mid on its last close is left as '
      'it is', () {
    expect(chartCandlesWithLive(btc, 86522, lowLiquidity: false), btc);
  });
}
