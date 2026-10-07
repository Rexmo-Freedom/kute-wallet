import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/polymarket_artwork.dart';
import 'package:kute/models/polymarket_model.dart';

void main() {
  const host = 'https://polymarket-upload.s3.us-east-2.amazonaws.com';
  final teams = [
    PolymarketTeam.fromJson({
      'name': 'Brentford FC',
      'alias': 'Brentford',
      'abbreviation': 'bre',
      'logo': '$host/Brentford FC-0585de7d82.png',
    }),
    PolymarketTeam.fromJson({
      'name': 'Chelsea FC',
      'alias': 'Chelsea',
      'abbreviation': 'che',
      'logo': '$host/Chelsea FC-a99798da02.png',
    }),
  ];

  test('both FC teams retain their own provider crest regardless of order', () {
    for (final order in [teams, teams.reversed.toList()]) {
      expect(
          PolymarketEvent.logoFromTeams(order, 'Brentford FC'), teams[0].logo);
      expect(PolymarketEvent.logoFromTeams(order, 'Chelsea FC'), teams[1].logo);
      expect(PolymarketEvent.logoFromTeams(order, 'Chelsea'), teams[1].logo);
      expect(PolymarketEvent.logoFromTeams(order, 'CHE'), teams[1].logo);
      expect(PolymarketEvent.logoFromTeams(order, 'FC'), isNull);
    }
  });

  test('ambiguous shortened team names never select an arbitrary badge', () {
    const manchester = [
      PolymarketTeam(name: 'Manchester City FC', logo: '$host/city.png'),
      PolymarketTeam(name: 'Manchester United FC', logo: '$host/united.png'),
    ];
    expect(PolymarketEvent.logoFromTeams(manchester, 'Manchester'), isNull);
    expect(PolymarketEvent.logoFromTeams(manchester, 'Manchester United'),
        '$host/united.png');
    expect(
        PolymarketEvent.logoForText(teams, 'Will Chelsea win?'), teams[1].logo);
    expect(
        PolymarketEvent.logoForText(teams, 'Brentford FC vs Chelsea FC draw?'),
        isNull);
  });

  test('raw and already escaped image URLs normalize identically', () {
    expect(
        polymarketArtworkUrl('$host/Chelsea FC.png'), '$host/Chelsea%20FC.png');
    expect(polymarketArtworkUrl('$host/Chelsea%20FC.png'),
        '$host/Chelsea%20FC.png');
    expect(polymarketArtworkUrl('$host/FK Bodø/Glimt.png'),
        '$host/FK%20Bod%C3%B8/Glimt.png');
    expect(polymarketArtworkUrl('  '), isNull);
    expect(polymarketArtworkUrl('javascript:alert(1)'), isNull);
  });

  test('empty event image falls back to optimized or actual child metadata',
      () {
    final model = PolymarketModel();
    addTearDown(model.dispose);
    final events = model.parseEventsRaw([
      {
        'id': 'event-1',
        'slug': 'netflix-event',
        'title': 'Netflix event',
        'image': '',
        'icon': ' ',
        'imageOptimized': {'imageUrlOptimized': '$host/Netflix art.webp'},
        'markets': <Map<String, dynamic>>[],
      },
      {
        'id': 'event-2',
        'slug': 'child-art-event',
        'title': 'Child art event',
        'image': '',
        'markets': [
          {
            'id': 'm1',
            'image': '',
            'icon': '',
            'outcomes': '["Yes","No"]',
            'outcomePrices': '["0.4","0.6"]'
          },
          {
            'id': 'm2',
            'image': '',
            'groupItemImage': '',
            'iconOptimized': {'imageUrlOptimized': '$host/real-child.svg'},
            'outcomes': '["Yes","No"]',
            'outcomePrices': '["0.6","0.4"]'
          },
        ],
      },
    ]);
    expect(events[0].imageUrl, '$host/Netflix%20art.webp');
    expect(events[1].imageUrl, '$host/real-child.svg');
    expect(events[1].outcomes[1].imageUrl, '$host/real-child.svg');
    expect(events[1].outcomes[1].gammaMarketId, 'm2');
  });
}
