// Which events the market page draws as a map or as race bars, read the
// way the page reads them (PolymarketModel.parseEventsRaw) from real Gamma
// events (special_event_fixtures.dart), and the chances the drawing
// shows.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/us_states.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/special_event_map.dart';

import 'special_event_fixtures.dart';

PolymarketEvent _event(Map<String, dynamic> raw) =>
    PolymarketModel().parseEventsRaw([raw]).single;

double? _shown(PolymarketOutcome o) => o.unpriced ? null : o.price;

void main() {
  group('state names', () {
    test('a code in capitals or a name in any case', () {
      expect(usStateCodeOf('TX'), 'TX');
      expect(usStateCodeOf('Texas'), 'TX');
      expect(usStateCodeOf(' new hampshire '), 'NH');
      expect(usStateCodeOf('Washington'), 'WA');
      expect(usStateCodeOf('Washington, D.C.'), 'DC');
      // Words that are codes only in capitals.
      expect(usStateCodeOf('or'), isNull);
      expect(usStateCodeOf('in'), isNull);
      expect(usStateCodeOf('United States'), isNull);
      expect(usStateCodeOf('Georgia Tech'), isNull);
    });
  });

  group('Build your map by state lists', () {
    test('the Senate swing states: 7 states, Republicans, 128 maps', () {
      final special = polySpecialEventOf(_event(buildYourMapSenateRaw()));
      expect(special, isA<PolyStateCombos>());
      final map = special as PolyStateCombos;
      expect(map.states, ['AK', 'IA', 'KS', 'ME', 'MI', 'OH', 'TX']);
      expect(map.sides, [PolyMapSide.rep, PolyMapSide.notRep]);
      expect(map.lead, PolyMapSide.rep);
      expect(map.combos, hasLength(128));
      final all = map.combos.firstWhere((c) => c.outcome.name == 'All 7');
      expect(all.picks.values.toSet(), {PolyMapSide.rep});
      final none = map.combos.firstWhere((c) => c.outcome.name == 'None');
      expect(none.picks.values.toSet(), {PolyMapSide.notRep});
      final ak = map.combos.firstWhere((c) => c.outcome.name == 'AK');
      expect(ak.picks['AK'], PolyMapSide.rep);
      expect(ak.picks['TX'], PolyMapSide.notRep);
    });

    test('each state is every map that has it Republican, added up', () {
      final map = polySpecialEventOf(_event(buildYourMapSenateRaw()))
          as PolyStateCombos;
      final odds = polyComboStateOdds(map, _shown);
      // "None" at 96.7% and "AK" at 3.35% (its midpoint) carry nearly
      // everything: Alaska is the one state with a real Republican
      // chance.
      final ak = odds['AK']!;
      expect(ak[PolyMapSide.rep]! + ak[PolyMapSide.notRep]!,
          closeTo(1, 1e-9));
      expect(ak[PolyMapSide.rep], greaterThan(0.03));
      expect(ak[PolyMapSide.rep], lessThan(0.1));
      expect(odds['TX']![PolyMapSide.rep], lessThan(0.05));
      expect(polyStatesFavouring(odds, PolyMapSide.rep), 0);
      expect(polyMostLikelyCombo(map, _shown)!.outcome.name, 'None');
    });

    test('picking every state lands on its one market', () {
      final map = polySpecialEventOf(_event(buildYourMapSenateRaw()))
          as PolyStateCombos;
      final picks = {
        for (final s in map.states)
          s: s == 'AK' || s == 'TX' ? PolyMapSide.rep : PolyMapSide.notRep,
      };
      expect(map.comboFor(picks)!.outcome.name, 'AK, TX');
      expect(map.comboFor({for (final s in map.states) s: PolyMapSide.rep})!
          .outcome
          .name, 'All 7');
    });
  });

  group('Build your map by party per state', () {
    test('Senate Combo with an independent: MT is Republican or '
        'independent, never Democratic', () {
      final map = polySpecialEventOf(_event(senateComboMsScMtRaw()))
          as PolyStateCombos;
      // The title's order; "Other" (switched off) is not a map.
      expect(map.states, ['MS', 'SC', 'MT']);
      expect(map.sides,
          [PolyMapSide.rep, PolyMapSide.dem, PolyMapSide.ind]);
      expect(map.combos, hasLength(8));
      expect(map.sidesOf('MT'), [PolyMapSide.rep, PolyMapSide.ind]);
      expect(map.sidesOf('SC'), [PolyMapSide.rep, PolyMapSide.dem]);
      final sweep = map.combos.firstWhere((c) => c.outcome.name == 'Reps sweep');
      expect(sweep.picks,
          {'MS': PolyMapSide.rep, 'SC': PolyMapSide.rep, 'MT': PolyMapSide.rep});
      expect(
          map.comboFor({
            'MS': PolyMapSide.rep,
            'SC': PolyMapSide.dem,
            'MT': PolyMapSide.ind,
          })!
              .outcome
              .name,
          'Reps MS, Dems SC, Ind MT');
      // A way no market lists.
      expect(
          map.comboFor({
            'MS': PolyMapSide.rep,
            'SC': PolyMapSide.rep,
            'MT': PolyMapSide.dem,
          }),
          isNull);
    });

    test('Governor Combo: Texas, Oregon, Vermont', () {
      final map = polySpecialEventOf(_event(governorComboTxOrVtRaw()))
          as PolyStateCombos;
      expect(map.states, ['TX', 'OR', 'VT']);
      expect(map.sides, [PolyMapSide.rep, PolyMapSide.dem]);
      final odds = polyComboStateOdds(map, _shown);
      // "Dems TX & OR, Reps VT" is settled in all but name at 99.95%.
      expect(polyLeadingSide(odds['TX'])!.side, PolyMapSide.dem);
      expect(polyLeadingSide(odds['VT'])!.side, PolyMapSide.rep);
      expect(polyStatesFavouring(odds, PolyMapSide.rep), 1);
      expect(polyMostLikelyCombo(map, _shown)!.outcome.name,
          'Dems TX & OR, Reps VT');
    });
  });

  group('Balance of power', () {
    test('2026 midterms: Senate and House, Democrats both', () {
      final b = polySpecialEventOf(_event(balanceOfPowerRaw()))
          as PolyBalanceOfPower;
      expect(b.races, ['Senate', 'House']);
      expect(b.cells, hasLength(4)); // "Other" is not a split
      final odds = polyRaceOdds(b, _shown);
      expect(odds['Senate']![PolyMapSide.dem], closeTo(0.9985, 0.001));
      expect(odds['House']![PolyMapSide.rep], lessThan(0.01));
    });

    test('a state\'s Senate and Governor combo: Gov and Senate', () {
      final b = polySpecialEventOf(_event(kansasSenateGovernorRaw()))
          as PolyBalanceOfPower;
      // "Dems win Gov, Reps win Senate" closed: only its mirror is a
      // split, which is enough.
      expect(b.races, ['Gov', 'Senate']);
      expect(b.cells, hasLength(3));
      final odds = polyRaceOdds(b, _shown);
      expect(polyLeadingSide(odds['Gov'])!.side, PolyMapSide.dem);
    });

    test('Presidency + Popular Vote (settled) reads as races too', () {
      final b = polySpecialEventOf(_event(presidencyPopularVoteRaw()))
          as PolyBalanceOfPower;
      expect(b.races, ['Presidency', 'Popular Vote']);
      final odds = polyRaceOdds(b, _shown);
      expect(odds['Presidency']![PolyMapSide.rep], closeTo(1, 1e-9));
    });
  });

  group('one market per state', () {
    test('Trump state visits: the open states, each its own market', () {
      final event = _event(trumpStateVisitsRaw());
      final m = polySpecialEventOf(event) as PolyStateMarkets;
      // Visited states have closed; the page lists the open ones.
      expect(m.byState.length, event.outcomes.length);
      expect(m.byState.keys, containsAll(['AR', 'CO', 'HI', 'WY']));
      expect(m.byState.keys, isNot(contains('TX')));
      expect(m.byState['AR']!.name, 'Arkansas');
    });
  });

  group('not special', () {
    test('countries, a conditional combo and a seat grid list as before',
        () {
      expect(polySpecialEventOf(_event(ebolaCountriesRaw())), isNull);
      expect(polySpecialEventOf(_event(demSweepRecessionRaw())), isNull);
      expect(polySpecialEventOf(_event(senateHouseSeatsRaw())), isNull);
    });

    test('a sports event naming states is never a map', () {
      PolymarketOutcome o(String name) =>
          PolymarketOutcome(name: name, price: 0.2, tokenId: name);
      final event = PolymarketEvent(
        id: '1',
        slug: 'cfp',
        title: 'College Football: which state school wins?',
        volume: 0,
        liquidity: 0,
        category: 'sports',
        conditionId: '',
        outcomes: [o('Texas'), o('Georgia'), o('Oregon'), o('Alabama')],
      );
      expect(polySpecialEventOf(event), isNull);
    });

    test('single states without "states" in the title, under eight', () {
      PolymarketOutcome o(String name) =>
          PolymarketOutcome(name: name, price: 0.2, tokenId: name);
      final event = PolymarketEvent(
        id: '1',
        slug: 'x',
        title: 'Where will the summit be held?',
        volume: 0,
        liquidity: 0,
        category: 'politics',
        conditionId: '',
        outcomes: [o('Texas'), o('Georgia'), o('Florida'), o('Paris')],
      );
      expect(polySpecialEventOf(event), isNull);
    });
  });
}
