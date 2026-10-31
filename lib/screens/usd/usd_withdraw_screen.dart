// The Investments Withdraw, a sheet over the current screen: the same
// sheet the Investments Deposit opens (usd_receive_screen.dart), turned
// around (founder, 2026-10-23: "just reuse the bottom modal sheet we have
// for bitcoin deposit").
//
// Its first step mirrors the Deposit's: "To your wallet" over the Bitcoin
// card (the Move money sheet, Dollars to Bitcoin, the Portfolio's own
// door), then "To another wallet or exchange" over the coins the dollars
// can be sent out as (the dollar send's own destinations, under the same
// runtime policy). A picked coin opens the dollar send (usd_send_screen
// .dart) over this sheet on its recipient field, the coin already picked;
// closing it comes back here as it was, and a send that went out closes
// this sheet too. Nothing here moves money: both doors are the existing
// flows, unchanged.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart'
    show OrchestraReceiveOption;
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show MoneyMovementAccount, showMoneyMovementSheet;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard, SendToListRow, SendToSectionHeader;
import 'package:kute/screens/shared/send/send_sheet.dart' show showSendSheet;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/screens/usd/usd_receive_screen.dart'
    show watchSpendingBitcoinUsd;
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/orchestra_usd_send_routes.dart'
    show UsdSendDestination;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The route name the Withdraw sheet carries.
const String kUsdWithdrawRouteName = 'withdrawDollars';

/// The Move sheet's `entry_source` when the Bitcoin card ("To your
/// wallet") at the top of this sheet opens it.
const String kUsdWithdrawBitcoinRowSource = 'usd_withdraw_bitcoin_row';

/// The dollar send's `entry_source` when a coin on this sheet opens it.
const String kUsdWithdrawSheetSource = 'usd_withdraw_sheet';

/// The Investments dock's Withdraw: "To your wallet" over the coins the
/// dollars can be sent out as, in the Deposit's sheet over the current
/// screen.
Future<void> showUsdWithdrawSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kUsdWithdrawRouteName),
      builder: (_) => const UsdWithdrawScreen(),
    );

/// The Withdraw sheet's first step (see the file header).
class UsdWithdrawScreen extends ConsumerStatefulWidget {
  const UsdWithdrawScreen({super.key});

  /// Test seam: what the Bitcoin card opens. Null opens the real Move
  /// money sheet, Dollars to Bitcoin.
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugMoveSheetOpener;

  /// Test seam: what a picked coin opens. Null opens the dollar send
  /// over this sheet; the answer is whether the send went out.
  @visibleForTesting
  static Future<bool?> Function(
      BuildContext context, UsdSendDestination destination)? debugSendOpener;

  @override
  ConsumerState<UsdWithdrawScreen> createState() => _UsdWithdrawScreenState();
}

class _UsdWithdrawScreenState extends ConsumerState<UsdWithdrawScreen> {
  @override
  void initState() {
    super.initState();
    TrackingService.screenView('usd_withdraw');
    // The offering is live-catalogue only, so nudge it rather than
    // waiting for the 6 h cadence.
    // ignore: discarded_futures
    ref.read(orchestraSupportedRoutesProvider.notifier).refresh();
  }

  /// The Bitcoin card: the Move money sheet from Dollars to Bitcoin.
  void _openToBitcoin() {
    final open = UsdWithdrawScreen.debugMoveSheetOpener;
    if (open != null) {
      TrackingService.markEntrySource('move', kUsdWithdrawBitcoinRowSource);
      unawaited(open(context));
      return;
    }
    unawaited(showMoneyMovementSheet(
      context,
      initialSource: MoneyMovementAccount.dollars,
      initialDestination: MoneyMovementAccount.bitcoin,
      entrySource: kUsdWithdrawBitcoinRowSource,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ReceiveSheetFrame(
      leading:
          KuteCloseButton(onPressed: () => Navigator.of(context).maybePop()),
      // The balance the money leaves from, read-only, where the Deposit
      // names the balance it lands in. No step bar.
      title: AccountSwitcherPill(
        pickerTitle: l10n.sendFromPickerTitle,
        readOnly: true,
        label: l10n.assetDollars,
      ),
      semanticTitle: l10n.withdraw,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
        child: _buildFirstStep(context),
      ),
    );
  }

  /// The coins the dollars can be sent out as, folded one per coin: the
  /// set the dollar send's own grid and coin sheet offer.
  List<UsdSendDestination> _offered() =>
      usdSendOfferedDestinations(ref.watch(orchestraSupportedRoutesProvider))
          .offered;

  /// Top to bottom, as the Deposit: "To your wallet" over the Bitcoin
  /// card, then "To another wallet or exchange" over the coin grid.
  Widget _buildFirstStep(BuildContext context) {
    final l10n = context.l10n;
    // Still fetching is not the same as nothing to offer.
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final offered = _offered();
    final groups = coinGroupsOfferedUnderPolicy(
      groupCoinsByAsset([for (final d in offered) usdSendDestinationOption(d)]),
      otherLegAsset: kOrchestraUsdAssetCode,
    ).groups;
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SendToSectionHeader(title: l10n.usdWithdrawToYourWallet),
          UsdBitcoinCard(
            rowKey: const ValueKey('usd-withdraw-to-bitcoin'),
            buttonKey: const ValueKey('usd-withdraw-to-bitcoin-button'),
            balance: watchSpendingBitcoinUsd(ref),
            buttonLabel: l10n.usdWithdrawNow,
            onTap: _openToBitcoin,
          ),
          SizedBox(height: 24.h),
          // Send to anyone: a link the recipient claims with Kute (a
          // pending dollar send, models/share_link_model.dart).
          SendToListCard(
            colors: context.colors,
            rows: [
              SendToListRow(
                key: const ValueKey('usd-withdraw-send-to-anyone'),
                colors: context.colors,
                leading: Icon(Icons.ios_share_rounded,
                    color: context.colors.textPrimary, size: 20.sp),
                title: l10n.shareSendToAnyone,
                subtitle: l10n.shareSendToAnyoneSubtitle,
                onTap: () => unawaited(showSendToAnyoneSheet(
                  context,
                  kind: ShareLinkKind.dollars,
                  entrySource: kUsdWithdrawSheetSource,
                )),
              ),
            ],
          ),
          SizedBox(height: 24.h),
          if (groups.isEmpty)
            ReceiveCaption(
              text: loading
                  ? l10n.usdSendRoutesUnavailable
                  : l10n.usdSendDestinationsUnavailable,
            )
          else ...[
            SendToSectionHeader(title: l10n.usdWithdrawToAnotherWallet),
            Expanded(
              child: CoinAssetGrid(
                key: const ValueKey('usd-withdraw-coin-grid'),
                groups: groups,
                emptyLabel: l10n.usdSendDestinationsUnavailable,
                markBuilder: (g, size) =>
                    AssetIcon(assetCode: g.assetCode, size: size),
                onPick: _pickGroup,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A coin tapped on the grid: one network goes straight to the send;
  /// several open the coin sheet on that coin's networks first.
  void _pickGroup(CoinAssetGroup group) {
    TrackingService.track('coin_picker_coin_picked', params: {
      'flow': 'usd_withdraw',
      'asset': group.assetCode,
      'networks': group.options.length,
    });
    if (group.isSingleNetwork) {
      unawaited(() async {
        // A coin only a region refuses stays listed; its tap says why
        // instead of opening the send.
        if (await coinPickStoppedByRegion(context, group.options.first,
                otherLegAsset: kOrchestraUsdAssetCode,
                surface: 'usd_withdraw') ||
            !mounted) {
          return;
        }
        final d = _destinationFor(group.options.first);
        if (d != null) unawaited(_openSend(d));
      }());
      return;
    }
    _openCoinPicker(initialGroupKey: group.key);
  }

  /// The offered destination a picker row stands for, matched by
  /// `chain:assetCode`.
  UsdSendDestination? _destinationFor(OrchestraReceiveOption row) {
    final id = '${row.chain}:${row.assetCode}';
    return usdSendOfferedDestinations(
            ref.read(orchestraSupportedRoutesProvider))
        .offered
        .where((d) => d.id == id)
        .firstOrNull;
  }

  /// The coin sheet the dollar send opens, on [initialGroupKey]'s
  /// networks.
  void _openCoinPicker({String? initialGroupKey}) {
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          final choices = usdSendOfferedDestinations(catalog).offered;
          return CoinAssetPickerSheet(
            otherLegAsset: kOrchestraUsdAssetCode,
            groups: groupCoinsByAsset(
                [for (final d in choices) usdSendDestinationOption(d)]),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: ctx.l10n.usdSendPickCoin,
            emptyLabel: loading
                ? ctx.l10n.usdSendRoutesUnavailable
                : ctx.l10n.usdSendDestinationsUnavailable,
            flow: 'usd_withdraw',
            initialAssetCode: initialGroupKey,
            onPicked: (row) {
              final picked = choices
                  .where((d) => d.id == '${row.chain}:${row.assetCode}')
                  .firstOrNull;
              if (picked == null) return;
              Navigator.of(sheetCtx).pop();
              unawaited(_openSend(picked));
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// The dollar send over this sheet, the coin already picked. A send
  /// that went out closes this sheet behind its success screen.
  Future<void> _openSend(UsdSendDestination destination) async {
    TrackingService.markEntrySource('usd_send', kUsdWithdrawSheetSource);
    final open = UsdWithdrawScreen.debugSendOpener;
    final sent = open != null
        ? await open(context, destination)
        : await showSendSheet<bool>(
            context,
            builder: (_) => UsdSendScreen(initialDestination: destination),
          );
    if (sent != true || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }
}
