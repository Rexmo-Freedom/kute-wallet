// Ships the Investing (Hyperliquid) market logos with the web build, so the
// web app draws them inside its own canvas instead of as `<img>` elements.
// Run after `flutter build web` and before the stamp:
//
//   flutter build web --release
//   dart run tool/web_hl_logos.dart             # or: ... build/web
//   dart run tool/web_pwa_stamp.dart
//
// Why: the logo hosts send no CORS headers, so the web app could only show
// them as `<img>` platform views, and on Safari each one costs a
// full-screen WebGL canvas (the Dollars home reloaded on phones). A file on
// the app's own origin needs no CORS: lib/screens/hyperliquid/components/
// hl_web_logos.dart reads it and draws it like the phones draw a downloaded
// logo.
//
// Writes into build/web only (never Flutter assets, so the phone apps do not
// grow):
//   - logos/hl/<hash>.<svg|png>: every logo the app's own candidate rules
//     can ask for (hlCoinIconCandidates: <wire>.svg for each perp of every
//     dex, <TOKEN>_spot.svg / <TOKEN>.svg / <TOKEN>_USDC.svg for each spot
//     token, and parqet's ticker logo for a builder-dex market Hyperliquid
//     has no logo for), in the original format;
//   - logos/hl/index.json: {remote URL: path under build/web}.
// A request that fails, a body that is not an SVG or a PNG (Hyperliquid
// answers a missing logo with its HTML page), or one past the size cap is
// skipped. The service worker does not precache these (they load on
// demand), and a market listed after the build shows its monogram.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

const String _info = 'https://api.hyperliquid.xyz/info';
const String _coins = 'https://app.hyperliquid.xyz/coins/';
const String _parqet = 'https://assets.parqet.com/logos/symbol/';

/// The largest logo shipped. Real marks are a few kilobytes (median about
/// 3 KB); what is heavier is a photo wrapped in an SVG (some spot memecoin
/// tokens, up to 1.3 MB each), which a phone browser would have to hold
/// and decode for a 32-pixel circle. Those are skipped: the market shows
/// its name alone, as one without a logo.
const int kWebLogoMaxBytes = 128 * 1024;

/// Where the logos and their index go, under the build root.
const String kWebLogoDir = 'logos/hl';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? 'build/web' : args.first);
  if (!File('${root.path}/index.html').existsSync()) {
    stderr.writeln('No web build at ${root.path} (run flutter build web).');
    exit(2);
  }
  final client = http.Client();
  try {
    final markets = await listMarkets(client);
    final hl = <String>{};
    for (final m in markets.perps) {
      hl.add('$_coins$m.svg');
    }
    for (final t in markets.spotTokens) {
      hl
        ..add('$_coins${t}_spot.svg')
        ..add('$_coins$t.svg')
        ..add('$_coins${t}_USDC.svg');
    }
    final fetch = httpLogoFetcher(client);
    final first = await downloadLogos(hl, fetch: fetch);
    // Builder-dex markets (stocks, indices, commodities) Hyperliquid has no
    // logo for: the ticker's logo from parqet, as the app falls back to.
    final parqet = <String>{
      for (final m in markets.perps)
        if (m.contains(':') && !first.containsKey('$_coins$m.svg'))
          '$_parqet${m.split(':').last.toUpperCase()}',
    };
    final second = await downloadLogos(parqet, fetch: fetch);
    final logos = {...first, ...second};
    final summary = writeLogos(root, logos);
    stdout.writeln('Web logos: ${logos.length} of ${hl.length + parqet.length} '
        'candidates (${(summary / 1024).toStringAsFixed(0)} KB) in '
        '${root.path}/$kWebLogoDir; the rest skipped.');
  } catch (e) {
    // No logos is a working build: every market shows its monogram.
    stderr.writeln('Web logos: skipped ($e).');
    writeLogos(root, const {});
  } finally {
    client.close();
  }
}

/// Every perp's wire name (`BTC`, `xyz:TSLA`) on every dex, and every spot
/// token traded in a pair.
Future<({List<String> perps, List<String> spotTokens})> listMarkets(
    http.Client client) async {
  Future<Object?> post(Map<String, Object?> body) async {
    final r = await client
        .post(Uri.parse(_info),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw HttpException('info ${r.statusCode}');
    return jsonDecode(r.body);
  }

  final dexes = <String?>[null];
  for (final d in (await post({'type': 'perpDexs'}) as List)) {
    if (d is Map && d['name'] is String) dexes.add(d['name'] as String);
  }
  final perps = <String>[];
  for (final dex in dexes) {
    final meta = await post({'type': 'meta', if (dex != null) 'dex': dex});
    for (final a in ((meta as Map)['universe'] as List)) {
      final name = (a as Map)['name'];
      if (name is String && name.isNotEmpty) perps.add(name);
    }
  }
  final spot = await post({'type': 'spotMeta'}) as Map;
  final tokens = spot['tokens'] as List;
  final traded = <String>{};
  for (final pair in spot['universe'] as List) {
    final ids = (pair as Map)['tokens'] as List;
    if (ids.isEmpty) continue;
    final base = ids.first;
    for (final t in tokens) {
      if ((t as Map)['index'] == base && t['name'] is String) {
        traded.add(t['name'] as String);
      }
    }
  }
  return (perps: perps, spotTokens: traded.toList()..sort());
}

/// One download: the body, or null for a failure of any kind.
typedef LogoFetcher = Future<Uint8List?> Function(String url);

LogoFetcher httpLogoFetcher(http.Client client) => (url) async {
      try {
        final r = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        return r.statusCode == 200 ? r.bodyBytes : null;
      } catch (_) {
        return null;
      }
    };

/// What a logo file is: 'svg', 'png', or null for anything else (an HTML
/// page, an error document, an empty body) or a body past the cap.
String? logoKind(Uint8List body) {
  if (body.isEmpty || body.length > kWebLogoMaxBytes) return null;
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (body.length >= png.length &&
      Iterable.generate(png.length).every((i) => body[i] == png[i])) {
    return 'png';
  }
  final head = utf8
      .decode(body.take(512).toList(), allowMalformed: true)
      .trimLeft()
      .toLowerCase();
  if (head.contains('<html') || head.startsWith('<!doctype')) return null;
  if (head.startsWith('<svg') ||
      (head.startsWith('<?xml') && head.contains('<svg'))) {
    return 'svg';
  }
  return null;
}

/// Downloads [urls], [concurrency] at a time, keeping each usable logo
/// ({url: (kind, bytes)}); failures and non-logos are left out.
Future<Map<String, (String, Uint8List)>> downloadLogos(Iterable<String> urls,
    {required LogoFetcher fetch, int concurrency = 8}) async {
  final queue = urls.toList();
  final out = <String, (String, Uint8List)>{};
  var next = 0;
  Future<void> worker() async {
    while (next < queue.length) {
      final url = queue[next++];
      Uint8List? body;
      try {
        body = await fetch(url);
      } catch (_) {
        body = null;
      }
      if (body == null) continue;
      final kind = logoKind(body);
      if (kind != null) out[url] = (kind, body);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  return out;
}

/// The file name a logo is stored under: a digest of its bytes, so the
/// same logo under two URLs (<TOKEN>_spot.svg and <TOKEN>_USDC.svg) is one
/// file, and wire names (':' and '@') never reach a path.
String logoFileName(Uint8List body, String kind) =>
    '${sha256.convert(body).toString().substring(0, 20)}.$kind';

/// Writes [logos] and the index under [root]/[kWebLogoDir], replacing what
/// an earlier run wrote. Returns the bytes written.
int writeLogos(Directory root, Map<String, (String, Uint8List)> logos) {
  final dir = Directory('${root.path}/$kWebLogoDir');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final index = <String, String>{};
  var bytes = 0;
  final urls = logos.keys.toList()..sort();
  for (final url in urls) {
    final (kind, body) = logos[url]!;
    final name = logoFileName(body, kind);
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) {
      file.writeAsBytesSync(body);
      bytes += body.length;
    }
    index[url] = '$kWebLogoDir/$name';
  }
  File('${dir.path}/index.json').writeAsStringSync(jsonEncode(index));
  return bytes;
}
