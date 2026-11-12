// A Predictions list is not read again, and never goes back to its
// loading state, when the runtime policy refreshes with nothing changed
// (founder, 2 November 2026: the browse "jitters every time it updates").
//
// The policy is fetched once a minute. Every fetch used to notify, and
// the list watched the whole policy, so every minute the list on screen
// was rebuilt from scratch: back to the page cached on disk (or to no
// rows and the skeleton) with `loading` set, the pages read since
// dropped, then the live first page again. On screen, the rows under the
// person's finger were swapped out and the list jumped. Now an unchanged
// refetch does not notify, and the list does not listen to the policy at
// all: since the founder decision of 12 November 2026 no category gate
// filters a list (shown, not bought), so even withdrawing sports leaves
// the list as it is; the bet slip is where a sports bet is refused.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/runtime_policy_fixture.dart';

final _future = DateTime.now().add(const Duration(days: 20)).toIso8601String();

Map<String, dynamic> _event(String slug, List<String> tags) => {
      'id': slug,
      'slug': slug,
      'title': '$slug title',
      'active': true,
      'closed': false,
      'endDate': _future,
      'volume': 1e6,
      'volume24hr': 1e5,
      'liquidity': 1e5,
      'tags': [
        for (final t in tags) {'slug': t}
      ],
      'markets': [
        {
          'id': 'm-$slug',
          'question': '$slug?',
          'outcomes': '["Yes","No"]',
          'outcomePrices': '["0.5","0.5"]',
          'clobTokenIds': '["y-$slug","n-$slug"]',
          'conditionId': '0x$slug',
          'active': true,
          'acceptingOrders': true,
        }
      ],
    };

final _rows = [
  for (var i = 0; i < 6; i++) _event('macro-$i', const ['economy']),
  _event('nfl-game', const ['sports', 'nfl']),
];

void main() {
  late Set<String> blocked;
  late RuntimeCapabilitiesService policy;
  late int reads;

  setUp(() async {
    AffiliateService.debugSessionToken = 'test-session';
    dotenv.clean();
    polyForgetLiveRead();
    PolyFeedPrefetch.debugReset();
    PolymarketFeedCache.instance.debugClearMemory();
    blocked = {};
    reads = 0;
    policy = runtimePolicyFixture(blocked: blocked);
    expect(await policy.refresh(), isTrue);
  });

  tearDown(() {
    policy.dispose();
    AffiliateService.debugSessionToken = null;
    dotenv.clean();
    PolyMarketProtocol.debugV2MarketIdsOverride = null;
  });

  http.Client backend() => MockClient((request) async {
        if (request.url.path == '/sports') return http.Response('[]', 200);
        reads++;
        return http.Response(jsonEncode({'events': _rows}), 200);
      });

  /// The container as the app wires it: the provider notifies its
  /// dependents whenever the service does.
  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      runtimeCapabilitiesProvider.overrideWith((ref) {
        policy.addListener(ref.notifyListeners);
        ref.onDispose(() => policy.removeListener(ref.notifyListeners));
        return policy;
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  const query = PolyFeedQuery(pill: PolyPill.trending);

  test(
      'an unchanged policy refetch neither notifies nor touches the list: '
      'no read, no loading, the same rows', () async {
    await http.runWithClient(() async {
      final c = container();
      final states = <PolyFeedState>[];
      c.listen(polyBrowseFeedProvider(query), (_, next) => states.add(next),
          fireImmediately: true);
      await c.read(polyBrowseFeedProvider(query).notifier).firstRead;
      final landed = c.read(polyBrowseFeedProvider(query));
      expect(landed.loading, isFalse);
      expect(landed.events, isNotEmpty);
      final readsBefore = reads;
      states.clear();
      var notified = 0;
      policy.addListener(() => notified++);

      // Three once-a-minute refreshes, the backend answering the same.
      for (var i = 0; i < 3; i++) {
        expect(await policy.refresh(), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(notified, 0, reason: 'nothing changed: nobody is told');
      expect(states, isEmpty, reason: 'the list was not rebuilt');
      expect(reads, readsBefore, reason: 'and not read again');
      expect(identical(c.read(polyBrowseFeedProvider(query)).events,
          landed.events), isTrue);
    }, backend);
  });

  test(
      'no policy change touches the list: withdrawing sports keeps its '
      'games listed', () async {
    await http.runWithClient(() async {
      final c = container();
      final states = <PolyFeedState>[];
      c.listen(polyBrowseFeedProvider(query), (_, next) => states.add(next),
          fireImmediately: true);
      await c.read(polyBrowseFeedProvider(query).notifier).firstRead;
      expect(
          c.read(polyBrowseFeedProvider(query)).events.map((e) => e.slug),
          contains('nfl-game'));
      states.clear();

      // Something else in the policy moved (a network change notifies
      // before it asks again): the list does not care.
      blocked.add('hyperliquid.stocks');
      await policy.networkChanged();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states, isEmpty);

      // Sports withdrawn: still listed, not read again.
      final readsBefore = reads;
      blocked.add(kPolymarketSportsCapability);
      expect(await policy.refresh(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(policy.allows(kPolymarketSportsCapability), isFalse);
      expect(states, isEmpty);
      expect(reads, readsBefore);
      final now = c.read(polyBrowseFeedProvider(query));
      expect(now.loading, isFalse);
      expect(now.events.map((e) => e.slug), contains('nfl-game'));
    }, backend);
  });
}
