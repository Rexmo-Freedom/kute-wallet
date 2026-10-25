// The Statistics tab's category donut, its numbers: which category a
// Predictions market and an Investing fill fall under, the all-time
// amounts per category, and the slices (the five largest, then "Other").

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_activity.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/services/portfolio/portfolio_categories.dart';
import 'package:kute/theme/app_theme.dart';

PredictionRecord _record(String market, double totalSize, double avgPrice,
        {DateTime? entered}) =>
    PredictionRecord(
      tokenId: 't-$market-$totalSize',
      conditionId: market,
      open: false,
      redeemable: false,
      size: 0,
      totalSize: totalSize,
      avgPrice: avgPrice,
      entryCostUsd: 0,
      currentPrice: 0,
      realizedPnlUsd: 0,
      unrealizedPnlUsd: 0,
      firstEntryAt: entered,
    );

HlFill _fill(String coin, double px, double sz, {int time = 1}) =>
    HlFill.fromJson({
      'coin': coin,
      'tid': '$coin$px$sz$time',
      'oid': 1,
      'hash': 'h',
      'time': time,
      'startPosition': '0',
      'sz': '$sz',
      'px': '$px',
      'side': 'B',
      'closedPnl': '0',
      'fee': '0',
    });

HlMarket _market(String coin, String wire,
        {bool spot = false, String category = 'crypto', bool hip3 = false}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire,
      assetId: 0,
      kind: spot ? HlMarketKind.spot : HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: 0,
      category: category,
      isHip3: hip3,
      dex: hip3 ? wire.split(':').first : '',
    );

void main() {
  setUp(debugClearPolyCategoryCache);

  group('Predictions categories', () {
    test('a market falls under the most specific of the tab\'s pills', () {
      expect(polyCategoryForTags(['sports', 'nba']), 'sports');
      // Esports games carry the sports tag too.
      expect(polyCategoryForTags(['sports', 'esports', 'cs2']), 'esports');
      expect(polyCategoryForTags(['politics', 'geopolitics', 'iran']),
          'geopolitics');
      expect(polyCategoryForTags(['fed', 'politics', 'economy', 'finance']),
          'finance');
      expect(polyCategoryForTags(['Cryptocurrency']), 'crypto');
      expect(polyCategoryForTags(['pop-culture']), 'culture');
      expect(polyCategoryForTags(['politics', 'trump']), 'politics');
      // Nothing a pill lists: other.
      expect(polyCategoryForTags(['all', 'eu']), kPortfolioOtherCategory);
      expect(polyCategoryForTags(const []), kPortfolioOtherCategory);
    });

    test('the stake per category, all time; unknown markets are other', () {
      final book = PredictionsBook(records: [
        _record('0xa', 20, .4), // 8 on sports
        _record('0xb', 10, .5), // 5 on politics
        _record('0xa', 10, .2), // 2 more on sports
        _record('0xc', 4, .5), // 2 on a market Gamma did not place
        _record('0xd', 0, .5), // nothing put on it
      ]);
      expect(
          predictionCategoryStakes(book, {'0xa': 'sports', '0xb': 'politics'}),
          {'sports': 10, 'politics': 5, kPortfolioOtherCategory: 2});
    });

    test('markets are read once a session; the ones not answered are other',
        () async {
      final asked = <List<String>>[];
      Future<Map<String, Set<String>>> fetch(List<String> ids) async {
        asked.add(ids);
        return {
          for (final id in ids)
            if (id != '0xgone') id: id == '0xa' ? {'crypto'} : {'weather'},
        };
      }

      final first =
          await resolvePolyCategories(['0xA', '0xb', '0xgone', ''], fetch);
      expect(first, {'0xa': 'crypto', '0xb': 'weather', '0xgone': 'other'});
      expect(asked, [
        ['0xa', '0xb', '0xgone']
      ]);
      // Placed markets are not read again; the unanswered one is.
      await resolvePolyCategories(['0xa', '0xb', '0xgone'], fetch);
      expect(asked.last, ['0xgone']);
    });
  });

  group('Investing categories', () {
    test('a fill falls under its market\'s class', () {
      expect(hlFillCategory('BTC', _market('BTC', 'BTC')), 'crypto');
      expect(hlFillCategory('BTC', null), 'crypto');
      expect(
          hlFillCategory('xyz:TSLA',
              _market('xyz:TSLA', 'xyz:TSLA', category: 'stocks', hip3: true)),
          'stocks');
      expect(
          hlFillCategory(
              'xyz:GOLD',
              _market('xyz:GOLD', 'xyz:GOLD',
                  category: 'commodities', hip3: true)),
          'commodities');
      // A builder dex's market the venue gives no class, or not known.
      expect(
          hlFillCategory('abc:RATE',
              _market('abc:RATE', 'abc:RATE', category: 'rates', hip3: true)),
          kPortfolioOtherCategory);
      expect(hlFillCategory('abc:RATE', null), kPortfolioOtherCategory);
      // Spot: a plain token is spot, a tracker its class.
      expect(
          hlFillCategory('@107', _market('HYPE', '@107', spot: true)), 'spot');
      expect(hlFillCategory('@107', null), 'spot');
      expect(hlFillCategory('@9', _market('SPY', '@9', spot: true)), 'indices');
      expect(hlFillCategory('@3', _market('XAUT0', '@3', spot: true)),
          'commodities');
    });

    test('the notional per category, all time, whatever the fills\' dates', () {
      final markets = {
        'xyz:TSLA':
            _market('xyz:TSLA', 'xyz:TSLA', category: 'stocks', hip3: true),
        '@107': _market('HYPE', '@107', spot: true),
      };
      final book = TradingBook(fills: [
        _fill('BTC', 60000, 0.1, time: 1),
        _fill('ETH', 2000, 1, time: 1 << 40),
        _fill('xyz:TSLA', 250, 4),
        _fill('@107', 40, 5),
        _fill('unknown:X', 10, 1),
      ]);
      expect(tradingCategoryVolumes(book, markets), {
        'crypto': 8000,
        'stocks': 1000,
        'spot': 200,
        kPortfolioOtherCategory: 10,
      });
    });

    test('a cut list has no all-time split', () {
      final book = TradingBook(fills: [_fill('BTC', 1, 1)], complete: false);
      expect(tradingCategoryVolumes(book, const {}), isNull);
    });
  });

  group('slices', () {
    test('largest first, five of their own, the rest with other as "Other"',
        () {
      final slices = categorySlices({
        'sports': 30,
        'crypto': 50,
        'politics': 10,
        'finance': 4,
        'tech': 3,
        'weather': 2,
        kPortfolioOtherCategory: 1,
        'culture': 0,
        'economy': -5,
        'mentions': double.nan,
      });
      expect(slices.map((s) => s.key), [
        'crypto',
        'sports',
        'politics',
        'finance',
        'tech',
        kPortfolioOtherCategory,
      ]);
      expect(slices.map((s) => s.rank), [1, 2, 3, 4, 5, 6]);
      expect(slices.last.kind, CategorySliceKind.other);
      // Weather (2) and the unknown (1) together.
      expect(slices.last.value, 3);
      expect(slices.map((s) => s.percent).reduce((a, b) => a + b), 100);
      expect(slices.map((s) => s.fraction).reduce((a, b) => a + b),
          closeTo(1, 1e-9));
    });

    test('a sixth category on its own keeps its slice', () {
      final slices =
          categorySlices({'a': 6, 'b': 5, 'c': 4, 'd': 3, 'e': 2, 'f': 1});
      expect(slices.length, 6);
      expect(slices.every((s) => s.kind == CategorySliceKind.category), isTrue);
    });

    test('whole percents always add up to 100', () {
      for (final values in [
        {'a': 1.0, 'b': 1.0, 'c': 1.0},
        {'a': 1000.0, 'b': 1.0, 'c': 1.0, 'd': 1.0},
        {'a': 33.3, 'b': 33.3, 'c': 33.4},
      ]) {
        final slices = categorySlices(values);
        expect(slices.map((s) => s.percent).reduce((a, b) => a + b), 100,
            reason: '$values');
      }
    });

    test('nothing worth anything has no slices', () {
      expect(categorySlices(const {}), isEmpty);
      expect(categorySlices({'a': 0, 'b': -1}), isEmpty);
    });
  });

  group('donut engine', () {
    test(
        'the chart palette: five distinct muted hues per mode and a grey, '
        'none of them the accent or the market pair, every one clear of '
        'the card', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
      }

      final light = AppColorsExtension.light();
      final dark = AppColorsExtension.dark();
      for (final c in [light, dark]) {
        final palette = c.chartCategorical;
        expect(palette.length, 6);
        expect(palette.toSet().length, 6);
        for (final color in palette) {
          expect(color, isNot(c.accent));
          expect(color, isNot(AppColors.marketUp));
          expect(color, isNot(AppColors.marketDown));
          expect(contrast(color, c.surface), greaterThanOrEqualTo(3),
              reason: '$color on ${c.surface}');
        }
        // Distinct hues (indigo, teal, amber, coral, violet): every pair of
        // colours sits at least 25 degrees apart on the colour wheel, so
        // neighbouring slices never read as one.
        final hues = [
          for (final color in palette.take(5)) HSLColor.fromColor(color).hue
        ];
        for (var i = 0; i < hues.length; i++) {
          for (var j = i + 1; j < hues.length; j++) {
            final d = (hues[i] - hues[j]).abs();
            expect(math.min(d, 360 - d), greaterThanOrEqualTo(25),
                reason: '${palette[i]} vs ${palette[j]}');
          }
        }
        // Other's grey is the last slot: no hue to speak of.
        final grey = HSLColor.fromColor(palette.last);
        expect(grey.saturation, lessThan(0.15));
        expect(c.chartOther, palette.last);
      }
      // Each mode is stepped for its own surface.
      expect(light.chartCategorical, isNot(dark.chartCategorical));
    });

    test('colours follow rank by size, slivers and the sixth are grey', () {
      for (final c in [AppColorsExtension.light(), AppColorsExtension.dark()]) {
        final ramp = c.chartCategorical;
        // Given out of order: the largest takes the deepest step.
        expect(c.chartColorsByShare([0.10, 0.58, 0.01, 0.23, 0.08]),
            [ramp[2], ramp[0], c.chartOther, ramp[1], ramp[3]]);
        // A sixth slice past the ramp wears the grey, as does "Other".
        expect(c.chartColorsByShare([0.3, 0.2, 0.15, 0.12, 0.1, 0.08, -1]), [
          ...ramp.take(5),
          c.chartOther,
          c.chartOther,
        ]);
        // Exactly 2% keeps its step.
        expect(c.chartColorsByShare([0.98, 0.02]), [ramp[0], ramp[1]]);
      }
    });

    test('a donut\'s slices by key: the ramp by rank, Other grey', () {
      final c = AppColorsExtension.light();
      final slices = categorySlices({
        'spark': 58,
        'investments': 23,
        'onchain': 10,
        'predictions': 8,
        'lightning': 1
      });
      final colors = chartSliceColors(c, slices);
      expect(colors['spark'], c.chartCategorical[0]);
      expect(colors['investments'], c.chartCategorical[1]);
      expect(colors['onchain'], c.chartCategorical[2]);
      expect(colors['predictions'], c.chartCategorical[3]);
      expect(colors['lightning'], c.chartOther);
    });

    test('an angle finds its slice, clockwise from twelve o\'clock', () {
      final f = kuteDonutFractions([50, 25, 25, -3]);
      expect(f, [.5, .25, .25, 0]);
      expect(kuteDonutIndexAtAngle(0.1, f), 0);
      expect(kuteDonutIndexAtAngle(math.pi * 1.2, f), 1);
      expect(kuteDonutIndexAtAngle(math.pi * 1.9, f), 2);
      expect(kuteDonutIndexAtAngle(1, const []), isNull);
    });
  });
}
