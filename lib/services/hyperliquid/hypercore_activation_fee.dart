import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/security/address_guard.dart';

/// The account does not hold the cash a native transfer needs, read
/// before anything is signed. A [StateError] like before, so every caller
/// that stops on one still does; the move sheet now also tells the person
/// why instead of a bare "could not be completed".
class HypercoreBalanceShortfall extends StateError {
  HypercoreBalanceShortfall(
      [super.message = 'Insufficient available balance.']);
}

class HypercoreActivationFeeUnavailable implements Exception {
  const HypercoreActivationFeeUnavailable();

  @override
  String toString() => 'Native transfer activation fee is unavailable.';
}

class HypercoreActivationFeeChanged implements Exception {
  const HypercoreActivationFeeChanged();

  @override
  String toString() => 'Native transfer activation fee changed. Review again.';
}

class HypercoreActivationFeeBalanceRequired implements Exception {
  const HypercoreActivationFeeBalanceRequired();

  @override
  String toString() => 'Additional USDC is required for account activation.';
}

/// Native USDC uses eight decimals. This is the documented new-account
/// activation charge, not a minimum withdrawal amount or bridge fee.
/// https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/activation-gas-fee
/// A sender pays it on top only for spot sends; see
/// [hypercoreUsdSendSenderFee] for the perpetuals `usdSend` Kute uses.
final BigInt hypercoreAccountActivationFee = BigInt.from(100000000);

BigInt hypercoreActivationFeeForRole(Object? response) {
  if (response is! Map) throw const HypercoreActivationFeeUnavailable();
  return switch (response['role']) {
    'missing' => hypercoreAccountActivationFee,
    'user' => BigInt.zero,
    // Agent keys and special account roles are not proof that this
    // ordinary spot-transfer destination is activated and fee-free.
    _ => throw const HypercoreActivationFeeUnavailable(),
  };
}

/// What a perpetuals `usdSend` charges its SENDER on top of the amount:
/// nothing, whether or not the destination is activated.
///
/// HyperCore bills the 1 USDC activation of a new account differently per
/// action. A `spotSend`/`sendAsset` debits the sender `amount + 1` and the
/// new account receives `amount` in full. A `usdSend` (perpetuals USDC,
/// the only action Orchestra's `hypercore:USDC` route accepts) debits the
/// sender exactly `amount`; the ledger records `fee: 1.0` on the transfer,
/// but the charge comes out of what the new account can spend (public
/// ledgers: a new address sent 100.0 by usdSend forwards 99.0 and holds 0).
/// Orchestra's deposit address, not the person, bears it. Reserving it on
/// the source left exactly 1 USDC stranded after every 100% withdrawal.
Future<BigInt> hypercoreUsdSendSenderFee(String destination) async {
  if (!isEvmAddress(destination)) {
    throw const HypercoreActivationFeeUnavailable();
  }
  return BigInt.zero;
}

Future<BigInt> readHypercoreActivationFee(String destination,
    {http.Client? client}) async {
  if (!isEvmAddress(destination)) {
    throw const HypercoreActivationFeeUnavailable();
  }
  try {
    final body = jsonEncode({'type': 'userRole', 'user': destination});
    final response = await (client == null
            ? http.post(HyperliquidConstants.infoUri,
                headers: {'content-type': 'application/json'}, body: body)
            : client.post(HyperliquidConstants.infoUri,
                headers: {'content-type': 'application/json'}, body: body))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const HypercoreActivationFeeUnavailable();
    }
    return hypercoreActivationFeeForRole(jsonDecode(response.body));
  } catch (_) {
    throw const HypercoreActivationFeeUnavailable();
  }
}

/// The exact source debit reserve. The quoted amount is never reduced
/// to pay the activation fee. A fee increase needs another approval.
BigInt hypercoreTransferReserve({
  required BigInt amountBaseUnits,
  required BigInt currentFeeBaseUnits,
  required BigInt reviewedFeeBaseUnits,
}) {
  if (amountBaseUnits <= BigInt.zero ||
      currentFeeBaseUnits < BigInt.zero ||
      reviewedFeeBaseUnits < BigInt.zero) {
    throw ArgumentError('Invalid native transfer amount or fee');
  }
  if (currentFeeBaseUnits > reviewedFeeBaseUnits) {
    throw const HypercoreActivationFeeChanged();
  }
  return amountBaseUnits + currentFeeBaseUnits;
}

/// Required internal perp-to-spot move in eight-decimal USDC units,
/// rounded up to the internal transfer's six-decimal quantum.
BigInt hypercoreSpotShortfall({
  required BigInt requiredBaseUnits,
  required double spotAvailable,
  required double perpAvailable,
  BigInt? activationFeeBaseUnits,
}) {
  if (!spotAvailable.isFinite ||
      !perpAvailable.isFinite ||
      spotAvailable < 0 ||
      perpAvailable < 0) {
    throw StateError('Available native balance could not be verified.');
  }
  // Exact, not floored: a floored 19.99 is one unit short of itself.
  final spot = hypercoreBalanceBaseUnits(spotAvailable);
  final perp = hypercoreBalanceBaseUnits(perpAvailable);
  final shortfall = requiredBaseUnits - spot;
  if (shortfall <= BigInt.zero) return BigInt.zero;
  final quantum = BigInt.from(100);
  final transfer = ((shortfall + quantum - BigInt.one) ~/ quantum) * quantum;
  if (transfer > perp) {
    final fee = activationFeeBaseUnits ?? BigInt.zero;
    if (fee > BigInt.zero && spot + perp >= requiredBaseUnits - fee) {
      throw const HypercoreActivationFeeBalanceRequired();
    }
    throw HypercoreBalanceShortfall();
  }
  return transfer;
}

/// Required spot-to-perpetuals move, restricted to available cash. Uses the
/// same exact reserve and six-decimal internal transfer quantum as legacy sends.
BigInt hypercorePerpShortfall({
  required BigInt requiredBaseUnits,
  required double spotAvailable,
  required double perpAvailable,
  BigInt? activationFeeBaseUnits,
}) =>
    hypercoreSpotShortfall(
      requiredBaseUnits: requiredBaseUnits,
      spotAvailable: perpAvailable,
      perpAvailable: spotAvailable,
      activationFeeBaseUnits: activationFeeBaseUnits,
    );

/// A dollar figure as eight-decimal HyperCore USDC base units. Rounded to
/// the nearest unit, not floored: a double like 0.29 is 0.28999999999...
/// and flooring it, then flooring again to the transfer's six-decimal
/// quantum, sent 0.289999 and stranded a micro-dollar. Balances never
/// carry more than eight decimals, so rounding can never exceed one.
BigInt hypercoreUsdcBaseUnits(double usd) {
  if (!usd.isFinite || usd <= 0) return BigInt.zero;
  return BigInt.from((usd * 1e8).round());
}

/// A quote funded from an all-in USDC budget. The amount sent to the provider
/// and the separately charged activation fee must fit that same budget.
class HypercoreBudgetQuote<T> {
  const HypercoreBudgetQuote({
    required this.value,
    required this.amount,
    required this.activationFee,
  });
  final T value;
  final BigInt amount;
  final BigInt activationFee;
}

/// Re-quote before approval when the provider's destination needs activation.
/// Every replacement address is checked again; nothing is funded here.
Future<HypercoreBudgetQuote<T>> quoteHypercoreBudget<T>({
  required BigInt budget,
  required Future<HypercoreBudgetQuote<T>> Function(BigInt amount, int attempt)
      request,
}) async {
  if (budget <= BigInt.zero) throw ArgumentError.value(budget, 'budget');
  // Round the budget down before requesting any quote, never after approval.
  final spendableBudget = (budget ~/ BigInt.from(100)) * BigInt.from(100);
  if (spendableBudget <= BigInt.zero) {
    throw ArgumentError.value(budget, 'budget');
  }
  var amount = spendableBudget;
  for (var attempt = 0; attempt < 3; attempt++) {
    final result = await request(amount, attempt);
    if (result.amount != amount || result.activationFee < BigInt.zero) {
      throw StateError('Withdrawal quote does not match the requested amount.');
    }
    final net = spendableBudget - result.activationFee;
    if (net <= BigInt.zero) {
      throw const HypercoreActivationFeeBalanceRequired();
    }
    if (amount == net) return result;
    amount = net;
  }
  throw const HypercoreActivationFeeChanged();
}
