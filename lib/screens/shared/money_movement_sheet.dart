import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/services/one_balance/money_movement_route.dart';
import 'package:kute/services/tracking_service.dart';

export 'package:kute/services/one_balance/money_movement_route.dart';

/// Opens Move money: the existing amount sheet with both cash accounts
/// editable. Opening it, or changing its accounts, never submits a move.
/// [entrySource] is the categorical surface it was opened from
/// (`move_sheet_opened`'s `entry_source`).
Future<void> showMoneyMovementSheet(
  BuildContext context, {
  MoneyMovementAccount initialSource = MoneyMovementAccount.dollars,
  MoneyMovementAccount initialDestination = MoneyMovementAccount.bitcoin,
  String entrySource = 'portfolio',
}) async {
  final destination = initialSource == initialDestination
      ? (initialSource == MoneyMovementAccount.dollars
          ? MoneyMovementAccount.bitcoin
          : MoneyMovementAccount.dollars)
      : initialDestination;
  TrackingService.markEntrySource('move', entrySource);
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DepositSheet(
        lockedSide: MoveLockedSide.depositToUsd,
        movementRoute: MoneyMovementRoute(initialSource, destination),
      ),
    ),
  );
}
