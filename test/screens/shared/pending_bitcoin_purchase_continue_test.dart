// A Buy bitcoin whose purchase waits on the person (its approval ran out,
// or the app restarted while the money came home) never sits silently in
// Dollars: its Activity row says "Your $X is in Investments. Tap to buy
// Bitcoin" once the money is there, and the tap asks ONE fresh approval
// for exactly that purchase and buys it. Declined: nothing moves.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/shared/pending_bitcoin_purchase_continue.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart';

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

void main() {
  late List<double> bought;
  late double dollars;
  late List<SensitiveIntent> prompts;

  BitcoinPurchaseFinisher finisher() => BitcoinPurchaseFinisher(
        readDollars: () => dollars,
        buy: (double usd, SettlementStepUpHook stepUp,
            {required String moveId,
            required void Function() onFunding}) async {
          bought.add(usd);
          onFunding();
        },
        sleep: (_) => Future<void>.delayed(const Duration(milliseconds: 10)),
      );

  setUp(() {
    bought = [];
    dollars = 25.71;
    prompts = [];
    PendingBitcoinPurchaseStore.reset();
  });
  tearDown(() => debugPendingPurchaseApproval = null);

  Future<WidgetRef> pump(WidgetTester tester, BitcoinPurchaseFinisher f) async {
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => _Settings()),
        sparkSelfAddressProvider.overrideWith((_) async => 'spark1self'),
        usdBalanceProvider.overrideWith((_) => dollars),
        bitcoinPurchaseFinisherProvider.overrideWithValue(f),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        }),
      ),
    ));
    return captured;
  }

  testWidgets(
      'the waiting purchase shows once its money is in Dollars, and one tap '
      'with a fresh approval buys exactly it', (tester) async {
    final f = finisher();
    PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
        moveId: 'msm_1',
        usd: 20.23,
        createdAt: DateTime(2026, 10, 15, 12),
        stage: PendingPurchaseStage.needsApproval));
    // Not landed yet: no prompt, the row stays Pending.
    expect(pendingPurchaseWaitingUsd(f, 'msm_1', 0.4), isNull);
    // Landed: what the purchase takes, never more than Dollars hold.
    expect(pendingPurchaseWaitingUsd(f, 'msm_1', 25.71), 20.23);
    expect(pendingPurchaseWaitingUsd(f, 'msm_1', 19.5), 19.5);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.multiMovePurchaseWaiting(r'$20.23', l10n.assetDollars),
        r'Your $20.23 is in Investments. Tap to buy Bitcoin');

    debugPendingPurchaseApproval = (intent) async {
      prompts.add(intent);
      return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
    };
    final ref = await pump(tester, f);
    await continuePendingBitcoinPurchase(
        tester.element(find.byType(SizedBox)), ref, 'msm_1');
    await tester.pump(const Duration(milliseconds: 50));
    // ONE prompt, for this purchase alone: the own Spark address, at most
    // the amount, 30 min.
    expect(prompts, hasLength(1));
    expect(prompts.single.action, SensitiveAction.moveTransfer);
    expect(prompts.single.destination, 'spark1self');
    expect(prompts.single.amountMax, BigInt.from(20230000));
    expect(prompts.single.ttl, AuthGrants.autofireTtl);
    expect(bought, [20.23]);
    expect(PendingBitcoinPurchaseStore.get('msm_1'), isNull);
    expect(pendingPurchaseWaitingUsd(f, 'msm_1', 25.71), isNull);
  });

  testWidgets('declined: nothing moves and the row keeps saying so',
      (tester) async {
    final f = finisher();
    PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
        moveId: 'msm_1',
        usd: 20.23,
        createdAt: DateTime(2026, 10, 15, 12),
        stage: PendingPurchaseStage.needsApproval));
    debugPendingPurchaseApproval = (intent) async {
      prompts.add(intent);
      return null;
    };
    final ref = await pump(tester, f);
    await continuePendingBitcoinPurchase(
        tester.element(find.byType(SizedBox)), ref, 'msm_1');
    await tester.pump(const Duration(milliseconds: 50));
    expect(prompts, hasLength(1));
    expect(bought, isEmpty);
    expect(pendingPurchaseWaitingUsd(f, 'msm_1', 25.71), 20.23);
  });
}
