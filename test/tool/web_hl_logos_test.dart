// tool/web_hl_logos.dart ships only real logos: a failed or thrown
// download, an HTML page (Hyperliquid's answer for a missing logo) and an
// oversized body are skipped; SVG and PNG are kept and indexed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/web_hl_logos.dart';

void main() {
  Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));
  final png = Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]);

  test('failed downloads and non-logos are skipped', () async {
    final bodies = <String, Uint8List?>{
      'svg': text('<svg viewBox="0 0 1 1"><path d="M0 0"/></svg>'),
      'xml': text('<?xml version="1.0"?><svg></svg>'),
      'png': png,
      'html': text('<!DOCTYPE html><html><body>app</body></html>'),
      'empty': Uint8List(0),
      'failed': null,
      'huge': Uint8List(kWebLogoMaxBytes + 1)..setAll(0, text('<svg')),
    };
    final logos = await downloadLogos([...bodies.keys, 'throws'],
        fetch: (url) async {
      if (url == 'throws') throw const SocketException('down');
      return bodies[url];
    });
    expect(logos.keys.toSet(), {'svg', 'xml', 'png'});
    expect(logos['png']!.$1, 'png');
    expect(logos['svg']!.$1, 'svg');
  });

  test('the index maps each remote URL to its file', () {
    final root = Directory.systemTemp.createTempSync('hl_logos');
    addTearDown(() => root.deleteSync(recursive: true));
    final url = 'https://app.hyperliquid.xyz/coins/xyz:SOXL.svg';
    final bytes =
        writeLogos(root, {url: ('svg', text('<svg></svg>'))});
    expect(bytes, 11);
    final index = jsonDecode(
            File('${root.path}/$kWebLogoDir/index.json').readAsStringSync())
        as Map;
    final path = index[url] as String;
    expect(path, startsWith('$kWebLogoDir/'));
    expect(path, endsWith('.svg'));
    expect(path, isNot(contains(':')));
    expect(File('${root.path}/$path').readAsStringSync(), '<svg></svg>');
    // One logo under two URLs is one file.
    writeLogos(root, {
      'a': ('svg', text('<svg></svg>')),
      'b': ('svg', text('<svg></svg>')),
    });
    expect(Directory('${root.path}/$kWebLogoDir').listSync().length, 2);
    // A second run replaces the first.
    writeLogos(root, const {});
    expect(Directory('${root.path}/$kWebLogoDir').listSync().length, 1);
  });
}
