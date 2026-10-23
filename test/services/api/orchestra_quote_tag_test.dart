// The provider-side `tag` on a quote: set on `OrchestraQuoteRequest`, it
// reaches the `/quote` body as the `tag` field through the quote gate;
// left null, the body carries no such field at all.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../../helpers/runtime_policy_fixture.dart';

final _quoteBody = jsonEncode({
  'quoteId': 'q_1',
  'depositAddress': 'deposit',
  'amountIn': '10000',
  'estimatedOut': '6000000',
  'feeAmount': '0',
  'feeBps': 0,
  'expiresAt': '2026-09-01T12:02:00Z',
});

/// Replies to every `/quote` and records each request body.
class _Recorder {
  final bodies = <Map<String, dynamic>>[];

  MockClient get client => MockClient((request) async {
        if (request.url.path.endsWith('/quote')) {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response(_quoteBody, 200);
      });
}

OrchestraQuoteRequest _request({String? tag}) => OrchestraQuoteRequest(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: 'polygon',
      destinationAsset: 'USDC.e',
      amountBaseUnits: BigInt.from(10000),
      recipientAddress: 'recipient',
      refundAddress: 'refund',
      recipientKind: RecipientKind.external,
      tag: tag,
    );

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
  });

  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  test('createQuote sends the tag as the body field `tag`', () async {
    final recorder = _Recorder();
    await http.runWithClient(
      () => OrchestraService.createQuote(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'polygon',
        destinationAsset: 'USDC.e',
        amount: '10000',
        recipientAddress: 'recipient',
        refundAddress: 'refund',
        tag: 'kute:manual_move',
      ),
      () => recorder.client,
    );
    expect(recorder.bodies.single['tag'], 'kute:manual_move');
  });

  test('createQuote without a tag sends no `tag` field', () async {
    final recorder = _Recorder();
    await http.runWithClient(
      () => OrchestraService.createQuote(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'polygon',
        destinationAsset: 'USDC.e',
        amount: '10000',
        recipientAddress: 'recipient',
        refundAddress: 'refund',
      ),
      () => recorder.client,
    );
    expect(recorder.bodies.single.containsKey('tag'), isFalse);
  });

  test("the quote gate forwards the request's tag, and only when set",
      () async {
    final recorder = _Recorder();
    Future<void> fetch(OrchestraQuoteRequest request) async {
      try {
        await http.runWithClient(
          () => OrchestraQuoteGate.fetchVerifiedWithSkew(
            request,
            OrchestraQuoteBounds.forSource(request.sourceChain,
                inputValueInOutputUnits: null),
            flow: 'test',
            idempotencyKey: 'k',
            retryTransport: false,
            clock: () => DateTime.utc(2026, 9, 1, 12),
          ),
          () => recorder.client,
        );
      } catch (_) {
        // Only the request body matters here; what the guard makes of the
        // canned reply is its own tests' business.
      }
    }

    await fetch(_request(tag: 'kute:sweep_predictions'));
    await fetch(_request());
    expect(recorder.bodies, hasLength(2));
    expect(recorder.bodies[0]['tag'], 'kute:sweep_predictions');
    expect(recorder.bodies[1].containsKey('tag'), isFalse);
  });

  test('one-balance tags name the purpose and the venue', () {
    expect(oneBalanceQuoteTag('order_funding', venue: 'investing'),
        'kute:order_funding_investing');
    expect(oneBalanceQuoteTag('sweep', venue: 'investing'),
        'kute:sweep_investing');
    expect(oneBalanceQuoteTag('rollout_sweep', venue: 'investing'),
        'kute:rollout_sweep_investing');
    expect(oneBalanceQuoteTag('order_funding', venue: 'predictions'),
        'kute:order_funding_predictions');
    expect(oneBalanceQuoteTag('manual_move', venue: 'investing'),
        kManualMoveQuoteTag);
    expect(kManualMoveQuoteTag, 'kute:manual_move');
  });
}
