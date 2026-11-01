// Inter for the brag card tests: the card names the bundled family, so
// its layout is measured with the real glyphs, not the test font.

import 'package:flutter/services.dart';

bool _loaded = false;

Future<void> loadBragFonts() async {
  if (_loaded) return;
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
  _loaded = true;
}
