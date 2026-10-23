// RECEIVE OPENS AS A SHEET.
//
// Both receives (the Bitcoin tab's and the Investments tab's) open as a
// tall bottom sheet over whatever is on screen, with every step inside it.
// The dock calls [showBitcoinReceiveSheet] / [showUsdReceiveSheet]; the
// old `/receive` and `/receive_dollars` routes stay for deep links and
// build a [ReceiveSheetPage], so a link opens the very same sheet over
// the current screen rather than a second, full-screen receive.

import 'package:flutter/material.dart';

import 'package:kute/screens/receive/components/confirm_receive.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/usd/usd_receive_screen.dart';

/// The route names the two sheets carry, the names the screens had, so
/// the route observers (sync gating, screen names) see what they saw.
const String kBitcoinReceiveRouteName = 'receive';
const String kUsdReceiveRouteName = 'receiveDollars';

/// The route name of the Bitcoin receive's "other coins" sheet.
const String kOtherCoinsReceiveRouteName = 'receiveOtherCoins';

/// Test seams: what each sheet holds. Null builds the real receive.
abstract final class ReceiveSheets {
  @visibleForTesting
  static WidgetBuilder? debugBitcoinBody;

  @visibleForTesting
  static WidgetBuilder? debugUsdBody;
}

Widget _bitcoinBody(BuildContext context) =>
    ReceiveSheets.debugBitcoinBody?.call(context) ?? const ConfirmReceive();

Widget _usdBody(BuildContext context) =>
    ReceiveSheets.debugUsdBody?.call(context) ?? const UsdReceiveScreen();

/// The Bitcoin tab's Receive: the unified QR and the coins it also
/// accepts, in a sheet over the current screen.
Future<void> showBitcoinReceiveSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kBitcoinReceiveRouteName),
      builder: _bitcoinBody,
    );

/// The Investments tab's Receive: "From your Bitcoin" over the coins it
/// also accepts, each through its reusable address (a one-time address
/// where that cannot serve it), in a sheet over the current screen.
Future<void> showUsdReceiveSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kUsdReceiveRouteName),
      builder: _usdBody,
    );

/// The Bitcoin receive's "other coins": the same coin sheet over the
/// Bitcoin receive. A coin gets the reusable Dollars address (landing in
/// Investments, said under it), or, where that cannot serve it, a one-time
/// address delivering bitcoin (`spark:BTC`). Closing it returns to the
/// Bitcoin receive as it was.
Future<void> showOtherCoinsReceiveSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kOtherCoinsReceiveRouteName),
      builder: (_) => const UsdReceiveScreen(destinationAsset: 'BTC'),
    );

/// A route's page that presents its receive as the same sheet
/// [showAppBottomSheet] opens, over whatever the route sits on.
class ReceiveSheetPage extends Page<void> {
  const ReceiveSheetPage({super.key, super.name, required this.usd});

  /// The Investments receive rather than the Bitcoin one.
  final bool usd;

  @override
  Route<void> createRoute(BuildContext context) => ModalBottomSheetRoute<void>(
        settings: this,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierLabel: MaterialLocalizations.of(context).scrimLabel,
        builder: (ctx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: usd ? _usdBody(ctx) : _bitcoinBody(ctx),
        ),
      );
}
