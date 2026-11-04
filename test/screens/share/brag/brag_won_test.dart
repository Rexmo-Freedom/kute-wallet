// A won prediction's brag (founder, 4 November 2026: "Able to share past
// prediction brags also, won ones"): only a resolved win in profit makes
// a card (never a loss, an open position or a win that cost what it paid
// out); the card says CALLED IT, the side that won and the day, the dial
// at the end with the dot at the price paid, the profit huge with "Won
// from 41¢ · +143.9%", "Paid · Paid out", the won pool's line, green and
// Sal's win pose; the preview sheet reads "Show off this win" and
// brag_shared says card: won; the resolved position page's share card
// brags on a win and sends on a loss; a receipt's entry draws nothing
// without a win.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';
import 'package:kute/screens/polymarket/components/position_speedometer.dart'
    show PolySpeedometerDialPainter, PolySpeedometerNeedlePainter;
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_lines.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/brag_win_entry.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';

import '../../../helpers/kute_bar_test_support.dart';
import '../share_test_harness.dart';
import 'brag_fixtures.dart';
import 'brag_test_fonts.dart';

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

class _NoTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

/// 30 Yes shares at 41¢ on a market that resolved Yes: $12.30 in, $30.00
/// out.
PolymarketPosition _resolved({bool? won = true, bool resolved = true}) =>
    PolymarketPosition(
      marketId: 'c-fed',
      marketQuestion: 'Fed cuts rates in December?',
      outcome: 'Yes',
      size: 30,
      avgPrice: 0.41,
      currentPrice: resolved ? (won == true ? 1.0 : 0.0) : 0.62,
      pnl: won == true ? 17.7 : -12.3,
      pnlPercent: won == true ? 143.9 : -100,
      isResolved: resolved,
      won: resolved ? won : null,
      resolvedAt: resolved ? DateTime.utc(2026, 11, 3, 18) : null,
      tokenId: 'fed-yes',
      eventSlug: 'fed-december',
    );

void main() {
  late ShareTestEnv env;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadBragFonts();
  });
  setUp(() => env = setUpShareTest());
  tearDown(() {
    tearDownShareTest();
    BragPreviewSheet.debugSharer = null;
    BragPreviewSheet.debugLineSeed = null;
  });

  /// Runs [body] with a build's watch (the person's currency: USD).
  Future<T> withWatch<T>(
      WidgetTester tester, T Function(BragWatch watch) body) async {
    late T out;
    await pumpShareWidget(tester, env, Consumer(builder: (context, ref, _) {
      out = body(ref.watch);
      return const SizedBox();
    }));
    return out;
  }

  group('eligibility', () {
    test('only a resolved win with a profit of a cent or more', () {
      bool can({
        bool resolved = true,
        bool? won = true,
        double cost = 12.3,
        double payout = 30,
      }) =>
          canBragWin(
              resolved: resolved, won: won, costUsd: cost, payoutUsd: payout);
      expect(can(), isTrue);
      expect(can(resolved: false), isFalse, reason: 'open');
      expect(can(won: false), isFalse, reason: 'a loss');
      expect(can(won: null), isFalse, reason: 'no verdict');
      expect(can(payout: 0), isFalse, reason: 'a loss pays nothing');
      expect(can(cost: 30, payout: 30), isFalse, reason: 'no profit');
      expect(can(cost: 29.996, payout: 30), isFalse, reason: 'under a cent');
      expect(can(cost: 29.99, payout: 30), isTrue);
      expect(can(cost: 0), isFalse, reason: 'cost unknown');
      expect(can(cost: double.nan), isFalse);
      expect(can(payout: double.infinity), isFalse);
    });

    testWidgets('the card data: profit, percent on the cost, the price paid',
        (tester) async {
      final win = await withWatch(
          tester,
          (watch) => bragWonPrediction(watch,
              title: 'Fed cuts rates in December?',
              side: 'Yes',
              resolved: true,
              won: true,
              costUsd: 12.3,
              payoutUsd: 30,
              shares: 30,
              eventSlug: 'fed-december',
              imageUrl: '  ',
              resolvedAt: DateTime.utc(2026, 11, 3)));
      expect(win, isNotNull);
      expect(win!.result.usd, closeTo(17.7, 1e-9));
      expect(win.result.text, r'+$17.70');
      expect(win.result.percent, closeTo(143.9, 0.05));
      expect(win.paidText, r'$12.30');
      expect(win.payoutText, r'$30.00');
      expect(win.entryValue, closeTo(0.41, 1e-9));
      expect(win.entryText, '41¢');
      expect(win.imageUrl, isNull);
      expect(win.link,
          'https://backend.kutewallet.com/m/predictions/fed-december');
      expect(win.kind, BragKind.position);
      expect(win.up, isTrue);
      expect(win.tone, BragTone.bigWin);
      // Without a share count, no price paid (never estimated).
      final noShares = await withWatch(
          tester,
          (watch) => bragWonPrediction(watch,
              title: 'Q', side: 'Yes', resolved: true, won: true,
              costUsd: 12.3, payoutUsd: 30));
      expect(noShares!.entryValue, isNull);
      expect(noShares.entryText, isNull);
    });

    testWidgets('a loss, an open position, a win with no profit: no card',
        (tester) async {
      final none = await withWatch(tester, (watch) {
        BragWin? w({bool resolved = true, bool? won = true,
                double cost = 12.3, double payout = 30}) =>
            bragWonPrediction(watch,
                title: 'Q', side: 'Yes', resolved: resolved, won: won,
                costUsd: cost, payoutUsd: payout, shares: 30);
        return [
          w(won: false, payout: 0),
          w(resolved: false),
          w(cost: 30),
          w(won: null),
        ];
      });
      expect(none, everyElement(isNull));
    });

    testWidgets('a position: the resolved win only, at a dollar a share',
        (tester) async {
      final cards = await withWatch(tester, (watch) {
        BragWin? of(PolymarketPosition p) =>
            bragWonPosition(watch, position: p, costBasis: 12.3);
        return [
          of(_resolved()),
          of(_resolved(won: false)),
          of(_resolved(resolved: false)),
        ];
      });
      final won = cards.first!;
      expect(won.side, 'Yes');
      expect(won.payoutText, r'$30.00');
      expect(won.result.text, r'+$17.70');
      expect(won.resolvedAt, DateTime.utc(2026, 11, 3, 18));
      expect(cards[1], isNull, reason: 'a loss stays non-braggable');
      expect(cards[2], isNull, reason: 'an open position brags elsewhere');
    });
  });

  group('the card', () {
    Text textAt(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key)));

    testWidgets(
        'CALLED IT, the side and the day, the dial at the end with the '
        'dot at the price paid, the profit, paid and paid out',
        (tester) async {
      await pumpShareWidget(
          tester, env, Center(child: BragCard(data: fakeBragWin())));
      expect(tester.takeException(), isNull);
      expect(textAt(tester, 'brag-card-caps').data, 'CALLED IT');
      expect(textAt(tester, 'brag-card-meta').data, 'Yes · Nov 3, 2026');
      expect(textAt(tester, 'brag-card-number').data, r'+$17.70');
      expect(textAt(tester, 'brag-card-fact').data, 'Won from 41¢ · +143.9%');
      expect(textAt(tester, 'brag-card-fact').style!.color,
          ShareCardPalette.win.up);
      expect(textAt(tester, 'brag-card-plain').data,
          r'Paid $12.30 · Paid out $30.00');
      // Resolved: the needle at the end, the dot at 41¢.
      final dial = tester
          .widgetList<CustomPaint>(find.descendant(
              of: find.byKey(const ValueKey('brag-card-speedometer')),
              matching: find.byType(CustomPaint)))
          .map((c) => c.painter)
          .toList();
      expect(
          dial.whereType<PolySpeedometerDialPainter>().single.entry, 0.41);
      expect(
          dial.whereType<PolySpeedometerNeedlePainter>().single.needle.value,
          1.0);
      // Green, Sal's win pose (a big one), the code, no money left out.
      expect(bragPalette(fakeBragWin()), ShareCardPalette.win);
      expect(bragPose(fakeBragWin()), ShareCardPose.bigWin);
      expect(find.byKey(const ValueKey('brag-card-sal')), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-card-code')), findsOneWidget);
    });

    testWidgets('the won pool: settled, PG, never "bet"', (tester) async {
      await pumpShareWidget(tester, env, const SizedBox());
      final l10n = AppLocalizations.of(
          tester.element(find.byType(SizedBox).first));
      final pool = bragEdges(l10n, fakeBragWin());
      expect(pool, [
        'Resolved. Receipts attached.',
        'In at 41¢. Aged well.',
        r'+$17.70 for being right.',
        'Not luck. Pattern recognition.',
      ]);
      for (final line in pool) {
        expect(line.toLowerCase(), isNot(contains('bet')));
      }
      for (var seed = 0; seed < 8; seed++) {
        expect(bragEdge(l10n, fakeBragWin(), seed), isIn(pool));
      }
    });

    testWidgets('a named side reads as itself; no day, no dot in the meta',
        (tester) async {
      final data = BragWin(
        title: 'LoL Worlds 2026: Gen.G vs T1',
        link: 'https://backend.kutewallet.com/m/predictions/lol',
        side: 'Gen.G',
        result: const BragResult(usd: 4.2, text: r'+$4.20', percent: 7.5),
        paidText: r'$56.00',
        payoutText: r'$60.20',
      );
      await pumpShareWidget(tester, env, Center(child: BragCard(data: data)));
      expect(tester.takeException(), isNull);
      expect(textAt(tester, 'brag-card-meta').data, 'Gen.G');
      expect(textAt(tester, 'brag-card-fact').data, '+7.5%');
      expect(bragPose(data), ShareCardPose.win);
    });
  });

  group('the preview and the doors', () {
    testWidgets('"Show off this win"; Share fires brag_shared card: won',
        (tester) async {
      BragPreviewSheet.debugSharer = (_, __) async {};
      BragPreviewSheet.debugLineSeed = 0;
      await pumpShareWidget(
          tester, env, BragPreviewSheet(data: fakeBragWin()));
      expect(find.text('Show off this win'), findsOneWidget);
      final before = env.paramsOf('brag_shared').length;
      await tester.runAsync(() async {
        await tester.tap(kuteBarPrimary);
        for (var i = 0;
            i < 100 && env.paramsOf('brag_shared').length == before;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester);
      expect(env.paramsOf('brag_shared').single,
          {'kind': 'position', 'card': 'won'});
    });

    testWidgets('the receipt entry: nothing without a win, else the button '
        'that opens the won card', (tester) async {
      await pumpShareWidget(
          tester,
          env,
          Column(children: [
            BragWinEntry.maybe(null),
            BragWinEntry.maybe(fakeBragWin()),
          ]));
      expect(find.byType(BragWinEntry), findsOneWidget);
      expect(find.text('Brag about it'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('brag-win-entry')));
      await settle(tester);
      expect(find.text('Show off this win'), findsOneWidget);
      expect(find.byKey(const ValueKey('brag-preview-card')), findsOneWidget);
    });

    Future<void> pumpPosition(
        WidgetTester tester, PolymarketPosition position) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpShareWidget(tester, env, PositionDetailSheet(position: position),
          cardVenues: false,
          overrides: [
            polymarketClaimablePositionsProvider.overrideWithValue(const []),
            polymarketActivePositionsProvider.overrideWithValue(const []),
            livePriceProvider.overrideWith(_Prices.new),
            sportsLiveProvider.overrideWith(_NoGames.new),
            polyGameTimelineProvider.overrideWith(_NoTimeline.new),
            aiEnabledProvider.overrideWith((ref) async => false),
            polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
            predictionUsdCostProvider.overrideWith((ref, id) async => null),
            polymarketTradingProvider.overrideWith(_NoTrading.new),
            polymarketEventDetailsProvider.overrideWith((ref, slug) async => null),
            polyPositionJourneyProvider.overrideWith((ref, key) async => null),
          ]);
      // pumpShareWidget sized the view for a phone; the page wants room.
      tester.view.physicalSize = const Size(390, 1200);
      await settle(tester);
    }

    testWidgets(
        'the resolved position page: a win brags (its won card), a loss '
        'sends', (tester) async {
      await pumpPosition(tester, _resolved());
      final card = find.byKey(const ValueKey('position-share-card'));
      await tester.ensureVisible(card);
      expect(find.descendant(of: card, matching: find.text('Brag about it')),
          findsOneWidget);
      await tester.tap(card);
      await settle(tester);
      expect(find.text('Show off this win'), findsOneWidget);
      expect(find.text('CALLED IT'), findsOneWidget);
      expect(find.text(r'+$17.70'), findsWidgets);

      await pumpPosition(tester, _resolved(won: false));
      final lost = find.byKey(const ValueKey('position-share-card'));
      await tester.ensureVisible(lost);
      expect(find.descendant(of: lost, matching: find.text('Brag about it')),
          findsNothing);
      expect(find.descendant(of: lost, matching: find.text('Send to a friend')),
          findsOneWidget);
    });
  });
}
