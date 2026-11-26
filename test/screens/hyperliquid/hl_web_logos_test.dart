// The Investing logos shipped with the web build: the index answers which
// remote logos have a same-origin copy, a missing key is a miss (the row
// shows no icon on the web), and a failed index read is tried again.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/hyperliquid/components/hl_web_logos.dart';

void main() {
  tearDown(HlWebLogos.debugReset);

  const btc = 'https://app.hyperliquid.xyz/coins/BTC.svg';
  const soxl = 'https://app.hyperliquid.xyz/coins/xyz:SOXL.svg';

  test('a shipped key resolves to its same-origin copy', () async {
    HlWebLogos.loadIndex = () async => '{"$btc": "logos/hl/abc.svg"}';
    expect(HlWebLogos.ready, isFalse);
    expect(HlWebLogos.hasAny([btc]), isFalse, reason: 'not read yet');
    await HlWebLogos.preload();
    expect(HlWebLogos.ready, isTrue);
    expect(HlWebLogos.hasAny([soxl, btc]), isTrue);
    final local = await HlWebLogos.localUrlFor(btc);
    expect(local, Uri.base.resolve('logos/hl/abc.svg').toString());
  });

  test('a key the build did not ship is a miss', () async {
    HlWebLogos.debugSetIndex({btc: 'logos/hl/abc.svg'});
    expect(HlWebLogos.hasAny([soxl]), isFalse);
    expect(await HlWebLogos.localUrlFor(soxl), isNull);
  });

  test('no index (or a broken one) means no logos, and is read again',
      () async {
    var reads = 0;
    HlWebLogos.loadIndex = () async {
      reads++;
      return null;
    };
    await HlWebLogos.preload();
    expect(HlWebLogos.hasAny([btc]), isFalse);
    expect(await HlWebLogos.localUrlFor(btc), isNull);
    expect(reads, 2);
    HlWebLogos.loadIndex = () async => 'not json';
    expect(await HlWebLogos.localUrlFor(btc), isNull);
  });
}
