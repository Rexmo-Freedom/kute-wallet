// One relayer action at a time per deposit wallet (device bug, 15 October
// 2026: the same delivered USDC.e was converted twice, the second batch was
// refused "wallet busy: active action exists" or on a moved nonce, and the
// bet placed right after failed). A conversion triggered again for the
// same delivery sends ONE batch; a busy or nonce refusal is read again on a
// fresh nonce and sent again; actions on a wallet run in order. Network
// fakes only: nothing is really signed for or sent.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/polymarket/relayer_wallet_queue.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _eoa = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _key = '0123456789012345678901234567890123456789012345678901234567890123';
const _wallet = '0x0088000000000000000000000000000000000001';

/// The relayer, the backend relay and Polygon RPC for one deposit wallet
/// holding [usdce] micro-USDC.e. [staleReads] balance reads after the
/// first conversion still show the old amount (a node not caught up);
/// [refusals] are the relayer's answers to the first submits.
class _Chain {
  _Chain({required this.usdce, this.staleReads = 0, List<String>? refusals})
      : refusals = refusals ?? [];

  BigInt usdce;
  int staleReads;
  final List<String> refusals;
  var nonce = 16;
  var nonceReads = 0;
  var submits = 0;
  var accepted = 0;
  final submittedNonces = <String>[];

  Future<http.Response> handle(http.Request request) async {
    final url = request.url;
    if (url.host == 'relayer-v2.polymarket.com') {
      if (url.path == '/v1/account/transactions/params') {
        nonceReads++;
        return http.Response(jsonEncode({'nonce': '$nonce'}), 200);
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
      submittedNonces.add(body['nonce'] as String);
      if (refusals.isNotEmpty) {
        return http.Response(refusals.removeAt(0), 400);
      }
      accepted++;
      // The conversion lands: the wallet holds no USDC.e any more, but
      // a node that has not caught up still shows it for a while.
      nonce++;
      usdce = BigInt.zero;
      return http.Response(jsonEncode({'transactionID': 'tx_$submits'}), 200);
    }
    if (request.method == 'POST' && request.body.contains('jsonrpc')) {
      final rpc = jsonDecode(request.body) as Map<String, dynamic>;
      if (rpc['method'] == 'eth_chainId') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x89'}), 200);
      }
      if (rpc['method'] == 'eth_call') {
        var shown = usdce;
        if (accepted > 0 && staleReads > 0) {
          staleReads--;
          shown = BigInt.from(1434141);
        }
        final word = shown.toRadixString(16).padLeft(64, '0');
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x$word'}), 200);
      }
    }
    return http.Response('unexpected ${request.method} $url', 500);
  }
}

Future<BigInt> _wrap() =>
    PolymarketOnboardingService().wrapHeldUsdceToPusdInDepositWallet(
        eoaAddress: _eoa, privateKey: _key, walletAddress: _wallet);

void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    WalletIdentityService.debugBind(pubkey: null);
    AffiliateService.debugSessionToken = 'test-session';
    PolymarketOnboardingService.debugReadRpcs = ['https://rpc.test'];
    RelayerWalletQueue.reset();
    RecentUsdceWraps.reset();
    relayerTransientBackoff = (_) => const Duration(milliseconds: 1);
    staleReadPoll = const Duration(milliseconds: 1);
  });
  tearDown(() {
    AffiliateService.debugSessionToken = null;
    PolymarketOnboardingService.debugReadRpcs = null;
    relayerTransientBackoff = (a) => Duration(seconds: 2 * (a + 1));
    staleReadPoll = const Duration(seconds: 1);
  });

  test(
      'the same delivery converted from two triggers (the arrival watch and '
      'the readiness nudge): ONE batch, even while reads lag', () async {
    final chain = _Chain(usdce: BigInt.from(1434141), staleReads: 3);
    final results = await http.runWithClient(
      () => Future.wait([_wrap(), _wrap()]),
      () => MockClient(chain.handle),
    );
    expect(chain.submits, 1);
    expect(results.where((r) => r > BigInt.zero), hasLength(1));
    // A third trigger right after, while a node still shows the old
    // amount: never signed again.
    chain.staleReads = 20;
    final third =
        await http.runWithClient(_wrap, () => MockClient(chain.handle));
    expect(third, BigInt.zero);
    expect(chain.submits, 1);
  });

  test(
      '"wallet busy: active action exists": the nonce is read again and the '
      'batch sent again', () async {
    final chain = _Chain(usdce: BigInt.from(1434141), refusals: [
      '{"error":"wallet busy: active action exists"}',
    ]);
    final wrapped =
        await http.runWithClient(_wrap, () => MockClient(chain.handle));
    expect(wrapped, BigInt.from(1434141));
    expect(chain.submits, 2);
    expect(chain.nonceReads, 2);
  });

  test(
      '"batch nonce N does not match on-chain nonce M": signed again on the '
      'fresh nonce', () async {
    final chain = _Chain(usdce: BigInt.from(1434141), refusals: [
      '{"error":"batch nonce 16 does not match on-chain nonce 17"}',
    ]);
    final wrapped = await http.runWithClient(_wrap, () {
      return MockClient((request) {
        // The relayer's nonce moved under the first signature.
        if (chain.submits == 1 &&
            request.url.path == '/v1/account/transactions/params') {
          chain.nonce = 17;
        }
        return chain.handle(request);
      });
    });
    expect(wrapped, BigInt.from(1434141));
    expect(chain.submittedNonces, ['16', '17']);
  });

  test('a refusal that is not transient fails at once', () async {
    final chain = _Chain(
        usdce: BigInt.from(1434141), refusals: ['{"error":"bad signature"}']);
    await expectLater(http.runWithClient(_wrap, () => MockClient(chain.handle)),
        throwsException);
    expect(chain.submits, 1);
  });

  group('pure rules', () {
    test('transient refusals', () {
      expect(
          isTransientRelayerRefusal(
              Exception('400 {"error":"wallet busy: active action exists"}')),
          isTrue);
      expect(
          isTransientRelayerRefusal(Exception(
              '400 {"error":"batch nonce 16 does not match on-chain nonce 17"}')),
          isTrue);
      expect(isTransientRelayerRefusal(Exception('bad signature')), isFalse);
      expect(isTransientRelayerRefusal(StateError('x')), isFalse);
    });

    test('bounded retries', () async {
      var sends = 0;
      await expectLater(withTransientRelayerRetry<void>((_) async {
        sends++;
        throw Exception('wallet busy: active action exists');
      }), throwsException);
      expect(sends, 1 + kRelayerTransientRetries);
    });

    test(
        'actions on one wallet run one at a time, in order; another wallet '
        'is not held', () async {
      final log = <String>[];
      final first = Completer<void>();
      final a = RelayerWalletQueue.run(_wallet, () async {
        log.add('a:start');
        await first.future;
        log.add('a:end');
      });
      final b = RelayerWalletQueue.run(_wallet, () async => log.add('b'));
      final other = RelayerWalletQueue.run('0xother', () async => log.add('x'));
      await other;
      expect(log, ['a:start', 'x']);
      first.complete();
      await Future.wait([a, b]);
      expect(log, ['a:start', 'x', 'a:end', 'b']);
      // A failed action does not hold the next one.
      await expectLater(
          RelayerWalletQueue.run<void>(_wallet, () async => throw 'boom'),
          throwsA('boom'));
      expect(await RelayerWalletQueue.run(_wallet, () async => 1), 1);
    });
  });
}
