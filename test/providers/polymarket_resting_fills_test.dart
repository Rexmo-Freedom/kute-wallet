// P6: a resting limit order that fills is said once (the Sal toast,
// polymarket_screen.dart), whichever way the fill is seen first: the user
// channel's order update, the open-orders list on a refresh (its size
// matched grew), or an order that left the list whose record shows a fill.
// The user channel follows the tokens with a resting order, not only the
// tokens held. Fakes only: nothing is read from the venue.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_resting_fills_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_user_channel_provider.dart';
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketOrderWsMessage;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Order, Position;

Order _order(String id,
        {String side = 'BUY',
        double size = 10,
        double matched = 0,
        String token = 'tok'}) =>
    Order(
      id: id,
      market: 'm',
      assetId: token,
      owner: 'x',
      side: side,
      price: '0.40',
      originalSize: '$size',
      sizeMatched: '$matched',
      outcome: 'Yes',
    );

PolymarketOrderWsMessage _update(String id, double matched,
        {double size = 10}) =>
    PolymarketOrderWsMessage(
      assetId: 'tok',
      market: 'm',
      timestamp: 0,
      orderId: id,
      action: 'UPDATE',
      side: 'BUY',
      price: 0.4,
      originalSize: size,
      sizeMatched: matched,
      outcome: 'Yes',
    );

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      isAuthenticated: true, proxyWalletAddress: '0xabc');

  void orders(List<Order> orders, {bool known = true}) =>
      state = AsyncData(state.requireValue
          .copyWith(openOrders: orders, openOrdersKnown: known));
}

class _Channel extends UserChannelNotifier {
  @override
  UserChannelState build() => const UserChannelState();
  void push(PolymarketOrderWsMessage m) => state = UserChannelState(
      recentOrders: [...state.recentOrders, m],
      recentTrades: state.recentTrades);
}

void main() {
  group('the tracker', () {
    test('the first list primes; a size matched that grew is a fill', () {
      final t = PolymarketRestingFillTracker();
      expect(t.onOrders([_order('a', matched: 2)]).fills, isEmpty);
      final seen = t.onOrders([_order('a', matched: 6)]);
      expect(seen.fills, hasLength(1));
      final fill = seen.fills.single;
      expect(fill.filledShares, closeTo(4, 1e-9));
      expect(fill.matchedShares, 6);
      expect(fill.complete, isFalse);
      expect(fill.remainingShares, 4);
      // The same list again says nothing.
      expect(t.onOrders([_order('a', matched: 6)]).fills, isEmpty);
    });

    test('the socket and the list never say the same fill twice', () {
      final t = PolymarketRestingFillTracker()..onOrders([_order('a')]);
      final socket = t.onOrderMessage(_update('a', 10));
      expect(socket?.complete, isTrue);
      // The list catches up (the order left it: all filled), and the
      // order's record shows the fill the socket already said.
      final seen = t.onOrders(const []);
      expect(seen.fills, isEmpty);
      expect(seen.gone.single.id, 'a');
      expect(t.onGone(seen.gone.single, {'size_matched': '10'}), isNull);
      // An order not resting here is not ours to say.
      expect(t.onOrderMessage(_update('other', 3)), isNull);
    });

    test('an order that left the list: its record decides', () {
      final t = PolymarketRestingFillTracker()
        ..onOrders([_order('filled'), _order('cancelled'), _order('mine')]);
      t.noteCancelled(['mine']);
      final seen = t.onOrders(const []);
      // Cancelled here: not read at all.
      expect(seen.gone.map((o) => o.id), ['filled', 'cancelled']);
      final filled = t.onGone(seen.gone[0], {'size_matched': '10'});
      expect(filled?.complete, isTrue);
      expect(filled?.filledShares, 10);
      // Cancelled elsewhere (or the market ended) with nothing matched.
      expect(t.onGone(seen.gone[1], {'size_matched': '0'}), isNull);
      expect(t.onGone(seen.gone[1], null), isNull);
    });
  });

  group('the provider', () {
    late ProviderContainer container;
    late _Trading trading;
    late _Channel channel;
    final fills = <PolymarketRestingFill>[];

    setUp(() async {
      fills.clear();
      trading = _Trading();
      channel = _Channel();
      PolymarketRestingFillsNotifier.lookup =
          (ref, id) async => {'size_matched': id == 'b' ? '4' : '10'};
      container = ProviderContainer(overrides: [
        polymarketTradingProvider.overrideWith(() => trading),
        userChannelProvider.overrideWith(() => channel),
      ]);
      await container.read(polymarketTradingProvider.future);
      container.listen<PolymarketRestingFill?>(polymarketRestingFillsProvider,
          (_, fill) {
        if (fill != null) fills.add(fill);
      }, fireImmediately: true);
    });
    tearDown(() => container.dispose());

    test('a resting buy that fills while the app is open is said once',
        () async {
      trading.orders([_order('a'), _order('b', side: 'SELL', size: 4)]);
      // Part of it on the socket, the rest on the next list.
      channel.push(_update('a', 3));
      expect(fills.single.filledShares, 3);
      trading.orders([_order('a', matched: 7), _order('b', side: 'SELL', size: 4)]);
      expect(fills, hasLength(2));
      expect(fills.last.filledShares, closeTo(4, 1e-9));
      // The sell filled whole: it left the list, its record says so.
      trading.orders([_order('a', matched: 7)]);
      await Future<void>.delayed(Duration.zero);
      expect(fills, hasLength(3));
      expect(fills.last.isBuy, isFalse);
      expect(fills.last.complete, isTrue);
      expect(fills.last.filledShares, 4);
    });

    test('a failed orders read says nothing and forgets nothing', () async {
      trading.orders([_order('a')]);
      trading.orders(const [], known: false);
      await Future<void>.delayed(Duration.zero);
      expect(fills, isEmpty);
      trading.orders([_order('a', matched: 5)]);
      expect(fills.single.filledShares, 5);
    });
  });

  test('the user channel follows resting orders\' tokens too', () {
    final state = PolymarketTradingState(
      openPositions: [
        const Position(
          proxyWallet: '0x',
          asset: 'held',
          conditionId: 'c',
          size: 1,
          avgPrice: 0.5,
          initialValue: 0.5,
          currentValue: 0.5,
          cashPnl: 0,
          percentPnl: 0,
          totalBought: 0.5,
          realizedPnl: 0,
          percentRealizedPnl: 0,
          curPrice: 0.5,
          redeemable: false,
          mergeable: false,
          title: 't',
          slug: 's',
          eventSlug: 'e',
          outcome: 'Yes',
          outcomeIndex: 0,
          oppositeOutcome: 'No',
          oppositeAsset: 'o',
          negativeRisk: false,
        ),
      ],
      openOrders: [_order('a', token: 'resting'), _order('b', token: 'held')],
    );
    expect(polymarketUserChannelAssets(state), ['held', 'resting']);
  });
}
