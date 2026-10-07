import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/security/address_guard.dart';

/// Resolves a Ledger-owned deposit wallet without deriving a hot signer.
/// Account creation is public and gasless; wrapping funds still requires Ledger.
Future<String> ledgerCashAppPredictionsRecipient({
  required String eoa,
  required PolymarketAccountReads reads,
  required Future<String> Function(String eoa) deploy,
  Future<void> Function(Duration)? delay,
}) async {
  if (!isEvmAddress(eoa)) throw StateError('Pair your Ledger account first.');
  final resolver = PolymarketAccountResolver(reads);
  var account = await resolver.resolve(eoa);
  if (account.kind == PolymarketAccountKind.none) {
    final expected =
        account.predictedDepositWallet ?? reads.deriveDepositWalletAddress(eoa);
    final deployed = await deploy(eoa);
    if (!sameEvmAddress(deployed, expected) &&
        !sameEvmAddress(deployed, reads.deriveDepositWalletAddress(eoa))) {
      throw StateError('The deposit address does not belong to this Ledger.');
    }
    for (var i = 0; i < 5; i++) {
      account = await resolver.resolve(eoa);
      if (account.canAct &&
          account.address != null &&
          sameEvmAddress(account.address!, deployed)) {
        break;
      }
      if (i < 4) {
        await (delay ?? Future<void>.delayed)(const Duration(seconds: 2));
      }
    }
  }
  final address = account.address;
  if (!account.canAct || address == null) {
    throw StateError('This Ledger Predictions account is not ready yet.');
  }
  final derived = reads.deriveDepositWalletAddress(eoa);
  if (!sameEvmAddress(address, derived) &&
      !sameEvmAddress(address, await reads.predictDepositWallet(eoa))) {
    throw StateError('The deposit address does not belong to this Ledger.');
  }
  return address;
}
