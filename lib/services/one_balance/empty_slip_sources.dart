import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show GetInfoRequest;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

/// A zero placeholder is never proof that the person needs a deposit.
bool slipSourcesKnownEmpty({
  required int? bitcoinSats,
  required double? sdkDollarsUsd,
  required OneBalanceState investments,
  required bool dollarsUnknown,
  required bool sparkSynced,
}) =>
    sparkSynced &&
    bitcoinSats == 0 &&
    sdkDollarsUsd == 0 &&
    !dollarsUnknown &&
    investments.investingKnown &&
    investments.predictionsKnown &&
    investments.dollarsUsd == 0 &&
    investments.investedUsd == 0 &&
    investments.venueCashUsd == 0 &&
    investments.inFlightUsd == 0 &&
    investments.waitingUsd == 0;

/// Called only after the ordinary in-place funding decision found no funding.
/// No price assumption or cached Bitcoin zero can open the deposit sheet.
final slipKnownEmptySourcesProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null) return false;
    try {
      final wrapper = await ref
          .read(breezSDKProvider.future)
          .timeout(const Duration(seconds: 3));
      final sdk = wrapper.instance;
      if (sdk == null || !wrapper.hasSynced) return false;
      final info = await sdk
          .getInfo(request: const GetInfoRequest())
          .timeout(const Duration(seconds: 3));
      if (pickSpendingWallet(ref.read(settingsProvider))?.id != walletId ||
          !identical(wrapper.instance, sdk)) {
        return false;
      }
      // A freshly delivered Dollar payment can precede the SDK row. A
      // conflicting positive settled ledger keeps this from claiming empty.
      if (usdLedgerSumDollars(ref.read(usdSettledTransfersProvider)) > 0) {
        return false;
      }
      return slipSourcesKnownEmpty(
        bitcoinSats: info.balanceSats.toInt(),
        // A successful node read with no dollar entry agrees with a known
        // empty ledger; a stale/missing held entry is rejected below.
        sdkDollarsUsd: usdDollarsFromNodeInfo(info) ?? 0,
        investments: ref.read(oneBalanceProvider),
        dollarsUnknown: ref.read(usdBalanceUnknownProvider),
        sparkSynced: wrapper.hasSynced,
      );
    } catch (_) {
      return false;
    }
  };
});
