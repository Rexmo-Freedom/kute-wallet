// Inter for the brag card tests: the card names the bundled family, so
// its layout is measured with the real glyphs, not the test font.

import 'package:flutter/services.dart';

import 'package:kute/screens/polymarket/components/poly_crest_image.dart'
    show PolyCrestImage;

import '../share_artwork.dart';

bool _loaded = false;

Future<void> loadBragFonts() async {
  // The cards' Polymarket artwork, offline unless a render installed the
  // online one.
  if (PolyCrestImage.debugCacheManager == null) useShareTestArtwork();
  if (_loaded) return;
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
  _loaded = true;
}
