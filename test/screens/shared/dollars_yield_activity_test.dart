// The daily reward on the Dollars balance arrives as bitcoin; its activity
// row and its receipt read "Dollars yield" (founder, 25 November 2026),
// with the receive's amount, time and mark. A receive the payout ledger
// does not name stays "Received". The export's type says the same.
// Every id here is made up.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/dollars_yield_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/transaction_pdf_export.dart';
import 'package:kute/theme/app_theme.dart';

import 'receipt_fixtures.dart';

final _paidAt = DateTime.utc(2026, 11, 1, 1, 0, 30);

SparkTransaction _receive(String id, int sats) => SparkTransaction.fromCache(
      id: id,
      timestamp: _paidAt,
      isConfirmed: true,
      amountSats: sats,
      sparkType: SparkTransactionType.spark,
      direction: TransactionType.received,
      pending: false,
    );

final _yield = _receive('pay-yield-test', 137);
final _plain = _receive('pay-plain-test', 4200);

const _payout = RewardPayout(
  day: '2026-10-31',
  usdbBalanceDisplay: 500,
  rewardsBracket: 1,
  payoutSats: 137,
  status: 'paid',
  paidAt: '2026-11-01T01:00:05Z',
);

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }
}

List<Override> get _overrides => [
      walletTransactionCacheProvider.overrideWith((_) => _Cache({
            'spending': Transaction(
              bitcoinTransactions: const [],
              sparkTransactions: [_yield, _plain],
              sparkUnclaimedDeposits: const [],
            ),
          })),
      dollarsYieldLedgerProvider.overrideWith((_) => DollarsYieldLedgerNotifier(
          initial: const {
            'spending': [_payout]
          })),
    ];

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  late Directory hive;
  setUpAll(() async => hive = await openReceiptHive());
  tearDownAll(() => closeReceiptHive(hive));

  late BuildContext opener;
  late WidgetRef openerRef;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpRows(WidgetTester tester, List<BaseTransaction> rows) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(receiptApp(
      Consumer(builder: (context, ref, _) {
        opener = context;
        openerRef = ref;
        return Column(children: [
          for (final tx in rows) buildUnifiedTransactionItem(tx, context, ref),
        ]);
      }),
      theme: buildLightTheme(),
      overrides: _overrides,
    ));
    await settle(tester);
  }

  testWidgets('the payout row reads "Dollars yield", the other "Received"',
      (tester) async {
    await pumpRows(tester, [_yield, _plain]);
    expect(find.text('Dollars yield'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    // Its amount stays the receive's, in bitcoin.
    expect(find.textContaining('137'), findsWidgets);
  });

  testWidgets('the payout receipt is titled "Dollars yield"', (tester) async {
    await pumpRows(tester, const []);
    await openTransactionDetails(opener, openerRef, _yield);
    await settle(tester);
    final hero = find.byKey(const ValueKey('receipt-hero'));
    expect(find.descendant(of: hero, matching: find.text('Dollars yield')),
        findsOneWidget);
    expect(_inSheet(find.text('Received')), findsNothing);
  });

  test('the export types the payout "Dollars yield"', () {
    final wallet = WalletConfig(id: 'spending', name: 'Spending');
    final yieldRow = TransactionPdfExport.enrichForTest(_yield, wallet,
        dollarsYieldIds: {_yield.id})!;
    final plainRow = TransactionPdfExport.enrichForTest(_plain, wallet,
        dollarsYieldIds: {_yield.id})!;
    expect(yieldRow.type, 'Dollars yield');
    expect(yieldRow.sats, 137);
    expect(yieldRow.isSent, isFalse);
    expect(plainRow.type, 'Spark Received');
  });
}
