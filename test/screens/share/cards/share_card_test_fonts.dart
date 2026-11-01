// The share cards' fonts for the tests and the renders: Inter (the card's
// family), the Material icons (the chip's arrow) and, when this machine
// has it, Hiragino for the Japanese frames.

import 'dart:io';

import 'package:flutter/services.dart';

import '../brag/brag_test_fonts.dart';

bool _loaded = false;

Future<void> loadShareCardFonts() async {
  await loadBragFonts();
  if (_loaded) return;
  try {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  } catch (_) {}
  for (final path in [
    '/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc',
    '/Library/Fonts/Arial Unicode.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    try {
      final bytes = f.readAsBytesSync();
      final cjk = FontLoader('Hiragino Sans')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await cjk.load();
      break;
    } catch (_) {}
  }
  _loaded = true;
}
