// lib/screens/shared/slip_shortfall.dart
//
// Top up from the slip: what the bet slip and the order slip share. One
// balance (2026-10): a hot slip short of venue cash funds the order from
// Dollars itself (`OrderFundingController`), so the only door here is the
// Dollars one. When Dollars cannot cover the move either, the slip's
// button reads "Add $X to Investments" and [openSlipTopUp] opens the
// Dollars deposit door prefilled with exactly what is missing: the
// order's top-up ([ShortfallRules.topUp], the route's fee counted) less
// the Dollars already held. The slip stays open underneath with
// everything the person typed; once the deposit goes through they are
// back on it and place the order (which then funds itself).
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
import 'package:kute/providers/pending_pool_deposits_provider.dart'
    show isPendingPoolDeposit;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show showDepositSheet, MoveLockedSide;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
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
Future<SlipRouteFee> _slipRouteFee(SlipVenue venue, ShortfallSource source,
    double amountUsd, double usdPerBtc) async {
  final seam = debugSlipRouteFee;
  if (seam != null) return seam(venue, source, amountUsd);
  final key = '${venue.code}:${source.code}';
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
    final balances = _spendingBalances(ref);
    var top = topUpUsd ?? 0.0;
    if (top <= 0) {
      // What the route is asked about: the order (or the rest) itself.
      final base = incomingUsd != null
          ? math.max(shortfallUsd - incomingUsd, ShortfallRules.minTopUpUsd)
          : orderUsd;
      if (base > 0) {
        final route = await _slipRouteFee(
            venue, ShortfallSource.dollars, base, balances.usdPerBtc);
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
    amount =
        slipDollarsShortfallUsd(topUpUsd: top, dollarsUsd: balances.dollars);
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
    final now = DateTime.now();
    final pending = <String, double>{};
    for (final e in orders) {
      if (!isPendingPoolDeposit(e,
          network: slipVenue.network,
          walletId: walletId,
          nowMs: now.millisecondsSinceEpoch)) {
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
