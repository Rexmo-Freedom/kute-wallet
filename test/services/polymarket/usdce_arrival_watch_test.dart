// The deposit wallet's arrival watch (USDC.e → pUSD) never waits for the
// next app start. Founder: "why would we wait". It used to end quietly when
// the Predictions state, deposit wallet or key was not loaded at its first
// pass (a cold start, the unlock, a rebuild), so a deposit sent then stayed
// USDC.e until the app was opened again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart';

import '../../helpers/source_scan.dart';

const _account = (eoa: '0xeoa', wallet: '0xwallet', key: 'key');

class _Harness {
  UsdceWatchAccount? loaded;
  bool ready = true;
  bool onItsWay = false;
  bool gone = false;
  BigInt held = BigInt.zero;
  final wraps = <UsdceWatchAccount>[];
  var setupAsks = 0;
  var waits = 0;

  late final watch = UsdceArrivalWatch(
    account: () => loaded,
    ready: () => ready,
    wrap: (a) async {
      wraps.add(a);
      final got = held;
      held = BigInt.zero;
      return got;
    },
    onItsWay: (_) => onItsWay,
    waitForAccount: (max) {
      waits++;
      return Future<void>.delayed(max);
    },
    gone: () => gone,
    askSetup: () => setupAsks++,
    setupEvery: const Duration(hours: 1),
  );

  Future<void> start({Duration timeout = const Duration(seconds: 5)}) =>
      watch.start(
          timeout: timeout,
          interval: const Duration(milliseconds: 2),
          lateInterval: const Duration(milliseconds: 2));
}

Future<void> _until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test(
      'the account loads late: the watch waits for it and converts in the '
      'same session', () async {
    final h = _Harness()..held = BigInt.from(4670000);
    final run = h.start();
    // Nothing loaded yet: the watch keeps waiting, never ends.
    await _until(() => h.waits >= 3);
    expect(h.watch.until, isNotNull);
    expect(h.wraps, isEmpty);
    h.loaded = _account;
    await run;
    expect(h.wraps, [_account]);
    expect(h.watch.until, isNull);
  });

  test(
      'setup done late: asked again (once), then the conversion runs in the '
      'same watch', () async {
    final h = _Harness()
      ..loaded = _account
      ..ready = false
      ..held = BigInt.from(1000000);
    final run = h.start();
    await _until(() => h.waits >= 3);
    expect(h.wraps, isEmpty);
    expect(h.setupAsks, 1);
    h.ready = true;
    await run;
    expect(h.wraps, hasLength(1));
  });

  test('a second start while one runs only pushes its end out', () async {
    final h = _Harness();
    final first = h.start(timeout: const Duration(milliseconds: 30));
    final end = h.watch.until!;
    final second = h.start(timeout: const Duration(seconds: 1));
    expect(identical(first, second), isTrue);
    expect(h.watch.until!.isAfter(end), isTrue);
    await _until(() => h.waits >= 2);
    h
      ..loaded = _account
      ..held = BigInt.from(2000000);
    await second;
    // One watch, one conversion.
    expect(h.wraps, hasLength(1));
  });

  test(
      'keeps watching past its window while the deposit is on its way, and '
      'after a conversion while another one still is', () async {
    final h = _Harness()
      ..loaded = _account
      ..onItsWay = true
      ..held = BigInt.from(1000000);
    final run = h.start(timeout: const Duration(milliseconds: 10));
    // Converted, but another deposit is still on its way: keeps watching,
    // past its window too.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await _until(() => h.wraps.length >= 3);
    expect(h.watch.until, isNotNull);
    h.onItsWay = false;
    await run;
    expect(h.watch.until, isNull);
  });

  test('a rebuild (gone for one pass) does not end it; staying gone does',
      () async {
    final h = _Harness()..gone = true;
    final run = h.start();
    await _until(() => h.waits >= 1);
    h.gone = false;
    h.loaded = _account;
    h.held = BigInt.from(1000000);
    await run;
    expect(h.wraps, hasLength(1));

    final h2 = _Harness()..gone = true;
    await h2.start();
    expect(h2.wraps, isEmpty);
    expect(h2.waits, 1);
  });

  test('the notifier\'s watch runs through it, and setup completing wakes it',
      () {
    final code = stripComments(
        File('lib/providers/polymarket_trading_provider.dart')
            .readAsStringSync());
    // The old early exit is gone: the watch is the shared one.
    expect(code, isNot(contains('_wrapWatchUntil')));
    expect(code, contains('_arrivalWatch.start('));
    // Every published state wakes a waiting watch; setup completing (from
    // any caller) converts what sits in the wallet or is on its way.
    expect(
        RegExp(r'state = AsyncData\(newState\);[\s\S]{0,120}_wakeAccountWaiters\(\);')
            .hasMatch(code),
        isTrue);
    expect(code, contains('if (tradingReady) _onTradingReady();'));
  });

  test('Investing → Predictions from the Move sheet starts the watch', () {
    final code = stripComments(
        File('lib/screens/home/components/deposit_sheet.dart')
            .readAsStringSync());
    final start = code.indexOf('Future<void> _dispatchInvestingToPredictions(');
    final end = code.indexOf('Future<void> _dispatchHyperliquidToBtc(');
    expect(start, greaterThan(0));
    expect(code.substring(start, end), contains('.wrapIncomingUsdcEToPusd()'));
  });
}
