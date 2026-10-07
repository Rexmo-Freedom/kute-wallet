import 'package:flutter_test/flutter_test.dart';
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
}
