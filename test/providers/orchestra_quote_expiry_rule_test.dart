import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/handlers/response_handlers.dart';
import 'package:kute/helpers/cash_app_purchase_session.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/api/orchestra_api.dart';

final _created = DateTime.utc(2026, 9, 1, 12);
final _expires = _created.add(const Duration(minutes: 2));

SwapOrder _row({
  String id = 'q_1',
  String status = 'wait',
  int? expiresAt,
  bool noExpiry = false,
  String? purchaseSource,
  DateTime? created,
}) =>
    SwapOrder(
      id: id,
      coinFrom: 'BTC',
      networkFrom: purchaseSource == 'cashapp' ? 'LIGHTNING' : 'SPARK',
      coinTo: purchaseSource == 'cashapp' ? 'BTC' : 'USDC.e',
      networkTo: purchaseSource == 'cashapp' ? 'SPARK' : 'POLYGON',
      depositAddress: 'deposit',
      depositAmount: '0.001',
      withdrawalAmount: '50',
      status: status,
      timestamp: (created ?? _created).millisecondsSinceEpoch,
      withdrawalAddress: '',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      expiresAt: noExpiry ? null : expiresAt ?? _expires.millisecondsSinceEpoch,
      purchaseSource: purchaseSource,
    );

Future<Result<OrchestraOrder>> _statusWith(
        Future<http.Response> Function(http.Request request) handler) =>
    http.runWithClient(
      () => OrchestraService.getStatus('q_1'),
      () => MockClient(handler),
    );

/// The body the backend's normalizeStatus returns for Flashnet's
/// `{quote, order: null}` reply (orchestra_orders.go parseOrchestraSnapshot).
String _normalizedNullOrder({
  required bool expired,
  bool paymentReceived = false,
}) =>
    jsonEncode({
      'order': null,
      'quote': {
        'id': 'q_1',
        'expired': expired,
        'expiresAt': _expires.toIso8601String(),
      },
      'status': expired ? 'unfulfilled' : 'pending',
      'normalizedStatus': 'pending',
      'expiresAt': _expires.toIso8601String(),
      if (paymentReceived) 'paymentReceived': true,
    });

const _ages = [
  Duration.zero,
  Duration(minutes: 5, seconds: 1),
  Duration(minutes: 31),
  Duration(hours: 2, minutes: 1),
  Duration(days: 1),
  Duration(days: 13),
  Duration(days: 40),
];

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
  });
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  group('status read classification', () {
    test('an order is an order', () async {
      final result = await _statusWith((request) async {
        expect(request.url.queryParameters['quoteId'], 'q_1');
        return http.Response(
            jsonEncode({
              'order': {'id': 'ord_1', 'status': 'processing'}
            }),
            200);
      });
      expect(
          classifyOrchestraStatusRead(result), OrchestraStatusReadKind.order);
      expect(result.statusCode, 200);
    });

    test('an HTTP 404 is a not-found read', () async {
      final result = await _statusWith(
          (_) async => http.Response('{"error":"not found"}', 404));
      expect(result.statusCode, 404);
      expect(classifyOrchestraStatusRead(result),
          OrchestraStatusReadKind.notFound);
    });

    test('a 200 with a null order is a not-found read that keeps the envelope',
        () async {
      final result = await _statusWith(
          (_) async => http.Response(_normalizedNullOrder(expired: true), 200));
      expect(result.isSuccess, isTrue);
      expect(result.data!.orderMissing, isTrue);
      expect(result.data!.status, 'unfulfilled');
      expect(DateTime.parse(result.data!.expiresAt!), _expires);
      expect(classifyOrchestraStatusRead(result),
          OrchestraStatusReadKind.notFound);
    });

    test('a null-order envelope with payment evidence is never not found',
        () async {
      final result = await _statusWith((_) async => http.Response(
          _normalizedNullOrder(expired: false, paymentReceived: true), 200));
      expect(result.data!.orderMissing, isTrue);
      expect(result.data!.paymentReceived, isTrue);
      expect(
          classifyOrchestraStatusRead(result), OrchestraStatusReadKind.order);
    });

    test('an order reply is not marked missing', () async {
      final result = await _statusWith((_) async => http.Response(
          jsonEncode({
            'order': {'id': 'ord_1', 'status': 'processing'}
          }),
          200));
      expect(result.data!.orderMissing, isFalse);
    });

    for (final code in [429, 500, 502, 503, 400]) {
      test('HTTP $code proves nothing', () async {
        final result =
            await _statusWith((_) async => http.Response('{}', code));
        expect(result.statusCode, code);
        expect(classifyOrchestraStatusRead(result),
            OrchestraStatusReadKind.unavailable);
      });
    }

    test('a rejected session with no re-authentication remains unavailable',
        () async {
      var requests = 0;
      final result = await _statusWith((_) async {
        requests++;
        return http.Response('{}', 401);
      });
      expect(requests, 1);
      expect(result.isSuccess, isFalse);
      expect(result.statusCode, isNull,
          reason: 'The session failure is surfaced before an HTTP retry.');
      expect(classifyOrchestraStatusRead(result),
          OrchestraStatusReadKind.unavailable);
    });

    test('a timeout proves nothing', () async {
      final result =
          await _statusWith((_) async => throw TimeoutException('slow'));
      expect(result.statusCode, isNull);
      expect(classifyOrchestraStatusRead(result),
          OrchestraStatusReadKind.unavailable);
    });

    test('a transport error proves nothing', () async {
      final result =
          await _statusWith((_) async => throw http.ClientException('offline'));
      expect(classifyOrchestraStatusRead(result),
          OrchestraStatusReadKind.unavailable);
    });
  });

  group('Cash App quote rows read the normalized null-order envelope', () {
    Future<OrchestraOrder?> fetchWith(String body) async {
      final result = await http.runWithClient(
        () => OrchestraService.getStatus('q_1'),
        () => MockClient((_) async => http.Response(body, 200)),
      );
      return result.isSuccess ? result.data : null;
    }

    OrchestraOnrampResponse quoteOnlyPurchase({String expiresAt = ''}) =>
        OrchestraOnrampResponse(
          orderId: '',
          quoteId: 'q_1',
          depositAddress: '',
          paymentLinks: OrchestraPaymentLinks(cashApp: '', shortUrl: ''),
          amountIn: '50',
          estimatedOut: '0.0005',
          expiresAt: expiresAt,
        );

    test('a paid purchase past its deadline shows the payment', () async {
      var now = _created;
      final session = CashAppPurchaseSession(now: () => now)
        ..begin(quoteOnlyPurchase(expiresAt: _expires.toIso8601String()));
      now = _expires.add(const Duration(minutes: 10));
      final data = await session.poll(
          (_) => fetchWith(
              _normalizedNullOrder(expired: false, paymentReceived: true)),
          force: true);
      expect(data, isNotNull);
      expect(session.paymentReceived, isTrue);
      expect(session.paymentWindowEnded, isFalse);
      expect(
          legacyStatusReadAction(
            row: _row(purchaseSource: 'cashapp'),
            read: OrchestraStatusReadKind.order,
            now: now,
          ),
          LegacyStatusReadAction.apply);
    });

    test('an unfulfilled envelope closes the window and restores the expiry',
        () async {
      var now = _created;
      final session = CashAppPurchaseSession(now: () => now)
        ..begin(quoteOnlyPurchase());
      expect(session.paymentWindowEnded, isFalse);
      now = _expires.add(const Duration(minutes: 1));
      final data = await session.poll(
          (_) => fetchWith(_normalizedNullOrder(expired: true)),
          force: true);
      expect(session.paymentWindowEnded, isTrue);
      expect(DateTime.tryParse(data!.expiresAt ?? '')?.millisecondsSinceEpoch,
          _expires.millisecondsSinceEpoch);
    });

    test('a swap quote row is still expired only after the 30 min grace',
        () async {
      final result = await _statusWith(
          (_) async => http.Response(_normalizedNullOrder(expired: true), 200));
      final read = classifyOrchestraStatusRead(result);
      expect(
          legacyStatusReadAction(
              row: _row(),
              read: read,
              now: _expires.add(const Duration(minutes: 29))),
          LegacyStatusReadAction.keep);
      expect(
          legacyStatusReadAction(
              row: _row(),
              read: read,
              now: _expires.add(const Duration(minutes: 31))),
          LegacyStatusReadAction.markExpired);
    });
  });

  group('legacy q_ expiry rule', () {
    for (final age in _ages) {
      test('a failed read never expires a quote row at age $age', () {
        final action = legacyStatusReadAction(
          row: _row(),
          read: OrchestraStatusReadKind.unavailable,
          now: _created.add(age),
        );
        expect(action, LegacyStatusReadAction.keep);
      });
    }

    test('a not-found read before expiry plus 30 min keeps the row', () {
      for (final now in [
        _created.add(const Duration(minutes: 6)),
        _expires.add(const Duration(minutes: 29, seconds: 59)),
        _expires.add(kLegacyQuoteNotFoundGrace),
      ]) {
        expect(
          legacyStatusReadAction(
              row: _row(), read: OrchestraStatusReadKind.notFound, now: now),
          LegacyStatusReadAction.keep,
          reason: '$now',
        );
      }
    });

    test('a not-found read after expiry plus 30 min marks it expired', () {
      expect(
        legacyStatusReadAction(
          row: _row(),
          read: OrchestraStatusReadKind.notFound,
          now: _expires.add(const Duration(minutes: 30, seconds: 1)),
        ),
        LegacyStatusReadAction.markExpired,
      );
    });

    test('without an expiry the grace is 2 h after creation', () {
      final row = _row(noExpiry: true);
      expect(
        legacyStatusReadAction(
            row: row,
            read: OrchestraStatusReadKind.notFound,
            now: _created.add(const Duration(hours: 1, minutes: 59))),
        LegacyStatusReadAction.keep,
      );
      expect(
        legacyStatusReadAction(
            row: row,
            read: OrchestraStatusReadKind.notFound,
            now: _created.add(const Duration(hours: 2, minutes: 1))),
        LegacyStatusReadAction.markExpired,
      );
    });

    test('an order is always applied', () {
      expect(
        legacyStatusReadAction(
            row: _row(status: 'expired'),
            read: OrchestraStatusReadKind.order,
            now: _created.add(const Duration(days: 5))),
        LegacyStatusReadAction.apply,
      );
    });

    test('Cash App rows are untouched', () {
      for (final read in OrchestraStatusReadKind.values) {
        if (read == OrchestraStatusReadKind.order) continue;
        for (final age in _ages) {
          expect(
            legacyStatusReadAction(
              row: _row(purchaseSource: 'cashapp'),
              read: read,
              now: _created.add(age),
            ),
            LegacyStatusReadAction.keep,
          );
        }
      }
    });

    test('order rows are never expired by a read', () {
      expect(
        legacyStatusReadAction(
          row: _row(id: 'ord_1'),
          read: OrchestraStatusReadKind.notFound,
          now: _created.add(const Duration(days: 3)),
        ),
        LegacyStatusReadAction.keep,
      );
    });
  });

  group('expired quote rows stay on the slow check', () {
    test('an expired q_ row is still checked until 14 days', () {
      final row = _row(status: 'expired');
      expect(row.shouldPollOrchestra, isFalse);
      expect(
          legacyOrchestraRowNeedsStatusCheck(
              row, _created.add(const Duration(days: 13, hours: 23))),
          isTrue);
      expect(
          legacyOrchestraRowNeedsStatusCheck(
              row, _created.add(const Duration(days: 14))),
          isFalse);
    });

    test('Cash App and order rows are not added', () {
      final now = _created.add(const Duration(days: 1));
      expect(
          legacyExpiredQuoteStillWatched(
              _row(status: 'expired', purchaseSource: 'cashapp'), now),
          isFalse);
      expect(
          legacyExpiredQuoteStillWatched(
              _row(id: 'ord_1', status: 'expired'), now),
          isFalse);
      expect(legacyExpiredQuoteStillWatched(_row(status: 'success'), now),
          isFalse);
    });

    test('an expired q_ row is checked daily', () {
      var now = _created.add(const Duration(days: 1));
      final schedule = LegacyExpiredQuoteSchedule(now: () => now);
      final row = _row(status: 'expired');
      expect(schedule.begin(row), isTrue);
      schedule.recordRead(row.id, OrchestraStatusReadKind.notFound);
      now = now.add(const Duration(hours: 23));
      expect(schedule.begin(row), isFalse);
      now = now.add(const Duration(hours: 1));
      expect(schedule.begin(row), isTrue);
    });

    test('a clock moved back never delays the next check', () {
      var now = _created.add(const Duration(days: 2));
      final schedule = LegacyExpiredQuoteSchedule(now: () => now);
      final row = _row(status: 'expired');
      expect(schedule.begin(row), isTrue);
      now = now.subtract(const Duration(hours: 3));
      expect(schedule.begin(row), isTrue);
    });

    test('pending rows are always due while reads answer', () {
      final schedule = LegacyExpiredQuoteSchedule(now: () => _created);
      final row = _row();
      for (var i = 0; i < 3; i++) {
        expect(schedule.begin(row), isTrue);
        schedule.recordRead(row.id, OrchestraStatusReadKind.notFound);
      }
    });

    test('a failed daily check is retried once after a minute', () {
      var now = _created.add(const Duration(days: 1));
      final schedule = LegacyExpiredQuoteSchedule(now: () => now);
      final row = _row(status: 'expired');
      expect(schedule.begin(row), isTrue);
      now = now.add(const Duration(seconds: 59));
      expect(schedule.begin(row), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(schedule.begin(row), isTrue);
      now = now.add(const Duration(minutes: 5));
      expect(schedule.begin(row), isFalse);
      now = now.add(const Duration(days: 1));
      expect(schedule.begin(row), isTrue);
    });

    test('a pending row backs off after repeated failed reads', () {
      var now = _created.add(const Duration(hours: 2));
      final schedule = LegacyExpiredQuoteSchedule(now: () => now);
      final row = _row();
      expect(schedule.begin(row), isTrue);
      now = now.add(const Duration(seconds: 5));
      expect(schedule.begin(row), isTrue);
      now = now.add(const Duration(seconds: 5));
      expect(schedule.begin(row), isFalse);
      now = now.add(const Duration(minutes: 5));
      expect(schedule.begin(row), isFalse);
      now = now.add(const Duration(minutes: 5));
      expect(schedule.begin(row), isTrue);
      schedule.recordRead(row.id, OrchestraStatusReadKind.order);
      now = now.add(const Duration(seconds: 5));
      expect(schedule.begin(row), isTrue);
    });

    test('Cash App and order rows are never paced', () {
      final schedule = LegacyExpiredQuoteSchedule(
          now: () => _created.add(const Duration(hours: 2)));
      for (final row in [_row(purchaseSource: 'cashapp'), _row(id: 'ord_1')]) {
        for (var i = 0; i < 4; i++) {
          expect(schedule.begin(row), isTrue);
        }
      }
    });
  });

  group('outcomes after a local expiry', () {
    final now = _created.add(const Duration(days: 3));

    test('a late success or refund of a watched expired row is new', () {
      final row = _row(status: 'expired');
      expect(legacyExpiredQuoteNewOutcome(row, 'success', now), isTrue);
      expect(legacyExpiredQuoteNewOutcome(row, 'refunded', now), isTrue);
    });

    test('a repeated expiry or a pending read is not', () {
      final row = _row(status: 'expired');
      expect(legacyExpiredQuoteNewOutcome(row, 'expired', now), isFalse);
      expect(legacyExpiredQuoteNewOutcome(row, 'wait', now), isFalse);
    });

    test('rows outside the watch keep their terminal status', () {
      expect(
          legacyExpiredQuoteNewOutcome(_row(status: 'expired'), 'success',
              _created.add(const Duration(days: 15))),
          isFalse);
      expect(
          legacyExpiredQuoteNewOutcome(
              _row(id: 'ord_1', status: 'expired'), 'success', now),
          isFalse);
      expect(
          legacyExpiredQuoteNewOutcome(_row(status: 'success'), 'success', now),
          isFalse);
    });
  });
}
