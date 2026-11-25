import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hl_price_line.dart';
import 'package:kute/models/hyperliquid_market.dart';

HlPriceLine _line(double level, HlPriceLineDirection direction) => HlPriceLine(
      id: '1',
      marketKey: 'hl:perp::BTC',
      coin: 'BTC',
      wireCoin: 'BTC',
      kind: HlMarketKind.perp,
      level: level,
      direction: direction,
      createdAtMs: 100,
    );

void main() {
  test('a line reads a price from the side it was set on', () {
    final above = _line(110, HlPriceLineDirection.above);
    expect(above.reachedBy(109.99), isFalse);
    expect(above.reachedBy(110), isTrue);
    expect(above.reachedBy(130), isTrue);
    final below = _line(90, HlPriceLineDirection.below);
    expect(below.reachedBy(90.01), isFalse);
    expect(below.reachedBy(90), isTrue);
    expect(below.reachedBy(70), isTrue);
  });

  test('silly levels and a full list are refused', () {
    HlPriceLineRefusal? check(double level,
            {double? now = 100, int count = 0}) =>
        hlPriceLineRefusal(level: level, reference: now, count: count);
    expect(check(110), isNull);
    expect(check(90), isNull);
    expect(check(1000), isNull);
    expect(check(10), isNull);
    expect(check(1000.1), HlPriceLineRefusal.tooFar);
    expect(check(9.99), HlPriceLineRefusal.tooFar);
    expect(check(0), HlPriceLineRefusal.tooFar);
    expect(check(double.nan), HlPriceLineRefusal.tooFar);
    expect(check(100), HlPriceLineRefusal.atPrice);
    expect(check(100.005), HlPriceLineRefusal.atPrice);
    expect(check(110, now: null), HlPriceLineRefusal.atPrice);
    expect(check(110, count: kHlPriceLineLimit), HlPriceLineRefusal.limit);
    expect(check(110, count: kHlPriceLineLimit - 1), isNull);
  });

  test('json round trip, and a corrupt record is dropped', () {
    final line = _line(90, HlPriceLineDirection.below).reachedAt(500);
    final back = HlPriceLine.fromJson(line.toJson())!;
    expect(back.id, '1');
    expect(back.marketKey, 'hl:perp::BTC');
    expect(back.coin, 'BTC');
    expect(back.wireCoin, 'BTC');
    expect(back.kind, HlMarketKind.perp);
    expect(back.level, 90);
    expect(back.direction, HlPriceLineDirection.below);
    expect(back.createdAtMs, 100);
    expect(back.reachedAtMs, 500);
    expect(HlPriceLine.fromJson(const {'id': '1'}), isNull);
    final bad = line.toJson()..['level'] = -1;
    expect(HlPriceLine.fromJson(bad), isNull);
  });
}
