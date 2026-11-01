import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid/hypercore_dex_cash.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

HlAccountSnapshot cash(double amount) => HlAccountSnapshot(
    accountValue: amount,
    withdrawable: amount,
    totalMarginUsed: 0,
    positions: const [],
    spotBalances: const []);

class Accounts extends HyperliquidModel {
  Accounts(this.base, this.dexes);
  final double base;
  final Map<String, HlAccountSnapshot> dexes;
  @override
  Future<HlAccountSnapshot> getAccountSnapshot(String address) async =>
      cash(base);
  @override
  Future<Map<String, HlAccountSnapshot>> getUsdcDexAccounts(
          String address) async =>
      dexes;
}

class Transfers implements HyperliquidExchangeService {
  final calls = <({String from, String to, double amount})>[];
  bool loseReply = false;
  @override
  String get walletAddress => '0x1111111111111111111111111111111111111111';
  @override
  Future<void> moveOwnUsdc(
      {required String sourceDex,
      required String destinationDex,
      required double amount,
      void Function()? beforeSend}) async {
    beforeSend?.call();
    calls.add((from: sourceDex, to: destinationDex, amount: amount));
    if (loseReply)
      throw const HyperliquidApiException(statusCode: 504, body: 'Unknown');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('HIP-3 transfer waits for its own clearinghouse before placing',
      () async {
    var reads = 0;
    await waitForOwnDexCash(
      requiredUsd: 10.93,
      pollEvery: const Duration(milliseconds: 1),
      availableUsd: () async => ++reads < 3 ? 0 : 10.93,
    );
    expect(reads, 3);
  });
  test(
      'an unreadable HIP-3 clearinghouse cannot leave placement waiting forever',
      () async {
    await expectLater(
        waitForOwnDexCash(
          requiredUsd: 10.93,
          maxWait: const Duration(milliseconds: 10),
          availableUsd: () => Completer<double>().future,
        ),
        throwsA(isA<OwnDexCreditPending>()));
  });
  test('short collateral fails boundedly without submitting another transfer',
      () async {
    await expectLater(
        waitForOwnDexCash(
          requiredUsd: 10.93,
          maxWait: const Duration(milliseconds: 10),
          pollEvery: const Duration(milliseconds: 1),
          availableUsd: () async => 10.74,
        ),
        throwsA(isA<OwnDexCreditPending>()));
  });
  test('insufficient total cash never triggers a partial collateral move',
      () async {
    final exchange = Transfers();
    await expectLater(
        collectOwnDexCash(
            model: Accounts(1, {'xyz': cash(2)}),
            exchange: exchange,
            requiredDefaultUsd: 5),
        throwsA(isA<HyperliquidInsufficientMarginException>()));
    expect(exchange.calls, isEmpty);
  });
  test('only the shortfall moves; destination DEX is not drained', () async {
    final exchange = Transfers();
    await collectOwnDexCash(
        model: Accounts(4, {'xyz': cash(100), 'other': cash(20)}),
        exchange: exchange,
        requiredDefaultUsd: 6,
        excludeDex: 'xyz');
    expect(exchange.calls, [(from: 'other', to: '', amount: 2.0)]);
  });
  test('a lost transfer response stops without retrying or moving another leg',
      () async {
    final exchange = Transfers()..loseReply = true;
    await expectLater(
        collectOwnDexCash(
            model: Accounts(0, {'a': cash(2), 'b': cash(3)}),
            exchange: exchange,
            requiredDefaultUsd: 4),
        throwsA(isA<HyperliquidApiException>()));
    expect(exchange.calls.length, 1);
  });

  // The first order on OPENAI used to fail: the builder dex showed the
  // collateral just sent to it after more than the old 8 s, the order gave
  // up ("Crediting to trading balance" as a failure), and the second try,
  // finding the cash there, went through. The order path waits longer.
  test('a slow builder dex read is waited for on the first order',
      () async {
    // A read that catches up only after a while (scaled down: 80 ms).
    final clock = Stopwatch()..start();
    Future<double> read() async =>
        clock.elapsed >= const Duration(milliseconds: 80) ? 10.93 : 0;
    // A wait shorter than the dex takes gives up with the cash on its way.
    await expectLater(
        waitForOwnDexCash(
          requiredUsd: 10.93,
          maxWait: const Duration(milliseconds: 20),
          pollEvery: const Duration(milliseconds: 5),
          availableUsd: read,
        ),
        throwsA(isA<OwnDexCreditPending>()));
    // The order path's wait sees it land.
    await waitForOwnDexCash(
      requiredUsd: 10.93,
      maxWait: kOwnDexCreditWait,
      pollEvery: const Duration(milliseconds: 5),
      availableUsd: read,
    );
    expect(clock.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 80)));
    expect(
        kOwnDexCreditWait, greaterThanOrEqualTo(const Duration(seconds: 30)));
  });
}
