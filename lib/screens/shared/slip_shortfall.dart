// lib/screens/shared/slip_shortfall.dart
//
// Top up from the slip: what the bet slip and the order slip share. One
// balance (2026-10): a hot slip short of venue cash funds the order from
// Dollars itself (`OrderFundingController`). When the whole Investments
// balance cannot cover the move either, the slip's button reads "Add $X
// to Investments" and its tap decides on the spending bitcoin
// (`decideSlipFunding`, the same for both slips): the Bitcoin-funded chain
// when it covers X, run in place on the slip whether or not anything was
// typed (an empty slip takes the market's minimum first, never a sheet);
// otherwise [openSlipReceive], the Investments Receive sheet, since the
// money has to come from outside. Order and bet slips opt into a contextual
// venue deposit instead only when every source is confirmed empty.
// [openSlipTopUp] (the Dollars deposit
// door, prefilled with exactly what is missing: the order's top-up,
// [ShortfallRules.topUp], the route's fee counted, less the Dollars
// already held) stays for "Add more". The slip stays open underneath with
// everything the person typed. A hot slip's "Available"
// ([slipAvailableUsd]) is the whole spendable Investments, and its Max
// ([slipMaxFundableUsd]) the largest order its own funding check passes
// on it.
//
// While a deposit into that venue is on its way (an order's funding leg
// that has left Dollars, read from the persisted Orchestra rows the pool
// hero's arriving line reads), the button says "Deposit incoming" instead
// of offering a second one, and the slip re-reads the venue's cash until
// the money lands; the autofire places the queued order by itself.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/orchestra_router.dart'
    show doubleToOrchestraAmount, orchestraAmountToDouble;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/pending_pool_deposits_provider.dart'
    show isPendingBitcoinLeg, isPendingPoolDeposit;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/screens/shared/money_steps_view.dart'
    show MoneyStepsView, moneyStepLines;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/screens/receive/receive_sheet.dart'
    show showUsdReceiveSheet;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/empty_slip_sources.dart';
import 'package:kute/services/one_balance/money_steps.dart' show MoneyStepGraph;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The venue a slip funds.
enum SlipVenue {
  predictions('polymarket', 'POLYGON', MoveLockedSide.depositToPredictions),
  investing('hyperliquid', 'HYPERCORE', MoveLockedSide.depositToHyperliquid);

  const SlipVenue(this.code, this.network, this.lockedSide);

  /// Analytics value (`venue`).
  final String code;

  /// The settle network of a deposit into this venue on the swap rows.
  final String network;

  /// The Move sheet door into this venue.
  final MoveLockedSide lockedSide;

  /// The one-balance venue this slip funds.
  OneBalanceVenue get oneBalanceVenue => switch (this) {
        SlipVenue.predictions => OneBalanceVenue.predictions,
        SlipVenue.investing => OneBalanceVenue.investing,
      };
}

/// The spending balances a top-up can come from, in dollars, and the
/// app's bitcoin price. Read, never sent anywhere.
({double dollars, double bitcoinUsd, double usdPerBtc}) _spendingBalances(
    WidgetRef ref) {
  double dollars;
  try {
    dollars = ref.read(usdBalanceProvider);
  } catch (_) {
    dollars = 0;
  }
  var bitcoinUsd = 0.0;
  var rate = 0.0;
  try {
    rate = ref.read(selectedCurrencyProvider('USD')).toDouble();
    final spending = pickSpendingWallet(ref.read(settingsProvider));
    final sats = spending == null
        ? 0
        : ref
                .read(walletBalanceCacheProvider)[spending.id]
                ?.sparkBitcoinbalance ??
            0;
    if (sats > 0 && rate > 0) bitcoinUsd = sats / 1e8 * rate;
  } catch (_) {}
  return (dollars: dollars, bitcoinUsd: bitcoinUsd, usdPerBtc: rate);
}

/// The spending source that covers [topUpUsd] on its own, or null for the
/// Move sheet's default. Balances are read, never sent anywhere.
ShortfallSource? slipTopUpSource(WidgetRef ref, double topUpUsd) {
  final b = _spendingBalances(ref);
  return ShortfallRules.chooseSource(
      topUpUsd: topUpUsd, dollarsUsd: b.dollars, bitcoinUsd: b.bitcoinUsd);
}

/// What a deposit route keeps: the route's own share ([fee]) and Kute's
/// app fee taken from what remains ([kuteBps]).
typedef SlipRouteFee = ({double fee, int kuteBps});

/// The last route fee read per venue and source, so a second tap within a
/// few minutes does not wait on the network.
final Map<String, ({SlipRouteFee fee, DateTime at})> _routeFees = {};
const Duration _routeFeeMaxAge = Duration(minutes: 5);

/// The last Kute rate any estimate reported, for a route whose estimate
/// could not be read at all.
int _lastKuteBps = 0;

/// What one estimate says a deposit keeps, or null when it cannot say.
/// [arrivingUsd] is the estimate's raw output. The backend's `/estimate`
/// leaves the Kute fee out of it (`X-Kute-Estimate-Includes-App-Fee:
/// false`) while the deposit's quote takes it, so the rate the estimate
/// reports (`X-Kute-App-Fee-Bps`, the same the quote applies) is counted
/// on top; an estimate that already took it out counts it inside [fee].
/// An excluded fee at an unknown rate is not read as zero.
@visibleForTesting
SlipRouteFee? slipRouteFeeFrom(OrchestraEstimate est,
    {required double sentUsd, required double arrivingUsd}) {
  final fee =
      ShortfallRules.routeFeeFrom(sentUsd: sentUsd, arrivingUsd: arrivingUsd);
  if (fee == null) return null;
  if (est.estimateIncludesAppFee == true) return (fee: fee, kuteBps: 0);
  final bps = est.kuteAppFeeBps;
  if (bps == null || bps < 0 || bps >= 10000) return null;
  return (fee: fee, kuteBps: bps);
}

/// Test seam: stands in for the route-fee read (Orchestra's estimate).
/// An error it throws reaches the slip, as an unexpected failure would.
@visibleForTesting
Future<SlipRouteFee> Function(
        SlipVenue venue, ShortfallSource source, double amountUsd)?
    debugSlipRouteFee;

/// Test seam: stands in for the Dollars deposit door [openSlipTopUp]
/// opens, with the prefill it was given (what is missing from Dollars).
@visibleForTesting
Future<void> Function(SlipVenue venue, double? initialTargetUsd)?
    debugShowSlipTopUpSheet;

/// The share of a deposit of [amountUsd] the route from [source] into
/// [venue] keeps, Kute's fee included, from Orchestra's current estimate
/// for that amount. Falls back to the last estimate, then to
/// [ShortfallRules.fallbackRouteFee] with the last Kute rate seen. An
/// estimate is a read: nothing is quoted or moved.
///
/// [recipient] is the venue account the deposit lands in (the address its
/// quote names), so a HyperCore account Hyperliquid already knows is not
/// priced with the one-time activation. Part of the held estimate's key.
Future<SlipRouteFee> _slipRouteFee(SlipVenue venue, ShortfallSource source,
    double amountUsd, double usdPerBtc,
    {String? recipient}) async {
  final seam = debugSlipRouteFee;
  if (seam != null) return seam(venue, source, amountUsd);
  final to = OrchestraService.estimateRecipient(recipient);
  final key = '${venue.code}:${source.code}:${to ?? ''}';
  final held = _routeFees[key];
  try {
    final destinationChain =
        venue == SlipVenue.investing ? 'hypercore' : 'polygon';
    final destinationAsset =
        venue == SlipVenue.investing ? 'USDC' : 'USDC.e';
    final String amount;
    if (source == ShortfallSource.dollars) {
      amount = doubleToOrchestraAmount(amountUsd, kOrchestraUsdAssetCode,
          chain: kOrchestraUsdChain);
    } else {
      if (usdPerBtc <= 0) throw StateError('no bitcoin price');
      amount = (amountUsd / usdPerBtc * 1e8).ceil().toString();
    }
    final result = await OrchestraService.getEstimate(
      sourceChain: source == ShortfallSource.dollars ? kOrchestraUsdChain : 'spark',
      sourceAsset:
          source == ShortfallSource.dollars ? kOrchestraUsdAssetCode : 'BTC',
      destinationChain: destinationChain,
      destinationAsset: destinationAsset,
      amount: amount,
      recipientAddress: to,
    ).timeout(const Duration(seconds: 4));
    final est = result.data;
    final fee = est == null
        ? null
        : slipRouteFeeFrom(est,
            sentUsd: amountUsd,
            arrivingUsd: orchestraAmountToDouble(
                est.estimatedOut, destinationAsset,
                chain: destinationChain));
    if (est != null && est.estimateIncludesAppFee != true && fee != null) {
      _lastKuteBps = fee.kuteBps;
    }
    if (fee != null) {
      _routeFees[key] = (fee: fee, at: DateTime.now());
      return fee;
    }
  } catch (_) {}
  if (held != null && DateTime.now().difference(held.at) < _routeFeeMaxAge) {
    return held.fee;
  }
  return (fee: ShortfallRules.fallbackRouteFee, kuteBps: _lastKuteBps);
}

/// The venue account a deposit into [venue] lands in, as already resolved
/// (never awaited): the Investing account's own EVM address, the
/// Predictions deposit wallet. Null while unknown. Only ever the estimate's
/// recipient; never sent to analytics or logged.
String? _slipVenueRecipient(WidgetRef ref, SlipVenue venue) {
  try {
    return switch (venue) {
      SlipVenue.investing => ref.read(hyperliquidAddressProvider).valueOrNull,
      SlipVenue.predictions =>
        ref.read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress,
    };
  } catch (_) {
    return null;
  }
}

/// One top-up sheet at a time: a second tap while the route fee is read
/// opens nothing.
bool _topUpOpening = false;

/// What the Dollars door is prefilled with for a slip short of venue
/// cash: the order's top-up ([topUpUsd], the move the order would make,
/// the route's fee counted) less the Dollars held, up to the cent, or
/// zero when Dollars already cover the move. Pure.
double slipDollarsShortfallUsd({
  required double topUpUsd,
  required double dollarsUsd,
}) {
  if (!topUpUsd.isFinite || topUpUsd <= 0) return 0;
  final held = dollarsUsd.isFinite && dollarsUsd > 0 ? dollarsUsd : 0.0;
  final missing = topUpUsd - held;
  if (missing <= 1e-6) return 0;
  return ((missing * 100) - 1e-9).ceilToDouble() / 100;
}

/// Opens the Dollars deposit door for a slip whose Dollars cannot cover
/// the move its order needs. The prefill is what is missing from Dollars:
/// the order's top-up (its own amount [orderUsd], or that plus exactly
/// the fees still missing so the money that arrives at [venue] covers
/// [requiredUsd] with [readyUsd], [ShortfallRules.topUp]) less the
/// Dollars held; with [incomingUsd] ("Add more" under "Deposit incoming")
/// the top-up is the rest of [shortfallUsd] instead. Both count the
/// Dollars route's own fee and the Kute fee the move's quote takes.
/// [topUpUsd] passes a top-up already worked out (the slip's funding
/// plan) so nothing is read again. Without an order (nothing typed yet)
/// it keeps [fallbackTargetUsd], as the door always did. [onReturned]
/// runs once the deposit went through and the person is back on the
/// still-open slip. [onSheetOpening] runs once the prefill is worked
/// out, right before the door opens: the slip's button stops showing its
/// calculation there.
///
/// No events of its own: the Dollars door and the order's funding report
/// themselves.
Future<void> openSlipTopUp(
  BuildContext context,
  WidgetRef ref, {
  required SlipVenue venue,
  required double shortfallUsd,
  required double orderUsd,
  double requiredUsd = 0,
  double readyUsd = 0,
  double? incomingUsd,
  double? topUpUsd,
  double? fallbackTargetUsd,
  required VoidCallback onReturned,
  VoidCallback? onSheetOpening,
}) async {
  if (_topUpOpening) return;
  _topUpOpening = true;
  double amount;
  try {
    amount = await _dollarsDoorPrefill(ref,
        venue: venue,
        shortfallUsd: shortfallUsd,
        orderUsd: orderUsd,
        requiredUsd: requiredUsd,
        readyUsd: readyUsd,
        incomingUsd: incomingUsd,
        topUpUsd: topUpUsd,
        fallbackTargetUsd: fallbackTargetUsd);
  } finally {
    _topUpOpening = false;
  }
  if (!context.mounted) return;
  onSheetOpening?.call();
  final sheetSeam = debugShowSlipTopUpSheet;
  if (sheetSeam != null) {
    await sheetSeam(venue, amount > 0 ? amount : null);
    return;
  }
  await showDepositSheet(
    context,
    lockedSide: MoveLockedSide.depositToUsd,
    initialTargetUsd: amount > 0 ? amount : null,
    onCompleted: () {
      if (!context.mounted) return;
      onReturned();
    },
  );
}

/// [openSlipTopUp]'s prefill: the order's top-up (or [topUpUsd]) less
/// the Dollars held.
Future<double> _dollarsDoorPrefill(
  WidgetRef ref, {
  required SlipVenue venue,
  required double shortfallUsd,
  required double orderUsd,
  required double requiredUsd,
  required double readyUsd,
  required double? incomingUsd,
  required double? topUpUsd,
  required double? fallbackTargetUsd,
}) async {
  final balances = _spendingBalances(ref);
  var top = topUpUsd ?? 0.0;
  if (top <= 0) {
    // What the route is asked about: the order (or the rest) itself.
    final base = incomingUsd != null
        ? math.max(shortfallUsd - incomingUsd, ShortfallRules.minTopUpUsd)
        : orderUsd;
    if (base > 0) {
      final route = await _slipRouteFee(
          venue, ShortfallSource.dollars, base, balances.usdPerBtc,
          recipient: _slipVenueRecipient(ref, venue));
      top = incomingUsd != null
          ? ShortfallRules.remainingTopUpUsd(
              shortfallUsd: shortfallUsd,
              incomingUsd: incomingUsd,
              routeFee: route.fee,
              kuteFeeBps: route.kuteBps)
          : ShortfallRules.topUpUsd(
              orderUsd: orderUsd,
              requiredUsd: requiredUsd,
              readyUsd: readyUsd,
              routeFee: route.fee,
              kuteFeeBps: route.kuteBps);
    }
  }
  if (top <= 0) top = fallbackTargetUsd ?? 0;
  return slipDollarsShortfallUsd(topUpUsd: top, dollarsUsd: balances.dollars);
}

/// What a hot slip's "Available" reads: its own venue's free cash
/// ([venueUsd]) plus what the rest of Investments can bring
/// ([otherSpendableUsd], `investmentsSpendableExcludingProvider`), floored
/// to the cent. The whole spendable Investments, never the venue alone.
/// Pure.
double slipAvailableUsd({
  required double venueUsd,
  required double otherSpendableUsd,
}) {
  final venue = venueUsd.isFinite && venueUsd > 0 ? venueUsd : 0.0;
  final other =
      otherSpendableUsd.isFinite && otherSpendableUsd > 0 ? otherSpendableUsd : 0.0;
  return ((venue + other) * 100 + 1e-6).floorToDouble() / 100;
}

/// Headroom a slip's Max keeps on the move it would need: the move's cost
/// is an estimate until the route is asked for that exact amount, and Max
/// must stay an order the rest of Investments can fund once it is.
const double kSlipMaxMoveHeadroom = 0.01;

/// The largest amount, to the cent, in `[0, upperUsd]` that [fits]: the
/// slip's own funding check (venue cash, else a move the rest of
/// Investments covers). [fits] must be monotone (true up to a point,
/// false after). Zero when nothing fits. Pure.
double slipMaxFundableUsd({
  required double upperUsd,
  required bool Function(double amountUsd) fits,
}) {
  if (!upperUsd.isFinite || upperUsd <= 0) return 0;
  var hi = (upperUsd * 100 + 1e-6).floor();
  if (fits(hi / 100)) return hi / 100;
  var lo = 0;
  // lo fits (0 always does), hi does not.
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (fits(mid / 100)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo / 100;
}

/// Test seam: stands in for the Investments Receive sheet [openSlipReceive]
/// opens, with the X the slip's button named.
@visibleForTesting
Future<void> Function(SlipVenue venue, double addUsd)? debugShowSlipReceiveSheet;

@visibleForTesting
Future<void> Function(SlipVenue venue, double targetUsd)?
    debugShowEmptySlipDepositSheet;

/// The "Add $X to Investments" tap whose X the spending bitcoin cannot
/// cover (none, or too little once the route's spread is counted): the
/// money has to come from outside, so this is the Investments Receive
/// sheet, the one the Investments dock's Receive opens, never the Bitcoin
/// Move sheet. The sheet takes no amount ([addUsd] is for the seam and the
/// event only); the slip stays open underneath with everything typed.
/// Order/bet callers may opt into [depositWhenKnownEmpty]: a confirmed empty
/// wallet opens the existing deposit pinned to this venue and target. It
/// queues no order; another user approval is required after funding.
///
/// Sends `slip_top_up_opened` once, here, for every caller (the Investing
/// ticket, the Predictions slip, the margin sheet): [venue]'s code, the
/// exact [shortfallUsd] the venue's cash lacks and the [addUsd] the button
/// named (with their legacy buckets), `prefill_rule:
/// investments_shortfall`, `suggested_source: receive`, and
/// [entrySource] when the caller is not a slip (`add_margin`).
Future<void> openSlipReceive(
  BuildContext context, {
  required SlipVenue venue,
  required double addUsd,
  required double shortfallUsd,
  String? entrySource,
  bool depositWhenKnownEmpty = false,
  VoidCallback? onDepositCompleted,
}) async {
  if (!context.mounted) return;
  if (depositWhenKnownEmpty) {
    final empty = await ProviderScope.containerOf(context, listen: false)
        .read(slipKnownEmptySourcesProvider)();
    if (!context.mounted) return;
    if (empty) {
      TrackingService.track('slip_top_up_opened', params: {
        'venue': venue.code,
        ...TrackingService.exactUsd('shortfall_usd', shortfallUsd),
        ...TrackingService.exactUsd('top_up_usd', addUsd),
        'prefill_rule': 'empty_wallet',
        'suggested_source': 'deposit',
      });
      final seam = debugShowEmptySlipDepositSheet;
      if (seam != null) {
        await seam(venue, addUsd);
      } else {
        await showDepositSheet(context,
            lockedSide: venue.lockedSide,
            initialTargetUsd: addUsd > 0 ? addUsd : null,
            onCompleted: onDepositCompleted);
      }
      return;
    }
  }
  TrackingService.track('slip_top_up_opened', params: {
    'venue': venue.code,
    if (entrySource != null) 'entry_source': entrySource,
    'shortfall_bucket': TrackingService.usdBucket(shortfallUsd),
    ...TrackingService.exactUsd('shortfall_usd', shortfallUsd),
    'top_up_bucket': TrackingService.usdBucket(addUsd),
    ...TrackingService.exactUsd('top_up_usd', addUsd),
    'prefill_rule': 'investments_shortfall',
    'suggested_source': 'receive',
  });
  final seam = debugShowSlipReceiveSheet;
  if (seam != null) {
    await seam(venue, addUsd);
    return;
  }
  await showUsdReceiveSheet(context);
}

/// What a short hot slip shows for its funding, read by [SlipIncomingDeposit].
class SlipFunding {
  const SlipFunding({
    required this.state,
    required this.incomingUsd,
    required this.failed,
  });

  final SlipFundingState state;

  /// The venue deposit on its way for this wallet (the Orchestra estimate).
  final double incomingUsd;

  /// A deposit this slip watched did not go through: the deposit button is
  /// back, with a short note above it.
  final bool failed;

  bool get isIncoming => state != SlipFundingState.deposit;
}

/// The "Deposit incoming" state both hot slips share. Call [slipFunding]
/// from build while the slip is short of venue cash (it watches the
/// persisted swap rows, so it holds across restarts and deposits started
/// anywhere), and [slipFundingCovered] while it is not.
///
/// Orders that leave the pending set are followed for this slip's life: a
/// completed one keeps "Deposit incoming" for a short grace while the
/// venue's balance catches up (so the deposit button never flashes back
/// in between), a failed or cancelled one brings the deposit button back
/// with [SlipFunding.failed].
mixin SlipIncomingDeposit<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// The venue this slip funds.
  SlipVenue get slipVenue;

  /// Re-read the venue's cash (the slip's own balance provider).
  void refreshSlipVenueCash();

  /// How long a landed deposit still reads as incoming while the venue's
  /// balance catches up (Predictions wraps the arriving USDC.e first).
  static const Duration landingGrace = Duration(minutes: 3);

  static const Duration _pollEvery = Duration(seconds: 5);

  final Map<String, double> _incomingSeen = {};
  double _landedUsd = 0;
  DateTime? _landedAt;
  bool _incomingFailed = false;
  Timer? _incomingPoll;

  /// The short slip's funding. Watches the swap rows; starts or stops the
  /// venue-cash poll to match.
  SlipFunding slipFunding({required double shortfallUsd}) {
    final orders = ref.watch(swapOrdersProvider);
    final walletId =
        ref.watch(settingsProvider.select((s) => s.activeWalletId));
    final funded = ref.watch(fundedOrdersProvider);
    final now = DateTime.now();
    final pending = <String, double>{};
    for (final e in orders) {
      final nowMs = now.millisecondsSinceEpoch;
      // A Bitcoin → Dollars leg a slip on this venue started for its
      // order (kept across restarts) is this venue's deposit on its way.
      final ownBitcoinLeg =
          isPendingBitcoinLeg(e, walletId: walletId, nowMs: nowMs) &&
              FundedOrdersNotifier.btcRowVenue(funded, e.id) ==
                  slipVenue.oneBalanceVenue;
      if (!ownBitcoinLeg &&
          !isPendingPoolDeposit(e,
              network: slipVenue.network, walletId: walletId, nowMs: nowMs)) {
        continue;
      }
      // An unpaid Cash App invoice is not money on its way.
      if (e.isCashAppPurchase && kCashAppUnpaidStatuses.contains(e.status)) {
        continue;
      }
      pending[e.id] = double.tryParse(e.withdrawalAmount) ?? 0;
    }
    _followLeftOrders(orders, pending, now);
    _incomingSeen
      ..clear()
      ..addAll(pending);
    if (pending.isNotEmpty) _incomingFailed = false;
    final landing = _landedAt != null && now.difference(_landedAt!) < landingGrace
        ? _landedUsd
        : 0.0;
    if (landing == 0) {
      _landedAt = null;
      _landedUsd = 0;
    }
    final incoming =
        pending.values.fold<double>(0, (sum, usd) => sum + usd) + landing;
    final state = ShortfallRules.fundingState(
        shortfallUsd: shortfallUsd, incomingUsd: incoming);
    final funding = SlipFunding(
      state: state,
      incomingUsd: incoming,
      failed: state == SlipFundingState.deposit && _incomingFailed,
    );
    _pollWhile(funding.isIncoming);
    return funding;
  }

  /// The slip is not short (the money landed, or the order shrank): drop
  /// what this slip was following and stop polling.
  void slipFundingCovered() {
    _incomingSeen.clear();
    _landedAt = null;
    _landedUsd = 0;
    _incomingFailed = false;
    _pollWhile(false);
  }

  /// Back on the slip after a deposit started from it: start reading.
  void slipTopUpReturned() {
    _incomingFailed = false;
    refreshSlipVenueCash();
    if (mounted) setState(() {});
  }

  void _followLeftOrders(
      List<SwapOrder> orders, Map<String, double> pending, DateTime now) {
    final byId = {for (final e in orders) e.id: e};
    var deleted = false;
    for (final seen in _incomingSeen.entries) {
      final id = seen.key;
      final usd = seen.value;
      if (pending.containsKey(id)) continue;
      final row = byId[id];
      if (row == null) {
        // A quote row gives way to its order row, or a deposit stopped
        // before any money left. Only the second is a failure.
        deleted = true;
      } else if (row.isComplete) {
        _landedUsd += usd;
        _landedAt = now;
      } else if (!row.isPending) {
        _incomingFailed = true;
      }
      // Still pending but past the age cap: it simply stops reading as
      // incoming, as on the pool hero.
    }
    if (deleted && pending.isEmpty && _landedAt == null) _incomingFailed = true;
  }

  void _pollWhile(bool on) {
    if (!on) {
      _incomingPoll?.cancel();
      _incomingPoll = null;
      return;
    }
    if (_incomingPoll != null) return;
    _incomingPoll = Timer.periodic(_pollEvery, (_) {
      if (!mounted) return;
      refreshSlipVenueCash();
      // Re-reads the landing grace too.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _incomingPoll?.cancel();
    _incomingPoll = null;
    super.dispose();
  }
}

/// The small lines under a "Deposit incoming" button: what is happening,
/// and "Add more" when the deposit on its way falls short.
class SlipIncomingDepositNote extends StatelessWidget {
  const SlipIncomingDepositNote({super.key, this.onAddMore});

  final VoidCallback? onAddMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A small working sign so the wait reads as something
              // happening; a still dot under Reduce Motion.
              Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: SizedBox.square(
                  key: const ValueKey('slip-deposit-incoming-working'),
                  dimension: 12.r,
                  child: kuteReduceMotion(context)
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                              color: c.textSecondary, shape: BoxShape.circle))
                      : CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: c.textSecondary,
                        ),
                ),
              ),
              Flexible(
                child: Text(
                  context.l10n.slipDepositIncomingNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.textSecondary, fontSize: 13.sp, height: 1.35),
                ),
              ),
            ],
          ),
          if (onAddMore != null)
            TextButton(
              key: const ValueKey('slip-deposit-add-more'),
              onPressed: onAddMore,
              style: TextButton.styleFrom(
                foregroundColor: c.textPrimary,
                minimumSize: Size(0, 36.h),
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                context.l10n.slipDepositAddMore,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// The plain line above the deposit button after a watched deposit did not
/// go through.
class SlipDepositFailedNote extends StatelessWidget {
  const SlipDepositFailedNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 8.h),
        child: Text(
          context.l10n.slipDepositFailedNote,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13.sp,
              height: 1.35),
        ),
      );
}

/// The staged progress of an order funded through Investments (founder
/// decision 14 October 2026): each step a line under the slip's one
/// button, a check once done, the small working sign the "Deposit
/// incoming" note uses while active, the rest waiting in a quieter tone.
/// No new chrome: the note's own type, colours and spinner.
///
/// A funding that stopped ([failed]) marks the step it stopped at with
/// the slips' error sign (the notice's `error_outline`) and says, in
/// [note], what happened and where the money is now.
class SlipFundingSteps extends StatelessWidget {
  const SlipFundingSteps({
    super.key,
    required this.steps,
    required this.active,
    this.slow = false,
    this.failed = false,
    this.note,
    this.graph,
    this.money,
  });

  /// The steps, in order.
  final List<String> steps;

  /// The order's step graph (`FundedOrderRecord.steps`): when it has
  /// steps, every leg shows on its own line with its own state, the
  /// readiness sub-steps indented under [steps]' second-to-last line, and
  /// [steps]' last line is the order (`MoneyStepsView`). [money] formats
  /// the legs' dollars the slip's way.
  final MoneyStepGraph? graph;
  final String Function(double usd)? money;

  /// The step running now (or the one that failed); the ones before it
  /// are done. [steps]'s length: every step done.
  final int active;

  /// The first step is taking longer than usual.
  final bool slow;

  /// The [active] step failed: nothing after it runs.
  final bool failed;

  /// One plain line under the steps: what happened and where the money
  /// is ("Price moved too fast. Your $5 is in Predictions. Tap to try
  /// again.").
  final String? note;

  @override
  Widget build(BuildContext context) {
    final g = graph;
    final format = money;
    if (g != null && !g.isEmpty && format != null && steps.length >= 2) {
      return MoneyStepsView(
        lines: moneyStepLines(context.l10n, g, format,
            readyLabel: steps[steps.length - 2], placeLine: steps.last),
        slow: slow,
        note: note,
      );
    }
    final c = context.colors;
    final still = kuteReduceMotion(context);
    Widget lead(int i) {
      if (failed && i == active) {
        return Icon(Icons.error_outline_rounded,
            key: ValueKey('slip-funding-step-failed-$i'),
            size: 14.r,
            color: c.textPrimary);
      }
      if (i < active) {
        return Icon(Icons.check_rounded,
            key: ValueKey('slip-funding-step-done-$i'),
            size: 14.r,
            color: c.textSecondary);
      }
      if (i == active) {
        return SizedBox.square(
          key: ValueKey('slip-funding-step-active-$i'),
          dimension: 12.r,
          child: still
              ? DecoratedBox(
                  decoration: BoxDecoration(
                      color: c.textSecondary, shape: BoxShape.circle))
              : CircularProgressIndicator(
                  strokeWidth: 1.6, color: c.textSecondary),
        );
      }
      return SizedBox.square(dimension: 12.r);
    }

    return Padding(
      key: const ValueKey('slip-funding-steps'),
      padding: EdgeInsets.only(top: 10.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              key: ValueKey('slip-funding-step-$i'),
              padding: EdgeInsets.symmetric(vertical: 3.h),
              child: Row(
                children: [
                  SizedBox(
                    width: 22.w,
                    child: Align(
                        alignment: Alignment.centerLeft, child: lead(i)),
                  ),
                  Flexible(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        color: failed && i == active
                            ? c.textPrimary
                            : i <= active
                                ? c.textSecondary
                                : c.textTertiary,
                        fontSize: 13.sp,
                        height: 1.35,
                        fontWeight:
                            i == active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (slow && !failed)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 22.w),
              child: Text(
                context.l10n.slipStepTakingLonger,
                key: const ValueKey('slip-funding-slow'),
                style: TextStyle(
                    color: c.textTertiary, fontSize: 12.sp, height: 1.35),
              ),
            ),
          if (note case final line?)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                line,
                key: const ValueKey('slip-funding-note'),
                style: TextStyle(
                    color: c.textSecondary, fontSize: 13.sp, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

/// What a slip says under a stopped funded order's steps: what happened,
/// then where the money is now, in [money]'s format. Funds that reached
/// the venue stay there as its cash (available); funds still in Dollars
/// are in Investments.
String fundedStopLine(
    AppLocalizations l10n, FundedOrderRecord r, String Function(double) money) {
  final venue = r.label.venue;
  // The rail's or the venue's own words already say it all.
  switch (r.reason) {
    case 'refunded':
    case 'maybe_sent':
    case 'not_sent':
      return r.message ?? l10n.betActionNotCompleted;
    case 'funds_timeout' || 'book_unavailable'
        when venue == OneBalanceVenue.predictions && r.message != null:
      return r.message!;
    // A 5-minute round that ended while the money was moving, the money
    // now Predictions cash: the whole line, no "tap to try again".
    case 'round_ended'
        when venue == OneBalanceVenue.predictions &&
            r.moneyAt == FundedMoneyAt.venue:
      return l10n.slipFundingRoundEnded(money(r.label.orderUsd));
  }
  final what = switch (r.reason) {
    'price_moved' => l10n.slipFundingPriceMoved,
    'market_closed' || 'round_ended' => l10n.slipFundingRoundClosed,
    // A 5-minute round: "Price changed to 81% while your money was moving."
    'round_price_moved' => r.message ?? l10n.slipFundingPriceMoved,
    _ => r.message,
  };
  final where = switch (r.moneyAt) {
    FundedMoneyAt.venue => venue == OneBalanceVenue.predictions
        ? l10n.slipFundingInPredictions(money(r.label.orderUsd))
        : l10n.slipFundingInInvesting(money(r.label.orderUsd)),
    FundedMoneyAt.investments => l10n.slipFundingReadyToPlace(
        money(r.fromBitcoin && r.addUsd > 0 ? r.addUsd : r.label.orderUsd)),
    FundedMoneyAt.bitcoin || null => null,
  };
  return [if (what != null) what, if (where != null) where].join(' ');
}

/// The plain line above a slip's button when its funding stopped with the
/// money in Investments and the order not placed: "Your $X is in
/// Investments. Tap to place." Same type as [SlipDepositFailedNote]. The
/// margin sheet passes its own line ([text]: "Tap to add margin").
class SlipFundingReadyNote extends StatelessWidget {
  const SlipFundingReadyNote({super.key, required this.amount, this.text});

  /// The formatted amount that landed.
  final String amount;

  /// The line itself, when it is not the slips' "Tap to place".
  final String? text;

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('slip-funding-ready'),
        padding: EdgeInsets.only(bottom: 8.h),
        child: Text(
          text ?? context.l10n.slipFundingReadyToPlace(amount),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13.sp,
              height: 1.35),
        ),
      );
}
