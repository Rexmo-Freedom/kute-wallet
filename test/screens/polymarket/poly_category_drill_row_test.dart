// Predictions browses with ONE row of boxed category pills (owner
// decision 2026-10-13). Finance has subcategories: a tap swaps the row for
// "‹ Finance" and All · Daily · …, All selected; the back pill brings the
// categories back with Finance still on screen at its default list, and
// says so to PostHog. A category with none (New) selects and the row
// stays.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyDrillRow;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../usd/investments_harness.dart';

/// Every list empty and read: nothing goes to the network.
class _EmptyFeed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => const PolyFeedState(done: true);
}

Finder _inBrowser(Finder f) =>
    find.descendant(of: find.byType(PolymarketScreen), matching: f);

Finder _pill(String label) => _inBrowser(find.widgetWithText(KutePill, label));

final _back = _inBrowser(find.byKey(const ValueKey('kute-back-pill')));

bool _selected(WidgetTester tester, String label) =>
    tester.widget<KutePill>(_pill(label)).selected;

/// Brings [f] into view (the row side-scrolls) and taps it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'Finance drills in to its back pill and subcategories; back restores '
      'the categories at Finance\'s default list; New stays put',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);

    await pumpInvestments(tester, browsePredictions: true, overrides: [
      polyBrowseFeedProvider.overrideWith(_EmptyFeed.new),
    ]);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(KutePillTabs).first));
    await tapAndPump(tester, investmentsPill(l10n.predictions));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PolymarketScreen)));

    final row = _inBrowser(find.byType(PolyDrillRow));
    expect(row, findsOneWidget);
    final rowSize = tester.getSize(row);
    expect(_selected(tester, 'Trending'), isTrue);
    expect(_back, findsNothing);

    // New has no subcategories: it selects, the row stays.
    await _tap(tester, _pill('New'));
    await _settle(tester);
    expect(_selected(tester, 'New'), isTrue);
    expect(_back, findsNothing);
    expect(_pill('More ›'), findsOneWidget);

    // Finance drills in: "‹ Finance", then All (selected), Daily …
    await _tap(tester, _pill('Finance'));
    await _settle(tester);
    expect(_pill('Trending'), findsNothing);
    expect(_pill('More ›'), findsNothing);
    expect(_back, findsOneWidget);
    expect(tester.widget<KutePill>(_back).label, 'Finance');
    expect(_selected(tester, 'All'), isTrue);
    expect(_selected(tester, 'Daily'), isFalse);
    expect(tester.getSize(row), rowSize);

    await _tap(tester, _pill('Daily'));
    await _settle(tester);
    expect(_selected(tester, 'Daily'), isTrue);
    expect(container.read(polyBrowseSelectionProvider).sub, 'daily');

    // Back: the categories, Finance still selected, at its default list.
    await _tap(tester, _back);
    await _settle(tester);
    expect(_back, findsNothing);
    expect(_selected(tester, 'Finance'), isTrue);
    expect(container.read(polyBrowseSelectionProvider).pill, PolyPill.finance);
    expect(container.read(polyBrowseSelectionProvider).sub, 'all');

    expect(
        events.where((e) => e.$1 == 'category_pill_tapped').map((e) => e.$2), [
      {'section': 'new'},
      {'section': 'finance'},
      {'section': 'finance', 'subcategory': 'daily'},
    ]);
    expect(
        events
            .where((e) => e.$1 == 'category_row_back_tapped')
            .map((e) => e.$2),
        [
          {'surface': 'predictions', 'parent': 'finance'},
        ]);

    await unmountInvestments(tester);
    // The BTC price feed lets its socket go 30 s after the last listener.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets(
      'the lists carry no titles; plain markets share grouped cards that '
      'an event with many outcomes breaks',
      (tester) async {
    await pumpInvestments(tester,
        browsePredictions: true,
        size: const Size(390, 2400),
        overrides: [
          polyBrowseFeedProvider.overrideWith(_ThreeMarkets.new),
          ...offlineVenueOverrides,
        ]);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(KutePillTabs).first));
    await tapAndPump(tester, investmentsPill(l10n.predictions));

    for (final pill in ['Trending', 'New']) {
      if (pill != 'Trending') {
        await _tap(tester, _pill(pill));
        await _settle(tester);
      }
      expect(_selected(tester, pill), isTrue);
      // The pill names the list: its label is written once, on the pill.
      expect(_inBrowser(find.text(pill)), findsOneWidget);
      expect(find.descendant(of: _pill(pill), matching: find.text(pill)),
          findsOneWidget);

      // Plain markets share Home Activity's grouped card; the event with
      // many outcomes keeps its own card and breaks the group:
      // group (Fed, BTC) → card (Trump) → group (Rain).
      final cards = _inBrowser(find.byType(MarketCard));
      expect(cards, findsNWidgets(4));
      final groups = _inBrowser(find.byType(DecoratedSliver));
      expect(groups, findsNWidgets(2));
      final context = tester.element(cards.first);
      for (final g in tester.widgetList<DecoratedSliver>(groups)) {
        expect(g.decoration, PremiumGroupContainer.decorationOf(context));
      }
      Finder inGroup(int g, Finder f) =>
          find.descendant(of: groups.at(g), matching: f);
      expect(inGroup(0, find.byType(MarketCard)), findsNWidgets(2));
      expect(inGroup(1, find.byType(MarketCard)), findsOneWidget);
      expect(inGroup(0, find.byType(Divider)), findsOneWidget);
      expect(inGroup(1, find.byType(Divider)), findsNothing);
      expect(tester.widget<Divider>(inGroup(0, find.byType(Divider))).indent,
          polyGroupRowIndent());
      final trump = find.ancestor(
          of: find.text('Who will Trump meet?'),
          matching: find.byType(MarketCard));
      expect(tester.widget<MarketCard>(trump).inGroup, isFalse);
      expect(find.descendant(of: groups, matching: trump), findsNothing);
      for (final title in [
        'Fed cuts in December?',
        'Bitcoin above 150k?',
        'Rain in London tomorrow?'
      ]) {
        final card = find.ancestor(
            of: find.text(title), matching: find.byType(MarketCard));
        expect(tester.widget<MarketCard>(card).inGroup, isTrue);
      }
      // In order: the first group, the card, the second group.
      Rect at(String title) => tester.getRect(
          find.ancestor(of: find.text(title), matching: find.byType(MarketCard)));
      expect(at('Bitcoin above 150k?').bottom,
          lessThan(tester.getRect(trump).top));
      expect(tester.getRect(trump).bottom,
          lessThan(at('Rain in London tomorrow?').top));
      // No title over the 5-minute card either, big or small.
      expect(_inBrowser(find.text(l10n.predictionsCryptoMarkets)),
          findsNothing);
    }

    await unmountInvestments(tester);
    await tester.pump(const Duration(seconds: 31));
  });
}

/// Two plain Yes/No markets, an event with many outcomes, another plain
/// one: in every list.
class _ThreeMarkets extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) {
    PolymarketEvent yesNo(String id, String title) => PolymarketEvent(
          id: id,
          slug: id,
          title: title,
          volume: 1e6,
          liquidity: 1e5,
          category: 'finance',
          conditionId: id,
          outcomes: const [
            PolymarketOutcome(name: 'Yes', price: 0.4),
            PolymarketOutcome(name: 'No', price: 0.6),
          ],
        );
    return PolyFeedState(done: true, events: [
      yesNo('fed', 'Fed cuts in December?'),
      yesNo('btc', 'Bitcoin above 150k?'),
      PolymarketEvent(
        id: 'trump',
        slug: 'trump',
        title: 'Who will Trump meet?',
        volume: 1e6,
        liquidity: 1e5,
        category: 'politics',
        conditionId: 'trump',
        negRisk: true,
        outcomes: [
          for (final (n, p) in [('Xi', 0.8), ('Putin', 0.2), ('Kim', 0.1)])
            PolymarketOutcome(
                name: n,
                price: p,
                conditionId: n,
                tokenId: '$n-yes',
                noTokenId: '$n-no'),
        ],
      ),
      yesNo('rain', 'Rain in London tomorrow?'),
    ]);
  }
}
