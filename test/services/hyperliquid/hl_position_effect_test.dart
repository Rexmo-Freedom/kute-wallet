import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hl_position_effect.dart';

HlPerpPosition _held(double szi) => HlPerpPosition(
      coin: 'BTC',
      szi: szi,
      entryPx: 60000,
      positionValue: szi.abs() * 60000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: szi.abs() * 60000,
      leverageType: 'isolated',
      leverageValue: 1,
      maxLeverage: 40,
    );

HlPositionPlan _plan(double? szi, {required bool long, required double size}) =>
    hlPositionPlan(
      position: szi == null ? null : _held(szi),
      orderIsLong: long,
      orderSize: size,
      szDecimals: 5,
    );

void main() {
  test('the position_effect values', () {
    expect(_plan(null, long: true, size: 0.001).effect.name, 'open');
    expect(_plan(0.01, long: true, size: 0.001).effect.name, 'add');
    expect(_plan(0.01, long: false, size: 0.004).effect.name, 'reduce');
    expect(_plan(0.01, long: false, size: 0.01).effect.name, 'close');
    expect(_plan(0.01, long: false, size: 0.012).effect.name, 'flip');
    expect(_plan(-0.01, long: true, size: 0.004).effect.name, 'reduce');
    expect(_plan(-0.01, long: true, size: 0.01).effect.name, 'close');
    expect(_plan(-0.01, long: true, size: 0.012).effect.name, 'flip');
    expect(_plan(-0.01, long: false, size: 0.004).effect.name, 'add');
  });

  test('within one size step of the position is a close of all of it', () {
    for (final size in [0.00999, 0.01, 0.01001]) {
      final plan = _plan(0.01, long: false, size: size);
      expect(plan.effect, HlPositionEffect.close, reason: '$size');
      expect(plan.isExit, isTrue);
      expect(plan.closeFraction, 1.0);
    }
    expect(_plan(0.01, long: false, size: 0.00998).effect,
        HlPositionEffect.reduce);
    expect(_plan(0.01, long: false, size: 0.01002).effect,
        HlPositionEffect.flip);
  });

  test('a reduce or a close goes reduce-only; a flip and an add do not', () {
    // A reduce worth about three dollars: still an exit, so the slip sends
    // it reduce-only through the close path with no venue minimum.
    final small = _plan(0.01, long: false, size: 0.00005);
    expect(small.isExit, isTrue);
    expect(small.closeFraction, closeTo(0.005, 1e-12));
    expect(small.remaining, closeTo(0.00995, 1e-12));
    expect(_plan(0.01, long: false, size: 0.012).isExit, isFalse);
    expect(_plan(0.01, long: true, size: 0.012).isExit, isFalse);
  });

  test('a flip opens only what is past the position', () {
    final flip = _plan(0.01, long: false, size: 0.012);
    expect(flip.remainder, closeTo(0.002, 1e-12));
    expect(flip.heldSide, 'long');
    expect(flip.opposes, isTrue);
  });
}
