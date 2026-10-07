import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/venue_analytics.dart';

import '../../helpers/runtime_policy_fixture.dart';

PolymarketEvent _event(String slug,
        {String category = 'other', List<String> tags = const []}) =>
    PolymarketEvent(
      id: slug,
      slug: slug,
      title: slug,
      volume: 1,
      volume24hr: 1,
      liquidity: 1,
      category: category,
      tags: tags,
      conditionId: 'cond-$slug',
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes'),
        PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  Future<RuntimeCapabilitiesService> policy(Set<String> blocked) async {
    final service = runtimePolicyFixture(blocked: blocked);
    addTearDown(service.dispose);
    expect(await service.refresh(), isTrue);
    return service;
  }

  test('sports and politics classify from tags and leagues, else category', () {
    expect(
        polymarketCategoryCapability('sports', const []), 'polymarket.sports');
    expect(polymarketCategoryCapability('other', const ['nba']),
        'polymarket.sports');
    expect(polymarketCategoryCapability('other', const ['premier-league']),
        'polymarket.sports');
    expect(polymarketCategoryCapability('politics', const []),
        'polymarket.politics');
    expect(polymarketCategoryCapability('other', const ['elections']),
        'polymarket.politics');
    expect(polymarketCategoryCapability('other', const ['us-election']),
        'polymarket.politics');
    // A crypto-tagged event stays crypto even when coarse-tagged politics
    // upstream, matching what analytics reports as market_category.
    expect(polymarketCategoryCapability('crypto', const ['bitcoin']), isNull);
    expect(polymarketCategoryCapability('other', const ['weather']), isNull);
    expect(polymarketCategoryCapability(null, const []), isNull);
    expect(polymarketBetCapabilities('sports', const []),
        ['polymarket.trade', 'polymarket.sports']);
    expect(polymarketBetCapabilities('crypto', const []), ['polymarket.trade']);
  });

  test('a blocked category hides its events and pills, the others stay',
      () async {
    final events = [
      _event('nba-game', tags: const ['nba']),
      _event('election', category: 'politics'),
      _event('btc-100k', category: 'crypto'),
    ];
    final open = await policy({});
    expect(polymarketEventsOffered(events, open).map((e) => e.slug),
        ['nba-game', 'election', 'btc-100k']);
    final noSports = await policy({'polymarket.sports'});
    expect(polymarketEventsOffered(events, noSports).map((e) => e.slug),
        ['election', 'btc-100k']);
    expect(polymarketTagOffered('nfl', noSports), isFalse);
    expect(polymarketTagOffered('politics', noSports), isTrue);
    final noPolitics = await policy({'polymarket.politics'});
    expect(polymarketEventsOffered(events, noPolitics).map((e) => e.slug),
        ['nba-game', 'btc-100k']);
    expect(polymarketTagOffered('elections', noPolitics), isFalse);
    expect(polymarketTagOffered('crypto', noPolitics), isTrue);
  });

  test('the gates fail closed without a readable policy', () {
    final unavailable = runtimePolicyFixture();
    addTearDown(unavailable.dispose);
    final events = [
      _event('nba-game', tags: const ['nba']),
      _event('election', category: 'politics'),
      _event('btc-100k', category: 'crypto'),
    ];
    expect(polymarketEventsOffered(events, unavailable).map((e) => e.slug),
        ['btc-100k']);
    expect(unavailable.allows('polymarket.close'), isTrue,
        reason: 'exits stay allowed while the policy is unavailable');
  });

  test('a new bet needs the category gate; a sell does not', () async {
    VenueAnalytics.rememberPolymarketEvent(
        _event('nba-finals', tags: const ['nba', 'basketball']));
    expect(
        polymarketBetCapabilitiesFor(['cond-nba-finals'],
            fallbackCategory: 'other'),
        ['polymarket.trade', 'polymarket.sports']);
    expect(
        polymarketBetCapabilitiesFor(['never-seen'],
            fallbackCategory: 'crypto'),
        ['polymarket.trade']);
    final noSports = await policy({'polymarket.sports'});
    await expectLater(
        noSports.ensureAllAllowed(
            polymarketBetCapabilitiesFor(['cond-nba-finals'])),
        throwsA(isA<CapabilityUnavailableException>()
            .having((e) => e.capability, 'capability', 'polymarket.sports')));
    await noSports.ensureAllAllowed(const ['polymarket.close']);
    await noSports.ensureAllAllowed(polymarketBetCapabilitiesFor(['never-seen'],
        fallbackCategory: 'crypto'));
  });
}
