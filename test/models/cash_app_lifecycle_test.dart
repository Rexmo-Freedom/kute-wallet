import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_invoice_expiry.dart';
import 'package:kute/helpers/cash_app_status.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra_routes.dart';

SwapOrder _purchase(
        {String status = 'pending', int? expiry, String invoice = ''}) =>
    SwapOrder(
      id: 'ord_test',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'BITCOIN',
      depositAddress: invoice,
      depositAmount: '0.001',
      withdrawalAmount: '0.00099',
      status: status,
      timestamp: 1000,
      withdrawalAddress: '',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      purchaseSource: 'cashapp',
      purchaseFiatUsd: '55.00',
      expiresAt: expiry,
    );

// Synthetic BOLT11 metadata fixture. No actual keys, recipient or payment.
String _invoice({int? expirySeconds}) {
  const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  const hrp = 'lnbc';
  final words = <int>[0, 0, 0, 0, 0, 0, 1]; // created at Unix second 1
  if (expirySeconds != null) {
    final value = <int>[];
    var n = expirySeconds;
    do {
      value.insert(0, n & 31);
      n >>= 5;
    } while (n > 0);
    words.addAll([6, 0, value.length, ...value]);
  }
  words.addAll(List.filled(104, 0)); // signature placeholder, never used to pay
  var crc = 1;
  for (final word in [
    ...hrp.codeUnits.map((c) => c >> 5),
    0,
    ...hrp.codeUnits.map((c) => c & 31),
    ...words,
    0,
    0,
    0,
    0,
    0,
    0
  ]) {
    final top = crc >> 25;
    crc = ((crc & 0x1ffffff) << 5) ^ word;
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 != 0) crc ^= gen[i];
    }
  }
  crc ^= 1;
  final checksum = [for (var i = 5; i >= 0; i--) (crc >> (5 * i)) & 31];
  return '${hrp}1${[...words, ...checksum].map((n) => alphabet[n]).join()}';
}

void main() {
  test('old stored invoices recover explicit expiry and BOLT11 default', () {
    expect(
        cashAppInvoiceExpiry(_invoice(expirySeconds: 300))!
            .millisecondsSinceEpoch,
        301000);
    expect(cashAppInvoiceExpiry(_invoice())!.millisecondsSinceEpoch, 3601000);
    expect(
        cashAppInvoiceExpiry(_invoice().toUpperCase())!.millisecondsSinceEpoch,
        3601000);
    expect(cashAppInvoiceExpiry('not-an-invoice'), isNull);
    final corrupted = '${_invoice().substring(0, _invoice().length - 1)}!';
    expect(cashAppInvoiceExpiry(corrupted), isNull);
  });
  test('closed invoice stops pending animation but keeps status reconciliation',
      () {
    final row = _purchase(expiry: 1000);
    expect(row.statusLabel, 'Payment window ended');
    expect(row.isPending, isFalse);
    expect(row.isExpired, isFalse);
    expect(row.shouldPollOrchestra, isTrue);
    expect(row.isComplete, isFalse);
  });
  test('existing rows use their own invoice expiry, never an invented deadline',
      () {
    expect(_purchase(invoice: _invoice()).cashAppPaymentWindowClosed, isTrue);
    expect(_purchase().cashAppPaymentWindowClosed, isFalse);
    expect(_purchase().statusLabel, 'Awaiting payment');
  });
  test(
      'paid and refund-in-flight orders keep their financial status after expiry',
      () {
    for (final status in ['exchanging', 'confirmation', 'sending', 'overdue']) {
      final row = _purchase(status: status, expiry: 1000);
      expect(row.cashAppPaymentWindowClosed, isFalse);
      expect(row.isExpired, isFalse);
      expect(row.shouldPollOrchestra, isTrue);
    }
  });
  test('unfulfilled remains reconcilable for late deposits', () {
    final row = _purchase(status: 'unfulfilled', expiry: 1000);
    expect(row.statusLabel, 'Payment window ended');
    expect(row.shouldPollOrchestra, isTrue);
    expect(row.copyWith(status: 'success').isComplete, isTrue);
  });
  test('provider terminal state wins over the payment window', () {
    for (final status in ['success', 'refunded', 'expired']) {
      final row = _purchase(status: status, expiry: 1000);
      expect(row.cashAppPaymentWindowClosed, isFalse);
      expect(row.shouldPollOrchestra, isFalse);
    }
  });
  test('nested provider order retains backend expiry and payment evidence', () {
    final order = OrchestraOrder.fromJson({
      'order': {
        'id': 'ord_test',
        'status': 'processing',
        'createdAt': '2026-09-15'
      },
      'expiresAt': '2026-09-15T10:00:00Z',
      'paymentReceived': true,
    });
    expect(order.id, 'ord_test');
    expect(order.expiresAt, '2026-09-15T10:00:00Z');
    expect(order.paymentReceived, isTrue);
    expect(
        cashAppExchangeStatus(order.status,
            paymentReceived: order.paymentReceived == true),
        'exchanging');
    expect(cashAppExchangeStatus('processing'), 'pending');
    expect(cashAppExchangeStatus('UNFULFILLED'), 'unfulfilled');
    expect(cashAppExchangeStatus('COMPLETED'), 'success');
  });
  test('id replacement preserves purchase fiat and expiry', () {
    final old = _purchase(expiry: 1000);
    final updated = old.copyWith(id: 'ord_real', status: 'success');
    expect(updated.purchaseFiatUsd, '55.00');
    expect(updated.expiresAt, 1000);
    expect(updated.isCashAppPurchase, isTrue);
  });
  test('provider unfulfilled closes the window without a deadline or clock',
      () {
    final noDeadline = _purchase(status: 'unfulfilled');
    expect(noDeadline.cashAppExpiresAt, isNull);
    expect(noDeadline.cashAppPaymentWindowClosed, isTrue);
    expect(noDeadline.isPending, isFalse);
    expect(noDeadline.cashAppWindowClosedAt, noDeadline.timestamp);
    final later =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
    expect(_purchase(status: 'unfulfilled', expiry: later).cashAppPaymentWindowClosed,
        isTrue);
    expect(_purchase(expiry: later).cashAppPaymentWindowClosed, isFalse);
    for (final status in ['exchanging', 'confirmation', 'sending', 'overdue']) {
      expect(_purchase(status: status).cashAppPaymentWindowClosed, isFalse);
      expect(_purchase(status: status).cashAppWindowClosedAt, isNull);
    }
  });
  test('legacy stuck order without stored expiry ends from its invoice', () {
    // Recorded days ago by an older build: no expiresAt, only the invoice.
    final legacy = _purchase(invoice: _invoice(expirySeconds: 600));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(legacy.expiresAt, isNull);
    expect(legacy.cashAppExpiresAt, 601000);
    expect(legacy.cashAppPaymentWindowClosed, isTrue);
    expect(cashAppStatusLabel(legacy, en), en.cashAppPaymentWindowEnded);
    expect(legacy.isPending, isFalse);
    expect(legacy.isExpired, isFalse);
    expect(legacy.isComplete, isFalse);
    expect(legacy.shouldPollOrchestra, isTrue);
    // Closed long ago: checked on the first sync after the app starts and
    // after each return to the foreground, never in between, and it never
    // keeps sync running off the sync routes.
    var now = DateTime.now();
    final schedule = CashAppClosedWindowSchedule(now: () => now);
    expect(schedule.anyRecentlyClosedDue([legacy]), isFalse);
    expect(schedule.begin(legacy), isTrue);
    schedule.recordSuccess(legacy.id);
    now = now.add(const Duration(days: 2));
    expect(schedule.begin(legacy), isFalse);
    schedule.markForegrounded();
    now = now.add(const Duration(seconds: 1));
    expect(schedule.begin(legacy), isTrue);
    // Older builds stored the ambiguous initial processing as exchanging.
    // The next unpaid status response moves it into the same ended state.
    final oldBuild = legacy.copyWith(status: 'exchanging');
    expect(oldBuild.cashAppPaymentWindowClosed, isFalse);
    final reconciled =
        oldBuild.copyWith(status: cashAppExchangeStatus('processing'));
    expect(reconciled.cashAppPaymentWindowClosed, isTrue);
    expect(reconciled.purchaseFiatUsd, '55.00');
  });
  test('a received payment is never stored as unpaid or window ended', () {
    for (final raw in ['unfulfilled', 'UNFULFILLED', 'awaiting_payment']) {
      final status = cashAppExchangeStatus(raw, paymentReceived: true);
      expect(status, 'exchanging', reason: raw);
      final row = _purchase(status: status, expiry: 1000);
      expect(row.cashAppPaymentWindowClosed, isFalse, reason: raw);
      expect(row.isPending, isTrue, reason: raw);
    }
    expect(cashAppExchangeStatus('unfulfilled'), 'unfulfilled');
    expect(cashAppExchangeStatus('failed', paymentReceived: true), 'expired');
    expect(cashAppExchangeStatus('refunding', paymentReceived: true), 'overdue');
  });
}
