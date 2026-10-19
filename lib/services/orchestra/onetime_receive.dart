// lib/services/orchestra/onetime_receive.dart
//
// Receiving another coin from another network (founder, 2026-10-19): a
// ONE-TIME quoted Orchestra deposit address per payment, for both
// destinations. The Dollars receive delivers `spark:USDB`; the Bitcoin
// receive's "other coins" delivers `spark:BTC`. No reusable address
// (standing or legacy accumulation) is created for either; the backend
// refuses them too.
//
//   * The person picks a coin and network the live catalogue routes into
//     the destination, then the amount (USD for dollars, sats or fiat for
//     bitcoin) in the Lightning receive's own "Request amount" sheet,
//     checked against the route's live minimum (Flashnet's own, no floor) and
//     maximum.
//   * Before the quote, the person may give a return address: theirs, on
//     the source network, for that coin (founder, 2026-10-19). A failed
//     deposit is sent back there. Never the wallet's own EVM address (the
//     Predictions EOA has no balance anyone sees, so a refund there is
//     lost), never a Spark or Bitcoin address, never prefilled from the
//     clipboard; the last one typed per wallet and network is remembered
//     on the device only ([OneTimeRefundAddressStore]).
//   * It is optional. Skipped, the quote carries no refund address, which
//     Flashnet takes for a listed token (it asks one only for
//     unlisted-token sources); every offered coin comes from the live
//     catalogue, so it is listed. A failed deposit then needs Support.
//     Sends keep the refund requirement.
//   * One exact-in quote from that network into the destination, paid to
//     the wallet's own Spark address (pinned and verified as every
//     own-Spark quote is). Offered from EVM networks, Solana and Tron;
//     other networks (Bitcoin, Litecoin, Zcash, TON, XRP) are not.
//   * The quote is persisted as a pending quote (`q_…`) before its address
//     is shown, and is NOT an Activity row: nothing appears in Activity, a
//     badge or a count before money is sent. The deposit poller and
//     background sync keep watching it after it expires (late deposits
//     included) and write the real order's row (`ord_…`) when Orchestra
//     reports a deposit, which retires the pending quote.
//
// Nothing here signs or pays anything.

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart'
    show PendingReceiveQuoteScope;
import 'package:kute/services/orchestra_routes.dart'
    show
        isOrchestraUsdLikeCoin,
        isVenueInternalRoute,
        orchestraCanQuoteReceiveOn;
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

/// The analytics `destination` of a one-time receive into
/// spark:[destinationAsset]: `spark_usd` or `spark_btc`.
String oneTimeReceiveDestinationLabel(String destinationAsset) =>
    destinationAsset.trim().toUpperCase() == 'USDB' ? 'spark_usd' : 'spark_btc';

/// Whether a one-time receive can be offered from [chain] at all: an EVM
/// network (HyperCore is Investing's own rail and never a payer's
/// network), Solana or Tron.
bool oneTimeReceiveOffered(String chain) {
  final slug = chain.trim().toLowerCase();
  return (kEvmAddressChains.contains(slug) && slug != 'hypercore') ||
      const {'solana', 'tron'}.contains(slug);
}

/// Whether [address] can be a one-time receive's return address on
/// [chain]: a mainnet address of that network (so never a Spark or
/// Bitcoin address), on a network a one-time receive is offered from.
bool oneTimeRefundAddressValid(String chain, String address) {
  final value = address.trim();
  return value.isNotEmpty &&
      oneTimeReceiveOffered(chain) &&
      formatMatchesChain(chain, value, mainnet: true) == AddressFormatMatch.ok;
}

/// Every coin and network the live catalogue routes into
/// spark:[destinationAsset] that a one-time receive can serve: a live
/// directed route with explicit source units, a network
/// [oneTimeReceiveOffered], and
/// never a venue's own rail. Every row is a
/// one-time row (`reusableAddress: false`). Empty without live data: a
/// static fallback carries no source units to quote with.
List<OrchestraReceiveOption> oneTimeReceiveOptions(
  OrchestraRoutesCatalog catalog, {
  required String destinationAsset,
}) {
  if (!catalog.hasLiveData) return const [];
  return [
    for (final o in catalog.receiveOptions(
        destinationChain: 'spark', destinationAsset: destinationAsset))
      if (oneTimeReceiveOffered(o.chain) &&
          orchestraCanQuoteReceiveOn(o.chain) &&
          !isVenueInternalRoute(o.chain, o.assetCode))
        OrchestraReceiveOption(
          assetCode: o.assetCode,
          displayName: o.displayName,
          displaySymbol: o.displaySymbol,
          chain: o.chain,
          chainDisplayName: o.chainDisplayName,
          decimals: o.decimals,
          chainIconUrl: o.chainIconUrl,
          assetIconUrl: o.assetIconUrl,
          reusableAddress: false,
        ),
  ];
}

/// Coins whose unit is one dollar.
bool _dollarCoin(String code) =>
    isOrchestraUsdLikeCoin(code) ||
    const {'USDT0', 'USDS', 'USDG', 'PYUSD'}.contains(code);

/// Coins whose unit is one bitcoin.
bool _bitcoinCoin(String code) =>
    const {'BTC', 'WBTC', 'CBBTC', 'BTCB', 'LBTC', 'TBTC'}.contains(code);

/// The source amount, in [asset]'s smallest unit, worth [usdCents]: at par
/// for a dollar coin, at the local [usdPerBtc] for a bitcoin coin, and at
/// the route's own price for anything else (its exact-in bounds, stated
/// both in source units and in cents, by `/orchestration/limits`). Null
/// when there is no price to use.
BigInt? oneTimeSourceUnits({
  required String asset,
  required int decimals,
  required int usdCents,
  required double usdPerBtc,
  OrchestraRouteLimits? limits,
}) {
  if (usdCents <= 0 || decimals < 0 || decimals > 18) return null;
  final code = asset.trim().toUpperCase();
  final cents = BigInt.from(usdCents);
  final scale = BigInt.from(10).pow(decimals);
  if (_dollarCoin(code)) return cents * scale ~/ BigInt.from(100);
  if (_bitcoinCoin(code)) {
    if (!usdPerBtc.isFinite || usdPerBtc <= 0) return null;
    final sats = BigInt.from((usdCents * 1e6 / usdPerBtc).round());
    if (sats <= BigInt.zero) return null;
    return decimals >= 8
        ? sats * BigInt.from(10).pow(decimals - 8)
        : sats ~/ BigInt.from(10).pow(8 - decimals);
  }
  if (limits == null) return null;
  ({BigInt units, int cents})? pair(BigInt? units, int? pairCents) =>
      units != null && units > BigInt.zero && pairCents != null && pairCents > 0
          ? (units: units, cents: pairCents)
          : null;
  // The larger bound carries more digits, so a cent of rounding moves
  // the price least.
  final price = pair(limits.exactInMaxBaseUnits, limits.exactInMaxUsdCents) ??
      pair(limits.exactInMinBaseUnits, limits.exactInMinUsdCents);
  if (price == null) return null;
  final units = cents * price.units ~/ BigInt.from(price.cents);
  return units > BigInt.zero ? units : null;
}

/// The route's largest order in whole USD cents, or null when the limits
/// read stated none.
int? oneTimeMaxUsdCents(OrchestraRouteLimits? limits) {
  if (limits == null) return null;
  final caps = [limits.exactInMaxUsdCents, limits.orderMaxUsdCents]
      .whereType<int>()
      .where((c) => c > 0);
  if (caps.isEmpty) return null;
  return caps.reduce((a, b) => a < b ? a : b);
}

/// Whether [row] is a one-time receive's row, under its quote id or its
/// order's: a receive from outside into Spark that carries its quote's
/// expiry (a reusable address's rows carry none).
bool isOneTimeReceiveRow(SwapOrder row) =>
    row.providerName == 'Orchestra' &&
    row.activityDirection == 'receive' &&
    row.purchaseSource == 'crypto_receive' &&
    row.networkTo.toUpperCase() == 'SPARK' &&
    row.expiresAt != null;

/// Whether [row] is a one-time receive's pending quote: what Receive
/// persists the moment the quote exists (never an Activity row; older
/// builds of this branch wrote one).
bool isOneTimeReceiveQuoteRow(SwapOrder row) =>
    row.id.startsWith('q_') &&
    row.providerName == 'Orchestra' &&
    row.activityDirection == 'receive' &&
    row.purchaseSource == 'crypto_receive' &&
    row.networkTo.toUpperCase() == 'SPARK';

/// How long after its quote expired a one-time receive's row keeps being
/// asked about before a not-found read may close it: a deposit sent late
/// is repriced by Flashnet and still lands.
const Duration kOneTimeReceiveLateDepositWatch = Duration(hours: 24);

abstract final class OneTimeReceive {
  /// The `flow` a refused quote is reported under.
  static const String quoteFlow = 'onetime_receive';

  /// Test seam: answers [fetch] in place of the Orchestra quote gate.
  @visibleForTesting
  static Future<VerifiedOrchestraQuote> Function(OrchestraQuoteRequest request)?
      debugFetch;

  /// Test seam: records the quote in place of the pending-quote cache.
  /// Read by the receive screen.
  static Future<void> Function(
          SwapOrder row, DateTime expiresAt, PendingReceiveQuoteScope scope)?
      debugRecord;

  static int destinationDecimals(String destinationAsset) =>
      destinationAsset.trim().toUpperCase() == 'BTC' ? 8 : 6;

  /// The quote for [amountBaseUnits] of [option] into
  /// spark:[destinationAsset], paid to the wallet's own Spark
  /// [recipient] ([ownSpark] is the independently resolved own address
  /// the guard compares it with), refunded to the person's own
  /// [refundAddress] on the source network, or carrying none when they
  /// skipped it (null or empty). Throws [WalletGuardException] for a
  /// network a one-time receive is not offered from, or a return address
  /// that is not one of that network.
  static OrchestraQuoteRequest request({
    required OrchestraReceiveOption option,
    required String destinationAsset,
    required BigInt amountBaseUnits,
    required String recipient,
    required String ownSpark,
    required String? refundAddress,
  }) {
    final refund = refundAddress?.trim() ?? '';
    if (!oneTimeReceiveOffered(option.chain) ||
        (refund.isNotEmpty &&
            !oneTimeRefundAddressValid(option.chain, refund))) {
      throw const WalletGuardException(WalletGuardReason.refundAddressChain);
    }
    return OrchestraQuoteRequest(
      sourceChain: option.chain,
      sourceAsset: option.assetCode,
      destinationChain: 'spark',
      destinationAsset: destinationAsset,
      amountBaseUnits: amountBaseUnits,
      recipientAddress: recipient,
      refundAddress: refund,
      refundOptional: refund.isEmpty,
      recipientKind: RecipientKind.ownSpark,
      ownAddress: ownSpark,
      deliveryMode: 'variable',
    );
  }

  /// Quotes [request] through the Orchestra quote gate (verified, or a
  /// [WalletGuardException] / [OrchestraQuoteFailure]).
  static Future<VerifiedOrchestraQuote> fetch(OrchestraQuoteRequest request) {
    final debug = debugFetch;
    if (debug != null) return debug(request);
    return OrchestraQuoteGate.fetchVerified(
      request,
      OrchestraQuoteBounds.forSource(request.sourceChain,
          inputValueInOutputUnits: null),
      flow: quoteFlow,
    );
  }

  /// Right before the address is shown to the payer: the quote is still
  /// outside its expiry margin and for exactly [amountBaseUnits].
  static void ensurePayable(
          VerifiedOrchestraQuote verified, BigInt amountBaseUnits) =>
      OrchestraQuoteGate.ensurePayable(verified,
          amountBaseUnits: amountBaseUnits, now: DateTime.now());

  /// The pending-quote record of [verified]: a receive of [option] into
  /// spark:[destinationAsset] waiting for its deposit, under the quote id.
  /// Its real order's Activity row is written from it once a deposit is
  /// detected. Throws [WalletGuardException] when
  /// the quote states no positive output.
  static SwapOrder row({
    required OrchestraReceiveOption option,
    required String destinationAsset,
    required VerifiedOrchestraQuote verified,
    required String walletId,
    required DateTime now,
  }) {
    final raw = verified.quote.estimatedOut;
    final output = RegExp(r'^\d+$').hasMatch(raw) ? BigInt.tryParse(raw) : null;
    if (output == null || output <= BigInt.zero) {
      throw const WalletGuardException(WalletGuardReason.echoMismatch);
    }
    return SwapOrder(
      activityDirection: 'receive',
      id: verified.quoteId,
      coinFrom: option.assetCode,
      networkFrom: option.chain,
      coinTo: destinationAsset,
      networkTo: 'SPARK',
      depositAddress: verified.depositAddress,
      depositAmount: decimalAmount(verified.amountIn, option.decimals),
      withdrawalAmount:
          decimalAmount(output, destinationDecimals(destinationAsset)),
      status: 'wait',
      timestamp: now.millisecondsSinceEpoch,
      withdrawalAddress: verified.request.recipientAddress,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: verified.request.refundAddress,
      provider: 'Orchestra',
      walletId: walletId,
      expiresAt: verified.expiresAt.millisecondsSinceEpoch,
      purchaseSource: 'crypto_receive',
    );
  }
}

/// [units] of an asset with [decimals] as a plain decimal string, with no
/// trailing zeros ("12.5", "0.00021").
String decimalAmount(BigInt units, int decimals) {
  final digits = units.toString().padLeft(decimals + 1, '0');
  if (decimals == 0) return digits;
  final split = digits.length - decimals;
  final fraction = digits.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? digits.substring(0, split)
      : '${digits.substring(0, split)}.$fraction';
}
