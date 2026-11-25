// Hyperliquid logos across launches: the first launch downloads them (and
// learns which candidates have no logo), the second reads both from disk
// and draws every row's logo on its first frame with no request at all.
// A failed request is never written down as a miss; the prefetch keeps to
// its connection limit. A crypto coin the venue has no logo for under its
// own name falls back to the venue's bare-symbol image, then CoinCap's
// PNG; a coin no host knows keeps the letter tile and is asked for once.

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

// Crypto perps on a builder dex whose dex-qualified logo the venue lacks.
const _nbtOwn = 'https://app.hyperliquid.xyz/coins/hyna:NBT.svg';
const _nbtBare = 'https://app.hyperliquid.xyz/coins/NBT.svg';
const _ansemOwn = 'https://app.hyperliquid.xyz/coins/hyna:ANSEM.svg';
const _ansemBare = 'https://app.hyperliquid.xyz/coins/ANSEM.svg';
const _ansemCoincap = 'https://assets.coincap.io/assets/icons/ansem@2x.png';
const _kntqOwn = 'https://app.hyperliquid.xyz/coins/hyna:KNTQ.svg';
const _kntqBare = 'https://app.hyperliquid.xyz/coins/KNTQ.svg';
const _kntqCoincap = 'https://assets.coincap.io/assets/icons/kntq@2x.png';

const _logo =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="12" fill="#F7931A"/></svg>';

/// A 2x2 orange PNG (a valid one: the icon decodes it).
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4PlnqPwgzwBgAX8AKjR/k5lsAAAAASUVORK5CYII=');

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
final _nbtMarket = _market('NBT', 'hyna:NBT');
final _ansemMarket = _market('ANSEM', 'hyna:ANSEM');

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

  Widget app(Widget home) => ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: home,
        ),
      );

  Widget icons() => app(Column(children: [
        HlCoinIcon(coin: 'BTC', wireCoin: 'BTC'),
        HlCoinIcon(coin: 'NVDA', wireCoin: 'xyz:NVDA', category: 'stocks'),
      ]));

  /// The fallback hosts: the venue 404s every builder-dex name, keeps a
  /// bare NBT logo, and CoinCap has ANSEM; KNTQ is nowhere.
  http.Response fallbackHosts(http.Request req) {
    final url = req.url.toString();
    requests.add(url);
    if (url == _nbtBare) {
      return http.Response.bytes(utf8.encode(_logo), 200,
          headers: {'content-type': 'image/svg+xml'});
    }
    if (url == _ansemCoincap) {
      return http.Response.bytes(_png, 200,
          headers: {'content-type': 'image/png'});
    }
    return http.Response('not found', 404);
  }

  /// Builds [home] and lets the rows' own loads run (the request, the
  /// disk read, the parse), then applies their frame.
  Future<void> pumpAndLoad(WidgetTester tester, Widget home) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app(home));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

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
    // Each venue miss asks CoinCap once more (the bare-symbol image is the
    // same URL for a default-dex perp, so it is not asked twice).
    expect(requests.length, 60);
  });

  testWidgets('the venue 404s a builder-dex name: its bare-symbol image shows',
      (tester) async {
    SharedHttpClient.debugOverride = MockClient((req) async => fallbackHosts(req));
    late IconDiskCache disk;
    await tester.runAsync(() async {
      disk = await launch();
      await HlIconPrefetch.prefetch([_nbtMarket]);
      await disk.flush();
    });
    expect(requests, [_nbtOwn, _nbtBare]);
    expect(disk.lookup(_nbtOwn)!.isMiss, isTrue);
    expect(disk.lookup(_nbtBare)!.kind, IconCacheKind.svg);

    await tester.pumpWidget(app(HlCoinIcon(coin: 'NBT', wireCoin: 'hyna:NBT')));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(HlLetterBadge), findsNothing);
    expect(requests.length, 2, reason: 'the row is served from memory');
  });

  testWidgets('both venue images 404: CoinCap\'s PNG is drawn and kept as a raster',
      (tester) async {
    SharedHttpClient.debugOverride = MockClient((req) async => fallbackHosts(req));
    late IconDiskCache disk;
    await tester.runAsync(() async {
      disk = await launch();
      await HlIconPrefetch.prefetch([_ansemMarket]);
      await disk.flush();
    });
    expect(requests, [_ansemOwn, _ansemBare, _ansemCoincap]);
    expect(disk.lookup(_ansemCoincap)!.kind, IconCacheKind.raster);

    // Decoded for real: a PNG the icon could not draw would fall back to
    // the letter badge through Image.memory's errorBuilder.
    await pumpAndLoad(tester, HlCoinIcon(coin: 'ANSEM', wireCoin: 'hyna:ANSEM'));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(HlLetterBadge), findsNothing);

    // The next launch reads the PNG from disk, offline.
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
    expect(IconLoadStats.disk, 1);
    await pumpAndLoad(tester, HlCoinIcon(coin: 'ANSEM', wireCoin: 'hyna:ANSEM'));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(HlLetterBadge), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets('a coin no host knows keeps the letter tile and is asked once',
      (tester) async {
    SharedHttpClient.debugOverride = MockClient((req) async => fallbackHosts(req));
    late IconDiskCache disk;
    await tester.runAsync(() async {
      disk = await launch();
      // Rows load themselves; nothing is prefetched here.
      IconCaches.debugSet(hyperliquid: disk, prefetch: false);
    });
    Widget row() =>
        HlCoinIcon(key: UniqueKey(), coin: 'KNTQ', wireCoin: 'hyna:KNTQ');

    await pumpAndLoad(tester, row());
    expect(find.byType(HlLetterBadge), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(requests, [_kntqOwn, _kntqBare, _kntqCoincap]);
    for (final url in [_kntqOwn, _kntqBare, _kntqCoincap]) {
      expect(disk.lookup(url)!.isMiss, isTrue, reason: url);
    }

    // The same session builds the row again (a list rebuild): no request.
    requests.clear();
    await pumpAndLoad(tester, row());
    expect(find.byType(HlLetterBadge), findsOneWidget);
    expect(requests, isEmpty);

    // The next launch, within the miss TTL: the disk remembers all three.
    await tester.runAsync(() async {
      await disk.flush();
      final next = await launch();
      IconCaches.debugSet(hyperliquid: next, prefetch: false);
    });
    await pumpAndLoad(tester, row());
    expect(find.byType(HlLetterBadge), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('nothing is requested for a row until the list builds it',
      (tester) async {
    SharedHttpClient.debugOverride = MockClient((req) async => fallbackHosts(req));
    await tester.runAsync(() async {
      final disk = await launch();
      IconCaches.debugSet(hyperliquid: disk, prefetch: false);
    });
    // The row sits far below the fold of a long list.
    const rows = 40;
    Widget list() => ListView.builder(
          itemCount: rows + 1,
          itemBuilder: (_, i) => i < rows
              ? const SizedBox(height: 400)
              : HlCoinIcon(coin: 'NBT', wireCoin: 'hyna:NBT'),
        );
    await pumpAndLoad(tester, list());
    expect(requests, isEmpty, reason: 'the row was never built');
    expect(find.byType(HlCoinIcon), findsNothing);

    // Scrolled into view, the row asks for its logo, once.
    await tester.runAsync(() async {
      await tester.drag(find.byType(ListView), const Offset(0, -400.0 * rows));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.byType(HlCoinIcon), findsOneWidget);
    expect(requests, [_nbtOwn, _nbtBare]);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('nothing is prefetched where boot never opened the caches',
      (tester) async {
    IconCaches.debugSet();
    await tester.runAsync(
        () => HlIconPrefetch.prefetch([_btcMarket, _nvdaMarket]));
    expect(requests, isEmpty);
  });
}
