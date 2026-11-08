// lib/screens/share/goal_share.dart
//
// SHARE MY LEVEL (founder, 8 November 2026, of the Levels sheet: "we should
// be able to share the goals"; then, of the Goals tab's bar: "just change
// Sal on this tab to share my level"). [openGoalCardShare] opens the share
// cards' preview ("Your card is ready", the bar "Share") with the level's
// card ([GoalCardData], cards/share_cards.dart), from the bar on the three
// surfaces that show the level (balance_goals.dart): the Goals tab, the
// Levels sheet, and the Goals tab while a rung is being celebrated.
//
// NO MONEY: the image shows a level, not what someone holds, and the
// message under it is the app's invite with the sharer's link or code
// (appInviteShareText, as a money receipt's), nothing without a code.
//
// Analytics: `balance_goal_card_shared {level, result, source}` once the OS
// share sheet answered: `level` the exact level, `result` its status
// (success | dismissed | unavailable | error), `source` where it started
// ([kGoalShareTab], [kGoalShareLadder], [kGoalShareCelebration]). Nothing
// else: no balance, no goal, no currency.

import 'package:flutter/widgets.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart'
    show showShareCardPreviewSheet;
import 'package:kute/screens/share/receipt_share.dart'
    show appInviteShareText, receiptReferralCode;
import 'package:kute/services/tracking_service.dart';

/// The preview's route name, for the route observers.
const String kGoalCardPreviewRoute = 'goal_card_preview';

/// The event's `source`: the Goals tab's bar.
const String kGoalShareTab = 'goals_tab';

/// The event's `source`: the Levels sheet's bar.
const String kGoalShareLadder = 'ladder';

/// The event's `source`: the Goals tab's bar while a rung is celebrated.
const String kGoalShareCelebration = 'celebration';

/// Opens the card of [level] (see the file header): [name] the level's name
/// in the app's language, [still] Sal's still for it.
Future<void> openGoalCardShare(
  BuildContext context, {
  required int level,
  required String name,
  required String still,
  required String source,
}) {
  final l10n = context.l10n;
  return showShareCardPreviewSheet(
    context,
    title: l10n.shareCardReadyTitle,
    shareLabel: l10n.share,
    routeName: kGoalCardPreviewRoute,
    source: 'goal_card',
    build: (_) => GoalCardData(
      level: level,
      name: name,
      still: still,
      referralCode: receiptReferralCode(),
    ),
    text: (context) =>
        appInviteShareText(context.l10n, receiptReferralCode()),
    onShared: (result) => TrackingService.track('balance_goal_card_shared',
        params: {'level': level, 'result': result, 'source': source}),
  );
}
