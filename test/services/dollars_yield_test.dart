// Recognising the Dollars yield payout among received bitcoin payments
// (lib/services/dollars_yield.dart): the ledger's transfer id first, then
// only an unambiguous exact amount on the paid day, never a pending row,
// never another wallet's payment. Every id here is made up.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/dollars_yield_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/services/dollars_yield.dart';

SparkTransaction _receive(
  String id,
  int sats,
  DateTime at, {
  SparkTransactionType rail = SparkTransactionType.spark,
  TransactionType direction = TransactionType.received,
  bool pending = false,
}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: !pending,
      amountSats: sats,
      sparkType: rail,
      direction: direction,
      pending: pending,
    );

RewardPayout _payout({
  String day = '2026-11-20',
  int sats = 137,
  String status = 'paid',
  String? txId,
  String? paidAt = '2026-11-21T01:00:12Z',
}) =>
    RewardPayout(
      day: day,
      usdbBalanceDisplay: 500,
      rewardsBracket: 1,
      payoutSats: sats,
      status: status,
      txId: txId,
      paidAt: paidAt,
    );

final _paidDay = DateTime.utc(2026, 11, 21, 1, 0, 40);

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }
}

Transaction _history(List<SparkTransaction> spark) => Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: spark,
      sparkUnclaimedDeposits: const [],
    );

void main() {
  group('matchDollarsYieldPayments', () {
    test('a paid payout matches the payment of its sats on its paid day', () {
      final ids = matchDollarsYieldPayments(
        [_payout()],
        [
          _receive('pay-yield', 137, _paidDay),
          _receive('pay-other', 5000, _paidDay),
        ],
      );
      expect(ids, {'pay-yield'});
    });

    test('the ledger naming the transfer matches it on any day', () {
      final ids = matchDollarsYieldPayments(
        [_payout(txId: 'AB12-CD34')],
        [_receive('ab12cd34:0', 137, DateTime.utc(2026, 11, 23, 9))],
      );
      expect(ids, {'ab12cd34:0'});
    });

    test('a named transfer whose amount disagrees labels nothing', () {
      final ids = matchDollarsYieldPayments(
        [_payout(txId: 'ab12cd34')],
        [
          _receive('ab12cd34', 999, _paidDay),
          // Not a fallback either: the row named its payment.
          _receive('pay-same-amount', 137, _paidDay),
        ],
      );
      expect(ids, isEmpty);
    });

    test('the same amount on another day is not yield', () {
      final ids = matchDollarsYieldPayments(
        [_payout()],
        [_receive('pay-later', 137, DateTime.utc(2026, 11, 24, 1, 0, 40))],
      );
      expect(ids, isEmpty);
    });

    test('two payments of the payout amount that day, one row: neither', () {
      final ids = matchDollarsYieldPayments(
        [_payout()],
        [
          _receive('pay-a', 137, _paidDay),
          _receive('pay-b', 137, _paidDay.add(const Duration(hours: 5))),
        ],
      );
      expect(ids, isEmpty);
    });

    test('one payment two rows could claim labels nothing', () {
      final ids = matchDollarsYieldPayments(
        [
          _payout(day: '2026-11-20', paidAt: null),
          _payout(day: '2026-11-21', paidAt: null),
        ],
        // 22:00 UTC on the 21st: day+1 of the first, day of the second.
        [_receive('pay-shared', 137, DateTime.utc(2026, 11, 21, 22))],
      );
      expect(ids, isEmpty);
    });

    test('without a paid time the accrual day and the next one count', () {
      final ids = matchDollarsYieldPayments(
        [_payout(paidAt: null)],
        [_receive('pay-yield', 137, _paidDay)],
      );
      expect(ids, {'pay-yield'});
    });

    test('a pending payout labels nothing', () {
      final ids = matchDollarsYieldPayments(
        [
          _payout(status: 'pending', paidAt: null),
          _payout(status: 'pending', txId: 'pay-yield'),
        ],
        [_receive('pay-yield', 137, _paidDay)],
      );
      expect(ids, isEmpty);
    });

    test('no ledger, nothing is yield', () {
      final ids = matchDollarsYieldPayments(
          const [], [_receive('pay-yield', 137, _paidDay)]);
      expect(ids, isEmpty);
    });

    test('a send, a pending receive or a Lightning receive is never yield',
        () {
      expect(
          matchDollarsYieldPayments([_payout()], [
            _receive('pay-sent', 137, _paidDay,
                direction: TransactionType.sent),
          ]),
          isEmpty);
      expect(
          matchDollarsYieldPayments([_payout()], [
            _receive('pay-pending', 137, _paidDay, pending: true),
          ]),
          isEmpty);
      expect(
          matchDollarsYieldPayments([_payout()], [
            _receive('pay-ln', 137, _paidDay,
                rail: SparkTransactionType.lightning),
          ]),
          isEmpty);
    });

    test('a Spark receive paying the person\'s own invoice is not yield', () {
      final invoiced = SparkTransaction(
        id: 'pay-invoice',
        timestamp: _paidDay,
        isConfirmed: true,
        details: breez.Payment(
          id: 'pay-invoice',
          paymentType: breez.PaymentType.receive,
          status: breez.PaymentStatus.completed,
          amount: BigInt.from(137),
          fees: BigInt.zero,
          timestamp: BigInt.from(_paidDay.millisecondsSinceEpoch ~/ 1000),
          method: breez.PaymentMethod.spark,
          details: const breez.PaymentDetails.spark(
            invoiceDetails: breez.SparkInvoicePaymentDetails(
                description: 'coffee', invoice: 'spark1invoice'),
          ),
        ),
      );
      expect(matchDollarsYieldPayments([_payout()], [invoiced]), isEmpty);
    });
  });

  group('dollarsYieldPaymentIdsProvider', () {
    ProviderContainer container(Map<String, List<RewardPayout>> ledger,
            Map<String, Transaction> cache) =>
        ProviderContainer(overrides: [
          dollarsYieldLedgerProvider
              .overrideWith((_) => DollarsYieldLedgerNotifier(initial: ledger)),
          walletTransactionCacheProvider.overrideWith((_) => _Cache(cache)),
        ]);

    test('labels the wallet\'s own payout', () {
      final c = container({
        'spending': [_payout()]
      }, {
        'spending': _history([_receive('pay-yield', 137, _paidDay)]),
      });
      addTearDown(c.dispose);
      expect(c.read(dollarsYieldPaymentIdsProvider), {'pay-yield'});
    });

    test('never another wallet\'s payment', () {
      final c = container({
        'spending': [_payout()]
      }, {
        'spending': _history(const []),
        'other': _history([_receive('pay-elsewhere', 137, _paidDay)]),
      });
      addTearDown(c.dispose);
      expect(c.read(dollarsYieldPaymentIdsProvider), isEmpty);
    });

    test('no ledger yet: nothing labelled; a fresher ledger re-labels', () {
      final c = container(const {}, {
        'spending': _history([_receive('pay-yield', 137, _paidDay)]),
      });
      addTearDown(c.dispose);
      expect(c.read(dollarsYieldPaymentIdsProvider), isEmpty);
      c.read(dollarsYieldLedgerProvider.notifier).put('spending', [
        _payout(),
        _payout(day: '2026-11-21', status: 'pending', sats: 140),
      ]);
      expect(c.read(dollarsYieldPaymentIdsProvider), {'pay-yield'});
      // Only paid rows are kept.
      expect(c.read(dollarsYieldLedgerProvider)['spending'], hasLength(1));
    });
  });

  test('the stored rows read back as the matcher needs them', () {
    final rows = [_payout(txId: 'ab12cd34')];
    final back =
        DollarsYieldLedgerStore.decode(DollarsYieldLedgerStore.encode(rows));
    expect(back.single.day, '2026-11-20');
    expect(back.single.payoutSats, 137);
    expect(back.single.isPaid, isTrue);
    expect(back.single.txId, 'ab12cd34');
    expect(back.single.paidAt, '2026-11-21T01:00:12Z');
  });
}
