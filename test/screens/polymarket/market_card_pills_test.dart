// B · one tap to the slip (founder, 12 November 2026; money only after
// Confirm): each pill on a Predictions list card (a Yes/No market's
// answers, a game's sides; an event with many outcomes has none since
// the founder found its row pills too small) opens the bet slip
// prefilled with its side, and places, funds or approves nothing. The slip opens in the round card's test world (fake books,
// trading and clock: crypto_next_round_card_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/shell_bar_harness.dart';
import 'crypto_next_round_card_test.dart' as card;

PolymarketEvent _event(
        String slug, String title, List<PolymarketOutcome> o) =>
    PolymarketEvent(
      id: slug,
      slug: slug,
      title: title,
      volume: 1e6,
      liquidity: 1e5,
      category: slug.startsWith('g') ? 'sports' : 'politics',
      conditionId: slug,
      endDate: DateTime.utc(2030, 12, 31),
      outcomes: o,
    );

final _yesNo = _event('fed', 'Fed cuts rates in December?', const [
  PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'y', conditionId: 'f'),
  PolymarketOutcome(name: 'No', price: 0.39, tokenId: 'n', conditionId: 'f'),
]);

final _threeWay = _event('g3', 'Arsenal vs Chelsea', const [
  PolymarketOutcome(
      name: 'Will Arsenal win?', price: 0.58, tokenId: 'ars', noTokenId: 'x1'),
  PolymarketOutcome(
      name: 'Draw (Arsenal vs Chelsea)',
      price: 0.21,
      tokenId: 'drw',
      noTokenId: 'x2'),
  PolymarketOutcome(
      name: 'Will Chelsea win?', price: 0.21, tokenId: 'che', noTokenId: 'x3'),
]);

final _twoWay = _event('g2', 'Broncos vs. 49ers', const [
  PolymarketOutcome(name: 'Broncos', price: 0.36, tokenId: 'bro'),
  PolymarketOutcome(name: '49ers', price: 0.64, tokenId: 'nin'),
]);

/// A game priced by the one market named for the match: Yes is its first
/// team (Celtics), the title names the Lakers first.
final _moneyline = _event('gm', 'Lakers vs. Celtics', const [
  PolymarketOutcome(
      name: 'Celtics vs. Lakers', price: 0.4, tokenId: 'cY', noTokenId: 'cN'),
  PolymarketOutcome(
      name: 'Lakers vs. Celtics: O/U 220.5',
      price: 0.5,
      tokenId: 'oY',
      noTokenId: 'oN'),
]);

void main() {
  late card.CardWorld world;
  late List<(String, Map<String, Object>?)> events;

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    world = card.CardWorld()..install();
    BetSlipSheet.debugClock = () => world.now;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    installShellBar();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    BetSlipSheet.debugClock = DateTime.now;
    PolymarketLiveBooks.instance.reset();
  });

  /// [event]'s card wired as the Predictions list wires it; taps the pill
  /// that says [pill] and returns the slip it opened.
  Future<BetSlipSheet> tapPill(
      WidgetTester tester, PolymarketEvent event, String pill) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pageOpened = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: world.overrides(),
      child: shellBarApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: MarketCard(
                title: event.displayTitle,
                outcomes: event.outcomes,
                volume: event.volume,
                category: event.category,
                endDate: event.endDate,
                slug: event.slug,
                onTap: () => pageOpened++,
                onPickSide: (pick) => polyCardOpenSlip(context,
                    event: event, pick: pick, source: 'feed_card'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text(pill));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The pill is not the card's tap: the market page stays shut.
    expect(pageOpened, 0);
    return tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
  }

  /// Nothing was placed, funded or approved: the slip only opened.
  void placedNothing() {
    final names = events.map((e) => e.$1).toList();
    expect(names, contains('polymarket_bet_slip_opened'));
    final opened =
        events.firstWhere((e) => e.$1 == 'polymarket_bet_slip_opened');
    expect(opened.$2?['source'], 'feed_card');
    expect(
        names.where((n) =>
            n.contains('placed') ||
            n.contains('approv') ||
            n.contains('fund') ||
            n.contains('order')),
        isEmpty,
        reason: '$names');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  }

  testWidgets('Yes/No: the No pill opens the slip on No', (tester) async {
    final slip = await tapPill(tester, _yesNo, 'No 39¢');
    expect(slip.outcomes.map((o) => o.tokenId), ['y', 'n']);
    expect(slip.initialOutcomeIndex, 1);
    expect(slip.initialAmountUsd, isNull);
    placedNothing();
    await close(tester);
  });

  testWidgets('a three-way game: the draw pill opens the match on the draw',
      (tester) async {
    final slip = await tapPill(tester, _threeWay, 'Draw 21¢');
    expect(slip.outcomes.map((o) => o.tokenId), ['ars', 'drw', 'che']);
    expect(slip.outcomeLabels, ['Arsenal', 'Draw', 'Chelsea']);
    expect(slip.initialOutcomeIndex, 1);
    placedNothing();
    await close(tester);
  });

  testWidgets('a three-way game: a team pill opens on that team',
      (tester) async {
    final slip = await tapPill(tester, _threeWay, 'Chelsea 21¢');
    expect(slip.initialOutcomeIndex, 2);
    expect(slip.outcomes[2].tokenId, 'che');
    placedNothing();
    await close(tester);
  });

  testWidgets("a two-way game: a team pill opens the market on its team",
      (tester) async {
    final slip = await tapPill(tester, _twoWay, '49ers 64¢');
    expect(slip.outcomes.map((o) => o.tokenId), ['bro', 'nin']);
    expect(slip.initialOutcomeIndex, 1);
    placedNothing();
    await close(tester);
  });

  testWidgets(
      "a game priced by the match's own market: the team it names second "
      'is its No', (tester) async {
    // Lakers (first in the title) are the market's No: 60¢.
    final slip = await tapPill(tester, _moneyline, 'Lakers 60¢');
    expect(slip.outcomes.map((o) => o.tokenId), ['cY', 'cN']);
    expect(slip.initialOutcomeIndex, 1);
    expect(slip.sideLabelPos, 'Celtics');
    expect(slip.sideLabelNeg, 'Lakers');
    placedNothing();
    await close(tester);
  });
}
