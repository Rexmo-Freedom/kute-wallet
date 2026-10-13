import 'package:kute/services/orchestra/standing_deposit_store.dart';
// Reusable dollar receive addresses. Amount-bound deposits use the shared
// quoted receive screen, including source-chain refund validation.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MovePickerRow, MoveLockedSide, showDepositSheet;
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart'
    show AppButton, AppButtonVariant;
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
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
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

enum _Step { coin, address }

/// The Move sheet's `entry_source` when the "From your Bitcoin" row at the
/// top of this screen opens it.
const String kUsdReceiveBitcoinRowSource = 'usd_receive_bitcoin_row';

/// The coins the Investments receive opens on when it picks one itself,
/// in order, after the one last used: USDC on Solana, Base, Polygon.
const List<String> kUsdReceiveDefaultCoins = [
  'solana:USDC',
  'base:USDC',
  'polygon:USDC',
];

/// The `chain:asset` id the coin sheet selects by.
String usdReceiveCoinId(OrchestraReceiveOption o) =>
    '${o.chain}:${o.assetCode}';

/// The coin the Investments receive opens on when the dock's Receive opens
/// it ([UsdReceiveScreen.autoPickCoin]), from what the live catalog
/// offers ([offered], in the coin sheet's order) as a reusable address:
/// the one last used ([lastUsed], `chain:asset`), else the first of
/// [kUsdReceiveDefaultCoins] on offer, else the first offered coin. Null
/// when no reusable address is offered: the screen opens on its coin step.
/// [reason] is the analytics `preselect_reason`. Pure.
({OrchestraReceiveOption option, String reason})? usdReceivePreselect(
    Iterable<OrchestraReceiveOption> offered,
    {String? lastUsed}) {
  final reusable = offered.where((o) => o.reusableAddress).toList();
  if (reusable.isEmpty) return null;
  OrchestraReceiveOption? find(String id) {
    final want = id.toLowerCase();
    for (final o in reusable) {
      if (usdReceiveCoinId(o).toLowerCase() == want) return o;
    }
    return null;
  }

  final last = lastUsed == null ? null : find(lastUsed);
  if (last != null) return (option: last, reason: 'last_used');
  for (final id in kUsdReceiveDefaultCoins) {
    final o = find(id);
    if (o != null) return (option: o, reason: 'default');
  }
  return (option: reusable.first, reason: 'default');
}

/// The coin the Investments receive last showed an address for, as
/// `chain:asset` (never the address), in the box the app opens at boot.
/// Best effort both ways: a box that is not open reads as nothing.
abstract final class UsdReceiveLastCoin {
  static const String boxName = 'usd_receive_last_coin';
  static const String _key = 'last';

  /// Test seam: stands in for the box when set.
  @visibleForTesting
  static Map<String, String>? debugStore;

  static String? read() {
    final store = debugStore;
    if (store != null) return store[_key];
    try {
      if (!Hive.isBoxOpen(boxName)) return null;
      return Hive.box<String>(boxName).get(_key);
    } catch (_) {
      return null;
    }
  }

  static void write(String id) {
    final store = debugStore;
    if (store != null) {
      store[_key] = id;
      return;
    }
    try {
      if (!Hive.isBoxOpen(boxName)) return;
      unawaited(Hive.box<String>(boxName).put(_key, id).catchError((_) {}));
    } catch (_) {}
  }
}

/// Full-screen dollar receive.
///
/// [autoPickCoin] (the Investments dock's Receive) opens straight on the
/// address step with a coin already picked ([usdReceivePreselect]); the
/// coin step and its sheet still change it. Without it, or when nothing
/// can be picked, the screen opens on the coin step as it always did.
///
/// Both steps carry, at the top, the Move sheet's Bitcoin row as "From
/// your Bitcoin": it opens the Investments deposit (spending bitcoin into
/// Dollars), exactly what the dock's old Deposit opened.
class UsdReceiveScreen extends ConsumerStatefulWidget {
  const UsdReceiveScreen({super.key, this.autoPickCoin = false});

  final bool autoPickCoin;

  /// Test seam: what the "From your Bitcoin" row opens. Null opens the
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

  /// The Kute fee the shown address's own terms charge, keyed by that
  /// address so a later address never inherits it. Null bps shows no
  /// fee line.
  ({String address, int? bps})? _displayFee;

  String? _error;

  int _requestId = 0;
  bool Function()? _sameSdk;

  /// The dock's Receive is still picking its coin: the address step's
  /// loading shape is on screen until the live catalog says what to show.
  bool _autoPicking = false;

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
      props: {'source': 'usd'},
    );
    // The offering is live-catalogue only, so nudge it rather than
    // waiting for the 6 h cadence.
    final refreshed =
        ref.read(orchestraSupportedRoutesProvider.notifier).refresh();
    if (widget.autoPickCoin && _spendingIsActive) {
      _autoPicking = true;
      _step = _Step.address;
      unawaited(_autoPick(refreshed));
      return;
    }
    unawaited(refreshed);
    // The coin question opens as a sheet, the way it does on the
    // bitcoin screens, so the first tap of the flow lands on the grid
    // rather than on a page that then has to be tapped again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _step != _Step.coin || !_spendingIsActive) return;
      _openCoinPicker();
    });
  }

  /// The dock's Receive: pick the coin ([usdReceivePreselect]) from a
  /// live catalog, waiting for the refresh [initState] nudged when the
  /// one in hand is not fresh. Nothing to pick (or no live catalog) lands
  /// on the coin step with its sheet open, as the screen always opened.
  Future<void> _autoPick(Future<bool> refreshed) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !_autoPicking) return;
    if (!ref.read(orchestraSupportedRoutesProvider).isFresh(DateTime.now())) {
      try {
        await refreshed.timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (!mounted || !_autoPicking) return;
    }
    final catalog = ref.read(orchestraSupportedRoutesProvider);
    final pick = catalog.isFresh(DateTime.now()) && _spendingIsActive
        ? usdReceivePreselect(
            [
              for (final g in _coinGroups(watch: false))
                ...g.options.where((o) =>
                    orchestraReceiveChainForDestination(o.assetCode, o.chain,
                        destinationAsset: kOrchestraUsdAssetCode) !=
                    null),
            ],
            lastUsed: UsdReceiveLastCoin.read(),
          )
        : null;
    setState(() => _autoPicking = false);
    if (pick == null) {
      setState(() => _step = _Step.coin);
      if (_spendingIsActive) _openCoinPicker();
      return;
    }
    _pick(pick.option, preselectReason: pick.reason);
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

  /// "From your Bitcoin": the Investments deposit from the spending
  /// bitcoin, the Move sheet the dock's old Deposit opened.
  void _openFromBitcoin() {
    TrackingService.markEntrySource('move', kUsdReceiveBitcoinRowSource);
    final open = UsdReceiveScreen.debugDepositSheetOpener ?? showDepositSheet;
    unawaited(open(context, lockedSide: MoveLockedSide.depositToUsd));
  }

  Widget _bitcoinRow(BuildContext context) {
    final l10n = context.l10n;
    final balance = _spendingBitcoinUsd();
    return MovePickerRow(
      key: const ValueKey('usd-receive-from-bitcoin'),
      asset: 'lib/assets/bitcoin-icon.svg',
      title: l10n.usdReceiveFromYourBitcoin,
      subtitle: balance != null
          ? l10n.depositFromSpendingWalletWithBalance(balance)
          : l10n.depositFromSpendingWallet,
      horizontalPadding: 0,
      onTap: _openFromBitcoin,
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
    ref.listen(
        settingsProvider.select(
            (s) => (s.activeWalletId, pickSpendingWallet(s)?.id)), (old, next) {
      if (old == next) return;
      _clearWalletAddress();
    });
    ref.listen(breezSDKProvider, (old, next) {
      if (_sameSdk != null && !_sameSdk!()) _clearWalletAddress();
    });
    final c = context.colors;
    final l10n = context.l10n;
    final option = _option;
    return UsdFlowScaffold(
      title: l10n.usdReceiveTitle,
      totalSteps: 2,
      currentStep: _step == _Step.coin ? 0 : 1,
      completedSteps: _step == _Step.coin ? const {} : const {0},
      onBack: _onBack,
      resizeToAvoidBottomInset: false,
      child: !_spendingIsActive
          ? UsdFlowNote(lines: [l10n.receiveOtherCoinsSpendingOnly])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _bitcoinRow(context),
                Expanded(
                  child: switch (_step) {
                    _Step.coin => StepPageWrapper(
                        title: l10n.usdFlowStepCoin,
                        subtitle: l10n.usdReceivePickCoin,
                        colors: c,
                        child: _buildCoinStep(context),
                      ),
                    // Not `tight`: the bitcoin receive gives its share step
                    // the full heading, and a dollar receive that shrank its
                    // own was one of the things that made the two look
                    // unrelated.
                    _Step.address => StepPageWrapper(
                        title: l10n.usdReceiveShareStep,
                        subtitle: option == null ||
                                _display == null ||
                                !_reusableRouteSupported
                            ? ''
                            : l10n.usdReceiveShareSubtitle(
                                option.displaySymbol, option.chainDisplayName),
                        colors: c,
                        child: _buildAddressStep(context),
                      ),
                  },
                ),
              ],
            ),
    );
  }

  /// The coins that can be converted into this balance, folded one per
  /// coin. The same fold and the same marks the sheet shows, so the
  /// line on the step and the grid in the sheet can never disagree.
  List<CoinAssetGroup> _coinGroups({bool watch = true}) => receiveCoinGroups(
        watch
            ? ref.watch(orchestraSupportedRoutesProvider)
            : ref.read(orchestraSupportedRoutesProvider),
        context.l10n,
        destinationChain: kOrchestraUsdChain,
        destinationAsset: kOrchestraUsdAssetCode,
      );

  /// Step 1 — the coin, asked ASSET FIRST in the sheet every other
  /// money screen opens: a grid of coins, the network asked second and
  /// only for a coin that lives on more than one.
  Widget _buildCoinStep(BuildContext context) {
    final l10n = context.l10n;
    // Still fetching is not the same as nothing to offer. Until the
    // first load settles the step says so, and only after it does may
    // an empty offering be called unavailable.
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final groups = _coinGroups();
    if (groups.isEmpty) {
      return UsdFlowNote(lines: [
        loading
            ? l10n.usdReceiveRoutesUnavailable
            : l10n.usdReceiveCoinsUnavailable,
      ]);
    }
    return SingleChildScrollView(
      child: UsdFlowCoinPickerPanel(
        label: l10n.receiveAlsoAccepts,
        groups: groups,
        onTap: _openCoinPicker,
      ),
    );
  }

  /// The sheet itself. Every row it offers is served by one of the two
  /// deposit primitives, and a row bound to a single payment says so
  /// before the tap (see `coinNetworkRowNote`).
  void _openCoinPicker() {
    TrackingService.track('usd_receive_coin_picker_opened');
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
            otherLegAsset: kOrchestraUsdAssetCode,
            depositAddress: true,
            groups: receiveCoinGroups(
              catalog,
              ctx.l10n,
              destinationChain: kOrchestraUsdChain,
              destinationAsset: kOrchestraUsdAssetCode,
            ),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: ctx.l10n.usdReceivePickCoin,
            emptyLabel: loading
                ? ctx.l10n.usdReceiveRoutesUnavailable
                : ctx.l10n.usdReceiveCoinsUnavailable,
            flow: 'usd_receive',
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
    final option = _option;
    final display = _display;
    if (option == null) {
      // The dock's Receive picking its coin: the loading shape below.
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
          ReceiveKuteFeeCaption(
            bps: _displayFee?.address == payload ? _displayFee!.bps : null,
          ),
          SizedBox(height: ReceiveGaps.addressToActions),
          ReceiveActionPills(
            onShare: () => _share(payload),
            onCopy: () => _copy(payload),
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
    _autoPicking = false;
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

  /// [preselectReason] is set when the screen picked the coin itself
  /// (`last_used` or `default`, see [usdReceivePreselect]).
  void _pick(OrchestraReceiveOption option, {String? preselectReason}) {
    if (!_spendingIsActive) return;
    _requestId++;
    _poller.cancel();
    _autoPicking = false;
    if (!option.reusableAddress) {
      _openQuoted(option);
      return;
    }
    UsdReceiveLastCoin.write(usdReceiveCoinId(option));
    TrackingService.swapAssetSelected(
        flow: 'receive_dollars', asset: option.assetCode);
    TrackingService.track('usd_receive_coin_selected', params: {
      'asset': option.assetCode,
      'chain': option.chain,
      'address_kind': 'reusable',
      'preselected': preselectReason != null,
      'preselect_reason': preselectReason ?? 'none',
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
    _autoPicking = false;
    setState(() {
      _option = null;
      _display = null;
      _standing = null;
      _error = null;
      _step = _Step.coin;
    });
  }

  /// Prefer an immutable standing instruction for supported destinations;
  /// retain the legacy rail where the provider does not offer standing funding.
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
      final catalog = ref.read(orchestraSupportedRoutesProvider);
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
        for (final a in AccumulationAddressCache.getAll()) {
          priorAddresses.add(a.depositAddress);
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
      // No `swap_initiated` here: showing (or re-showing) a reusable
      // deposit address is not a swap, and counting it inflated the
      // swap funnel.
      TrackingService.track('receive_address_generated', params: {
        'asset': option.assetCode,
        'network': option.chain,
        'provider': 'orchestra',
        'reused': priorAddresses.contains(address),
        'destination': 'spark_usd',
        'address_kind': 'reusable_deposit',
        'model': resolved.model.name,
        if (kuteFeeBps != null) 'kute_fee_bps': kuteFeeBps,
      });
      TrackingService.moneyFlowStep('usd_receive', 'deposit_address_shown',
          props: _flowInputs());
      setState(() {
        _display = display;
        _displayFee = (address: address, bps: kuteFeeBps);
      });
      _startPolling(display);
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
        'error_category': TrackingService.errorCategory(e),
        if (model case final m?) 'model': m.name,
      });
      TrackingService.moneyFlowError('usd_receive', e);
      // Never change the destination balance when address creation fails.
      setState(() {
        _error = _errorCopy(e);
      });
    }
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
