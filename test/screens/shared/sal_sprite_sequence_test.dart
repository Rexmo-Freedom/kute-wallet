import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

/// A loop that repeats itself stores each distinct cell once (the balance
/// goals' level loops, 7 November 2026): the manifest's `cells` and
/// `sequence`, and [SalClip.cell] reading through it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ui.Image image(int w, int h) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    return recorder.endRecording().toImageSync(w, h);
  }

  test(
      'a sequence maps each played frame to its cell; without one, frame i '
      'is cell i', () {
    final sheet = image(30, 20); // 3 columns x 2 rows of 10 px cells
    final plain = SalClip(
      image: sheet,
      fps: 12,
      frames: 5,
      columns: 3,
      cellWidth: 10,
      cellHeight: 10,
      loop: true,
      body: true,
    );
    expect(plain.cell(4), const Rect.fromLTWH(10, 10, 10, 10));
    final seq = SalClip(
      image: sheet,
      fps: 12,
      frames: 6,
      columns: 3,
      cellWidth: 10,
      cellHeight: 10,
      loop: true,
      body: true,
      sequence: const [0, 0, 1, 4, 4, 2],
    );
    expect(seq.cell(0), const Rect.fromLTWH(0, 0, 10, 10));
    expect(seq.cell(1), const Rect.fromLTWH(0, 0, 10, 10));
    expect(seq.cell(3), const Rect.fromLTWH(10, 10, 10, 10));
    expect(seq.cell(5), const Rect.fromLTWH(20, 0, 10, 10));
    // Past the end: the last played frame.
    expect(seq.cell(99), const Rect.fromLTWH(20, 0, 10, 10));
    expect(seq.duration, const Duration(milliseconds: 500));
  });

  testWidgets(
      'the bundled level loops read as 48 played frames over their distinct '
      'cells, the sheet laid out by the cells', (tester) async {
    await tester.runAsync(() async {
      final manifest = jsonDecode(
              await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>;
      SalSpriteCache.debugSetManifest(manifest);
      for (final name in ['level_3', 'goal_next']) {
        final entry = manifest[name] as Map<String, dynamic>;
        final cells = entry['cells'] as int;
        final sequence = (entry['sequence'] as List).cast<int>();
        for (final density in [2, 3]) {
          final clip = (await SalSpriteCache.clip(name, density))!;
          expect(clip.frames, sequence.length, reason: name);
          expect(clip.frames, 48, reason: name);
          expect(clip.loop, isTrue, reason: name);
          final side = 64.0 * density;
          expect(clip.cellWidth, side, reason: '$name @$density');
          expect(clip.cellHeight, side, reason: '$name @$density');
          expect(clip.image.height, (cells / clip.columns).ceil() * side);
          for (var i = 0; i < clip.frames; i++) {
            final c = sequence[i];
            expect(
                clip.cell(i),
                Rect.fromLTWH((c % clip.columns) * side,
                    (c ~/ clip.columns) * side, side, side),
                reason: '$name frame $i');
          }
        }
      }
      SalSpriteCache.debugReset();
    });
  });
}
