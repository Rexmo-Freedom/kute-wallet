import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_purchase_session.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';

final _start = DateTime.utc(2026, 9, 15, 12);
final _deadline = _start.add(const Duration(minutes: 10));
const _grace = CashAppPurchaseSession.endedGracePeriod;

class _Clock {
  DateTime now = _start;
  void advance(Duration by) => now = now.add(by);
}

OrchestraOnrampResponse _onramp({
  String orderId = 'ord_1',
  String quoteId = 'q_1',
  String invoice = 'lnbc1invoice',
  DateTime? expiresAt,
}) =>
    OrchestraOnrampResponse(
      orderId: orderId,
      quoteId: quoteId,
      depositAddress: invoice,
      paymentLinks: OrchestraPaymentLinks(cashApp: '', shortUrl: ''),
      amountIn: '0',
      estimatedOut: '0',
      expiresAt: expiresAt?.toIso8601String() ?? '',
    );

OrchestraOrder _status(String status, {bool? paymentReceived}) =>
    OrchestraOrder(
      id: 'ord_1',
      status: status,
      createdAt: '',
      paymentReceived: paymentReceived,
    );

SwapOrder _row({
  String id = 'ord_1',
  String status = 'pending',
  String invoice = 'lnbc1invoice',
  int? expiresAt,
}) =>
    SwapOrder(
      id: id,
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'SPARK',
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
      expiresAt: expiresAt,
    );

Future<OrchestraOrder?> _unpaid(String _) async => _status('processing');

void main() {
  group('sheet poll cadence', () {
    test('polls every 5 s in the window and tolerates early timer ticks',
        () async {
      final clock = _Clock();
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      var calls = 0;
      Future<OrchestraOrder?> fetch(String id) async {
        calls++;
        expect(id, 'ord_1');
        return _status('processing');
      }

      await session.poll(fetch);
      clock.advance(const Duration(milliseconds: 4600));
      await session.poll(fetch);
      expect(calls, 2);
      clock.advance(const Duration(seconds: 4));
      await session.poll(fetch);
      expect(calls, 2);
      await session.poll(fetch, force: true);
      expect(calls, 3);
      expect(session.pollInterval, CashAppPurchaseSession.activePollInterval);
    });

    test('keeps the fast cadence through the grace period, then slows down',
        () async {
      final clock = _Clock();
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      clock.now = _deadline.add(const Duration(seconds: 1));
      expect(session.paymentWindowEnded, isTrue);
      expect(session.pollInterval, CashAppPurchaseSession.activePollInterval);

      clock.now = _deadline.add(_grace);
      expect(session.pollInterval, CashAppPurchaseSession.endedPollInterval);
      var calls = 0;
      Future<OrchestraOrder?> fetch(String _) async {
        calls++;
        return _status('processing');
      }

      await session.poll(fetch);
      clock.advance(const Duration(seconds: 10));
      await session.poll(fetch);
      expect(calls, 1);
      clock.advance(const Duration(seconds: 20));
      await session.poll(fetch);
      expect(calls, 2);
    });

    test('a poll in flight is not duplicated, even when forced', () async {
      final session = CashAppPurchaseSession(now: () => _start)
        ..begin(_onramp(expiresAt: _deadline));
      final pending = Completer<OrchestraOrder?>();
      final first = session.poll((_) => pending.future);
      var calls = 0;
      final second = await session.poll((_) async {
        calls++;
        return null;
      }, force: true);
      expect(second, isNull);
      expect(calls, 0);
      pending.complete(_status('processing'));
      expect(await first, isNotNull);
    });
  });

  group('new purchase offer', () {
    test('needs the grace period and an unpaid check sent after the deadline',
        () async {
      final clock = _Clock();
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      await session.poll(_unpaid);

      clock.now = _deadline.add(_grace).add(const Duration(seconds: 1));
      expect(session.paymentWindowEnded, isTrue);
      expect(session.canOfferNewPurchase, isFalse);
      expect(session.prepareNewPurchase(), isFalse);
      expect(session.order, isNotNull);

      await session.poll(_unpaid);
      expect(session.canOfferNewPurchase, isTrue);
      expect(session.prepareNewPurchase(), isTrue);
      expect(session.order, isNull);
    });

    test('an unpaid check from early in the grace period does not count',
        () async {
      final clock = _Clock();
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      clock.now = _deadline.add(const Duration(seconds: 5));
      await session.poll(_unpaid);
      clock.now = _deadline.add(_grace).add(const Duration(minutes: 3));
      expect(session.canOfferNewPurchase, isFalse);

      clock.now = _deadline
          .add(_grace)
          .subtract(CashAppPurchaseSession.activePollInterval);
      await session.poll(_unpaid);
      expect(session.canOfferNewPurchase, isFalse);
      clock.now = _deadline.add(_grace);
      expect(session.canOfferNewPurchase, isTrue);
      expect(session.newPurchaseOfferAt,
          _deadline.add(_grace).millisecondsSinceEpoch);
    });

    test('a failed status check never counts as unpaid', () async {
      final clock = _Clock()..now = _deadline.add(_grace).add(_grace);
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      await session.poll((_) async => null);
      expect(session.paymentWindowEnded, isTrue);
      expect(session.canOfferNewPurchase, isFalse);
    });

    test('a later failed or unknown check withdraws the offer', () async {
      for (final later in <Future<OrchestraOrder?> Function(String)>[
        (_) async => null,
        (_) async => _status('quoted'),
      ]) {
        final clock = _Clock()..now = _deadline.add(_grace);
        final session = CashAppPurchaseSession(now: () => clock.now)
          ..begin(_onramp(expiresAt: _deadline));
        await session.poll(_unpaid);
        expect(session.canOfferNewPurchase, isTrue);

        clock.advance(CashAppPurchaseSession.endedPollInterval);
        await session.poll(later);
        expect(session.canOfferNewPurchase, isFalse);
        expect(session.paymentReceived, isFalse);

        clock.advance(CashAppPurchaseSession.endedPollInterval);
        await session.poll(_unpaid);
        expect(session.canOfferNewPurchase, isTrue);
      }
    });

    test('payment received stays sticky and keeps the fast cadence', () async {
      final clock = _Clock()
        ..now = _deadline.subtract(const Duration(seconds: 3));
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      await session
          .poll((_) async => _status('processing', paymentReceived: true));
      expect(session.paymentReceived, isTrue);

      clock.now = _deadline.add(_grace).add(const Duration(seconds: 5));
      await session.poll(_unpaid, force: true);
      expect(session.paymentReceived, isTrue);
      expect(session.paymentWindowEnded, isFalse);
      expect(session.canOfferNewPurchase, isFalse);
      expect(session.prepareNewPurchase(), isFalse);
      expect(session.pollInterval, CashAppPurchaseSession.activePollInterval);
    });

    test('an in-progress provider status is payment evidence', () async {
      final clock = _Clock()..now = _deadline.add(_grace).add(_grace);
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp(expiresAt: _deadline));
      await session.poll((_) async => _status('bridging'));
      expect(session.paymentReceived, isTrue);
      expect(session.paymentWindowEnded, isFalse);
      expect(session.canOfferNewPurchase, isFalse);
    });

    test('failed, cancelled and unknown statuses are not payment evidence',
        () async {
      for (final raw in ['failed', 'cancelled', 'expired', 'quoted']) {
        final session =
            CashAppPurchaseSession(now: () => _deadline.add(_grace))
              ..begin(_onramp(expiresAt: _deadline));
        await session.poll((_) async => _status(raw));
        expect(session.paymentReceived, isFalse, reason: raw);
        expect(session.paymentWindowEnded, isTrue, reason: raw);
        expect(session.canOfferNewPurchase, isFalse, reason: raw);
      }
      for (final stored in ['expired', 'canceled', 'quoted']) {
        final session = CashAppPurchaseSession(
          now: () => _deadline.add(_grace),
          storedOrders: () => [_row(status: stored)],
        )..begin(_onramp(expiresAt: _deadline));
        expect(session.paymentReceived, isFalse, reason: stored);
        expect(session.paymentWindowEnded, isTrue, reason: stored);
      }
    });

    test('a stored order updated by background sync blocks the offer', () async {
      final cases = <(OrchestraOnrampResponse, SwapOrder)>[
        (_onramp(), _row(id: 'ord_1', status: 'exchanging', invoice: 'other')),
        (
          _onramp(orderId: ''),
          _row(id: 'q_1', status: 'confirmation', invoice: 'other')
        ),
        (_onramp(orderId: ''), _row(id: 'ord_real', status: 'sending')),
        (_onramp(), _row(id: 'ord_real', status: 'success')),
      ];
      for (final (order, paidRow) in cases) {
        final clock = _Clock();
        var stored = [_row(id: paidRow.id, invoice: paidRow.depositAddress)];
        final session = CashAppPurchaseSession(
          now: () => clock.now,
          storedOrders: () => stored,
        )..begin(order.copyWithDeadline(_deadline));
        clock.now = _deadline.add(_grace);
        await session.poll(_unpaid);
        expect(session.canOfferNewPurchase, isTrue);

        stored = [paidRow];
        expect(session.showsPaymentIn(stored), isTrue);
        expect(session.paymentReceived, isTrue);
        expect(session.paymentWindowEnded, isFalse);
        expect(session.canOfferNewPurchase, isFalse);

        stored = [_row(id: paidRow.id, invoice: paidRow.depositAddress)];
        expect(session.paymentReceived, isTrue);
        expect(session.canOfferNewPurchase, isFalse);
      }
    });

    test('unrelated stored orders are ignored', () {
      final session = CashAppPurchaseSession(
        now: () => _deadline.add(_grace),
        storedOrders: () =>
            [_row(id: 'ord_other', status: 'success', invoice: 'lnbc1other')],
      )..begin(_onramp(expiresAt: _deadline));
      expect(session.paymentReceived, isFalse);
      expect(session.paymentWindowEnded, isTrue);
    });
  });

  group('provider-confirmed expiry', () {
    test('unfulfilled closes a window with no known deadline', () async {
      final clock = _Clock();
      final session = CashAppPurchaseSession(now: () => clock.now)
        ..begin(_onramp());
      expect(session.expiresAt, isNull);
      expect(session.paymentWindowEnded, isFalse);

      await session.poll((_) async {
        clock.advance(const Duration(seconds: 1));
        return _status('unfulfilled');
      });
      expect(session.paymentWindowEnded, isTrue);
      expect(session.pollInterval, CashAppPurchaseSession.activePollInterval);

      // The check that reported expiry was sent before the window ended.
      clock.advance(_grace);
      expect(session.canOfferNewPurchase, isFalse);
      await session.poll(_unpaid);
      expect(session.canOfferNewPurchase, isTrue);
    });

    test('unfulfilled closes the window before a slow clock reaches it',
        () async {
      final session = CashAppPurchaseSession(now: () => _start)
        ..begin(_onramp(expiresAt: _start.add(const Duration(hours: 1))));
      await session.poll((_) async => _status('unfulfilled'));
      expect(session.paymentWindowEnded, isTrue);
    });

    test('paid or in-progress statuses never close the window', () async {
      for (final response in [
        _status('unfulfilled', paymentReceived: true),
        _status('processing', paymentReceived: true),
        _status('confirming'),
        _status('refunding'),
      ]) {
        final session = CashAppPurchaseSession(now: () => _start)
          ..begin(_onramp());
        await session.poll((_) async => response);
        expect(session.paymentWindowEnded, isFalse);
        expect(session.paymentReceived, isTrue);
      }
    });
  });

  group('stored purchase outside the payment sheet', () {
    test('a row that just closed needs the grace period and a fresh check',
        () async {
      final closedAt = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
      var now = closedAt.add(const Duration(seconds: 10));
      final row = _row(expiresAt: 1000);
      expect(row.cashAppPaymentWindowClosed, isTrue);
      final ids = <String>[];
      final session = CashAppPurchaseSession(
        now: () => now,
        storedOrders: () => [row],
      )..beginStored(row);
      expect(session.expiresAt, 1000);
      expect(session.paymentWindowEnded, isTrue);
      Future<OrchestraOrder?> fetch(String id) async {
        ids.add(id);
        return _status('processing');
      }

      await session.poll(fetch);
      expect(ids, ['ord_1']);
      expect(session.canOfferNewPurchase, isFalse);
      now = closedAt.add(_grace);
      await session.poll(fetch);
      expect(session.canOfferNewPurchase, isTrue);
    });

    test('a quote row is checked by its quote id', () async {
      final row = _row(id: 'q_1', status: 'unfulfilled');
      final ids = <String>[];
      final session = CashAppPurchaseSession()..beginStored(row);
      await session.poll((id) async {
        ids.add(id);
        return _status('unfulfilled');
      });
      expect(ids, ['q_1']);
      expect(session.canOfferNewPurchase, isTrue);
    });

    test('a payment recorded by background sync withdraws the offer',
        () async {
      final row = _row(expiresAt: 1000);
      var stored = [row];
      final session = CashAppPurchaseSession(storedOrders: () => stored)
        ..beginStored(row);
      await session.poll(_unpaid);
      expect(session.canOfferNewPurchase, isTrue);
      stored = [row.copyWith(id: 'ord_real', status: 'exchanging')];
      expect(session.canOfferNewPurchase, isFalse);
      expect(session.paymentReceived, isTrue);
    });
  });

  test('late responses for a replaced purchase are ignored', () async {
    for (final late in [
      _status('unfulfilled'),
      _status('processing', paymentReceived: true),
    ]) {
      final clock = _Clock();
      final session = CashAppPurchaseSession(now: () => clock.now);
      final first = _onramp(orderId: 'ord_old', invoice: 'lnbc1old');
      session.begin(first);
      final pending = Completer<OrchestraOrder?>();
      final stale = session.poll((_) => pending.future);

      final second = _onramp(
          orderId: 'ord_new', invoice: 'lnbc1new', expiresAt: _deadline);
      session.begin(second);
      final ids = <String>[];
      final fresh = await session.poll((id) async {
        ids.add(id);
        return _status('processing');
      });
      expect(ids, ['ord_new']);
      expect(fresh, isNotNull);

      pending.complete(late);
      expect(await stale, isNull);
      expect(session.isCurrent(second), isTrue);
      expect(session.isCurrent(first), isFalse);
      expect(session.paymentReceived, isFalse);
      expect(session.paymentWindowEnded, isFalse);
    }
  });
}

extension on OrchestraOnrampResponse {
  OrchestraOnrampResponse copyWithDeadline(DateTime deadline) =>
      OrchestraOnrampResponse(
        orderId: orderId,
        quoteId: quoteId,
        depositAddress: depositAddress,
        paymentLinks: paymentLinks,
        amountIn: amountIn,
        estimatedOut: estimatedOut,
        expiresAt: deadline.toIso8601String(),
      );
}
