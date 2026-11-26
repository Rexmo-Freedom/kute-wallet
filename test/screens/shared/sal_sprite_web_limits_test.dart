// The web's Sal memory limits (sal_sprite.dart header, 26 November 2026:
// Safari on an iPhone reloaded the page on the Dollars empty state): never
// @3x, a lower cap, a warm list decoded one sheet after another, and the
// empty states' Sal reading only what he shows first. Phones unchanged.
// `kIsWeb` cannot be flipped in a test: SalSpriteCache.debugWebOverride
// stands in for it.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/sal_sprite.dart';

SalClip _sheet({bool loop = true}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 64, 48), Paint()..color = Colors.brown);
  return SalClip(
      image: recorder.endRecording().toImageSync(64, 48),
      fps: 24,
      frames: 48,
      columns: 8,
      cellWidth: 8,
      cellHeight: 8,
      loop: loop,
      body: true);
}

Map<String, dynamic> _entry({bool loop = true}) => {
      'framing': 'body',
      'fps': 24,
      'frames': 48,
      'columns': 8,
      'rows': 6,
      'loop': loop,
      'group': 'hero',
      'files': {
        '2x': {'file': 'none@2x.webp'},
        '3x': {'file': 'none@3x.webp'},
      },
    };

const _hero = [
  'body_hero',
  'hero_look_around',
  'hero_stretch',
  'hero_sleep',
  'hero_wake',
];

const int _mib = 1024 * 1024;

void main() {
  tearDown(() {
    SalSpriteCache.debugWebOverride = null;
    SalSpriteCache.debugRequestLog = null;
    SalSpriteCache.debugReset();
  });

  group('density', () {
    test('the web picks @2x whatever the pixel ratio', () {
      SalSpriteCache.debugWebOverride = true;
      expect(SalSpriteCache.densityFor(3), 2);
      expect(SalSpriteCache.densityFor(2.5), 2);
      expect(SalSpriteCache.densityFor(1), 2);
      expect(SalSpriteCache.fullDensity, 2);
    });

    test('phones still pick @3x from 2.5 up', () {
      SalSpriteCache.debugWebOverride = false;
      expect(SalSpriteCache.densityFor(3), 3);
      expect(SalSpriteCache.densityFor(2.5), 3);
      expect(SalSpriteCache.densityFor(2), 2);
      expect(SalSpriteCache.fullDensity, 3);
      // And with no override at all (the test VM is not the web).
      SalSpriteCache.debugWebOverride = null;
      expect(SalSpriteCache.densityFor(3), 3);
    });
  });

  group('cap', () {
    test('the web cap holds the hero loop plus two more @2x hero sheets', () {
      // A hero sheet: 2880 x 3840 at @3x, 1920 x 2560 at @2x.
      const hero2x = 1920 * 2560 * 4;
      const hero3x = 2880 * 3840 * 4;
      expect(hero2x / _mib, closeTo(18.75, 0.01));
      expect(hero3x / _mib, closeTo(42.19, 0.01));
      expect(kSalSpriteCacheWebMaxBytes, 64 * _mib);
      expect(3 * hero2x, lessThanOrEqualTo(kSalSpriteCacheWebMaxBytes));
      expect(4 * hero2x, greaterThan(kSalSpriteCacheWebMaxBytes));
    });

    test('the web starts with the web cap; phones with the old one', () {
      SalSpriteCache.debugWebOverride = true;
      SalSpriteCache.debugReset();
      expect(SalSpriteCache.maxBytes, kSalSpriteCacheWebMaxBytes);
      SalSpriteCache.debugWebOverride = false;
      SalSpriteCache.debugReset();
      expect(SalSpriteCache.maxBytes, kSalSpriteCacheMaxBytes);
    });
  });

  group('warm', () {
    /// Loader whose reads stay out until the test completes them.
    Map<String, Completer<SalClip?>> pendingLoader() {
      final reads = <String, Completer<SalClip?>>{};
      SalSpriteCache.debugSetManifest({for (final n in _hero) n: _entry()});
      SalSpriteCache.debugLoader = (name, density) {
        final c = Completer<SalClip?>();
        reads[name] = c;
        return c.future;
      };
      return reads;
    }

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('the web reads one sheet at a time, in order', () async {
      SalSpriteCache.debugWebOverride = true;
      final reads = pendingLoader();
      final done = SalSpriteCache.warm(_hero.take(3), 2);
      await settle();
      expect(reads.keys.toList(), ['body_hero']);
      reads['body_hero']!.complete(_sheet());
      await settle();
      expect(reads.keys.toList(), ['body_hero', 'hero_look_around']);
      reads['hero_look_around']!.complete(null);
      await settle();
      expect(reads.keys.toList(),
          ['body_hero', 'hero_look_around', 'hero_stretch']);
      reads['hero_stretch']!.complete(_sheet());
      expect(await done, ['hero_look_around']);
    });

    test('phones still ask for the whole list at once', () async {
      SalSpriteCache.debugWebOverride = false;
      final reads = pendingLoader();
      final done = SalSpriteCache.warm(_hero.take(3), 3);
      await settle();
      expect(reads.keys.toSet(),
          {'body_hero', 'hero_look_around', 'hero_stretch'});
      for (final r in reads.values) {
        r.complete(_sheet());
      }
      expect(await done, isEmpty);
    });
  });

  group('the empty states\' Sal', () {
    Widget app(Widget child) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: Center(child: child),
          ),
        );

    SalIdleDirector director() => SalIdleDirector(
          size: 120,
          fallback: const SizedBox(),
          sleepAfter: const Duration(seconds: 60),
          random: math.Random(3),
        );

    void stage() {
      SalSpriteCache.debugSetManifest({
        for (final n in _hero)
          n: _entry(loop: n != 'hero_stretch' && n != 'hero_wake'),
      });
      SalSpriteCache.debugLoader = (name, density) async =>
          _sheet(loop: name != 'hero_stretch' && name != 'hero_wake');
    }

    testWidgets(
        'web: on mount only the hero loop and the next beat are read, @2x',
        (tester) async {
      SalSpriteCache.debugWebOverride = true;
      stage();
      final log = <String>[];
      SalSpriteCache.debugRequestLog = log;
      await tester.pumpWidget(app(director()));
      await tester.pump();
      await tester.pump();
      expect(log.toSet().difference({'body_hero'}).length, lessThanOrEqualTo(1),
          reason: 'one beat read ahead at most: $log');
      expect(log, contains('body_hero'));
      expect(log, isNot(contains('hero_sleep')));
      expect(log, isNot(contains('hero_wake')));
      expect(SalSpriteCache.residentAt(3), isEmpty);
      expect(SalSpriteCache.residentAt(2).length, lessThanOrEqualTo(2));

      // The beat plays from its read-ahead sheet, without a blank.
      var cue = tester.widget<SalSprite>(find.byType(SalSprite)).cue;
      String? played;
      for (var ms = 0; ms < 16000 && played == null; ms += 100) {
        await tester.pump(const Duration(milliseconds: 100));
        final s = tester.widget<SalSprite>(find.byType(SalSprite));
        if (s.cue != cue) {
          cue = s.cue;
          played = s.clip;
        }
      }
      expect(played, isNotNull);
      expect(SalSpriteCache.ready(played!, 2), isNotNull);

      // The sleep loop is read about 10 s before he sleeps, not before.
      log.clear();
      await tester.pump(const Duration(seconds: 30));
      expect(log, isNot(contains('hero_sleep')));
      await tester.pump(const Duration(seconds: 25));
      expect(log, contains('hero_sleep'));
      await tester.pump(const Duration(seconds: 10));
      expect(
          tester.widget<SalSprite>(find.byType(SalSprite)).clip, 'hero_sleep');
      // Asleep, the wake is read.
      expect(log, contains('hero_wake'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('phones still decode the whole pool on mount', (tester) async {
      SalSpriteCache.debugWebOverride = false;
      stage();
      final log = <String>[];
      SalSpriteCache.debugRequestLog = log;
      await tester.pumpWidget(app(director()));
      await tester.pump();
      await tester.pump();
      expect(log.toSet(), _hero.toSet());
      expect(SalSpriteCache.residentAt(3).toSet(), _hero.toSet());
      await tester.pumpWidget(const SizedBox());
    });
  });
}
