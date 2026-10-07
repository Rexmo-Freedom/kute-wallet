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
// The recipient field recognises what is pasted or scanned the way the
// bitcoin send does: a payment request is reduced to its bare address and
// the address picks the destination. The send starts on USDC · Arbitrum,
// so a bare EVM address lands there; an `ethereum:…@chainId` request
// picks the chain it names; a Tron or Solana address picks its own
// route; and an address several routes share with no default asks which
// network once it is in.
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
import 'package:kute/models/account.dart' show UsdcSpendingAccount;
import 'package:kute/models/orchestra_routes_model.dart'
    show OrchestraReceiveOption, OrchestraRoutesCatalog, RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
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

/// Page indices of the stepper, in the bitcoin send's order.
const int _kAmountStep = 0;
const int _kSendToStep = 1;
const int _kReviewStep = 2;

/// Full-screen dollar send. Push it on the root navigator.
class UsdSendScreen extends ConsumerStatefulWidget {
  const UsdSendScreen({super.key});

  @override
  ConsumerState<UsdSendScreen> createState() => _UsdSendScreenState();
}

class _UsdSendScreenState extends ConsumerState<UsdSendScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  final TextEditingController _address = TextEditingController();

  /// The "digit lands" bounce on each keystroke, as on the bitcoin send.
  late final AnimationController _amountPulse;

  int _step = _kAmountStep;
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

  /// The picked destination. Null until the recipient settles one or the
  /// person picks one, and the send cannot dispatch without it.
  UsdSendDestination? _destination;

  /// True when the destination was chosen in the sheet rather than read
  /// from the address.
  bool _destinationChosen = false;

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
      props: {'source': 'usd', 'source_asset': 'usd'},
    );
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
    return !_drain && units != null && units > _availableBaseUnits;
  }

  bool get _amountBelowMinimum {
    final units = _typedBaseUnits;
    return units != null && units > BigInt.zero && units < _minBaseUnits;
  }

  /// The amount step's gate.
  bool get _amountStepValid {
    final units = _typedBaseUnits;
    if (units == null) return false;
    return units >= _minBaseUnits && units <= _availableBaseUnits;
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
    return units >= _minBaseUnits && units <= _availableBaseUnits;
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

  /// Settles the destination from the field's text: the current one
  /// stays while the address still fits it; a recognised address that
  /// does not fit moves to the default (USDC · Arbitrum) when it fits
  /// that, else to what the address itself decides.
  void _settleDestination({String selection = 'address'}) {
    final catalog = ref.read(orchestraSupportedRoutesProvider);
    final offered = _offeredDestinations(catalog).offered;
    final match = _match(_address.text.trim(), offered: offered);
    final current = _destination;
    if (current != null && match.accepts(current)) return;
    if (!match.recognised) return;
    final fallback = usdSendDefaultDestination(offered);
    final next =
        fallback != null && match.accepts(fallback) ? fallback : match.autoPick;
    if (next?.id == current?.id) return;
    _destination = next;
    _destinationChosen = false;
    _estimateOut = null;
    _estimateError = null;
    if (next != null) _trackDestination(next, selection);
  }

  void _trackDestination(UsdSendDestination d, String selection) {
    TrackingService.track('usd_send_destination_selected', params: {
      'asset': d.assetCode,
      'chain': d.chain,
      'selection': selection,
    });
  }

  /// Paste, Scan, the clipboard nudge and a recent row all land here: a
  /// payment request is reduced to its bare address (an `ethereum:`
  /// request keeps the chain id it named), and the address decides the
  /// destination.
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
      _settleDestination(selection: method == 'recent' ? 'recent' : 'address');
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
      _settleDestination();
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

  /// Read the clipboard on arriving at Send to and keep it as a nudge
  /// when it holds a recipient this send can pay.
  Future<void> _checkClipboard() async {
    if (_address.text.isNotEmpty) return;
    try {
      if (!await Clipboard.hasStrings()) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty || raw.length > 2048) return;
      if (raw == _clipboardDismissed || raw == _clipboardCandidate) return;
      final catalog = ref.read(orchestraSupportedRoutesProvider);
      final match =
          matchUsdRecipient(raw, _offeredDestinations(catalog).offered);
      if (match.candidates.isEmpty) return;
      setState(() => _clipboardCandidate = raw);
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  /// Last few recipients this wallet sent dollars to, newest first, from
  /// the dollar send's own activity rows. Only rows whose destination is
  /// still offered are shown, so a tap always lands on a live route.
  List<
      ({
        String address,
        UsdSendDestination destination,
        String amount,
        DateTime when
      })> _recentRecipients(List<UsdSendDestination> offered) {
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
      if (destination == null) continue;
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
    // A catalog that lands after Amount still gets the default.
    ref.listen(orchestraSupportedRoutesProvider, (_, __) {
      if (_step == _kSendToStep) _applyDefaultDestination();
    });
    return PopScope(
      canPop: !_processing,
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
            // The wallet the dollars leave from, read-only, exactly as
            // the bitcoin send names its source.
            title: spending == null
                ? null
                : AccountSwitcherPill(
                    pickerTitle: context.l10n.sendFromPickerTitle,
                    account: UsdcSpendingAccount(spending),
                    readOnly: true,
                  ),
            leading: _step == _kAmountStep
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
            pages: [
              StepPageWrapper(
                title: context.l10n.amount,
                subtitle: context.l10n.usdSendAmountSubtitle,
                colors: c,
                child: _amountPage(c),
              ),
              StepPageWrapper(
                title: context.l10n.sendTo,
                subtitle: context.l10n.sendWhereShouldItLand,
                colors: c,
                child: _sendToPage(c),
              ),
              StepPageWrapper(
                title: context.l10n.sendReview,
                subtitle: context.l10n.sendConfirmTheDetails,
                trailing: const AskSalChip(
                  advisorContext: AdvisorContext(surface: 'send_review'),
                ),
                colors: c,
                child: _reviewPage(c),
              ),
            ],
            cta: SharedStepCta(
              step: _step,
              colors: c,
              visibleSteps: const {_kAmountStep, _kSendToStep},
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

  // ─── Step 1: Amount ───────────────────────────────────────────────

  Widget _amountPage(AppColorsExtension c) {
    final available = ref.watch(usdBalanceProvider);
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
    final drain = ratio >= 1;
    _amountMethod = drain ? 'max' : 'percent_${(ratio * 100).round()}';
    TrackingService.track('send_amount_percent_tapped', params: {
      'percent': (ratio * 100).round(),
      'source_asset': 'usd',
    });
    // Cents, floored: the keypad types two decimals, so the percentage
    // lands on one too rather than on a sub-cent amount it cannot show.
    final cents = (_availableUsd * ratio * 100).floor();
    setState(() {
      _error = null;
      _drain = drain;
      _drainUnits = null;
      _drainError = null;
      _typed = (cents / 100).toStringAsFixed(2);
    });
  }

  void _confirmAmount() {
    if (!_amountStepValid) return;
    _applyDefaultDestination();
    TrackingService.moneyFlowStep('usd_send', 'address', props: _flowInputs());
    _advanceTo(_kSendToStep, completed: _kAmountStep);
  }

  // ─── Step 2: Send to ──────────────────────────────────────────────

  /// Starts the send on USDC · Arbitrum when nothing is chosen yet and
  /// that route is offered; otherwise leaves the destination to the
  /// address, as before.
  void _applyDefaultDestination() {
    if (_destination != null || _address.text.trim().isNotEmpty) return;
    final catalog = ref.read(orchestraSupportedRoutesProvider);
    final fallback =
        usdSendDefaultDestination(_offeredDestinations(catalog).offered);
    if (fallback == null) return;
    setState(() {
      _destination = fallback;
      _destinationChosen = false;
    });
    _trackDestination(fallback, 'default');
  }

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

  Widget _sendToPage(AppColorsExtension c) {
    final l10n = context.l10n;
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final offered = _offeredDestinations(catalog);
    final addr = _address.text.trim();
    final match = _match(addr, offered: offered.offered);
    final destination = _destination;

    // What the field says about itself, in the bitcoin send's words.
    String? error;
    if (addr.isNotEmpty) {
      if (destination != null &&
          !usdSendDestinationAccepts(destination, addr, chainId: _chainId)) {
        error = match.recognised && match.candidates.isEmpty
            ? (offered.hiddenReason ?? l10n.usdSendAddressUnsupported)
            : l10n.usdSendAddressWrongNetwork(destination.chainDisplayName);
      } else if (destination == null && !match.recognised) {
        error = l10n.sendAddressNotIdentified;
      } else if (destination == null && match.candidates.isEmpty) {
        error = offered.hiddenReason ?? l10n.usdSendAddressUnsupported;
      }
    }
    final hint = destination != null && _destinationChosen
        ? l10n.sendAssetOnNetworkAddressHint(
            destination.displaySymbol, destination.chainDisplayName)
        : l10n.usdSendAddressHint;
    final recents = addr.isEmpty
        ? _recentRecipients(offered.offered)
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
          SendRecipientField(
            controller: _address,
            colors: c,
            hintText: hint,
            isValid: addr.isNotEmpty && error == null && match.recognised,
            onPaste: _paste,
            onScan: _scan,
            onChanged: _onAddressTyped,
          ),
          if (error != null) ...[
            SizedBox(height: 10.h),
            SendRecipientError(message: error),
          ] else if (addr.isNotEmpty && match.recognised) ...[
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
                    onTap: () => _pickRecent(r.address, r.destination),
                  ),
              ],
            ),
          ],
          SizedBox(height: 24.h),
          _destinationCard(c, offered.offered, match),
        ],
      ),
    );
  }

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

  void _pickRecent(String address, UsdSendDestination destination) {
    _commitRecipient(address, method: 'recent');
    if (_destination?.id != destination.id) {
      setState(() {
        _destination = destination;
        _destinationChosen = false;
      });
      _trackDestination(destination, 'recent');
    }
  }

  /// What the money arrives as, in one card: at rest a statement of the
  /// coins dollars can be sent as (tap to pick first, as on the bitcoin
  /// send); once an address needs a network, the question; once a
  /// destination is settled, that destination, still tappable.
  Widget _destinationCard(AppColorsExtension c,
      List<UsdSendDestination> offered, UsdRecipientMatch match) {
    final l10n = context.l10n;
    final addr = match.address;
    final destination = _destination;
    final needsPick =
        addr.isNotEmpty && destination == null && match.candidates.length > 1;
    // The sheet offers what the address can take, or everything while
    // the field is empty or unrecognised.
    final choices = addr.isNotEmpty && match.candidates.isNotEmpty
        ? match.candidates
        : offered;
    void open() => _openDestinationPicker(choices);

    if (destination == null && !needsPick) {
      final groups = groupCoinsByAsset([for (final d in choices) _asOption(d)]);
      if (groups.isEmpty) return const SizedBox.shrink();
      return SendToListCard(
        colors: c,
        rows: [
          CoinMarksLine(
            label: l10n.sendAlsoSendsTo,
            groups: groups,
            moreLabel: l10n.receiveAlsoAcceptsMore,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            onTap: open,
          ),
        ],
      );
    }
    return SendToListCard(
      colors: c,
      // Attention reads through the border weight and copy: while a
      // network is still needed this card is the only way forward.
      emphasized: needsPick,
      rows: [
        SendToListRow(
          colors: c,
          leading: destination != null
              ? _destinationMark(destination, size: 32)
              : Icon(Icons.swap_horiz_rounded,
                  color: c.textSecondary, size: 20.sp),
          title: destination != null
              ? '${destination.displaySymbol} · ${destination.chainDisplayName}'
              : l10n.sendWhichNetworkIsThisAddressOn,
          subtitle: destination == null
              ? l10n.sendTapToChoose
              : l10n.usdSendConvertedFromDollars,
          onTap: open,
        ),
      ],
    );
  }

  /// The coin sheet every money screen opens, asset first and network
  /// second, over [choices]. The picked row is matched back by
  /// `chain:assetCode`, the id the dollar table keys on.
  void _openDestinationPicker(List<UsdSendDestination> choices) {
    TrackingService.track('usd_send_coin_picker_opened');
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          return CoinAssetPickerSheet(
            otherLegAsset: kOrchestraUsdAssetCode,
            groups: groupCoinsByAsset([for (final d in choices) _asOption(d)]),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: ctx.l10n.usdSendPickCoin,
            emptyLabel: loading
                ? ctx.l10n.usdSendRoutesUnavailable
                : ctx.l10n.usdSendDestinationsUnavailable,
            flow: 'usd_send',
            selectedOptionId: _destination?.id,
            onPicked: (row) {
              final picked = choices
                  .where((d) => d.id == '${row.chain}:${row.assetCode}')
                  .firstOrNull;
              if (picked == null) return;
              Navigator.of(sheetCtx).pop();
              setState(() {
                _destination = picked;
                _destinationChosen = true;
                _estimateOut = null;
                _estimateError = null;
                _error = null;
              });
              _trackDestination(picked, 'picker');
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  void _confirmRecipient() {
    if (!_recipientReady) return;
    TrackingService.moneyFlowStep('usd_send', 'review', props: _flowInputs());
    _advanceTo(_kReviewStep, completed: _kSendToStep);
    if (_drain) {
      unawaited(_resolveDrain());
    } else {
      unawaited(_fetchEstimate());
    }
  }

  // ─── Step 3: Review ───────────────────────────────────────────────

  /// 100%, made exact: the dollar balance in the token's own base units,
  /// read from a freshly synced SDK, replacing the cent-floored figure the
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
    final available = ref.watch(usdBalanceProvider);
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
                        icon: SvgPicture.asset(kUsdMarkAsset,
                            width: 24.sp, height: 24.sp),
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
          label: _processing ? l10n.sendSendingEllipsis : l10n.send,
          loading: _processing,
          onPressed: canSend ? _confirmSend : null,
          footnote: waiting
              ? l10n.sendWaitForFee
              : l10n.sendFundsLeaveYourWalletImmediately,
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

  /// First tap on a later step goes back one page; on Amount it closes.
  void _onLeadingTap() {
    if (_processing) return;
    if (_step <= _kAmountStep) {
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
          amountBaseUnits > _availableBaseUnits;
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
          ..._flowInputs(),
        });

    // Outcome analytics: one `send_completed` / `send_failed` per send
    // that passed the gates above.
    final sendNetwork = destination.chain.toLowerCase();
    final sendAsset = destination.assetCode.toLowerCase();
    final walletKind = _walletKind();

    TrackingService.track('usd_send_initiated', params: {
      'asset': destination.assetCode,
      'chain': destination.chain,
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
