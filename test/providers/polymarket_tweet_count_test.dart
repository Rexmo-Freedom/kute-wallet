import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_tweet_count_provider.dart';

void main() {
  final uri =
      Uri.parse('https://gamma-api.polymarket.com/events/1083683/tweet-count');

  test('reads the tally Gamma serves', () async {
    final client = MockClient((_) async => http.Response(
        '{"\$schema":"https://gamma-api.polymarket.com/schemas/EventTweetCount.json","tweetCount":167}',
        200));
    expect(await readPolyTweetCount(client, uri), 167);
  });

  test('fails silently: errors, other statuses and odd bodies are null',
      () async {
    expect(
        await readPolyTweetCount(
            MockClient((_) async => http.Response('nope', 404)), uri),
        isNull);
    expect(
        await readPolyTweetCount(
            MockClient((_) async => http.Response('{"count":3}', 200)), uri),
        isNull);
    expect(
        await readPolyTweetCount(
            MockClient((_) async => throw http.ClientException('down')), uri),
        isNull);
  });

  test('count brackets', () {
    expect(polyCountBracket('<20'), (min: 0, max: 19));
    expect(polyCountBracket('20-39'), (min: 20, max: 39));
    expect(polyCountBracket('580+'), (min: 580, max: null));
    expect(polyCountBracket('Mexico'), isNull);
  });

  test('events carry tweetCount and the Mentions tag', () {
    final e = PolymarketModel().parseEventsRaw([
      {
        'id': '1083683',
        'slug': 'elon-musk-of-tweets-september-29-october-6-2026',
        'title': 'Elon Musk # of tweets',
        'tweetCount': 168,
        'tags': [
          {'slug': 'tweets-markets'}
        ],
        'markets': const [],
      },
      {
        'id': '1',
        'slug': 'what-will-trump-say',
        'title': 'What will Trump say?',
        'tags': [
          {'slug': 'mention-markets'}
        ],
        'markets': const [],
      },
    ]);
    expect(e[0].tweetCount, 168);
    expect(e[0].isMentionMarket, isFalse);
    expect(e[1].tweetCount, isNull);
    expect(e[1].isMentionMarket, isTrue);
  });
}
