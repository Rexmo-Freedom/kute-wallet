// Who keeps the passkey, per platform and, on the web, per browser.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/passkey_account_name.dart';

void main() {
  const macSafari =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.0 Safari/605.1.15';
  const macChrome =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  const iphoneSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 '
      'Safari/604.1';
  const iphoneChrome =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0 Mobile/15E148 '
      'Safari/604.1';
  const android =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, '
      'like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  const winFirefox =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 '
      'Firefox/132.0';
  const winEdge =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, '
      'like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0';

  PasskeyKeeper web(String ua) => passkeyKeeper(web: true, userAgent: ua);

  test('the web follows the browser and its system', () {
    expect(web(macSafari), PasskeyKeeper.apple);
    expect(web(iphoneSafari), PasskeyKeeper.apple);
    expect(web(iphoneChrome), PasskeyKeeper.apple);
    expect(web(macChrome), PasskeyKeeper.google);
    expect(web(android), PasskeyKeeper.google);
    expect(web(winFirefox), PasskeyKeeper.other);
    expect(web(winEdge), PasskeyKeeper.other);
  });

  test('the phones are as before', () {
    expect(passkeyKeeper(web: false, ios: true), PasskeyKeeper.apple);
    expect(passkeyKeeper(web: false, ios: false), PasskeyKeeper.google);
  });
}
