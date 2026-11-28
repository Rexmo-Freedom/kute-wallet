// LEVERAGE IS BLOCKED IN THIS APP: on a market whose position is held
// above 1x or in cross (opened elsewhere), nothing the app sends adds to it
// or flips it; only a reduction goes, reduce-only. And a position that is
// not positively known is never taken for "no position".
//
// The one rule (hl_exposure_rule.dart) as a function, then the real order
// notifier driven against a fake venue (an exchange whose POSTs are
// captured, a model whose reads are counted): what reaches the exchange
// door (the leverage write, the order's reduce-only flag, any funding), and
// that a plain market buy on a flat, loaded account makes exactly the calls
// it always made. Nothing here touches a real account.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/services/hyperliquid/hl_exposure_rule.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

const _xyz = HlMarket(
  coin: 'xyz:TSLA',
  wireCoin: 'xyz:TSLA',
  assetId: 110000,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 10,
  onlyIsolated: true,
  markPx: 300,
  midPx: 300,
  prevDayPx: 300,
  dayNtlVlm: 0,
  dex: 'xyz',
);

const _spot = HlMarket(
  coin: 'HYPE',
  wireCoin: '@107',
  assetId: 10107,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 40,
  midPx: 40,
  prevDayPx: 40,
  dayNtlVlm: 0,
);

/// A BTC position of [usd] notional at 60,000 (negative [usd]: a short).
HlPerpPosition held(double usd,
        {int leverage = 10, bool cross = false, String coin = 'BTC'}) =>
    HlPerpPosition(
      coin: coin,
      szi: usd / 60000,
      entryPx: 60000,
      positionValue: usd.abs(),
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: usd.abs() / leverage,
      leverageType: cross ? 'cross' : 'isolated',
      leverageValue: leverage,
      maxLeverage: 40,
    );

/// A flat main-dex account read [age] ago.
HlAccountSnapshot _flatReadAgo(Duration age) => HlAccountSnapshot(
      accountValue: 0,
      withdrawable: 5000,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
      positionsReadAt: {'': DateTime.now().subtract(age)},
    );

/// A resting BUY limit on BTC at 59,000, placed while the market was flat.
const _restingBuy = HlOpenOrder(
  coin: 'BTC',
  oid: 41,
  isBuy: true,
  limitPx: 59000,
  sz: 0.002,
  origSz: 0.002,
  timestamp: 1,
  cloid: null,
  reduceOnly: false,
  orderType: 'Limit',
  isTrigger: false,
  triggerPx: null,
  tif: 'Gtc',
);

HlExposureCheck _check(HlHeldPosition h, {required bool isBuy, double usd = 0}) =>
    hlExposureCheck(market: btc, held: h, isBuy: isBuy, size: usd / 60000);

// ─────────────────────────── the fake venue ───────────────────────────

class _Venue extends HyperliquidModel {
  _Venue(this.positions);
  List<HlPerpPosition> positions;
  bool failDexRead = false;

  /// What a fresh per-dex read finds, when it differs from the account
  /// read (a position opened elsewhere since the last poll).
  List<HlPerpPosition>? dexPositions;
  final reads = <String>[];

  HlAccountSnapshot _snap({Set<String> dexes = const {''}}) =>
      HlAccountSnapshot(
        // No equity: the referrer check (a backend call) stays asleep.
        accountValue: 0,
        withdrawable: 5000,
        totalMarginUsed: 0,
        positions: positions,
        spotBalances: const [],
        positionDexes: dexes,
      );

  @override
  Future<HlAccountSnapshot> getAccountSnapshot(String address) async {
    reads.add('account');
    return _snap();
  }

  @override
  Future<HlAccountSnapshot> getDexClearinghouse(
      String address, String dex) async {
    reads.add('dex:$dex');
    if (failDexRead) throw http.ClientException('info failed');
    final fresh = dexPositions;
    if (fresh != null) {
      return HlAccountSnapshot(
          accountValue: 0,
          withdrawable: 5000,
          totalMarginUsed: 0,
          positions: fresh,
          spotBalances: const [],
          positionDexes: {dex});
    }
    return _snap(dexes: {dex});
  }

  @override
  Future<Map<String, HlAccountSnapshot>> getUsdcDexAccounts(
          String address) async =>
      const {};

  @override
  Future<double> getPerpTakerFundingRate(String address, HlMarket market) async =>
      0.00045;

  @override
  Future<List<HlOpenOrder>> getOpenOrders(String address,
          {Iterable<String> dexes = const []}) async =>
      const [];

  @override
  Future<List<HlFill>> getUserFills(String address) async => const [];
}

/// The account provider: [snapshot], or a failed read when null.
class _Account extends HlAccountNotifier {
  _Account(this.snapshot);
  final HlAccountSnapshot? Function() snapshot;

  /// Account reads (builds), to see the refresh an accepted order asks for.
  static int builds = 0;
  @override
  Future<HlAccountSnapshot> build() async {
    builds++;
    final s = snapshot();
    if (s == null) throw http.ClientException('account read failed');
    return s;
  }
}

class _Prices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

/// The policy: every gate open, or Advanced withheld ([advanced] false).
class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy({required this.advanced});
  final bool advanced;

  @override
  RuntimeCapabilities? get snapshot => null;

  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    if (!advanced && ids.contains('trading.advanced')) {
      throw StateError('trading.advanced withheld');
    }
  }

  @override
  Future<void> ensureAllowed(String id,
          {Duration maxAge = Duration.zero}) =>
      ensureAllAllowed([id]);

  @override
  void ensureLeverageAllowed(int leverage) {}
}

const _walletId = 'w1';

/// The real notifier on [venue], its account as [account] says (null: the
/// read failed), signing with an exchange whose POSTs land in [posted].
Future<HyperliquidTradingNotifier> _notifierOn(
  _Venue venue,
  List<Map<String, dynamic>> posted, {
  HlAccountSnapshot? Function()? account,
  Object? orderThrows,
}) async {
  final key = EthPrivateKey.fromHex(
      '0x0123456789012345678901234567890101234567890123456789012345678901');
  final exchange = HyperliquidExchangeService(
    credentials: key,
    walletAddress: key.address.hexEip55,
    httpClient: MockClient((request) async {
      final action = (jsonDecode(request.body)
          as Map<String, dynamic>)['action'] as Map<String, dynamic>;
      posted.add(action);
      if (action['type'] == 'order' && orderThrows != null) throw orderThrows;
      if (action['type'] == 'order') {
        final o = (action['orders'] as List).first as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'status': 'ok',
              'response': {
                'type': 'order',
                'data': {
                  'statuses': [
                    {
                      'filled': {'totalSz': o['s'], 'avgPx': '60000', 'oid': 7}
                    }
                  ]
                }
              }
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'status': 'ok',
            'response': {'type': 'default'}
          }),
          200);
    }),
  );
  final c = ProviderContainer(overrides: [
    hyperliquidAddressProvider.overrideWith((_) async => exchange.walletAddress),
    hyperliquidAccountProvider
        .overrideWith(() => _Account(account ?? () => venue._snap())),
    hyperliquidTradingModelProvider.overrideWithValue(venue),
    hyperliquidLivePricesProvider.overrideWith(_Prices.new),
  ]);
  addTearDown(c.dispose);
  c.listen(hyperliquidTradingProvider, (_, __) {});
  await c.read(hyperliquidTradingProvider.future);
  final n = c.read(hyperliquidTradingProvider.notifier);
  n.debugAttachExchange(exchange, walletId: _walletId);
  return n;
}

AuthGrant _grantFor(SensitiveIntent intent) =>
    AuthGrants.issue(intent, method: AuthGrantMethod.pin);

Future<void> _buy(HyperliquidTradingNotifier n,
        {required bool isLong, required double usd}) =>
    n.openPosition(
      market: btc,
      isLong: isLong,
      marginUsd: usd,
      leverage: 1,
      grant: _grantFor(HlIntents.openPosition(
        walletId: _walletId,
        market: btc,
        isLong: isLong,
        marginUsd: usd,
        leverage: 1,
        slippagePct: 1.0,
      )),
    );

Future<void> _limit(HyperliquidTradingNotifier n,
        {required bool isLong, required double usd, bool reduceOnly = false}) =>
    n.placeLimit(
      market: btc,
      isLong: isLong,
      marginUsd: usd,
      px: 59000,
      reduceOnly: reduceOnly,
      grant: _grantFor(HlIntents.limit(
        walletId: _walletId,
        market: btc,
        isLong: isLong,
        marginUsd: usd,
        leverage: 1,
        px: 59000,
        tif: 'Gtc',
        postOnly: false,
        reduceOnly: reduceOnly,
      )),
    );

List<String> _types(List<Map<String, dynamic>> posted) =>
    [for (final a in posted) a['type'] as String];

bool _orderReduceOnly(List<Map<String, dynamic>> posted) {
  final order = posted.lastWhere((a) => a['type'] == 'order');
  return ((order['orders'] as List).first as Map<String, dynamic>)['r'] ==
      true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the one rule', () {
    const flat = HlHeldPosition.flat();
    const unknown = HlHeldPosition.unknown();

    test('spot is never new perp exposure', () {
      expect(
          hlExposureCheck(
                  market: _spot, held: unknown, isBuy: true, size: 10)
              .verdict,
          HlExposureVerdict.allowed);
    });

    test('a flat market, or one held at 1x isolated, takes the order as asked',
        () {
      expect(_check(flat, isBuy: true, usd: 1000).verdict,
          HlExposureVerdict.allowed);
      final oneX = HlHeldPosition.of(held(500, leverage: 1));
      expect(_check(oneX, isBuy: true, usd: 1000).verdict,
          HlExposureVerdict.allowed);
      expect(_check(oneX, isBuy: false, usd: 1000).verdict,
          HlExposureVerdict.allowed);
    });

    test('an unknown position is refused, never read as flat', () {
      final c = _check(unknown, isBuy: true, usd: 100);
      expect(c.verdict, HlExposureVerdict.refused);
      expect(c.refusal, HlExposureRefusal.positionUnknown);
    });

    test('an order sent reduce-only passes, known or not', () {
      expect(
          hlExposureCheck(
                  market: btc,
                  held: unknown,
                  isBuy: true,
                  size: 1,
                  reduceOnly: true)
              .allows(sentReduceOnly: true),
          isTrue);
    });

    test('a ticket\'s reduce-only order needs something to reduce', () {
      HlExposureCheck reduce(HlHeldPosition h, {required bool isBuy}) =>
          hlExposureCheck(
              market: btc,
              held: h,
              isBuy: isBuy,
              size: 0.001,
              reduceOnly: true,
              needsPositionToReduce: true);
      // Nothing held: refused, in its own words, never sent.
      final none = reduce(flat, isBuy: true);
      expect(none.verdict, HlExposureVerdict.refused);
      expect(none.refusal, HlExposureRefusal.nothingToReduce);
      expect(none.allows(sentReduceOnly: true), isFalse);
      // A long, and a reduce-only buy: it could only add.
      final long = HlHeldPosition.of(held(500, leverage: 1));
      expect(reduce(long, isBuy: true).refusal,
          HlExposureRefusal.nothingToReduce);
      // The closing side of a held position goes, reduce-only.
      expect(reduce(long, isBuy: false).allows(sentReduceOnly: true), isTrue);
      // A position that could not be read never stops an exit.
      expect(reduce(unknown, isBuy: false).allows(sentReduceOnly: true),
          isTrue);
      // A stop attached to an order that has just filled is not asked.
      expect(
          hlExposureCheck(
                  market: btc,
                  held: flat,
                  isBuy: false,
                  size: 0.001,
                  reduceOnly: true)
              .allows(sentReduceOnly: true),
          isTrue);
    });

    for (final cross in [false, true]) {
      final kind = cross ? '10x cross' : '10x isolated';
      group('a $kind short worth \$500', () {
        final short = HlHeldPosition.of(held(-500, cross: cross));

        test('an add is refused', () {
          final c = _check(short, isBuy: false, usd: 100);
          expect(c.verdict, HlExposureVerdict.refused);
          expect(c.refusal, HlExposureRefusal.leveragedPosition);
        });

        test('a \$1,000 buy (a flip) is refused', () {
          final c = _check(short, isBuy: true, usd: 1000);
          expect(c.verdict, HlExposureVerdict.refused);
          expect(c.refusal, HlExposureRefusal.leveragedPosition);
        });

        test('a \$200 buy (a pure reduction) goes only reduce-only', () {
          final c = _check(short, isBuy: true, usd: 200);
          expect(c.verdict, HlExposureVerdict.reduceOnly);
          expect(c.allows(sentReduceOnly: true), isTrue);
          expect(c.allows(sentReduceOnly: false), isFalse);
        });

        test('the whole position (the close) goes reduce-only', () {
          expect(_check(short, isBuy: true, usd: 500).verdict,
              HlExposureVerdict.reduceOnly);
        });
      });
    }

    test('a position is known only on the dexes the account read covered', () {
      final snap = HlAccountSnapshot(
        accountValue: 0,
        withdrawable: 0,
        totalMarginUsed: 0,
        positions: [held(500)],
        spotBalances: const [],
        positionDexes: const {''},
      );
      expect(HlHeldPosition.fromSnapshot(btc, snap).position, isNotNull);
      // A builder dex the read did not cover (one not settled in USDC):
      // unknown, not flat.
      expect(HlHeldPosition.fromSnapshot(_xyz, snap).known, isFalse);
      expect(HlHeldPosition.fromSnapshot(btc, null).known, isFalse);
      // A per-dex read names its own dex.
      final dex = HlAccountSnapshot.fromJson(
          perpState: const {'assetPositions': []}, dex: 'xyz');
      expect(dex.positionDexes, {'xyz'});
      expect(HlHeldPosition.fromSnapshot(_xyz, dex).known, isTrue);
    });
  });

  for (final advanced in [false, true]) {
    group('the order notifier, Advanced ${advanced ? 'on' : 'off'}', () {
      setUp(() =>
          RuntimeCapabilitiesService.debugInstance = _Policy(advanced: advanced));
      tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

      test(
          'a plain market buy on a flat, loaded account is unchanged: the 1x '
          'isolated write, then the order, and no extra read', () async {
        final venue = _Venue([]);
        final posted = <Map<String, dynamic>>[];
        final n = await _notifierOn(venue, posted);
        venue.reads.clear();
        await _buy(n, isLong: true, usd: 100);
        expect(_types(posted), ['updateLeverage', 'order']);
        expect(posted.first['leverage'], 1);
        expect(posted.first['isCross'], isFalse);
        expect(_orderReduceOnly(posted), isFalse);
        // The funding reads it always made; never a position read.
        expect(venue.reads.where((r) => r.startsWith('dex:')), isEmpty);
      });

      for (final cross in [false, true]) {
        final kind = cross ? '10x cross' : '10x isolated';
        test('an add to a $kind position is refused before anything is sent',
            () async {
          final venue = _Venue([held(-500, cross: cross)]);
          final posted = <Map<String, dynamic>>[];
          final n = await _notifierOn(venue, posted);
          venue.reads.clear();
          await expectLater(_buy(n, isLong: false, usd: 100),
              throwsA(isA<HlExposureRefusedException>()));
          expect(posted, isEmpty);
          // Refused before the funding read, too.
          expect(venue.reads, isEmpty);
        });

        test('a \$1,000 buy against a $kind \$500 short (a flip) is refused',
            () async {
          final venue = _Venue([held(-500, cross: cross)]);
          final posted = <Map<String, dynamic>>[];
          final n = await _notifierOn(venue, posted);
          await expectLater(_buy(n, isLong: true, usd: 1000),
              throwsA(isA<HlExposureRefusedException>()));
          expect(posted, isEmpty);
        });

        test(
            'a \$200 buy against a $kind \$500 short goes out reduce-only, '
            'with no leverage write and no funding', () async {
          final venue = _Venue([held(-500, cross: cross)]);
          final posted = <Map<String, dynamic>>[];
          final n = await _notifierOn(venue, posted);
          venue.reads.clear();
          await _buy(n, isLong: true, usd: 200);
          expect(_types(posted), ['order']);
          expect(_orderReduceOnly(posted), isTrue);
          expect(venue.reads, isEmpty);
        });
      }

      test(
          'an account that could not be read: the market\'s dex is read '
          'fresh, and a failed read refuses with nothing sent', () async {
        final venue = _Venue([])..failDexRead = true;
        final posted = <Map<String, dynamic>>[];
        final n = await _notifierOn(venue, posted, account: () => null);
        await expectLater(
            _buy(n, isLong: true, usd: 100),
            throwsA(isA<HlExposureRefusedException>().having(
                (e) => e.refusal, 'refusal', HlExposureRefusal.positionUnknown)));
        expect(venue.reads, contains('dex:'));
        expect(posted, isEmpty);
      });

      test(
          'an account that could not be read but whose fresh read shows a '
          '10x position: the add is refused, never written over', () async {
        final venue = _Venue([held(500)]);
        final posted = <Map<String, dynamic>>[];
        final n = await _notifierOn(venue, posted, account: () => null);
        await expectLater(_buy(n, isLong: true, usd: 100),
            throwsA(isA<HlExposureRefusedException>()));
        expect(posted, isEmpty);
      });

      test(
          'an account that could not be read but whose fresh read is flat: '
          'the order goes as usual', () async {
        final venue = _Venue([]);
        final posted = <Map<String, dynamic>>[];
        final n = await _notifierOn(venue, posted, account: () => null);
        await _buy(n, isLong: true, usd: 100);
        expect(_types(posted), ['updateLeverage', 'order']);
      });
    });
  }

  group('the limit path (Advanced on)', () {
    setUp(() => RuntimeCapabilitiesService.debugInstance = _Policy(advanced: true));
    tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

    test('on a flat market: 1x isolated, then the order', () async {
      final venue = _Venue([]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await _limit(n, isLong: true, usd: 100);
      expect(_types(posted), ['updateLeverage', 'order']);
      expect(posted.first['leverage'], 1);
      expect(_orderReduceOnly(posted), isFalse);
    });

    test('an add to a 10x cross position is refused before the leverage write',
        () async {
      final venue = _Venue([held(500, cross: true)]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await expectLater(_limit(n, isLong: true, usd: 100),
          throwsA(isA<HlExposureRefusedException>()));
      expect(posted, isEmpty);
    });

    test('a reduction of a 10x position goes out reduce-only', () async {
      final venue = _Venue([held(500)]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await _limit(n, isLong: false, usd: 200);
      expect(_types(posted), ['order']);
      expect(_orderReduceOnly(posted), isTrue);
    });

    test('reduce-only with nothing to reduce is refused, nothing is sent',
        () async {
      final venue = _Venue([]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await expectLater(
          _limit(n, isLong: true, usd: 100, reduceOnly: true),
          throwsA(isA<HlExposureRefusedException>().having((e) => e.refusal,
              'refusal', HlExposureRefusal.nothingToReduce)));
      expect(posted, isEmpty);
    });

    test('reduce-only against a held position goes out', () async {
      final venue = _Venue([held(500, leverage: 1)]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await _limit(n, isLong: false, usd: 200, reduceOnly: true);
      expect(_types(posted), ['order']);
      expect(_orderReduceOnly(posted), isTrue);
    });

    test('an unknown position on a builder dex writes no leverage', () async {
      // The account read covers the main dex only (xyz is not settled in
      // USDC, say), and the fresh read of xyz fails.
      final venue = _Venue([])..failDexRead = true;
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await expectLater(
          n.placeLimit(
            market: _xyz,
            isLong: true,
            marginUsd: 100,
            px: 290,
            grant: _grantFor(HlIntents.limit(
              walletId: _walletId,
              market: _xyz,
              isLong: true,
              marginUsd: 100,
              leverage: 1,
              px: 290,
              tif: 'Gtc',
              postOnly: false,
              reduceOnly: false,
            )),
          ),
          throwsA(isA<HlExposureRefusedException>()));
      expect(venue.reads, contains('dex:xyz'));
      expect(posted, isEmpty);
    });
  });

  group('the scale path (Advanced on)', () {
    setUp(() => RuntimeCapabilitiesService.debugInstance = _Policy(advanced: true));
    tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

    Future<void> scale(HyperliquidTradingNotifier n,
            {required bool isLong, required double usd}) =>
        n.placeScale(
          market: btc,
          isLong: isLong,
          totalUsd: usd,
          startPx: isLong ? 58000 : 62000,
          endPx: isLong ? 57000 : 63000,
          count: 3,
          grant: _grantFor(HlIntents.scale(
            walletId: _walletId,
            market: btc,
            isLong: isLong,
            totalUsd: usd,
            startPx: isLong ? 58000 : 62000,
            endPx: isLong ? 57000 : 63000,
            count: 3,
          )),
        );

    test('a ladder adding to a 10x cross position is refused, nothing sent',
        () async {
      final venue = _Venue([held(500, cross: true)]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await expectLater(scale(n, isLong: true, usd: 100),
          throwsA(isA<HlExposureRefusedException>()));
      expect(posted, isEmpty);
    });

    test('a ladder reducing a 10x position goes out reduce-only', () async {
      final venue = _Venue([held(500)]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await scale(n, isLong: false, usd: 200);
      expect(_types(posted), ['order']);
      for (final o in posted.single['orders'] as List) {
        expect((o as Map<String, dynamic>)['r'], isTrue);
      }
    });
  });

  group('freshness of the positions an opening order is judged on', () {
    setUp(() => RuntimeCapabilitiesService.debugInstance = _Policy(advanced: true));
    tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

    test(
        'a 5x cross long opened elsewhere since the last poll (10 s ago): '
        'seen by one fresh read, the add refused before any funding or '
        'leverage write', () async {
      final venue = _Venue([])
        ..dexPositions = [held(500, leverage: 5, cross: true)];
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted,
          account: () => _flatReadAgo(const Duration(seconds: 10)));
      venue.reads.clear();
      await expectLater(
          _buy(n, isLong: true, usd: 100),
          throwsA(isA<HlExposureRefusedException>().having((e) => e.refusal,
              'refusal', HlExposureRefusal.leveragedPosition)));
      // One position read; no funding read ('account'), nothing posted (no
      // updateLeverage on the wire).
      expect(venue.reads, ['dex:']);
      expect(posted, isEmpty);
    });

    test('the same on the limit path', () async {
      final venue = _Venue([])
        ..dexPositions = [held(500, leverage: 10)];
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted,
          account: () => _flatReadAgo(const Duration(seconds: 10)));
      await expectLater(_limit(n, isLong: true, usd: 100),
          throwsA(isA<HlExposureRefusedException>()));
      expect(posted, isEmpty);
    });

    test(
        'a plain market buy on a flat account read 1 s ago: no extra read, '
        'the 1x isolated write, then the order', () async {
      final venue = _Venue([]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted,
          account: () => _flatReadAgo(const Duration(seconds: 1)));
      venue.reads.clear();
      await _buy(n, isLong: true, usd: 100);
      expect(venue.reads.where((r) => r.startsWith('dex:')), isEmpty);
      expect(_types(posted), ['updateLeverage', 'order']);
    });

    test(
        'a flat account read 10 s ago and still flat: one read, then the '
        'order as usual (the leverage write reads nothing more)', () async {
      final venue = _Venue([]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted,
          account: () => _flatReadAgo(const Duration(seconds: 10)));
      venue.reads.clear();
      await _buy(n, isLong: true, usd: 100);
      expect(venue.reads.where((r) => r.startsWith('dex:')), ['dex:']);
      expect(_types(posted), ['updateLeverage', 'order']);
    });

    test(
        'a builder dex the account read does not cover is read once per '
        'bound, not on every tap', () async {
      final venue = _Venue([]);
      final n = await _notifierOn(venue, <Map<String, dynamic>>[]);
      venue.reads.clear();
      final a =
          await n.heldPositionFor(_xyz, maxAge: kHlPositionsFreshFor);
      final b =
          await n.heldPositionFor(_xyz, maxAge: kHlPositionsFreshFor);
      expect(a.known && b.known, isTrue);
      expect(n.heldPositionKnown(_xyz).known, isTrue);
      expect(venue.reads, ['dex:xyz']);
    });
  });

  group('a resting order moved (modifyOrder)', () {
    setUp(() => RuntimeCapabilitiesService.debugInstance = _Policy(advanced: true));
    tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

    Future<void> move(HyperliquidTradingNotifier n, HlOpenOrder order,
            double px) =>
        n.modifyOrder(
          market: btc,
          order: order,
          newPx: px,
          grant: _grantFor(HlIntents.modify(
            walletId: _walletId,
            market: btc,
            oid: order.oid,
            isLong: order.isBuy,
            size: order.sz,
            px: px,
            reduceOnly: order.reduceOnly,
            tif: order.tif,
            tpsl: null,
            isMarket: false,
          )),
        );

    for (final (lev, cross) in [(5, true), (10, false)]) {
      final kind = '${lev}x ${cross ? 'cross' : 'isolated'}';
      test(
          'a buy limit placed while flat, dragged above the price after a '
          '$kind long was opened elsewhere: refused, nothing sent', () async {
        final venue = _Venue([held(500, leverage: lev, cross: cross)]);
        final posted = <Map<String, dynamic>>[];
        final n = await _notifierOn(venue, posted);
        await expectLater(
            move(n, _restingBuy, 61000),
            throwsA(isA<HlExposureRefusedException>().having((e) => e.refusal,
                'refusal', HlExposureRefusal.leveragedPosition)));
        expect(posted, isEmpty);
        // The drag asks the same rule before its confirm sheet.
        expect(
            hlMoveExposureRefusal(btc, _restingBuy,
                HlHeldPosition.of(held(500, leverage: lev, cross: cross))),
            HlExposureRefusal.leveragedPosition);
      });
    }

    test('flat: the move goes out as the venue\'s modify', () async {
      final venue = _Venue([]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      await move(n, _restingBuy, 61000);
      expect(_types(posted), ['modify']);
      expect(hlMoveExposureRefusal(btc, _restingBuy, const HlHeldPosition.flat()),
          isNull);
    });

    test('a reduce-only order on a 5x cross position moves', () async {
      final venue = _Venue([held(500, leverage: 5, cross: true)]);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted);
      const sell = HlOpenOrder(
        coin: 'BTC',
        oid: 42,
        isBuy: false,
        limitPx: 62000,
        sz: 0.002,
        origSz: 0.002,
        timestamp: 1,
        cloid: null,
        reduceOnly: true,
        orderType: 'Limit',
        isTrigger: false,
        triggerPx: null,
        tif: 'Gtc',
      );
      await move(n, sell, 61500);
      expect(_types(posted), ['modify']);
      expect(
          hlMoveExposureRefusal(btc, sell, const HlHeldPosition.unknown()),
          isNull);
    });

    test('an unknown position: the move is refused', () {
      expect(
          hlMoveExposureRefusal(
              btc, _restingBuy, const HlHeldPosition.unknown()),
          HlExposureRefusal.positionUnknown);
    });

    test('the chart drag asks the rule before its confirm sheet and approval',
        () {
      final src = File('lib/screens/hyperliquid/market_detail_sheet.dart')
          .readAsStringSync();
      final start = src.indexOf('Future<void> _moveOrder(');
      final end = src.indexOf('\n  void _onTradeLineTapped', start);
      final body = src.substring(start, end);
      final rule = body.indexOf('hlMoveExposureRefusal(');
      expect(rule, greaterThan(0));
      expect(body.indexOf('showAppBottomSheet<bool>('), greaterThan(rule));
      expect(body.indexOf('requireFreshAuthGrant('), greaterThan(rule));
      expect(body, contains('on HlExposureRefusedException'));
    });
  });

  // Every order door that can open perp exposure asks the rule before its
  // leverage write and its funding (TWAP and trailing stops need a session
  // and a stop guard, so their order is held here by the source).
  test('every opening order path asks the rule before writing or funding', () {
    final src =
        File('lib/providers/hyperliquid_trading_provider.dart').readAsStringSync();
    for (final name in [
      'openPosition',
      'placeLimit',
      'placeScale',
      'placeTwap',
      'placeTrailingStop',
    ]) {
      final start = src.indexOf('Future<HlOrderResult> $name({');
      expect(start, greaterThan(0), reason: name);
      final end = src.indexOf('\n  Future<', start + 10);
      final body = src.substring(start, end);
      final rule = body.indexOf('exposureFor(');
      expect(rule, greaterThan(0), reason: '$name asks the rule');
      for (final step in ['_ensureLeverage(', '_fundPerpAction(']) {
        final at = body.indexOf(step);
        expect(at, greaterThan(rule), reason: '$name: $step after the rule');
      }
    }
    // The portfolio builder's perp legs go through openPosition, and say
    // the rule's refusal in its own words.
    final builder = File(
            'lib/screens/shared/portfolio_builder/builder_placement.dart')
        .readAsStringSync();
    expect(builder, contains('trading.openPosition('));
    expect(builder, contains('on HlExposureRefusedException'));
  });

  group('an unclear answer to a market order its own fills already filled',
      () {
    late List<(String, Map<String, Object>?)> events;
    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      RuntimeCapabilitiesService.debugInstance = _Policy(advanced: false);
    });
    tearDown(() {
      TrackingService.debugTrackObserver = null;
      RuntimeCapabilitiesService.debugInstance = null;
    });

    HlFill fill(String cloid, double sz, {int time = 1}) => HlFill(
          coin: 'BTC',
          px: 60000,
          sz: sz,
          side: 'B',
          time: time,
          closedPnl: 0,
          fee: 0,
          feeToken: 'USDC',
          oid: 7,
          hash: '0x$time',
          dir: 'Open Long',
          cloid: cloid,
          tradeId: 't$time',
        );

    // $600 at 60,000: 0.01 BTC sent.
    const cloid = '0x00000000000000000000000000000abc';

    Future<Object?> buyWithFills(List<HlFill> fills) async {
      final venue = _Venue(const []);
      final posted = <Map<String, dynamic>>[];
      final n = await _notifierOn(venue, posted,
          orderThrows: const HyperliquidOrderUnconfirmedException());
      n.recordFills(fills);
      _Account.builds = 0;
      double? sent;
      try {
        await n.openPosition(
          market: btc,
          isLong: true,
          marginUsd: 600,
          leverage: 1,
          cloid: cloid,
          onSent: (size) => sent = size,
          grant: _grantFor(HlIntents.openPosition(
            walletId: _walletId,
            market: btc,
            isLong: true,
            marginUsd: 600,
            leverage: 1,
            slippagePct: 1.0,
          )),
        );
        expect(sent, closeTo(0.01, 1e-9));
        return null;
      } catch (e) {
        return e;
      }
    }

    int count(String event) => events.where((e) => e.$1 == event).length;

    test('own fills totalling the size: accepted, one placed event, no failure,'
        ' the account read again', () async {
      final error = await buyWithFills(
          [fill(cloid, 0.006, time: 1), fill(cloid, 0.004, time: 2)]);
      expect(error, isNull);
      expect(count('hyperliquid_order_placed'), 1);
      expect(count('hyperliquid_order_failed'), 0);
      await Future<void>.delayed(Duration.zero);
      expect(_Account.builds, greaterThan(0));
    });

    test('no own fills: still unconfirmed, reported as before', () async {
      final error = await buyWithFills(
          [fill('0x00000000000000000000000000000def', 0.01)]);
      expect(error, isA<HyperliquidOrderUnconfirmedException>());
      expect(count('hyperliquid_order_placed'), 0);
    });

    test('own fills of a part: still unconfirmed', () async {
      final error = await buyWithFills([fill(cloid, 0.005)]);
      expect(error, isA<HyperliquidOrderUnconfirmedException>());
      expect(count('hyperliquid_order_placed'), 0);
    });
  });
}
