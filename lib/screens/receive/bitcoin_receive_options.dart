// lib/screens/receive/bitcoin_receive_options.dart
//
// THE BITCOIN RECEIVE'S FIRST SHEET, "Receive" (founder, 6 November 2026:
// "On Bitcoin it needs that first screen"; the word swap appears nowhere:
// the sheet is titled Receive, in the first steps' header, big on the left
// with the compact X at the top right: receive_surface.dart,
// SheetTitleHeader). The Bitcoin tab's Receive opens it; it is the Dollars
// receive's first step turned around (usd_receive_screen.dart): the app's
// big cards (kute_action_cards.dart) in a sheet as tall as they are,
// which, being short, hides the floating bar while it is up.
//
// TWO SQUARES (founder, 8 November 2026, of the two full-width rows: "here
// on receive make it two square cards"), the grid's two equal squares side
// by side, as the Send's What step (send_what_step.dart); a title wraps to
// the lines it needs and the other square grows with it:
//
//   Bitcoin             the bitcoin mark, "Bitcoin and Lightning"; the QR
//                       receive ("Spending Wallet", the paykute address,
//                       Unified / Bitcoin only / Lightning only).
//   Another crypto      (founder, 7 November 2026: "Another crypto", was
//                       "Another wallet"): the two best-known coins' marks
//                       side by side and "USDC, ETH and more"
//                       (anotherCryptoCard, the Dollars receive's card for
//                       the same door); the Bitcoin receive's "other
//                       coins" sheet (showOtherCoinsReceiveSheet). Only
//                       while a coin can be offered (the spending wallet,
//                       an account that may be offered swaps, a coin the
//                       standing route or a one-time quote can serve).
//
// With no coin to offer, Bitcoin alone: the grid's lead card, full width
// and larger, never a square alone in half the width.
//
// NOT YOUR OWN MONEY (founder, 7 November 2026: "On bitcoin receive we get
// rid of from your dollars. On dollars receive we get rid of from your
// bitcoin."): moving money between your own accounts is no longer a
// Receive door; the Dollars home's Move money is. Each card's sheet opens
// over this one, and closing it comes back here.
//
// Tracking keeps the events the doors already send:
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
    show kBitcoinMarkAsset;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showBitcoinQrReceiveSheet, showOtherCoinsReceiveSheet;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show anotherCryptoCard;
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';

/// This sheet as a source: `receive_also_accepts_opened`'s `source` and
/// the QR receive's `entry_source`.
const String kReceiveOptionsSource = 'receive_options';

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

  /// The coins "Another crypto" offers: exactly the set the other
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
    final alone = groups.isEmpty;
    final mark =
        (alone ? kKuteActionCardLeadVisualSize : kKuteActionCardVisualSize).sp;
    final bitcoin = KuteActionCard(
      key: const ValueKey('bitcoin-receive-bitcoin'),
      visual: SvgPicture.asset(kBitcoinMarkAsset, width: mark, height: mark),
      title: l10n.bitcoin,
      subtitle: l10n.receiveBitcoinAndLightning,
      visualSlot: alone ? kKuteActionCardLeadVisualSlot : kKuteActionCardVisualSlot.sp,
      onTap: _openBitcoin,
    );
    return ReceiveSheetFrame.titled(
      heading: l10n.receive,
      onClose: () => Navigator.of(context).maybePop(),
      fitContent: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, sheetStepContentTop, 20.w, 8.h),
        child: KuteActionCardGrid(
          key: const ValueKey('bitcoin-receive-options'),
          // Bitcoin alone, or two squares (no "From your Dollars": see the
          // file header).
          lead: alone ? bitcoin : null,
          cards: [
            if (!alone) ...[
              bitcoin,
              // The Dollars receive's card for the same door.
              anotherCryptoCard(
                l10n,
                key: const ValueKey('bitcoin-receive-from-another'),
                groups: groups,
                onTap: () => _openOtherCoins(groups.length),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
