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
      // The decision lives in the buy's collateral check
      // (venue_collateral.dart), which runs before the order is signed.
      final decide = code.indexOf('polyReadyVenueCollateral(');
      final sign = code.indexOf('final signed = await buildOrder();');
      expect(decide, greaterThan(0));
      expect(sign, greaterThan(decide));
      expect(
          File('lib/services/polymarket/venue_collateral.dart')
              .readAsStringSync(),
          contains('polyShouldWrapBeforeBuy('));
      expect(code, contains('isPolymarketBalanceRefusal(e.reason)'));
      expect(code, contains("trigger: prefetched ? 'order' : 'refusal'"));
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

  group('no conversion while a funded bet\'s money is still on its way', () {
    tearDown(FundedConversionHold.reset);

    test('held while funding or waiting, until the balances showed all of it',
        () {
      // Funding running (the legs on their way, the bet not queued yet).
      expect(
          fundedConversionHeld(
              funded: true,
              fundingRunning: true,
              awaitingBalance: false,
              landedConfirmed: false),
          isTrue);
      // Queued for its money, not all of it read on chain yet.
      expect(
          fundedConversionHeld(
              funded: true,
              fundingRunning: false,
              awaitingBalance: true,
              landedConfirmed: false),
          isTrue);
      // The wallet's balances showed every leg's money: the one
      // conversion may run.
      expect(
          fundedConversionHeld(
              funded: true,
              fundingRunning: false,
              awaitingBalance: true,
              landedConfirmed: true),
          isFalse);
      // A bet funded from nothing, or one placing, done, failed or
      // cleared, holds nothing: a stop never leaves conversions held.
      expect(
          fundedConversionHeld(
              funded: false,
              fundingRunning: false,
              awaitingBalance: true,
              landedConfirmed: false),
          isFalse);
      expect(
          fundedConversionHeld(
              funded: true,
              fundingRunning: false,
              awaitingBalance: false,
              landedConfirmed: false),
          isFalse);
    });

    test('the autofire answers; removed, nothing is held', () {
      expect(FundedConversionHold.held, isFalse);
      var held = true;
      final remove = FundedConversionHold.install(() => held);
      expect(FundedConversionHold.held, isTrue);
      held = false;
      expect(FundedConversionHold.held, isFalse);
      held = true;
      remove();
      expect(FundedConversionHold.held, isFalse);
      // A failing answer holds nothing.
      FundedConversionHold.install(() => throw StateError('gone'));
      expect(FundedConversionHold.held, isFalse);
    });

    test('every conversion path asks first, before the gate and the relayer',
        () {
      final code = stripComments(
          File('lib/providers/polymarket_trading_provider.dart')
              .readAsStringSync());
      final wrap = code.indexOf('Future<BigInt> _wrapHeldUsdcE(');
      final hold = code.indexOf('FundedConversionHold.held', wrap);
      final gate = code.indexOf('_wrapGate.run(wallet', wrap);
      expect(wrap, greaterThan(0));
      expect(hold, greaterThan(wrap));
      expect(gate, greaterThan(hold));
      // The post-withdraw rewrap (its own direct call) asks too.
      final rewrap = code.indexOf('void scheduleDelayedUsdceRewrap(');
      final rewrapHold = code.indexOf('FundedConversionHold.held', rewrap);
      final rewrapCall =
          code.indexOf('wrapUsdceToPusdInDepositWallet(', rewrap);
      expect(rewrapHold, greaterThan(rewrap));
      expect(rewrapCall, greaterThan(rewrapHold));
      // Nothing else converts outside _wrapHeldUsdcE.
      expect('wrapHeldUsdceToPusdInDepositWallet('.allMatches(code).length, 1);
    });
  });
}
