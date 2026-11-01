// The share cards' fonts for the tests and the renders: Inter (the card's
// family), the Material icons and, when this machine has it, Hiragino for
// the Japanese frames; and Sal's face for the footer mark.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardSal;
import 'package:kute/screens/shared/sal_sprite.dart'
    show SalSpriteCache, kSalSpriteDir;

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

/// Sal's face for the cards' footer mark, decoded from the bundle (the
/// manifest read directly: the sprite cache's own read does not run in a
/// test).
Future<void> loadShareCardSal() async {
  if (ShareCardSal.peek() != null) return;
  SalSpriteCache.debugSetManifest(jsonDecode(
          await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
      as Map<String, dynamic>);
  await ShareCardSal.load();
}
