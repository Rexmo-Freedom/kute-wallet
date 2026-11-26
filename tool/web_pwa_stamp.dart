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
//
// Before stamping, the font manifest loses the package icon fonts the
// compiled app never names (pruneUnusedPackageFonts): Flutter web fetches
// and registers every family in assets/FontManifest.json at start, and
// icons_plus alone lists fifteen icon fonts (4.6 MB) the app does not use
// (it uses that package's flag images only). The files stay in the build;
// only the start-up load goes.

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

  final pruned = pruneUnusedPackageFonts(root);
  if (pruned.isNotEmpty) {
    stdout.writeln('Font manifest: dropped ${pruned.length} package fonts '
        'the app never names (${pruned.join(', ')}).');
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

/// Removes from `assets/FontManifest.json` every package font family
/// (`packages/<package>/<Family>`) whose family name the compiled app
/// never names: a widget that draws with a family carries its name as a
/// string literal ("Iconsax") in main.dart.js (or a deferred part). The
/// app's own families (no `packages/` prefix) and MaterialIcons are always
/// kept. Returns the families removed; a build without main.dart.js (a
/// wasm-only build) or without a manifest is left as it is.
List<String> pruneUnusedPackageFonts(Directory root) {
  final manifest = File('${root.path}/assets/FontManifest.json');
  final scripts = root
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'[/\\]main\.dart\.js(_\d+\.part\.js)?$')
          .hasMatch(f.path))
      .toList();
  if (!manifest.existsSync() || scripts.isEmpty) return const [];
  final code = scripts.map((f) => f.readAsStringSync()).join('\n');
  final families = jsonDecode(manifest.readAsStringSync()) as List;
  final kept = <Object?>[];
  final pruned = <String>[];
  for (final entry in families) {
    final family = (entry as Map)['family'] as String;
    final parts = family.split('/');
    final isPackageFont = parts.length == 3 && parts.first == 'packages';
    if (isPackageFont &&
        !code.contains('"${parts.last}"') &&
        !code.contains("'${parts.last}'")) {
      pruned.add(family);
    } else {
      kept.add(entry);
    }
  }
  if (pruned.isNotEmpty) manifest.writeAsStringSync(jsonEncode(kept));
  return pruned;
}
