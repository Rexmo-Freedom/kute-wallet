import 'package:kute/services/orchestra/standing_deposit_store.dart';
// Reusable dollar receive addresses. Amount-bound deposits use the shared
// quoted receive screen, including source-chain refund validation.

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
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide, showDepositSheet;
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart'
    show AppButton, AppButtonVariant;
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCircleBackButton, KuteCloseButton;
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard, SendToListRow, SendToSectionHeader;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart';
import 'package:kute/services/orchestra_routes.dart'
    show
        orchestraExchangeStatusIsTerminal,
        kOrchestraUsdAssetCode,
        kOrchestraUsdChain,
        orchestraCanQuoteReceiveOn,
        orchestraReceiveChainForDestination;
import 'package:kute/services/security/wallet_guard_exception.dart'
    show WalletGuardException;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/success_feedback.dart' show moneyFailureFeedback;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/services/orchestra/bitcoin_receive_marks.dart'
    show BitcoinReceiveMarks;

enum _Step { coin, address }

/// The Move sheet's `entry_source` when the Bitcoin card ("From your
/// wallet") at the top of this screen opens it.
const String kUsdReceiveBitcoinRowSource = 'usd_receive_bitcoin_row';

/// The `entry_source` of the Dollars receive (and the `entry` on its
/// events) when the Bitcoin receive's "other coins" line opens it.
const String kUsdReceiveFromBitcoinReceiveSource = 'bitcoin_receive';

/// The `chain:asset` id the coin sheet selects by.
String usdReceiveCoinId(OrchestraReceiveOption o) =>
    '${o.chain}:${o.assetCode}';

/// The dollar receive, a sheet over the current screen
/// (`showUsdReceiveSheet`, or the `receiveDollars` route's sheet page).
///
/// Every way in (the Investments dock's Receive included) opens on the
/// coin step, two labelled choices: "From your wallet" over the Bitcoin
/// card (the Move sheet's way in from the spending bitcoin), then "From
/// another wallet or exchange" over the coin grid. Picking a coin shows
/// its address; nothing is ever picked for the person.
class UsdReceiveScreen extends ConsumerStatefulWidget {
  const UsdReceiveScreen({super.key, this.fromBitcoinReceive = false});

  /// Opened from the Bitcoin receive's "other coins" line: the same sheet,
  /// with a note that the money lands in the Investments dollar balance,
  /// its events tagged `entry: bitcoin_receive`, and every address it shows
  /// remembered so its deposits also show in the Bitcoin Activity
  /// ([BitcoinReceiveMarks]).
  final bool fromBitcoinReceive;

  /// Test seam: what the Bitcoin card opens. Null opens the
  /// real Move sheet ([showDepositSheet]).
  @visibleForTesting
  static Future<void> Function(BuildContext context,
      {required MoveLockedSide lockedSide})? debugDepositSheetOpener;

  @override
  ConsumerState<UsdReceiveScreen> createState() => _UsdReceiveScreenState();
}

class _UsdReceiveScreenState extends ConsumerState<UsdReceiveScreen> {
  _Step _step = _Step.coin;

  /// The picked coin, as the live catalogue spells it.
  OrchestraReceiveOption? _option;

  /// The address on screen, as a local display row. Deliberately never
  /// written to `swapOrdersProvider` at creation: an Orchestra deposit
  /// address has no order id until a deposit lands, so a row written
  /// now would make background sync poll an id that never resolves. The
  /// poller records the real `ord_…` when it appears.
  SwapOrder? _display;
  StandingDepositRecord? _standing;

  /// The smallest deposit the shown address takes, keyed by that address
  /// so a later address never inherits it. Null until known: the address
  /// never waits for it.
  ({String address, ReceiveMinimum minimum})? _displayMinimum;

  String? _error;

  int _requestId = 0;
  bool Function()? _sameSdk;

  bool get _spendingIsActive {
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    return spending != null && spending.id == settings.activeWalletId;
  }

  late final OrchestraDepositPoller _poller = OrchestraDepositPoller(ref);

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('usd_receive');
    TrackingService.moneyFlowStarted(
      'usd_receive',
      event: 'usd_receive_opened',
      entrySource:
          TrackingService.takeEntrySource('usd_receive', fallback: 'usd'),
      props: {'source': 'usd', 'presentation': 'sheet'},
    );
    // The offering is live-catalogue only, so nudge it rather than
    // waiting for the 6 h cadence. The coin step holds the grid itself,
    // under the Bitcoin card, so no sheet opens over it.
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
    TrackingService.moneyFlowAbandoned('usd_receive', props: _flowInputs());
    _poller.cancel();
    super.dispose();
  }

  bool _terminalTracked = false;

  Map<String, Object> _flowInputs() {
    final o = _option;
    return {
      if (widget.fromBitcoinReceive)
        'entry_source': kUsdReceiveFromBitcoinReceiveSource,
      'address_shown': _display != null,
      if (o != null)
        ...TrackingService.routeParams(
          fromAsset: o.assetCode,
          fromNetwork: o.chain,
          toAsset: 'usd',
          toNetwork: 'spark',
          provider: 'orchestra',
        ),
    };
  }

  void _trackTerminal(SwapOrder order) {
    if (_terminalTracked || !orchestraExchangeStatusIsTerminal(order.status)) {
      return;
    }
    _terminalTracked = true;
    final ok = order.status == 'success';
    TrackingService.track(ok ? 'usd_receive_completed' : 'usd_receive_failed',
        params: {
          ..._flowInputs(),
          'status': order.status,
          if (!ok) 'error_category': 'settlement',
          if (!ok) 'stage': 'settle',
        });
    TrackingService.moneyFlowFinished('usd_receive');
  }

  @override
  Widget build(BuildContext context) {
    // Retire an already displayed route as soon as catalog support changes.
    ref.watch(orchestraSupportedRoutesProvider);
    // Kept alive across both steps, so coming back to the coin step never
    // flashes an empty offering while the destinations are read again.
    ref.watch(standingDestinationsProvider);
    ref.listen(
        settingsProvider.select(
            (s) => (s.activeWalletId, pickSpendingWallet(s)?.id)), (old, next) {
      if (old == next) return;
      _clearWalletAddress();
    });
    ref.listen(breezSDKProvider, (old, next) {
      if (_sameSdk != null && !_sameSdk!()) _clearWalletAddress();
    });
    final l10n = context.l10n;
    // Opens as a sheet over the current screen (receive_sheet.dart), and
    // both steps happen inside it: the header's close becomes a back
    // once a coin is picked, and back returns to the coin step.
    return ReceiveSheetFrame(
      leading: _step == _Step.coin
          ? KuteCloseButton(onPressed: _onBack)
          : KuteCircleBackButton(onPressed: _onBack),
      // The balance the money lands in, read-only, where the bitcoin
      // receive names its wallet: "Investments" (founder decision). No
      // step bar; the close/back in the header says where you are.
      title: AccountSwitcherPill(
        pickerTitle: l10n.receiveInto,
        readOnly: true,
        label: l10n.assetDollars,
      ),
      semanticTitle: l10n.usdReceiveTitle,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
        child: !_spendingIsActive
            ? UsdFlowNote(lines: [l10n.receiveOtherCoinsSpendingOnly])
            : switch (_step) {
                _Step.coin => _buildCoinStep(context),
                // The address step opens on the code, as the bitcoin
                // receive does: the coin and network it takes are in the
                // plate under the actions.
                _Step.address => Padding(
                    padding: EdgeInsets.only(top: 6.h),
                    child: _buildAddressStep(context),
                  ),
              },
      ),
    );
  }

  /// The coins that can be converted into this balance, folded one per
  /// coin, minus what the runtime policy withdraws: the same set the
  /// sheet offers, so the grid on the step and the grid in the sheet can
  /// never disagree.
  List<CoinAssetGroup> _coinGroups() => coinGroupsOfferedUnderPolicy(
        receiveCoinGroups(
          ref.watch(orchestraSupportedRoutesProvider),
          context.l10n,
          standingDestinations:
              ref.watch(standingDestinationsProvider).valueOrNull ?? const {},
          destinationChain: kOrchestraUsdChain,
          destinationAsset: kOrchestraUsdAssetCode,
        ),
        otherLegAsset: kOrchestraUsdAssetCode,
        depositAddress: true,
      ).groups;

  /// Step 1, top to bottom: "From your wallet" over the Bitcoin card (the
  /// Move sheet from the spending bitcoin), then "From another wallet or
  /// exchange" over the coin grid, asked
  /// ASSET FIRST as every money screen asks it: a coin on one network
  /// goes straight to its address, a coin on several opens the sheet on
  /// its networks.
  Widget _buildCoinStep(BuildContext context) {
    final l10n = context.l10n;
    // Still fetching is not the same as nothing to offer. Until the
    // first load settles the step says so, and only after it does may
    // an empty offering be called unavailable.
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final groups = _coinGroups();
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Opened from the Bitcoin receive: say once where the money
          // lands, in the caption style, before the choices.
          if (widget.fromBitcoinReceive) ...[
            ReceiveCaption(
                key: const ValueKey('usd-receive-from-bitcoin-note'),
                text: l10n.moveDestDollarsSubtitle),
            SizedBox(height: 16.h),
          ],
          SendToSectionHeader(title: l10n.usdReceiveFromYourWallet),
          _bitcoinRow(context),
          SizedBox(height: 24.h),
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
  /// address; several open the sheet on that coin's networks.
  void _pickGroup(CoinAssetGroup group) {
    TrackingService.track('coin_picker_coin_picked', params: {
      'flow': 'usd_receive',
      'asset': group.assetCode,
      'networks': group.options.length,
    });
    if (group.isSingleNetwork) {
      _pick(group.options.first);
      return;
    }
    _openCoinPicker(initialGroupKey: group.key);
  }

  /// The sheet itself, open on [initialGroupKey]'s networks. Every row
  /// it offers is served by one of the two deposit primitives, and a row
  /// bound to a single payment says so before the tap (see
  /// `coinNetworkRowNote`).
  void _openCoinPicker({String? initialGroupKey}) {
    TrackingService.track('usd_receive_coin_picker_opened');
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          // Watch so the offering re-folds the moment the live
          // catalogue lands.
          final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
          final destinations = sheetRef.watch(standingDestinationsProvider);
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading ||
                  destinations.isLoading;
          return CoinAssetPickerSheet(
            otherLegAsset: kOrchestraUsdAssetCode,
            depositAddress: true,
            groups: receiveCoinGroups(
              catalog,
              ctx.l10n,
              standingDestinations: destinations.valueOrNull ?? const {},
              destinationChain: kOrchestraUsdChain,
              destinationAsset: kOrchestraUsdAssetCode,
            ),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: ctx.l10n.usdReceivePickCoin,
            emptyLabel: loading
                ? ctx.l10n.usdReceiveRoutesUnavailable
                : ctx.l10n.usdReceiveCoinsUnavailable,
            flow: 'usd_receive',
            initialAssetCode: initialGroupKey,
            selectedOptionId:
                _option == null ? null : usdReceiveCoinId(_option!),
            onPicked: (option) {
              Navigator.of(sheetCtx).pop();
              _pick(option);
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// Uses the same QR, address and action sizing as Bitcoin receive.
  Widget _buildAddressStep(BuildContext context) {
    final l10n = context.l10n;
    final option = _option!;
    final display = _display;

    final routeRetired = display != null && !_reusableRouteSupported;
    if ((_error != null && display == null) || routeRetired) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UsdFlowNote(lines: [
              routeRetired ? l10n.receiveCoinNetworkUnavailable : _error!,
            ]),
            SizedBox(height: ReceiveGaps.block),
            if (!routeRetired &&
                orchestraCanQuoteReceiveOn(option.chain) &&
                oneTimeReceiveAllowed(RuntimeCapabilitiesService.instance)) ...[
              AppButton(
                text: l10n.receiveOneOffUseAddress,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => _openQuoted(option),
              ),
              SizedBox(height: ReceiveGaps.block),
            ],
            AppButton(
              text: l10n.back,
              variant: AppButtonVariant.secondary,
              compact: true,
              onPressed: () => setState(() {
                _error = null;
                _requestId++;
                _step = _Step.coin;
              }),
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
          // Which coin on which network, said once under the address it
          // belongs to (it was the step's subtitle before the sheet lost
          // its titles).
          SizedBox(height: 8.h),
          ReceiveCaption(
            text: l10n.usdReceiveShareSubtitle(
                option.displaySymbol, option.chainDisplayName),
          ),
          ReceiveMinimumCaption(
            amount: _displayMinimum?.address == payload
                ? _displayMinimum!.minimum.usdText
                : null,
          ),
          if (widget.fromBitcoinReceive) ...[
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
          UsdFlowNote(lines: [l10n.usdReceiveArriving]),
          SizedBox(height: ReceiveGaps.tail),
        ],
      ),
    );
  }

  void _onBack() {
    _requestId++;
    _poller.cancel();
    if (_step == _Step.coin) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _error = null;
      _display = null;
      _standing = null;
      _step = _Step.coin;
    });
  }

  /// The person picked [option]; the screen never picks one itself, so
  /// `preselected` is always false (the property is kept for history).
  void _pick(OrchestraReceiveOption option) {
    if (!_spendingIsActive) return;
    _requestId++;
    _poller.cancel();
    if (!option.reusableAddress) {
      _openQuoted(option);
      return;
    }
    TrackingService.swapAssetSelected(
        flow: 'receive_dollars', asset: option.assetCode);
    TrackingService.track('usd_receive_coin_selected', params: {
      'asset': option.assetCode,
      'chain': option.chain,
      'address_kind': 'reusable',
      'preselected': false,
      'preselect_reason': 'none',
    });
    TrackingService.moneyFlowStep('usd_receive', 'coin_selected', props: {
      'asset': option.assetCode,
      'chain': option.chain,
      'address_kind': 'reusable',
    });
    setState(() {
      _option = option;
      _error = null;
      _display = null;
      _standing = null;
      _step = _Step.address;
    });
    unawaited(_createReusableAddress(option));
  }

  void _openQuoted(OrchestraReceiveOption option) {
    // One-time addresses are an operator switch (fails closed).
    if (!oneTimeReceiveAllowed(RuntimeCapabilitiesService.instance)) return;
    TrackingService.track('usd_receive_coin_selected', params: {
      'asset': option.assetCode,
      'chain': option.chain,
      'address_kind': 'one_time',
      'preselected': false,
      'preselect_reason': 'none',
    });
    TrackingService.markEntrySource('quoted_receive', 'usd_receive');
    _requestId++;
    _poller.cancel();
    unawaited(Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => QuotedReceiveScreen(
        option: option,
        destinationAsset: kOrchestraUsdAssetCode,
      ),
    )));
  }

  Future<void> _share(String payload) async {
    if (!_canExportAddress(payload)) return;
    TrackingService.track('usd_receive_address_shared',
        params: {'chain': _option?.chain ?? ''});
    TrackingService.moneyFlowStep('usd_receive', 'shared',
        props: {..._flowInputs(), 'method': 'share'});
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
        params: {'chain': _option?.chain ?? ''});
    TrackingService.moneyFlowStep('usd_receive', 'shared',
        props: {..._flowInputs(), 'method': 'copy'});
    showMessageSnackBar(
        context: context, message: context.l10n.copied, error: false);
  }

  bool _canExportAddress(String payload) =>
      mounted &&
      _spendingIsActive &&
      _reusableRouteSupported &&
      (_sameSdk?.call() ?? false) &&
      _step == _Step.address &&
      payload.isNotEmpty &&
      _display?.depositAddress == payload;

  bool get _reusableRouteSupported {
    final option = _option;
    final standing = _standing;
    if (standing != null && option != null) {
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
    return option != null &&
        orchestraReceiveChainForDestination(option.assetCode, option.chain,
                destinationAsset: kOrchestraUsdAssetCode) !=
            null;
  }

  void _clearWalletAddress() {
    _requestId++;
    _poller.cancel();
    _sameSdk = null;
    setState(() {
      _option = null;
      _display = null;
      _standing = null;
      _error = null;
      _step = _Step.coin;
    });
  }

  /// The immutable standing instruction to `spark:USDB` for this coin
  /// (see [ReusableDepositAddressService]). There is no legacy rail: a
  /// coin the standing rail cannot serve is refused and leaves the list.
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
        requestId == _requestId &&
        _spendingIsActive &&
        walletId == ref.read(settingsProvider).activeWalletId;
    setState(() {
      _error = null;
    });
    TrackingService.receiveSourceSelected(
        asset: option.assetCode, network: option.chain, provider: 'orchestra');
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
      final received = await sdk.receivePayment(
        request: const ReceivePaymentRequest(
          paymentMethod: ReceivePaymentMethod.sparkAddress(),
        ),
      );
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
      if (!catalog.isFresh(DateTime.now()) ||
          !catalog.supports(RouteKey(
              fromChain: option.chain,
              fromAsset: option.assetCode,
              toChain: 'spark',
              toAsset: kOrchestraUsdAssetCode))) {
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
      if (widget.fromBitcoinReceive) {
        unawaited(BitcoinReceiveMarks.mark(
            walletId: walletId,
            label: resolved.standing?.label ?? resolved.id,
            sourceChain: option.chain,
            address: resolved.address));
      }
      final address = resolved.address;
      final addressId = resolved.id;
      final kuteFeeBps = resolved.kuteFeeBps;
      final display = SwapOrder(
        activityDirection: 'receive',
        id: addressId,
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
        if (widget.fromBitcoinReceive)
          'entry_source': kUsdReceiveFromBitcoinReceiveSource,
        'address_kind': 'reusable_deposit',
        'model': resolved.model.name,
        if (kuteFeeBps != null) 'kute_fee_bps': kuteFeeBps,
      };
      TrackingService.moneyFlowStep('usd_receive', 'deposit_address_shown',
          props: _flowInputs());
      final knownMinimum = minimums.cachedLive(route);
      setState(() {
        _display = display;
        _displayMinimum = knownMinimum == null
            ? null
            : (address: address, minimum: knownMinimum);
      });
      _startPolling(display);
      unawaited(_showMinimum(address, minimum, addressEvent));
    } catch (e) {
      TrackingService.swapFailed(
          fromCoin: option.assetCode,
          toCoin: kOrchestraUsdAssetCode,
          provider: 'orchestra',
          reason: e.toString());
      if (!current()) return;
      TrackingService.track('receive_address_failed', params: {
        'asset': option.assetCode,
        'network': option.chain,
        'provider': 'orchestra',
        if (widget.fromBitcoinReceive)
          'entry_source': kUsdReceiveFromBitcoinReceiveSource,
        'error_category': TrackingService.errorCategory(e),
        if (model case final m?) 'model': m.name,
      });
      TrackingService.moneyFlowError('usd_receive', e);
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
          setState(() => _display = exchange);
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
    // The rails refused this coin and network, not this attempt: say so,
    // and the coin step no longer offers it (ReceiveRouteAvailability).
    if (error is ReceiveRouteUnavailableException) {
      return l10n.receiveCoinNetworkUnavailable;
    }
    return railSafeErrorCopy(context, error,
        fallback: l10n.receiveDepositAddressFailed);
  }
}
