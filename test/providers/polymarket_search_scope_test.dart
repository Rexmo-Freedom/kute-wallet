// The search sheet's venue search: scoped to the picked topic's Gamma tag
// under the Predictions scope (`events_tag=<slug>`), to nothing under All;
// paged, "Show more" reading the page after.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

Map<String, Object> _event(String id, {List<String> tags = const []}) => {
      'id': id,
      'slug': id,
      'title': 'Match $id',
      'active': true,
      'closed': false,
      'liquidity': 5000,
      'volume': 100,
      'tags': [for (final t in tags) {'slug': t}],
      'markets': [
        {
          'id': 'm-$id',
          'question': 'Match $id?',
          'conditionId': 'c-$id',
          'active': true,
          'closed': false,
          'outcomes': '["Yes","No"]',
          'outcomePrices': '["0.6","0.4"]',
          'liquidityNum': 5000,
          'volumeNum': 100,
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RuntimeCapabilitiesService policy;

  setUp(() async {
    AffiliateService.debugSessionToken = 'test-session';
    policy = runtimePolicyFixture();
    expect(await policy.refresh(), isTrue);
  });
  tearDown(() {
    policy.dispose();
    AffiliateService.debugSessionToken = null;
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('the query carries the topic\'s tag under Predictions only', () {
    final c = container();
    c.read(searchQueryProvider.notifier).state = ' trump ';
    expect(c.read(polySearchQueryProvider), (query: 'trump', tag: null));
    c.read(searchPredictionsTopicProvider.notifier).state = PolyPill.sports;
    // Under All a topic does not scope.
    expect(c.read(polySearchQueryProvider).tag, isNull);
    c.read(selectedSearchCategoryProvider.notifier).state =
        SearchCategory.predictions;
    expect(c.read(polySearchQueryProvider), (query: 'trump', tag: 'sports'));
    // The tag is the Gamma slug (Culture is `pop-culture`).
    c.read(searchPredictionsTopicProvider.notifier).state = PolyPill.culture;
    expect(c.read(polySearchQueryProvider).tag, 'pop-culture');
    c.read(searchPredictionsTopicProvider.notifier).state = PolyPill.art;
    expect(c.read(polySearchQueryProvider).tag, 'art');
    c.read(searchPredictionsTopicProvider.notifier).state = null;
    expect(c.read(polySearchQueryProvider).tag, isNull);
  });

  test('the feed reads the first page scoped, then the next on Show more',
      () async {
    final requests = <Map<String, String>>[];
    await http.runWithClient(() async {
      final c = container();
      final feed = polySearchFeedProvider((query: 'madrid', tag: 'sports'));
      final sub = c.listen(feed, (_, __) {});
      expect(c.read(feed).loading, isTrue);
      // The debounce, then the read.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      for (var i = 0; i < 20 && c.read(feed).loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      var state = c.read(feed);
      expect(state.loading, isFalse);
      expect(state.events.map((e) => e.id), ['1', '2']);
      expect(state.hasMore, isTrue);
      expect(state.pages, 1);
      expect(requests.single['q'], 'madrid');
      expect(requests.single['events_tag'], 'sports');
      expect(requests.single['page'], isNull);

      await c.read(feed.notifier).loadMore();
      state = c.read(feed);
      // The earlier rows never move; the new page comes after, once each.
      expect(state.events.map((e) => e.id), ['1', '2', '3']);
      expect(state.hasMore, isFalse);
      expect(state.pages, 2);
      expect(state.loadingMore, isFalse);
      expect(requests.last['page'], '2');
      expect(requests.last['events_tag'], 'sports');
      // Nothing more: no read.
      await c.read(feed.notifier).loadMore();
      expect(requests, hasLength(2));
      sub.close();
    }, () => MockClient((request) async {
          expect(request.url.path, '/public-search');
          requests.add(request.url.queryParameters);
          final second = request.url.queryParameters['page'] == '2';
          return http.Response(
              jsonEncode({
                'events': second
                    ? [_event('2', tags: ['sports']), _event('3', tags: ['sports'])]
                    : [_event('1', tags: ['sports']), _event('2', tags: ['sports'])],
                'pagination': {'hasMore': !second},
              }),
              200);
        }));
  });

  test('paging shows under the Predictions scope with a query only', () async {
    await http.runWithClient(() async {
      final c = container();
      expect(c.read(searchPredictionsPagingProvider),
          (hasMore: false, loadingMore: false));
      c.read(searchQueryProvider.notifier).state = 'madrid';
      c.read(selectedSearchCategoryProvider.notifier).state =
          SearchCategory.predictions;
      final sub = c.listen(searchPredictionsPagingProvider, (_, __) {});
      // While the first page loads there is no Show more.
      expect(c.read(searchPredictionsPagingProvider).hasMore, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      for (var i = 0;
          i < 20 && !c.read(searchPredictionsPagingProvider).hasMore;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(c.read(searchPredictionsPagingProvider),
          (hasMore: true, loadingMore: false));
      c.read(selectedSearchCategoryProvider.notifier).state =
          SearchCategory.all;
      expect(c.read(searchPredictionsPagingProvider).hasMore, isFalse);
      sub.close();
    }, () => MockClient((request) async => http.Response(
          jsonEncode({
            'events': [_event('1')],
            'pagination': {'hasMore': true},
          }),
          200,
        )));
  });
}
