import '../helpers/runtime_policy_fixture.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _pubkey =
    '02a1633cafcc01ebfb6d78e39f687a1f0995c62fc95f51ead10a02ee0be551b5dc';
final _nonce = 'ab' * 32;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];
  final events = <(String, Map<String, Object>?)>[];
  final valid = <String>{};
  var mints = 0;
  var acceptNewSessions = true;
  var walletAuthStatus = 200;

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    FlutterSecureStorage.setMockInitialValues({
      'kute_affiliate_session_address':
          jsonEncode({'pubkey': _pubkey, 'address': 'alice@paykute.com'}),
    });
    AppsFlyerService.clearCapturedReferrer();
    WalletIdentityService.debugBind(
        pubkey: _pubkey, signer: (_) async => 'cd' * 65);
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    requests.clear();
    events.clear();
    valid.clear();
    mints = 0;
    acceptNewSessions = true;
    walletAuthStatus = 200;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    WalletIdentityService.debugBind(pubkey: null);
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
  });

  String challenge() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'kute-auth-v2|$_pubkey|$_nonce|$now|${now + 300}';
  }

  /// Backend where protected routes answer 401 unless the bearer is valid,
  /// and auth/wallet mints `fresh-N`.
  MockClient backend() => MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (path == '/api/v1/affiliate/auth/challenge') {
          return http.Response(jsonEncode({'challenge': challenge()}), 200);
        }
        if (path == '/api/v1/affiliate/auth/wallet') {
          if (walletAuthStatus != 200) {
            return http.Response('{"error":"invalid signature"}', walletAuthStatus);
          }
          final token = 'fresh-${++mints}';
          if (acceptNewSessions) valid.add(token);
          return http.Response(jsonEncode({'session_token': token}), 200);
        }
        if (req.url.host != 'backend.test') {
          return http.Response('{}', 200);
        }
        final bearer = req.headers['Authorization'];
        if (bearer == null || !valid.contains(bearer.substring(7))) {
          return http.Response('{"error":"invalid session"}', 401);
        }
        return http.Response('{}', 200);
      });

  Future<T> withBackend<T>(Future<T> Function() body) =>
      http.runWithClient(body, backend);

  List<http.Request> routeCalls(String suffix) =>
      requests.where((r) => r.url.path.endsWith(suffix)).toList();

  int walletAuths() => routeCalls('/affiliate/auth/wallet').length;

  final unavailable = l10nForLanguage('en').walletSessionUnavailable;

  test('every Orchestra client call carries the session bearer', () async {
    AffiliateService.debugSessionToken = 'tok';
    valid.add('tok');
    await withBackend(() async {
      await OrchestraService.getRoutesRaw();
      await OrchestraService.getOnrampLimits();
      await OrchestraService.createOnramp(
          destinationChain: 'spark',
          destinationAsset: 'BTC',
          recipientAddress: 'r',
          amountFiatUsd: '10.00');
      await OrchestraService.getEstimate(
          sourceChain: 'spark',
          sourceAsset: 'BTC',
          destinationChain: 'polygon',
          destinationAsset: 'USDC',
          amount: '1');
      await OrchestraService.createQuote(
          sourceChain: 'spark',
          sourceAsset: 'BTC',
          destinationChain: 'polygon',
          destinationAsset: 'USDC',
          amount: '1',
          recipientAddress: 'r',
          refundAddress: 'f');
      await OrchestraService.submitDeposit(quoteId: 'q_1', sparkTxHash: 'h');
      await OrchestraService.getStatus('q_1');
      await OrchestraService.getHistory('a');
      await OrchestraService.createAccumulationAddress(
          sourceChain: 'arbitrum',
          sourceAsset: 'USDC',
          destinationAsset: 'BTC',
          recipientSparkAddress: 's');
      await OrchestraService.getAccumulationAddresses();
      await OrchestraService.deleteAccumulationAddress('a1');
      await OrchestraService.createLiquidationAddress(
          destinationChain: 'polygon',
          destinationAsset: 'USDC',
          destinationAddress: 'd');
      await OrchestraService.getLiquidationAddresses();
      await OrchestraService.deleteLiquidationAddress('l1');
      await OrchestraService.createPayLink(
          destinationChain: 'polygon',
          destinationAsset: 'USDC',
          recipientAddress: 'r',
          amountOut: '1');
      await OrchestraService.getPayLinks();
      await OrchestraService.deletePayLink('p1');
    });

    final toBackend =
        requests.where((r) => r.url.host == 'backend.test').toList();
    expect(toBackend.map((r) => '${r.method} ${r.url.path}'), [
      'GET /api/v1/orchestra/routes',
      'GET /api/v1/orchestra/limits',
      'POST /api/v1/orchestra/onramp',
      'GET /api/v1/orchestra/estimate',
      'POST /api/v1/orchestra/quote',
      'POST /api/v1/orchestra/submit',
      'GET /api/v1/orchestra/status',
      'GET /api/v1/orchestra/history',
      'POST /api/v1/orchestra/accumulation-addresses',
      'GET /api/v1/orchestra/accumulation-addresses',
      'DELETE /api/v1/orchestra/accumulation-addresses/a1',
      'POST /api/v1/orchestra/liquidation-addresses',
      'GET /api/v1/orchestra/liquidation-addresses',
      'DELETE /api/v1/orchestra/liquidation-addresses/l1',
      'POST /api/v1/orchestra/pay-links',
      'GET /api/v1/orchestra/pay-links',
      'DELETE /api/v1/orchestra/pay-links/p1',
    ]);
    for (final r in toBackend) {
      expect(r.headers['Authorization'], 'Bearer tok', reason: r.url.path);
    }
    // The public Flashnet fallback never sees the backend token.
    for (final r in requests.where((r) => r.url.host != 'backend.test')) {
      expect(r.headers.containsKey('Authorization'), isFalse);
    }
    expect(walletAuths(), 0);
  });

  test('a session is minted with the hot wallet identity before the first call',
      () async {
    await withBackend(() => OrchestraService.createOnramp(
        destinationChain: 'bitcoin',
        destinationAsset: 'BTC',
        recipientAddress: 'bc1qcold',
        amountFiatUsd: '25.00'));
    expect(requests.map((r) => r.url.path), [
      '/api/v1/affiliate/auth/challenge',
      '/api/v1/affiliate/auth/wallet',
      '/api/v1/orchestra/onramp',
    ]);
    final wallet = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(wallet['pubkey'], _pubkey);
    expect(wallet['paykute_address'], 'alice@paykute.com');
    expect(requests.last.headers['Authorization'], 'Bearer fresh-1');
  });

  test('a 401 re-authenticates once and resends submit with the same key',
      () async {
    AffiliateService.debugSessionToken = 'stale';
    final result = await withBackend(() =>
        OrchestraService.submitDeposit(quoteId: 'q_1', sparkTxHash: 'h'));

    final submits = routeCalls('/orchestra/submit');
    expect(submits, hasLength(2));
    expect(submits.map((r) => r.headers['Authorization']),
        ['Bearer stale', 'Bearer fresh-1']);
    final key = submits.first.headers['X-Idempotency-Key'];
    expect(key, isNotNull);
    expect(submits.last.headers['X-Idempotency-Key'], key);
    expect(submits.last.body, submits.first.body);
    expect(walletAuths(), 1);
    expect(result.error, isNull);
    expect(events.where((e) => e.$1 == 'wallet_session_auth').map((e) => e.$2),
        [
          {'route': 'orchestra', 'outcome': 'reauth'}
        ]);
  });

  test('a caller idempotency key is kept on the retry', () async {
    AffiliateService.debugSessionToken = 'stale';
    await withBackend(() => OrchestraService.createQuote(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'polygon',
        destinationAsset: 'USDC',
        amount: '1',
        recipientAddress: 'r',
        refundAddress: 'f',
        idempotencyKey: 'key-1'));
    expect(routeCalls('/orchestra/quote').map((r) => r.headers['X-Idempotency-Key']),
        ['key-1', 'key-1']);
  });

  test('a second 401 is returned, never retried again', () async {
    AffiliateService.debugSessionToken = 'stale';
    acceptNewSessions = false;
    final result = await withBackend(() =>
        OrchestraService.submitDeposit(quoteId: 'q_1', sparkTxHash: 'h'));
    expect(routeCalls('/orchestra/submit'), hasLength(2));
    expect(walletAuths(), 1);
    expect(result.error, isNotNull);
  });

  test('a failed re-auth shows localized copy and does not resend', () async {
    AffiliateService.debugSessionToken = 'stale';
    walletAuthStatus = 401;
    final result = await withBackend(() =>
        OrchestraService.submitDeposit(quoteId: 'q_1', sparkTxHash: 'h'));
    expect(routeCalls('/orchestra/submit'), hasLength(1));
    expect(result.error, unavailable);
    expect(events.where((e) => e.$1 == 'wallet_session_auth').map((e) => e.$2),
        [
          {'route': 'orchestra', 'outcome': 'reauth_failed'}
        ]);
  });

  test('concurrent 401s share one re-auth', () async {
    AffiliateService.debugSessionToken = 'stale';
    await withBackend(() => Future.wait([
          OrchestraService.getStatus('q_1'),
          OrchestraService.getStatus('q_2'),
        ]));
    expect(walletAuths(), 1);
    expect(
        requests
            .where((r) => r.headers['Authorization'] == 'Bearer fresh-1')
            .length,
        2);
  });

  group('without a hot wallet identity', () {
    setUp(() => WalletIdentityService.debugBind(pubkey: null));

    test('payments show localized copy and call no backend route', () async {
      final onramp = await withBackend(() => OrchestraService.createOnramp(
          destinationChain: 'bitcoin',
          destinationAsset: 'BTC',
          recipientAddress: 'bc1qcold',
          amountFiatUsd: '25.00'));
      final submit = await withBackend(() =>
          OrchestraService.submitDeposit(quoteId: 'q_1', sparkTxHash: 'h'));
      expect([onramp.error, submit.error], [unavailable, unavailable]);
      expect(requests, isEmpty);
      expect(
          events.where((e) => e.$1 == 'wallet_session_auth').map((e) => e.$2),
          [
            {'route': 'orchestra', 'outcome': 'unavailable'},
            {'route': 'orchestra', 'outcome': 'unavailable'},
          ]);
    });

    test('the route catalog falls back to the public host only', () async {
      await withBackend(OrchestraService.getRoutesRaw);
      expect(requests.map((r) => r.url.host), ['orchestration.flashnet.xyz']);
    });
  });
}
