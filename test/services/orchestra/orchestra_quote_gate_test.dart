import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _flashnetEvm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

final _now = DateTime.utc(2026, 9, 15, 12);

Map<String, dynamic> _fixture() => jsonDecode(
        File('test/services/fixtures/orchestra_quote_spark_to_polygon.json')
            .readAsStringSync())
    as Map<String, dynamic>;

final _request = OrchestraQuoteRequest(
  sourceChain: 'spark',
  sourceAsset: 'BTC',
  destinationChain: 'polygon',
  destinationAsset: 'USDC.e',
  amountBaseUnits: BigInt.from(100000),
  recipientAddress: _pmWallet,
  refundAddress: _ownSpark,
  recipientKind: RecipientKind.ownPmWallet,
  ownAddress: _pmWallet,
);

final _bounds =
    OrchestraQuoteBounds.forSource('spark', inputValueInOutputUnits: 60000000);

void main() {
  final events = <(String, Map<String, Object>?)>[];
  // The per-request reliability and latency events, kept apart from the
  // guard events.
  final quoteResults = <Map<String, Object>?>[];
  final latencies = <Map<String, Object>?>[];
  final posted = <Map<String, dynamic>>[];

  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    resetOrchestraDecimalsForTest();
    events.clear();
    quoteResults.clear();
    latencies.clear();
    posted.clear();
    TrackingService.debugTrackObserver = (e, p) => switch (e) {
          'orchestra_quote_result' => quoteResults.add(p),
          LatencyKeys.quoteRoundtrip => latencies.add(p),
          _ => events.add((e, p)),
        };
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
    resetOrchestraDecimalsForTest();
  });

  MockClient quoting(Map<String, dynamic> body, {int status = 200}) =>
      MockClient((req) async {
        expect(req.url.path, '/api/v1/orchestra/quote');
        posted.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(body), status);
      });

  Future<VerifiedOrchestraQuote> fetch(http.Client client) =>
      http.runWithClient(
        () => OrchestraQuoteGate.fetchVerified(_request, _bounds,
            flow: 'move_predictions', clock: () => _now),
        () => client,
      );

  group('fetchVerified', () {
    test('returns a verified quote and posts the request values', () async {
      final verified = await fetch(quoting(_fixture()));
      expect(verified.quoteId, 'q_fixture_spark_polygon');
      expect(verified.amountIn, BigInt.from(100000));
      expect(posted.single['amount'], '100000');
      expect(posted.single['recipientAddress'], _pmWallet);
      expect(posted.single['refundAddress'], _ownSpark);
      expect(posted.single['sourceAsset'], 'BTC');
      expect(events, isEmpty);
      expect(quoteResults.single, {
        'source_chain': 'spark',
        'source_asset': 'BTC',
        'destination_chain': 'polygon',
        'destination_asset': 'USDC.e',
        'outcome': 'ok',
        'status_class': '2xx',
      });
      expect(latencies.single?['outcome'], 'ok');
      expect(latencies.single?['duration_ms'], isA<int>());
    });

    test('never returns an unverified quote', () async {
      final hostile = <String, Object>{
        'depositAddress': _flashnetEvm,
        'depositMemo': 'memo',
        'amountIn': '100001',
        'expiresAt': _now.toIso8601String(),
        'feeBps': 900,
        // No output floor since 6bf6be95, so a low estimate alone is not
        // hostile; a malformed one is.
        'estimatedOut': 'lots',
        'destinationChain': 'arbitrum',
      };
      for (final entry in hostile.entries) {
        final body = _fixture()..[entry.key] = entry.value;
        await expectLater(fetch(quoting(body)),
            throwsA(isA<WalletGuardException>()),
            reason: entry.key);
      }
      expect(events, hasLength(hostile.length));
      // The round-trip itself succeeded every time; only the guard refused.
      expect(latencies, hasLength(hostile.length));
      expect(latencies.map((p) => p?['outcome']), everyElement('ok'));
    });

    test('a rejection emits one event with no amounts or addresses', () async {
      final body = _fixture()..['depositAddress'] = _flashnetEvm;
      await expectLater(
          fetch(quoting(body)),
          throwsA(isA<WalletGuardException>().having((e) => e.reason,
              'reason', WalletGuardReason.depositAddressFormat)));
      expect(events, hasLength(1));
      final (name, params) = events.single;
      expect(name, 'orchestra_quote_rejected');
      expect(params, {
        'flow': 'move_predictions',
        'route': 'spark_btc>polygon_usdc.e',
        'reason': 'deposit_address_format',
      });
    });

    test('a failed request is a quote failure, not a guard rejection',
        () async {
      await expectLater(
          fetch(quoting({
            'error': {'message': 'upstream down'}
          }, status: 502)),
          throwsA(isA<OrchestraQuoteFailure>()
              .having((e) => e.message, 'message', 'upstream down')));
      expect(events, isEmpty);
      expect(quoteResults.single?['outcome'], 'error');
      expect(quoteResults.single?['status_class'], '5xx');
      expect(latencies.single?['outcome'], 'error');
    });

    test('a decimals mismatch refuses the route before quoting', () async {
      setOrchestraDecimalsCatalog(OrchestraRoutesCatalog.fromJson(
        {
          'assets': [
            {
              'id': 'spark:BTC',
              'chain': 'spark',
              'asset': 'BTC',
              'decimals': 8,
              'route': {
                'to': ['polygon:USDC.e']
              },
            },
            {
              'id': 'polygon:USDC.e',
              'chain': 'polygon',
              'asset': 'USDC.e',
              'decimals': 18,
              'route': {
                'to': ['spark:BTC']
              },
            },
          ],
        },
        source: OrchestraCatalogSource.live,
      ));
      events.clear();
      await expectLater(
          fetch(quoting(_fixture())),
          throwsA(isA<WalletGuardException>().having((e) => e.reason,
              'reason', WalletGuardReason.decimalsMismatch)));
      expect(posted, isEmpty);
      expect(latencies, isEmpty);
      expect(events.single.$2?['reason'], 'decimals_mismatch');
    });
  });

  group('ensurePayable', () {
    late VerifiedOrchestraQuote verified;

    setUp(() async {
      verified = await fetch(quoting(_fixture()));
    });

    test('passes for the quoted amount inside the margin', () {
      expect(
          () => OrchestraQuoteGate.ensurePayable(verified,
              amountBaseUnits: BigInt.from(100000),
              now: _now.add(const Duration(seconds: 100))),
          returnsNormally);
    });

    test('rejects expiry at the margin', () {
      expect(
          () => OrchestraQuoteGate.ensurePayable(verified,
              amountBaseUnits: BigInt.from(100000),
              now: _now.add(const Duration(seconds: 105))),
          throwsA(isA<WalletGuardException>().having(
              (e) => e.reason, 'reason', WalletGuardReason.quoteExpired)));
    });

    test('rejects an amount drift', () {
      expect(
          () => OrchestraQuoteGate.ensurePayable(verified,
              amountBaseUnits: BigInt.from(100001), now: _now),
          throwsA(isA<WalletGuardException>().having(
              (e) => e.reason, 'reason', WalletGuardReason.amountMismatch)));
    });
  });
}
