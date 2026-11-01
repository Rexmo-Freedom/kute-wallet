// lib/screens/share/brag/brag_sal.dart
//
// SAL ON THE BRAG CARD: one still per tone, rendered from the v5 rig
// (Sal 3D/v5 app, round r4-bragfun: hero framing, sitting, 1024 then
// cropped to 635 × 720, lossy WebP with lossless alpha):
//   * `brag_smug`: chin up, lids half down with smug lower lids, the
//     camera-left lid heavier (a raised-brow side-eye at the viewer), head
//     turned away, one ear cocked, front paws together;
//   * `brag_shades`: the same with black rectangular sunglasses on the
//     head bone, ONLY for a big win ([BragTone.bigWin]);
//   * `brag_unbothered`: the loss face, heavy lids, eyes off to the side,
//     chin still up ("character building").
//
// [BragSalStills] decodes them once (the preview warms them on open) so
// the card, which never loads anything itself, draws the right one.

import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'package:kute/screens/share/brag/brag_data.dart' show BragTone;

/// A still's width over its height.
const double kBragSalAspect = 635 / 720;

/// The asset for [tone].
String bragSalAsset(BragTone tone) => switch (tone) {
      BragTone.bigWin => 'lib/assets/sal/brag_shades.webp',
      BragTone.loss => 'lib/assets/sal/brag_unbothered.webp',
      BragTone.win ||
      BragTone.smallWin ||
      BragTone.flat =>
        'lib/assets/sal/brag_smug.webp',
    };

/// Whether [tone] gets Sal's sunglasses.
bool bragSalWearsShades(BragTone tone) => tone == BragTone.bigWin;

class BragSalStills {
  BragSalStills._();

  static final Map<String, ui.Image> _decoded = {};
  static final Map<String, Future<ui.Image?>> _loading = {};

  /// The decoded still for [tone], or null until [load] has finished.
  static ui.Image? peek(BragTone tone) => _decoded[bragSalAsset(tone)];

  /// Decodes the still for [tone] (once); null when it cannot be read.
  static Future<ui.Image?> load(BragTone tone) {
    final asset = bragSalAsset(tone);
    final done = _decoded[asset];
    if (done != null) return Future.value(done);
    return _loading[asset] ??= () async {
      try {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        codec.dispose();
        _decoded[asset] = frame.image;
        return frame.image;
      } catch (_) {
        return null;
      } finally {
        _loading.remove(asset)?.ignore();
      }
    }();
  }

  /// Tests: forget every decoded still.
  static void debugReset() {
    _decoded.clear();
    _loading.clear();
  }
}
