// lib/screens/share/brag/position_share_card.dart
//
// THE SHARE ON A POSITION PAGE (founder, 1 November 2026; floating since
// 4 November 2026: "I do not like the Send to a friend on the top right
// ... It must be a floating button"). Both position pages put the round
// Sal button at the right of their floating Close position or Sell
// (kute_bar_context.dart, THE TRADE ROW; kute_bar_trade_row.dart): on an
// open position in profit a tap opens its brag preview ("Brag about it",
// the bar context's primaryAction, kute_share_actions.dart), else the
// position's Sal sheet ("Send to a friend": send the market, send this
// prediction, and for an open position "Show off this position"). No
// share pill beside the figure and no share card in the page any more.

import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart'
    show KuteMarketBarContext;

/// The round Sal button beside a position's Close position or Sell, for
/// the page's market context [bar]: with [brag] (an open position in
/// profit) a tap opens the brag preview, where the context has one;
/// otherwise the Sal sheet.
KuteBarShare positionBarShare(KuteBarContext bar, {required bool brag}) =>
    KuteBarShare(
      barContext: bar,
      brag: brag && bar is KuteMarketBarContext ? bar.primaryAction : null,
    );
