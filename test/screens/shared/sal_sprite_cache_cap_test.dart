// SalSpriteCache's cap (sal_sprite.dart, 9 November 2026): a body sheet
// decodes to 27 MiB at @3x, so the cache holds at most maxBytes of
// decoded sheets, least recently used given up first; a clip given up
// is read again when it is next asked for, and asking whether a clip is
// decoded (ready) starts no read.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

/// A sheet of [side] x [side] pixels: side * side * 4 bytes decoded.
SalClip _sheet(int side) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..color = Colors.brown);
  return SalClip(
      image: recorder.endRecording().toImageSync(side, side),
      fps: 20,
      frames: 1,
      columns: 1,
      cellWidth: side.toDouble(),
      cellHeight: side.toDouble(),
      loop: true,
      body: true);
}

void main() {
  tearDown(SalSpriteCache.debugReset);

  test('the default cap is 120 MiB: four @3x body sheets and the faces', () {
    expect(kSalSpriteCacheMaxBytes, 120 * 1024 * 1024);
    // A body sheet at @3x: 2304 x 3072, four bytes a pixel.
    const body = 2304 * 3072 * 4;
    expect(body / (1024 * 1024), closeTo(27.0, 0.01));
    expect(4 * body, lessThan(kSalSpriteCacheMaxBytes));
    expect(5 * body, greaterThan(kSalSpriteCacheMaxBytes));
  });

  test('over the cap, the least recently used clip is given up first',
      () async {
    SalSpriteCache.debugSetManifest({
      for (final n in ['a', 'b', 'c']) n: {'framing': 'body', 'frames': 1},
    });
    const one = 16 * 16 * 4;
    SalSpriteCache.maxBytes = 2 * one;
    SalSpriteCache.debugPutClip('a', 3, _sheet(16));
    SalSpriteCache.debugPutClip('b', 3, _sheet(16));
    expect(SalSpriteCache.residentBytes, 2 * one);
    // A use of a: b is now the least recently used.
    expect(SalSpriteCache.ready('a', 3), isNotNull);
    SalSpriteCache.debugPutClip('c', 3, _sheet(16));
    expect(SalSpriteCache.residentAt(3).toSet(), {'a', 'c'});
    expect(SalSpriteCache.residentBytes, 2 * one);
    // Asking after b starts no read and finds nothing.
    SalSpriteCache.debugRequestLog = [];
    addTearDown(() => SalSpriteCache.debugRequestLog = null);
    expect(SalSpriteCache.ready('b', 3), isNull);
    expect(SalSpriteCache.debugRequestLog, isEmpty);
    // Asking for it reads it again (and gives up the oldest, a).
    expect(await SalSpriteCache.clip('b', 3), isNotNull);
    expect(SalSpriteCache.debugRequestLog, ['b']);
    expect(SalSpriteCache.residentAt(3).toSet(), {'c', 'b'});
    expect(SalSpriteCache.residentBytes, lessThanOrEqualTo(2 * one));
  });

  test('evict gives a clip up at once; a clip larger than the cap is still '
      'held alone', () async {
    SalSpriteCache.debugSetManifest({
      for (final n in ['a', 'big']) n: {'framing': 'body', 'frames': 1},
    });
    SalSpriteCache.maxBytes = 16 * 16 * 4;
    SalSpriteCache.debugPutClip('a', 3, _sheet(16));
    SalSpriteCache.evict('a', 3);
    expect(SalSpriteCache.ready('a', 3), isNull);
    expect(SalSpriteCache.residentBytes, 0);
    SalSpriteCache.debugPutClip('big', 3, _sheet(32));
    expect(SalSpriteCache.residentAt(3), ['big']);
  });

  test('a clip given up while its read was out is not held when it lands',
      () async {
    SalSpriteCache.debugSetManifest({
      'a': {'framing': 'body', 'frames': 1},
    });
    SalSpriteCache.debugLoader = (name, density) async => _sheet(8);
    final reading = SalSpriteCache.clip('a', 3);
    SalSpriteCache.evict('a', 3);
    expect(await reading, isNotNull, reason: 'the caller still gets it');
    expect(SalSpriteCache.residentBytes, 0);
  });
}
