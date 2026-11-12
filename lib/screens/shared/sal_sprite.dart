// lib/screens/shared/sal_sprite.dart
//
// THE 3D SAL (founder, 31 October 2026: the Blender Sal, official v5, over
// the code-drawn pixel rig, everywhere Sal appears). Sal's clips are
// rendered to sprite sheets in `lib/assets/sal/`: `<clip>@2x.png` and
// `<clip>@3x.png`, a grid of cells read left to right, top to bottom, and
// `manifest.json` naming each clip's `fps`, `frames`, `columns`, `cell`,
// `loop` and `framing`:
//
//   * face framing (cell 48 logical): `search`, `idle`, `happy`, `sad`,
//     `curious`, `surprised` (stills), `blink` (a 24-frame loop);
//   * body framing (cell 128 logical, 24 frames at 12 fps): `body_idle`,
//     `body_walk`, `body_sit_down` (one-shot), `body_sit`, `body_lie_down`
//     (one-shot), `body_lie`, `body_wag`, `body_cheer`, `body_sad`,
//     `body_sniff`, `body_nudge` (one-shot), `body_search`.
//
// [SalSprite] paints the current cell of one clip: the sheet is decoded
// ONCE per clip and density (a cached `ui.Image`), a [Ticker] advances the
// frame, and a [CustomPainter] draws that cell with `drawImageRect`. No
// Image widget per frame, no decoding per frame; the paint is inside its
// own repaint boundary so nothing around him repaints with him. The sheet
// matching the device's pixel ratio is used (@3x from 2.5 up). [speed]
// scales the clip's fps; [loop] overrides the manifest's; a one-shot holds
// its last frame and calls [onComplete] once. [SalSprite.sequence] plays
// a one-shot and then a loop (body_sit_down → body_sit). Under Reduce
// Motion frame 0 is all there is; while an ancestor TickerMode is off the
// ticker is muted; unmounted, it stops. On a dark background a body clip
// gets a 6% white radial glow behind it, so the render's contact shadow
// does not float (the renders are lit for light).
//
// ONE CONTINUOUS PERFORMANCE (founder, 31 October 2026: "the animation
// should loop, not stop and load a new one"). A clip change is never a
// remount: the SAME sprite, the same ticker, switches clips in place
// ([SalSprite.clip] or [SalSprite.cue] changing), and
//
//   * the clip on screen keeps painting until the incoming one is decoded
//     (a clip already in [SalSpriteCache] is taken synchronously, so a
//     cached clip never shows an empty frame, not even on mount);
//   * the switch lands on a frame boundary of the outgoing clip: a loop
//     gives way as it comes back to frame 0, a one-shot once its last
//     frame has had its time ([switchAtBoundary], on by default); the
//     incoming clip starts at frame 0 with the tick's overshoot carried
//     over, so the beat is not lost;
//   * the two cells cross-dissolve for [crossfade] (120 ms, an exact
//     lerp in a layer: outgoing at 1−t, incoming added at t), so clips
//     whose poses match pass unseen and clips whose poses differ blend
//     instead of cutting;
//   * Reduce Motion switches at once to frame 0, no dissolve; the
//     directors below do not switch at all under it.
//
// UNTIL A SHEET EXISTS the widget must not break the screen: a missing
// manifest or sheet falls back to [fallback], the rig drawing that site
// wore before (kute_dog_rig.dart / kute_dog_scenes.dart stay in place for
// that), so the app runs either way. A clip that is in the manifest but
// cannot be read says so once through [onUnavailable], so a director can
// drop it from its pool and move on; the clip on screen stays. A read
// still out is never a failure: the widget draws nothing until it lands,
// and a painter of its own ([SalSpriteCache.peek]) asks
// [SalSpriteCache.failed] before it reaches for its last resort (founder,
// 9 November 2026: never the pixel Sal for a wait on a read).
//
// A LOOP THAT REPEATS ITSELF (the balance goals' level loops, 7 November
// 2026) may store each distinct cell once: its entry then carries
// `"cells"` (the sheet's cells) and `"sequence"` (the cell each played
// frame shows; `frames` is its length), so a 4 s breath costs a dozen
// cells, not 48. [SalClip.cell] reads through it; nothing else changes.
//
// THE SECOND CLIP BATCH (founder, 31 October 2026) adds a `group` to each
// manifest entry, read through [SalSpriteCache.groups] / [SalSpriteCache.group]:
//
//   * `hero`: one-shots cut into the `body_hero` loop (`hero_stretch`,
//     `hero_look_around`, `hero_scratch`, `hero_tail_chase`), the
//     `hero_sleep` loop and the `hero_wake` one-shot;
//   * `waiting`: the money journey's waits (`body_dig`, `body_pace`,
//     `body_sniff_trail`, `body_point`, `body_think`, `body_nod`,
//     `body_shake_no`, `body_shake_off`, `body_jump`);
//   * `reaction`: face one-shots the bar plays (`wink`, `yawn`, `nod`,
//     `shake_no`, `think`, `cheer`; sal_reactions.dart).
//
// A director pre-decodes its whole group once on mount
// ([SalSpriteCache.warm] / [SalSpriteCache.warmGroup]); the cache keeps
// the images, so a switch never waits on a read, up to a cap.
//
// THE CAP (9 November 2026). A body sheet decodes to 27 MiB at @3x
// (2304 x 3072 RGBA; body_hero 42 MiB), and the money journey alone wore
// 24 of them (648 MiB): far past what iOS lets an app keep on an older
// iPhone. The cache holds at most [SalSpriteCache.maxBytes] (120 MiB) of
// decoded sheets, least recently used given up first ([peek] and
// [SalSpriteCache.ready] count as a use); a clip given up is read again
// when it is next asked for. Giving one up only drops the cache's hold:
// a sprite still showing it keeps its own, and nothing is disposed.
//
// [SalIdleDirector] is the empty states' Sal, calm (founder, 12 November
// 2026: "an occasional blink/stretch on a slow random cadence, not
// constant motion"): he stands still in the hero pose, and every 8–15 s
// plays ONE beat ([kSalIdleBeats]: one pass of `body_hero`, which is his
// blink, `hero_look_around` or `hero_stretch`; never the same twice in a
// row) and holds its last frame, which is the hero pose again. After 60 s
// without a touch anywhere in the app he sleeps (`hero_sleep`), and the
// next pointer wakes him (`hero_wake`, then still). The beats stop while
// he is off screen (an ancestor TickerMode off: a covered route, a tab
// away) or the app is in the background, and when he is gone. A clip the
// manifest lacks, or that fails to read, is skipped; nothing ever
// crashes for a missing clip. Reduce Motion: `body_hero`'s first frame,
// nothing else.
//
// ONE SAL AT A TIME (founder, 12 November 2026: "never two Sals animating
// at once in the same view"). [SalSpotlight] is who is performing now: a
// Sal toast on screen, a result sheet up, the money journey while the
// money moves, and an empty state's Sal during his beat hold it; while it
// is held the bar's Sals finish the pass they are in and hold its last
// frame, a bar reaction is not played, the busy button's waiting Sal
// starts no new pass and an empty state's beat waits for its next turn.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where the sheets and the manifest live.
const String kSalSpriteDir = 'lib/assets/sal';

/// The most decoded bytes [SalSpriteCache] holds: four @3x body sheets
/// and the result sheet's faces (see the file header).
const int kSalSpriteCacheMaxBytes = 120 * 1024 * 1024;

/// The cross-dissolve between two clips (see the file header).
const Duration kSalCrossfade = Duration(milliseconds: 120);

/// Who is performing now (see the file header, "one Sal at a time"): a
/// set of holders, and a revision that changes whenever it does. A change
/// made while the tree builds (a holder mounting or going) is told after
/// that frame, so listeners may set state.
abstract final class SalSpotlight {
  static final Set<Object> _holders = <Object>{};
  static final ValueNotifier<int> _changes = ValueNotifier<int>(0);
  static bool _scheduled = false;

  /// Changes whenever a holder comes or goes.
  static ValueListenable<int> get changes => _changes;

  /// [who] is performing (a toast, a result sheet, the money journey, an
  /// idle beat); idempotent.
  static void hold(Object who) {
    if (_holders.add(who)) _notify();
  }

  /// [who] is through; idempotent.
  static void release(Object who) {
    if (_holders.remove(who)) _notify();
  }

  /// Whether any Sal is performing.
  static bool get held => _holders.isNotEmpty;

  /// Whether a Sal other than [who] is performing.
  static bool heldByOther(Object who) =>
      _holders.any((h) => !identical(h, who));

  static void _notify() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      _changes.value++;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      _changes.value++;
    });
  }

  /// Tests: nobody performing.
  @visibleForTesting
  static void debugReset() {
    _holders.clear();
    _scheduled = false;
  }
}

/// One clip's sheet, decoded, with its timing.
class SalClip {
  const SalClip({
    required this.image,
    required this.fps,
    required this.frames,
    required this.columns,
    required this.cellWidth,
    required this.cellHeight,
    required this.loop,
    required this.body,
    this.sequence,
  });

  final ui.Image image;
  final double fps;

  /// The frames played, one per tick of [fps] (the [sequence]'s length
  /// when there is one).
  final int frames;
  final int columns;
  final double cellWidth;
  final double cellHeight;

  /// The manifest's `loop` (true unless it says otherwise).
  final bool loop;

  /// Body framing (the whole dog) rather than the face.
  final bool body;

  /// The sheet's cell for each played frame, when the manifest gives one
  /// (`"sequence"`): a loop whose frames repeat (a breath, a held look)
  /// stores each distinct cell once. Null: frame i is cell i.
  final List<int>? sequence;

  /// One pass through the clip at its own fps.
  Duration get duration =>
      Duration(microseconds: math.max(1, (frames / fps * 1e6).round()));

  /// The source rectangle of [frame] in the sheet.
  Rect cell(int frame) {
    final f = frame.clamp(0, frames - 1);
    final seq = sequence;
    final c = seq == null || seq.isEmpty ? f : seq[f % seq.length];
    final col = c % columns;
    final row = c ~/ columns;
    return Rect.fromLTWH(
        col * cellWidth, row * cellHeight, cellWidth, cellHeight);
  }
}

/// Loads and caches the clips: one decode per clip and density for the
/// app's life. A clip that cannot be read resolves to null (and is asked
/// again next time, so the assets can land while the app runs).
abstract final class SalSpriteCache {
  static Future<Map<String, dynamic>?>? _manifest;
  static final Map<String, Future<SalClip?>> _clips = {};

  static Future<Map<String, dynamic>?> manifest() =>
      _manifest ??= _loadManifest();

  static Future<Map<String, dynamic>?> _loadManifest() async {
    try {
      final text = await rootBundle.loadString('$kSalSpriteDir/manifest.json');
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } catch (e) {
      // Never fatal (the rig draws him), but never silent either: a
      // device that shows the pixel Sal says why in its logs.
      if (kDebugMode) {
        debugPrint('SalSpriteCache: manifest not read ($e)');
      }
      _manifest = null;
      return null;
    }
  }

  /// Tests: a manifest of their own (null: none), the decoded clips let go.
  @visibleForTesting
  static void debugSetManifest(Map<String, dynamic>? manifest) {
    _manifest = Future<Map<String, dynamic>?>.value(manifest);
    _clips.clear();
    _ready.clear();
    _failed.clear();
    _debugStaged.clear();
    _bytes = 0;
    SalCoinAnchors.debugSet(null);
  }

  /// Tests: [clip] stands as decoded under [name] at [density] (a
  /// synthetic image; no sheet read), and as its sheet in the bundle: a
  /// read after the cache gave it up gets it back.
  @visibleForTesting
  static void debugPutClip(String name, int density, SalClip clip) {
    _debugStaged['$name@$density'] = clip;
    _clips['$name@$density'] = Future<SalClip?>.value(clip);
    _admit('$name@$density', clip);
    _failed.remove('$name@$density');
  }

  /// Tests: [name] at [density] is still decoding until [loading]
  /// completes (a slow read, stood in for); null from it is a read that
  /// came back empty ([failed]).
  @visibleForTesting
  static void debugPutLoading(
      String name, int density, Future<SalClip?> loading) {
    final key = '$name@$density';
    _clips[key] = loading.then((c) {
      if (c != null) {
        _admit(key, c);
      } else {
        _failed.add(key);
      }
      return c;
    });
  }

  /// Tests: every clip asked for through [clip] (and so [peek], [warm])
  /// is appended here while it is set, by name: whether a flow warms
  /// its clips on open.
  @visibleForTesting
  static List<String>? debugRequestLog;

  /// Tests: reads a clip in place of the bundle while it is set (a
  /// synthetic sheet, timed as the test likes); null from it is a read
  /// that came back empty. The manifest still has to name the clip.
  @visibleForTesting
  static Future<SalClip?> Function(String name, int density)? debugLoader;

  static final Map<String, SalClip> _debugStaged = {};

  /// Tests: back to the bundle's manifest, nothing decoded.
  @visibleForTesting
  static void debugReset() {
    _manifest = null;
    _clips.clear();
    _ready.clear();
    _failed.clear();
    _debugStaged.clear();
    _bytes = 0;
    maxBytes = kSalSpriteCacheMaxBytes;
    debugLoader = null;
    SalCoinAnchors.debugReset();
    SalSpotlight.debugReset();
  }

  /// The manifest's groups: group name → clip names, in manifest order.
  /// Empty when there is no manifest (or no entry names a group).
  static Future<Map<String, List<String>>> groups() async {
    final manifest = await SalSpriteCache.manifest();
    final out = <String, List<String>>{};
    if (manifest == null) return out;
    for (final e in manifest.entries) {
      final v = e.value;
      if (v is Map && v['group'] is String) {
        out.putIfAbsent(v['group'] as String, () => []).add(e.key);
      }
    }
    return out;
  }

  /// The clips of [group]; falls back to [defaults] (the names the
  /// contract promises) filtered to the clips the manifest has, so code
  /// written against the contract runs before the sheets land and after.
  static Future<List<String>> group(String name,
      {List<String> defaults = const []}) async {
    final manifest = await SalSpriteCache.manifest();
    if (manifest == null) return const [];
    final grouped = (await groups())[name];
    if (grouped != null && grouped.isNotEmpty) return grouped;
    return [for (final d in defaults) if (manifest.containsKey(d)) d];
  }

  /// Whether the manifest names [clip] (not whether its sheet reads).
  static Future<bool> exists(String clip) async =>
      (await SalSpriteCache.manifest())?.containsKey(clip) ?? false;

  /// [density] is 2 or 3: which sheet to read.
  static Future<SalClip?> clip(String name, int density) {
    debugRequestLog?.add(name);
    final key = '$name@$density';
    // A test's staged sheet is the bundle's, decoded at once when it is
    // read again after the cache gave it up.
    final staged = _debugStaged[key];
    if (staged != null && !_clips.containsKey(key)) {
      _admit(key, staged);
      return _clips[key] = Future<SalClip?>.value(staged);
    }
    return _clips[key] ??= _loadClip(name, density);
  }

  /// Decodes [names] at [density] once, ahead of their use (a director's
  /// group on mount), and keeps them for the app's life. Resolves to the
  /// names that could not be read, so the caller can drop them.
  static Future<List<String>> warm(Iterable<String> names, int density) async {
    final list = names.toList();
    final clips = await Future.wait([for (final n in list) clip(n, density)]);
    return [for (var i = 0; i < list.length; i++) if (clips[i] == null) list[i]];
  }

  /// [warm] for the manifest's [group] (see [SalSpriteCache.group]);
  /// resolves to the names that could not be read.
  static Future<List<String>> warmGroup(String group,
      {List<String> defaults = const [], required int density}) async {
    final names = await SalSpriteCache.group(group, defaults: defaults);
    return warm(names, density);
  }

  /// The decoded clips the cache holds, least recently used first.
  static final Map<String, SalClip> _ready = <String, SalClip>{};

  /// What [_ready] holds, in decoded bytes.
  static int _bytes = 0;

  /// The most decoded bytes the cache holds (see the file header).
  static int maxBytes = kSalSpriteCacheMaxBytes;

  /// What the cache holds now, in decoded bytes.
  static int get residentBytes => _bytes;

  /// The names it holds now at [density] (tests, and the journey's own
  /// bookkeeping).
  static Iterable<String> residentAt(int density) => [
        for (final k in _ready.keys)
          if (k.endsWith('@$density')) k.substring(0, k.lastIndexOf('@'))
      ];

  /// A clip's decoded size: four bytes a pixel.
  static int bytesOf(SalClip clip) => clip.image.width * clip.image.height * 4;

  /// [clip] is held under [key], the most recently used; the least
  /// recently used go until the cache is within [maxBytes] (never the
  /// one just admitted).
  static void _admit(String key, SalClip clip) {
    final old = _ready.remove(key);
    if (old != null) _bytes -= bytesOf(old);
    _ready[key] = clip;
    _bytes += bytesOf(clip);
    while (_bytes > maxBytes && _ready.length > 1) {
      final victim = _ready.keys.first;
      if (victim == key) break;
      _drop(victim);
    }
  }

  static void _drop(String key) {
    final c = _ready.remove(key);
    if (c != null) _bytes -= bytesOf(c);
    _clips.remove(key);
  }

  /// A use of [key]: the most recently used now.
  static SalClip? _touch(String key) {
    final c = _ready.remove(key);
    if (c != null) _ready[key] = c;
    return c;
  }

  /// Gives up [name] at [density] (a clip its user has passed); read
  /// again when it is next asked for.
  static void evict(String name, int density) => _drop('$name@$density');

  /// A clip already decoded, without starting a read when it is not: for
  /// a painter that asks after clips it will not draw now (what it could
  /// switch to), so asking does not decode them all at once.
  static SalClip? ready(String name, int density) =>
      _touch('$name@$density');

  /// The clips whose last read came back empty: no manifest, not in it,
  /// or a sheet that did not decode.
  static final Set<String> _failed = {};

  /// Whether the last read of [name] at [density] came back empty (see
  /// [_failed]). A painter that cannot await ([peek]) draws its last
  /// resort, the rig, only then; while a read is still out it draws
  /// nothing, or a still, and never the rig for a wait. Cleared by a read
  /// that lands.
  static bool failed(String name, int density) =>
      _failed.contains('$name@$density');

  /// The density for a device pixel ratio: @3x from 2.5 up.
  static int densityFor(double dpr) => dpr >= 2.5 ? 3 : 2;

  /// A clip already decoded, for a painter that cannot await (the money
  /// journey's Sal, a sprite switching clips): null while it is still
  /// loading (the read is started) or when it does not exist, and the
  /// painter keeps drawing what it has.
  static SalClip? peek(String name, int density) {
    final key = '$name@$density';
    final ready = _touch(key);
    if (ready != null) return ready;
    unawaited(clip(name, density));
    return _ready[key];
  }

  static Future<SalClip?> _loadClip(String name, int density) async {
    final key = '$name@$density';
    try {
      final manifest = await SalSpriteCache.manifest();
      final entry = manifest?[name];
      if (entry is! Map) {
        _failed.add(key);
        return null;
      }
      final loader = debugLoader;
      if (loader != null) {
        final c = await loader(name, density);
        if (c == null) {
          _failed.add(key);
          _clips.remove(key);
          return null;
        }
        if (_clips[key] == null) return c;
        _admit(key, c);
        _failed.remove(key);
        return c;
      }
      final files = entry['files'];
      final file = files is Map && files['${density}x'] is Map
          ? (files['${density}x'] as Map)['file'] as String?
          : null;
      final data =
          await rootBundle.load('$kSalSpriteDir/${file ?? '$name@${density}x.png'}');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frameInfo = await codec.getNextFrame();
      codec.dispose();
      final image = frameInfo.image;
      // A "sequence" names the cell each played frame shows ("cells"
      // distinct cells in the sheet); without one, frame i is cell i.
      final rawSequence = entry['sequence'];
      final cellCount = (entry['cells'] as num?)?.toInt();
      final sequence = rawSequence is List && rawSequence.isNotEmpty
          ? [
              for (final v in rawSequence)
                ((v as num).toInt()).clamp(0, (cellCount ?? 1 << 16) - 1)
            ]
          : null;
      final frames = (sequence?.length ??
              (entry['frames'] as num?)?.toInt() ??
              1)
          .clamp(1, 1 << 16);
      final cells = sequence == null ? frames : (cellCount ?? frames);
      final columns =
          ((entry['columns'] as num?)?.toInt() ?? cells).clamp(1, 1 << 16);
      final rows = (cells / columns).ceil().clamp(1, 1 << 16);
      final clip = SalClip(
        image: image,
        fps: (entry['fps'] as num?)?.toDouble() ?? 24,
        frames: frames,
        columns: columns,
        // The cells as the sheet lays them out, whatever the manifest
        // says the logical cell is: the sheet is the truth at its density.
        cellWidth: image.width / columns,
        cellHeight: image.height / rows,
        loop: entry['loop'] != false,
        body: entry['framing'] == 'body' || name.startsWith('body_'),
        sequence: sequence,
      );
      // Given up while it was read (evicted, or the cache reset): it is
      // not held; the caller still gets it.
      if (_clips[key] == null) return clip;
      _admit(key, clip);
      _failed.remove(key);
      return clip;
    } catch (e, st) {
      // Never fatal (the site's fallback draws him), but never silent: a
      // sheet that does not read on a device (missing from the bundle, a
      // codec without webp, out of memory) says so in the logs.
      if (kDebugMode) {
        debugPrint('SalSpriteCache: $name@${density}x not decoded ($e)\n$st');
      }
      _failed.add(key);
      _clips.remove(key);
      return null;
    }
  }
}

/// Where the coin a coin clip renders (body_carry, body_pickup,
/// body_drop) sits on one frame, in the cell's logical units (0..128 from
/// its top-left, as `coin_anchors.json` gives them): the centre of its
/// projected rim, its semi-major radius [r] (about 8.3 held in the mouth)
/// and its semi-minor radius [ry] (about 3.9 lying flat on the floor).
@immutable
class SalCoinAnchor {
  const SalCoinAnchor(this.centre, this.r, this.ry);
  final Offset centre;
  final double r;
  final double ry;

  /// How round the coin reads: 1 facing the camera, small lying flat.
  double get roundness => r <= 0 ? 0 : ry / r;
}

/// The coin clips' per-frame anchors (`coin_anchors.json`), read once
/// for the app's life. [peek] never awaits: null while the file is
/// still read (the read is started) or where it has no entry, and the
/// caller draws without it.
abstract final class SalCoinAnchors {
  /// The cell's logical size the anchors are in.
  static const double cell = 128;

  static Future<Map<String, List<SalCoinAnchor>>?>? _loading;
  static Map<String, List<SalCoinAnchor>>? _ready;

  /// Reads the file once; resolves to null when it cannot be read (and
  /// is asked again next time).
  static Future<Map<String, List<SalCoinAnchor>>?> load() =>
      _loading ??= _load();

  static Future<Map<String, List<SalCoinAnchor>>?> _load() async {
    try {
      final text =
          await rootBundle.loadString('$kSalSpriteDir/coin_anchors.json');
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) throw const FormatException('map');
      final minor = json['_minor'];
      final out = <String, List<SalCoinAnchor>>{};
      for (final e in json.entries) {
        if (e.key.startsWith('_') || e.value is! List) continue;
        final rows = e.value as List;
        final ry = minor is Map && minor[e.key] is List
            ? minor[e.key] as List
            : const [];
        out[e.key] = [
          for (var i = 0; i < rows.length; i++)
            () {
              final v = (rows[i] as List).cast<num>();
              final r = v[2].toDouble();
              return SalCoinAnchor(Offset(v[0].toDouble(), v[1].toDouble()),
                  r, i < ry.length ? (ry[i] as num).toDouble() : r);
            }(),
        ];
      }
      return _ready = out;
    } catch (e) {
      if (kDebugMode) debugPrint('SalCoinAnchors: not read ($e)');
      _loading = null;
      return null;
    }
  }

  /// The anchor of [clip] on [frame] (clamped to its frames), null while
  /// the file is not read or for a clip it has no entry for.
  static SalCoinAnchor? peek(String clip, int frame) {
    final ready = _ready;
    if (ready == null) {
      unawaited(load());
      return null;
    }
    final list = ready[clip];
    if (list == null || list.isEmpty) return null;
    return list[frame.clamp(0, list.length - 1)];
  }

  /// Tests: these anchors stand as read (null: none, and none read).
  @visibleForTesting
  static void debugSet(Map<String, List<SalCoinAnchor>>? anchors) {
    _ready = anchors;
    _loading = Future.value(anchors);
  }

  /// Tests: back to the bundle's file, nothing read.
  @visibleForTesting
  static void debugReset() {
    _ready = null;
    _loading = null;
  }
}

/// What [SalSprite] paints on one frame: [clip] (named [name]) at
/// [frame]; during a cross-dissolve the [outgoing] clip at
/// [outgoingFrame] under it, [fade] running 0 → 1 (1: no dissolve).
@immutable
class SalSpriteFrame {
  const SalSpriteFrame({
    required this.clip,
    required this.name,
    required this.frame,
    this.outgoing,
    this.outgoingName,
    this.outgoingFrame = 0,
    this.fade = 1.0,
  });

  final SalClip clip;
  final String name;
  final int frame;
  final SalClip? outgoing;
  final String? outgoingName;
  final int outgoingFrame;
  final double fade;

  /// Whether this frame dissolves two clips.
  bool get dissolving => outgoing != null && fade < 1.0;

  @override
  bool operator ==(Object other) =>
      other is SalSpriteFrame &&
      identical(other.clip, clip) &&
      other.name == name &&
      other.frame == frame &&
      identical(other.outgoing, outgoing) &&
      other.outgoingName == outgoingName &&
      other.outgoingFrame == outgoingFrame &&
      other.fade == fade;

  @override
  int get hashCode =>
      Object.hash(clip, name, frame, outgoing, outgoingName, outgoingFrame, fade);

  @override
  String toString() => dissolving
      ? 'SalSpriteFrame($name#$frame over $outgoingName#$outgoingFrame '
          '@${fade.toStringAsFixed(2)})'
      : 'SalSpriteFrame($name#$frame)';
}

/// Sal, one clip, at [size] (see the file header).
class SalSprite extends StatefulWidget {
  const SalSprite({
    super.key,
    required this.clip,
    required this.size,
    this.speed = 1.0,
    this.loop,
    this.cue = 0,
    this.crossfade = kSalCrossfade,
    this.switchAtBoundary = true,
    this.paused = false,
    this.onComplete,
    this.onUnavailable,
    this.onFrame,
    required this.fallback,
  });

  /// A one-shot [first] (its last frame held for one frame), then [then]
  /// looping: body_sit_down → body_sit.
  static Widget sequence({
    Key? key,
    required String first,
    required String then,
    required double size,
    double speed = 1.0,
    required Widget fallback,
  }) =>
      _SalSequence(
          key: key, first: first, then: then, size: size, speed: speed,
          fallback: fallback);

  /// Tests: every frame the painter draws goes here while it is set.
  @visibleForTesting
  static List<SalSpriteFrame>? debugPaintLog;

  /// `search`, `idle`, `happy`, `body_sit`…
  final String clip;

  /// The square's side in logical pixels.
  final double size;

  /// Multiplies the clip's fps.
  final double speed;

  /// Overrides the manifest's loop flag; null follows the manifest.
  final bool? loop;

  /// A changed cue plays [clip] from frame 0 again, even when it is the
  /// clip on screen (the same reaction twice): a switch like any other.
  final int cue;

  /// How long the outgoing and incoming cells dissolve on a clip switch
  /// (zero: a cut).
  final Duration crossfade;

  /// Whether a clip switch waits for the outgoing clip's frame boundary
  /// (a loop back at frame 0, a one-shot through); off, it lands on the
  /// next tick.
  final bool switchAtBoundary;

  /// Holds the frame on screen, the ticker stopped (frame 0 when nothing
  /// has played yet: an empty state's Sal standing still before his first
  /// beat); unpaused, the clip plays on from there. A clip asked for while
  /// paused takes the screen at once.
  final bool paused;

  /// Called once when a one-shot reaches its last frame.
  final VoidCallback? onComplete;

  /// Called once when [clip] cannot be read (not in the manifest, no
  /// sheet): the clip on screen stays (or the [fallback] when there is
  /// none), and a director can move on.
  final VoidCallback? onUnavailable;

  /// Drawn when no sheet can be read (not rendered yet, not registered):
  /// the rig drawing the site wore before.
  final Widget fallback;

  /// Called with every new frame the painter is handed (a layer timed to
  /// Sal's beats, the share badge's arrow on his blink). It can come
  /// during a build: repaint from it, never rebuild.
  final ValueChanged<SalSpriteFrame>? onFrame;

  @override
  State<SalSprite> createState() => _SalSpriteState();
}

class _SalSpriteState extends State<SalSprite>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _density = 2;
  bool _reduce = false;

  // The clip on screen: its decoded sheet, its name, the loop override
  // captured when it started, its clock (speed applied), and whether a
  // one-shot has said it is complete.
  SalClip? _clip;
  String? _name;
  bool? _loopOverride;
  Duration _elapsed = Duration.zero;
  bool _completed = false;

  /// The [SalSprite.onComplete] that came with the clip on screen: a
  /// request made while it plays (the next reaction) must not be told
  /// that THIS clip is through.
  VoidCallback? _onComplete;

  /// The last tick's time; null before the first tick after a start (a
  /// first tick at exactly zero, as in a test, is a tick like any other).
  Duration? _last;

  // The clip asked for and not yet on screen: its name, its sheet once
  // decoded, the outgoing loop's cycle when it was asked for (the switch
  // lands when a later cycle begins), and the read's generation.
  String? _pendingName;
  SalClip? _pendingClip;
  int _pendingCycle = 0;
  int _load = 0;

  // The cross-dissolve: the outgoing clip frozen at its boundary frame,
  // and how long it has run (real time).
  SalClip? _out;
  String? _outName;
  int _outFrame = 0;
  Duration _fade = Duration.zero;

  /// Nothing to draw at all: the fallback.
  bool _failed = false;

  final ValueNotifier<SalSpriteFrame?> _paint =
      ValueNotifier<SalSpriteFrame?>(null);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final density = SalSpriteCache.densityFor(dpr);
    if (density != _density) {
      _density = density;
      _request(widget.clip);
    } else if (_clip == null && _pendingName == null && !_failed) {
      _request(widget.clip);
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant SalSprite old) {
    super.didUpdateWidget(old);
    if (old.clip != widget.clip || old.cue != widget.cue) {
      _request(widget.clip);
    } else if (old.loop != widget.loop) {
      // The clip on screen asked to loop (or not) from here: a one-shot
      // that is now asked to loop plays on from where it stopped (the
      // bar's `share`: once at 1.3x, then looping); a loop asked to stop
      // plays out the pass it is in and holds its last frame (a bar Sal
      // giving the spotlight to another), never cut to it mid-cycle.
      final wasLooping = _loops;
      _loopOverride = widget.loop;
      _onComplete = widget.onComplete;
      final clip = _clip;
      if (wasLooping && !_loops && clip != null) {
        _elapsed = Duration(
            microseconds:
                _elapsed.inMicroseconds % clip.duration.inMicroseconds);
      }
      if (_completed && _loops) _completed = false;
    }
    _sync();
  }

  bool get _loops => _loopOverride ?? _clip?.loop ?? true;

  /// The outgoing clip's cycle count now (0 for a one-shot or nothing).
  int get _cycle {
    final clip = _clip;
    if (clip == null) return 0;
    return _elapsed.inMicroseconds ~/ clip.duration.inMicroseconds;
  }

  /// The frame [clip] shows at [_elapsed].
  int _frameOf(SalClip clip) {
    final raw = ((_elapsed.inMicroseconds / 1e6) * clip.fps).floor();
    return _loops ? raw % clip.frames : raw.clamp(0, clip.frames - 1);
  }

  /// Asks for [name]: at once when its sheet is decoded, else once the
  /// read lands; the clip on screen plays on meanwhile.
  void _request(String name) {
    _failed = false;
    final density = _density;
    _pendingName = name;
    _pendingClip = null;
    _pendingCycle = _cycle;
    final ready = SalSpriteCache.peek(name, density);
    if (ready != null) {
      _arrive(name, ready);
      return;
    }
    final load = ++_load;
    unawaited(SalSpriteCache.clip(name, density).then((c) {
      if (!mounted || load != _load || _pendingName != name) return;
      if (c == null) {
        _pendingName = null;
        if (_clip == null) setState(() => _failed = true);
        widget.onUnavailable?.call();
        return;
      }
      _arrive(name, c);
      // A cell where there was nothing (or a glow to add): rebuild.
      setState(() {});
    }));
  }

  /// [clip] is decoded: on screen at once when nothing plays (nothing
  /// there, Reduce Motion, a held one-shot, a still, a start not yet
  /// ticked, or no boundary asked for), else at the outgoing clip's next
  /// boundary ([_tick]).
  void _arrive(String name, SalClip clip) {
    _pendingClip = clip;
    // The boundary to wait for is the next one from here (a read that
    // landed after one passed does not cut in mid-cycle).
    _pendingCycle = _cycle;
    final current = _clip;
    final ticking = _ticker?.isActive ?? false;
    final held = current != null &&
        (current.frames <= 1 ||
            (!_loops && _elapsed >= current.duration) ||
            !ticking);
    final fresh = _last == null && _elapsed == Duration.zero;
    if (current == null ||
        _reduce ||
        !widget.switchAtBoundary ||
        held ||
        fresh) {
      _switch(carry: Duration.zero, fade: current != null && !_reduce && !fresh);
    }
    _sync();
  }

  /// The pending clip takes the screen from [carry] into its first
  /// cycle; the outgoing clip, frozen at [outFrame], dissolves away when
  /// [fade] is on.
  void _switch({
    required Duration carry,
    required bool fade,
    int? outFrame,
  }) {
    final incoming = _pendingClip;
    final name = _pendingName;
    if (incoming == null || name == null) return;
    final current = _clip;
    if (fade && current != null && widget.crossfade > Duration.zero) {
      _out = current;
      _outName = _name;
      _outFrame = outFrame ?? _frameOf(current);
      _fade = Duration.zero;
    } else {
      _out = null;
      _outName = null;
    }
    _clip = incoming;
    _name = name;
    _loopOverride = widget.loop;
    _onComplete = widget.onComplete;
    _elapsed = carry;
    _completed = false;
    _pendingName = null;
    _pendingClip = null;
    _publish();
  }

  /// Runs the ticker only when there is something to move (a loop, a
  /// one-shot still playing, a switch waiting for its boundary, a
  /// dissolve) and motion is on. A one-shot under Reduce Motion is its
  /// first frame, complete at once.
  void _sync() {
    final ticker = _ticker;
    if (ticker == null) return;
    final clip = _clip;
    if (_reduce && clip != null && !_loops && !_completed) {
      _completed = true;
      final done = _onComplete;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) done?.call();
      });
    }
    final moving = clip != null &&
        clip.frames > 1 &&
        (_loops || _elapsed < clip.duration);
    final play = !_reduce &&
        !widget.paused &&
        clip != null &&
        (moving || _pendingClip != null || _out != null);
    if (play && !ticker.isActive) {
      _last = null;
      ticker.start();
    } else if (!play && ticker.isActive) {
      ticker.stop();
      if (!_completed && !widget.paused) _elapsed = Duration.zero;
      _out = null;
      _outName = null;
      _publish();
    } else if (!play && _out != null) {
      // A switch while still (paused): no dissolve to run.
      _out = null;
      _outName = null;
      _publish();
    }
  }

  void _tick(Duration now) {
    var clip = _clip;
    if (clip == null) return;
    final last = _last;
    final dt = last == null ? Duration.zero : now - last;
    _last = now;
    // Whether the one-shot's completion was announced on an earlier tick
    // (so its parent has had a frame to ask for what comes next).
    final announced = _completed;
    _elapsed += dt * widget.speed;
    if (_out != null) {
      _fade += dt;
      if (_fade >= widget.crossfade) {
        _out = null;
        _outName = null;
      }
    }
    // A switch waiting for the boundary: a loop as a new cycle begins, a
    // one-shot once its length has run. The overshoot past the boundary
    // is the incoming clip's first moments.
    final pending = _pendingClip;
    if (pending != null) {
      final period = clip.duration;
      final loops = _loops;
      final cycle = _elapsed.inMicroseconds ~/ period.inMicroseconds;
      final boundary = loops ? cycle > _pendingCycle : _elapsed >= period;
      if (boundary) {
        final end = loops ? period * cycle : period;
        _switch(
            carry: _elapsed - end,
            fade: true,
            outFrame: loops ? 0 : clip.frames - 1);
        clip = _clip!;
      }
    }
    final raw = ((_elapsed.inMicroseconds / 1e6) * clip.fps).floor();
    final int frame;
    if (_loops) {
      frame = raw % clip.frames;
    } else {
      // A one-shot: hold the last frame and say so once.
      frame = raw.clamp(0, clip.frames - 1);
      if (raw >= clip.frames - 1 && !_completed) {
        _completed = true;
        _onComplete?.call();
      }
    }
    _publish(frame);
    // Nothing left to move: a one-shot through and announced a frame
    // ago (a parent asking for the next clip in this frame's build keeps
    // the ticker, and its clock, running), no switch waiting, no
    // dissolve running.
    if (!_loops &&
        announced &&
        _elapsed >= clip.duration &&
        _pendingClip == null &&
        _out == null) {
      _ticker?.stop();
    }
  }

  /// Hands the painter what to draw now.
  void _publish([int? frame]) {
    final clip = _clip;
    final name = _name;
    if (clip == null || name == null) {
      if (_paint.value != null) _paint.value = null;
      return;
    }
    final out = _out;
    final crossfade = widget.crossfade.inMicroseconds;
    final fade = out == null || crossfade <= 0
        ? 1.0
        : (_fade.inMicroseconds / crossfade).clamp(0.0, 1.0);
    final next = SalSpriteFrame(
      clip: clip,
      name: name,
      frame: frame ?? _frameOf(clip),
      outgoing: out,
      outgoingName: _outName,
      outgoingFrame: _outFrame,
      fade: fade,
    );
    if (next != _paint.value) {
      _paint.value = next;
      widget.onFrame?.call(next);
    }
  }

  /// Tests: what the painter draws now (null: nothing decoded yet).
  SalSpriteFrame? get debugFrame => _paint.value;

  /// Tests: the clip asked for and not yet on screen.
  String? get debugPending => _pendingName;

  @override
  void dispose() {
    _ticker?.dispose();
    _paint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    if (clip == null) {
      return _failed
          ? widget.fallback
          : SizedBox(width: widget.size, height: widget.size);
    }
    final dark = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark ||
        _isDarkTheme(context);
    final paint = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _SalSpritePainter(_paint),
      ),
    );
    if (!clip.body || !dark) return paint;
    // The glow under a body on a dark ground.
    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x0FFFFFFF), Color(0x00FFFFFF)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        paint,
      ],
    );
  }

  /// The theme's darkness, read without a dependency on the app theme
  /// package (this file is a widget leaf).
  static bool _isDarkTheme(BuildContext context) {
    final ink = DefaultTextStyle.of(context).style.color;
    if (ink == null) return false;
    return ink.computeLuminance() > 0.5;
  }
}


/// The hero clips the contract promises (the manifest's `hero` group).
const List<String> kSalHeroOneShots = [
  'hero_stretch',
  'hero_look_around',
  'hero_scratch',
  'hero_tail_chase',
];
const String kSalHeroLoop = 'body_hero';
const String kSalHeroSleep = 'hero_sleep';
const String kSalHeroWake = 'hero_wake';

/// An empty state's beats (founder, 12 November 2026: "an occasional
/// blink/stretch"), each played once and held: one pass of the hero
/// loop (his blink), a look around, a stretch. The scratch and the tail
/// chase stay out: calm, not busy.
const List<String> kSalIdleBeats = [
  kSalHeroLoop,
  'hero_look_around',
  'hero_stretch',
];

/// The empty states' Sal (see the file header): still in the hero pose, a
/// beat every [minGap]–[maxGap], sleep after [sleepAfter] without a
/// pointer anywhere, wake on the next one. One [SalSprite] for all of it:
/// a beat takes the screen from the held pose with the 120 ms dissolve and
/// holds its own last frame (the hero pose again), and the beats are
/// decoded once on mount.
class SalIdleDirector extends StatefulWidget {
  const SalIdleDirector({
    super.key,
    required this.size,
    required this.fallback,
    this.minGap = const Duration(seconds: 8),
    this.maxGap = const Duration(seconds: 15),
    this.sleepAfter = const Duration(seconds: 60),
    this.random,
  });

  final double size;

  /// What [SalSprite] draws when the hero sheet itself is missing.
  final Widget fallback;
  final Duration minGap;
  final Duration maxGap;
  final Duration sleepAfter;

  /// The picks' source; tests pass a seeded one.
  final math.Random? random;

  /// The last pointer anywhere in the app, for the sleep timer: a global
  /// pointer route, so a scroll or a tap on the page above wakes him.
  static DateTime lastInput = DateTime.now();

  @override
  State<SalIdleDirector> createState() => _SalIdleDirectorState();
}

enum _DirectorPhase { rest, beat, sleeping, waking }

class _SalIdleDirectorState extends State<SalIdleDirector>
    with WidgetsBindingObserver {
  late final math.Random _random = widget.random ?? math.Random();
  List<String> _pool = const [];
  bool _hasSleep = false;
  bool _hasWake = false;
  _DirectorPhase _phase = _DirectorPhase.rest;
  String _clip = kSalHeroLoop;
  String? _last;
  Timer? _timer;
  Timer? _sleepTimer;
  bool _reduce = false;
  bool _started = false;
  bool _onScreen = true;
  bool _foreground = true;
  int _density = 2;
  int _cue = 0;

  /// Whether the beats run: on screen, the app in front, motion on.
  bool get _live => _onScreen && _foreground && !_reduce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    _density = SalSpriteCache.densityFor(dpr);
    if (!_started) {
      _started = true;
      unawaited(_loadPool());
    }
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (reduce != _reduce || onScreen != _onScreen) {
      final wasLive = _live;
      _reduce = reduce;
      _onScreen = onScreen;
      if (reduce) {
        _phase = _DirectorPhase.rest;
        _clip = kSalHeroLoop;
        SalSpotlight.release(this);
      }
      _liveChanged(wasLive);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasLive = _live;
    _foreground = state == AppLifecycleState.resumed;
    _liveChanged(wasLive);
  }

  /// Off screen, in the background or under Reduce Motion nothing is
  /// armed; back, the next beat and the sleep are timed from now.
  void _liveChanged(bool wasLive) {
    if (_live == wasLive) return;
    if (_live) {
      // A beat cut short by going away plays on from where it froze.
      if (_phase == _DirectorPhase.beat) SalSpotlight.hold(this);
      _armNext();
      _armSleep();
    } else {
      _timer?.cancel();
      _sleepTimer?.cancel();
      // Nothing of his moves now: the spotlight is free for the others.
      SalSpotlight.release(this);
    }
  }

  Future<void> _loadPool() async {
    final names = <String>[];
    for (final c in kSalIdleBeats) {
      if (await SalSpriteCache.exists(c)) names.add(c);
    }
    final sleep = await SalSpriteCache.exists(kSalHeroSleep);
    final wake = await SalSpriteCache.exists(kSalHeroWake);
    if (!mounted) return;
    setState(() {
      _pool = names;
      _hasSleep = sleep;
      _hasWake = wake;
    });
    _armNext();
    _armSleep();
    // The beats decoded once, now, so no beat ever waits on a read; a
    // clip that cannot be read leaves the pool here and now.
    unawaited(SalSpriteCache.warm([
      kSalHeroLoop,
      ...names,
      if (sleep) kSalHeroSleep,
      if (wake) kSalHeroWake,
    ], _density).then((missing) {
      if (!mounted) return;
      for (final m in missing) {
        if (m != kSalHeroLoop) _unavailable(m);
      }
    }));
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent &&
        event is! PointerMoveEvent &&
        event is! PointerSignalEvent) {
      return;
    }
    SalIdleDirector.lastInput = DateTime.now();
    if (!mounted || !_live) return;
    if (_phase == _DirectorPhase.sleeping) {
      _wake();
    } else {
      _armSleep();
    }
  }

  /// The next beat, [minGap]–[maxGap] from now.
  void _armNext() {
    _timer?.cancel();
    if (!_live || _pool.isEmpty || _phase != _DirectorPhase.rest) return;
    final span = widget.maxGap.inMilliseconds - widget.minGap.inMilliseconds;
    final wait = widget.minGap.inMilliseconds +
        (span > 0 ? _random.nextInt(span + 1) : 0);
    _timer = Timer(Duration(milliseconds: wait), _playBeat);
  }

  void _armSleep() {
    _sleepTimer?.cancel();
    if (!_live || !_hasSleep) return;
    _sleepTimer = Timer(widget.sleepAfter, _sleep);
  }

  void _playBeat() {
    if (!mounted || !_live || _phase != _DirectorPhase.rest || _pool.isEmpty) {
      return;
    }
    // Another Sal is performing (a toast, a sheet, another empty state's
    // beat): this one waits for its next turn.
    if (SalSpotlight.heldByOther(this)) {
      _armNext();
      return;
    }
    // Never the same twice in a row (one clip alone repeats, there is
    // nothing else); a clip already decoded over one still reading.
    final choices = _pool.length > 1
        ? [for (final c in _pool) if (c != _last) c]
        : _pool;
    final decoded = [
      for (final c in choices)
        if (SalSpriteCache.ready(c, _density) != null) c
    ];
    final from = decoded.isNotEmpty ? decoded : choices;
    final pick = from[_random.nextInt(from.length)];
    SalSpotlight.hold(this);
    setState(() {
      _phase = _DirectorPhase.beat;
      _clip = pick;
      _last = pick;
      _cue++;
    });
  }

  void _sleep() {
    if (!mounted || !_hasSleep || _phase == _DirectorPhase.sleeping) return;
    _timer?.cancel();
    SalSpotlight.release(this);
    setState(() {
      _phase = _DirectorPhase.sleeping;
      _clip = kSalHeroSleep;
      _cue++;
    });
  }

  void _wake() {
    if (!mounted) return;
    if (_hasWake) {
      setState(() {
        _phase = _DirectorPhase.waking;
        _clip = kSalHeroWake;
        _cue++;
      });
    } else {
      _rest(back: true);
    }
    _armSleep();
  }

  /// The beat played through: he holds its last frame (the hero pose)
  /// and the next one is timed from here. [back]: from a clip he cannot
  /// hold (asleep without a wake, a beat that cannot be read), the hero
  /// pose itself.
  void _rest({bool back = false}) {
    if (!mounted) return;
    SalSpotlight.release(this);
    setState(() {
      _phase = _DirectorPhase.rest;
      if (back) {
        _clip = kSalHeroLoop;
        _cue++;
      }
    });
    _armNext();
  }

  /// A clip that cannot be read leaves the pool, and he rests.
  void _unavailable(String clip) {
    if (!mounted) return;
    if (clip == kSalHeroSleep) _hasSleep = false;
    if (clip == kSalHeroWake) _hasWake = false;
    _pool = [for (final c in _pool) if (c != clip) c];
    if (_clip == clip) _rest(back: true);
  }

  /// The clip on screen now (tests).
  String get clip => _clip;

  @override
  void dispose() {
    _timer?.cancel();
    _sleepTimer?.cancel();
    SalSpotlight.release(this);
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final playing =
        _phase == _DirectorPhase.beat || _phase == _DirectorPhase.waking;
    // One sprite for the whole performance: a beat asks it to switch in
    // place (a new cue), it plays once and holds its last frame; at rest
    // the frame on screen is held (the hero pose, frame 0 before any
    // beat); asleep, the sleep loop.
    return SalSprite(
      clip: clip,
      cue: _cue,
      size: widget.size,
      loop: _phase == _DirectorPhase.sleeping ? null : false,
      paused: _phase == _DirectorPhase.rest,
      onComplete: playing ? _rest : null,
      onUnavailable: () => _unavailable(clip),
      fallback: widget.fallback,
    );
  }
}

class _SalSequence extends StatefulWidget {
  const _SalSequence({
    super.key,
    required this.first,
    required this.then,
    required this.size,
    required this.speed,
    required this.fallback,
  });

  final String first;
  final String then;
  final double size;
  final double speed;
  final Widget fallback;

  @override
  State<_SalSequence> createState() => _SalSequenceState();
}

class _SalSequenceState extends State<_SalSequence> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => SalSprite(
        clip: _done ? widget.then : widget.first,
        size: widget.size,
        speed: widget.speed,
        loop: _done ? null : false,
        onComplete: _done ? null : () => setState(() => _done = true),
        fallback: widget.fallback,
      );
}

/// Draws a [SalSpriteFrame]: one cell, or during a dissolve the exact
/// lerp of two (in a layer: outgoing at 1−t, incoming added at t), so
/// identical poses pass unchanged and different ones blend.
class _SalSpritePainter extends CustomPainter {
  _SalSpritePainter(this.frame) : super(repaint: frame);

  final ValueListenable<SalSpriteFrame?> frame;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    if (f == null) return;
    SalSprite.debugPaintLog?.add(f);
    final dst = Offset.zero & size;
    final out = f.outgoing;
    if (out == null || f.fade >= 1.0) {
      canvas.drawImageRect(
        f.clip.image,
        f.clip.cell(f.frame),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(
      out.image,
      out.cell(f.outgoingFrame),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, 1.0 - f.fade),
    );
    canvas.drawImageRect(
      f.clip.image,
      f.clip.cell(f.frame),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, f.fade)
        ..blendMode = BlendMode.plus,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SalSpritePainter old) => old.frame != frame;
}
