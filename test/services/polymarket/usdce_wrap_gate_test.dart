// USDC.e → pUSD conversion: the decision to convert before a buy is
// signed, and the gate that keeps conversions from running twice.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart';

import '../../helpers/source_scan.dart';

BigInt _usd(num v) => BigInt.from((v * 1e6).round());

void main() {
  group('converting before a buy is signed', () {
    test('pUSD short, pUSD + USDC.e covers it: convert', () {
      expect(
          polyShouldWrapBeforeBuy(
              pusd: _usd(2), usdce: _usd(10), costMicros: _usd(5)),
          isTrue);
      // A deposit that landed while the app was closed: no pUSD at all.
      expect(
          polyShouldWrapBeforeBuy(
              pusd: BigInt.zero, usdce: _usd(5), costMicros: _usd(5)),
          isTrue);
    });

    test('pUSD alone covers it: nothing to convert first', () {
      expect(
          polyShouldWrapBeforeBuy(
              pusd: _usd(5), usdce: _usd(10), costMicros: _usd(5)),
          isFalse);
    });

    test('even both do not cover it: left to the order book', () {
      expect(
          polyShouldWrapBeforeBuy(
              pusd: _usd(1), usdce: _usd(2), costMicros: _usd(5)),
          isFalse);
    });

    test('no USDC.e, or no cost: nothing to do', () {
      expect(
          polyShouldWrapBeforeBuy(
              pusd: _usd(1), usdce: BigInt.zero, costMicros: _usd(5)),
          isFalse);
      expect(
          polyShouldWrapBeforeBuy(
              pusd: BigInt.zero, usdce: _usd(5), costMicros: BigInt.zero),
          isFalse);
    });

    test('a buy costs its shares times its price, rounded up', () {
      expect(polyBuyCostMicros(size: 10, price: 0.55), _usd(5.5));
      expect(polyBuyCostMicros(size: 3, price: 0.333333),
          BigInt.from(999999));
      expect(polyBuyCostMicros(size: 0, price: 0.5), BigInt.zero);
      expect(polyBuyCostMicros(size: double.nan, price: 0.5), BigInt.zero);
    });

    test('the order path converts before it signs, and keeps the refusal '
        'fallback', () {
      final code = stripComments(
          File('lib/providers/polymarket_trading_provider.dart')
              .readAsStringSync());
      final decide = code.indexOf('polyShouldWrapBeforeBuy(');
      final sign = code.indexOf('final signed = await buildOrder();');
      expect(decide, greaterThan(0));
      expect(sign, greaterThan(decide));
      expect(code, contains('isPolymarketBalanceRefusal(e.reason)'));
      expect(code, contains("trigger: 'refusal'"));
    });
  });

  group('one conversion at a time', () {
    test('a second caller while one runs gets its result, no second wrap',
        () async {
      final gate = UsdceWrapGate();
      var wraps = 0;
      final release = Completer<BigInt>();
      Future<BigInt> wrap() {
        wraps++;
        return release.future;
      }

      final first = gate.run('0xAbC', wrap);
      // Same wallet, other spelling: the order path and the arrival watch.
      final second = gate.run('0xabc', wrap);
      expect(gate.isRunning('0xABC'), isTrue);
      release.complete(_usd(25));
      expect(await first, _usd(25));
      expect(await second, _usd(25));
      expect(wraps, 1);
      expect(gate.isRunning('0xabc'), isFalse);

      // Once it is done, the next conversion runs again (and wraps only
      // what is there then).
      expect(await gate.run('0xabc', () async {
        wraps++;
        return BigInt.zero;
      }), BigInt.zero);
      expect(wraps, 2);
    });

    test('a failed conversion reaches every caller and frees the gate',
        () async {
      final gate = UsdceWrapGate();
      final release = Completer<BigInt>();
      final first = gate.run('0xabc', () => release.future);
      final second = gate.run('0xabc', () async => _usd(1));
      release.completeError(StateError('relayer'));
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(gate.isRunning('0xabc'), isFalse);
    });

    test('another wallet runs its own', () async {
      final gate = UsdceWrapGate();
      var wraps = 0;
      final a = gate.run('0xa', () async => _usd(++wraps));
      final b = gate.run('0xb', () async => _usd(++wraps));
      await Future.wait([a, b]);
      expect(wraps, 2);
    });
  });
}
