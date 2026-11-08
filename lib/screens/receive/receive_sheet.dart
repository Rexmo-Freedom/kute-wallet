// RECEIVE OPENS AS A SHEET.
//
// Both receives (the Bitcoin tab's and the Investments tab's) open as a
// bottom sheet over whatever is on screen, with every step inside it.
// The row calls [showBitcoinReceiveSheet] / [showUsdReceiveSheet]: each
// opens on its "Receive" cards (bitcoin_receive_options.dart,
// usd_receive_screen.dart), a sheet as tall as they are. The Bitcoin
// card opens the QR receive over it ([showBitcoinQrReceiveSheet]); a
// wallet with nothing else to receive from (watch-only, hardware) opens
// the QR straight away. The old `/receive` and `/receive_dollars` routes stay
// for deep links and build a [ReceiveSheetPage], so a link opens the
// very same sheet over the current screen rather than a second,
// full-screen receive (`/receive` the QR itself).

import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/kute_motion.dart';

import 'package:kute/screens/receive/bitcoin_receive_options.dart';
import 'package:kute/screens/receive/components/confirm_receive.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/usd/usd_receive_screen.dart';

/// The route names the two sheets carry, the names the screens had, so
/// the route observers (sync gating, screen names) see what they saw.
const String kBitcoinReceiveRouteName = 'receive';
const String kUsdReceiveRouteName = 'receiveDollars';

/// The route name of the Bitcoin receive's "other coins" sheet.
const String kOtherCoinsReceiveRouteName = 'receiveOtherCoins';

/// The route name of the Bitcoin receive's first sheet, "Receive".
const String kBitcoinReceiveOptionsRouteName = 'receiveOptions';

/// Test seams: what each sheet holds. Null builds the real receive.
abstract final class ReceiveSheets {
  /// The Bitcoin QR receive.
  @visibleForTesting
  static WidgetBuilder? debugBitcoinBody;

  /// The Bitcoin receive's "Receive" cards.
  @visibleForTesting
  static WidgetBuilder? debugBitcoinOptionsBody;

  @visibleForTesting
  static WidgetBuilder? debugUsdBody;
}

Widget _bitcoinBody(BuildContext context) =>
    ReceiveSheets.debugBitcoinBody?.call(context) ?? const ConfirmReceive();

Widget _bitcoinOptionsBody(BuildContext context) =>
    ReceiveSheets.debugBitcoinOptionsBody?.call(context) ??
    const BitcoinReceiveOptions();

Widget _usdBody(BuildContext context) =>
    ReceiveSheets.debugUsdBody?.call(context) ?? const UsdReceiveScreen();

/// The Bitcoin tab's Receive: "Receive", Bitcoin on top, then From your
/// Dollars and Another crypto, as big cards
/// (bitcoin_receive_options.dart), in a sheet over the current screen.
Future<void> showBitcoinReceiveSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kBitcoinReceiveOptionsRouteName),
      builder: _bitcoinOptionsBody,
    );

/// The Bitcoin QR receive: the unified code (Bitcoin only, Lightning
/// only) of the account the money lands in, in a sheet over the current
/// screen: over "Receive" from its Bitcoin card, or straight from the row
/// of a wallet with nothing else to receive from.
Future<void> showBitcoinQrReceiveSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kBitcoinReceiveRouteName),
      builder: _bitcoinBody,
    );

/// The Dollars tab's Receive: "Receive", Dollars on top (the dollar
/// coins), then Another crypto, as big cards
/// (usd_receive_screen.dart; each coin through its reusable address, a
/// one-time address where that cannot serve it), in a sheet over the
/// current screen.
Future<void> showUsdReceiveSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kUsdReceiveRouteName),
      builder: _usdBody,
    );

/// The Bitcoin receive's "other coins" ("Another crypto" on Receive): the
/// coin sheet over it. A coin gets the reusable Dollars
/// address (landing in Investments, said under it), or, where that cannot
/// serve it, a one-time address delivering bitcoin (`spark:BTC`). Closing
/// it returns to Receive as it was.
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
        // The app's sheet motion (lib/theme/kute_motion.dart).
        sheetAnimationStyle: KuteMotion.sheetStyle(context),
        // The bar explains the screen (founder, 31 October 2026): "What
        // is this?", tapping sends the receive question to Sal.
        builder: (ctx) => KuteBarContextScope(
          barContext: KuteBarContext(
            label: ctx.l10n.barWhatIsThis,
            sublabel: ctx.l10n.barReceiveExplainSub,
            clip: 'curious',
            question: ctx.l10n.barReceiveQuestion,
            source: 'receive',
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: usd ? _usdBody(ctx) : _bitcoinBody(ctx),
          ),
        ),
      );
}
