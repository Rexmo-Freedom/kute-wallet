// A first-time Predictions user: the account start, the wallet's own
// provisioning at unlock and the first deposit's conversion all reach the
// deposit wallet at once. Before, the second setup and a conversion batch
// each refused the approvals batch (`busy`), the account never became
// ready, and the slip sat on "Setting up your Predictions wallet…" and then
// stopped with nothing said. Network fakes only: nothing is really signed
// for or sent.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _eoa = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _key = '0123456789012345678901234567890123456789012345678901234567890123';

/// The relayer, the backend relay and Polygon RPC for one deployed
/// deposit wallet whose approvals are all missing until a batch lands.
class _Chain {
  _Chain({this.holdFirstNonce});

  /// When set, the first nonce read waits for it (a conversion batch
  /// caught mid-flight).
  final Completer<void>? holdFirstNonce;
  var nonceReads = 0;
  var submits = 0;
  var allowanceReads = 0;
  final submittedCalls = <int>[];
  var approvalsLanded = false;

  Future<http.Response> handle(http.Request request) async {
    final url = request.url;
    if (url.host == 'relayer-v2.polymarket.com') {
      if (url.path == '/deployed') {
        return http.Response(jsonEncode({'deployed': true}), 200);
      }
      if (url.path == '/v1/account/transactions/params') {
        nonceReads++;
        if (nonceReads == 1 && holdFirstNonce != null) {
          await holdFirstNonce!.future;
        }
        return http.Response(jsonEncode({'nonce': '$nonceReads'}), 200);
      }
      if (url.path == '/transaction') {
        approvalsLanded = true;
        return http.Response(
            jsonEncode([
              {
                'transactionID': url.queryParameters['id'],
                'state': 'STATE_CONFIRMED',
                'transactionHash': '0x${'b' * 64}',
              }
            ]),
            200);
      }
    }
    if (url.host == 'backend.test' && url.path.endsWith('/submit')) {
      submits++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      submittedCalls.add(
          ((body['depositWalletParams'] as Map)['calls'] as List).length);
      return http.Response(jsonEncode({'transactionID': 'tx_$submits'}), 200);
    }
    if (request.method == 'POST' && request.body.contains('jsonrpc')) {
      final rpc = jsonDecode(request.body) as Map<String, dynamic>;
      if (rpc['method'] == 'eth_chainId') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x89'}), 200);
      }
      if (rpc['method'] == 'eth_getCode') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x6080'}), 200);
      }
      if (rpc['method'] == 'eth_call') {
        allowanceReads++;
        final word = approvalsLanded ? '1'.padLeft(64, '0') : '0' * 64;
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x$word'}), 200);
      }
    }
    return http.Response('unexpected ${request.method} $url', 500);
  }
}

void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    WalletIdentityService.debugBind(pubkey: null);
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() => AffiliateService.debugSessionToken = null);

  test(
      'the account start and the unlock provisioning share one setup: '
      'one approvals batch, both ready', () async {
    final chain = _Chain();
    final wallets = await http.runWithClient(
      () => Future.wait([
        PolymarketOnboardingService()
            .enableTrading(eoaAddress: _eoa, privateKey: _key),
        PolymarketOnboardingService()
            .enableTrading(eoaAddress: _eoa, privateKey: _key),
      ]),
      () => MockClient(chain.handle),
    );
    expect(wallets[0], wallets[1]);
    // Before, the second setup scanned the same missing approvals and its
    // batch was refused as busy, failing the account's readiness.
    expect(chain.submits, 1);
    expect(chain.nonceReads, 1);
    expect(chain.submittedCalls.single, greaterThan(0));
  });

  test(
      'setup waits for a conversion batch on the same wallet instead of '
      'failing busy, then sends the approvals still missing', () async {
    final hold = Completer<void>();
    final chain = _Chain(holdFirstNonce: hold);
    await http.runWithClient(() async {
      final onboarding = PolymarketOnboardingService();
      final wallet = onboarding.deriveDepositWalletAddress(_eoa);
      // A deposit's conversion is mid-flight on the deposit wallet.
      final conversion = onboarding.executeDepositWalletBatch(
        eoaAddress: _eoa,
        signer: const CredentialsDepositWalletBatchSigner(_key),
        walletAddress: wallet,
        calls: [(target: wallet, value: BigInt.zero, data: '0x01')],
        deadline: 2000000000,
        beforeSubmit: (_) async => throw StateError('conversion stops here'),
      );
      final conversionDone = expectLater(conversion, throwsStateError);
      await pumpEventQueue();
      expect(PolymarketOnboardingService.batchInFlight(wallet), isTrue);

      final setup = onboarding.enableTrading(eoaAddress: _eoa, privateKey: _key);
      var setupFailed = false;
      setup.catchError((Object _) {
        setupFailed = true;
        return '';
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // Still waiting: no allowance read, nothing refused, nothing sent.
      expect(setupFailed, isFalse);
      expect(chain.allowanceReads, 0);
      expect(chain.submits, 0);

      hold.complete();
      await conversionDone;
      expect(await setup, wallet);
      expect(chain.submits, 1);
      expect(chain.allowanceReads, greaterThan(0));
    }, () => MockClient(chain.handle));
  });

  test('approvals already set: setup sends nothing', () async {
    final chain = _Chain()..approvalsLanded = true;
    await http.runWithClient(
      () => PolymarketOnboardingService()
          .enableTrading(eoaAddress: _eoa, privateKey: _key),
      () => MockClient(chain.handle),
    );
    expect(chain.submits, 0);
    expect(chain.nonceReads, 0);
  });
}
