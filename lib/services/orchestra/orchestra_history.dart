import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/security/address_guard.dart';

/// Recipient history includes every route for that wallet. Attribute an order
/// only to the deposit address and route actually displayed or cached.
bool orchestraHistoryMatchesDeposit(
  OrchestraOrder order, {
  required String sourceChain,
  required String sourceAsset,
  required String destinationAsset,
  required String depositAddress,
  required String recipientSparkAddress,
}) {
  bool label(String? actual, String expected) =>
      actual != null && actual.toLowerCase() == expected.toLowerCase();
  if (!label(order.sourceChain, sourceChain) ||
      !label(order.sourceAsset, sourceAsset) ||
      !label(order.destinationChain, 'spark') ||
      !label(order.destinationAsset, destinationAsset) ||
      !sameSparkAddress(order.recipientAddress ?? '', recipientSparkAddress)) {
    return false;
  }
  final actualDeposit = order.depositAddress;
  if (actualDeposit == null ||
      actualDeposit.isEmpty ||
      depositAddress.isEmpty) {
    return false;
  }
  if (kEvmAddressChains.contains(sourceChain.toLowerCase())) {
    return sameEvmAddress(actualDeposit, depositAddress);
  }
  return actualDeposit == depositAddress;
}
