// The first prediction after money arrived must not be refused because the
// order book still counts the old balance: before any buy, held USDC.e is
// converted, a missing exchange allowance set and the book's count re-read
// until it covers the order; the venue's balance refusal gets one refresh
// that waits for the count, never a second funding.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket/venue_collateral.dart';

const _v2Yes =
    '834369838335332281222091626449713794621251551518727511203689528701902389248';
const _v1Token = '12345';
final _exchange = PolymarketConstants.exchangeAddress.toLowerCase();

BigInt _usd(num v) => BigInt.from((v * 1e6).round());

const _balanceRefusal = 'not enough balance / allowance: the balance is not '
    'enough -> balance: 0, order amount: 3000000';

/// A deposit wallet on chain and the order book's own count of it. The
/// book re-reads the chain only on a refresh request, and only once the
/// chain has been visible to it for [lag] requests (the block the
/// conversion landed in is not yet the one the book reads).
class _Account {
  _Account({
    required this.pusd,
    BigInt? usdce,
    BigInt? counted,
    this.lag = 0,
    BigInt? chainAllowance,
    BigInt? countedAllowance,
    this.readable = true,
  })  : usdce = usdce ?? BigInt.zero,
        counted = counted ?? pusd,
        chainAllowance = chainAllowance ?? _max,
        countedAllowance = countedAllowance ?? chainAllowance ?? _max;

  static final _max = BigInt.parse('1' * 30);

  BigInt pusd;
  BigInt usdce;
  BigInt counted;
  int lag;
  BigInt chainAllowance;
  BigInt countedAllowance;
  bool readable;

  int wraps = 0;
  int refreshes = 0;
  int venueReads = 0;
  int splitReads = 0;
  int approvals = 0;
  int sleeps = 0;
  int posts = 0;
  int accepted = 0;
  Duration wrapTakes = Duration.zero;

  BigInt get held => pusd + usdce;

  PolyVenueCollateralOps get ops => PolyVenueCollateralOps(
        readVenue: () async {
          venueReads++;
          if (!readable) throw StateError('404 no deposit wallet found');
          return PolyVenueCount(
              balance: counted, allowances: {_exchange: countedAllowance});
        },
        readSplit: ({required bool fresh}) async {
          splitReads++;
          return (pusd: pusd, usdce: usdce);
        },
        wrap: () async {
          if (wrapTakes > Duration.zero) await Future<void>.delayed(wrapTakes);
          wraps++;
          final moved = usdce;
          pusd += moved;
          usdce = BigInt.zero;
          return moved;
        },
        refreshVenue: () async {
          refreshes++;
          if (!readable) throw Exception('404 no deposit wallet found');
          if (lag > 0) {
            lag--;
            return;
          }
          counted = pusd;
          countedAllowance = chainAllowance;
        },
        approveSpender: (spender) async {
          approvals++;
          expect(spender, _exchange);
          final sent = chainAllowance == BigInt.zero;
          chainAllowance = _max;
          return sent;
        },
        sleep: (_) async => sleeps++,
      );

  /// The order book's answer to a buy costing [cost].
  Future<void> post(BigInt cost) async {
    posts++;
    if (counted < cost || countedAllowance < cost) {
      throw const PolymarketOrderNotAcceptedExceptionForTest(_balanceRefusal);
    }
    accepted++;
    pusd -= cost;
    counted -= cost;
  }
}

class PolymarketOrderNotAcceptedExceptionForTest implements Exception {
  const PolymarketOrderNotAcceptedExceptionForTest(this.reason);
  final String reason;
}

/// The buy as a placement runs it: get the collateral ready, post, and on
/// a balance refusal the one refresh (which waits for the count) and one
/// more post. Never funds: the only money it touches is the wallet's.
Future<PolyVenueReadiness> _placeBuy(_Account a, BigInt cost) async {
  final spenders = polyBuySpenders(_v1Token, negRisk: false);
  final readiness = await polyReadyVenueCollateral(
      costMicros: cost, spenders: spenders, ops: a.ops);
  polyRequireConfirmedCollateral(readiness);
  var balanceRefreshed = false;
  while (true) {
    try {
      await a.post(cost);
      return readiness;
    } on PolymarketOrderNotAcceptedExceptionForTest catch (e) {
      final heal = polymarketRefusalHeal(e.reason,
          balanceRefreshed: balanceRefreshed,
          keyRebound: false,
          approvalsFixed: false);
      if (heal != PolymarketRefusalHeal.refreshBalance) rethrow;
      balanceRefreshed = true;
      final after = await polyReadyVenueCollateral(
          costMicros: cost, spenders: spenders, ops: a.ops, afterRefusal: true);
      polyRequireConfirmedCollateral(after);
    }
  }
}

void main() {
  test('only confirmed full collateral permits a post', () {
    for (final readiness in PolyVenueReadiness.values) {
      if (readiness == PolyVenueReadiness.counted ||
          readiness == PolyVenueReadiness.refreshed) {
        expect(
            () => polyRequireConfirmedCollateral(readiness), returnsNormally);
      } else {
        expect(() => polyRequireConfirmedCollateral(readiness),
            throwsA(isA<PolymarketCollateralPending>()));
      }
    }
  });

  test('a stale high book count cannot certify missing on-chain pUSD',
      () async {
    final a = _Account(pusd: _usd(1), counted: _usd(10));
    final ready = await polyReadyVenueCollateral(
        costMicros: _usd(5), spenders: [_exchange], ops: a.ops);
    expect(ready, PolyVenueReadiness.short);
    expect(() => polyRequireConfirmedCollateral(ready),
        throwsA(isA<PolymarketCollateralPending>()));
    expect(a.posts, 0);
  });

  test('joining a prior conversion cannot synthesize aggregate pUSD proof',
      () async {
    final ready = await polyReadyVenueCollateral(
        costMicros: _usd(10),
        spenders: [_exchange],
        ops: PolyVenueCollateralOps(
          readVenue: () async => PolyVenueCount(balance: _usd(10)),
          readSplit: ({required fresh}) async =>
              (pusd: _usd(4), usdce: _usd(6)),
          // Another delivery's single-flight wrap reports six converted,
          // but this read still sees only four usable: re-read, never add.
          wrap: () async => _usd(6),
          refreshVenue: () async {},
          approveSpender: (_) async => false,
          sleep: (_) async {},
        ));
    expect(ready, PolyVenueReadiness.short);
    expect(() => polyRequireConfirmedCollateral(ready),
        throwsA(isA<PolymarketCollateralPending>()));
  });
  setUp(() {
    PolymarketPlacementWaits.venueCount = const Duration(seconds: 3);
    PolymarketPlacementWaits.venueCountPoll = const Duration(seconds: 1);
    PolymarketPlacementWaits.conversion = const Duration(seconds: 90);
  });

  group('before the first order', () {
    test('money still in USDC.e is converted, then the order posts once',
        () async {
      final a = _Account(pusd: BigInt.zero, usdce: _usd(3.55));
      final readiness = await _placeBuy(a, _usd(3));
      expect(readiness, PolyVenueReadiness.refreshed);
      expect(a.wraps, 1);
      expect(a.posts, 1);
      expect(a.accepted, 1);
    });

    test('a stale count is re-read until it covers the buy, then posts once',
        () async {
      // Converted a moment ago: the chain holds it, the book counts 0 and
      // only sees it on the third re-read.
      final a = _Account(pusd: _usd(3.55), counted: BigInt.zero, lag: 2);
      final readiness = await _placeBuy(a, _usd(3));
      expect(readiness, PolyVenueReadiness.refreshed);
      expect(a.wraps, 0);
      expect(a.refreshes, 3);
      expect(a.sleeps, 2);
      expect(a.posts, 1);
      expect(a.accepted, 1);
    });

    test('a missing exchange allowance is set, then the order posts once',
        () async {
      final a = _Account(pusd: _usd(5), chainAllowance: BigInt.zero);
      final readiness = await _placeBuy(a, _usd(3));
      expect(readiness, PolyVenueReadiness.refreshed);
      expect(a.approvals, 1);
      expect(a.posts, 1);
      expect(a.accepted, 1);
    });

    test('a book that already counts the buy costs one read and nothing else',
        () async {
      final a = _Account(pusd: _usd(5));
      final readiness = await _placeBuy(a, _usd(3));
      expect(readiness, PolyVenueReadiness.counted);
      expect(a.venueReads, 1);
      expect(a.splitReads, 1);
      expect(a.wraps + a.refreshes + a.approvals + a.sleeps, 0);
      expect(a.posts, 1);
    });

    test('a book that cannot be read is not waited on', () async {
      final a = _Account(pusd: _usd(5), readable: false);
      final readiness = await polyReadyVenueCollateral(
          costMicros: _usd(3),
          spenders: polyBuySpenders(_v1Token, negRisk: false),
          ops: a.ops);
      expect(readiness, PolyVenueReadiness.unread);
      expect(a.sleeps, 0);
    });

    test('a wallet short of the buy is not waited on either', () async {
      final a = _Account(pusd: _usd(1), usdce: _usd(1));
      final readiness = await polyReadyVenueCollateral(
          costMicros: _usd(3),
          spenders: polyBuySpenders(_v1Token, negRisk: false),
          ops: a.ops);
      expect(readiness, PolyVenueReadiness.short);
      expect(a.wraps, 0);
      expect(a.sleeps, 0);
    });

    test('a conversion that outlasts its wait says the money is converting',
        () async {
      PolymarketPlacementWaits.conversion = const Duration(milliseconds: 10);
      final a = _Account(pusd: BigInt.zero, usdce: _usd(5))
        ..wrapTakes = const Duration(milliseconds: 200);
      await expectLater(
          polyReadyVenueCollateral(
              costMicros: _usd(3),
              spenders: polyBuySpenders(_v1Token, negRisk: false),
              ops: a.ops),
          throwsA(isA<PolymarketFundsConverting>()));
    });
  });

  group('the book remains behind after the bounded preflight', () {
    test('no post until a later confirmed check covers the full buy', () async {
      final a = _Account(pusd: _usd(3.55), counted: BigInt.zero, lag: 5);
      await expectLater(
          _placeBuy(a, _usd(3)), throwsA(isA<PolymarketCollateralPending>()));
      expect(a.posts, 0);
      final readiness = await _placeBuy(a, _usd(3));
      expect(readiness, PolyVenueReadiness.refreshed);
      expect(a.posts, 1);
      expect(a.accepted, 1);
    });

    test('a second refusal ends the placement, nothing funded twice', () async {
      final a = _Account(pusd: _usd(3.55), counted: BigInt.zero, lag: 100);
      final before = a.held;
      await expectLater(
          _placeBuy(a, _usd(3)), throwsA(isA<PolymarketCollateralPending>()));
      expect(a.posts, 0);
      expect(a.accepted, 0);
      // Only the wallet's own money: nothing came in or left.
      expect(a.held, before);
      expect(
          polymarketRefusalHeal(_balanceRefusal,
              balanceRefreshed: true, keyRebound: false, approvalsFixed: false),
          PolymarketRefusalHeal.stop);
    });

    test('the refresh converts USDC.e that landed after the first read',
        () async {
      final a = _Account(pusd: BigInt.zero);
      final cost = _usd(3);
      final spenders = polyBuySpenders(_v1Token, negRisk: false);
      // Nothing there yet: preparation is short and no order may post.
      final before = await polyReadyVenueCollateral(
          costMicros: cost, spenders: spenders, ops: a.ops);
      expect(() => polyRequireConfirmedCollateral(before),
          throwsA(isA<PolymarketCollateralPending>()));
      expect(a.posts, 0);
      // The funding lands as USDC.e; the next check converts it.
      a.usdce = _usd(3.55);
      final after = await polyReadyVenueCollateral(
          costMicros: cost, spenders: spenders, ops: a.ops, afterRefusal: true);
      expect(after, PolyVenueReadiness.refreshed);
      expect(a.wraps, 1);
      await a.post(cost);
      expect(a.accepted, 1);
    });
  });

  group('the count', () {
    test('is read from the book, allowances by lower-case spender', () {
      final count = PolyVenueCount.fromClob({
        'balance': '3550000',
        'allowances': {PolymarketConstants.exchangeAddress: '0'},
      })!;
      expect(count.balance, _usd(3.55));
      expect(count.shortSpenders([_exchange], _usd(1)), [_exchange]);
      expect(count.covers(_usd(1), [_exchange]), isFalse);
      // A spender the book does not report is not counted as missing.
      expect(
          count.covers(_usd(1), [
            PolymarketConstants.comboExchangeV3Address.toLowerCase(),
          ]),
          isTrue);
      expect(PolyVenueCount.fromClob({'balance': null}), isNull);
      expect(PolyVenueCount.fromClob(null), isNull);
    });

    test('names the exchanges a buy pulls pUSD through', () {
      expect(polyBuySpenders(_v1Token, negRisk: false), [_exchange]);
      expect(polyBuySpenders(_v1Token, negRisk: true), [
        PolymarketConstants.negRiskExchangeAddress.toLowerCase(),
        PolymarketConstants.legacyNegRiskAdapterAddress.toLowerCase(),
      ]);
      expect(polyBuySpenders(_v2Yes, negRisk: true),
          [PolymarketConstants.comboExchangeV3Address.toLowerCase()]);
    });
  });

  test('every buy, direct or funded, is readied before the order guard', () {
    final provider = File('lib/providers/polymarket_trading_provider.dart')
        .readAsStringSync();
    final start = provider.indexOf('Future<Map<String, dynamic>> placeOrder({');
    final guard = provider.indexOf('HotPolymarketOrderGuard().run(', start);
    final ready = provider.indexOf('polyReadyVenueCollateral(', start);
    expect(start, greaterThan(0));
    expect(ready, greaterThan(start));
    expect(ready, lessThan(guard));
    // The balance refusal's one refresh waits for the count too.
    final heal =
        provider.indexOf('heal == PolymarketRefusalHeal.refreshBalance', guard);
    expect(provider.indexOf('afterRefusal: true', heal),
        lessThan(provider.indexOf('PolymarketRefusalHeal.rebindKey', heal)));
    // The slip's own placement and the autofire (funded from Dollars) both
    // place through it.
    for (final path in [
      'lib/providers/polymarket_bet_controller.dart',
      'lib/providers/pending_bet_autofire.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('.placeOrder('),
          reason: path);
    }
  });
}
