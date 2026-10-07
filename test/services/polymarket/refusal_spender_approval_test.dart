// "the allowance is not enough -> spender: 0x…": when the spender is one of
// Polymarket's pinned contracts the placement sets exactly that approval
// (pUSD, plus the CTF operator approval for the neg-risk pair) in one
// gasless batch and signs again; an address the app does not know is never
// approved. Network fakes only: nothing is really signed for or sent.
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _eoa = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _key = '0123456789012345678901234567890123456789012345678901234567890123';

class _Chain {
  _Chain({this.approved = false});
  final bool approved;
  var submits = 0;
  var requests = 0;
  final submittedCalls = <int>[];

  Future<http.Response> handle(http.Request request) async {
    requests++;
    final url = request.url;
    if (url.host == 'relayer-v2.polymarket.com') {
      if (url.path == '/v1/account/transactions/params') {
        return http.Response(jsonEncode({'nonce': '1'}), 200);
      }
      if (url.path == '/transaction') {
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
    if (request.method == 'POST' && request.body.contains('eth_chainId')) {
      // Reads use only endpoints that answer as Polygon.
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x89'}), 200);
    }
    if (request.method == 'POST' && request.body.contains('jsonrpc')) {
      final word = approved ? '1'.padLeft(64, '0') : '0' * 64;
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x$word'}), 200);
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

  Future<(bool, _Chain)> approve(String spender, {bool approved = false}) async {
    final chain = _Chain(approved: approved);
    final sent = await http.runWithClient(() {
      final onboarding = PolymarketOnboardingService();
      return onboarding.approveRefusalSpender(
        eoaAddress: _eoa,
        privateKey: _key,
        walletAddress: onboarding.deriveDepositWalletAddress(_eoa),
        spender: spender,
      );
    }, () => MockClient(chain.handle));
    return (sent, chain);
  }

  test('the neg-risk adapter gets pUSD and CTF approvals in one batch',
      () async {
    final (sent, chain) = await approve(
        PolymarketConstants.legacyNegRiskAdapterAddress.toLowerCase());
    expect(sent, isTrue);
    expect(chain.submits, 1);
    expect(chain.submittedCalls.single, 2);
  });

  test('another pinned contract gets its pUSD approval only', () async {
    final (sent, chain) = await approve(PolymarketConstants.exchangeAddress);
    expect(sent, isTrue);
    expect(chain.submittedCalls.single, 1);
  });

  test('an approval already set sends nothing', () async {
    final (sent, chain) = await approve(
        PolymarketConstants.negRiskExchangeAddress,
        approved: true);
    expect(sent, isFalse);
    expect(chain.submits, 0);
  });

  test('an unknown address is never approved, nothing is read or sent',
      () async {
    final chain = _Chain();
    await expectLater(
        http.runWithClient(
            () => PolymarketOnboardingService().approveRefusalSpender(
                  eoaAddress: _eoa,
                  privateKey: _key,
                  walletAddress: '0x${'2' * 40}',
                  spender: '0x${'3' * 40}',
                ),
            () => MockClient(chain.handle)),
        throwsArgumentError);
    expect(chain.requests, 0);
  });

  test('ExchangeV3 gets pUSD and the PositionManager operator approval',
      () async {
    final (sent, chain) =
        await approve(PolymarketConstants.comboExchangeV3Address);
    expect(sent, isTrue);
    expect(chain.submittedCalls.single, 2);
  });

  test('the V2 Router and modules get their operator approval only',
      () async {
    for (final spender in [
      PolymarketConstants.comboRouterAddress,
      PolymarketConstants.v2BinaryModuleAddress,
      PolymarketConstants.v2NegRiskModuleAddress,
    ]) {
      final (sent, chain) = await approve(spender);
      expect(sent, isTrue, reason: spender);
      expect(chain.submittedCalls.single, 1, reason: spender);
    }
    expect(
        polymarketPinnedSpenderApprovals[
            PolymarketConstants.comboRouterAddress.toLowerCase()],
        {PolymarketSpenderApproval.positionOperator});
    expect(
        polymarketPinnedSpenderApprovals[
            PolymarketConstants.v2NegRiskModuleAddress.toLowerCase()],
        {PolymarketSpenderApproval.ctfOperator});
  });

  test('every pinned contract has an analytics name', () {
    expect(polymarketPinnedSpenders.length, 10);
    expect(polymarketPinnedSpenderApprovals.keys.toSet(),
        polymarketPinnedSpenders.keys.toSet());
    expect(polymarketSpenderName(PolymarketConstants.comboRouterAddress),
        'v2_router');
    expect(
        polymarketSpenderName(PolymarketConstants.legacyNegRiskAdapterAddress),
        'neg_risk_adapter');
    expect(polymarketSpenderName('0x${'3' * 40}'), 'unknown');
    expect(polymarketSpenderName(null), 'unknown');
  });
}
