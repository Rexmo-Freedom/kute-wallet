// Stamps a web build for the service worker. Run after every web build that
// is deployed:
//
//   flutter build web --release
//   dart run tool/web_pwa_stamp.dart            # or: ... build/web
//
// Writes into build/web:
//   - flutter_bootstrap.js and sw.js: BUILD, a sha256 of every file of the
//     build, so any change (code, asset, vendored wasm) is a new version;
//   - sw.js: PRECACHE, the app shell as [path, sha256] pairs: the page, the
//     bootstrap, main.dart.js, the CanvasKit builds the loader picks
//     (full and Chromium), the vendored Breez and BDK wasm, fonts, the asset
//     and font manifests, splash and icons. Other assets (images, sounds)
//     are cached as the app loads them.
// A build that is not stamped ships a kill-switch worker (see web/sw.js).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _buildPlaceholder = '__KUTE_BUILD__';
const _precachePlaceholder = '/*__KUTE_PRECACHE__*/[]';

void main(List<String> args) {
  final root = Directory(args.isEmpty ? 'build/web' : args.first);
  final bootstrap = File('${root.path}/flutter_bootstrap.js');
  final worker = File('${root.path}/sw.js');
  if (!bootstrap.existsSync() || !worker.existsSync()) {
    stderr.writeln('No web build at ${root.path} (run flutter build web).');
    exit(2);
  }
  final bootstrapSource = bootstrap.readAsStringSync();
  final workerSource = worker.readAsStringSync();
  if (!bootstrapSource.contains(_buildPlaceholder) ||
      !workerSource.contains(_buildPlaceholder) ||
      !workerSource.contains(_precachePlaceholder)) {
    stderr.writeln('${root.path} is already stamped (or the templates '
        'changed): rebuild before stamping.');
    exit(2);
  }

  String rel(File f) =>
      f.path.substring(root.path.length + 1).replaceAll(r'\', '/');
  String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

  // Every file but the worker: the build's identity.
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => rel(f) != 'sw.js')
      .toList()
    ..sort((a, b) => rel(a).compareTo(rel(b)));
  final hashes = <String, String>{
    for (final f in files) rel(f): hashOf(f.readAsBytesSync()),
  };
  final build = hashOf(utf8.encode(
          hashes.entries.map((e) => '${e.key} ${e.value}').join('\n')))
      .substring(0, 20);

  final stampedBootstrap = bootstrapSource.replaceAll(_buildPlaceholder, build);
  bootstrap.writeAsStringSync(stampedBootstrap);
  hashes['flutter_bootstrap.js'] = hashOf(utf8.encode(stampedBootstrap));

  final fonts = <String>{};
  final fontManifest = File('${root.path}/assets/FontManifest.json');
  if (fontManifest.existsSync()) {
    for (final family in jsonDecode(fontManifest.readAsStringSync()) as List) {
      for (final font in (family as Map)['fonts'] as List) {
        fonts.add('assets/${(font as Map)['asset']}');
      }
    }
  }
  final wasmBuild = hashes.containsKey('main.dart.wasm');
  bool inShell(String p) {
    if (const {
      'flutter_bootstrap.js',
      'version.json',
      'main.dart.js',
      'main.dart.mjs',
      'main.dart.wasm',
      'manifest.json',
      'favicon.png',
      'splash.js',
      'breez_boot.js',
      'bdk_boot.js',
      'assets/FontManifest.json',
      'assets/AssetManifest.bin.json',
      'assets/AssetManifest.bin',
      'canvaskit/canvaskit.js',
      'canvaskit/canvaskit.wasm',
      'canvaskit/chromium/canvaskit.js',
      'canvaskit/chromium/canvaskit.wasm',
    }.contains(p)) {
      return true;
    }
    if (wasmBuild &&
        RegExp(r'^canvaskit/(skwasm|skwasm_heavy)\.(js|wasm)$').hasMatch(p)) {
      return true;
    }
    if (RegExp(r'^main\.dart\.js_\d+\.part\.js$').hasMatch(p)) return true;
    if (RegExp(r'^(breez_sdk_spark|bdk_wallet_web)/.+\.(js|wasm)$')
        .hasMatch(p)) {
      return true;
    }
    if (RegExp(r'^(icons|splash/img)/[^/]+\.png$').hasMatch(p)) return true;
    if (p.startsWith('assets/shaders/')) return true;
    return fonts.contains(p);
  }

  final precache = <List<String>>[
    // The page, under the scope root: what a navigation is answered with.
    ['./', hashes['index.html']!],
    for (final p in hashes.keys.where(inShell).toList()..sort())
      [Uri(path: p).toString(), hashes[p]!],
  ];
  worker.writeAsStringSync(workerSource
      .replaceAll(_buildPlaceholder, build)
      .replaceAll(_precachePlaceholder, jsonEncode(precache)));

  var bytes = 0;
  for (final entry in precache) {
    final p = entry[0] == './' ? 'index.html' : Uri.decodeFull(entry[0]);
    bytes += File('${root.path}/$p').lengthSync();
  }
  stdout.writeln('Stamped ${root.path}: build $build, '
      '${precache.length} shell files '
      '(${(bytes / 1024 / 1024).toStringAsFixed(1)} MB) precached.');
}
