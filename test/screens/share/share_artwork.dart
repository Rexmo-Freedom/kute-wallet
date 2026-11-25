// The Polymarket artwork the share and brag cards draw (PolyCrestImage,
// the app's one image widget) in a test: its disk cache needs the
// platform's folders, which a test does not have. Offline (every test),
// each image fails at once and the app's own stand-in shows; for the
// on-demand renders ([online]), each image is downloaded into a temp
// folder, as a real phone would load it.

import 'dart:io';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';

class ShareTestArtwork implements BaseCacheManager {
  ShareTestArtwork({this.online = false});

  final bool online;
  static Directory? _dir;

  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) async {
    if (!online) throw const HttpException('no artwork in a test');
    final dir = _dir ??= Directory.systemTemp.createTempSync('share_art');
    final name = url.hashCode.toUnsigned(32).toRadixString(16);
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) {
      final client = HttpClient();
      try {
        final req = await client
            .getUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        final res = await req.close().timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) throw HttpException('${res.statusCode}');
        final bytes = <int>[];
        await for (final chunk in res) {
          bytes.addAll(chunk);
        }
        final svg = (res.headers.contentType?.mimeType ?? '').contains('svg');
        final path = svg ? '${file.path}.svg' : file.path;
        File(path).writeAsBytesSync(bytes);
        return const LocalFileSystem().file(path);
      } finally {
        client.close(force: true);
      }
    }
    return const LocalFileSystem().file(file.path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Installs the artwork stand-in (see the file header).
void useShareTestArtwork({bool online = false}) {
  PolyCrestImage.debugCacheManager = ShareTestArtwork(online: online);
}
