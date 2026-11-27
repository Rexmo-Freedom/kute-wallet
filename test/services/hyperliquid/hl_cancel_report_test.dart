// The batch cancel answer read per order, against the venue's documented
// shapes (Hyperliquid docs, Exchange endpoint, "Cancel order(s)"):
//   success: {"status":"ok","response":{"type":"cancel","data":
//            {"statuses":["success"]}}}
//   error:   ... "statuses":[{"error":"Order was never placed, already
//            canceled, or filled."}]
// An order no longer resting is done (not a failure, not counted as
// cancelled); any other error stays open; an unclear envelope throws.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';

const _gone = 'Order was never placed, already canceled, or filled.';

Map<String, dynamic> _body(List<Object> statuses,
        {String status = 'ok', String type = 'cancel'}) =>
    {
      'status': status,
      'response': {
        'type': type,
        'data': {'statuses': statuses}
      }
    };

const _three = [
  (assetId: 0, oid: 31),
  (assetId: 0, oid: 32),
  (assetId: 0, oid: 33),
];

void main() {
  test('success, already gone and refused are told apart per order', () {
    final r = HyperliquidExchangeService.cancelReportFromBody(
        _body([
          'success',
          {'error': _gone},
          {'error': 'Rate limited.'},
        ]),
        _three);
    expect(r.cancelled, [31]);
    expect(r.gone, [32]);
    expect(r.failed.map((f) => f.oid), [33]);
    expect(r.failed.single.reason, 'Rate limited.');
    expect(r.done, {31, 32});
  });

  test('every order already gone: nothing cancelled, nothing failed', () {
    final r = HyperliquidExchangeService.cancelReportFromBody(
        _body([
          {'error': _gone}
        ]),
        const [(assetId: 0, oid: 31)]);
    expect(r.cancelled, isEmpty);
    expect(r.failed, isEmpty);
    expect(r.gone, [31]);
  });

  test('an unclear acknowledgement is never read as done', () {
    for (final body in [
      _body(['success', 'success']), // one status missing
      _body(['success', 'success', 'success', 'success']), // one extra
      _body(['success', 'success', 'resting']), // unknown status
      _body(['success', 'success', {'error': ''}]),
      _body(['success', 'success', 'success'], status: 'err'),
      _body(['success', 'success', 'success'], type: 'order'),
    ]) {
      expect(() => HyperliquidExchangeService.cancelReportFromBody(body, _three),
          throwsA(isA<HyperliquidApiException>()),
          reason: '$body');
    }
  });

  test('the gone wording is matched, other errors are not', () {
    expect(hlCancelErrorMeansGone(_gone), isTrue);
    expect(hlCancelErrorMeansGone('Order was already cancelled'), isTrue);
    expect(hlCancelErrorMeansGone('Rate limited.'), isFalse);
    expect(hlCancelErrorMeansGone('Insufficient margin'), isFalse);
  });
}
