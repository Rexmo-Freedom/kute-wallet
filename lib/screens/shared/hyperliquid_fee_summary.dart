import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';

final _builderConfig = FutureProvider.autoDispose<HlBuilderInfo?>((ref) {
  ref.watch(runtimeCapabilitiesProvider
      .select((policy) => policy.snapshot?.revision));
  return HyperliquidFundingService.getBuilder();
});

final _userFees = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, address) async {
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final client = http.Client();
  ref.onDispose(client.close);
  final response = await client
      .post(Uri.parse('https://api.hyperliquid.xyz/info'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'type': 'userFees', 'user': address}))
      .timeout(const Duration(seconds: 8));
  if (response.statusCode != 200) throw StateError('Fee unavailable');
  return jsonDecode(response.body) as Map<String, dynamic>;
});

/// One order the fee summary prices: its notional and the flags that pick
/// the Kute fee and the venue rate. The order slip prices one; the
/// portfolio Builder prices every leg of its run.
class HyperliquidFeeLeg {
  const HyperliquidFeeLeg(
      {required this.notional,
      required this.spot,
      required this.buy,
      this.dex = ''});
  final double notional;
  final bool spot, buy;
  final String dex;
}

/// The Kute (builder) fee attached to one order: the order's notional at the
/// `f` tenths of a basis point it carries (`builder:{b,f}`). Spot buys show
/// none, as on the order slip.
double hyperliquidKuteFeeUsd(HyperliquidFeeLeg leg,
        {required int feeTenthsBp, bool builder = true}) =>
    !builder || (leg.spot && leg.buy) ? 0 : leg.notional * feeTenthsBp / 100000;

/// Totals across [legs]. `kute` is null while the published fee is unknown
/// (and any leg carries one); `exchange` is null when the account's rate is
/// unknown or any leg is on a HIP-3 dex, whose multipliers we don't model.
({double? kute, double? exchange}) hyperliquidFeeTotals(
  List<HyperliquidFeeLeg> legs, {
  required bool builderKnown,
  int? feeTenthsBp,
  Map<String, dynamic>? userFees,
  bool maker = false,
  bool builder = true,
}) {
  final charged = builder && legs.any((l) => !(l.spot && l.buy));
  double? kute = 0;
  if (charged && !builderKnown) {
    kute = null;
  } else {
    for (final leg in legs) {
      kute = kute! +
          hyperliquidKuteFeeUsd(leg,
              feeTenthsBp: feeTenthsBp ?? 0, builder: builder);
    }
  }
  final discount = double.tryParse('${userFees?['activeReferralDiscount']}');
  double? exchange = 0;
  for (final leg in legs) {
    final key = leg.spot
        ? (maker ? 'userSpotAddRate' : 'userSpotCrossRate')
        : (maker ? 'userAddRate' : 'userCrossRate');
    final rate = double.tryParse('${userFees?[key]}');
    // HIP-3's deployer/growth multipliers are not in our market model. Do
    // not present the default-perp rate as the total for those markets.
    final known = rate != null &&
        rate.isFinite &&
        discount != null &&
        discount.isFinite &&
        discount >= 0 &&
        discount <= 1 &&
        leg.dex.isEmpty;
    if (!known) {
      exchange = null;
      break;
    }
    exchange = exchange! + leg.notional * math.max(0, rate) * (1 - discount);
  }
  return (kute: kute, exchange: exchange);
}

/// The totals [HyperliquidFeeSummary] is showing for [legs] on the hot
/// account right now, read from the same providers. For analytics at the
/// moment a reviewed run is placed.
({double? kute, double? exchange}) readHyperliquidFeeTotals(
    WidgetRef ref, List<HyperliquidFeeLeg> legs) {
  final config = ref.read(_builderConfig);
  final owner = ref.read(hyperliquidAddressProvider).valueOrNull;
  final fees = owner == null || legs.any((l) => l.dex.isNotEmpty)
      ? null
      : ref.read(_userFees(owner)).valueOrNull;
  return hyperliquidFeeTotals(legs,
      builderKnown: config.hasValue,
      feeTenthsBp: config.valueOrNull?.defaultFeeTenthsBp,
      userFees: fees);
}

class HyperliquidFeeSummary extends ConsumerWidget {
  const HyperliquidFeeSummary(
      {super.key,
      required this.notional,
      required this.spot,
      required this.buy,
      this.maker = false,
      this.builder = true,
      this.dex = '',
      this.address,
      this.useHotAccount = true,
      this.hasFunds = true})
      : legs = null;

  /// The total across several market orders on the hot account (the
  /// portfolio Builder's run), in the same row as the order slip's.
  const HyperliquidFeeSummary.legs(
      {super.key, required List<HyperliquidFeeLeg> this.legs})
      : notional = 0,
        spot = false,
        buy = true,
        maker = false,
        builder = true,
        dex = '',
        address = null,
        useHotAccount = true,
        hasFunds = true;
  final double notional;
  final bool spot, buy, maker, builder, useHotAccount, hasFunds;
  final String dex;
  final String? address;
  final List<HyperliquidFeeLeg>? legs;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const btc = false;
    if (!hasFunds) {
      return const MoneyFeeSummary(
          bitcoinFirst: btc, state: 'Add funds to continue');
    }
    final orders = legs ??
        [HyperliquidFeeLeg(notional: notional, spot: spot, buy: buy, dex: dex)];
    final total = orders.fold<double>(0, (s, l) => s + l.notional);
    if (total <= 0 ||
        !total.isFinite ||
        orders.any((l) => l.notional < 0 || !l.notional.isFinite)) {
      return const MoneyFeeSummary(bitcoinFirst: btc, state: 'Enter an amount');
    }
    final owner = address ??
        (useHotAccount
            ? ref.watch(hyperliquidAddressProvider).valueOrNull
            : null);
    final builderConfig = ref.watch(_builderConfig);
    final anyDex = orders.any((l) => l.dex.isNotEmpty);
    final fees = owner == null || anyDex ? null : ref.watch(_userFees(owner));
    final totals = hyperliquidFeeTotals(orders,
        builderKnown: builderConfig.hasValue,
        feeTenthsBp: builderConfig.valueOrNull?.defaultFeeTenthsBp,
        userFees: fees?.valueOrNull,
        maker: maker,
        builder: builder);
    final builderFee = totals.kute;
    final exchange = totals.exchange;
    return MoneyFeeSummary(
        bitcoinFirst: btc,
        label: exchange == null ? 'Kute fee' : 'Estimated fee',
        usd: builderFee == null ? null : builderFee + (exchange ?? 0),
        state: builderFee == null
            ? (builderConfig.isLoading
                ? 'Calculating…'
                : 'Fee settings unavailable')
            : null,
        onRetry: exchange == null &&
                owner != null &&
                !anyDex &&
                fees?.isLoading != true
            ? () => ref.invalidate(_userFees(owner))
            : null,
        details: [
          MoneyFeeSummary(
              label: 'Exchange fee estimate',
              usd: exchange,
              state: exchange == null ? 'Unavailable' : null,
              bitcoinFirst: btc),
          MoneyFeeSummary(
              label: 'Kute fee',
              usd: builderFee,
              note: builderConfig.valueOrNull?.discounted == true
                  ? context.l10n.feeUiFriendDiscountIncluded(discountShareText(
                      discountShareOf(
                          paid: builderConfig.valueOrNull!.defaultFeeTenthsBp,
                          discount: builderConfig
                                  .valueOrNull!.listedFeeTenthsBp -
                              builderConfig.valueOrNull!.defaultFeeTenthsBp)))
                  : null,
              state: builderFee == null ? 'Unavailable' : null,
              bitcoinFirst: btc),
        ]);
  }
}
