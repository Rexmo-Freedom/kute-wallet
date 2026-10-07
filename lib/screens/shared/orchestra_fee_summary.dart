import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;

typedef FeeRoute = ({
  String fromChain,
  String fromAsset,
  String toChain,
  String toAsset,
  String amount
});
final orchestraFeeEstimateProvider = FutureProvider.autoDispose
    .family<OrchestraEstimate, FeeRoute>(
        (ref, route) => _loadFeeEstimate(ref, route, onramp: false));

/// The estimate for a route a Cash App onramp order will run. The backend
/// prices an onramp at its own rule (not the quote's), so the Kute fee and
/// what arrives are asked for under that rule.
final orchestraOnrampFeeEstimateProvider = FutureProvider.autoDispose
    .family<OrchestraEstimate, FeeRoute>(
        (ref, route) => _loadFeeEstimate(ref, route, onramp: true));

Future<OrchestraEstimate> _loadFeeEstimate(Ref ref, FeeRoute route,
    {required bool onramp}) async {
  var active = true;
  ref.onDispose(() => active = false);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (!active) {
    throw StateError('Amount changed');
  }
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final result = await OrchestraService.getEstimate(
          sourceChain: route.fromChain,
          sourceAsset: route.fromAsset,
          destinationChain: route.toChain,
          destinationAsset: route.toAsset,
          amount: route.amount,
          onramp: onramp)
      .timeout(const Duration(seconds: 10));
  if (result.data == null) {
    throw StateError('Fee unavailable');
  }
  return result.data!;
}

// NO "this amount is too small" WARNING LIVES HERE.
//
// There was one: it applied the quote gate's own floor to the estimate,
// so the block could say an amount would lose too much to fees while the
// person was still typing. It was wrong. The gate decides on the QUOTE,
// against a locked figure and a reference the quote carries; this block
// has an estimate and a locally derived net, and the two do not agree
// closely enough to refuse anything. On the Investing deposit it warned
// about every amount on a route that works.
//
// Estimating is not the same as deciding. The gate refuses, in its own
// words, at the moment there is something real to refuse, and that is
// the only place the claim can be made honestly.

/// One block for a conversion estimate: the total fees on the amount sent,
/// with the provider and Kute parts on demand, then what arrives net of every
/// fee. The last good estimate stays on screen through the 30 s refresh and
/// through a refresh that failed; "Calculating…" shows only for a first load
/// or a new amount.
class OrchestraFeeSummary extends ConsumerWidget {
  const OrchestraFeeSummary(
      {super.key,
      required this.route,
      this.bitcoinFirst,
      this.sourceFeeUsd = 0,
      this.sourceFeeIsMaximum = false,
      this.onramp = false,
      this.showReceive = false});
  final FeeRoute route;

  /// The route runs as a Cash App onramp order: estimated at the rule that
  /// order is charged, not the quote's.
  final bool onramp;

  /// Ends the breakdown with "You receive": what arrives net of every fee
  /// ([orchestraNetReceiveAmount]), from the same estimate as the rows
  /// above it.
  final bool showReceive;
  final double sourceFeeUsd;
  final bool sourceFeeIsMaximum;

  /// Unit of the fee rows: the unit the amount is entered in. Null follows the
  /// wallet's main denomination.
  final bool? bitcoinFirst;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = double.tryParse(route.amount);
    if (amount == null || !amount.isFinite || amount <= 0) {
      return const MoneyFeeSummary(label: 'Fees', state: 'Enter an amount');
    }
    final source = onramp
        ? orchestraOnrampFeeEstimateProvider(route)
        : orchestraFeeEstimateProvider(route);
    final estimate = ref.watch(source);
    void retry() => ref.invalidate(source);
    // A refresh in flight and a refresh that failed both keep the previous
    // estimate; the provider's own timer already retries a failure.
    final quote = estimate.valueOrNull;
    if (quote == null) {
      return estimate.hasError
          ? MoneyFeeSummary(
              label: 'Fees', state: 'Estimate unavailable', onRetry: retry)
          : const MoneyFeeSummary(label: 'Fees', state: 'Calculating…');
    }
    return _OrchestraEstimateBlock(
        quote: quote,
        route: route,
        sourceFeeUsd: sourceFeeUsd,
        sourceFeeIsMaximum: sourceFeeIsMaximum,
        bitcoinFirst: bitcoinFirst,
        showReceive: showReceive,
        stale: estimate.hasError,
        retry: retry);
  }
}

class _OrchestraEstimateBlock extends ConsumerWidget {
  const _OrchestraEstimateBlock(
      {required this.quote,
      required this.route,
      required this.sourceFeeUsd,
      required this.sourceFeeIsMaximum,
      required this.bitcoinFirst,
      required this.showReceive,
      required this.stale,
      required this.retry});
  final OrchestraEstimate quote;
  final FeeRoute route;
  final double sourceFeeUsd;
  final bool sourceFeeIsMaximum;
  final bool? bitcoinFirst;
  final bool showReceive;
  final bool stale;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usdPerBtc = feeUsdPerBtc(ref);
    final provider = orchestraFeeAmount(quote);
    final kute = orchestraKuteFeeAmount(quote,
        destinationChain: route.toChain, destinationAsset: route.toAsset);
    final included = quote.estimateIncludesAppFee == true;
    // The provider's figure already holds the Kute share when included;
    // otherwise the Kute fee is added to it.
    final quoted = included
        ? provider
        : orchestraFeeSum(provider, kute, usdPerBtc: usdPerBtc);
    final providerPart = included
        ? orchestraFeeDifference(provider, kute, usdPerBtc: usdPerBtc)
        : provider;
    final input = _inputInDestinationUnits(route, usdPerBtc: usdPerBtc);
    // What the transfer really costs: everything that does not arrive.
    // The quoted fees cover the provider's own rate and ours; the route's
    // own costs live inside the output and are invisible in them, so the
    // headline is the amount sent less the amount received and the two
    // rows always reconcile with the figure above.
    final cost = orchestraTotalCostAmount(quote,
        destinationChain: route.toChain,
        destinationAsset: route.toAsset,
        inputValueInDestinationUnits: input);
    // The headline is the WHOLE cost or it is nothing. It used to fall
    // back to the declared fees when the cost could not be worked out,
    // and on the Investing routes that fallback is not a rounding
    // difference: a ten dollar deposit into HyperCore declares about two
    // cents and actually costs about a dollar twenty, because the
    // route's fixed bridging cost lives inside `estimatedOut` and
    // appears in no fee field. Showing two cents there is worse than
    // showing nothing, so when the arithmetic is unavailable the block
    // says the figure comes before confirming rather than quoting a
    // number that is wrong by fifty times.
    final total = sourceFeeUsd > 0 && cost.isAvailable
        ? orchestraFeeSum(cost, OrchestraFeeAmount(usd: sourceFeeUsd),
            usdPerBtc: usdPerBtc)
        : cost;
    // Whatever the quoted fees do not explain is the route's own cost.
    final routePart = cost.isAvailable
        ? orchestraFeeDifference(cost, quoted, usdPerBtc: usdPerBtc)
        : const OrchestraFeeAmount();
    final received = showReceive
        ? orchestraNetReceiveAmount(quote,
            destinationChain: route.toChain, destinationAsset: route.toAsset)
        : const OrchestraFeeAmount();
    final rate = orchestraKuteFeeRate(quote);
    final kuteLabel = rate == null
        ? 'Kute fee'
        : context.l10n.feeUiKuteFeeWithRate(feeRateText(quote.kuteAppFeeBps!));
    final String? totalState;
    if (total.isAvailable) {
      totalState = null;
    } else if (!provider.isAvailable) {
      totalState = 'Estimate unavailable';
    } else {
      totalState = 'Shown before you confirm';
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyFeeSummary(
            label: sourceFeeIsMaximum ? 'Estimated fees' : 'Fees',
            usd: total.usd,
            sats: total.sats,
            bitcoinFirst: bitcoinFirst,
            state: totalState,
            onRetry: stale || !total.isAvailable ? retry : null,
            // The split is only shown under a real headline. Listing a
            // one cent provider fee under "Shown before you confirm"
            // reads as the answer, and it is not.
            details: total.isAvailable && provider.isAvailable
                ? [
                    if (sourceFeeUsd > 0)
                      MoneyFeeSummary(
                          label: sourceFeeIsMaximum
                              ? 'Network activation (up to)'
                              : 'Network activation',
                          usd: sourceFeeUsd,
                          bitcoinFirst: bitcoinFirst),
                    if (providerPart.isAvailable)
                      MoneyFeeSummary(
                          label: 'Provider fee',
                          usd: providerPart.usd,
                          sats: providerPart.sats,
                          bitcoinFirst: bitcoinFirst),
                    MoneyFeeSummary(
                        label: kuteLabel,
                        usd: kute.usd,
                        sats: kute.sats,
                        bitcoinFirst: bitcoinFirst,
                        note: quote.kuteReferralDiscountBps > 0
                            ? context.l10n.feeUiFriendDiscountIncluded(
                                discountShareText(discountShareOf(
                                    paid: quote.kuteAppFeeBps ?? 0,
                                    discount: quote.kuteReferralDiscountBps)))
                            : null,
                        state: kute.isAvailable
                            ? null
                            : 'Shown before you confirm'),
                    if (routePart.isAvailable &&
                        (routePart.usd ?? routePart.sats ?? 0) > 0)
                      MoneyFeeSummary(
                          label: 'Network fee',
                          usd: routePart.usd,
                          sats: routePart.sats,
                          bitcoinFirst: bitcoinFirst),
                    if (received.isAvailable)
                      MoneyFeeSummary(
                          label: 'You receive',
                          usd: received.usd,
                          sats: received.sats,
                          bitcoinFirst: bitcoinFirst),
                  ]
                : const [],
          ),
        ]);
  }
}

/// Resolve native HyperCore availability before displaying fees.
final _directHypercore =
    FutureProvider.autoDispose.family<bool, bool>((ref, deposit) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref
      .watch(sparkHypercoreFundingServiceProvider)
      .tryDirect(deposit: deposit);
});

class MoveHyperliquidFees extends ConsumerWidget {
  const MoveHyperliquidFees(
      {super.key,
      required this.deposit,
      required this.sats,
      required this.usd,
      required this.bitcoinFirst,
      this.fromDollars = false,
      this.toDollars = false});
  final bool deposit, bitcoinFirst;

  /// A deposit funded from the dollar balance rather than from spending
  /// bitcoin. Same destination, different leg, so the estimate has to
  /// ask about the one that will actually run.
  final bool fromDollars;

  /// A withdrawal delivered into the dollar balance rather than into
  /// spending bitcoin. The mirror of [fromDollars]: same source, other
  /// end of the leg.
  final bool toDollars;
  final int sats;
  final double usd;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entered = deposit && !fromDollars ? sats.toDouble() : usd;
    if (entered <= 0) {
      return const MoneyFeeSummary(label: 'Fees', state: 'Enter an amount');
    }
    return ref.watch(_directHypercore(deposit)).when(
          skipLoadingOnRefresh: true,
          loading: () =>
              const MoneyFeeSummary(label: 'Fees', state: 'Calculating…'),
          error: (_, __) => MoneyFeeSummary(
              label: 'Fees',
              state: 'Estimate unavailable',
              onRetry: () => ref.invalidate(_directHypercore(deposit))),
          data: (direct) {
            if (!direct) {
              return MoneyFeeSummary(
                  label: 'Fees',
                  state: deposit
                      ? context.l10n.investingDepositsUnavailable
                      : context.l10n.investingWithdrawalsUnavailable);
            }
            final fromChain = deposit
                ? (fromDollars ? kOrchestraUsdChain : 'spark')
                : 'hypercore';
            final fromAsset = deposit
                ? (fromDollars ? kOrchestraUsdAssetCode : 'BTC')
                : 'USDC';
            // A withdrawal is a perpetuals usdSend, which costs the source
            // only its amount (hypercoreUsdSendSenderFee): the whole figure
            // is priced, with no activation line and nothing held back.
            return OrchestraFeeSummary(bitcoinFirst: bitcoinFirst, route: (
              fromChain: fromChain,
              fromAsset: fromAsset,
              toChain: deposit
                  ? 'hypercore'
                  : (toDollars ? kOrchestraUsdChain : 'spark'),
              toAsset: deposit
                  ? 'USDC'
                  : (toDollars ? kOrchestraUsdAssetCode : 'BTC'),
              amount: deposit && !fromDollars
                  ? sats.toString()
                  : doubleToOrchestraAmount(usd, fromAsset, chain: fromChain),
            ));
          },
        );
  }
}

/// The amount [route] sends, valued at the app's own price in the unit the
/// destination is quoted in: dollars for a stablecoin, sats for bitcoin.
/// Null whenever the pair has no honest valuation, which leaves the fee
/// block on the provider's own figure.
double? _inputInDestinationUnits(FeeRoute route, {double? usdPerBtc}) {
  const stables = {'USDC', 'USDC.E', 'USDT', 'USDB', 'USD'};
  final from = route.fromAsset.trim().toUpperCase();
  final to = route.toAsset.trim().toUpperCase();
  final input = orchestraAmountToDouble(route.amount, route.fromAsset,
      chain: route.fromChain);
  if (!input.isFinite || input <= 0) return null;
  final priced = usdPerBtc != null && usdPerBtc.isFinite && usdPerBtc > 0;
  if (from == 'BTC' && to == 'BTC') return input * 1e8;
  if (from == 'BTC' && stables.contains(to)) {
    return priced ? input * usdPerBtc : null;
  }
  if (stables.contains(from) && to == 'BTC') {
    return priced ? input / usdPerBtc * 1e8 : null;
  }
  if (stables.contains(from) && stables.contains(to)) return input;
  return null;
}
