// NO CUT TEXT ON THE DOLLARS OVERVIEW (founder, 10 November 2026, on
// 2.2.0 (99): "On the overview the text is cut", his screenshot two
// squares and a full-width row: "Who will leave Trump Admi…", "Jensen
// Huang announced r…"). Three open predictions with long market names,
// two squares in a row and the third the full-width card (the no-orphan
// rule), at 375 pt and 430 pt, in English, Portuguese and German: no text
// on the Overview ends in an ellipsis or is cut by its line limit, nothing
// overflows, and the two squares of the row stand at one height (the
// Portfolio's Positions' rule, position_rows.dart).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/shared/open_once.dart';

import 'investments_harness.dart';

/// The founder's two, and a third as long.
const kLongMarkets = [
  'Jensen Huang announced resignation or removal by March 31, 2027',
  'Will Pete Hegseth leave the Trump Administration before 2027?',
  'Will the Federal Reserve cut interest rates by 50 basis points or more '
      'at its December 2026 meeting?',
];

/// What the cards write for them, whole (polyPositionRowNames: the
/// person's name over the question it answers, as the founder's "Pete
/// Hegseth" over "Who will leave Trump Admi…").
const kShownNames = [
  'Jensen Huang announced resignation or removal by March 31, 2027',
  'Pete Hegseth',
  'Leave Trump Administration before 2027 · Yes',
  'The Federal Reserve cut interest rates by 50 basis points or more at its '
      'December 2026 meeting',
];

/// Biggest first, as the Overview ranks them: the first two the squares,
/// the third the full-width card.
List<PolymarketPosition> longPositions() => [
      for (final (i, q) in kLongMarkets.indexed)
        PolymarketPosition(
            marketId: 'long-$i',
            marketQuestion: q,
            outcome: i == 2 ? 'No' : 'Yes',
            size: 60.0 - i * 15,
            avgPrice: 0.4,
            currentPrice: 0.45,
            pnl: (0.45 - 0.4) * (60.0 - i * 15),
            pnlPercent: 12.5,
            isResolved: false,
            tokenId: 'tok-long-$i'),
    ];

/// No live prices: the positions' own (the render's too).
class NoLivePolyPrices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: false, prices: {});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  final list = find.byKey(const ValueKey('dollars-activity-list'));
  final squares = find.byKey(const ValueKey('dollars-activity-squares'));

  for (final code in ['en', 'pt', 'de']) {
    for (final width in [375.0, 430.0]) {
      testWidgets(
          '$code at ${width.round()} pt: two squares and the full-width '
          'card, every name whole, nothing ellipsized or overflowing',
          (tester) async {
        await pumpInvestments(tester,
            size: Size(width, 1400),
            locale: Locale(code),
            overrides: [
              polymarketActivePositionsProvider
                  .overrideWith((_) => longPositions()),
              livePriceProvider.overrideWith(NoLivePolyPrices.new),
            ]);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(squares, findsOneWidget);
        final squareCards = find.descendant(
            of: squares,
            matching: find.byKey(const ValueKey('portfolio-square')));
        final wide = find.descendant(
            of: squares, matching: find.byKey(const ValueKey('portfolio-wide')));
        expect(squareCards, findsNWidgets(2));
        expect(wide, findsOneWidget);

        // Every market's name is on screen whole.
        for (final q in kShownNames) {
          expect(
              find.descendant(of: squares, matching: find.textContaining(q)),
              findsOneWidget,
              reason: q);
        }

        // No paragraph on the Overview is cut: none past its line limit,
        // none ending in an ellipsis, none wider than the room it has.
        final paragraphs = [
          for (final e in find
              .descendant(of: list, matching: find.byType(RichText))
              .evaluate())
            e.renderObject! as RenderParagraph,
        ];
        expect(paragraphs, isNotEmpty);
        for (final p in paragraphs) {
          final words = p.text.toPlainText();
          expect(p.didExceedMaxLines, isFalse, reason: 'cut: "$words"');
          expect(words.trimRight().endsWith('…'), isFalse,
              reason: 'ellipsized: "$words"');
          expect(p.size.width, lessThanOrEqualTo(width),
              reason: 'overflows: "$words"');
        }

        // The squares of the row: one height, at least the square's.
        final left = tester.getRect(squareCards.at(0));
        final right = tester.getRect(squareCards.at(1));
        expect(left.height, right.height);
        expect(left.top, right.top);
        await unmountInvestments(tester);
      });
    }
  }
}
