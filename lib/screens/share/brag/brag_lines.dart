// lib/screens/share/brag/brag_lines.dart
//
// THE EDGY LINE ON THE BRAG CARD (founder, 1 November 2026: keep it
// fintech, but make it interesting to share; the line is written on the
// card, typographic, never a bubble). A pool per tone ([BragTone]), built
// from the card's own figure: cocky on a gain ("Not luck. Pattern
// recognition.", "+$412.35 while you were scrolling."), unbothered on a
// loss ("Down bad, still trading.", "Character building, $23.00 at a
// time."), deadpan when flat ("Patience is a position."). The card leaves
// the phone (WhatsApp, Instagram), so every line is PG: no profanity, no
// slurs, nothing about other people. The preview picks a seed once when
// it opens; [bragEdge] maps the seed into the pool. The share message
// does not repeat it.
//
// A WON PREDICTION ([BragWin]) has its own pool, the result settled:
// "Resolved. Receipts attached.", "In at 41¢. Aged well.", "+$17.70 for
// being right.", and the pattern line. Never "bet", never a promise of a
// next one.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/share/brag/brag_data.dart';

/// [data]'s result: the position's, or the portfolio's all-time P&L.
BragResult? _resultOf(BragData data) => switch (data) {
      final BragPosition d => d.result,
      final BragWin d => d.result,
      final BragPortfolio d => d.allTime,
    };

/// The lines that may go on [data]'s card.
List<String> bragEdges(AppLocalizations l10n, BragData data) {
  final r = _resultOf(data);
  if (data is BragWin) {
    final entry = data.entryText;
    return [
      l10n.bragEdgeWonReceipts,
      if (entry != null) l10n.bragEdgeWonAgedWell(entry),
      l10n.bragEdgeWonRight(data.result.text),
      l10n.shareEdgeBragPattern,
    ];
  }
  switch (data.tone) {
    case BragTone.bigWin || BragTone.win || BragTone.smallWin:
      return [
        l10n.shareEdgeBragPattern,
        if (r != null) l10n.shareEdgeBragScrolling(r.text),
      ];
    case BragTone.loss:
      // The amount without its sign: "$23.00 at a time".
      final abs = r?.text.replaceFirst(RegExp(r'^[−\-+]\s*'), '');
      return [
        l10n.shareEdgeBragStillTrading,
        if (abs != null && abs.isNotEmpty) l10n.shareEdgeBragCharacter(abs),
      ];
    case BragTone.flat:
      return [l10n.shareEdgePatience];
  }
}

/// The line for [data] at [seed] (any int; the preview's random pick).
String bragEdge(AppLocalizations l10n, BragData data, int seed) {
  final pool = bragEdges(l10n, data);
  return pool[seed.abs() % pool.length];
}
