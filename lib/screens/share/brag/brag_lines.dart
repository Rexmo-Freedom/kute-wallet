// lib/screens/share/brag/brag_lines.dart
//
// THE EDGY LINE ON THE BRAG CARD (founder, 1 November 2026: keep it
// fintech, but make it interesting to share; the line is written on the
// card, typographic, never a bubble; 5 November 2026: "add many more
// variations"). A pool of 12 to 16 per tone ([BragTone]), built from the
// card's own figure: cocky on a gain ("Not luck. Pattern recognition.",
// "+$412.35 while you were scrolling.", a big one "This is me being
// calm.", a small one "Small win. Still a win."), unbothered on a loss
// ("Down bad, still trading.", "Character building, $23.00 at a time.",
// "Temporarily humbled."), deadpan when flat ("Patience is a position.",
// "Break-even is undefeated."). The P&L card draws from the same pools.
// The card leaves the phone (WhatsApp, Instagram), so every line is PG:
// no profanity, no slurs, nothing about other people. The preview picks a
// seed once when it opens; [bragEdge] maps the seed into the pool. The
// share message does not repeat it.
//
// A WON PREDICTION ([BragWin]) has its own pool, the result settled:
// "Resolved. Receipts attached.", "In at 41¢. Aged well.", "+$17.70 for
// being right.", "Told you. Politely.", "Early, then right." only when it
// was bought under 50¢. Never "bet", never a promise of a next one.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/share/brag/brag_data.dart';

/// [data]'s result: the position's, or the portfolio's all-time P&L.
BragResult? _resultOf(BragData data) => switch (data) {
      final BragPosition d => d.result,
      final BragWin d => d.result,
      final BragPortfolio d => d.allTime,
    };

/// The lines that may go on [data]'s card: 12 to 16 per tone, the big
/// and the small win each with a few of their own; a flat card without a
/// result only lines that claim none.
List<String> bragEdges(AppLocalizations l10n, BragData data) {
  final r = _resultOf(data);
  if (data is BragWin) {
    final entry = data.entryText;
    final paid = data.entryValue;
    return [
      l10n.bragEdgeWonReceipts,
      if (entry != null) l10n.bragEdgeWonAgedWell(entry),
      l10n.bragEdgeWonRight(data.result.text),
      l10n.shareEdgeBragPattern,
      l10n.bragEdgeWonToldPolitely,
      l10n.bragEdgeWonNormal,
      l10n.bragEdgeWonMyFavour,
      l10n.bragEdgeWonPaysSometimes,
      l10n.bragEdgeWonAgreed,
      l10n.bragEdgeWonMySide,
      l10n.bragEdgeWonThenPayout,
      l10n.bragEdgeWonNoNotes,
      l10n.bragEdgeWonFutureSelf,
      // "Early" only when it was bought as the underdog.
      if (paid != null && paid < 0.5) l10n.bragEdgeWonEarlyThenRight,
      l10n.bragEdgeWonCollecting,
      l10n.bragEdgeWonNotSurprised,
    ];
  }
  final tone = data.tone;
  switch (tone) {
    case BragTone.bigWin || BragTone.win || BragTone.smallWin:
      return [
        l10n.shareEdgeBragPattern,
        if (r != null) l10n.shareEdgeBragScrolling(r.text),
        l10n.shareEdgeBragQuietlyGreen,
        l10n.shareEdgeBragGreenSuits,
        l10n.shareEdgeBragCopyMe,
        l10n.shareEdgeBragHumbleWorking,
        l10n.shareEdgeBragNotVibes,
        l10n.shareEdgeBragMildlyPleased,
        l10n.shareEdgeBragNotAPromise,
        l10n.shareEdgeBragBeforeItChanges,
        l10n.shareEdgeBragMainCharacter,
        l10n.bragEdgeWonNoNotes,
        if (tone == BragTone.bigWin) ...[
          if (r != null) l10n.shareEdgeBragUnbearable(r.text),
          l10n.shareEdgeBragBeingCalm,
          l10n.shareEdgeBragAllegedly,
        ],
        if (tone == BragTone.smallWin) ...[
          l10n.shareEdgeBragStillAWin,
          if (r != null) l10n.shareEdgeBragRome(r.text),
          l10n.shareEdgeBragModest,
        ],
      ];
    case BragTone.loss:
      // The amount without its sign: "$23.00 at a time".
      final abs = r?.text.replaceFirst(RegExp(r'^[−\-+]\s*'), '');
      final has = abs != null && abs.isNotEmpty;
      return [
        l10n.shareEdgeBragStillTrading,
        if (has) l10n.shareEdgeBragCharacter(abs),
        l10n.shareEdgeBragHumbled,
        l10n.shareEdgeBragRedPhase,
        if (has) l10n.shareEdgeBragLessons(abs),
        l10n.shareEdgeBragNotOut,
        l10n.shareEdgeBragGrowth,
        l10n.shareEdgeBragHumbleEra,
        l10n.shareEdgeBragOnTheChin,
        l10n.shareEdgeBragNotMyBest,
        l10n.shareEdgeBragDignified,
        l10n.shareEdgeBragTuition,
      ];
    case BragTone.flat:
      // No result to read (a portfolio before its P&L lands): nothing
      // that says it is zero.
      if (r == null) {
        return [
          l10n.shareEdgePatience,
          l10n.shareEdgeBragBlinked,
          l10n.shareEdgeBragNotAPromise,
          l10n.shareEdgeBragBeforeItChanges,
        ];
      }
      return [
        l10n.shareEdgePatience,
        l10n.shareEdgeBragNetCalm,
        l10n.shareEdgeBragBalanced,
        l10n.shareEdgeBragDidntPanic,
        l10n.shareEdgeBragUndefeated,
        l10n.shareEdgeBragWithStyle,
        l10n.shareEdgeBragSharedAnyway,
        l10n.shareEdgeBragSteadyHands,
        l10n.shareEdgeBragBlinked,
        l10n.shareEdgeBragEvenTemper,
        l10n.shareEdgeBragNoDrama,
        l10n.shareEdgeStockSideways,
      ];
  }
}

/// The line for [data] at [seed] (any int; the preview's random pick).
String bragEdge(AppLocalizations l10n, BragData data, int seed) {
  final pool = bragEdges(l10n, data);
  return pool[seed.abs() % pool.length];
}
