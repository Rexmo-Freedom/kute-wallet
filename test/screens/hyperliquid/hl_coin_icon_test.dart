// The Hyperliquid logo loader's pure parts: taking the raster out of an
// SVG that only wraps one (flutter_svg paints no pattern fills, so those
// drew as a blank plate), the candidate list of a builder perp, which
// tries the same symbol on every builder dex the venue lists, and the two
// last resorts of a crypto market no candidate has a logo for.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';

/// A 3x2 transparent PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAC0lEQVR4nGNgwAYAAB4AAT2ex7MAAAAASUVORK5CYII=';

/// The venue's export for a raster logo: a white square, a rect filled by
/// a pattern, and the image the pattern uses.
String _wrapped(String href) => '''
<svg width="827" height="827" viewBox="0 0 827 827" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<path d="M0 0H827V827H0V0Z" fill="white"/>
<rect x="66" y="182" width="695" height="463" fill="url(#pattern0)"/>
<defs>
<pattern id="pattern0" patternContentUnits="objectBoundingBox" width="1" height="1">
<use xlink:href="#image0" transform="matrix(0.0005 0 0 0.0007 0 0)"/>
</pattern>
<image id="image0" width="3" height="2" preserveAspectRatio="none" $href/>
</defs>
</svg>''';

const _vector =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="12" fill="#F7931A"/></svg>';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

HlMarket _perp(String coin, String dex, {String category = 'indices'}) =>
    HlMarket(
      coin: coin,
      wireCoin: '$dex:$coin',
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
      dex: dex,
      isHip3: true,
    );

void main() {
  group('embedded raster', () {
    test('the image is taken out of a wrapping SVG', () {
      final png = base64.decode(_png);
      expect(hlEmbeddedRaster(_wrapped('xlink:href="data:image/png;base64,$_png"')),
          png);
      // Without the xlink prefix, single quotes, and a JPEG type.
      expect(hlEmbeddedRaster(_wrapped('href="data:image/png;base64,$_png"')),
          png);
      expect(hlEmbeddedRaster(_wrapped("href='data:image/jpeg;base64,$_png'")),
          png);
      // Exporters wrap the payload across lines.
      final broken = '${_png.substring(0, 40)}\n${_png.substring(40)}';
      expect(
          hlEmbeddedRaster(
              _wrapped('xlink:href="data:image/png;base64,$broken"')),
          png);
    });

    test('a plain vector, a linked image and a bad payload embed nothing', () {
      expect(hlEmbeddedRaster(_vector), isNull);
      expect(hlEmbeddedRaster(_wrapped('href="https://example.com/a.png"')),
          isNull);
      expect(hlEmbeddedRaster(_wrapped('href="data:image/svg+xml;base64,$_png"')),
          isNull);
      expect(hlEmbeddedRaster(_wrapped('href="data:image/png;base64,!!!"')),
          isNull);
    });

    test('a PNG reports its shape; anything else does not', () {
      expect(hlPngAspectRatio(base64.decode(_png)), 1.5);
      expect(hlPngAspectRatio(_bytes(_vector)), isNull);
      expect(hlPngAspectRatio(Uint8List(4)), isNull);
    });
  });

  group('what the icon draws for a downloaded SVG', () {
    test('a wrapped raster is drawn as its image', () {
      final art = hlIconArtFromSvg(
          _bytes(_wrapped('xlink:href="data:image/png;base64,$_png"')))!;
      expect(art.raster, isTrue);
      expect(art.bytes, base64.decode(_png));
      expect(art.aspect, 1.5);
    });

    test('a vector logo stays a vector', () {
      final art = hlIconArtFromSvg(_bytes(_vector))!;
      expect(art.raster, isFalse);
      expect(art.aspect, 1);
      expect(utf8.decode(art.bytes), contains('<circle'));
    });

    test('a vector logo that also embeds a small image stays a vector', () {
      final paths = List.filled(200, '<path d="M0 0H827V827H0V0Z" fill="red"/>')
          .join();
      final svg = _wrapped('href="data:image/png;base64,$_png"')
          .replaceFirst('<defs>', '$paths<defs>');
      expect(svg.length, greaterThan(kHlIconWrapperMarkupMax));
      expect(hlIconArtFromSvg(_bytes(svg))!.raster, isFalse);
    });

    test('a wrapped raster may be larger than a vector; neither is unbounded',
        () {
      // 400 KB of image payload: over the vector limit, fine for a raster.
      final payload = base64.encode(Uint8List(300 * 1024));
      final big = _wrapped('href="data:image/png;base64,$payload"');
      expect(big.length, greaterThan(kHlIconMaxBytes));
      expect(hlIconArtFromSvg(_bytes(big))!.raster, isTrue);

      final hugeVector =
          '<svg xmlns="http://www.w3.org/2000/svg">${'<g/>' * 80000}</svg>';
      expect(hugeVector.length, greaterThan(kHlIconMaxBytes));
      expect(hlIconArtFromSvg(_bytes(hugeVector)), isNull);

      final huge = _wrapped(
          'href="data:image/png;base64,${base64.encode(Uint8List(1200 * 1024))}"');
      expect(huge.length, greaterThan(kHlIconRasterSvgMaxBytes));
      expect(hlIconArtFromSvg(_bytes(huge)), isNull);
      expect(hlIconArtFromSvg(Uint8List(0)), isNull);
    });
  });

  group('a white-only logo is no logo', () {
    // XPL's: white shapes under a drop shadow flutter_svg does not paint,
    // an empty circle on the light plate.
    const xpl = '''
<svg width="162" height="162" viewBox="0 0 162 162" fill="none" xmlns="http://www.w3.org/2000/svg">
<g filter="url(#f)">
<path d="M158 77.4H120.5V74.2H157.9Z" fill="white"/>
<path d="M83.4 86.3L118.8 90.7Z" fill="#FFFFFF" stroke="none"/>
</g>
<defs>
<filter id="f"><feFlood flood-opacity="0"/></filter>
<clipPath id="c"><rect width="10" height="10" fill="black"/></clipPath>
</defs>
</svg>''';

    test('white shapes only: a miss, so the letter tile shows', () {
      expect(hlSvgPaintsOnlyWhite(xpl), isTrue);
      expect(hlIconArtFromSvg(_bytes(xpl)), isNull);
    });

    test('a mark with any other paint, or an unpainted (black) shape, is '
        'drawn', () {
      // LIT's: white strokes on a black disc.
      final lit = xpl.replaceFirst(
          '<g filter', '<circle cx="81" cy="81" r="81" fill="black"/><g filter');
      expect(hlSvgPaintsOnlyWhite(lit), isFalse);
      expect(hlIconArtFromSvg(_bytes(lit)), isNotNull);
      expect(
          hlSvgPaintsOnlyWhite(
              xpl.replaceFirst('fill="white"', 'style="fill:#0EA57C"')),
          isFalse);
      expect(hlSvgPaintsOnlyWhite(xpl.replaceFirst(' fill="white"', '')),
          isFalse);
      expect(hlSvgPaintsOnlyWhite(_vector), isFalse);
    });
  });

  group('a builder perp borrows its symbol from every builder dex', () {
    test('the same symbol on every other dex, in the venue\'s order', () {
      expect(hlBuilderTwinWires('mkts:US500', ['xyz', 'flx', 'km', 'mkts']),
          ['xyz:US500', 'flx:US500', 'km:US500']);
      // Not a builder perp: nothing to borrow.
      expect(hlBuilderTwinWires('BTC', ['xyz', 'km']), isEmpty);
      expect(hlBuilderTwinWires('@142', ['xyz', 'km']), isEmpty);
      expect(hlBuilderTwinWires('mkts:US500', const []), isEmpty);
    });

    test('a dex with no live market of the symbol is still tried', () {
      // km lists US500 as delisted, so the directory has no km market: the
      // venue's dex list is what names it.
      HlMarketDirectory.remember([
        _perp('US500', 'mkts'),
        _perp('US500', 'para'),
        _perp('TSLA', 'xyz', category: 'stocks'),
      ]);
      final before = HlMarketDirectory.dexEpoch;
      HlMarketDirectory.rememberDexes(['xyz', 'km', 'para', 'mkts']);
      expect(HlMarketDirectory.dexEpoch, greaterThan(before));
      // Known again: nothing changed, nothing to retry.
      final after = HlMarketDirectory.dexEpoch;
      HlMarketDirectory.rememberDexes(['xyz', 'km']);
      expect(HlMarketDirectory.dexEpoch, after);

      final siblings = hlIconSiblingWires('US500', 'mkts:US500', 'indices');
      // The live twin of the same asset class first, then every other dex.
      expect(siblings.first, 'para:US500');
      expect(siblings, containsAll(['xyz:US500', 'km:US500']));
      expect(siblings.where((w) => w == 'para:US500'), hasLength(1));
      expect(siblings, isNot(contains('mkts:US500')));

      final urls = hlCoinIconCandidates('US500', 'mkts:US500', 'indices',
          siblingWires: siblings);
      expect(urls.first, 'https://app.hyperliquid.xyz/coins/mkts:US500.svg');
      expect(urls, contains('https://app.hyperliquid.xyz/coins/km:US500.svg'));
      // The stock-logo host stays the last resort.
      expect(urls.last, 'https://assets.parqet.com/logos/symbol/US500');
    });

    test('a Unit token tries the logo of the asset it holds', () {
      HlMarketDirectory.remember([
        const HlMarket(
          coin: 'UZEC',
          wireCoin: '@901',
          assetId: 10901,
          kind: HlMarketKind.spot,
          szDecimals: 2,
          maxLeverage: 1,
          onlyIsolated: false,
          markPx: 1,
          midPx: 1,
          prevDayPx: 1,
          dayNtlVlm: 1,
          unitAssetName: 'Zcash',
        ),
      ]);
      final urls = hlCoinIconCandidates('UZEC', '@901', 'crypto',
          siblingWires: hlIconSiblingWires('UZEC', '@901', 'crypto'));
      expect(urls, [
        'https://app.hyperliquid.xyz/coins/UZEC_spot.svg',
        'https://app.hyperliquid.xyz/coins/UZEC.svg',
        'https://app.hyperliquid.xyz/coins/UZEC_USDC.svg',
        'https://app.hyperliquid.xyz/coins/ZEC.svg',
      ]);
    });
  });

  group('last resorts', () {
    test('a crypto market ends with the bare venue image, then CoinCap', () {
      // Its own dex-qualified image first (then its twins on the dexes the
      // directory knows), the two last resorts after everything else.
      final nbt = hlIconUrlsFor('NBT', 'hyna:NBT', null, 'crypto');
      expect(nbt.first, 'https://app.hyperliquid.xyz/coins/hyna:NBT.svg');
      expect(nbt.sublist(nbt.length - 2), [
        'https://app.hyperliquid.xyz/coins/NBT.svg',
        'https://assets.coincap.io/assets/icons/nbt@2x.png',
      ]);
      expect(nbt.toSet(), hasLength(nbt.length), reason: 'no repeats');
      // A default-dex perp already tried the bare image: not twice.
      expect(hlIconUrlsFor('BTC', 'BTC', null, 'crypto'), [
        'https://app.hyperliquid.xyz/coins/BTC.svg',
        'https://assets.coincap.io/assets/icons/btc@2x.png',
      ]);
      // Upper case on the venue, lower case on CoinCap.
      expect(hlIconLastResorts('kPEPE', null), [
        'https://app.hyperliquid.xyz/coins/KPEPE.svg',
        'https://assets.coincap.io/assets/icons/kpepe@2x.png',
      ]);
    });

    test('a stock, index or commodity has none', () {
      expect(hlIconLastResorts('STX', 'stocks'), isEmpty);
      expect(hlIconLastResorts('GAS', 'commodities'), isEmpty);
      expect(hlIconUrlsFor('NVDA', 'xyz:NVDA', null, 'stocks').last,
          'https://assets.parqet.com/logos/symbol/NVDA');
    });

    test('a PNG body is told by its signature', () {
      expect(hlLooksLikePng(base64Decode(_png)), isTrue);
      expect(hlLooksLikePng(_bytes(_vector)), isFalse);
      expect(hlLooksLikePng(Uint8List(0)), isFalse);
    });
  });
}
