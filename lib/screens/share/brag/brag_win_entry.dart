// lib/screens/share/brag/brag_win_entry.dart
//
// "BRAG ABOUT IT" ON A PAST WIN (founder, 4 November 2026: "Able to share
// past prediction brags also, won ones"). The one door every surface that
// shows a won prediction puts under its figures: the position page's
// black share button (position_share_card.dart, ShareActionCard), "Brag
// about it" over "A card with your result", opening the won card's
// preview (brag_preview_sheet.dart) with the data the surface built
// (brag_data.dart: bragWonPrediction, bragWonPosition). A surface that has
// no win to show (a loss, an open position, a win with no profit) gets
// null from those builders and draws nothing: [BragWinEntry.maybe].
//
// Used by the activity receipts of a won payout and of a won result
// (transactions_builder.dart); the resolved position page reaches the
// same preview through its own share card. The Portfolio's past
// positions can put [BragWinEntry.maybe] (or call showBragPreviewSheet
// with bragWonPosition's card) on a won row's detail.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_data.dart' show BragWin;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart'
    show showBragPreviewSheet;
import 'package:kute/screens/share/brag/position_share_card.dart'
    show ShareActionCard;

class BragWinEntry extends StatelessWidget {
  const BragWinEntry({super.key, required this.data});

  /// The won card to open.
  final BragWin data;

  /// The entry for [data], or nothing when there is no win to brag about.
  static Widget maybe(BragWin? data, {EdgeInsetsGeometry? padding}) {
    if (data == null) return const SizedBox.shrink();
    final entry = BragWinEntry(data: data);
    return padding == null ? entry : Padding(padding: padding, child: entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ShareActionCard(
      key: const ValueKey('brag-win-entry'),
      keyPrefix: 'brag-win-entry',
      title: l10n.bragAboutIt,
      sub: l10n.bragPositionActionSub,
      onTap: () => unawaited(showBragPreviewSheet(context, data)),
    );
  }
}
