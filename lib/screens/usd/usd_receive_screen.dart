// Receiving another coin from another network, a sheet over the current
// screen: the Dollars receive (into `spark:USDB`, with "From your wallet"
// over the Bitcoin card first) and the Bitcoin receive's "other coins"
// (into `spark:BTC`). Every coin is a ONE-TIME quoted deposit address
// (onetime_receive.dart): a picked coin asks its amount in the "Request
// amount" sheet and then shows its address (quoted_receive_screen.dart).
// No reusable deposit address is ever created here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide, showDepositSheet;
import 'package:kute/screens/receive/quoted_receive_screen.dart'
    show openOneTimeReceive, prefetchOneTimeReceiveMinimums;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard, SendToListRow, SendToSectionHeader;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/receive_minimums.dart'
    show receiveMinimumsProvider;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Move sheet's `entry_source` when the Bitcoin card ("From your
/// wallet") at the top of this screen opens it.
const String kUsdReceiveBitcoinRowSource = 'usd_receive_bitcoin_row';

/// The `chain:asset` id the coin sheet selects by.
String usdReceiveCoinId(OrchestraReceiveOption o) =>
    '${o.chain}:${o.assetCode}';

/// The receive of another coin, a sheet over the current screen
/// (`showUsdReceiveSheet` / `showOtherCoinsReceiveSheet`, or the
/// `receiveDollars` route's sheet page).
///
/// Into Dollars ([destinationAsset] `USDB`, the default) it opens on two
/// labelled choices: "From your wallet" over the Bitcoin card (the Move
/// sheet's way in from the spending bitcoin), then "From another wallet or
/// exchange" over the coin grid. Into Bitcoin (`BTC`, the Bitcoin
/// receive's "other coins") it is the coin grid alone. A picked coin asks
/// its amount and shows its one-time address; nothing is ever picked for
/// the person.
class UsdReceiveScreen extends ConsumerStatefulWidget {
  const UsdReceiveScreen(
      {super.key, this.destinationAsset = kOrchestraUsdAssetCode});

  /// What the coins are converted into: the dollar balance (`USDB`) or
  /// the wallet's bitcoin (`BTC`).
  final String destinationAsset;

  /// Test seam: what the Bitcoin card opens. Null opens the
  /// real Move sheet ([showDepositSheet]).
  @visibleForTesting
  static Future<void> Function(BuildContext context,
      {required MoveLockedSide lockedSide})? debugDepositSheetOpener;

  @override
  ConsumerState<UsdReceiveScreen> createState() => _UsdReceiveScreenState();
}

class _UsdReceiveScreenState extends ConsumerState<UsdReceiveScreen> {
  /// The picked coin, as the live catalogue spells it.
  OrchestraReceiveOption? _option;

  /// Routes whose minimum this sheet already asked for.
  final Set<String> _prefetched = {};

  /// After the grid's frame, reads the live minimum of every route it
  /// lists that this sheet has not asked for yet, in the background, so
  /// the amount sheet usually has it before a coin is tapped.
  void _prefetchMinimums(List<CoinAssetGroup> groups) {
    final fresh = [
      for (final g in groups)
        for (final o in g.options)
          if (_prefetched.add(usdReceiveCoinId(o))) o,
    ];
    if (fresh.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      prefetchOneTimeReceiveMinimums(ref.read(receiveMinimumsProvider), fresh,
          destinationAsset: widget.destinationAsset);
    });
  }

  bool get _dollars => widget.destinationAsset == kOrchestraUsdAssetCode;

  bool get _spendingIsActive {
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    return spending != null && spending.id == settings.activeWalletId;
  }

  @override
  void initState() {
    super.initState();
    if (_dollars) {
      TrackingService.screenView('usd_receive');
      TrackingService.moneyFlowStarted(
        'usd_receive',
        event: 'usd_receive_opened',
        entrySource:
            TrackingService.takeEntrySource('usd_receive', fallback: 'usd'),
        props: {'source': 'usd', 'presentation': 'sheet'},
      );
    } else {
      // Part of the Bitcoin receive, whose own funnel ("receive") is
      // still open underneath.
      TrackingService.screenView('receive_other_coins');
    }
    // The offering is live-catalogue only, so nudge it rather than
    // waiting for the 6 h cadence.
    // ignore: discarded_futures
    ref.read(orchestraSupportedRoutesProvider.notifier).refresh();
  }

  /// The spending bitcoin's balance in dollars, as the Move sheet's
  /// Bitcoin row prints it (floored to the cent), or null while unknown.
  String? _spendingBitcoinUsd() {
    try {
      final spending = pickSpendingWallet(ref.watch(settingsProvider));
      if (spending == null) return null;
      final sats = ref
          .watch(walletBalanceCacheProvider)[spending.id]
          ?.sparkBitcoinbalance;
      final rate = ref.watch(selectedCurrencyProvider('USD')).toDouble();
      if (sats == null || rate <= 0) return null;
      final usd = sats / 1e8 * rate;
      return '\$${((usd * 100).floor() / 100).toStringAsFixed(2)}';
    } catch (_) {
      return null;
    }
  }

  /// The Bitcoin card: the Investments deposit from the spending
  /// bitcoin, the Move sheet the dock's old Deposit opened.
  void _openFromBitcoin() {
    TrackingService.markEntrySource('move', kUsdReceiveBitcoinRowSource);
    final open = UsdReceiveScreen.debugDepositSheetOpener ?? showDepositSheet;
    unawaited(open(context, lockedSide: MoveLockedSide.depositToUsd));
  }

  /// The coin step's first choice, under its "From your wallet" label, in
  /// the Send-to step's list card: the Bitcoin mark, "Bitcoin" over the
  /// spending wallet's dollar balance, and a compact Add button. The
  /// whole card and the button both open the Move sheet, and the pair
  /// reads to assistive tech as one button.
  Widget _bitcoinRow(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final balance = _spendingBitcoinUsd();
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SendToListCard(
          colors: c,
          rows: [
            SendToListRow(
              key: const ValueKey('usd-receive-from-bitcoin'),
              leading: SvgPicture.asset('lib/assets/bitcoin-icon.svg',
                  width: 40.sp, height: 40.sp),
              title: l10n.bitcoin,
              // The Bitcoin balance alone: the card is "Bitcoin", the
              // tab's name, never "spending wallet" (founder decision).
              subtitle: balance,
              trailing: _bitcoinRowButton(context),
              colors: c,
              onTap: _openFromBitcoin,
            ),
          ],
        ),
      ),
    );
  }

  /// The Bitcoin card's explicit action: the app's compact filled
  /// button (as a claim row draws it), sized to its label at the
  /// current text scale and capped so the title keeps its room.
  Widget _bitcoinRowButton(BuildContext context) {
    final label = context.l10n.moveAdd;
    final fontSize = 14.sp;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            )),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final labelWidth = painter.width;
    painter.dispose();
    final maxWidth = MediaQuery.sizeOf(context).width * 0.34;
    final width = (labelWidth + 32.w).clamp(72.w, maxWidth).toDouble();
    return SizedBox(
      key: const ValueKey('usd-receive-from-bitcoin-button'),
      width: width,
      child: AppButton(
        text: label,
        compact: true,
        height: 36.h,
        fontSize: fontSize,
        onPressed: _openFromBitcoin,
      ),
    );
  }

  @override
  void dispose() {
    if (_dollars) {
      TrackingService.moneyFlowAbandoned('usd_receive', props: {
        'address_kind': 'onetime',
        if (_option != null)
          ...TrackingService.routeParams(
            fromAsset: _option!.assetCode,
            fromNetwork: _option!.chain,
            toAsset: 'usd',
            toNetwork: 'spark',
            provider: 'orchestra',
          ),
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(orchestraSupportedRoutesProvider);
    ref.listen(
        settingsProvider.select(
            (s) => (s.activeWalletId, pickSpendingWallet(s)?.id)), (old, next) {
      if (old == next) return;
      setState(() => _option = null);
    });
    final l10n = context.l10n;
    return ReceiveSheetFrame(
      leading: KuteCloseButton(
          onPressed: () => unawaited(Navigator.of(context).maybePop())),
      // The balance the money lands in, read-only, where the bitcoin
      // receive names its wallet. No step bar.
      title: AccountSwitcherPill(
        pickerTitle: l10n.receiveInto,
        readOnly: true,
        label: _dollars ? l10n.assetDollars : l10n.bitcoin,
      ),
      semanticTitle: _dollars ? l10n.usdReceiveTitle : l10n.receiveBitcoin,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
        child: !_spendingIsActive
            ? UsdFlowNote(lines: [l10n.receiveOtherCoinsSpendingOnly])
            : _buildCoinStep(context),
      ),
    );
  }

  /// The coins that can be received into this balance, folded one per
  /// coin, minus what the runtime policy withdraws: the same set the
  /// sheet offers, so the grid on the step and the grid in the sheet can
  /// never disagree.
  List<CoinAssetGroup> _coinGroups() => coinGroupsOfferedUnderPolicy(
        receiveCoinGroups(
          ref.watch(orchestraSupportedRoutesProvider),
          context.l10n,
          destinationAsset: widget.destinationAsset,
        ),
        otherLegAsset: widget.destinationAsset,
        depositAddress: true,
      ).groups;

  /// Top to bottom: into Dollars, "From your wallet" over the Bitcoin card
  /// (the Move sheet from the spending bitcoin); then "From another wallet
  /// or exchange" over the coin grid, asked ASSET FIRST as every money
  /// screen asks it: a coin on one network goes straight to its amount, a
  /// coin on several opens the sheet on its networks.
  Widget _buildCoinStep(BuildContext context) {
    final l10n = context.l10n;
    // Still fetching is not the same as nothing to offer. Until the
    // first load settles the step says so, and only after it does may
    // an empty offering be called unavailable.
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final groups = _coinGroups();
    _prefetchMinimums(groups);
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_dollars) ...[
            SendToSectionHeader(title: l10n.usdReceiveFromYourWallet),
            _bitcoinRow(context),
            SizedBox(height: 24.h),
          ],
          if (groups.isEmpty)
            UsdFlowNote(lines: [
              loading
                  ? l10n.usdReceiveRoutesUnavailable
                  : l10n.usdReceiveCoinsUnavailable,
            ])
          else ...[
            SendToSectionHeader(title: l10n.usdReceiveFromAnotherWallet),
            Expanded(
              child: CoinAssetGrid(
                groups: groups,
                emptyLabel: l10n.usdReceiveCoinsUnavailable,
                selectedKey: _selectedGroupKey(groups),
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

  /// The grid cell to check: the coin the picked network belongs to.
  String? _selectedGroupKey(List<CoinAssetGroup> groups) {
    final option = _option;
    if (option == null) return null;
    final id = usdReceiveCoinId(option);
    for (final group in groups) {
      if (group.options.any((o) => usdReceiveCoinId(o) == id)) {
        return group.key;
      }
    }
    return null;
  }

  /// A coin tapped on the step's grid: one network goes straight to its
  /// amount; several open the sheet on that coin's networks.
  void _pickGroup(CoinAssetGroup group) {
    TrackingService.track('coin_picker_coin_picked', params: {
      'flow': _dollars ? 'usd_receive' : 'receive_other_coins',
      'asset': group.assetCode,
      'networks': group.options.length,
    });
    if (group.isSingleNetwork) {
      unawaited(_pick(group.options.first));
      return;
    }
    _openCoinPicker(initialGroupKey: group.key);
  }

  /// The sheet itself, open on [initialGroupKey]'s networks.
  void _openCoinPicker({String? initialGroupKey}) {
    if (_dollars) TrackingService.track('usd_receive_coin_picker_opened');
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          // Watch so the offering re-folds the moment the live
          // catalogue lands.
          final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          return CoinAssetPickerSheet(
            otherLegAsset: widget.destinationAsset,
            depositAddress: true,
            groups: receiveCoinGroups(
              catalog,
              ctx.l10n,
              destinationAsset: widget.destinationAsset,
            ),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: _dollars
                ? ctx.l10n.usdReceivePickCoin
                : ctx.l10n.receiveAlsoAcceptsSubtitle,
            emptyLabel: loading
                ? ctx.l10n.usdReceiveRoutesUnavailable
                : ctx.l10n.usdReceiveCoinsUnavailable,
            flow: _dollars ? 'usd_receive' : 'receive_other_coins',
            initialAssetCode: initialGroupKey,
            selectedOptionId:
                _option == null ? null : usdReceiveCoinId(_option!),
            onPicked: (option) {
              Navigator.of(sheetCtx).pop();
              unawaited(_pick(option));
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// The person picked [option]: its amount, then its one-time address.
  /// The screen never picks one itself, so `preselected` is always false.
  Future<void> _pick(OrchestraReceiveOption option) async {
    if (!_spendingIsActive ||
        !oneTimeReceiveAllowed(RuntimeCapabilitiesService.instance)) {
      return;
    }
    final props = <String, Object>{
      'asset': option.assetCode,
      'chain': option.chain,
      'address_kind': 'onetime',
    };
    if (_dollars) {
      TrackingService.swapAssetSelected(
          flow: 'receive_dollars', asset: option.assetCode);
      TrackingService.track('usd_receive_coin_selected', params: {
        ...props,
        'preselected': false,
        'preselect_reason': 'none',
      });
      TrackingService.moneyFlowStep('usd_receive', 'coin_selected',
          props: props);
    } else {
      TrackingService.moneyFlowStep('receive', 'coin_selected',
          props: {...props, 'destination': 'spark_btc'});
    }
    TrackingService.receiveSourceSelected(
        asset: option.assetCode, network: option.chain, provider: 'orchestra');
    setState(() => _option = option);
    await openOneTimeReceive(context, ref,
        option: option, destinationAsset: widget.destinationAsset);
  }
}
