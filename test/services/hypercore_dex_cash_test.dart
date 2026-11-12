import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
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
  test('a slow builder dex read is waited for on the first order', () async {
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
    expect(
        clock.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 80)));
    expect(
        kOwnDexCreditWait, greaterThanOrEqualTo(const Duration(seconds: 30)));
  });

  group('a send out of Investing gathers its own cash first', () {
    // The founder's Swap (12 November 2026): a stock bought and closed on
    // the xyz builder dex left $20.94 there. The Investing leg moved it home
    // to perpetuals and read the main account at once: the read had not
    // caught up, the send found it short and stopped as "not sent". The
    // Retry, finding the cash already home, went through.
    const reserve8 = 2094000000; // $20.88 burn + $0.06 HyperCore reserve

    BigInt spotMoveOf(Ledger ledger) => hypercorePerpShortfall(
          requiredBaseUnits: BigInt.from(reserve8),
          spotAvailable: ledger.spot,
          perpAvailable: ledger.readMain(),
        );

    test('after a dex stock round-trip: moved home, waited for, then sent',
        () async {
      final ledger = Ledger(main: 0, dexes: {'xyz': 20.94}, lagReads: 3);
      await gatherOwnPerpCash(
        model: ledger,
        exchange: ledger,
        requiredBaseUnits: BigInt.from(reserve8),
        requiredDefaultBaseUnits: BigInt.from(reserve8),
        spotMove: () async => spotMoveOf(ledger),
        pollEvery: const Duration(milliseconds: 1),
      );
      expect(ledger.moves, [(from: 'xyz', to: '', amount: 20.94)]);
      expect(ledger.classTransfers, isEmpty);
      // The main account's own read shows it: the burn's check passes.
      expect(spotMoveOf(ledger), BigInt.zero);
    });

    test('the old order (move, then read at once) is what stopped the leg',
        () async {
      final ledger = Ledger(main: 0, dexes: {'xyz': 20.94}, lagReads: 3);
      await collectOwnDexCash(
          model: ledger, exchange: ledger, requiredDefaultUsd: reserve8 / 1e8);
      expect(
          () => spotMoveOf(ledger), throwsA(isA<HypercoreBalanceShortfall>()));
    });

    test(
        'a read that never catches up stops before the send; Retry then '
        'sends without moving the cash again', () async {
      final ledger = Ledger(main: 0, dexes: {'xyz': 20.94}, lagReads: 1000);
      await expectLater(
          gatherOwnPerpCash(
            model: ledger,
            exchange: ledger,
            requiredBaseUnits: BigInt.from(reserve8),
            requiredDefaultBaseUnits: BigInt.from(reserve8),
            spotMove: () async => spotMoveOf(ledger),
            maxWait: const Duration(milliseconds: 20),
            pollEvery: const Duration(milliseconds: 1),
          ),
          throwsA(isA<OwnDexCreditPending>()));
      expect(ledger.moves.length, 1);
      // Later the read has caught up: the Retry moves nothing and goes.
      ledger.caughtUp();
      await gatherOwnPerpCash(
        model: ledger,
        exchange: ledger,
        requiredBaseUnits: BigInt.from(reserve8),
        requiredDefaultBaseUnits: BigInt.from(reserve8),
        spotMove: () async => spotMoveOf(ledger),
        pollEvery: const Duration(milliseconds: 1),
      );
      expect(ledger.moves.length, 1);
      expect(spotMoveOf(ledger), BigInt.zero);
    });

    test('spot USDC: moved to perpetuals and waited for', () async {
      final ledger = Ledger(main: 0, dexes: const {}, spot: 20.94, lagReads: 2);
      await gatherOwnPerpCash(
        model: ledger,
        exchange: ledger,
        requiredBaseUnits: BigInt.from(reserve8),
        requiredDefaultBaseUnits: BigInt.zero,
        spotMove: () async => spotMoveOf(ledger),
        pollEvery: const Duration(milliseconds: 1),
      );
      expect(ledger.moves, isEmpty);
      expect(ledger.classTransfers, [20.94]);
      expect(ledger.main, closeTo(20.94, 1e-9));
    });

    test(
        'a fraction of a micro-dollar on the main account never leaves the '
        'send short', () async {
      // Flooring the dex leg moved 20.939999 onto 0.0000005: half a
      // micro-dollar short of the exact requirement.
      final ledger =
          Ledger(main: 0.0000005, dexes: {'xyz': 20.95}, lagReads: 0);
      await gatherOwnPerpCash(
        model: ledger,
        exchange: ledger,
        requiredBaseUnits: BigInt.from(reserve8),
        requiredDefaultBaseUnits: BigInt.from(reserve8),
        spotMove: () async => spotMoveOf(ledger),
        pollEvery: const Duration(milliseconds: 1),
      );
      expect(ledger.moves.single.amount, 20.94);
      expect(spotMoveOf(ledger), BigInt.zero);
    });
  });
}

/// One Investing account: main perpetuals, builder dexes and spot USDC,
/// whose main-account read lags [lagReads] reads behind each move.
class Ledger extends HyperliquidModel implements HyperliquidExchangeService {
  Ledger(
      {required this.main,
      required Map<String, double> dexes,
      this.spot = 0,
      this.lagReads = 0})
      : dexes = {...dexes};

  double main;
  double spot;
  final Map<String, double> dexes;
  int lagReads;
  double _shownMain = double.nan;
  int _staleLeft = 0;
  final moves = <({String from, String to, double amount})>[];
  final classTransfers = <double>[];

  double readMain() {
    if (_staleLeft > 0 && !_shownMain.isNaN) {
      _staleLeft--;
      return _shownMain;
    }
    return main;
  }

  /// The main account's read has caught up with every move.
  void caughtUp() => _staleLeft = 0;

  void _moved(double before) {
    _shownMain = before;
    _staleLeft = lagReads;
  }

  @override
  String get walletAddress => '0x1111111111111111111111111111111111111111';

  @override
  Future<HlAccountSnapshot> getAccountSnapshot(String address) async =>
      cash(readMain());

  @override
  Future<Map<String, HlAccountSnapshot>> getUsdcDexAccounts(
          String address) async =>
      {for (final e in dexes.entries) e.key: cash(e.value)};

  @override
  Future<void> moveOwnUsdc(
      {required String sourceDex,
      required String destinationDex,
      required double amount,
      void Function()? beforeSend}) async {
    beforeSend?.call();
    final before = main;
    dexes[sourceDex] = dexes[sourceDex]! - amount;
    main += amount;
    moves.add((from: sourceDex, to: destinationDex, amount: amount));
    _moved(before);
  }

  @override
  Future<void> usdClassTransfer(
      {required double amount,
      required bool toPerp,
      void Function()? beforeSend}) async {
    beforeSend?.call();
    final before = main;
    spot -= amount;
    main += amount;
    classTransfers.add(amount);
    _moved(before);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
