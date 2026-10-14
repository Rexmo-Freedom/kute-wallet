// lib/screens/usd/usd_send_screen.dart
//
// SENDING THE DOLLAR BALANCE. The same three screens as the bitcoin send
// (`confirm_send.dart`) — Amount, Send to, Review — built from the same
// pieces (`shared/send/send_flow_widgets.dart`), with its own money path.
//
// WHY ITS OWN MONEY PATH. The bitcoin stepper carries one amount for the
// whole flow — `SendTx.amount`, a single `int` of SATOSHIS that the PSBT
// builder and every fee provider read — and roughly sixty of its
// branches answer "which pool is this" with a two-way test. Threading a
// six-decimal token through that would mean either storing a
// satoshi-equivalent converted at the bitcoin price (dollars → sats →
// dollars, on a money path, when the SDK needs the exact base units the
// user typed) or auditing all sixty branches. And its cross-asset path
// spends bitcoin by design — for a dollar send, the single outcome that
// must never happen. So the screens are shared and the dispatch is not.
//
// THE RULE THIS FILE KEEPS: A FAILED DOLLARS SEND MUST NEVER SPEND
// BITCOIN. Four things enforce it, and none of them is a comment:
//
//   1. This file imports no bitcoin dispatcher and no `SendTx`. There is
//      nothing here to fall back TO. Every failure path below ends in
//      `setState(_error = …)` and a screen the user can leave.
//   2. The only money call is `HotSettlement.prepareSpark`, which picks
//      the paying balance from the VERIFIED quote's own source asset —
//      `spark:USDB` here, always — and holds the SDK's reply to an
//      EQUALITY echo on the token identifier. A reply that echoed no
//      token, or another one, throws before anything moves.
//   3. The amount never becomes a satoshi count. It is parsed straight
//      from the typed string into six-decimal base units
//      ([usdBaseUnitsFromTyped]), or read from the SDK's own dollar
//      balance for 100% ([usdDrainBaseUnits]), and stays a `BigInt`
//      through the quote, the echo check and the SDK call.
//   4. The destinations are the dollar row's own outbound routes
//      ([usdSendDestinations]), live-catalog only and filtered by the
//      runtime policy exactly as the coin sheet filters them. The
//      recipient picks among those; nothing it pastes can open another
//      route. Spark recipients are not offered for now.
//
// THE COIN COMES FIRST (founder decision, 14 October 2026). Send to opens
// on the coin grid — what the recipient gets, asset first and network
// second, the same set the coin sheet offers — and nothing else is there
// until one is picked: no address field, no Paste, no Scan, no recents.
// The pick then stays on every step as one chip (coin · network) that
// reopens the picker. The address is checked against THAT network only:
// a pasted or scanned address for another one is refused with the
// existing invalid-address words, never used to move the destination.
// Changing the coin keeps an address the new network still accepts and
// clears one it does not. A payment request handed over on open
// ([UsdSendScreen.initialRecipient]) that names its own network
// (`ethereum:…@chainId`, `tron:…`, `solana:…`) preselects that coin and
// fills the field; one that names none waits for the pick.
//
// The user never sees the token's internal spelling: every label here
// says Dollars, USD or $.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:kute/helpers/venue_intents.dart' show OrchestraGrants;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart'
    show OrchestraReceiveOption, OrchestraRoutesCatalog, RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show AssetIcon, kInvestmentsIcon, kUsdMarkAsset;
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdDrainBaseUnits;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, AmountPercentChips;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/asset_network_picker.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingProof, SettlementStopReason, SettlementStopped;
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraOptionsOfferedUnderPolicy;
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show OrchestraQuoteRequest, RecipientKind;
import 'package:kute/services/orchestra_routes.dart'
    show
        kOrchestraUsdAssetCode,
        kOrchestraUsdChain,
        orchestraAssetCodeFor,
        orchestraChainDisplayName;
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore, trackMultiSourceMoveRetry;
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show investmentsSpendableProvider, venueCashRefreshProvider;
import 'package:kute/screens/shared/venue_cash_pull_copy.dart';
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Smallest dollar send, in dollars.
const double _kMinUsd = 1.0;

/// The dollar token's decimals. Pinned, not read from the catalog: this
/// is the unit the SDK is handed, and a catalog that disagreed with the
/// pin makes the route unavailable in the quote gate long before here.
const int _kUsdDecimals = 6;

/// Page indices of the stepper, in the bitcoin send's order: the
/// recipient first (the send sheet's medium-height step), then the
/// amount on the keypad, then Review.
const int _kSendToStep = 0;
const int _kAmountStep = 1;
const int _kReviewStep = 2;

/// The dollar send. Open it with `showSendSheet` (send_sheet.dart): it
/// reports to the sheet what height it needs and when it may close.
///
/// Typed over what can be sent, the amount step says "more than
/// available" and Continue stays dead; nothing is offered to top it up.
class UsdSendScreen extends ConsumerStatefulWidget {
  const UsdSendScreen({super.key, this.initialRecipient});

  /// A recipient handed over on open (a deep link or a scanner
  /// hand-off), raw. A payment request that names its own network
  /// preselects that coin and fills the field; anything else waits for
  /// the coin to be picked and fills the field only if that coin's
  /// network accepts it.
  final String? initialRecipient;

  @override
  ConsumerState<UsdSendScreen> createState() => _UsdSendScreenState();
}

class _UsdSendScreenState extends ConsumerState<UsdSendScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  final TextEditingController _address = TextEditingController();

  /// The "digit lands" bounce on each keystroke, as on the bitcoin send.
  late final AnimationController _amountPulse;

  int _step = _kSendToStep;
  final Set<int> _completedSteps = <int>{};

  /// The typed amount, in dollars, exactly as the keypad produced it.
  /// Base units are derived from THIS STRING, never from a double.
  String _typed = '';

  /// 100% is armed: the figure on screen is the balance to the cent, and
  /// the exact amount is read from the SDK on Review ([_drainUnits]).
  bool _drain = false;
  BigInt? _drainUnits;
  bool _resolvingDrain = false;
  String? _drainError;

  /// The picked coin and network. Null until the person picks one (or a
  /// payment request handed over on open names it); until then Send to
  /// shows only the coin grid, and the send cannot dispatch without it.
  UsdSendDestination? _destination;

  /// [UsdSendScreen.initialRecipient] while it still waits for a coin.
  String? _pendingRecipient;

  /// The EIP-155 chain id the committed payment request named, if any.
  int? _chainId;

  String? _clipboardCandidate;
  String? _clipboardDismissed;

  /// How the recipient got into the field (analytics; never the
  /// address).
  String? _addressMethod;
  String? _amountMethod;

  /// The live estimate Review shows as "You receive".
  double? _estimateOut;
  bool _estimateLoading = false;
  String? _estimateError;
  int _estimateSeq = 0;

  bool _reviewToExpanded = false;
  bool _processing = false;
  String? _error;

  /// While venue cash is coming home for this send: one line per leg,
  /// shown where Review's footnote is.
  String? _pullProgress;

  /// The multi-source move this send's venue cash went under, and the
  /// amount it was for: a Retry of the same amount continues it (the money
  /// already on its way is reused, never pulled twice) and the send joins
  /// its one Activity row.
  String? _moveId;
  double? _moveUsd;

  /// The last pull stopped with a leg that did not go: the button is
  /// Retry for the remainder until the slip changes.
  bool _retryPull = false;

  @override
  void initState() {
    super.initState();
    _amountPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    TrackingService.screenView('usd_send');
    TrackingService.moneyFlowStarted(
      'usd_send',
      event: 'usd_send_opened',
      entrySource: TrackingService.takeEntrySource('usd_send', fallback: 'usd'),
      walletKind: _walletKind(),
      network: 'spark',
      props: {
        'source': 'usd',
        'source_asset': 'usd',
        'presentation': SendSheetScope.presented(context) ? 'sheet' : 'screen',
      },
    );
    // Send to opens on the coin grid with nothing picked. A recipient
    // handed over on open may pick it, once the catalog can say which.
    final initial = widget.initialRecipient?.trim() ?? '';
    if (initial.isNotEmpty) _pendingRecipient = initial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _step != _kSendToStep) return;
      _applyInitialRecipient();
    });
    // A dollar send is a money decision on a live route, so nudge the
    // catalog rather than waiting for its 6 h cadence. Fire and forget:
    // the screen renders the current table meanwhile.
    // ignore: discarded_futures
    ref.read(orchestraSupportedRoutesProvider.notifier).refresh();
  }

  @override
  void dispose() {
    TrackingService.moneyFlowAbandoned('usd_send', props: _flowInputs());
    _pageCtrl.dispose();
    _address.dispose();
    _amountPulse.dispose();
    super.dispose();
  }

  String? _walletKind() {
    try {
      final w = ref.read(settingsProvider).activeWallet;
      if (w == null) return null;
      return TrackingService.walletKind(
        isLedger: w.isLedger,
        isHardware: w.isHardware,
        isWatchOnly: w.isWatchOnly,
        isSigner: w.isSigner,
        isExternalAddress: w.isExternalAddress,
      );
    } catch (_) {
      return null;
    }
  }

  /// What has been entered so far (funnel props); never the address.
  Map<String, Object> _flowInputs() {
    final d = _destination;
    final usd = _amountUsd;
    return {
      'source_asset': 'usd',
      if (d != null)
        ...TrackingService.routeParams(
          fromAsset: 'usd',
          fromNetwork: 'spark',
          toAsset: d.assetCode,
          toNetwork: d.chain,
          provider: 'orchestra',
        ),
      'address_entered': _address.text.trim().isNotEmpty,
      if (_addressMethod != null) 'address_method': _addressMethod!,
      if (_amountMethod != null) 'amount_method': _amountMethod!,
      ...TrackingService.moneyParams(
        amountUsd: usd > 0 ? usd : null,
        amount: usd > 0 ? usd : null,
        asset: 'usd',
        currency: 'USD',
      ),
    };
  }

  // ─── Balance and amount ───────────────────────────────────────────

  double get _availableUsd => ref.read(usdBalanceProvider);

  /// The balance as base units, rounded DOWN. Rounding up would let 100%
  /// ask for a unit the wallet does not hold.
  BigInt get _availableBaseUnits =>
      BigInt.from((_availableUsd * 1000000).floor());

  /// How far the send reaches: Dollars plus the venue cash that can come
  /// home for it, net of the planned move costs (the Max, a figure the
  /// engine's plan covers), never less than Dollars. From the last known
  /// values ([investmentsSpendableProvider]): never loading.
  ///
  /// It is also the figure the available line and the Review From row
  /// show (founder decision 13 October 2026): what can actually be sent,
  /// so any amount up to it goes through and "more than available" starts
  /// a cent above it.
  double get _reachUsd {
    final dollars = _availableUsd;
    final max = ref.read(investmentsSpendableProvider).maxUsd;
    return max > dollars ? max : dollars;
  }

  BigInt get _reachBaseUnits => BigInt.from((_reachUsd * 1000000).floor());

  /// The typed amount as base units, or null when the string is not a
  /// plain decimal the token can express.
  BigInt? get _typedBaseUnits =>
      usdBaseUnitsFromTyped(_typed, decimals: _kUsdDecimals);

  BigInt get _minBaseUnits => BigInt.from((_kMinUsd * 1000000).round());

  /// The amount this send moves: the exact balance once 100% has been
  /// resolved on Review, else the typed figure.
  BigInt? get _amountBaseUnits =>
      _drain && _drainUnits != null ? _drainUnits : _typedBaseUnits;

  double get _amountUsd {
    final units = _amountBaseUnits;
    return units == null ? 0 : units.toDouble() / 1e6;
  }

  bool get _amountExceedsBalance {
    final units = _typedBaseUnits;
    return !_drain && units != null && units > _reachBaseUnits;
  }

  bool get _amountBelowMinimum {
    final units = _typedBaseUnits;
    return units != null && units > BigInt.zero && units < _minBaseUnits;
  }

  /// The amount step's gate.
  bool get _amountStepValid {
    final units = _typedBaseUnits;
    if (units == null) return false;
    return units >= _minBaseUnits && units <= _reachBaseUnits;
  }

  /// The gate the dispatch re-checks.
  bool get _amountValid {
    final units = _amountBaseUnits;
    if (units == null) return false;
    if (_drain) {
      return _drainUnits != null &&
          units >= _minBaseUnits &&
          _drainError == null;
    }
    return units >= _minBaseUnits && units <= _reachBaseUnits;
  }

  /// A dollar figure as the hero shows it: cents always, and every
  /// further digit the exact amount carries.
  static String _formatUsdUnits(BigInt units) {
    final whole = units ~/ BigInt.from(1000000);
    var frac = (units % BigInt.from(1000000)).toString().padLeft(6, '0');
    while (frac.length > 2 && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    final grouped = NumberFormat.decimalPattern('en_US').format(whole.toInt());
    return '$grouped.$frac';
  }

  // ─── Destinations and the recipient ───────────────────────────────

  OrchestraReceiveOption _asOption(UsdSendDestination d) =>
      OrchestraReceiveOption(
        assetCode: d.assetCode,
        displayName: d.displayName,
        displaySymbol: d.displaySymbol,
        chain: d.chain,
        chainDisplayName: d.chainDisplayName,
        decimals: d.decimals,
        chainIconUrl: d.chainIconUrl,
        assetIconUrl: d.assetIconUrl,
      );

  /// Every Orchestra destination the dollar balance can reach, minus the
  /// rows the runtime policy withdraws (the coin sheet's own filter, so
  /// an address can never settle on a row the sheet would hide), and the
  /// reason the first withdrawn row gave.
  ({List<UsdSendDestination> offered, String? hiddenReason})
      _offeredDestinations(OrchestraRoutesCatalog catalog) {
    final all = usdSendDestinations(catalog);
    final result = orchestraOptionsOfferedUnderPolicy(
      [for (final d in all) _asOption(d)],
      RuntimeCapabilitiesService.instance,
      otherLegAsset: kOrchestraUsdAssetCode,
    );
    final ids = {for (final o in result.offered) '${o.chain}:${o.assetCode}'};
    return (
      offered: [
        for (final d in all)
          if (ids.contains(d.id)) d
      ],
      hiddenReason: result.hiddenReason,
    );
  }

  /// What the field's text means against what this send can reach.
  UsdRecipientMatch _match(String text,
      {required List<UsdSendDestination> offered}) {
    final raw = _chainId == null ? text : 'ethereum:$text@$_chainId';
    return matchUsdRecipient(raw, offered);
  }

  /// The offered destination a picker row stands for, matched by
  /// `chain:assetCode`.
  UsdSendDestination? _destinationFor(OrchestraReceiveOption row) {
    final offered =
        _offeredDestinations(ref.read(orchestraSupportedRoutesProvider))
            .offered;
    return offered
        .where((d) => d.id == '${row.chain}:${row.assetCode}')
        .firstOrNull;
  }

  /// A recipient handed over on open: a payment request that names its
  /// own network picks that coin and fills the field; one that names
  /// none waits for the pick ([_selectDestination] fills it then, if the
  /// picked network accepts it). Retried when the catalog lands.
  void _applyInitialRecipient() {
    final raw = _pendingRecipient;
    if (raw == null || _destination != null) return;
    final offered =
        _offeredDestinations(ref.read(orchestraSupportedRoutesProvider))
            .offered;
    if (offered.isEmpty) return;
    final pinned = usdSendPaymentRequestDestination(raw, offered);
    if (pinned == null) return;
    _pendingRecipient = null;
    _selectDestination(pinned, selection: 'deep_link', preselected: true);
    _commitRecipient(raw, method: 'deep_link');
  }

  /// The coin and network are picked (the grid, the sheet, or a payment
  /// request on open). An address already in stays only while the new
  /// network accepts it; otherwise it is cleared and the send goes back
  /// to Send to for a new one. On Review the estimate is asked again for
  /// the new destination.
  void _selectDestination(UsdSendDestination d,
      {required String selection, bool preselected = false}) {
    final firstPick = _destination == null;
    final address = _address.text.trim();
    final keepsAddress = address.isEmpty ||
        usdSendDestinationAccepts(d, address, chainId: _chainId);
    setState(() {
      _destination = d;
      _estimateOut = null;
      _estimateError = null;
      _error = null;
      if (!keepsAddress) {
        _address.clear();
        _chainId = null;
        _addressMethod = null;
        _reviewToExpanded = false;
        _completedSteps.removeAll({_kSendToStep, _kAmountStep});
      }
    });
    TrackingService.track('usd_send_coin_selected', params: {
      'asset': d.assetCode,
      'network': d.chain,
      'preselected': preselected,
    });
    _trackDestination(d, selection);
    if (!keepsAddress && _step != _kSendToStep) {
      _animateTo(_kSendToStep);
    } else if (_step == _kReviewStep && !_resolvingDrain) {
      unawaited(_fetchEstimate());
    }
    // A recipient handed over on open that named no network of its own
    // lands now, if this network takes it.
    final pending = _pendingRecipient;
    if (pending != null) {
      _pendingRecipient = null;
      if (_address.text.trim().isEmpty &&
          usdSendDestinationAccepts(d, bareRecipientAddress(pending),
              chainId: evmPaymentChainId(pending))) {
        _commitRecipient(pending, method: 'deep_link');
      }
    }
    if (firstPick || !keepsAddress) unawaited(_checkClipboard());
  }

  void _trackDestination(UsdSendDestination d, String selection) {
    TrackingService.track('usd_send_destination_selected', params: {
      'asset': d.assetCode,
      'chain': d.chain,
      'network': d.chain,
      'selection': selection,
    });
  }

  /// Paste, Scan, the clipboard nudge and a recent row all land here: a
  /// payment request is reduced to its bare address (an `ethereum:`
  /// request keeps the chain id it named). The picked destination never
  /// moves: an address for another network is refused by the field.
  void _commitRecipient(String raw, {required String method}) {
    final address = bareRecipientAddress(raw);
    if (address.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _clipboardCandidate = null;
      _chainId = evmPaymentChainId(raw);
      _address.value = TextEditingValue(
        text: address,
        selection: TextSelection.collapsed(offset: address.length),
      );
      _error = null;
    });
    _addressMethod = method;
  }

  void _onAddressTyped(String value) {
    // A request typed or pasted from the keyboard is reduced exactly as
    // the Paste button reduces it.
    if (bareRecipientAddress(value) != value.trim() && value.contains(':')) {
      _commitRecipient(value, method: 'pasted');
      return;
    }
    setState(() {
      _chainId = null;
      _error = null;
    });
    if (value.isNotEmpty) _addressMethod ??= 'typed';
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty) return;
      _commitRecipient(raw, method: 'pasted');
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  /// The shared smart scanner, in return-value mode: camera, Gallery and
  /// Paste, with its own camera-permission handling.
  Future<void> _scan() async {
    final scanned = await scanRecipientRaw(context);
    if (scanned == null || !mounted || _step != _kSendToStep) return;
    _commitRecipient(scanned, method: 'scanned');
  }

  /// Read the clipboard on arriving at Send to with a coin picked and
  /// keep it as a nudge when it holds a recipient the picked network
  /// accepts.
  Future<void> _checkClipboard() async {
    if (_address.text.isNotEmpty || _destination == null) return;
    try {
      if (!await Clipboard.hasStrings()) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty || raw.length > 2048) return;
      if (raw == _clipboardDismissed || raw == _clipboardCandidate) return;
      final d = _destination;
      if (d == null || _address.text.isNotEmpty) return;
      if (!usdSendDestinationAccepts(d, bareRecipientAddress(raw),
          chainId: evmPaymentChainId(raw))) {
        return;
      }
      setState(() => _clipboardCandidate = raw);
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  /// Last few recipients this wallet sent dollars to as [only] (the
  /// picked coin on its network), newest first, from the dollar send's
  /// own activity rows. Only rows whose destination is still offered are
  /// shown, so a tap always lands on a live route.
  List<
          ({
            String address,
            UsdSendDestination destination,
            String amount,
            DateTime when
          })>
      _recentRecipients(
          List<UsdSendDestination> offered, UsdSendDestination only) {
    final walletId = pickSpendingWallet(ref.watch(settingsProvider))?.id;
    final orders = ref.watch(swapOrdersProvider);
    final rows = orders
        .where((o) =>
            o.activityDirection == 'send' &&
            o.coinFrom.toUpperCase() == kOrchestraUsdAssetCode &&
            o.networkFrom.toUpperCase() == 'SPARK' &&
            o.withdrawalAddress.trim().isNotEmpty &&
            (o.walletId == null || o.walletId == walletId))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final seen = <String>{};
    final out = <({
      String address,
      UsdSendDestination destination,
      String amount,
      DateTime when
    })>[];
    for (final o in rows) {
      final chain = o.networkTo.toLowerCase();
      final destination = offered
          .where((d) =>
              d.chain == chain &&
              d.assetCode.toUpperCase() == o.coinTo.toUpperCase())
          .firstOrNull;
      if (destination == null || destination.id != only.id) continue;
      final address = o.withdrawalAddress.trim();
      if (!usdSendDestinationAccepts(destination, address)) continue;
      if (!seen.add('${destination.id}|${address.toLowerCase()}')) continue;
      out.add((
        address: address,
        destination: destination,
        amount: o.depositAmount,
        when: DateTime.fromMillisecondsSinceEpoch(o.timestamp),
      ));
      if (out.length >= 5) break;
    }
    return out;
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spending = pickSpendingWallet(ref.watch(settingsProvider));
    // A catalog that lands after the sheet opened can still place a
    // recipient handed over on open.
    ref.listen(orchestraSupportedRoutesProvider, (_, __) {
      if (_step == _kSendToStep) _applyInitialRecipient();
    });
    // The send sheet: medium on Send to until a recipient is in, full
    // from there on. A drag or a scrim tap may close it only on Send to
    // and never while the send (or a venue pull for it) is running.
    final onFirstStep = _step == _kSendToStep;
    SendSheetScope.sync(
      context,
      expanded: !onFirstStep || _address.text.trim().isNotEmpty,
      dismissible: onFirstStep && !_processing,
    );
    return PopScope(
      // Past Send to, system back steps back inside the send instead of
      // dropping it.
      canPop: !_processing && onFirstStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_processing && !onFirstStep) _onLeadingTap();
      },
      child: KeyboardDismissOnTap(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: c.background,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            scrolledUnderElevation: 0,
            centerTitle: true,
            // The balance the dollars leave from, read-only, in the place
            // the bitcoin send names its wallet: "Investments", never the
            // spending wallet that holds it (founder decision).
            title: spending == null
                ? null
                : AccountSwitcherPill(
                    pickerTitle: context.l10n.sendFromPickerTitle,
                    readOnly: true,
                    label: context.l10n.assetDollars,
                  ),
            leading: onFirstStep
                ? KuteBareCloseButton(onPressed: _onLeadingTap)
                : KuteBackButton(onPressed: _onLeadingTap),
          ),
          body: SendStepperFrame(
            progress: StepperProgress(
              totalSteps: 3,
              currentStep: _step,
              completedSteps: _completedSteps,
              colors: c,
            ),
            controller: _pageCtrl,
            onPageChanged: (i) {
              setState(() => _step = i);
              if (i == _kSendToStep) unawaited(_checkClipboard());
            },
            // No visible step headings (founder decision, 14 October
            // 2026): each page is announced by name to screen readers.
            pages: [
              SendStepPage(
                title: context.l10n.sendTo,
                child: _sendToPage(c),
              ),
              SendStepPage(
                title: context.l10n.amount,
                child: _amountPage(c),
              ),
              SendStepPage(
                title: context.l10n.sendReview,
                trailing: const AskSalChip(
                  advisorContext: AdvisorContext(surface: 'send_review'),
                ),
                child: _reviewPage(c),
              ),
            ],
            cta: SharedStepCta(
              step: _step,
              colors: c,
              visibleSteps: const {_kSendToStep, _kAmountStep},
              enabled: _step == _kAmountStep
                  ? _amountStepValid
                  : _step == _kSendToStep && _recipientReady,
              onContinue: () {
                if (_step == _kAmountStep) _confirmAmount();
                if (_step == _kSendToStep) _confirmRecipient();
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 2: Amount ───────────────────────────────────────────────

  Widget _amountPage(AppColorsExtension c) {
    ref.watch(usdBalanceProvider);
    // The last known figure is on screen at once; the venues are read
    // again in the background and the number follows.
    ref.watch(investmentsSpendableProvider);
    ref.watch(venueCashRefreshProvider);
    final available = _reachUsd;
    final overBalance = _amountExceedsBalance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero ── the one big number with its unit pill and the
        // available balance, scrolling so the pinned keypad always fits.
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(top: 4.h, bottom: 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // What the recipient gets, changeable from here.
                if (_destination != null) ...[
                  _destinationChip(_destination!),
                  SizedBox(height: 14.h),
                ],
                Row(
                  children: [
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _amountPulse,
                        builder: (context, child) {
                          final t = _amountPulse.value;
                          final scale =
                              0.94 + Curves.easeOutBack.transform(t) * 0.06;
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: SendTypedAmountHero(
                            prefix: '\$',
                            typed: _typed,
                            overBalance: overBalance,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    // Dollars only: the pill names the unit and has
                    // nothing to switch to.
                    SendAmountUnitPill(
                      code: 'USD',
                      icon: SvgPicture.asset(kUsdMarkAsset,
                          width: 20.sp, height: 20.sp),
                    ),
                  ],
                ),
                if (overBalance || _amountBelowMinimum) ...[
                  SizedBox(height: 8.h),
                  Text(
                    overBalance
                        ? context.l10n.sendMoreThanAvailable
                        : context.l10n
                            .usdSendMinimum('\$${_kMinUsd.toStringAsFixed(2)}'),
                    style: TextStyle(
                      color: AppColors.marketDown,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
                SizedBox(height: 10.h),
                Text(
                  context.l10n.hlYieldAvailableLine(
                      '\$${available.toStringAsFixed(2)}'),
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Bottom, pinned: percent chips + keypad ──
        AmountPercentChips(
          enabled: !_processing,
          onPercent: _onPercent,
        ),
        SizedBox(height: 12.h),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: AmountKeypad(
            value: _typed,
            maxDecimals: 2,
            enabled: !_processing,
            onChanged: (v) {
              setState(() {
                _amountMethod = 'keypad';
                _drain = false;
                _drainUnits = null;
                _drainError = null;
                _error = null;
                _typed = v;
              });
              if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
                _amountPulse.forward(from: 0.0);
              }
            },
          ),
        ),
      ],
    );
  }

  /// 25/50 set a bounded amount to the cent. 100% arms the drain: the
  /// balance shows to the cent here and Review reads the exact figure
  /// from the SDK, so no sub-cent dust is left behind.
  void _onPercent(double ratio) {
    HapticFeedback.selectionClick();
    // 100% of Dollars alone is the exact drain; with venue cash in reach
    // it is the reach to the cent, sent as typed.
    final reach = _reachUsd;
    final withVenueCash = reach > _availableUsd + 0.005;
    final drain = ratio >= 1 && !withVenueCash;
    _amountMethod = ratio >= 1 ? 'max' : 'percent_${(ratio * 100).round()}';
    TrackingService.track('send_amount_percent_tapped', params: {
      'percent': (ratio * 100).round(),
      'source_asset': 'usd',
    });
    // Cents, floored: the keypad types two decimals, so the percentage
    // lands on one too rather than on a sub-cent amount it cannot show.
    final cents = (reach * ratio * 100).floor();
    setState(() {
      _error = null;
      _drain = drain;
      _drainUnits = null;
      _drainError = null;
      _typed = (cents / 100).toStringAsFixed(2);
    });
  }

  /// Amount → Review. The recipient was settled on the step before; it
  /// is held to the same gate again here, so Review never opens on a
  /// destination that stopped fitting.
  void _confirmAmount() {
    if (!_amountStepValid || !_recipientReady) return;
    TrackingService.moneyFlowStep('usd_send', 'review', props: _flowInputs());
    _advanceTo(_kReviewStep, completed: _kAmountStep);
    if (_drain) {
      unawaited(_resolveDrain());
    } else {
      unawaited(_fetchEstimate());
    }
  }

  // ─── Step 1: Send to ──────────────────────────────────────────────

  /// Whether the recipient and destination can be sent to. Continue is
  /// dead until they are.
  bool get _recipientReady {
    final d = _destination;
    final address = _address.text.trim();
    if (d == null || address.isEmpty) return false;
    if (!usdSendDestinationAccepts(d, address, chainId: _chainId)) {
      return false;
    }
    return true;
  }

  /// Send to: the coin grid until a coin is picked, then the picked coin
  /// as a chip over the recipient field, its Paste and Scan, and the
  /// recents for that coin.
  Widget _sendToPage(AppColorsExtension c) {
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final offered = _offeredDestinations(catalog);
    final destination = _destination;
    if (destination == null) return _coinStep(offered.offered);

    final l10n = context.l10n;
    final addr = _address.text.trim();
    final match = _match(addr, offered: offered.offered);
    final accepted = addr.isNotEmpty &&
        usdSendDestinationAccepts(destination, addr, chainId: _chainId);

    // What the field says about itself, in the bitcoin send's words. The
    // picked network is the only one it is checked against.
    String? error;
    if (addr.isNotEmpty && !accepted) {
      if (!match.recognised) {
        error = l10n.sendAddressNotIdentified;
      } else if (match.candidates.isEmpty) {
        error = offered.hiddenReason ?? l10n.usdSendAddressUnsupported;
      } else {
        error = l10n.usdSendAddressWrongNetwork(destination.chainDisplayName);
      }
    }
    final recents = addr.isEmpty
        ? _recentRecipients(offered.offered, destination)
        : const <({
            String address,
            UsdSendDestination destination,
            String amount,
            DateTime when
          })>[];

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _destinationChip(destination),
          ),
          SizedBox(height: 16.h),
          SendRecipientField(
            controller: _address,
            colors: c,
            hintText: l10n.sendAssetOnNetworkAddressHint(
                destination.displaySymbol, destination.chainDisplayName),
            isValid: accepted,
            onPaste: _paste,
            onScan: _scan,
            onChanged: _onAddressTyped,
          ),
          if (error != null) ...[
            SizedBox(height: 10.h),
            SendRecipientError(message: error),
          ] else if (accepted && match.recognised) ...[
            SizedBox(height: 10.h),
            SendDetectedBadge(
              label: _familyLabel(match.family),
              icon: _familyIcon(match.family),
              color: const Color(0xFF2775CA),
              identity: match.family,
            ),
          ],
          if (_clipboardCandidate != null && addr.isEmpty) ...[
            SizedBox(height: 12.h),
            SendClipboardNudge(
              onUse: () =>
                  _commitRecipient(_clipboardCandidate!, method: 'pasted'),
              onDismiss: () => setState(() {
                _clipboardDismissed = _clipboardCandidate;
                _clipboardCandidate = null;
              }),
            ),
          ],
          if (recents.isNotEmpty) ...[
            SizedBox(height: 24.h),
            SendToSectionHeader(title: l10n.sendRecentRecipients),
            SendToListCard(
              colors: c,
              rows: [
                for (final r in recents)
                  SendToListRow(
                    colors: c,
                    leading: _destinationMark(r.destination, size: 32),
                    title: sendShortAddress(r.address),
                    subtitle:
                        '${r.destination.displaySymbol} · ${r.destination.chainDisplayName}',
                    trailingTitle: '\$${r.amount}',
                    trailingSubtitle: DateFormat.MMMd(
                            Localizations.localeOf(context).toString())
                        .format(r.when),
                    onTap: () => _commitRecipient(r.address, method: 'recent'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The first thing on Send to: the coins dollars can be sent as, one
  /// tile per coin (the receive step's grid, the coin sheet's set). A
  /// coin on one network is picked at once; a coin on several opens the
  /// sheet on its networks.
  Widget _coinStep(List<UsdSendDestination> offered) {
    final l10n = context.l10n;
    // Still fetching is not the same as nothing to offer.
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final groups = coinGroupsOfferedUnderPolicy(
      groupCoinsByAsset([for (final d in offered) _asOption(d)]),
      otherLegAsset: kOrchestraUsdAssetCode,
    ).groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SendToSectionHeader(title: l10n.usdFlowStepCoin),
        Expanded(
          child: CoinAssetGrid(
            key: const ValueKey('usd-send-coin-grid'),
            groups: groups,
            emptyLabel: loading
                ? l10n.usdSendRoutesUnavailable
                : l10n.usdSendDestinationsUnavailable,
            markBuilder: (g, size) =>
                AssetIcon(assetCode: g.assetCode, size: size),
            onPick: _pickGroup,
          ),
        ),
      ],
    );
  }

  /// A coin tapped on the Send to grid.
  void _pickGroup(CoinAssetGroup group) {
    TrackingService.track('coin_picker_coin_picked', params: {
      'flow': 'usd_send',
      'asset': group.assetCode,
      'networks': group.options.length,
    });
    if (group.isSingleNetwork) {
      final d = _destinationFor(group.options.first);
      if (d != null) _selectDestination(d, selection: 'grid');
      return;
    }
    _openDestinationPicker(initialGroupKey: group.key);
  }

  /// The picked coin and network, on every step: tapping it reopens the
  /// picker.
  Widget _destinationChip(UsdSendDestination destination) => SendAmountUnitPill(
        key: const ValueKey('usd-send-coin-chip'),
        code: '${destination.displaySymbol} · ${destination.chainDisplayName}',
        icon: _destinationMark(destination, size: 22),
        onTap: _processing ? null : _openDestinationPicker,
      );

  /// Plain words for the badge under the field, shared with the bitcoin
  /// send's copy.
  String _familyLabel(String family) {
    final l10n = context.l10n;
    return switch (family) {
      'evm' => l10n.sendDetectedEthereumStyleAddress,
      'solana' => l10n.sendDetectedSolanaAddress,
      'bitcoin' => l10n.sendDetectedBitcoinAddress,
      'spark' => l10n.sendDetectedSpendingWalletAddress,
      _ => orchestraChainDisplayName(family),
    };
  }

  IconData _familyIcon(String family) => switch (family) {
        'evm' => Icons.account_tree_rounded,
        'solana' => Icons.brightness_7_rounded,
        'bitcoin' => Icons.currency_bitcoin_rounded,
        'spark' => Icons.flash_on_rounded,
        _ => Icons.account_balance_wallet_outlined,
      };

  /// The coin sheet every money screen opens, asset first and network
  /// second, over every destination the dollars can be sent to; open on
  /// [initialGroupKey]'s networks when a multi-network coin was tapped on
  /// the grid. The picked row is matched back by `chain:assetCode`, the
  /// id the dollar table keys on.
  void _openDestinationPicker({String? initialGroupKey}) {
    TrackingService.track('usd_send_coin_picker_opened');
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          // Watch so the offering re-folds the moment the live catalog
          // lands.
          final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          final choices = _offeredDestinations(catalog).offered;
          return CoinAssetPickerSheet(
            otherLegAsset: kOrchestraUsdAssetCode,
            groups: groupCoinsByAsset([for (final d in choices) _asOption(d)]),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: ctx.l10n.usdSendPickCoin,
            emptyLabel: loading
                ? ctx.l10n.usdSendRoutesUnavailable
                : ctx.l10n.usdSendDestinationsUnavailable,
            flow: 'usd_send',
            initialAssetCode: initialGroupKey,
            selectedOptionId: _destination?.id,
            onPicked: (row) {
              final picked = choices
                  .where((d) => d.id == '${row.chain}:${row.assetCode}')
                  .firstOrNull;
              if (picked == null) return;
              Navigator.of(sheetCtx).pop();
              _selectDestination(picked, selection: 'picker');
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// Send to → Amount.
  void _confirmRecipient() {
    if (!_recipientReady) return;
    TrackingService.moneyFlowStep('usd_send', 'amount', props: _flowInputs());
    _advanceTo(_kAmountStep, completed: _kSendToStep);
  }

  // ─── Step 3: Review ───────────────────────────────────────────────

  /// 100%, made exact: the dollar balance in the token's own base units,
  /// read from the SDK's cached balance, replacing the cent-floored figure the
  /// amount step showed. The send moves exactly this.
  Future<void> _resolveDrain() async {
    setState(() {
      _resolvingDrain = true;
      _drainError = null;
      _drainUnits = null;
    });
    try {
      final wrapper = await ref.read(breezSDKProvider.future);
      final sdk = wrapper.instance;
      if (sdk == null) throw StateError('spending wallet disconnected');
      final units = await usdDrainBaseUnits(sdk);
      if (!mounted || !_drain) return;
      setState(() {
        _resolvingDrain = false;
        if (units < _minBaseUnits) {
          _drainError =
              context.l10n.usdSendMinimum('\$${_kMinUsd.toStringAsFixed(2)}');
        } else {
          _drainUnits = units;
        }
      });
      if (_drainUnits != null) unawaited(_fetchEstimate());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvingDrain = false;
        _drainError = context.l10n.usdSendFailed;
      });
    }
  }

  /// The live estimate behind "You receive". An Orchestra estimate for
  /// the exact amount; a plain dollar transfer arrives as sent and needs
  /// none.
  Future<void> _fetchEstimate() async {
    final destination = _destination;
    final units = _amountBaseUnits;
    if (destination == null) return;
    if (units == null || units <= BigInt.zero) return;
    final seq = ++_estimateSeq;
    setState(() {
      _estimateLoading = true;
      _estimateError = null;
      _estimateOut = null;
    });
    try {
      final est = await OrchestraService.getEstimate(
        sourceChain: kOrchestraUsdChain,
        sourceAsset: kOrchestraUsdAssetCode,
        destinationChain: destination.chain,
        destinationAsset: orchestraAssetCodeFor(destination.assetCode),
        amount: units.toString(), // dollar base units, six decimals
        // The address the send's quote pays, once it is one the
        // destination accepts.
        recipientAddress: _recipientReady ? _address.text.trim() : null,
      );
      if (!mounted || seq != _estimateSeq) return;
      final gross = est.data == null
          ? 0.0
          : orchestraAmountToDouble(
              est.data!.estimatedOut, destination.assetCode,
              chain: destination.chain);
      // The estimate leaves the Kute fee out; the quote that is paid
      // takes it, so "You receive" and the fee note use the net figure.
      final out = est.data == null
          ? 0.0
          : orchestraOutNetOfKuteFee(est.data!, gross) ?? gross;
      setState(() {
        _estimateLoading = false;
        if (out > 0) {
          _estimateOut = out;
        } else {
          _estimateError = context.l10n.swapRouteTemporarilyUnavailable;
        }
      });
    } catch (_) {
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _estimateLoading = false;
        _estimateError = context.l10n.receiveNetworkErrorTapToRetry;
      });
    }
  }

  static String _formatOut(double v) {
    if (v >= 1) return v.toStringAsFixed(2);
    final s = v.toStringAsFixed(8);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Widget _reviewPage(AppColorsExtension c) {
    final l10n = context.l10n;
    final destination = _destination;
    final addr = _address.text.trim();
    // The From row reads what the send can spend, as on the amount step:
    // the Max (Dollars plus reachable venue cash, net of the move costs).
    ref.watch(usdBalanceProvider);
    ref.watch(investmentsSpendableProvider);
    final available = _reachUsd;
    final units = _amountBaseUnits;
    final heroText = units == null ? '0.00' : _formatUsdUnits(units);
    final waiting = _resolvingDrain || _estimateLoading;
    final canSend = !_processing &&
        !_resolvingDrain &&
        _completedSteps.containsAll({_kAmountStep, _kSendToStep}) &&
        _recipientReady &&
        _amountValid;

    final feeRows = <Widget>[];
    if (destination != null) {
      if (_estimateError != null) {
        feeRows.add(GestureDetector(
          onTap: () => unawaited(_fetchEstimate()),
          child: SendReviewErrorRow(
              label: l10n.youReceive, error: _estimateError!),
        ));
      } else {
        final out = _estimateOut;
        feeRows.add(SendReviewKVRow(
          label: l10n.youReceive,
          value: out == null
              ? l10n.sendCalculatingEllipsis
              : '≈ ${_formatOut(out)} ${destination.displaySymbol}',
          muted: true,
        ));
        if (out != null) {
          // The route's whole cost, when both legs are dollars: what goes
          // in less what is quoted out.
          final sent = _amountUsd;
          final stable = const {'USDC', 'USDT', 'USDB'}
              .contains(destination.assetCode.toUpperCase().split('.').first);
          final fee = stable ? sent - out : 0.0;
          feeRows
            ..add(SizedBox(height: 10.h))
            ..add(SendReviewNote(
                text: fee > 0
                    ? l10n.sendLiveQuoteProviderWithFee(
                        'Orchestra', '\$${fee.toStringAsFixed(2)}')
                    : l10n.sendLiveQuoteProvider('Orchestra')));
        }
      }
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero amount, chromeless, as on the bitcoin Review. For
                // 100% it becomes the exact balance once it is read.
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text('\$$heroText',
                        style: sendHeroAmountStyle(c.textPrimary)),
                  ),
                ),
                // What the recipient gets, changeable up to the last tap.
                if (destination != null) ...[
                  SizedBox(height: 4.h),
                  Center(child: _destinationChip(destination)),
                ],
                SizedBox(height: 20.h),
                // ─── From → To card ───
                SendReviewCard(
                  child: Column(
                    children: [
                      SendReviewSummaryRow(
                        label: l10n.from,
                        title: l10n.assetDollars,
                        subtitle: l10n.sendAvailableBalanceSubtitle(
                            '\$${available.toStringAsFixed(2)}'),
                        // The dollar balance as a source row wears the
                        // Investments arrow, never the USDB coin.
                        icon: Icon(kInvestmentsIcon,
                            size: 24.sp, color: c.textPrimary),
                      ),
                      Divider(
                          height: 1,
                          thickness: 1,
                          color: c.borderSubtle,
                          indent: 14.w),
                      InkWell(
                        onTap: addr.isEmpty
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                setState(() =>
                                    _reviewToExpanded = !_reviewToExpanded);
                              },
                        borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(18.r)),
                        child: SendReviewSummaryRow(
                          label: l10n.to,
                          title: addr.isEmpty ? '…' : sendShortAddress(addr),
                          subtitle: destination == null
                              ? ''
                              : '${destination.displaySymbol} · ${destination.chainDisplayName}',
                          icon: destination == null
                              ? const SizedBox.shrink()
                              : _destinationMark(destination, size: 24),
                          trailing: addr.isEmpty
                              ? null
                              : Icon(
                                  _reviewToExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 18.sp,
                                  color: c.textTertiary),
                        ),
                      ),
                      if (_reviewToExpanded && addr.isNotEmpty)
                        SendReviewFullAddress(
                          address: addr,
                          onCopied: () => TrackingService.track(
                              'pay_review_address_copied',
                              params: {'address_type': 'usd_recipient'}),
                        ),
                    ],
                  ),
                ),
                if (feeRows.isNotEmpty) ...[
                  SizedBox(height: 14.h),
                  SendReviewCard(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    child: Column(children: feeRows),
                  ),
                ],
                if ((_error ?? _drainError) != null) ...[
                  SizedBox(height: 14.h),
                  SendRecipientError(message: (_error ?? _drainError)!),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: 16.h),
        SendReviewAction(
          label: _processing
              ? l10n.sendSendingEllipsis
              : _retryPull && _error != null
                  ? l10n.retry
                  : l10n.send,
          loading: _processing,
          onPressed: canSend ? _confirmSend : null,
          footnote: _pullProgress ??
              (waiting
                  ? l10n.sendWaitForFee
                  : l10n.sendFundsLeaveYourWalletImmediately),
        ),
      ],
    );
  }

  Widget _destinationMark(UsdSendDestination destination,
      {required double size}) {
    return PickerCoinBadgeIcon(
      size: size,
      coinIcon: ChainAvatarIcon(
        chainId: destination.assetCode,
        label: destination.displaySymbol,
        iconUrl: destination.assetIconUrl,
        size: size,
      ),
      badge: ChainAvatarIcon(
        chainId: destination.chain,
        label: destination.chainDisplayName,
        iconUrl: destination.chainIconUrl,
        size: size / 2,
      ),
    );
  }

  // ─── Navigation ───────────────────────────────────────────────────

  void _advanceTo(int target, {required int completed}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _completedSteps.add(completed);
      _error = null;
    });
    _animateTo(target);
  }

  void _animateTo(int target) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageCtrl.jumpToPage(target);
    } else {
      // ignore: discarded_futures
      _pageCtrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// First tap on a later step goes back one page; on Send to it closes.
  void _onLeadingTap() {
    if (_processing) return;
    if (_step <= _kSendToStep) {
      Navigator.of(context).maybePop();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _completedSteps.remove(_step);
      _error = null;
    });
    _animateTo(_step - 1);
  }

  /// Review → send. The settlement runner quotes and goes straight into
  /// the step-up prompt; the Review page is the decision.
  void _confirmSend() {
    // `usd_send_confirmed` fires in _send once the local gates pass, so
    // a tap that is refused (in flight, bad address, bad amount) does
    // not count as a confirmation.
    setState(() {
      _error = null;
    });
    // ignore: discarded_futures
    _send();
  }

  // ─── The send ─────────────────────────────────────────────────────

  /// Tap to settlement, in order:
  ///
  ///   1. Local gates: a destination, an address it accepts, an amount
  ///      between the minimum and the balance (or the resolved 100%).
  ///      Any of these failing stops here and moves nothing.
  ///   2. The wallet's own Spark address is resolved as the
  ///      REFUND target. Failing to resolve it throws before any quote.
  ///   3. `HotSettlement.plan` with the route `spark:USDB → chain:asset`
  ///      and `destination: null` (an external recipient), then
  ///      `runner.run`, which checks route availability, persists the
  ///      operation, quotes, steps up, prepares and funds.
  ///   4. `prepareSpark` asks the SDK for a TOKEN payment of exactly the
  ///      verified quote's `amountIn` base units, and refuses unless the
  ///      SDK echoes back the same deposit address, the same amount and
  ///      the same token identifier.
  ///   5. `sendSpark` sends that prepared payment and nothing else.
  ///
  /// Every step can only fail by throwing, and the catch below shows the
  /// failure. There is no second rail in this file.
  Future<void> _send() async {
    if (_processing) return;
    final destination = _destination;
    if (destination == null || !_recipientReady) return;
    final amountBaseUnits = _amountBaseUnits;
    if (amountBaseUnits == null || !_amountValid) {
      final exceeds = amountBaseUnits != null &&
          !_drain &&
          amountBaseUnits > _reachBaseUnits;
      TrackingService.moneyFlowError(
          'usd_send', exceeds ? 'insufficient_funds' : 'below_minimum');
      setState(() {
        _error = exceeds
            ? context.l10n.usdSendNotEnough
            : context.l10n.usdSendMinimum('\$${_kMinUsd.toStringAsFixed(2)}');
      });
      return;
    }
    final recipient = _address.text.trim();
    // Dollars only ever for the analytics bucket and the step-up sheet;
    // the money itself is the BigInt above.
    final usdForDisplay = amountBaseUnits.toDouble() / 1e6;

    TrackingService.moneyFlowSubmitted('usd_send',
        event: 'usd_send_confirmed',
        props: {
          'asset': destination.assetCode,
          'chain': destination.chain,
          'network': destination.chain,
          ..._flowInputs(),
        });

    // Dollars first: when they do not hold the amount, the shortfall
    // comes home from venue cash before the send asks for its one
    // approval. Nothing is sent until Dollars hold the whole amount.
    if (_retryPull && _error != null && _moveId != null) {
      trackMultiSourceMoveRetry(
          MultiSourceMoveStore.get(_moveId!)?.remainingUsd ?? 0);
    }
    _retryPull = false;
    if (!_drain && amountBaseUnits > _availableBaseUnits) {
      final ready = await _pullVenueCash(usdForDisplay);
      if (!ready) return;
    } else if (_moveUsd != usdForDisplay) {
      _moveId = null;
    }

    // Outcome analytics: one `send_completed` / `send_failed` per send
    // that passed the gates above.
    final sendNetwork = destination.chain.toLowerCase();
    final sendAsset = destination.assetCode.toLowerCase();
    final walletKind = _walletKind();

    TrackingService.track('usd_send_initiated', params: {
      'asset': destination.assetCode,
      'chain': destination.chain,
      'network': destination.chain,
      'amount_bucket': TrackingService.usdBucket(usdForDisplay),
      'provider': 'orchestra',
    });
    TrackingService.swapInitiated(
      fromCoin: kOrchestraUsdAssetCode,
      toCoin: destination.assetCode,
      provider: 'orchestra',
      amountUsd: usdForDisplay,
    );

    var sendDone = false;
    setState(() {
      _processing = true;
      _error = null;
    });

    final destAsset = orchestraAssetCodeFor(destination.assetCode);
    try {
      final refundAddress = await ref.read(sparkSelfAddressProvider.future);
      final runner = await HotSettlement.runner();
      final settled = await runner.run(HotSettlement.plan(
        ref.read,
        flow: SettlementFlow.sendExternal,
        route: RouteKey(
          fromChain: kOrchestraUsdChain,
          fromAsset: kOrchestraUsdAssetCode,
          toChain: destination.chain,
          toAsset: destAsset,
        ),
        source: SettlementAccountKind.sparkHot,
        destination: null,
        externalRecipient: recipient,
        amountUsd: usdForDisplay,
        requestQuote: (key) => HotSettlement.quote(
          ref.read,
          OrchestraQuoteRequest(
            sourceChain: kOrchestraUsdChain,
            sourceAsset: kOrchestraUsdAssetCode,
            destinationChain: destination.chain,
            destinationAsset: destAsset,
            // The typed digits (or the resolved 100%), in the token's own
            // base units. This is the only amount in the whole path.
            amountBaseUnits: amountBaseUnits,
            recipientAddress: recipient,
            refundAddress: refundAddress,
            recipientKind: RecipientKind.external,
          ),
          flow: 'send_dollars',
          idempotencyKey: key,
        ),
        stepUp: (auth) async {
          if (!mounted) return false;
          // The person decided on Review and the step-up prompt below is
          // the confirmation. The runner's own drift check still refuses
          // a quote that moved against them.
          final intent = OrchestraGrants.settlement(
            auth,
            action: SensitiveAction.send,
            asset: kOrchestraUsdAssetCode,
          );
          final grant = await requireFreshAuthGrant(
            context,
            ref,
            intent: intent,
            reason: context.l10n.stepUpReasonSend(
                '\$${(auth.amountIn.toDouble() / 1e6).toStringAsFixed(2)}'),
            amountUsd: auth.amountIn.toDouble() / 1e6,
          );
          if (grant == null) return false;
          try {
            AuthGrants.consume(grant, intent);
            return true;
          } on AuthGrantException {
            return false;
          }
        },
        // The token-aware funding leg. It decides WHICH BALANCE PAYS
        // from the verified quote's source asset and holds the SDK's
        // reply to an equality echo on the token identifier, so this is
        // a dollar payment or it is no payment at all.
        prepareFunding: (verifiedQuote, _) =>
            HotSettlement.prepareSpark(ref.read, verifiedQuote),
        fund: (verifiedQuote, prepared) async {
          final paymentId = await HotSettlement.sendSpark(ref.read, prepared);
          // The exchange row below tells the story once; without this
          // the raw token transfer would tell it a second time.
          PolymarketSparkTxsService.tag(paymentId);
          return SettlementFundingProof.spark(paymentId);
        },
      ));

      final orchQuote = settled.quote.quote;
      final sentUsd = settled.quote.amountIn.toDouble() / 1e6;
      final orderId = settled.orderId ?? orchQuote.quoteId;
      final estOut = orchestraAmountToDouble(
          orchQuote.estimatedOut, destination.assetCode,
          chain: destination.chain);

      // The deposit leg is written in DOLLARS, two decimals. Writing it
      // with the bitcoin divisor is the bug the dollar rows exist to
      // make impossible.
      final exchange = SwapOrder(
        activityDirection: 'send',
        id: orderId,
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: destination.assetCode,
        networkTo: destination.chain.toUpperCase(),
        depositAddress: orchQuote.depositAddress,
        depositAmount: sentUsd.toStringAsFixed(2),
        withdrawalAmount: estOut.toStringAsFixed(2),
        status: 'exchanging',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: recipient,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: settled.operation.refund?.address ?? refundAddress,
        provider: 'Orchestra',
        walletId: ref.read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      // The send is the last leg of its multi-source move: one row.
      MultiSourceMoveStore.attachFinal(_moveId, settled.operation.operationId);
      _moveId = null;
      await ref.read(swapOrdersProvider.notifier).addExchange(exchange);
      ref
          .read(walletTransactionCacheProvider.notifier)
          .mergeSwapOrder(exchange);
      // Backend attribution for the REAL order only — a quote id (q_…)
      // would create a row the completion can never reconcile with.
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: kOrchestraUsdAssetCode,
          sourceAmount: sentUsd,
          destinationAsset: destination.assetCode,
          destinationAmount: estOut,
        );
      }
      BackgroundSyncService().syncNow();
      TrackingService.track('usd_send_completed', params: {
        'asset': destination.assetCode,
        'chain': destination.chain,
        'network': destination.chain,
        'amount_bucket': TrackingService.usdBucket(sentUsd),
        'order_id': orderId,
        'provider': 'orchestra',
      });
      // Deposit submitted: the user's send is done (delivery is the
      // swap lifecycle's). For a dollar destination the route's whole
      // cost is what went in less the quoted output.
      sendDone = true;
      final feeUsd = estOut > 0 ? sentUsd - estOut : null;
      TrackingService.sendCompleted(
        flow: 'usd_send',
        network: sendNetwork,
        asset: sendAsset,
        walletKind: walletKind,
        provider: 'orchestra',
        amountUsd: sentUsd,
        amount: estOut > 0 ? estOut : sentUsd,
        currency: 'USD',
        amountFiat: usdForDisplay,
        feeUsd: feeUsd != null && feeUsd >= 0 ? feeUsd : null,
        dedupeKey: settled.operation.operationId,
      );
      TrackingService.moneyFlowFinished('usd_send');

      if (!mounted) return;
      _showSent(destination,
          detail: settled.registered
              ? context.l10n.moveConversionOngoing
              : context.l10n.settlementRegistering);
    } catch (e) {
      // NOTHING IS RETRIED HERE, on any rail. A declined step-up is
      // silent (the user said no); everything else shows why and leaves
      // the dollar balance exactly where it was.
      TrackingService.swapFailed(
        fromCoin: kOrchestraUsdAssetCode,
        toCoin: destination.assetCode,
        provider: 'orchestra',
        reason:
            e is SettlementStopped ? 'settlement_${e.reason.name}' : 'error',
        fromNetwork: kOrchestraUsdChain.toLowerCase(),
        toNetwork: sendNetwork,
        venue: 'orchestra',
        fromAmount: usdForDisplay,
        amountUsd: usdForDisplay,
      );
      // One outcome per send: a decline (step-up refused) reports as
      // `user_cancelled`; a replaced quote goes back for another tap and
      // is not an outcome; a throw after the deposit was submitted is
      // UI only (send_completed already fired).
      final stopped = e is SettlementStopped ? e.reason : null;
      if (!sendDone && stopped != SettlementStopReason.quoteReplaced) {
        TrackingService.sendFailed(
          flow: 'usd_send',
          network: sendNetwork,
          asset: sendAsset,
          error: stopped == SettlementStopReason.declined
              ? 'declined'
              : stopped != null
                  ? 'settlement_${stopped.name}'
                  : e,
          walletKind: walletKind,
          provider: 'orchestra',
          amountUsd: usdForDisplay,
          amount: usdForDisplay,
          currency: 'USD',
          amountFiat: usdForDisplay,
          stage: switch (stopped) {
            SettlementStopReason.declined => 'sign',
            SettlementStopReason.quoteExpired ||
            SettlementStopReason.routeUnavailable ||
            SettlementStopReason.blockedPending =>
              'quote',
            _ => 'settle',
          },
        );
        TrackingService.moneyFlowError('usd_send', e);
      }
      if (!mounted) return;
      if (e is SettlementStopped && e.reason == SettlementStopReason.declined) {
        setState(() {
          _processing = false;
        });
        return;
      }
      setState(() {
        _processing = false;
        _error = HotSettlement.messageFor(e, context.l10n) ??
            context.l10n.usdSendFailed;
      });
    }
  }

  /// Brings the shortfall of [usd] home from venue cash and waits,
  /// bounded, for Dollars to hold it. True to go on with the send; false
  /// when it stopped (the reason is on screen, and whatever was pulled
  /// stays in Dollars: the send never goes twice).
  Future<bool> _pullVenueCash(double usd) async {
    setState(() {
      _processing = true;
      _error = null;
    });
    VenueCashPullOutcome? outcome;
    try {
      if (_moveUsd != usd) _moveId = null;
      outcome = await ref.read(venueCashPullerProvider).pullShortfall(
            neededUsd: usd,
            forAction: VenueCashFor.send,
            moveId: _moveId,
            onPlanned: (plan) {
              if (!mounted || plan.pulls.isEmpty) return;
              setState(() =>
                  _pullProgress = venueCashProgressText(context.l10n, plan));
            },
          );
    } catch (_) {
      outcome = null;
    }
    if (outcome?.moveId != null) {
      _moveId = outcome!.moveId;
      _moveUsd = usd;
    }
    if (!mounted) return false;
    if (outcome != null && outcome.dollarsCover) {
      setState(() => _pullProgress = null);
      return true;
    }
    // A leg that did not go: Retry pulls only what it left behind.
    _retryPull = outcome != null && outcome.failedLegs.isNotEmpty;
    TrackingService.moneyFlowError(
        'usd_send',
        outcome == null || !outcome.plan.covers
            ? 'insufficient_funds'
            : 'venue_cash_pending');
    setState(() {
      _processing = false;
      _pullProgress = null;
      _error = (outcome == null
              ? null
              : venueCashStoppedText(context.l10n, outcome)) ??
          (outcome != null && !outcome.plan.covers
              ? context.l10n.usdSendNotEnough
              : context.l10n.usdSendFailed);
    });
    return false;
  }

  void _showSent(UsdSendDestination destination, {String? detail}) {
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    navigator.pop();
    pushKuteSuccessOverlay(
      navigator: navigator,
      overlay: KuteSuccessOverlay(
        headlineLabel: l10n.confirmationSentToWallet(
            '${destination.displaySymbol} · ${destination.chainDisplayName}'),
        detail: detail,
      ),
    );
  }
}
