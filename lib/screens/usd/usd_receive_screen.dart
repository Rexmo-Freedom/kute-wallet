// Receiving another coin from another network, a sheet over the current
// screen: the Dollars receive (into `spark:USDB`, with "From your wallet"
// over the Bitcoin card first) and the Bitcoin receive's "other coins".
//
// REUSABLE FIRST (founder, 2026-10-19; reusable_deposit_address.dart): a
// picked coin the standing route may serve shows its reusable standing
// address to `spark:USDB` in its own sheet over this one
// ([UsdStandingAddressSheet]: QR, address, the coin and network, the
// minimum; never a Kute fee line); closing it comes back here as it was.
// From the Bitcoin receive that address lands in Investments: it says so
// ("Into your Investments balance"), and its deposits also show in the
// Bitcoin Activity (BitcoinReceiveMarks). Where the standing route cannot
// serve the coin (not on the standing rail, refused by the backend, denied
// by the policy, or no address on the source chain), the ONE-TIME flow
// takes over (onetime_receive.dart): the "Request amount" sheet, the
// return-address sheet, then the quoted address sheet
// (quoted_receive_screen.dart), each over this one
// into the receive's own destination (`spark:USDB`, or `spark:BTC` from the
// Bitcoin receive, whose screens say Bitcoin). Coins only a one-time quote
// can serve go straight there. Never a legacy accumulation address.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_operation_guard.dart' show runSparkQuote;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide, showDepositSheet;
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart'
    show openOneTimeReceive, prefetchOneTimeReceiveMinimums;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart'
    show AppButton, AppButtonVariant;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard, SendToListRow, SendToSectionHeader;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/services/orchestra/bitcoin_receive_marks.dart'
    show BitcoinReceiveMarks;
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart'
    show
        orchestraExchangeStatusIsTerminal,
        kOrchestraUsdAssetCode,
        orchestraReceiveChainForDestination;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/wallet_guard_exception.dart'
    show WalletGuardException;
import 'package:kute/services/success_feedback.dart' show moneyFailureFeedback;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Move sheet's `entry_source` when the Bitcoin card ("From your
/// wallet") at the top of this screen opens it.
const String kUsdReceiveBitcoinRowSource = 'usd_receive_bitcoin_row';

/// The `entry_source` on the events of the Bitcoin receive's "other
/// coins" (this screen into `BTC`).
const String kUsdReceiveFromBitcoinReceiveSource = 'bitcoin_receive';

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
/// receive's "other coins") it is the coin grid alone. A picked coin shows
/// its reusable address in a sheet over this one, or, where only a
/// one-time address serves it, asks its amount and shows that the same
/// way; nothing is ever picked for the person.
class UsdReceiveScreen extends ConsumerStatefulWidget {
  const UsdReceiveScreen(
      {super.key, this.destinationAsset = kOrchestraUsdAssetCode});

  /// What a one-time address converts the coins into: the dollar balance
  /// (`USDB`) or the wallet's bitcoin (`BTC`). A reusable address always
  /// pays the dollar balance.
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

  /// `standing` or `onetime`: what the last pick was served by.
  String? _addressKind;

  /// Whether the reusable address sheet over this one has an address on
  /// it, for the funnel's `address_shown` when this sheet closes.
  bool _addressShown = false;

  /// Bumped by every pick and by a wallet switch, so a fallback answered
  /// by an address sheet opened for an older pick opens nothing.
  int _pickId = 0;

  /// Routes whose minimum this sheet already asked for.
  final Set<String> _prefetched = {};

  bool get _dollars => widget.destinationAsset == kOrchestraUsdAssetCode;

  bool get _spendingIsActive {
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    return spending != null && spending.id == settings.activeWalletId;
  }

  /// After the grid's frame, reads the live minimum of every one-time
  /// route it lists that this sheet has not asked for yet, in the
  /// background, so the amount sheet usually has it before a coin is
  /// tapped.
  void _prefetchMinimums(List<CoinAssetGroup> groups) {
    final fresh = [
      for (final g in groups)
        for (final o in g.options)
          if (!o.reusableAddress && _prefetched.add(usdReceiveCoinId(o))) o,
    ];
    if (fresh.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      prefetchOneTimeReceiveMinimums(ref.read(receiveMinimumsProvider), fresh,
          destinationAsset: widget.destinationAsset);
    });
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
    final label = context.l10n.usdReceiveDepositNow;
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
      TrackingService.moneyFlowAbandoned('usd_receive',
          props: usdReceiveFlowInputs(
              dollars: _dollars,
              addressKind: _addressKind,
              addressShown: _addressShown,
              option: _option));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-fold the grid as soon as catalog support changes.
    ref.watch(orchestraSupportedRoutesProvider);
    // Kept alive while an address sheet is over this one, so coming back
    // never re-reads the standing destinations.
    ref.watch(standingDestinationsProvider);
    ref.listen(
        settingsProvider.select(
            (s) => (s.activeWalletId, pickSpendingWallet(s)?.id)), (old, next) {
      if (old == next) return;
      _clearWalletAddress();
    });
    final l10n = context.l10n;
    return ReceiveSheetFrame(
      leading: KuteCloseButton(onPressed: _onBack),
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
            ? Padding(
                padding: EdgeInsets.only(top: 12.h),
                child: ReceiveCaption(text: l10n.receiveOtherCoinsSpendingOnly),
              )
            : _buildCoinStep(context),
      ),
    );
  }

  /// The coins that can be received here, folded one per coin, minus
  /// what the runtime policy withdraws: the same set the sheet offers, so
  /// the grid on the step and the grid in the sheet can never disagree.
  /// Reusable rows pay the dollar balance, one-time rows this receive's
  /// destination.
  List<CoinAssetGroup> _coinGroups() => coinGroupsOfferedUnderPolicy(
        receiveCoinGroups(
          ref.watch(orchestraSupportedRoutesProvider),
          context.l10n,
          destinationAsset: widget.destinationAsset,
          standingDestinations:
              ref.watch(standingDestinationsProvider).valueOrNull,
        ),
        otherLegAsset: widget.destinationAsset,
        reusableLegAsset: kOrchestraUsdAssetCode,
        depositAddress: true,
      ).groups;

  /// Top to bottom: into Dollars, "From your wallet" over the Bitcoin card
  /// (the Move sheet from the spending bitcoin); then "From another wallet
  /// or exchange" over the coin grid, asked ASSET FIRST as every money
  /// screen asks it: a coin on one network goes straight to its address
  /// (or amount), a coin on several opens the sheet on its networks.
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
            ReceiveCaption(
              text: loading
                  ? l10n.usdReceiveRoutesUnavailable
                  : l10n.usdReceiveCoinsUnavailable,
            )
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

  /// A coin tapped on the step's grid: one network goes straight to it;
  /// several open the sheet on that coin's networks.
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
          final destinations =
              sheetRef.watch(standingDestinationsProvider).valueOrNull;
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          return CoinAssetPickerSheet(
            otherLegAsset: widget.destinationAsset,
            reusableLegAsset: kOrchestraUsdAssetCode,
            depositAddress: true,
            closeOnLeft: true,
            groups: receiveCoinGroups(
              catalog,
              ctx.l10n,
              destinationAsset: widget.destinationAsset,
              standingDestinations: destinations,
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

  /// The person picked [option]; the screen never picks one itself, so
  /// `preselected` is always false. A reusable row shows its standing
  /// address unless the standing route can no longer serve it; a one-time
  /// row (and a reusable row that falls back) asks its amount for a
  /// one-time address.
  Future<void> _pick(OrchestraReceiveOption option) async {
    if (!_spendingIsActive) return;
    _pickId++;
    final standingFallback = standingReceiveFallback(
        sourceChain: option.chain,
        sourceAsset: option.assetCode,
        destinations: ref.read(standingDestinationsProvider).valueOrNull ??
            StandingDepositStore.cachedDestinations);
    final StandingFallbackReason? fallback = option.reusableAddress
        ? standingFallback
        : standingFallback ?? StandingFallbackReason.standingUnserved;
    if (fallback != null) {
      final oneTime = oneTimeFallbackOption(
          ref.read(orchestraSupportedRoutesProvider), option,
          destinationAsset: widget.destinationAsset);
      if (oneTime != null) {
        _trackCoinSelected(oneTime, 'onetime', fallback);
        await _openOneTime(oneTime, fallback);
        return;
      }
      // Nothing else serves a one-time row; a reusable row's address sheet
      // says the coin is unavailable (no request is made for it, and it
      // is not a failure: the step says why).
      if (!option.reusableAddress) return;
    }
    _trackCoinSelected(option, 'standing', fallback);
    setState(() {
      _option = option;
      _addressKind = 'standing';
    });
    await _openStandingAddress(option, unavailable: fallback);
  }

  /// The reusable address of [option], in its own sheet over this one.
  /// Closing it comes back here as it was. Where the standing route turns
  /// out not to serve the coin, that sheet closes with the one-time
  /// option and the reason, and the one-time flow takes over from here.
  Future<void> _openStandingAddress(OrchestraReceiveOption option,
      {StandingFallbackReason? unavailable}) async {
    final pickId = _pickId;
    final fallback = await showAppBottomSheet<UsdStandingFallback>(
      context: context,
      builder: (_) => UsdStandingAddressSheet(
        option: option,
        destinationAsset: widget.destinationAsset,
        unavailable: unavailable,
        onAddressShown: (shown) => _addressShown = shown,
      ),
    );
    if (!mounted) return;
    _addressShown = false;
    if (fallback == null || pickId != _pickId || !_spendingIsActive) return;
    await _openOneTime(fallback.option, fallback.reason);
  }

  /// `usd_receive_coin_selected` and the coin step, in this sheet's
  /// funnel, with what serves the pick and why it fell back.
  void _trackCoinSelected(OrchestraReceiveOption option, String addressKind,
      StandingFallbackReason? fallback) {
    final props = <String, Object>{
      'asset': option.assetCode,
      'chain': option.chain,
      'address_kind': addressKind,
      if (fallback != null) 'fallback_reason': fallback.analytics,
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
      TrackingService.moneyFlowStep('receive', 'coin_selected', props: {
        ...props,
        'destination': addressKind == 'standing' ? 'spark_usd' : 'spark_btc',
      });
    }
    TrackingService.receiveSourceSelected(
        asset: option.assetCode, network: option.chain, provider: 'orchestra');
  }

  /// The one-time flow for [option] (its amount, return address and
  /// quoted address) because the standing route could not serve it.
  Future<void> _openOneTime(
      OrchestraReceiveOption option, StandingFallbackReason fallback) async {
    _pickId++;
    setState(() {
      _option = option;
      _addressKind = 'onetime';
    });
    await openOneTimeReceive(context, ref,
        option: option,
        destinationAsset: widget.destinationAsset,
        fallbackReason: fallback.analytics);
  }

  void _onBack() {
    _pickId++;
    Navigator.of(context).maybePop();
  }

  /// A wallet switch: nothing picked any more. An address sheet over this
  /// one closes itself (it listens for the same switch).
  void _clearWalletAddress() {
    _pickId++;
    setState(() {
      _option = null;
      _addressShown = false;
    });
  }
}

/// What every event of the reusable address (and the coin sheet's
/// abandon) says about it. Exact values only; never the address or its id.
Map<String, Object> usdReceiveFlowInputs({
  required bool dollars,
  required String? addressKind,
  required bool addressShown,
  required OrchestraReceiveOption? option,
}) =>
    {
      if (!dollars) 'entry_source': kUsdReceiveFromBitcoinReceiveSource,
      if (addressKind != null) 'address_kind': addressKind,
      'address_shown': addressShown,
      if (option != null)
        ...TrackingService.routeParams(
          fromAsset: option.assetCode,
          fromNetwork: option.chain,
          toAsset: 'usd',
          toNetwork: 'spark',
          provider: 'orchestra',
        ),
    };

/// What a reusable address sheet answers when the standing route turned
/// out not to serve its coin: the one-time option that does, and why.
typedef UsdStandingFallback = ({
  OrchestraReceiveOption option,
  StandingFallbackReason reason,
});

/// The reusable (standing) address of a coin to `spark:USDB`, a sheet
/// over the coin sheet in the receive sheet's frame: the close X and
/// "Investments" (it always pays the dollar balance, also from the
/// Bitcoin receive), then the code, the address with copy, the minimum,
/// Share and the coin and network. Closing it comes back to the coin
/// sheet as it was. Where the standing route cannot serve the coin and a
/// one-time address can, it closes with a [UsdStandingFallback].
class UsdStandingAddressSheet extends ConsumerStatefulWidget {
  const UsdStandingAddressSheet({
    super.key,
    required this.option,
    required this.destinationAsset,
    this.unavailable,
    this.onAddressShown,
  });

  final OrchestraReceiveOption option;

  /// Why the standing route will not serve [option] when that is already
  /// known and no one-time address serves it either: the sheet then only
  /// says the coin is unavailable, asks nothing and counts nothing (the
  /// coin step already said why).
  final StandingFallbackReason? unavailable;

  /// The receive this sheet belongs to: `USDB` (the Dollars receive) or
  /// `BTC` (the Bitcoin receive's "other coins"), which decides the funnel
  /// and the one-time fallback's destination. The address itself always
  /// pays the dollar balance.
  final String destinationAsset;

  /// Told whether an address is on the sheet, each time that changes.
  final ValueChanged<bool>? onAddressShown;

  @override
  ConsumerState<UsdStandingAddressSheet> createState() =>
      _UsdStandingAddressSheetState();
}

class _UsdStandingAddressSheetState
    extends ConsumerState<UsdStandingAddressSheet> {
  /// The reusable address on screen, as a local display row. Deliberately
  /// never written to `swapOrdersProvider` at creation: an Orchestra
  /// deposit address has no order id until a deposit lands, so a row
  /// written now would make background sync poll an id that never
  /// resolves. The poller records the real `ord_…` when it appears.
  SwapOrder? _display;
  StandingDepositRecord? _standing;

  /// The smallest deposit the shown address takes, keyed by that address
  /// so a later address never inherits it. Null until known: the address
  /// never waits for it.
  ({String address, ReceiveMinimum minimum})? _displayMinimum;

  String? _error;

  int _requestId = 0;
  bool Function()? _sameSdk;

  /// Set once the sheet is closing (a fallback or a wallet switch), so
  /// nothing more happens on it.
  bool _closing = false;

  bool _terminalTracked = false;

  late final OrchestraDepositPoller _poller = OrchestraDepositPoller(ref);

  OrchestraReceiveOption get _option => widget.option;

  bool get _dollars => widget.destinationAsset == kOrchestraUsdAssetCode;

  bool get _spendingIsActive {
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    return spending != null && spending.id == settings.activeWalletId;
  }

  @override
  void initState() {
    super.initState();
    if (widget.unavailable == null) unawaited(_createReusableAddress(_option));
  }

  @override
  void dispose() {
    _requestId++;
    _poller.cancel();
    super.dispose();
  }

  Map<String, Object> _flowInputs() => usdReceiveFlowInputs(
      dollars: _dollars,
      addressKind: 'standing',
      addressShown: _display != null,
      option: _option);

  /// One step of the reusable address, in the funnel this sheet belongs
  /// to: the Dollars receive's own, or the Bitcoin receive's.
  void _flowStep(String step, Map<String, Object> props) {
    if (_dollars) {
      TrackingService.moneyFlowStep('usd_receive', step, props: props);
    } else {
      TrackingService.moneyFlowStep('receive', step,
          props: {...props, 'destination': 'spark_usd'});
    }
  }

  void _trackTerminal(SwapOrder order) {
    if (_terminalTracked || !orchestraExchangeStatusIsTerminal(order.status)) {
      return;
    }
    _terminalTracked = true;
    final ok = order.status == 'success';
    final props = <String, Object>{
      ..._flowInputs(),
      'status': order.status,
      if (!ok) 'error_category': 'settlement',
      if (!ok) 'stage': 'settle',
    };
    if (_dollars) {
      TrackingService.track(ok ? 'usd_receive_completed' : 'usd_receive_failed',
          params: props);
      TrackingService.moneyFlowFinished('usd_receive');
    } else {
      _flowStep(ok ? 'deposit_completed' : 'deposit_failed', props);
    }
  }

  void _setDisplay(SwapOrder? display) {
    _display = display;
    widget.onAddressShown?.call(display != null);
  }

  /// The sheet is going (the X, a swipe, the system back, a fallback or
  /// a wallet switch): nothing more happens on it. A registration still
  /// in flight lands silently: no address, no event, no poller, and
  /// never a second pop (the sheet stays mounted through its close
  /// animation, and a pop then would take the coin sheet with it).
  void _onClosing() {
    if (_closing) return;
    _closing = true;
    _requestId++;
    _poller.cancel();
    _sameSdk = null;
  }

  /// Closes this sheet once the current frame is done, with [result].
  void _close([UsdStandingFallback? result]) {
    if (_closing) return;
    _onClosing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only this sheet's own route: one already popping, or one under
      // another, is never popped from here.
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) return;
      Navigator.of(context).pop<UsdStandingFallback>(result);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    // Retire an already displayed route as soon as catalog support changes.
    ref.watch(orchestraSupportedRoutesProvider);
    // A wallet switch ends the address: the sheet closes back to the coin
    // sheet, which clears its pick on the same switch.
    ref.listen(
        settingsProvider.select(
            (s) => (s.activeWalletId, pickSpendingWallet(s)?.id)), (old, next) {
      if (old == next) return;
      setState(() {
        _setDisplay(null);
        _standing = null;
        _error = null;
      });
      _close();
    });
    // A reconnect (a rebuilt SDK) never ends a shown address: it pays the
    // wallet's own Spark address, which the new SDK keeps. One still being
    // set up under the old SDK is set up again.
    ref.listen(breezSDKProvider, (old, next) {
      if (!_closing &&
          _display == null &&
          _error == null &&
          _sameSdk != null &&
          !_sameSdk!()) {
        _sameSdk = null;
        unawaited(_createReusableAddress(_option));
      }
    });
    final l10n = context.l10n;
    return PopScope(
      // A swipe or the system back: the sheet is going.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _onClosing();
      },
      child: ReceiveSheetFrame(
        leading: KuteCloseButton(onPressed: _close),
        // The reusable address always pays the dollar balance: the title
        // names it, also when opened from the Bitcoin receive. No step bar.
        title: AccountSwitcherPill(
          pickerTitle: l10n.receiveInto,
          readOnly: true,
          label: l10n.assetDollars,
        ),
        semanticTitle: l10n.usdReceiveTitle,
        child: Padding(
          // The coin sheet's body inset plus its address step's, as the
          // Bitcoin receive opens on its code.
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
          child: !_spendingIsActive
              ? Padding(
                  padding: EdgeInsets.only(top: 12.h),
                  child:
                      ReceiveCaption(text: l10n.receiveOtherCoinsSpendingOnly),
                )
              : _buildAddressStep(context),
        ),
      ),
    );
  }

  /// Uses the same QR, address and action sizing as Bitcoin receive.
  Widget _buildAddressStep(BuildContext context) {
    final l10n = context.l10n;
    final option = _option;
    final display = _display;

    final routeRetired = display != null && !_reusableRouteSupported;
    final unavailable = widget.unavailable != null || routeRetired;
    if ((_error != null && display == null) || unavailable) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: ReceiveCaption(
                text:
                    unavailable ? l10n.receiveCoinNetworkUnavailable : _error!,
              ),
            ),
            SizedBox(height: ReceiveGaps.block),
            // Back to the coin sheet, as the close X does.
            AppButton(
              text: l10n.back,
              variant: AppButtonVariant.secondary,
              compact: true,
              onPressed: _close,
            ),
          ],
        ),
      );
    }

    if (display == null) {
      // The finished page's own shape, with the code shimmering in the
      // plate and a line saying why. A spinner on an otherwise empty
      // page made the address arrive as a jump.
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ReceiveQrPlate(child: ReceiveQrShimmer()),
            SizedBox(height: ReceiveGaps.qrToCaption),
            ReceiveCaption(text: l10n.usdReceiveCreating),
          ],
        ),
      );
    }

    final payload = display.depositAddress;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReceiveQrPlate(child: buildQrCode(payload, context)),
          SizedBox(height: ReceiveGaps.qrToAddress),
          ReceiveAddressLine(
            address: payload,
            onCopy: () => _copy(payload),
          ),
          // Under the address, where the Bitcoin receive puts its own
          // caption: the network warning (only this coin, only this
          // network), then the minimum and, from the Bitcoin receive,
          // where it lands.
          SizedBox(height: 8.h),
          ReceiveCaption(
            key: const ValueKey('usd-receive-network-warning'),
            text: l10n.usdReceiveShareSubtitle(
                option.displaySymbol, option.chainDisplayName),
          ),
          ReceiveMinimumCaption(
            amount: _displayMinimum?.address == payload
                ? _displayMinimum!.minimum.usdText
                : null,
          ),
          // Opened from the Bitcoin receive: this address lands in the
          // Investments dollar balance, not in bitcoin. Said once.
          if (!_dollars) ...[
            SizedBox(height: 4.h),
            ReceiveCaption(
                key: const ValueKey('usd-receive-from-bitcoin-note'),
                text: l10n.moveDestDollarsSubtitle),
          ],
          SizedBox(height: ReceiveGaps.addressToActions),
          ReceiveActionPills(
            onShare: () => _share(payload),
          ),
          SizedBox(height: ReceiveGaps.block),
          // No Kute fee line: the fee is charged, never shown under a
          // receive address.
          UsdReviewPlate(children: [
            UsdReviewLine(
              label: l10n.network,
              value: option.chainDisplayName,
            ),
            UsdReviewLine(
              label: l10n.youSend,
              value: option.displaySymbol.toUpperCase(),
            ),
          ]),
          SizedBox(height: ReceiveGaps.block),
          ReceiveCaption(text: l10n.ledgerArrivesAfterNetwork),
          SizedBox(height: ReceiveGaps.tail),
        ],
      ),
    );
  }

  Future<void> _share(String payload) async {
    if (!_canExportAddress(payload)) return;
    TrackingService.track('usd_receive_address_shared',
        params: {'chain': _option.chain, 'address_kind': 'standing'});
    _flowStep('shared', {..._flowInputs(), 'method': 'share'});
    // iPad anchors the share popover to this rect; phones ignore it.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: payload,
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero,
    ));
  }

  void _copy(String payload) {
    if (!_canExportAddress(payload)) return;
    Clipboard.setData(ClipboardData(text: payload));
    HapticFeedback.lightImpact();
    TrackingService.track('usd_receive_address_copied',
        params: {'chain': _option.chain, 'address_kind': 'standing'});
    _flowStep('shared', {..._flowInputs(), 'method': 'copy'});
    showMessageSnackBar(
        context: context, message: context.l10n.copied, error: false);
  }

  bool _canExportAddress(String payload) =>
      mounted &&
      !_closing &&
      _spendingIsActive &&
      _reusableRouteSupported &&
      payload.isNotEmpty &&
      _display?.depositAddress == payload &&
      _display?.walletId == ref.read(settingsProvider).activeWalletId;

  bool get _reusableRouteSupported {
    final option = _option;
    final standing = _standing;
    if (standing != null) {
      final catalog = ref.read(orchestraSupportedRoutesProvider);
      // A reused address keeps the terms it was registered under, so a
      // newer policy revision does not retire it: Receive shows the same
      // address for a coin and network every time.
      return standing.enabled &&
          catalog.isFresh(DateTime.now()) &&
          catalog.supports(RouteKey(
              fromChain: option.chain,
              fromAsset: option.assetCode,
              toChain: 'spark',
              toAsset: kOrchestraUsdAssetCode));
    }
    return orchestraReceiveChainForDestination(option.assetCode, option.chain,
            destinationAsset: kOrchestraUsdAssetCode) !=
        null;
  }

  /// The standing instruction to `spark:USDB` for this coin (see
  /// [ReusableDepositAddressService]). Where the standing route cannot
  /// serve it, the sheet closes and the one-time flow takes over on the
  /// coin sheet when a one-time address can; otherwise the coin is
  /// unavailable. Never a legacy accumulation address.
  ///
  /// No exchange row is recorded here: the address has no order id at
  /// creation (Flashnet spawns an `ord_…` per inbound deposit), so a row
  /// written now would make background sync poll a nonexistent id. The
  /// poller discovers spawned orders and records them then.
  Future<void> _createReusableAddress(OrchestraReceiveOption option) async {
    final requestId = ++_requestId;
    final walletId = ref.read(settingsProvider).activeWalletId;
    bool current() =>
        mounted &&
        !_closing &&
        requestId == _requestId &&
        _spendingIsActive &&
        walletId == ref.read(settingsProvider).activeWalletId;
    if (_error != null) setState(() => _error = null);
    // The route's minimum is read beside the address, never before it.
    final route = RouteKey(
        fromChain: option.chain,
        fromAsset: option.assetCode,
        toChain: 'spark',
        toAsset: kOrchestraUsdAssetCode);
    final minimums = ref.read(receiveMinimumsProvider);
    final minimum = minimums.refresh(route);
    // Which model was being asked when a failure happened, for the event.
    DepositAddressModel? model;
    try {
      final wrapper = await ref.read(breezSDKProvider.future);
      if (!current()) return;
      final sdk = wrapper.instance;
      if (sdk == null) throw StateError('Wallet unavailable');
      bool sameSdk() =>
          identical(wrapper.instance, sdk) &&
          identical(ref.read(breezSDKProvider).asData?.value.instance, sdk);
      _sameSdk = sameSdk;
      // A quote's creation: a pull never retires the handle under it.
      final received = await runSparkQuote(() => sdk.receivePayment(
            request: const ReceivePaymentRequest(
              paymentMethod: ReceivePaymentMethod.sparkAddress(),
            ),
          ));
      if (!current() || !sameSdk()) return;
      final spark = received.paymentRequest;
      if (walletId == null) throw StateError('Wallet unavailable');
      // The route is asked of a live catalogue, fetched now when the one
      // on hand is older than a money decision allows: the screen only
      // nudges a refresh when it opens, and a coin tapped before that
      // landed used to fail with "Receive route unavailable" on the first
      // try and work on the second.
      final catalog = await ref
          .read(orchestraSupportedRoutesProvider.notifier)
          .refreshIfOlderThan(kMoneyCatalogMaxAge);
      if (!current() || !sameSdk()) return;
      if (!catalog.isFresh(DateTime.now()) || !catalog.supports(route)) {
        throw StateError('Receive route unavailable');
      }
      // Addresses already issued to this wallet, compared in memory only
      // so `receive_address_generated` can say whether this is a reuse.
      // The address itself never leaves the device.
      // Best effort: a failed read only costs the `reused` flag.
      final priorAddresses = <String?>{};
      try {
        for (final r in await StandingDepositStore.records(walletId)) {
          priorAddresses.add(r.addressFor(option.chain));
        }
      } catch (_) {}
      if (!current() || !sameSdk()) return;
      final resolved = await ReusableDepositAddressService.resolve(
          walletId: walletId,
          recipient: spark,
          destinationAsset: kOrchestraUsdAssetCode,
          sourceChain: option.chain,
          sourceAsset: option.assetCode,
          wanted: () => current() && sameSdk(),
          onAttempt: (m) => model = m);
      if (!current() || !sameSdk()) return;
      _standing = resolved.standing;
      // Opened from the Bitcoin receive: its deposits also show in the
      // Bitcoin Activity. Kept on the device only.
      if (!_dollars) {
        unawaited(BitcoinReceiveMarks.mark(
            walletId: walletId,
            label: resolved.standing?.label ?? resolved.id,
            sourceChain: option.chain,
            address: resolved.address));
      }
      final address = resolved.address;
      final kuteFeeBps = resolved.kuteFeeBps;
      final display = SwapOrder(
        activityDirection: 'receive',
        id: resolved.id,
        coinFrom: option.assetCode,
        networkFrom: option.chain,
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAddress: address,
        depositAmount: '0',
        withdrawalAmount: '0',
        status: 'wait',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: spark,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: walletId,
      );
      final addressEvent = <String, Object>{
        'asset': option.assetCode,
        'network': option.chain,
        'provider': 'orchestra',
        'reused': priorAddresses.contains(address),
        'destination': 'spark_usd',
        if (!_dollars) 'entry_source': kUsdReceiveFromBitcoinReceiveSource,
        'address_kind': 'standing',
        'model': resolved.model.name,
        if (kuteFeeBps != null) 'kute_fee_bps': kuteFeeBps,
      };
      _terminalTracked = false;
      final knownMinimum = minimums.cachedLive(route);
      setState(() {
        _setDisplay(display);
        _displayMinimum = knownMinimum == null
            ? null
            : (address: address, minimum: knownMinimum);
      });
      _flowStep('deposit_address_shown', _flowInputs());
      _startPolling(display);
      unawaited(_showMinimum(address, minimum, addressEvent));
    } catch (e) {
      if (!current()) return;
      // The standing route cannot serve this coin: the one-time flow takes
      // over when it can. Not a failure, so no failure event.
      final fallback = switch (e) {
        StandingUnavailableException(:final reason) => reason,
        CapabilityUnavailableException() =>
          StandingFallbackReason.standingPolicyOff,
        _ => null,
      };
      if (fallback != null) {
        final oneTime = oneTimeFallbackOption(
            ref.read(orchestraSupportedRoutesProvider), option,
            destinationAsset: widget.destinationAsset);
        if (oneTime != null) {
          _close((option: oneTime, reason: fallback));
          return;
        }
      }
      TrackingService.swapFailed(
          fromCoin: option.assetCode,
          toCoin: kOrchestraUsdAssetCode,
          provider: 'orchestra',
          reason: e.toString());
      TrackingService.track('receive_address_failed', params: {
        'asset': option.assetCode,
        'network': option.chain,
        'provider': 'orchestra',
        'destination': 'spark_usd',
        'address_kind': 'standing',
        if (!_dollars) 'entry_source': kUsdReceiveFromBitcoinReceiveSource,
        'error_category': TrackingService.errorCategory(e),
        if (model case final m?) 'model': m.name,
        if (fallback != null) 'fallback_reason': fallback.analytics,
      });
      if (_dollars) {
        TrackingService.moneyFlowError('usd_receive', e);
      } else {
        TrackingService.moneyFlowError('receive', e);
      }
      // Never change the destination balance when address creation fails.
      setState(() {
        _error = _errorCopy(e);
      });
      // The address the person picked a coin for could not be made.
      unawaited(moneyFailureFeedback());
    }
  }

  /// Puts the route's minimum under [address] once the read settles, and
  /// records the address with the minimum it showed. No
  /// `swap_initiated` here: showing (or re-showing) a reusable deposit
  /// address is not a swap, and counting it inflated the swap funnel.
  Future<void> _showMinimum(String address, Future<ReceiveMinimum> pending,
      Map<String, Object> addressEvent) async {
    final minimum = await pending;
    TrackingService.track('receive_address_generated',
        params: {...addressEvent, ...minimum.trackingParams});
    if (!mounted || _display?.depositAddress != address) return;
    setState(() => _displayMinimum = (address: address, minimum: minimum));
  }

  void _startPolling(SwapOrder display) {
    _poller.start(
      display,
      stillWanted: () =>
          mounted && _display?.depositAddress == display.depositAddress,
      onProgress: (exchange) {
        if (mounted) {
          setState(() => _setDisplay(exchange));
          _trackTerminal(exchange);
        }
      },
    );
  }

  /// The reason an address could not be shown, in the user's words. A
  /// guard refusal and a partner limit each carry their own copy, both
  /// written for people; anything else is a rail talking, so it goes
  /// through [railSafeErrorCopy] and only reaches the screen if it says
  /// nothing the person has never been shown. Otherwise the plain
  /// deposit-address failure stands in.
  String _errorCopy(Object error) {
    final l10n = context.l10n;
    if (error is WalletGuardException) return error.messageFor(l10n);
    // The rails refused this coin and network and no one-time address
    // serves it either: say so.
    if (error is ReceiveRouteUnavailableException) {
      return l10n.receiveCoinNetworkUnavailable;
    }
    return railSafeErrorCopy(context, error,
        fallback: l10n.receiveDepositAddressFailed);
  }
}
