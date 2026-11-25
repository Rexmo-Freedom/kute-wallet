// Search puts the markets ABOUT what was typed first (founder, 12 November
// 2026): "porto" in Predictions listed "UEFA Champions League: 2027
// Champion", where Porto is one of 36 teams, above Porto's own games. The
// fixture is Gamma's real `public-search?q=porto` answer of that day,
// trimmed (test/fixtures/polymarket_search/public_search_porto.json).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/search/search_result_order.dart';
import 'package:kute/theme/app_theme.dart';

/// The day the fixture was read: Porto's games are still to play.
final _now = DateTime.utc(2026, 11, 12, 12);

Future<List<PolymarketEvent>> _portoResults() async {
  final body =
      File('test/fixtures/polymarket_search/public_search_porto.json')
          .readAsStringSync();
  final model = PolymarketModel(
      searchClient: MockClient((request) async {
    expect(request.url.queryParameters['q'], 'porto');
    return http.Response.bytes(utf8.encode(body), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }));
  final events = await model.searchEvents('porto');
  model.dispose();
  return events;
}

PolymarketEvent _event(String title,
        {double volume = 0,
        List<PolymarketOutcome>? outcomes,
        List<String> tags = const [],
        String? slug}) =>
    PolymarketEvent(
      id: title,
      slug: slug ?? title,
      title: title,
      volume: volume,
      liquidity: 5000,
      category: 'other',
      conditionId: title,
      tags: tags,
      outcomes: outcomes ??
          const [
            PolymarketOutcome(name: 'Yes', price: 0.5),
            PolymarketOutcome(name: 'No', price: 0.5),
          ],
    );

HlMarketSearchResult _hl(String coin, {String? name}) => HlMarketSearchResult(
      coin: coin,
      wireCoin: coin,
      kind: HlMarketKind.perp,
      isStock: false,
      name: name,
      category: 'crypto',
      iconUrl: null,
      markPx: 1,
      dayChangePct: 0,
    );

void main() {
  group('"porto" in Predictions', () {
    test('Porto\'s own games lead, soonest first; the many-team markets '
        'follow, most traded first', () async {
      final events = await _portoResults();
      // Gamma's page as the app reads it: most traded first, so the
      // Champions League winner (72.9 M) led and the games trailed.
      expect(events.first.title, 'UEFA Champions League: 2027 Champion');

      final ranked =
          rankPredictionResults(events, (e) => e, query: 'porto', now: _now);
      final titles = [for (final e in ranked) e.title];
      final about = titles.where((t) => t.contains('Porto')).toList();
      // Every event whose title names Porto comes before every other one.
      expect(titles.take(about.length), about);
      // The games still to play lead, soonest first.
      expect(titles.take(3), [
        'Joventut vs. Porto', // 17 November
        'FC Porto vs. USC Paredes', // 20 November
        'Feyenoord Rotterdam vs. FC Porto', // 24 November
      ]);
      // Then the markets where Porto is one outcome among many, the most
      // traded first: the Champions League winner leads them.
      final rest = titles.skip(about.length).toList();
      expect(rest, isNotEmpty);
      expect(rest.first, 'UEFA Champions League: 2027 Champion');
      expect(
          rest,
          containsAllInOrder([
            'UEFA Champions League: 2027 Champion',
            'UEFA Champions League: Team to advance to 2027 Round of 16',
            'UEFA Champions League: Team to Finish 9th-24th in League Phase',
            'Primeira Liga: 2027 Champion',
            'UEFA Champions League: League Phase Winner',
          ]));
    });

    test('a many-team market shows Porto\'s chance, not the leader\'s',
        () async {
      final events = await _portoResults();
      final champion = events
          .firstWhere((e) => e.title == 'Primeira Liga: 2027 Champion');
      final porto = predictionMatchedOutcome('porto', champion);
      expect(porto, isNotNull);
      expect(porto!.name, 'Porto');
      expect(SearchPredictionRow.chanceFractionOf(champion, outcome: porto),
          porto.price);
      expect(SearchPredictionRow.chanceOf(champion, outcome: porto),
          '${(porto.price * 100).round()}%');

      final r16 = events.firstWhere((e) =>
          e.title == 'UEFA Champions League: Team to advance to 2027 Round of 16');
      final r16Porto = predictionMatchedOutcome('porto', r16)!;
      expect(r16Porto.name, 'Porto');
      // The leader's chance is what the row showed before.
      expect(SearchPredictionRow.chanceFractionOf(r16),
          isNot(r16Porto.price));

      // A game about Porto shows its own chance: nothing singled out.
      final game =
          events.firstWhere((e) => e.title == 'FC Porto vs. USC Paredes');
      expect(predictionMatchedOutcome('porto', game), isNull);
    });

    testWidgets('the row reads the outcome and its chance', (tester) async {
      final event = _event('UEFA Champions League: 2027 Champion',
          outcomes: const [
            PolymarketOutcome(name: 'Arsenal', price: 0.24),
            PolymarketOutcome(name: 'Porto', price: 0.02),
          ]);
      final porto = predictionMatchedOutcome('porto', event);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: SearchPredictionRow(
                event: event, outcome: porto, onTap: () {}),
          ),
        ),
      ));
      expect(find.text('Porto'), findsOneWidget);
      expect(find.text('2%'), findsOneWidget);
      expect(find.text('24%'), findsNothing);
    });
  });

  group('matching', () {
    test('whole words, never inside another word', () {
      final ranked = rankPredictionResults(
        [
          _event('Will the jobs report beat estimates?', volume: 900),
          _event('Will Porto win the league?', volume: 1),
        ],
        (e) => e,
        query: 'porto',
        now: _now,
      );
      expect(ranked.first.title, 'Will Porto win the league?');
      // "port" while typing starts the word Porto, not "report".
      final typing = rankPredictionResults(
        [
          _event('Will the jobs report beat estimates?', volume: 900),
          _event('Will Porto win the league?', volume: 1),
        ],
        (e) => e,
        query: 'port',
        now: _now,
      );
      expect(typing.first.title, 'Will Porto win the league?');
    });

    test('accents, case, club tags and every word of a longer query', () {
      final events = [
        _event('Primeira Liga: 2027 Champion', volume: 900, outcomes: const [
          PolymarketOutcome(name: 'Benfica', price: 0.4),
          PolymarketOutcome(name: 'Porto', price: 0.3),
        ]),
        _event('FC Porto vs. SL Benfica', volume: 5),
        _event('Will Grêmio win?', volume: 1),
      ];
      expect(
          rankPredictionResults(events, (e) => e, query: 'FC PORTO', now: _now)
              .first
              .title,
          'FC Porto vs. SL Benfica');
      expect(
          rankPredictionResults(events, (e) => e,
                  query: 'porto benfica', now: _now)
              .first
              .title,
          'FC Porto vs. SL Benfica');
      expect(
          rankPredictionResults(events, (e) => e, query: 'gremio', now: _now)
              .first
              .title,
          'Will Grêmio win?');
    });

    test('a tag ranks above an outcome among many', () {
      final ranked = rankPredictionResults(
        [
          _event('Who wins the 2026-27 title?', volume: 900, outcomes: const [
            PolymarketOutcome(name: 'Primeira Liga XI', price: 0.4),
            PolymarketOutcome(name: 'Other', price: 0.6),
          ]),
          _event('Top scorer 2026-27', volume: 1, tags: const ['primeira-liga']),
        ],
        (e) => e,
        query: 'primeira liga',
        now: _now,
      );
      expect(ranked.first.title, 'Top scorer 2026-27');
    });

    test('a localized name finds its English title first', () {
      final ranked = rankPredictionResults(
        [
          _event('2026 World Cup Winner', volume: 900, outcomes: const [
            PolymarketOutcome(name: 'Brazil', price: 0.1),
            PolymarketOutcome(name: 'Spain', price: 0.2),
          ]),
          _event('Brazil Presidential Election', volume: 10),
        ],
        (e) => e,
        query: 'brasil',
        now: _now,
      );
      expect(ranked.first.title, 'Brazil Presidential Election');
    });

    test('within a step: in play, then the most traded', () {
      final ranked = rankPredictionResults(
        [
          _event('Brazil vs. Argentina', volume: 1),
          _event('Lula flips Bolsonaro for Brazil president?', volume: 900),
          _event('Brazil live game', volume: 5),
        ],
        (e) => e,
        query: 'brazil',
        isLive: (e) => e.title == 'Brazil live game',
        now: _now,
      );
      expect([for (final e in ranked) e.title], [
        'Brazil live game',
        'Lula flips Bolsonaro for Brazil president?',
        'Brazil vs. Argentina',
      ]);
    });
  });

  test('investing: the exact ticker, then a name that starts with it, then '
      'one that only holds it', () {
    final ranked = rankInvestingResults('sol', [
      _hl('ASOL', name: 'Aave Solana'),
      _hl('SOLV', name: 'Solv Protocol'),
      _hl('SOL', name: 'Solana'),
    ]);
    expect([for (final r in ranked) r.coin], ['SOL', 'SOLV', 'ASOL']);
  });
}
