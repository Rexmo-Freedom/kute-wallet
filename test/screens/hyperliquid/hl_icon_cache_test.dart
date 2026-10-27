// Hyperliquid logos across launches: the first launch downloads them (and
// learns which candidates have no logo), the second reads both from disk
// and draws every row's logo on its first frame with no request at all.
// A failed request is never written down as a miss; the prefetch keeps to
// its connection limit.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show HlLetterBadge;
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/icon_cache/icon_disk_cache.dart';
import 'package:kute/theme/app_theme.dart';

const _btc = 'https://app.hyperliquid.xyz/coins/BTC.svg';
const _nvdaOwn = 'https://app.hyperliquid.xyz/coins/xyz:NVDA.svg';
const _nvdaParqet = 'https://assets.parqet.com/logos/symbol/NVDA';

const _logo =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="12" fill="#F7931A"/></svg>';

HlMarket _market(String coin, String wire, {String category = 'crypto'}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: 1,
      midPx: 1,
      prevDayPx: 1,
      dayNtlVlm: 1,
      category: category,
      dex: wire.contains(':') ? wire.split(':').first : '',
      isHip3: wire.contains(':'),
    );

final _btcMarket = _market('BTC', 'BTC');
final _nvdaMarket = _market('NVDA', 'xyz:NVDA', category: 'stocks');

void main() {
  late Directory dir;
  late List<String> requests;

  /// The venue: BTC has a logo, xyz:NVDA answers the web app's HTML
  /// shell (its "missing"), the stock-logo host has NVDA.
  http.Response venue(http.Request req) {
    final url = req.url.toString();
    requests.add(url);
    if (url == _btc || url == _nvdaParqet) {
      return http.Response.bytes(utf8.encode(_logo), 200,
          headers: {'content-type': 'image/svg+xml'});
    }
    return http.Response('<!doctype html><html></html>', 200,
        headers: {'content-type': 'text/html'});
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hl_icon_cache_test');
    requests = [];
    HlIconPrefetch.debugReset();
    IconLoadStats.reset();
    SharedHttpClient.debugOverride =
        MockClient((req) async => venue(req));
  });

  tearDown(() {
    SharedHttpClient.debugOverride = null;
    IconCaches.debugSet();
    HlIconPrefetch.debugReset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// One app launch: a fresh memory, a new cache over the same folder.
  Future<IconDiskCache> launch() async {
    HlIconPrefetch.debugReset();
    final disk = await IconDiskCache.open(dir);
    IconCaches.debugSet(hyperliquid: disk, prefetch: true);
    return disk;
  }

  Widget icons() => ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: Column(children: [
            HlCoinIcon(coin: 'BTC', wireCoin: 'BTC'),
            HlCoinIcon(coin: 'NVDA', wireCoin: 'xyz:NVDA', category: 'stocks'),
          ]),
        ),
      );

  testWidgets('a second launch draws every logo on the first frame, offline',
      (tester) async {
    // First launch: the prefetch downloads, the misses are learnt.
    await tester.runAsync(() async {
      final disk = await launch();
      await HlIconPrefetch.prefetch([_btcMarket, _nvdaMarket]);
      await disk.flush();
    });
    expect(requests, [_btc, _nvdaOwn, _nvdaParqet]);
    expect(IconLoadStats.network, 3);

    // Second launch: no network at all.
    requests.clear();
    IconLoadStats.reset();
    SharedHttpClient.debugOverride = MockClient((req) async {
      requests.add(req.url.toString());
      throw const SocketException('offline');
    });
    await tester.runAsync(() async {
      await launch();
      await HlIconPrefetch.warmFromDisk();
    });
    expect(IconLoadStats.disk, 2);

    await tester.pumpWidget(icons());
    // The very first frame: both logos, no fallback, no request.
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.byType(HlLetterBadge), findsNothing);
    expect(requests, isEmpty);
    expect(IconLoadStats.network, 0);
  });

  testWidgets('without the warm-up a relaunch still loads from disk only',
      (tester) async {
    await tester.runAsync(() async {
      final disk = await launch();
      await HlIconPrefetch.prefetch([_btcMarket, _nvdaMarket]);
      await disk.flush();
    });
    requests.clear();
    IconLoadStats.reset();
    await tester.runAsync(() async {
      await launch();
      // The list landing again (the 30 s refresh, the next launch).
      await HlIconPrefetch.prefetch([_btcMarket, _nvdaMarket]);
    });
    expect(requests, isEmpty, reason: 'the HTML miss was remembered too');
    expect(IconLoadStats.disk, 2);
  });

  testWidgets('a failed request shows the fallback and is not written down',
      (tester) async {
    SharedHttpClient.debugOverride = MockClient((req) async {
      requests.add(req.url.toString());
      throw const SocketException('offline');
    });
    late IconDiskCache disk;
    await tester.runAsync(() async {
      disk = await launch();
      await HlIconPrefetch.prefetch([_btcMarket]);
    });
    expect(disk.lookup(_btc), isNull,
        reason: 'a bad network must not hide the logo next launch');

    await tester.pumpWidget(icons());
    await tester.pump();
    expect(find.byType(HlLetterBadge), findsWidgets);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('the HTML catch-all is a miss on disk; a 503 is not',
      (tester) async {
    SharedHttpClient.debugOverride = MockClient((req) async {
      final url = req.url.toString();
      requests.add(url);
      if (url == _nvdaParqet) return http.Response('busy', 503);
      return venue(req);
    });
    late IconDiskCache disk;
    await tester.runAsync(() async {
      disk = await launch();
      await HlIconPrefetch.prefetch([_nvdaMarket]);
    });
    expect(disk.lookup(_nvdaOwn)!.isMiss, isTrue);
    expect(disk.lookup(_nvdaParqet), isNull);
  });

  testWidgets('the prefetch keeps to six requests at once', (tester) async {
    var inFlight = 0;
    var peak = 0;
    SharedHttpClient.debugOverride = MockClient((req) async {
      inFlight++;
      peak = inFlight > peak ? inFlight : peak;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      inFlight--;
      return venue(req);
    });
    await tester.runAsync(() async {
      await launch();
      await HlIconPrefetch.prefetch([
        for (var i = 0; i < 30; i++) _market('C$i', 'C$i'),
      ]);
    });
    expect(peak, HlIconPrefetch.concurrency);
    expect(requests.length, 30);
  });

  testWidgets('nothing is prefetched where boot never opened the caches',
      (tester) async {
    IconCaches.debugSet();
    await tester.runAsync(
        () => HlIconPrefetch.prefetch([_btcMarket, _nvdaMarket]));
    expect(requests, isEmpty);
  });
}
