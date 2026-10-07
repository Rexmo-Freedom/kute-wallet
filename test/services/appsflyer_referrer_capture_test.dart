// Verifies AppsFlyer referrer capture from a deep link. The capture path is
// IDENTICAL for a direct invite-link tap (onDeepLinking) and a deferred install
// (onInstallConversionData) — both funnel into _captureReferrerCode — so
// exercising the UDL handler here proves the shared capture logic for both.
// authWallet then reads AppsFlyerService.capturedReferrer to sync to the backend.

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/appsflyer_service.dart';

DeepLinkResult _link(Map<String, dynamic> clickEvent,
        {DeepLinkStatus status = DeepLinkStatus.found}) =>
    DeepLinkResult(status: status, deepLink: DeepLink(clickEvent));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppsFlyerService.clearCapturedReferrer();
    AppsFlyerService.onReferrerCaptured = null;
  });

  group('AppsFlyer deep-link referrer capture', () {
    test('captures + uppercases deep_link_value on a FOUND link', () {
      String? persisted;
      AppsFlyerService.onReferrerCaptured = (c) async {
        persisted = c;
      };

      AppsFlyerService.handleDeepLinkForTest(_link({'deep_link_value': 'abin'}));

      expect(AppsFlyerService.capturedReferrer, 'ABIN'); // normalized
      expect(persisted, 'ABIN'); // durably persisted for authWallet to sync
    });

    test('falls back to af_sub1 when deep_link_value is absent', () {
      AppsFlyerService.handleDeepLinkForTest(_link({'af_sub1': 'friend7'}));
      expect(AppsFlyerService.capturedReferrer, 'FRIEND7');
    });

    test('does not capture when the link status is not FOUND', () {
      AppsFlyerService.handleDeepLinkForTest(
          _link({'deep_link_value': 'abin'}, status: DeepLinkStatus.notFound));
      expect(AppsFlyerService.capturedReferrer, isNull);
    });

    test('does not capture when there is no deepLink object', () {
      AppsFlyerService
          .handleDeepLinkForTest(const DeepLinkResult(status: DeepLinkStatus.found));
      expect(AppsFlyerService.capturedReferrer, isNull);
    });

    test('rejects codes that are too short or have invalid characters', () {
      AppsFlyerService.handleDeepLinkForTest(_link({'deep_link_value': 'ab'}));
      expect(AppsFlyerService.capturedReferrer, isNull);

      AppsFlyerService
          .handleDeepLinkForTest(_link({'deep_link_value': 'bad code!'}));
      expect(AppsFlyerService.capturedReferrer, isNull);
    });
  });

  // Deferred install path: the plugin wraps conversion data as
  // {'status': 'success'|'failure', 'payload': <decoded map>} — 'payload',
  // NOT 'data' (appsflyer_sdk 6.18.0 lib/src/callbacks.dart). These pin the
  // envelope shape so a plugin upgrade that changes it fails loudly here.
  group('deferred conversion-data capture (real plugin envelope)', () {
    test('captures deep_link_value from the {status, payload} envelope', () {
      AppsFlyerService.handleConversionDataForTest({
        'status': 'success',
        'payload': {
          'is_first_launch': true,
          'af_status': 'Non-organic',
          'deep_link_value': 'abin',
        },
      });
      expect(AppsFlyerService.capturedReferrer, 'ABIN');
    });

    test('ignores non-first launches', () {
      AppsFlyerService.handleConversionDataForTest({
        'status': 'success',
        'payload': {'is_first_launch': false, 'deep_link_value': 'abin'},
      });
      expect(AppsFlyerService.capturedReferrer, isNull);
    });

    test('ignores an organic payload with no code', () {
      AppsFlyerService.handleConversionDataForTest({
        'status': 'success',
        'payload': {'is_first_launch': true, 'af_status': 'Organic'},
      });
      expect(AppsFlyerService.capturedReferrer, isNull);
    });

    test('ignores failure envelopes', () {
      AppsFlyerService.handleConversionDataForTest({
        'status': 'failure',
        'payload': {'is_first_launch': true, 'deep_link_value': 'abin'},
      });
      expect(AppsFlyerService.capturedReferrer, isNull);
    });

    test('falls back to af_sub1 and tolerates a bare map + string bool', () {
      AppsFlyerService.handleConversionDataForTest({
        'is_first_launch': 'true',
        'af_sub1': 'abin',
      });
      expect(AppsFlyerService.capturedReferrer, 'ABIN');
    });
  });

  // The app-native path: go_router's redirect hands a kute://open (or OneLink)
  // deep link's code straight to ingestReferrerFromDeepLink — no SDK round-trip,
  // so it fires in debug too and on both iOS + Android.
  group('app-side deep-link ingestion (router path)', () {
    test('ingestReferrerFromDeepLink captures + uppercases a raw code', () {
      AppsFlyerService.ingestReferrerFromDeepLink('abin');
      expect(AppsFlyerService.capturedReferrer, 'ABIN');
    });

    test('ingestReferrerFromDeepLink ignores null + invalid codes', () {
      AppsFlyerService.ingestReferrerFromDeepLink(null);
      expect(AppsFlyerService.capturedReferrer, isNull);

      AppsFlyerService.ingestReferrerFromDeepLink('x');
      expect(AppsFlyerService.capturedReferrer, isNull);
    });
  });
}
