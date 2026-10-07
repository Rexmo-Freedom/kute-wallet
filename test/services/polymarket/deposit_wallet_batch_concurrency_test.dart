import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

const _owner = '0x14791697260E4c9A71f18484C9f997B308e59325';
const _wallet = '0x1111111111111111111111111111111111111111';
const _signer = CredentialsDepositWalletBatchSigner(
  '0123456789012345678901234567890123456789012345678901234567890123',
);

List<DepositWalletCall> _calls(String data) => [
      (target: _owner, value: BigInt.zero, data: data),
    ];

void main() {
  for (final sameCalls in [false, true]) {
    test(
        'hot wallet rejects a concurrent ${sameCalls ? 'identical' : 'different'} '
        'batch before signing or submitting', () async {
      final started = Completer<void>();
      final releaseNonce = Completer<http.Response>();
      var nonceReads = 0;
      var submits = 0;
      var signed = 0;

      await http.runWithClient(() async {
        Future<String> execute(String data) =>
            PolymarketOnboardingService().executeDepositWalletBatch(
              eoaAddress: _owner,
              signer: _signer,
              walletAddress: _wallet,
              calls: _calls(data),
              deadline: 2000000000,
              beforeSubmit: (_) async {
                signed++;
                throw StateError('stop before sending');
              },
            );

        final first = execute('0x01');
        final firstFailure = expectLater(first, throwsStateError);
        await started.future;

        // The rejection must happen while the first batch is still waiting
        // for its nonce, rather than returning its eventual result.
        try {
          await expectLater(
            execute(sameCalls ? '0x01' : '0x02')
                .timeout(const Duration(seconds: 1)),
            throwsA(isA<LedgerFailure>()
                .having((e) => e.code, 'code', LedgerFailureCode.busy)),
          );
          expect(nonceReads, 1);
          expect(signed, 0);
        } finally {
          releaseNonce.complete(http.Response(jsonEncode({'nonce': '7'}), 200));
          await firstFailure;
        }

        // Failure must release the lock so a deliberate retry can proceed.
        await expectLater(execute('0x02'), throwsStateError);
        expect(nonceReads, 2);
        expect(signed, 2);
        expect(submits, 0);
      },
          () => MockClient((request) async {
                if (request.url.path == '/v1/account/transactions/params') {
                  nonceReads++;
                  if (!started.isCompleted) started.complete();
                  return releaseNonce.future;
                }
                submits++;
                return http.Response('unexpected network call', 500);
              }));
    });
  }
}
