// A search that names a Predictions category puts that category first:
// a topic by its name or slug, a sport, an esports game, a league by its
// name or code, a localized name through the venue search's aliases; never
// a prefix.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/search/search_category_match.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations en;
  late AppLocalizations pt;
  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    pt = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  const leagues = [
    PolySub('series:10193', route: 'lal', label: 'LaLiga'),
    PolySub('series:12185', route: 'nfl', label: 'NFL'),
  ];

  test('a topic by its name or slug, in the app\'s language', () {
    final art = polySearchCategoryHit('Art', en)!;
    expect(art.pill, PolyPill.art);
    expect(art.sub, isNull);
    expect(art.label, 'Art');
    expect(art.selection.pill, PolyPill.art);
    expect(art.key, 'art');
    expect(polySearchCategoryHit('pop-culture', en)!.pill, PolyPill.culture);
    expect(polySearchCategoryHit('Culture', en)!.pill, PolyPill.culture);
    expect(polySearchCategoryHit('geopolítica', pt)!.pill, PolyPill.geopolitics);
    expect(polySearchCategoryHit('Eleições', pt)!.pill, PolyPill.elections);
    expect(polySearchCategoryHit(' politics ', en)!.pill, PolyPill.politics);
  });

  test('a sport, an esports game, a league by name or code', () {
    final soccer = polySearchCategoryHit('soccer', en)!;
    expect(soccer.pill, PolyPill.sports);
    expect(soccer.sub, 'soccer');
    expect(soccer.label, 'Soccer');
    expect(soccer.selection.sub, 'soccer');
    expect(soccer.key, 'sports/soccer');
    // Combat's chip is Gamma's `mma`.
    expect(polySearchCategoryHit('Combat', en)!.sub, 'mma');
    expect(polySearchCategoryHit('mma', en)!.sub, 'mma');
    expect(polySearchCategoryHit('Table tennis', en)!.sub, 'table-tennis');
    final cs2 = polySearchCategoryHit('CS2', en)!;
    expect(cs2.pill, PolyPill.esports);
    expect(cs2.sub, 'cs2');
    expect(polySearchCategoryHit('dota 2', en)!.sub, 'dota-2');
    final nfl = polySearchCategoryHit('nfl', en, leagues: leagues)!;
    expect(nfl.pill, PolyPill.sports);
    expect(nfl.sub, 'series:12185');
    expect(nfl.label, 'NFL');
    expect(polySearchCategoryHit('laliga', en, leagues: leagues)!.sub,
        'series:10193');
    expect(polySearchCategoryHit('lal', en, leagues: leagues)!.sub,
        'series:10193');
    // Without the league list a league is not known.
    expect(polySearchCategoryHit('nfl', en), isNull);
  });

  test('a localized name goes through the venue search\'s aliases', () {
    expect(polySearchCategoryHit('futebol', pt)!.sub, 'soccer');
    expect(polySearchCategoryHit('fútbol', en)!.sub, 'soccer');
    expect(polySearchCategoryHit('eleições', en)!.pill, PolyPill.elections);
  });

  test('never a prefix, never a market title, nothing for an empty query',
      () {
    expect(polySearchCategoryHit('ten', en), isNull);
    expect(polySearchCategoryHit('art market sales', en), isNull);
    expect(polySearchCategoryHit('bitcoin', en), isNull);
    expect(polySearchCategoryHit('', en), isNull);
    expect(polySearchCategoryHit('  ', en), isNull);
  });

  test('a category the policy withholds is not offered', () {
    final pills = [
      for (final p in PolyPill.values)
        if (p != PolyPill.sports && p != PolyPill.esports) p
    ];
    expect(polySearchCategoryHit('soccer', en, pills: pills), isNull);
    expect(polySearchCategoryHit('cs2', en, pills: pills), isNull);
    expect(polySearchCategoryHit('nfl', en, pills: pills, leagues: leagues),
        isNull);
    expect(polySearchCategoryHit('art', en, pills: pills), isNotNull);
  });
}
