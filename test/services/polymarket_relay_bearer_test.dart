import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

void main() {
  final seen = <http.Request>[];

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    WalletIdentityService.debugBind(pubkey: null);
    seen.clear();
  });

  tearDown(() => AffiliateService.debugSessionToken = null);

  Future<String> submit() => http.runWithClient(
        () => PolymarketOnboardingService().submitForTest({'type': 'SAFE'}),
        () => MockClient((req) async {
          seen.add(req);
          return http.Response('{"transactionID":"tx_1"}', 200);
        }),
      );

  test('the relay submit carries the session bearer', () async {
    AffiliateService.debugSessionToken = 'session-token';
    expect(await submit(), 'tx_1');
    expect(seen.single.url.path, '/api/v1/pm/relay/submit');
    expect(seen.single.headers['Authorization'], 'Bearer session-token');
  });

  test('without a session or hot wallet identity nothing is submitted',
      () async {
    AffiliateService.debugSessionToken = null;
    await expectLater(
      submit(),
      throwsA(isA<WalletSessionUnavailable>().having((e) => e.message,
          'message', l10nForLanguage('en').walletSessionUnavailable)),
    );
    expect(seen, isEmpty);
  });
}
