// Left-over protective orders after a full close, at the provider level:
// the real HyperliquidTradingNotifier with a MockClient-backed exchange
// (only build() is replaced, to seed the account).
//
//   * a limit close sized to the whole position arms the sweep; nothing is
//     cancelled when it is accepted, and once a snapshot shows the
//     position gone exactly the coin's reduce-only triggers are cancelled
//     (never the entry limit, never another coin's stop);
//   * a partial close arms nothing: the position gone later (closed
//     elsewhere) cancels nothing;
//   * a mixed cancel answer (one order already gone) is success for the
//     gone one: the one cancelled is counted, both leave local state, the
//     receipt's "still open" is zero;
//   * the replace-stop sequence the close sheet runs: the new stop is
//     placed first and the old one cancelled after it is accepted; a
//     rejected new stop throws before any cancel;
//   * the position is read fresh right before the cancel: the coin open
//     again (another device, a queued order) or a read that fails cancels
//     nothing and disarms; an order placed after the close was armed is
//     never its left-over;
//   * a wallet switch while the sweep runs sends nothing to either
//     account.
//
// Cancel answers are the venue's documented shapes (Hyperliquid docs,
// Exchange endpoint, "Cancel order(s)"): statuses ["success"], and
// {"error": "Order was never placed, already canceled, or filled."}.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

import '../helpers/runtime_policy_fixture.dart';

const _gone = 'Order was never placed, already canceled, or filled.';
const _walletId = 'w1';

HlMarket _perp(String coin, int assetId) => HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: assetId,
      kind: HlMarketKind.perp,
      szDecimals: 5,
      maxLeverage: 40,
      onlyIsolated: false,
      markPx: 66000,
      midPx: 66000,
      prevDayPx: 65000,
      dayNtlVlm: 1e9,
    );

final _btc = _perp('BTC', 0);
final _eth = _perp('ETH', 1);

HlPerpPosition _long(String coin, double szi) => HlPerpPosition(
      coin: coin,
      szi: szi,
      entryPx: 60000,
      positionValue: szi * 66000,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: szi * 66000,
      leverageType: 'isolated',
      leverageValue: 1,
      maxLeverage: 40,
    );

HlOpenOrder _order(int oid, String coin,
        {required bool trigger, required bool reduceOnly, String? tpsl}) =>
    HlOpenOrder(
      coin: coin,
      oid: oid,
      isBuy: false,
      limitPx: 60000,
      sz: 0.5,
      origSz: 0.5,
      timestamp: 1000 - oid,
      cloid: null,
      reduceOnly: reduceOnly,
      orderType: trigger
          ? (tpsl == 'tp' ? 'Take Profit Market' : 'Stop Market')
          : 'Limit',
      isTrigger: trigger,
      triggerPx: trigger ? 60000 : null,
    );

final _stop = _order(31, 'BTC', trigger: true, reduceOnly: true, tpsl: 'sl');
final _take = _order(32, 'BTC', trigger: true, reduceOnly: true, tpsl: 'tp');
final _entry = _order(40, 'BTC', trigger: false, reduceOnly: false);
final _ethStop = _order(50, 'ETH', trigger: true, reduceOnly: true, tpsl: 'sl');

/// The account poll, quiet: snapshots are delivered by the test.
class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot.empty;
}

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.seed);
  final HyperliquidTradingState seed;
  @override
  Future<HyperliquidTradingState> build() async => seed;
}

/// The venue as the test answers it: every posted action recorded; an
/// order rests (or is rejected); each cancel answers per order from
/// [cancelAnswer] and takes what it cancelled off [book]. Reads: the
/// open orders are [book] (after [ordersGate], when set), the position
/// read fresh is [positions] (or fails with [failPositionRead]).
class _Venue {
  _Venue({List<HlOpenOrder>? book, this.keyHex = _keyA})
      : book = [...?book];
  final String keyHex;
  final actions = <Map<String, dynamic>>[];
  bool rejectOrders = false;
  Object Function(int oid) cancelAnswer = (_) => 'success';
  List<HlOpenOrder> book;
  List<HlPerpPosition> positions = const [];
  bool failPositionRead = false;
  Completer<void>? ordersGate;
  final positionReads = <String>[];

  HyperliquidModel model() => _Model(this);

  List<List<int>> get cancels => [
        for (final a in actions)
          if (a['type'] == 'cancel')
            [for (final c in a['cancels'] as List) (c as Map)['o'] as int],
      ];

  int get orders => actions.where((a) => a['type'] == 'order').length;

  HyperliquidExchangeService exchange() {
    final key = EthPrivateKey.fromHex(keyHex);
    return HyperliquidExchangeService(
      credentials: key,
      walletAddress: key.address.hexEip55,
      httpClient: MockClient((request) async {
        final action = (jsonDecode(request.body)
            as Map<String, dynamic>)['action'] as Map<String, dynamic>;
        actions.add(action);
        if (action['type'] == 'cancel') {
          final gone = {
            for (final c in action['cancels'] as List)
              if (cancelAnswer((c as Map)['o'] as int) == 'success')
                c['o'] as int,
          };
          book = [
            for (final o in book)
              if (!gone.contains(o.oid)) o
          ];
          return http.Response(
              jsonEncode({
                'status': 'ok',
                'response': {
                  'type': 'cancel',
                  'data': {
                    'statuses': [
                      for (final c in action['cancels'] as List)
                        cancelAnswer((c as Map)['o'] as int),
                    ]
                  }
                }
              }),
              200);
        }
        return http.Response(
            jsonEncode({
              'status': 'ok',
              'response': {
                'type': 'order',
                'data': {
                  'statuses': [
                    rejectOrders
                        ? {'error': 'Order has invalid price.'}
                        : {
                            'resting': {'oid': 77}
                          }
                  ]
                }
              }
            }),
            200);
      }),
    );
  }
}

const _keyA =
    '0x0123456789012345678901234567890101234567890123456789012345678901';
const _keyB =
    '0x0223456789012345678901234567890101234567890123456789012345678902';

/// The venue's info reads ([_Venue]): open orders, fills, and the
/// position on one dex.
class _Model extends HyperliquidModel {
  _Model(this.venue);
  final _Venue venue;

  @override
  Future<List<HlOpenOrder>> getOpenOrders(String address,
      {Iterable<String> dexes = const []}) async {
    final gate = venue.ordersGate;
    if (gate != null) await gate.future;
    return List.of(venue.book);
  }

  @override
  Future<List<HlFill>> getUserFills(String address) async => const [];

  @override
  Future<HlAccountSnapshot> getDexClearinghouse(
      String address, String dex) async {
    venue.positionReads.add(dex);
    if (venue.failPositionRead) throw http.ClientException('info failed');
    return HlAccountSnapshot(
        accountValue: 100,
        withdrawable: 100,
        totalMarginUsed: 0,
        positions: venue.positions,
        spotBalances: const [],
        positionDexes: {dex});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RuntimeCapabilitiesService policy;

  setUp(() async {
    AffiliateService.debugSessionToken = 'test-session';
    policy = runtimePolicyFixture(also: const {'hyperliquid.cancel'});
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    policy.dispose();
  });

  Future<(ProviderContainer, _Trading, _Venue)> setup({
    List<HlPerpPosition>? positions,
    List<HlOpenOrder>? orders,
  }) async {
    final venue =
        _Venue(book: orders ?? [_stop, _take, _entry, _ethStop]);
    final container = ProviderContainer(overrides: [
      hyperliquidTradingModelProvider.overrideWithValue(venue.model()),
      hyperliquidTradingProvider.overrideWith(() => _Trading(
          HyperliquidTradingState(
              isInitialized: true,
              withdrawable: 100,
              positions: positions ?? [_long('BTC', 0.5)],
              openOrders: orders ?? [_stop, _take, _entry, _ethStop]))),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      hyperliquidWireMarketProvider.overrideWith((ref, wire) =>
          wire == 'BTC' ? _btc : (wire == 'ETH' ? _eth : null)),
    ]);
    addTearDown(container.dispose);
    container.listen(hyperliquidTradingProvider, (_, __) {});
    await container.read(hyperliquidTradingProvider.future);
    final notifier = container.read(hyperliquidTradingProvider.notifier);
    notifier.debugAttachExchange(venue.exchange(), walletId: _walletId);
    return (container, notifier as _Trading, venue);
  }

  AuthGrant limitGrant(double size) => AuthGrants.issue(
      HlIntents.limit(
        walletId: _walletId,
        market: _btc,
        isLong: false,
        size: size,
        px: 70000,
        tif: 'Gtc',
        postOnly: false,
        reduceOnly: true,
      ),
      method: AuthGrantMethod.pin);

  Future<HlOrderResult> limitClose(_Trading t, double size) => t.placeLimit(
        market: _btc,
        isLong: false,
        size: size,
        px: 70000,
        tif: 'Gtc',
        postOnly: false,
        reduceOnly: true,
        source: 'close_position',
        grant: limitGrant(size),
      );

  HlAccountSnapshot snapshot(List<HlPerpPosition> positions) =>
      HlAccountSnapshot(
          accountValue: 100,
          withdrawable: 100,
          totalMarginUsed: 0,
          positions: positions,
          spotBalances: const []);

  List<int> openOids(ProviderContainer c) => [
        for (final o in c.read(hyperliquidTradingProvider).value!.openOrders)
          o.oid
      ];

  test(
      'a full limit close: nothing cancelled on acceptance; once the '
      'position is gone exactly its reduce-only triggers are cancelled',
      () async {
    final (c, t, venue) = await setup();
    final result = await limitClose(t, 0.5);
    expect(result.kind, HlOrderResultKind.resting);
    await pumpEventQueue();
    // Accepted, resting: the position is still open, nothing cancelled.
    expect(venue.cancels, isEmpty);
    t.debugApplySnapshot(snapshot([_long('BTC', 0.5)]));
    await pumpEventQueue();
    expect(venue.cancels, isEmpty);

    // Filled: the snapshot shows no BTC position.
    t.debugApplySnapshot(snapshot(const []));
    final sweep = t.leftoverSweepFor('BTC');
    expect(sweep, isNotNull);
    expect(await sweep, (cancelled: 2, failed: 0));
    expect(venue.cancels, [
      [31, 32]
    ]);
    // The entry limit and the other coin's stop stay.
    expect(openOids(c), unorderedEquals([40, 50]));

    // Once: a later snapshot does not cancel again.
    t.debugApplySnapshot(snapshot(const []));
    await pumpEventQueue();
    expect(venue.cancels, hasLength(1));
  });

  test('a partial close cancels nothing, even when the position is closed '
      'elsewhere later', () async {
    final (c, t, venue) = await setup();
    await limitClose(t, 0.25);
    t.debugApplySnapshot(snapshot([_long('BTC', 0.25)]));
    t.debugApplySnapshot(snapshot(const []));
    await pumpEventQueue();
    expect(t.leftoverSweepFor('BTC'), isNull);
    expect(venue.cancels, isEmpty);
    expect(openOids(c), unorderedEquals([31, 32, 40, 50]));
  });

  test('a position this app never closed going to zero cancels nothing',
      () async {
    final (c, t, venue) = await setup();
    t.debugApplySnapshot(snapshot(const []));
    await pumpEventQueue();
    expect(venue.cancels, isEmpty);
    expect(openOids(c), hasLength(4));
  });

  test('a full close whose limit the user cancels is disarmed', () async {
    final (c, t, venue) = await setup(
        orders: [_stop, _take, _entry, _ethStop]);
    await limitClose(t, 0.5);
    await t.cancelOrder(assetId: 0, oid: 77, coin: 'BTC');
    t.debugApplySnapshot(snapshot(const []));
    await pumpEventQueue();
    expect(venue.cancels, [
      [77]
    ]);
    expect(openOids(c), unorderedEquals([31, 32, 40, 50]));
  });

  test(
      'a mixed cancel answer: the order already gone is done, not a '
      'failure; both leave local state', () async {
    final (c, t, venue) = await setup();
    venue.cancelAnswer = (oid) => oid == 32 ? {'error': _gone} : 'success';
    await limitClose(t, 0.5);
    t.debugApplySnapshot(snapshot(const []));
    expect(await t.leftoverSweepFor('BTC'), (cancelled: 1, failed: 0));
    expect(openOids(c), unorderedEquals([40, 50]));
  });

  test('a cancel the venue truly refuses is reported still open and stays '
      'listed; what it cancelled is pruned', () async {
    final (c, t, venue) = await setup();
    venue.cancelAnswer =
        (oid) => oid == 32 ? {'error': 'Rate limited.'} : 'success';
    await expectLater(
        t.cancelOrdersList([_stop, _take]),
        throwsA(isA<HlCancelPartialException>()
            .having((e) => e.cancelled, 'cancelled', 1)
            .having((e) => e.stillOpen, 'stillOpen', 1)));
    expect(openOids(c), unorderedEquals([32, 40, 50]));
  });

  group('replace a stop (the close sheet\'s order of calls)', () {
    AuthGrant triggerGrant() => AuthGrants.issue(
        HlIntents.trigger(
          walletId: _walletId,
          market: _btc,
          isLong: false,
          size: 0.5,
          triggerPx: 61000,
          isMarket: true,
          tpsl: 'sl',
          reduceOnly: true,
        ),
        method: AuthGrantMethod.pin);

    Future<void> replace(_Trading t) async {
      await t.placeTrigger(
        market: _btc,
        isLong: false,
        size: 0.5,
        triggerPx: 61000,
        isMarket: true,
        tpsl: 'sl',
        reduceOnly: true,
        source: 'close_position',
        grant: triggerGrant(),
      );
      await t.cancelOrdersList([_stop], reason: 'replace_stop');
    }

    test('the old stop is cancelled only after the new one is accepted; '
        'one already gone is a success', () async {
      final (c, t, venue) = await setup();
      venue.cancelAnswer = (_) => {'error': _gone};
      await replace(t);
      expect([for (final a in venue.actions) a['type']], ['order', 'cancel']);
      expect(venue.cancels, [
        [31]
      ]);
      expect(openOids(c), isNot(contains(31)));
    });

    test('a rejected new stop cancels nothing', () async {
      final (_, t, venue) = await setup();
      venue.rejectOrders = true;
      await expectLater(replace(t), throwsA(anything));
      expect(venue.orders, 1);
      expect(venue.cancels, isEmpty);
    });
  });

  group('the position read fresh before the cancel', () {
    final newStop =
        _order(61, 'BTC', trigger: true, reduceOnly: true, tpsl: 'sl');
    final newTake =
        _order(62, 'BTC', trigger: true, reduceOnly: true, tpsl: 'tp');

    test(
        'the coin opened again (with its own TP/SL) before the cancel: '
        'nothing cancelled, and the close is disarmed', () async {
      final (c, t, venue) = await setup();
      await limitClose(t, 0.5);
      // Filled, then reopened elsewhere with a new stop and take before
      // the sweep's reads: the book holds both pairs, the venue's
      // position is open again while the snapshot still says flat.
      venue.book = [newStop, newTake, ...venue.book];
      venue.positions = [_long('BTC', 0.3)];
      t.debugApplySnapshot(snapshot(const []));
      expect(await t.leftoverSweepFor('BTC'), (cancelled: 0, failed: 0));
      expect(venue.positionReads, ['']);
      expect(venue.cancels, isEmpty);
      // Disarmed: a later flat snapshot starts nothing.
      venue.positions = const [];
      t.debugApplySnapshot(snapshot(const []));
      await pumpEventQueue();
      expect(venue.cancels, isEmpty);
      expect(openOids(c), containsAll([31, 32, 61, 62]));
    });

    test('the fresh read fails: nothing cancelled', () async {
      final (c, t, venue) = await setup();
      venue.failPositionRead = true;
      await limitClose(t, 0.5);
      t.debugApplySnapshot(snapshot(const []));
      expect(await t.leftoverSweepFor('BTC'), (cancelled: 0, failed: 0));
      expect(venue.cancels, isEmpty);
      expect(openOids(c), containsAll([31, 32]));
      // Disarmed: the next flat snapshot does not retry.
      venue.failPositionRead = false;
      t.debugApplySnapshot(snapshot(const []));
      await pumpEventQueue();
      expect(venue.cancels, isEmpty);
    });

    test(
        'an order placed after the close was armed is never cancelled, '
        'even with the position gone', () async {
      final (c, t, venue) = await setup();
      await limitClose(t, 0.5);
      // A stop placed after the close (another device): on the book.
      venue.book = [newStop, ...venue.book];
      t.debugApplySnapshot(snapshot(const []));
      expect(await t.leftoverSweepFor('BTC'), (cancelled: 2, failed: 0));
      expect(venue.cancels, [
        [31, 32]
      ]);
      expect(openOids(c), contains(61));
    });

    test('only orders placed after it: nothing to cancel', () async {
      final (c, t, venue) = await setup(orders: [_entry, _ethStop]);
      await limitClose(t, 0.5);
      venue.book = [newStop, newTake, ...venue.book];
      t.debugApplySnapshot(snapshot(const []));
      expect(await t.leftoverSweepFor('BTC'), (cancelled: 0, failed: 0));
      expect(venue.cancels, isEmpty);
      expect(openOids(c), containsAll([61, 62]));
    });
  });

  test(
      'a wallet switch while the sweep runs: nothing is sent to either '
      'account', () async {
    final (_, t, venue) = await setup();
    await limitClose(t, 0.5);
    final gate = Completer<void>();
    venue.ordersGate = gate;
    t.debugApplySnapshot(snapshot(const []));
    final sweep = t.leftoverSweepFor('BTC')!;
    await pumpEventQueue();
    // Another wallet loads while the orders read is out; its own book
    // holds a BTC stop.
    final other = _Venue(book: [_stop, _take], keyHex: _keyB);
    t.debugAttachExchange(other.exchange(), walletId: 'w2');
    gate.complete();
    expect(await sweep, (cancelled: 0, failed: 0));
    expect(venue.cancels, isEmpty);
    expect(other.cancels, isEmpty);
    expect(venue.positionReads, isEmpty);
  });

  test('every hot close path reaches the one sweep', () {
    final source = File('lib/providers/hyperliquid_trading_provider.dart')
        .readAsStringSync();
    String body(String signature) {
      final start = source.indexOf(signature);
      expect(start, isNonNegative, reason: signature);
      final next = source.indexOf(RegExp(r'\n  Future<'), start + 1);
      return source.substring(start, next < 0 ? source.length : next);
    }

    expect(body('Future<HlOrderResult> closePosition('),
        contains('_dropClosedInFull(pos,'));
    expect(body('void _dropClosedInFull('), contains('_startLeftoverSweep('));
    expect(body('Future<HlOrderResult> placeLimit('), contains('_armFullClose('));
    expect(body('Future<HlOrderResult> placeTwap('), contains('_armFullClose('));
  });
}
