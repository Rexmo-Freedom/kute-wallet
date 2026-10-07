// test/models/hyperliquid_market_test.dart
//
// Fixture-driven parse tests for the Hyperliquid trading data classes.
// Fixtures are trimmed real response shapes from the /info endpoint
// (metaAndAssetCtxs, spotMetaAndAssetCtxs, clearinghouseState,
// spotClearinghouseState, frontendOpenOrders, userFills, l2Book).
//
// The high-stakes invariants exercised here:
//   * perp assetId == POSITION in the universe (preserved across skipped
//     delisted entries);
//   * spot assetId == 10000 + the pair's `index` FIELD (not its list
//     position) — the '@107 at list position 1' case;
//   * full spot universe: every USDC-quoted pair kept, non-USDC-quoted
//     and unresolvable-base pairs dropped;
//   * defensive parsing of string-encoded numbers and nullable fields.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';

const String kMetaAndAssetCtxsFixture = '''
[
  {
    "universe": [
      {"name": "BTC", "szDecimals": 5, "maxLeverage": 40},
      {"name": "ETH", "szDecimals": 4, "maxLeverage": 25, "onlyIsolated": true},
      {"name": "OLDCOIN", "szDecimals": 1, "maxLeverage": 3, "isDelisted": true},
      {"name": "SOL", "szDecimals": 2}
    ],
    "marginTables": []
  },
  [
    {
      "funding": "0.0000125",
      "openInterest": "688.11",
      "prevDayPx": "100000.0",
      "dayNtlVlm": "1169046.29406",
      "premium": "0.00031774",
      "oraclePx": "102000.0",
      "markPx": "102500.0",
      "midPx": "102490.5"
    },
    {
      "funding": "-0.0000021",
      "openInterest": "12345.6",
      "prevDayPx": "3200.0",
      "dayNtlVlm": "500000.5",
      "markPx": "3100.0",
      "midPx": "3099.5"
    },
    {
      "funding": "0.0",
      "openInterest": "0.0",
      "prevDayPx": "1.0",
      "dayNtlVlm": "0.0",
      "markPx": "1.0"
    },
    {
      "funding": "0.00005",
      "openInterest": "99.0",
      "prevDayPx": "0",
      "dayNtlVlm": "7777.0",
      "markPx": "150.25"
    }
  ]
]
''';

const String kSpotMetaAndAssetCtxsFixture = '''
[
  {
    "tokens": [
      {"name": "USDC", "szDecimals": 8, "weiDecimals": 8, "index": 0, "isCanonical": true},
      {"name": "PURR", "szDecimals": 0, "weiDecimals": 5, "index": 1, "isCanonical": true},
      {"name": "USDH", "szDecimals": 2, "weiDecimals": 6, "index": 3, "isCanonical": false},
      {"name": "TSLA", "szDecimals": 2, "weiDecimals": 8, "index": 10, "isCanonical": false}
    ],
    "universe": [
      {"name": "PURR/USDC", "tokens": [1, 0], "index": 0, "isCanonical": true},
      {"name": "@107", "tokens": [10, 0], "index": 107, "isCanonical": false},
      {"name": "@5", "tokens": [10, 3], "index": 5, "isCanonical": false},
      {"name": "@6", "tokens": [99, 0], "index": 6, "isCanonical": false}
    ]
  },
  [
    {
      "markPx": "0.15",
      "midPx": "0.1505",
      "prevDayPx": "0.14",
      "dayNtlVlm": "120000.0",
      "circulatingSupply": "1000000.0",
      "coin": "PURR/USDC"
    },
    {
      "markPx": "0.0525",
      "prevDayPx": "0.05",
      "dayNtlVlm": "43000.5",
      "coin": "@107"
    },
    {
      "markPx": "1.0",
      "midPx": "1.0",
      "prevDayPx": "1.0",
      "dayNtlVlm": "5.0",
      "coin": "@5"
    },
    {
      "markPx": "2.0",
      "midPx": "2.0",
      "prevDayPx": "2.0",
      "dayNtlVlm": "6.0",
      "coin": "@6"
    }
  ]
]
''';

const String kClearinghouseStateFixture = '''
{
  "assetPositions": [
    {
      "position": {
        "coin": "ETH",
        "cumFunding": {"allTime": "514.09", "sinceChange": "0.0", "sinceOpen": "0.0"},
        "entryPx": "2986.3",
        "leverage": {"rawUsd": "-95.06", "type": "isolated", "value": 20},
        "liquidationPx": "2866.26",
        "marginUsed": "4.98",
        "maxLeverage": 50,
        "positionValue": "99.65",
        "returnOnEquity": "-0.026",
        "szi": "0.0335",
        "unrealizedPnl": "-0.13"
      },
      "type": "oneWay"
    },
    {
      "position": {
        "coin": "BTC",
        "entryPx": "101000.0",
        "leverage": {"type": "cross", "value": 5},
        "liquidationPx": null,
        "marginUsed": "20.5",
        "maxLeverage": 40,
        "positionValue": "102.5",
        "returnOnEquity": "0.073",
        "szi": "-0.001",
        "unrealizedPnl": "1.5"
      },
      "type": "oneWay"
    },
    {
      "position": {
        "coin": "SOL",
        "entryPx": "0.0",
        "leverage": {"type": "cross", "value": 1},
        "liquidationPx": null,
        "marginUsed": "0.0",
        "positionValue": "0.0",
        "returnOnEquity": "0.0",
        "szi": "0.0",
        "unrealizedPnl": "0.0"
      },
      "type": "oneWay"
    }
  ],
  "crossMaintenanceMarginUsed": "3.1",
  "marginSummary": {
    "accountValue": "342.11",
    "totalMarginUsed": "25.48",
    "totalNtlPos": "202.15",
    "totalRawUsd": "306.66"
  },
  "time": 1708622398623,
  "withdrawable": "310.2"
}
''';

const String kSpotClearinghouseStateFixture = '''
{
  "balances": [
    {"coin": "USDC", "token": 0, "total": "14.625485", "hold": "0.0", "entryNtl": "0.0"},
    {"coin": "TSLA", "token": 10, "total": "100.0", "hold": "25.0", "entryNtl": "5.2"}
  ]
}
''';

const String kFrontendOpenOrdersFixture = '''
[
  {
    "coin": "BTC",
    "isPositionTpsl": false,
    "isTrigger": false,
    "limitPx": "29792.0",
    "oid": 91490942,
    "orderType": "Limit",
    "origSz": "5.0",
    "reduceOnly": false,
    "side": "B",
    "sz": "5.0",
    "timestamp": 1681247412573,
    "triggerCondition": "N/A",
    "triggerPx": "0.0"
  },
  {
    "coin": "ETH",
    "cloid": "0x00000000000000000000000000000001",
    "isPositionTpsl": false,
    "isTrigger": true,
    "limitPx": "2800.0",
    "oid": 91490943,
    "orderType": "Stop Market",
    "origSz": "1.0",
    "reduceOnly": true,
    "side": "A",
    "sz": "0.4",
    "timestamp": 1681247412600,
    "triggerCondition": "Price below 2900",
    "triggerPx": "2900.0"
  }
]
''';

const String kUserFillsFixture = '''
[
  {
    "closedPnl": "0.0",
    "coin": "AVAX",
    "crossed": false,
    "dir": "Open Long",
    "hash": "0xa166e3fa63c25663024b03f2e0da011a00307e4017465df020210d3d432e7cb8",
    "oid": 90542681,
    "px": "18.435",
    "side": "B",
    "startPosition": "26.86",
    "sz": "93.53",
    "time": 1681222254710,
    "fee": "0.01",
    "feeToken": "USDC",
    "tid": 118906512037719
  },
  {
    "closedPnl": "12.75",
    "coin": "@107",
    "crossed": true,
    "dir": "Sell",
    "hash": "0xbb66e3fa63c25663024b03f2e0da011a00307e4017465df020210d3d432e7cb9",
    "oid": 90542700,
    "px": "0.0531",
    "side": "A",
    "sz": "500.0",
    "time": 1681222254999,
    "fee": "0.002",
    "feeToken": "USDC",
    "cloid": "0x000000000000000000000000000000ff",
    "tid": 118906512037720
  }
]
''';

const String kL2BookFixture = '''
{
  "coin": "BTC",
  "time": 1710131872708,
  "levels": [
    [
      {"px": "68674.0", "sz": "0.97139", "n": 4},
      {"px": "68673.0", "sz": "1.62345", "n": 2}
    ],
    [
      {"px": "68675.0", "sz": "0.04396", "n": 1},
      {"px": "68676.0", "sz": "2.5", "n": 3}
    ]
  ]
}
''';

void main() {
  group('HlMarket.parsePerpList', () {
    final markets = HlMarket.parsePerpList(jsonDecode(kMetaAndAssetCtxsFixture));

    test('skips delisted entries but preserves positional assetIds', () {
      expect(markets.length, 3); // OLDCOIN dropped
      expect(markets.map((m) => m.coin), ['BTC', 'ETH', 'SOL']);
      expect(markets[0].assetId, 0);
      expect(markets[1].assetId, 1);
      expect(markets[2].assetId, 3); // position 3, NOT 2
    });

    test('parses meta + ctx fields', () {
      final btc = markets[0];
      expect(btc.kind, HlMarketKind.perp);
      expect(btc.wireCoin, 'BTC');
      expect(btc.szDecimals, 5);
      expect(btc.maxLeverage, 40);
      expect(btc.onlyIsolated, isFalse);
      expect(btc.markPx, 102500.0);
      expect(btc.midPx, 102490.5);
      expect(btc.prevDayPx, 100000.0);
      expect(btc.dayNtlVlm, 1169046.29406);
      expect(btc.funding, 0.0000125);
      expect(btc.openInterest, 688.11);
    });

    test('onlyIsolated flag and negative funding parse', () {
      final eth = markets[1];
      expect(eth.onlyIsolated, isTrue);
      expect(eth.funding, -0.0000021);
    });

    test('maxLeverage defaults to 1 and midPx falls back to markPx', () {
      final sol = markets[2];
      expect(sol.maxLeverage, 1);
      expect(sol.midPx, 150.25); // no midPx in ctx → markPx
    });

    test('dayChangePct math + zero prevDayPx guard', () {
      expect(markets[0].dayChangePct, closeTo(0.025, 1e-9));
      expect(markets[2].dayChangePct, 0); // prevDayPx "0"
    });

    test('pxDecimalCap is 6 - szDecimals for perps', () {
      expect(markets[0].pxDecimalCap, 1); // 6 - 5
      expect(markets[1].pxDecimalCap, 2); // 6 - 4
      expect(markets[2].pxDecimalCap, 4); // 6 - 2
    });

    test('throws FormatException on malformed shapes', () {
      expect(() => HlMarket.parsePerpList(null), throwsFormatException);
      expect(() => HlMarket.parsePerpList([]), throwsFormatException);
      expect(() => HlMarket.parsePerpList({'universe': []}),
          throwsFormatException);
      expect(() => HlMarket.parsePerpList(['not a map', []]),
          throwsFormatException);
    });
  });

  group('HlMarket.marginMode', () {
    // The docs mark `onlyIsolated` deprecated ("means either strictIsolated
    // or noCross") and add `marginMode`; both shapes must parse.
    HlMarket perp(Map<String, Object?> entry) => HlMarket.parsePerpList(
          jsonDecode(jsonEncode([
            {
              'universe': [
                {'name': 'X', 'szDecimals': 1, 'maxLeverage': 3, ...entry}
              ]
            },
            [
              {'markPx': '1.0'}
            ],
          ])),
        ).single;

    test('marginMode drives onlyIsolated when present', () {
      final strict = perp({'marginMode': 'strictIsolated', 'onlyIsolated': true});
      expect(strict.marginMode, 'strictIsolated');
      expect(strict.onlyIsolated, isTrue);
      expect(strict.isolatedMarginLocked, isTrue);

      // marginMode wins over a stale boolean either way.
      final noCross = perp({'marginMode': 'noCross', 'onlyIsolated': false});
      expect(noCross.onlyIsolated, isTrue);
      expect(noCross.isolatedMarginLocked, isFalse);
      expect(perp({'marginMode': 'cross', 'onlyIsolated': true}).onlyIsolated,
          isFalse);
    });

    test('falls back to the deprecated boolean when marginMode is absent', () {
      expect(perp({'onlyIsolated': true}).onlyIsolated, isTrue);
      expect(perp({'onlyIsolated': false}).onlyIsolated, isFalse);
      expect(perp({}).onlyIsolated, isFalse);
      expect(perp({'marginMode': ''}).marginMode, isNull);
      expect(perp({'marginMode': 7, 'onlyIsolated': true}).onlyIsolated, isTrue);
    });

    test('backend catalog entries carry marginMode too', () {
      HlMarket catalog(Map<String, Object?> entry) => HlMarket.parseCatalog({
            'markets': [
              {'coin': 'X', ...entry}
            ]
          }).single;
      expect(catalog({'marginMode': 'noCross'}).onlyIsolated, isTrue);
      expect(catalog({'onlyIsolated': true}).onlyIsolated, isTrue);
      expect(catalog({}).onlyIsolated, isFalse);
    });

    test('copyWith preserves both the mode and the legacy flag', () {
      expect(perp({'marginMode': 'noCross'}).copyWith(category: 'fx').onlyIsolated,
          isTrue);
      expect(perp({'onlyIsolated': true}).copyWith(category: 'fx').onlyIsolated,
          isTrue);
    });
  });

  group('HlMarket.parseSpotList', () {
    final markets =
        HlMarket.parseSpotList(jsonDecode(kSpotMetaAndAssetCtxsFixture));

    test('keeps every USDC-quoted pair, drops the rest', () {
      // @5 is USDH-quoted, @6 has an unresolvable base token.
      expect(markets.length, 2);
      expect(markets.map((m) => m.coin), ['PURR', 'TSLA']);
    });

    test('assetId = 10000 + index FIELD, not list position', () {
      final tsla = markets[1];
      // '@107' sits at list position 1 — the field must win.
      expect(tsla.assetId, 10107);
      expect(markets[0].assetId, 10000);
    });

    test('wireCoin is the universe pair name, coin the base token', () {
      expect(markets[0].coin, 'PURR');
      expect(markets[0].wireCoin, 'PURR/USDC');
      expect(markets[1].coin, 'TSLA');
      expect(markets[1].wireCoin, '@107');
    });

    test('spot metadata: base-token szDecimals, leverage 1, no funding', () {
      final tsla = markets[1];
      expect(tsla.kind, HlMarketKind.spot);
      expect(tsla.isSpot, isTrue);
      expect(tsla.szDecimals, 2);
      expect(tsla.maxLeverage, 1);
      expect(tsla.onlyIsolated, isFalse);
      expect(tsla.funding, isNull);
      expect(tsla.openInterest, isNull);
    });

    test('spot price context + 8-decimal price cap', () {
      final tsla = markets[1];
      expect(tsla.markPx, 0.0525);
      expect(tsla.midPx, 0.0525); // missing midPx → markPx
      expect(tsla.prevDayPx, 0.05);
      expect(tsla.dayNtlVlm, 43000.5);
      expect(tsla.pxDecimalCap, 6); // 8 - 2
      expect(markets[0].pxDecimalCap, 8); // 8 - 0
    });

    test('throws FormatException on malformed shapes', () {
      expect(() => HlMarket.parseSpotList(null), throwsFormatException);
      expect(() => HlMarket.parseSpotList([{}]), throwsFormatException);
    });

    // The venue returns more contexts than listed pairs and not in
    // universe order. Read by position, HYPE took another pair's
    // previous-day price: a 24h change of -100% or +240,000%.
    test('a pair takes the context that names it, not the one at its index',
        () {
      final out = HlMarket.parseSpotList([
        {
          'tokens': [
            {'name': 'USDC', 'szDecimals': 8, 'index': 0},
            {'name': 'HYPE', 'szDecimals': 2, 'index': 150},
            {'name': 'UBTC', 'szDecimals': 5, 'index': 197,
              'fullName': 'Unit Bitcoin'},
            {'name': 'NEW', 'szDecimals': 0, 'index': 300},
          ],
          'universe': [
            {'name': '@107', 'tokens': [150, 0], 'index': 107},
            {'name': '@142', 'tokens': [197, 0], 'index': 142},
            {'name': '@900', 'tokens': [300, 0], 'index': 900},
          ],
        },
        [
          {'coin': '@1', 'markPx': '0.0003', 'prevDayPx': '27.0',
            'dayNtlVlm': '1.0'},
          {'coin': '@142', 'markPx': '85628.0', 'prevDayPx': '84853.0',
            'dayNtlVlm': '17000000.0'},
          {'coin': '@107', 'markPx': '90.5', 'prevDayPx': '89.3',
            'dayNtlVlm': '30000000.0'},
        ],
      ]);
      final hype = out.firstWhere((m) => m.coin == 'HYPE');
      expect(hype.markPx, 90.5);
      expect(hype.prevDayPx, 89.3);
      expect(hype.dayNtlVlm, 30000000.0);
      expect(hype.dayChangeAtOrNull(90.5)! * 100, closeTo(1.34, 0.01));
      final btc = out.firstWhere((m) => m.coin == 'UBTC');
      expect(btc.prevDayPx, 84853.0);
      // A listed pair with no context of its own has no previous price:
      // a dash, never -100% or another pair's numbers.
      final fresh = out.firstWhere((m) => m.coin == 'NEW');
      expect(fresh.prevDayPx, 0);
      expect(fresh.dayChangeAtOrNull(1.0), isNull);
      expect(fresh.dayChangeAtOrNull(0), isNull);
      expect(btc.unitAssetName, 'Bitcoin');
      expect(hype.unitAssetName, isNull);
    });

    test('no 24h change for an untraded pair; a wild mid is read at the mark',
        () {
      HlMarket spot({required double volume}) => HlMarket(
            coin: 'FRCT',
            wireCoin: '@175',
            assetId: 10175,
            kind: HlMarketKind.spot,
            szDecimals: 0,
            maxLeverage: 1,
            onlyIsolated: false,
            markPx: 0.00019,
            midPx: 0.0096,
            prevDayPx: 0.00023,
            dayNtlVlm: volume,
          );
      // Nobody traded it: a dash, not +4,051%.
      expect(spot(volume: 0).dayChangeAtOrNull(0.0096), isNull);
      // Traded, but the book's mid is 50 times the mark: the mark's change.
      expect(spot(volume: 900).dayChangeAtOrNull(0.0096)! * 100,
          closeTo(-17.4, 0.1));
      // A normal mid is used as it is.
      expect(spot(volume: 900).dayChangeAtOrNull(0.0002)! * 100,
          closeTo(-13.0, 0.1));
    });

    test('a spot token icon is <TOKEN>_spot.svg; Unit tokens drop the U', () {
      expect(HlMarket.hlSpotIconUrl('KNTQ', fullName: 'Kinetiq'),
          'https://app.hyperliquid.xyz/coins/KNTQ_spot.svg');
      expect(HlMarket.hlSpotIconUrl('UBTC', fullName: 'Unit Bitcoin'),
          'https://app.hyperliquid.xyz/coins/BTC_spot.svg');
      // Not Unit tokens: the first letter is part of the name.
      expect(HlMarket.hlSpotIconUrl('USDH', fullName: 'USDH'),
          'https://app.hyperliquid.xyz/coins/USDH_spot.svg');
      expect(HlMarket.hlSpotIconUrl('HOP', fullName: 'Hopurr'),
          'https://app.hyperliquid.xyz/coins/HOP_spot.svg');
      expect(HlMarket.hlSpotIconUrl('PURR'),
          'https://app.hyperliquid.xyz/coins/PURR_spot.svg');
    });
  });

  group('HlAccountSnapshot', () {
    final snapshot = HlAccountSnapshot.fromJson(
      perpState:
          jsonDecode(kClearinghouseStateFixture) as Map<String, dynamic>,
      spotState:
          jsonDecode(kSpotClearinghouseStateFixture) as Map<String, dynamic>,
    );

    test('margin summary + withdrawable', () {
      expect(snapshot.accountValue, 342.11);
      expect(snapshot.totalMarginUsed, 25.48);
      expect(snapshot.withdrawable, 310.2);
    });

    test('skips flat (szi == 0) positions', () {
      expect(snapshot.positions.length, 2);
      expect(snapshot.positions.map((p) => p.coin), ['ETH', 'BTC']);
    });

    test('long isolated position parses fully', () {
      final eth = snapshot.positions[0];
      expect(eth.szi, 0.0335);
      expect(eth.isLong, isTrue);
      expect(eth.entryPx, 2986.3);
      expect(eth.positionValue, 99.65);
      expect(eth.unrealizedPnl, -0.13);
      expect(eth.returnOnEquity, -0.026);
      expect(eth.liquidationPx, 2866.26);
      expect(eth.marginUsed, 4.98);
      expect(eth.leverageType, 'isolated');
      expect(eth.isCross, isFalse);
      expect(eth.leverageValue, 20);
      expect(eth.maxLeverage, 50);
    });

    test('short cross position with null liquidationPx', () {
      final btc = snapshot.positions[1];
      expect(btc.szi, -0.001);
      expect(btc.isLong, isFalse);
      expect(btc.liquidationPx, isNull);
      expect(btc.leverageType, 'cross');
      expect(btc.isCross, isTrue);
      expect(btc.leverageValue, 5);
    });

    test('spot balances with hold → available', () {
      expect(snapshot.spotBalances.length, 2);
      final usdc = snapshot.spotBalances[0];
      expect(usdc.coin, 'USDC');
      expect(usdc.total, 14.625485);
      expect(usdc.hold, 0.0);
      expect(usdc.available, 14.625485);
      final tsla = snapshot.spotBalances[1];
      expect(tsla.total, 100.0);
      expect(tsla.hold, 25.0);
      expect(tsla.available, 75.0);
    });

    test('missing spot state yields empty balances', () {
      final perpOnly = HlAccountSnapshot.fromJson(
        perpState:
            jsonDecode(kClearinghouseStateFixture) as Map<String, dynamic>,
      );
      expect(perpOnly.spotBalances, isEmpty);
      expect(perpOnly.positions.length, 2);
    });
  });

  group('HlOpenOrder.fromJson', () {
    final orders = (jsonDecode(kFrontendOpenOrdersFixture) as List)
        .whereType<Map<String, dynamic>>()
        .map(HlOpenOrder.fromJson)
        .toList();

    test('plain limit order', () {
      final o = orders[0];
      expect(o.coin, 'BTC');
      expect(o.oid, 91490942);
      expect(o.isBuy, isTrue); // side B
      expect(o.limitPx, 29792.0);
      expect(o.sz, 5.0);
      expect(o.origSz, 5.0);
      expect(o.timestamp, 1681247412573);
      expect(o.cloid, isNull);
      expect(o.reduceOnly, isFalse);
      expect(o.orderType, 'Limit');
      expect(o.isTrigger, isFalse);
      expect(o.triggerPx, isNull); // 0.0 placeholder suppressed
    });

    test('take profit and stop loss are classified from the venue name', () {
      final tp = HlOpenOrder.fromJson({
        'coin': 'ETH', 'oid': 1, 'side': 'A', 'limitPx': '3100', 'sz': '1',
        'origSz': '1', 'timestamp': 0, 'reduceOnly': true,
        'orderType': 'Take Profit Limit', 'isTrigger': true,
        'triggerPx': '3000', 'tif': 'Alo', 'isPositionTpsl': true,
      });
      expect(tp.tpsl, 'tp');
      expect(tp.isMarketTrigger, isFalse);
      expect(tp.tif, 'Alo');
      expect(tp.isPositionTpsl, isTrue);
      expect(orders[1].tpsl, 'sl');
      expect(orders[1].isMarketTrigger, isTrue);
      expect(orders[0].tpsl, isNull);
      expect(orders[0].tif, 'Gtc');
      // An unknown time in force never reaches the wire as-is.
      final odd = HlOpenOrder.fromJson({
        'coin': 'ETH', 'oid': 2, 'side': 'B', 'limitPx': '1', 'sz': '1',
        'origSz': '1', 'timestamp': 0, 'orderType': 'Limit',
        'tif': 'FrontendMarket',
      });
      expect(odd.tif, 'Gtc');
    });

    test('trigger order with cloid', () {
      final o = orders[1];
      expect(o.isBuy, isFalse); // side A
      expect(o.cloid, '0x00000000000000000000000000000001');
      expect(o.reduceOnly, isTrue);
      expect(o.orderType, 'Stop Market');
      expect(o.isTrigger, isTrue);
      expect(o.triggerPx, 2900.0);
    });
  });

  group('HlFill.fromJson', () {
    final fills = (jsonDecode(kUserFillsFixture) as List)
        .whereType<Map<String, dynamic>>()
        .map(HlFill.fromJson)
        .toList();

    test('buy fill', () {
      final f = fills[0];
      expect(f.coin, 'AVAX');
      expect(f.px, 18.435);
      expect(f.sz, 93.53);
      expect(f.side, 'B');
      expect(f.isBuy, isTrue);
      expect(f.time, 1681222254710);
      expect(f.closedPnl, 0.0);
      expect(f.fee, 0.01);
      expect(f.feeToken, 'USDC');
      expect(f.oid, 90542681);
      expect(f.hash, startsWith('0xa166'));
      expect(f.dir, 'Open Long');
      expect(f.cloid, isNull);
    });

    test('spot sell fill with cloid and pnl', () {
      final f = fills[1];
      expect(f.coin, '@107');
      expect(f.isBuy, isFalse);
      expect(f.closedPnl, 12.75);
      expect(f.cloid, '0x000000000000000000000000000000ff');
    });
  });

  group('HlL2Book.fromJson', () {
    final book =
        HlL2Book.fromJson(jsonDecode(kL2BookFixture) as Map<String, dynamic>);

    test('levels split into best-first bids/asks', () {
      expect(book.coin, 'BTC');
      expect(book.time, 1710131872708);
      expect(book.bids.length, 2);
      expect(book.asks.length, 2);
      expect(book.bids.first.px, 68674.0);
      expect(book.bids.first.sz, 0.97139);
      expect(book.bids.first.n, 4);
      expect(book.asks.first.px, 68675.0);
    });

    test('bestBid/bestAsk/midPx', () {
      expect(book.bestBid, 68674.0);
      expect(book.bestAsk, 68675.0);
      expect(book.midPx, closeTo(68674.5, 1e-9));
    });

    test('empty/missing levels are safe', () {
      final empty = HlL2Book.fromJson(const {'coin': 'X', 'time': 1});
      expect(empty.bids, isEmpty);
      expect(empty.asks, isEmpty);
      expect(empty.bestBid, isNull);
      expect(empty.bestAsk, isNull);
      expect(empty.midPx, isNull);
    });
  });
}
