import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/services/one_balance/money_movement_route.dart';
import 'package:kute/services/tracking_service.dart';

export 'package:kute/services/one_balance/money_movement_route.dart';

/// What a door asked Move money for: the route it opens on, whether the
/// screen is [swap], the `entry_source` and the prefilled dollars.
@immutable
class MoneyMovementRequest {
  const MoneyMovementRequest({
    required this.route,
    required this.swap,
    required this.entrySource,
    this.initialTargetUsd,
  });

  final MoneyMovementRoute route;
  final bool swap;
  final String entrySource;
  final double? initialTargetUsd;

  @override
  String toString() => 'MoneyMovementRequest($route, swap: $swap, '
      'entrySource: $entrySource, initialTargetUsd: $initialTargetUsd)';
}

/// Test seam: stands in for the Move money screen. Receives what the door
/// asked for (the `entry_source` is marked first, as for the real sheet).
@visibleForTesting
void Function(BuildContext context, MoneyMovementRequest request)?
    debugMoneyMovementSheetOpener;

/// Opens Move money: the existing amount sheet with both cash accounts
/// editable. Opening it, or changing its accounts, never submits a move.
/// [entrySource] is the categorical surface it was opened from
/// (`move_sheet_opened`'s `entry_source`).
/// [swap]: the screen is "Swap" (founder, 7 November 2026: "a button in a
/// reversible way"), Move money's pickers and rails under Swap's words.
/// [initialTargetUsd] prefills the typed dollars once the price is up
/// (the Goals nudge's "Move $50 to Dollars"), as every door's prefill.
Future<void> showMoneyMovementSheet(
  BuildContext context, {
  MoneyMovementAccount initialSource = MoneyMovementAccount.dollars,
  MoneyMovementAccount initialDestination = MoneyMovementAccount.bitcoin,
  String entrySource = 'portfolio',
  bool swap = false,
  double? initialTargetUsd,
}) async {
  final destination = initialSource == initialDestination
      ? (initialSource == MoneyMovementAccount.dollars
          ? MoneyMovementAccount.bitcoin
          : MoneyMovementAccount.dollars)
      : initialDestination;
  // A pair the sheet does not offer (Predictions to anywhere but Bitcoin)
  // opens on the source's one offered destination instead.
  final route = MoneyMovementRoute(initialSource, destination).offeredOrNearest;
  TrackingService.markEntrySource('move', entrySource);
  final seam = debugMoneyMovementSheetOpener;
  if (seam != null) {
    seam(
        context,
        MoneyMovementRequest(
            route: route,
            swap: swap,
            entrySource: entrySource,
            initialTargetUsd: initialTargetUsd));
    return;
  }
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DepositSheet(
        lockedSide: MoveLockedSide.depositToUsd,
        movementRoute: route,
        movementSwap: swap,
        initialTargetUsd: initialTargetUsd,
      ),
    ),
  );
}

/// MONEY BETWEEN YOUR OWN BITCOIN AND DOLLARS OPENS ONE SCREEN (founder,
/// 7 November 2026: "that swap screen should be the only one shown when
/// it's not a buy"; and "hide the swap": it reads as moving your own
/// money, so it keeps the Move money title and names both ends by their
/// accounts). Every own-account door ("Move to your Dollars" and "Move to
/// your Bitcoin" on the Sends' search, the Goals nudge, the Dollars home's
/// Swap; the Receives' own doors are gone, founder, 7 November 2026)
/// opens Swap straight on the amount, aimed [from] the one account to the
/// other: no picker sheet in between. Buys (Purchase, Buy dollars) never
/// come here.
///
/// SWAP (founder, 7 November 2026: "ideally is to have a move button ...
/// Only on dollars"; "Move money or swap money whatever is more common in
/// crypto lingo. or just 'swap'"): the screen is titled Swap and is
/// reversible. The swap circle between its From and To squares turns
/// Bitcoin → Dollars into Dollars → Bitcoin and back; the amount, Max,
/// the chips, the fee and the checks follow the direction on screen, and
/// a direction the policy withholds says so once it is on screen. Each
/// door still opens on its own direction.
///
/// ANY ACCOUNT BY HAND (founder, 8 November 2026: "here i need to be able
/// to choose predictions and investments also right? so user can manually
/// swap. It happens mostly automatic but we should allow for this"): a tap
/// on From or To opens the account picker, the Portfolio's Move money's
/// own, over its own rails, from every door that shows this screen: one
/// screen, one behaviour. The pairs Move money does not offer stay out
/// ([kMoneyMovementHiddenRoutes]).
///
/// From Dollars to Bitcoin it spends ALL the person's dollar money (founder, 7
/// November 2026: "From your Dollars should and must be all the available
/// balances, not just the Dollars balance"): Dollars first, then the
/// Predictions and Investing cash in reach, exactly as the Investments'
/// Buy bitcoin did (`dollarsToBitcoinSpendableProvider` for the figure and
/// Max, the venue-cash purchase for the funding). Every Dollars → Bitcoin
/// door comes through here, so none can differ.
Future<void> showOwnMoneyMove(
  BuildContext context, {
  required MoneyMovementAccount from,
  required String entrySource,
  double? initialTargetUsd,
}) {
  assert(from == MoneyMovementAccount.bitcoin ||
      from == MoneyMovementAccount.dollars);
  return showMoneyMovementSheet(
    context,
    initialSource: from,
    initialDestination: from == MoneyMovementAccount.bitcoin
        ? MoneyMovementAccount.dollars
        : MoneyMovementAccount.bitcoin,
    entrySource: entrySource,
    swap: true,
    initialTargetUsd: initialTargetUsd,
  );
}
