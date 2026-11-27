// P6: a resting limit order that fills is said once (the Sal toast,
// polymarket_screen.dart), whichever way the fill is seen first: the user
// channel's order update, the open-orders list on a refresh (its size
// matched grew), or an order that left the list whose record shows a fill.
// The user channel follows the tokens with a resting order, not only the
// tokens held. Fakes only: nothing is read from the venue.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart'
    show showPolymarketRestingFillToast;
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/providers/polymarket_resting_fills_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/polymarket_user_channel_provider.dart';
import 'package:kute/services/polymarket_clob_websocket.dart'
    show PolymarketClobWebSocket, PolymarketOrderWsMessage, PolymarketWsMessage;
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

  void orders(List<Order> orders) =>
      state = AsyncData(state.requireValue.copyWith(openOrders: orders));

  void account(String proxy) => state = AsyncData(PolymarketTradingState(
      isAuthenticated: true, proxyWalletAddress: proxy));
}

/// The user-channel socket, faked: what was subscribed, and a stream the
/// test pushes order updates down.
class _Socket extends PolymarketClobWebSocket {
  final subscribed = <List<String>>[];
  int listeners = 0;
  late final _out = StreamController<PolymarketWsMessage>.broadcast(
      onListen: () => listeners++, onCancel: () => listeners--);

  @override
  Future<void> connect() async {}
  @override
  Stream<PolymarketWsMessage> get messages => _out.stream;
  @override
  void subscribeToUser({
    required List<String> assetIds,
    required Map<String, String> Function() authHeadersFactory,
  }) =>
      subscribed.add(assetIds);
  @override
  void dispose() {}
  void push(PolymarketWsMessage m) => _out.add(m);
}

class _Backend extends Fake implements PolymarketBackendService {
  @override
  Map<String, String> userChannelAuthHeaders() => const {};
}

class _AuthedTrading extends _Trading {
  @override
  PolymarketBackendService? get backendService => _Backend();
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

    test(
        'the socket silent across a resubscribe: the next list says the fill '
        '(the list backs the socket up)', () async {
      trading.orders([_order('a')]);
      // No socket update at all; the refresh's list shows the fill.
      trading.orders([_order('a', matched: 5)]);
      expect(fills.single.filledShares, 5);
    });

    test(
        'an order placed here that fills whole before the next list is '
        'still said (registered at placement)', () async {
      container
          .read(polymarketRestingFillsProvider.notifier)
          .noteOrder(_order('new'));
      // The first list read after it: already gone (filled), never listed.
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills.single.orderId, 'new');
      expect(fills.single.complete, isTrue);
    });

    test(
        'a cancel that failed marks nothing: a fill after it is said; a '
        'confirmed cancel is never a fill', () async {
      trading.orders([_order('kept'), _order('gone')]);
      // Only the confirmed cancel is noted (open_orders_sheet.dart).
      container
          .read(polymarketRestingFillsProvider.notifier)
          .noteCancelled(['gone']);
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills.map((f) => f.orderId), ['kept']);
    });

    test('a record that could not be read is read again with the next list',
        () async {
      var tries = 0;
      PolymarketRestingFillsNotifier.lookup = (ref, id) async {
        if (tries++ == 0) throw StateError('offline');
        return {'size_matched': '10'};
      };
      trading.orders([_order('a')]);
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills, isEmpty);
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills.single.orderId, 'a');
      expect(tries, 2);
    });

    test('another account: nothing of the last one is said', () async {
      trading.orders([_order('a')]);
      trading.account('0xother');
      trading.orders([_order('a', matched: 8)]);
      await Future<void>.delayed(Duration.zero);
      expect(fills, isEmpty);
    });
  });

  group('the user channel', () {
    late _Socket socket;
    late ProviderContainer container;

    setUp(() async {
      socket = _Socket();
      UserChannelNotifier.socketFactory = () => socket;
      container = ProviderContainer(overrides: [
        polymarketTradingProvider.overrideWith(_AuthedTrading.new),
      ]);
      container.listen(userChannelProvider, (_, __) {});
      await container.read(polymarketTradingProvider.future);
    });
    tearDown(() {
      container.dispose();
      UserChannelNotifier.socketFactory = PolymarketClobWebSocket.new;
    });

    test(
        'resting orders\' tokens are added to the open subscription: no '
        'teardown, an update right after is heard', () async {
      final channel = container.read(userChannelProvider.notifier);
      channel.subscribe(['held']);
      await Future<void>.delayed(Duration.zero);
      expect(socket.subscribed, [
        ['held']
      ]);
      expect(socket.listeners, 1);
      channel.follow(['resting', 'held']);
      // One more `user` frame with the new token only; the stream stays.
      expect(socket.subscribed.last, ['resting']);
      expect(socket.listeners, 1);
      socket.push(_update('o1', 2));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(userChannelProvider).recentOrders, hasLength(1));
      // Already followed: nothing sent again.
      channel.follow(['resting']);
      expect(socket.subscribed, hasLength(2));
    });

    test('an account with no positions: its resting orders open the channel',
        () async {
      container.read(userChannelProvider.notifier).follow(['resting']);
      await Future<void>.delayed(Duration.zero);
      expect(socket.subscribed.single, ['resting']);
      expect(socket.listeners, 1);
    });
  });

  testWidgets('a fill is said with the Sal toast', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
            theme: ThemeData(extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: (c) {
              ctx = c;
              return const Scaffold();
            }))));
    showPolymarketRestingFillToast(
        ctx,
        const PolymarketRestingFill(
            orderId: 'a',
            tokenId: 't',
            isBuy: true,
            price: 0.4,
            outcome: 'Yes',
            filledShares: 10,
            matchedShares: 10,
            originalShares: 10));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SalToast), findsOneWidget);
    expect(find.text('Limit order filled'), findsOneWidget);
    expect(find.text('Bought 10.00 shares of Yes at 40%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('the tokens with a resting order, held or not', () {
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
    expect(polymarketRestingOrderAssets(state), ['resting', 'held']);
  });
}
