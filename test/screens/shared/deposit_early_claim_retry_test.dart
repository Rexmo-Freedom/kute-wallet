// Claim now on a confirming deposit asks again while the sheet is open:
// the SDK lists a deposit some time after it is broadcast, and a sheet
// that checked once, at open, never offered Claim now for it.
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/deposit_quick_claim.dart';
import 'package:kute/services/spark_deposit_actions.dart';

class _Actions extends SparkDepositActions {
  _Actions()
      : super(
            loadSdk: (_) => throw UnimplementedError(),
            currentWalletId: () => 'spending');

  /// The SDK lists the deposit from this lookup on (1-based).
  int listedFrom = 3;
  int? earlyFee = 400;
  int lookups = 0;
  int quotes = 0;

  @override
  Future<DepositInfo?> depositForTxid(
      {required String walletId, required String txid}) async {
    lookups++;
    if (lookups < listedFrom) return null;
    return DepositInfo(
        txid: txid, vout: 1, amountSats: BigInt.from(50000), isMature: false);
  }

  @override
  Future<SparkDepositQuote> quote(
      {required String walletId,
      required String txid,
      required int vout}) async {
    quotes++;
    return SparkDepositQuote(
        confirmations: 0, matureFeeSats: 300, earlyFeeSats: earlyFee);
  }
}

Future<void> _pump(WidgetTester tester, _Actions actions) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
            activeWalletId: 'spending',
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: true,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      sparkDepositActionsProvider.overrideWithValue(actions),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => const MaterialApp(
        // The probe never builds the button (it would need the price
        // providers): only the asking is under test.
        home: Scaffold(body: _Probe()),
      ),
    ),
  ));
}

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) =>
      const DepositEarlyClaim(txid: 'abc', amountSats: 50000);
}

void main() {
  testWidgets('a deposit the SDK lists later still gets its quote',
      (tester) async {
    final actions = _Actions()..earlyFee = null;
    await _pump(tester, actions);
    await tester.pump();
    expect(actions.lookups, 1);
    expect(actions.quotes, 0);
    // Not listed yet: asked again after the wait, not only at open.
    await tester.pump(DepositEarlyClaimRetry.every + const Duration(seconds: 1));
    expect(actions.lookups, 2);
    await tester.pump(DepositEarlyClaimRetry.every + const Duration(seconds: 1));
    expect(actions.lookups, 3);
    expect(actions.quotes, 1);
    // Listed, but the provider offers no early claim yet: it asks again.
    await tester.pump(DepositEarlyClaimRetry.every + const Duration(seconds: 1));
    expect(actions.quotes, 2);
    // Closing the sheet stops the asking.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(DepositEarlyClaimRetry.every * 3);
    expect(actions.quotes, 2);
  });
}
