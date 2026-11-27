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
          .noteOrder(_order('new'), account: '0xabc');
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

    test(
        'a list read before the placement misses the order: its LIVE record '
        'keeps it tracked, and a part fill on the next list is said',
        () async {
      final reads = <String>[];
      PolymarketRestingFillsNotifier.lookup = (ref, id) async {
        reads.add(id);
        return {'status': 'LIVE', 'size_matched': '0', 'original_size': '10'};
      };
      container
          .read(polymarketRestingFillsProvider.notifier)
          .noteOrder(_order('new'), account: '0xabc');
      // The stale list (read before the order was placed) lands.
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(reads, ['new']);
      expect(fills, isEmpty);
      // The next list carries it, part filled: said, counted from the
      // registered shares.
      trading.orders([_order('new', matched: 4)]);
      expect(fills.single.orderId, 'new');
      expect(fills.single.filledShares, 4);
    });

    test('one record read at a time per order, however many lists land',
        () async {
      final pending = Completer<Map<String, dynamic>?>();
      var calls = 0;
      PolymarketRestingFillsNotifier.lookup = (ref, id) {
        calls++;
        return pending.future;
      };
      trading.orders([_order('a')]);
      trading.orders(const []);
      trading.orders([_order('z')]);
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2); // 'a' once, 'z' once
      pending.complete({'size_matched': '10'});
      await Future<void>.delayed(Duration.zero);
      expect(fills.map((f) => f.orderId).toSet(), {'a', 'z'});
    });

    test('an order placed on another account is never tracked here',
        () async {
      container
          .read(polymarketRestingFillsProvider.notifier)
          .noteOrder(_order('elsewhere'), account: '0xdef');
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills, isEmpty);
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

  group('the re-check timer (fake time)', () {
    late _Trading trading;
    late ProviderContainer container;
    late List<String> reads;

    late DateTime fakeNow;

    /// Fake time for the timers and the tracker's clock together.
    Future<void> advance(WidgetTester tester, Duration d) async {
      fakeNow = fakeNow.add(d);
      await tester.pump(d);
    }

    Future<void> start(WidgetTester tester) async {
      fakeNow = DateTime(2026, 11, 27, 12);
      PolymarketRestingFillsNotifier.clock = () => fakeNow;
      trading = _Trading();
      reads = [];
      container = ProviderContainer(overrides: [
        polymarketTradingProvider.overrideWith(() => trading),
        userChannelProvider.overrideWith(_Channel.new),
      ]);
      await tester.runAsync(
          () => container.read(polymarketTradingProvider.future));
      container.listen(polymarketRestingFillsProvider, (_, __) {});
    }

    tearDown(() {
      PolymarketRestingFillsNotifier.clock = DateTime.now;
    });

    testWidgets(
        'arms on a registration, fires, stops with nothing tracked',
        (tester) async {
      await start(tester);
      var answer = <String, dynamic>{
        'status': 'LIVE',
        'size_matched': '0',
        'original_size': '10'
      };
      PolymarketRestingFillsNotifier.lookup = (ref, id) async {
        reads.add(id);
        return answer;
      };
      container
          .read(polymarketRestingFillsProvider.notifier)
          .noteOrder(_order('new'), account: '0xabc');
      // No list carried it yet: the timer reads it.
      await advance(tester, const Duration(seconds: 30));
      expect(reads, ['new']);
      // LIVE: read again on a later tick (after its 20 s), not before.
      await advance(tester, const Duration(seconds: 30));
      expect(reads, ['new', 'new']);
      // Ended: let go, and the timer stops by itself.
      answer = {'status': 'MATCHED', 'size_matched': '10'};
      await advance(tester, const Duration(seconds: 30));
      expect(reads, ['new', 'new', 'new']);
      await advance(tester, const Duration(seconds: 30));
      await advance(tester, const Duration(seconds: 90));
      expect(reads, hasLength(3));
      container.dispose();
    });

    testWidgets('stops on another account', (tester) async {
      await start(tester);
      PolymarketRestingFillsNotifier.lookup = (ref, id) async {
        reads.add(id);
        return {'status': 'LIVE', 'size_matched': '0', 'original_size': '10'};
      };
      container
          .read(polymarketRestingFillsProvider.notifier)
          .noteOrder(_order('new'), account: '0xabc');
      trading.account('0xother');
      await advance(tester, const Duration(minutes: 3));
      expect(reads, isEmpty);
      container.dispose();
    });

    for (final ending in ['throws', 'LIVE'])
      testWidgets(
          'disposed with a read in flight ($ending): no timer and no read '
          'after it', (tester) async {
        await start(tester);
        final pending = Completer<Map<String, dynamic>?>();
        PolymarketRestingFillsNotifier.lookup = (ref, id) {
          reads.add(id);
          return pending.future;
        };
        trading.orders([_order('a')]);
        trading.orders(const []);
        await tester.pump();
        expect(reads, ['a']);
        container.dispose();
        if (ending == 'throws') {
          pending.completeError(StateError('offline'));
        } else {
          pending.complete(
              {'status': 'LIVE', 'size_matched': '0', 'original_size': '10'});
        }
        await tester.pump();
        await advance(tester, const Duration(minutes: 5));
        expect(reads, ['a']);
        // The test framework fails on any timer still pending here.
      });
  });

  group('registering a placed order (buy and sell share one path)', () {
    late _Trading trading;
    late ProviderContainer container;
    final fills = <PolymarketRestingFill>[];

    setUp(() async {
      fills.clear();
      trading = _Trading();
      container = ProviderContainer(overrides: [
        polymarketTradingProvider.overrideWith(() => trading),
        userChannelProvider.overrideWith(_Channel.new),
      ]);
      await container.read(polymarketTradingProvider.future);
      container.listen<PolymarketRestingFill?>(polymarketRestingFillsProvider,
          (_, f) {
        if (f != null) fills.add(f);
      });
      PolymarketRestingFillsNotifier.lookup =
          (ref, id) async => {'status': 'MATCHED', 'size_matched': '10'};
    });
    tearDown(() => container.dispose());

    void note({required String? account, double matched = 0}) =>
        polymarketNoteRestingOrder(
          tracking: container.exists(polymarketRestingFillsProvider),
          tracker: () => container.read(polymarketRestingFillsProvider.notifier),
          placed: {'orderID': 'p1'},
          account: account,
          tokenId: 'tok',
          isBuy: false,
          price: 0.7,
          shares: 10,
          matched: matched,
          outcome: 'Yes',
        );

    test('counted from what the receipt stated: only shares beyond it',
        () async {
      note(account: '0xABC', matched: 4);
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills.single.filledShares, 6);
      expect(fills.single.isBuy, isFalse);
    });

    test('placed on another account: dropped', () async {
      note(account: '0xdef');
      trading.orders(const []);
      await Future<void>.delayed(Duration.zero);
      expect(fills, isEmpty);
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
