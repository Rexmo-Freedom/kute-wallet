// lib/screens/receive/bitcoin_receive_options.dart
//
// THE BITCOIN RECEIVE'S FIRST SHEET, "Receive" (founder, 6 November 2026:
// "On Bitcoin it needs that first screen"; 7 November 2026: "Bitcoin
// should be on top, more prevalent here", and the word swap appears
// nowhere: the sheet is titled Receive). The Bitcoin tab's Receive opens
// it; it is the Dollars receive's first step turned around
// (usd_receive_screen.dart): the app's big cards (kute_action_cards.dart)
// in a sheet as tall as they are, which, being short, hides the floating
// bar while it is up.
//
//   Bitcoin             the main action, on top, full width and larger
//                       (the grid's lead card): the bitcoin mark,
//                       "Bitcoin and Lightning"; the QR receive ("Spending
//                       Wallet", the paykute address, Unified / Bitcoin
//                       only / Lightning only).
//   From your Dollars   under it, a square: the Dollars mark, the Dollars
//                       balance ("$4.75 in Dollars"); Move money straight
//                       on the amount, Dollars to Bitcoin, pinned
//                       (showOwnMoneyMove), as the Dollars Send's "To your
//                       Bitcoin" opens it. Only where the wallet has a
//                       Dollars account (the spending wallet).
//   From another wallet the square beside it: the coins stacked, "USDC,
//   or exchange         USDT, ETH and N more" (the Dollars receive's words
//                       for the same door); the Bitcoin receive's "other
//                       coins" sheet (showOtherCoinsReceiveSheet). Only
//                       while a coin can be offered (the spending wallet,
//                       an account that may be offered swaps, a coin the
//                       standing route or a one-time quote can serve).
//
// The grid's own rule lays the two under Bitcoin out: two squares side by
// side, or, with one hidden, the other full width and compact; with both
// hidden, Bitcoin alone. Each card's sheet opens over this one, and
// closing it comes back here.
//
// Tracking keeps the events the doors already send: the Move sheet's
// `move_sheet_opened` with `entry_source` [kBitcoinReceiveDollarsSource],
// `receive_also_accepts_opened` with `source` [kReceiveOptionsSource],
// and the QR's own `receive_opened` with `entry_source`
// [kReceiveOptionsSource]. The sheet itself is the `receive_options`
// screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/receive/receive_sheet.dart'
    show showBitcoinQrReceiveSheet, showOtherCoinsReceiveSheet;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendStepTitle, sendAlsoSendsToCard;
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';

/// The `entry_source` of the Move sheet "From your Dollars" opens.
const String kBitcoinReceiveDollarsSource = 'bitcoin_receive_dollars';

/// This sheet as a source: `receive_also_accepts_opened`'s `source` and
/// the QR receive's `entry_source`.
const String kReceiveOptionsSource = 'receive_options';

/// The Dollars balance as the card prints it (floored to the cent, as the
/// Bitcoin card on the Dollars sheets prints the bitcoin), or null while
/// the figure is a guess (the SDK has not answered).
String? watchDollarsBalance(WidgetRef ref) {
  try {
    if (ref.watch(usdBalanceUnknownProvider)) return null;
    final usd = ref.watch(usdBalanceProvider);
    return '\$${((usd * 100).floor() / 100).toStringAsFixed(2)}';
  } catch (_) {
    return null;
  }
}

/// The Bitcoin tab's "Receive" sheet (see the file header).
class BitcoinReceiveOptions extends ConsumerStatefulWidget {
  const BitcoinReceiveOptions({super.key});

  @override
  ConsumerState<BitcoinReceiveOptions> createState() =>
      _BitcoinReceiveOptionsState();
}

class _BitcoinReceiveOptionsState extends ConsumerState<BitcoinReceiveOptions> {
  @override
  void initState() {
    super.initState();
    TrackingService.screenView('receive_options');
    // The coins are live-catalogue only, so nudge it rather than waiting
    // for the 6 h cadence.
    // ignore: discarded_futures
    ref.read(orchestraSupportedRoutesProvider.notifier).refresh();
  }

  /// Whether the wallet the money lands in is the spending wallet, the
  /// one with a Dollars account (a watch-only or hardware wallet has
  /// none), on its bitcoin side.
  bool _onSpending() {
    final account = ref.watch(selectedAccountProvider);
    if (account is UsdcSpendingAccount) return false;
    final settings = ref.watch(settingsProvider);
    final spending = settings.wallets.where((w) => w.isSparkWallet).firstOrNull;
    final picked = account?.wallet?.id ?? settings.activeWalletId;
    return spending != null && spending.id == picked;
  }

  /// The coins "From another wallet or exchange" offers: exactly the set the other
  /// coins sheet lists (a reusable standing address where that route may
  /// serve the coin, else a one-time address into `spark:BTC` while the
  /// policy allows them). Empty off the spending wallet and for accounts
  /// that may not be offered swaps.
  List<CoinAssetGroup> _otherCoins({required bool onSpending}) {
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final offersOn = ref.watch(swapOffersEnabledProvider);
    final destinations = ref.watch(standingDestinationsProvider).valueOrNull;
    if (!onSpending || !offersOn) return const [];
    return coinGroupsOfferedUnderPolicy(
      receiveCoinGroups(catalog, context.l10n,
          destinationAsset: 'BTC', standingDestinations: destinations),
      otherLegAsset: 'BTC',
      reusableLegAsset: kOrchestraUsdAssetCode,
      depositAddress: true,
    ).groups;
  }

  /// Move money straight on the amount, Dollars to Bitcoin, nothing to
  /// pick, as the Dollars Send's "To your Bitcoin" opens it.
  void _openFromDollars() => unawaited(showOwnMoneyMove(context,
      from: MoneyMovementAccount.dollars,
      entrySource: kBitcoinReceiveDollarsSource));

  void _openOtherCoins(int coins) {
    HapticFeedback.lightImpact();
    TrackingService.track('receive_also_accepts_opened',
        params: {'source': kReceiveOptionsSource, 'coins': coins});
    unawaited(showOtherCoinsReceiveSheet(context));
  }

  void _openBitcoin() {
    TrackingService.markEntrySource('receive', kReceiveOptionsSource);
    unawaited(showBitcoinQrReceiveSheet(context));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onSpending = _onSpending();
    final groups = _otherCoins(onSpending: onSpending);
    final dollars = onSpending ? watchDollarsBalance(ref) : null;
    final mark = kKuteActionCardVisualSize.sp;
    final lead = kKuteActionCardLeadVisualSize.sp;
    return ReceiveSheetFrame(
      leading: KuteCloseButton(
          onPressed: () => Navigator.of(context).maybePop()),
      title: SendStepTitle(l10n.receive),
      semanticTitle: l10n.receive,
      fitContent: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 8.h),
        child: KuteActionCardGrid(
          key: const ValueKey('bitcoin-receive-options'),
          // Bitcoin on top, the main action (founder, 7 November 2026).
          lead: KuteActionCard(
            key: const ValueKey('bitcoin-receive-bitcoin'),
            visual: SvgPicture.asset(kBitcoinMarkAsset,
                width: lead, height: lead),
            title: l10n.bitcoin,
            subtitle: l10n.receiveBitcoinAndLightning,
            visualSlot: kKuteActionCardLeadVisualSlot,
            onTap: _openBitcoin,
          ),
          cards: [
            if (onSpending)
              KuteActionCard(
                key: const ValueKey('bitcoin-receive-from-dollars'),
                visual: SvgPicture.asset(kUsdMarkAsset,
                    width: mark, height: mark),
                title: l10n.receiveFromYourDollars,
                subtitle:
                    dollars == null ? null : l10n.usdDollarsBalanceLine(dollars),
                onTap: _openFromDollars,
              ),
            if (groups.isNotEmpty)
              sendAlsoSendsToCard(
                l10n,
                key: const ValueKey('bitcoin-receive-from-another'),
                // The Dollars receive's words for the same door.
                title: l10n.usdReceiveFromAnotherWallet,
                groups: groups,
                onTap: () => _openOtherCoins(groups.length),
              ),
          ],
        ),
      ),
    );
  }
}
