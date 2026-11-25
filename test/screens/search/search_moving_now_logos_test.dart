// "Moving now" lists only markets with a logo of their own (founder, 11
// November 2026, over HWAVE and ANSEM drawn as letter tiles and MUU as a
// building glyph: "don't show Moving now without svg, means that they
// have low liquidity"). The pool is the day's largest moves above the
// liquidity floor; a mover whose logo is a known miss is skipped and the
// next one by move takes its place; CoinCap's guess at a ticker is no
// logo; logos not known yet are settled without a request to CoinCap.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/icon_cache/icon_disk_cache.dart';

HlMarket _market(String coin,
        {double px = 110,
        double prev = 100,
        double vlm = kHlLowLiquidityDayVolumeUsd * 10,
        String? wire}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire ?? coin,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: 'crypto',
      dex: (wire ?? '').contains(':') ? wire!.split(':').first : '',
      isHip3: (wire ?? '').contains(':'),
    );

List<String> _coins(Iterable<HlMarket> ms) => [for (final m in ms) m.coin];

const _logo =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="12" fill="#F7931A"/></svg>';

/// A 2x2 orange PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4PlnqPwgzwBgAX8AKjR/k5lsAAAAASUVORK5CYII=');

void main() {
  group('the pool', () {
    test('the liquidity floor still applies, ranked by the size of the move',
        () {
      final pool = searchMoverPool([
        _market('BTC', px: 102),
        // The biggest move of the day, but thin: never in the pool.
        _market('THIN', px: 300, vlm: kHlLowLiquidityDayVolumeUsd - 1),
        _market('HYPE', px: 80),
        _market('NOPREV', prev: 0),
        _market('SOL', px: 105),
      ]);
      expect(_coins(pool), ['HYPE', 'SOL', 'BTC']);
    });

    test('looks through the first thirty movers', () {
      final pool = searchMoverPool([
        for (var i = 0; i < 50; i++) _market('C$i', px: 101.0 + i),
      ]);
      expect(pool, hasLength(kSearchMoverPool));
      expect(pool.first.coin, 'C49');
    });
  });

  group('the movers shown', () {
    final ranked = [
      for (final c in ['HWAVE', 'TBC', 'INIT', 'SNXX', 'MUU', 'ANSEM', 'ZEC', 'SOL'])
        _market(c),
    ];
    HlLogoStatus Function(HlMarket) statuses(Map<String, HlLogoStatus> s) =>
        (m) => s[m.coin] ?? HlLogoStatus.hit;

    test('a mover with no logo is skipped; the next with one takes its place',
        () {
      final pick = searchMoversWithLogos(ranked,
          status: statuses({
            'HWAVE': HlLogoStatus.miss,
            'MUU': HlLogoStatus.miss,
            'ANSEM': HlLogoStatus.miss,
          }));
      expect(_coins(pick.shown), ['TBC', 'INIT', 'SNXX', 'ZEC', 'SOL']);
      expect(pick.loading, isFalse);
      expect(pick.pending, isEmpty);
    });

    test('logos not known yet that could fill a short grid: loading', () {
      final pick = searchMoversWithLogos(ranked,
          status: statuses({
            'HWAVE': HlLogoStatus.unknown,
            'TBC': HlLogoStatus.unknown,
            'INIT': HlLogoStatus.miss,
            'ANSEM': HlLogoStatus.miss,
            'ZEC': HlLogoStatus.miss,
          }));
      expect(pick.shown, isEmpty);
      expect(pick.loading, isTrue);
      expect(_coins(pick.pending), ['HWAVE', 'TBC']);
    });

    test('enough known logos: those show while a higher one is settled', () {
      final pick = searchMoversWithLogos(ranked,
          status: statuses({'TBC': HlLogoStatus.unknown}));
      expect(_coins(pick.shown), ['HWAVE', 'INIT', 'SNXX', 'MUU', 'ANSEM', 'ZEC']);
      expect(pick.loading, isFalse);
      expect(_coins(pick.pending), ['TBC']);
    });

    test('fewer with a logo: fewer rows; none: no block', () {
      final few = searchMoversWithLogos(ranked,
          status: (m) => m.coin == 'SNXX' || m.coin == 'SOL'
              ? HlLogoStatus.hit
              : HlLogoStatus.miss);
      expect(_coins(few.shown), ['SNXX', 'SOL']);
      final none =
          searchMoversWithLogos(ranked, status: (_) => HlLogoStatus.miss);
      expect(none.shown, isEmpty);
      expect(none.loading, isFalse);
    });
  });

  group('HlIconAvailability', () {
    late List<String> requests;
    late Directory dir;

    // NBT: the venue has no hyna:NBT logo but has its bare-symbol image.
    // ANSEM: only CoinCap has one. BTC: the venue's own.
    final nbt = _market('NBT', wire: 'hyna:NBT');
    final ansem = _market('ANSEM', wire: 'hyna:ANSEM');
    final btc = _market('BTC');

    http.Response hosts(http.Request req) {
      final url = req.url.toString();
      requests.add(url);
      if (url == 'https://app.hyperliquid.xyz/coins/NBT.svg' ||
          url == 'https://app.hyperliquid.xyz/coins/BTC.svg') {
        return http.Response.bytes(utf8.encode(_logo), 200,
            headers: {'content-type': 'image/svg+xml'});
      }
      if (url == 'https://assets.coincap.io/assets/icons/ansem@2x.png') {
        return http.Response.bytes(_png, 200,
            headers: {'content-type': 'image/png'});
      }
      return http.Response('not found', 404);
    }

    setUp(() {
      requests = [];
      dir = Directory.systemTemp.createTempSync('hl_icon_availability_test');
      HlIconPrefetch.debugReset();
      SharedHttpClient.debugOverride = MockClient((req) async => hosts(req));
    });

    tearDown(() {
      SharedHttpClient.debugOverride = null;
      IconCaches.debugSet();
      HlIconPrefetch.debugReset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    testWidgets(
        'unknown until settled; the venue\'s own image is a logo, CoinCap\'s '
        'is not and is never asked for', (tester) async {
      expect(HlIconAvailability.of(nbt), HlLogoStatus.unknown);
      expect(HlIconAvailability.of(ansem), HlLogoStatus.unknown);
      final before = HlIconAvailability.revision.value;
      await tester.runAsync(
          () => HlIconAvailability.ensure([nbt, ansem, btc]));
      expect(HlIconAvailability.of(nbt), HlLogoStatus.hit);
      expect(HlIconAvailability.of(btc), HlLogoStatus.hit);
      expect(HlIconAvailability.of(ansem), HlLogoStatus.miss);
      expect(HlIconAvailability.revision.value, before + 1);
      expect(requests.where((u) => u.contains('coincap')), isEmpty);

      // The icon itself may still draw CoinCap's PNG elsewhere: it is
      // still no logo of ANSEM's own.
      IconCaches.debugSet(prefetch: true);
      await tester.runAsync(() => HlIconPrefetch.prefetch([ansem]));
      expect(requests.last, contains('coincap'));
      expect(HlIconAvailability.of(ansem), HlLogoStatus.miss);

      // Asked once a session.
      final asked = requests.length;
      await tester.runAsync(() => HlIconAvailability.ensure([ansem, nbt]));
      expect(requests, hasLength(asked));
    });

    testWidgets('read from the disk cache without a request', (tester) async {
      await tester.runAsync(() async {
        final disk = await IconDiskCache.open(dir);
        IconCaches.debugSet(hyperliquid: disk);
        await HlIconAvailability.ensure([btc, ansem]);
        await disk.flush();
      });
      // A new launch over the same folder: nothing in memory.
      HlIconPrefetch.debugReset();
      requests.clear();
      await tester.runAsync(() async {
        IconCaches.debugSet(hyperliquid: await IconDiskCache.open(dir));
        // The opened cache is read synchronously once it has resolved.
        HlIconAvailability.of(btc);
        await Future<void>.delayed(Duration.zero);
      });
      expect(HlIconAvailability.of(btc), HlLogoStatus.hit);
      expect(HlIconAvailability.of(ansem), HlLogoStatus.miss);
      expect(requests, isEmpty);
    });
  });
}
