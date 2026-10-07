import 'package:kute/constants/polymarket_constants.dart';

/// Net six-decimal collateral credited by this transaction, not the change in
/// the whole wallet balance (which may include concurrent claims/deposits).
/// Null means receipt data is incomplete; zero is a verified zero-credit tx.
BigInt? claimCreditFromReceipt(Map<String, dynamic> receipt, String owner) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(owner)) return null;
  if (!['0x1', '0x01'].contains(receipt['status'])) return null;
  final logs = receipt['logs'];
  if (logs is! List) return null;
  const transfer =
      '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';
  final tokens = {
    PolymarketConstants.pusdAddress.toLowerCase(),
    PolymarketConstants.usdcEAddress.toLowerCase()
  };
  final target = owner.substring(2).toLowerCase();
  var total = BigInt.zero;
  for (final log in logs) {
    if (log is! Map) return null;
    if (!tokens.contains('${log['address']}'.toLowerCase())) continue;
    final topics = log['topics'];
    if (topics is! List || topics.isEmpty) return null;
    if ('${topics.first}'.toLowerCase() != transfer) continue;
    if (topics.length != 3 ||
        !topics
            .skip(1)
            .every((t) => RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch('$t'))) {
      return null;
    }
    final data = '${log['data']}';
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(data)) return null;
    final value = BigInt.parse(data.substring(2), radix: 16);
    if ('${topics[2]}'.substring(26).toLowerCase() == target) total += value;
    if ('${topics[1]}'.substring(26).toLowerCase() == target) total -= value;
  }
  return total >= BigInt.zero ? total : null;
}
