// The open orders a refresh carries, through the account's own refresh
// reads (_fetchAllData, with fakes for the public model and the
// authenticated service; nothing reaches the network):
//   * a cold boot (no cache, no earlier list) whose orders read fails is
//     nothing reserved, exactly as before limits: a plain bet is never held;
//   * a cash-only tick keeps the account's list, never another account's;
//   * a failed full read keeps the account's last list (a known reserve
//     stays held, resting sells stay locked) for kPolymarketKeptOrdersFor,
//     then the account reads as nothing reserved again, and a read that
//     lands starts over.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show ClosedPosition, Order, Position;

const _eoa = '0x1111111111111111111111111111111111111111';
const _a = '0x2222222222222222222222222222222222222222';
const _b = '0x3333333333333333333333333333333333333333';

Order _buy(String id, {String size = '10', String price = '0.30'}) => Order(
    id: id,
    market: 'm',
    assetId: 't',
    owner: 'x',
    side: 'BUY',
    price: price,
    originalSize: size,
    sizeMatched: '0',
    outcome: 'Yes');

class _Model extends Fake implements PolymarketModel {
  @override
  List<ClosedPosition> closedSoldPositions = const [];
  @override
  Set<String> closedNegRiskConditionIds = const {};
  @override
  void invalidateBalanceCache() {}
  @override
  Future<List<Position>?> getPositionsOrNull(String walletAddress,
          {Object? client}) async =>
      const [];
  @override
  Future<double> getOnChainUsdcBalance(String walletAddress) async => 5;
  @override
  Future<double> getPortfolioTotalValue(String walletAddress,
          {Object? client}) async =>
      5;
  @override
  Future<List<ClosedPosition>> getClosedPositions(String walletAddress,
          {Object? client}) async =>
      const [];
}

/// The authenticated orders read: answers [orders], or fails.
class _Backend extends Fake implements PolymarketBackendService {
  List<Order>? orders = const [];
  int reads = 0;
  @override
  Future<List<Order>> getOpenOrders({String? market}) async {
    reads++;
    final o = orders;
    if (o == null) throw StateError('orders read failed');
    return o;
  }
}

class _Account extends PolymarketTradingNotifier {
  _Account(this.start);
  final PolymarketTradingState? start;
  @override
  Future<PolymarketTradingState> build() async =>
      start ?? const PolymarketTradingState();
  void set(PolymarketTradingState s) => state = AsyncData(s);
}

void main() {
  late DateTime now;
  setUp(() {
    now = DateTime(2026, 11, 27, 12);
    PolymarketTradingNotifier.ordersClock = () => now;
  });
  tearDown(() => PolymarketTradingNotifier.ordersClock = DateTime.now);

  Future<(_Account, _Backend, ProviderContainer)> account(
      {PolymarketTradingState? start}) async {
    final notifier = _Account(start);
    final backend = _Backend();
    final container = ProviderContainer(overrides: [
      polymarketTradingProvider.overrideWith(() => notifier),
    ]);
    addTearDown(container.dispose);
    container.listen(polymarketTradingProvider, (_, __) {});
    await container.read(polymarketTradingProvider.future);
    notifier.debugUseReads(_Model(), backend);
    return (notifier, backend, container);
  }

  Future<PolymarketTradingState> read(_Account n,
      {String proxy = _a,
      PolymarketRefreshScope scope = PolymarketRefreshScope.full}) async {
    final s = await n.debugFetchAllData(_eoa, proxyWallet: proxy, scope: scope);
    n.set(s);
    return s;
  }

  test(
      'a cold boot with no cache whose orders read fails: nothing reserved, '
      'and a plain bet sizes on the whole balance, as before', () async {
    final (n, backend, container) = await account();
    backend.orders = null;
    // The account start's first read is cash only, then the full read fails.
    expect((await read(n, scope: PolymarketRefreshScope.cash)).openOrders,
        isEmpty);
    final s = await read(n);
    expect(s.openOrders, isEmpty);
    expect(s.balanceKnown, isTrue);
    expect(PolymarketBetController.spendableUsdc(s.usdcBalance, s.openOrders),
        5);
    expect(backend.reads, 1);
    expect(container.read(polymarketTradingProvider).valueOrNull?.usdcBalance,
        5);
  });

  test('a cash-only tick keeps the account\'s list, never another\'s',
      () async {
    final (n, backend, _) = await account();
    backend.orders = [_buy('o1')];
    expect((await read(n)).openOrders.single.id, 'o1');
    // A cash tick reads no orders: the list stays.
    expect((await read(n, scope: PolymarketRefreshScope.cash)).openOrders
        .single
        .id, 'o1');
    // Another account's cash tick never carries the last one's list.
    expect(
        (await read(n, proxy: _b, scope: PolymarketRefreshScope.cash))
            .openOrders,
        isEmpty);
  });

  test(
      'a failed full read keeps the list for its bound, then nothing is '
      'reserved; a read that lands starts over', () async {
    final (n, backend, _) = await account();
    backend.orders = [_buy('o1')];
    await read(n);
    backend.orders = null;
    // Failing reads within the bound: the reserve ($3 of $5) is held.
    var s = await read(n);
    expect(s.openOrders.single.id, 'o1');
    expect(PolymarketBetController.spendableUsdc(s.usdcBalance, s.openOrders),
        closeTo(2, 1e-9));
    now = now.add(kPolymarketKeptOrdersFor);
    s = await read(n);
    expect(s.openOrders.single.id, 'o1');
    // Past it: nothing reserved, the venue's refusal is the guard.
    now = now.add(const Duration(seconds: 1));
    s = await read(n);
    expect(s.openOrders, isEmpty);
    expect(PolymarketBetController.spendableUsdc(s.usdcBalance, s.openOrders),
        5);
    // A read that lands: its list, and the clock starts over.
    backend.orders = [_buy('o2')];
    expect((await read(n)).openOrders.single.id, 'o2');
    backend.orders = null;
    now = now.add(const Duration(minutes: 1));
    expect((await read(n)).openOrders.single.id, 'o2');
  });

  test(
      'a cached list restored at launch is kept for the bound too while '
      'every read fails', () async {
    final (n, backend, _) = await account(
        start: PolymarketTradingState(
            proxyWalletAddress: _a, usdcBalance: 5, openOrders: [_buy('c1')]));
    backend.orders = null;
    expect((await read(n)).openOrders.single.id, 'c1');
    now = now.add(kPolymarketKeptOrdersFor + const Duration(seconds: 1));
    expect((await read(n)).openOrders, isEmpty);
  });
}
