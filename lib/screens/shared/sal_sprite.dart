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
// a one-shot and then a loop (body_sit_down → body_sit): the renders share
// framing, so the cut needs no crossfade. Under Reduce Motion frame 0 is
// all there is; while an ancestor TickerMode is off the ticker is muted;
// unmounted, it stops. On a dark background a body clip gets a 6% white
// radial glow behind it, so the render's contact shadow does not float
// (the renders are lit for light).
//
// UNTIL A SHEET EXISTS the widget must not break the screen: a missing
// manifest or sheet falls back to [fallback], the rig drawing that site
// wore before (kute_dog_rig.dart / kute_dog_scenes.dart stay in place for
// that), so the app runs either way. A clip that is in the manifest but
// cannot be read says so once through [onUnavailable], so a director can
// drop it from its pool and move on.
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
// [SalIdleDirector] is the hero loop with a life: `body_hero`, and every
// 6–12 s one `hero` one-shot (never the same twice in a row), then the
// loop again; after 60 s without a touch anywhere in the app he sleeps
// (`hero_sleep`), and the next pointer wakes him (`hero_wake`, then
// hero). A clip the manifest lacks, or that fails to read, is skipped;
// nothing ever crashes for a missing clip. Reduce Motion: `body_hero`'s
// first frame, nothing else.

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
  });

  final ui.Image image;
  final double fps;
  final int frames;
  final int columns;
  final double cellWidth;
  final double cellHeight;

  /// The manifest's `loop` (true unless it says otherwise).
  final bool loop;

  /// Body framing (the whole dog) rather than the face.
  final bool body;

  /// The source rectangle of [frame] in the sheet.
  Rect cell(int frame) {
    final f = frame.clamp(0, frames - 1);
    final col = f % columns;
    final row = f ~/ columns;
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
    } catch (_) {
      _manifest = null;
      return null;
    }
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
  static Future<SalClip?> clip(String name, int density) =>
      _clips['$name@$density'] ??= _loadClip(name, density);

  static final Map<String, SalClip> _ready = {};

  /// The density for a device pixel ratio: @3x from 2.5 up.
  static int densityFor(double dpr) => dpr >= 2.5 ? 3 : 2;

  /// A clip already decoded, for a painter that cannot await (the money
  /// journey's Sal): null while it is still loading (the read is started)
  /// or when it does not exist, and the painter keeps drawing the rig.
  static SalClip? peek(String name, int density) {
    final key = '$name@$density';
    final ready = _ready[key];
    if (ready != null) return ready;
    unawaited(clip(name, density));
    return null;
  }

  static Future<SalClip?> _loadClip(String name, int density) async {
    try {
      final manifest = await SalSpriteCache.manifest();
      final entry = manifest?[name];
      if (entry is! Map) return null;
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
      final frames = ((entry['frames'] as num?)?.toInt() ?? 1).clamp(1, 1 << 16);
      final columns =
          ((entry['columns'] as num?)?.toInt() ?? frames).clamp(1, 1 << 16);
      final rows = (frames / columns).ceil().clamp(1, 1 << 16);
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
      );
      _ready['$name@$density'] = clip;
      return clip;
    } catch (_) {
      _clips.remove('$name@$density');
      return null;
    }
  }
}

/// Sal, one clip, at [size] (see the file header).
class SalSprite extends StatefulWidget {
  const SalSprite({
    super.key,
    required this.clip,
    required this.size,
    this.speed = 1.0,
    this.loop,
    this.onComplete,
    this.onUnavailable,
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

  /// `search`, `idle`, `happy`, `body_sit`…
  final String clip;

  /// The square's side in logical pixels.
  final double size;

  /// Multiplies the clip's fps.
  final double speed;

  /// Overrides the manifest's loop flag; null follows the manifest.
  final bool? loop;

  /// Called once when a one-shot reaches its last frame.
  final VoidCallback? onComplete;

  /// Called once when [clip] cannot be read (not in the manifest, no
  /// sheet): the [fallback] is on screen, and a director can move on.
  final VoidCallback? onUnavailable;

  /// Drawn when the sheet cannot be read (not rendered yet, not
  /// registered): the rig drawing the site wore before.
  final Widget fallback;

  @override
  State<SalSprite> createState() => _SalSpriteState();
}

class _SalSpriteState extends State<SalSprite>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  SalClip? _clip;
  bool _failed = false;
  bool _completed = false;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _elapsed = Duration.zero;
  Duration _last = Duration.zero;
  int _density = 2;
  bool _reduce = false;

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
    final density = dpr >= 2.5 ? 3 : 2;
    if (density != _density || _clip == null && !_failed) {
      _density = density;
      _load();
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant SalSprite old) {
    super.didUpdateWidget(old);
    if (old.clip != widget.clip) {
      _elapsed = Duration.zero;
      _frame.value = 0;
      _completed = false;
      _clip = null;
      _load();
    } else if (old.loop != widget.loop && _completed && _loops) {
      // A one-shot that is now asked to loop plays on from where it
      // stopped (the bar's `share`: once at 1.3x, then looping).
      _completed = false;
    }
    _sync();
  }

  void _load() {
    final clip = widget.clip;
    final density = _density;
    _failed = false;
    unawaited(SalSpriteCache.clip(clip, density).then((c) {
      if (!mounted || clip != widget.clip || density != _density) return;
      setState(() {
        _clip = c;
        _failed = c == null;
      });
      _sync();
      if (c == null) widget.onUnavailable?.call();
    }));
  }

  bool get _loops => widget.loop ?? _clip?.loop ?? true;

  /// Runs the ticker only when there is something to play and motion is
  /// on. A one-shot under Reduce Motion is its first frame, complete at
  /// once.
  void _sync() {
    final ticker = _ticker;
    if (ticker == null) return;
    final clip = _clip;
    final frames = clip?.frames ?? 1;
    if (_reduce && clip != null && !_loops && !_completed) {
      _completed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete?.call();
      });
    }
    final play = !_reduce && frames > 1 && !_completed;
    if (play && !ticker.isActive) {
      _last = Duration.zero;
      ticker.start();
    } else if (!play && ticker.isActive) {
      ticker.stop();
      if (!_completed) _frame.value = 0;
    }
  }

  void _tick(Duration now) {
    final clip = _clip;
    if (clip == null) return;
    if (_last != Duration.zero) _elapsed += (now - _last) * widget.speed;
    _last = now;
    final raw = ((_elapsed.inMicroseconds / 1e6) * clip.fps).floor();
    if (_loops) {
      final frame = raw % clip.frames;
      if (frame != _frame.value) _frame.value = frame;
      return;
    }
    // A one-shot: hold the last frame and say so once.
    final frame = raw.clamp(0, clip.frames - 1);
    if (frame != _frame.value) _frame.value = frame;
    if (raw >= clip.frames - 1 && !_completed) {
      _completed = true;
      _ticker?.stop();
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frame.dispose();
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
        painter: _SalSpritePainter(clip: clip, frame: _frame),
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


/// The hero clips the contract promises (see the file header); the
/// manifest's `hero` group wins when it names any.
const List<String> kSalHeroOneShots = [
  'hero_stretch',
  'hero_look_around',
  'hero_scratch',
  'hero_tail_chase',
];
const String kSalHeroLoop = 'body_hero';
const String kSalHeroSleep = 'hero_sleep';
const String kSalHeroWake = 'hero_wake';

/// The hero loop with a life (see the file header): `body_hero`, a `hero`
/// one-shot every [minGap]–[maxGap], sleep after [sleepAfter] without a
/// pointer anywhere, wake on the next one. Every empty state that shows
/// `body_hero` uses this.
class SalIdleDirector extends StatefulWidget {
  const SalIdleDirector({
    super.key,
    required this.size,
    required this.fallback,
    this.minGap = const Duration(seconds: 6),
    this.maxGap = const Duration(seconds: 12),
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

enum _DirectorPhase { hero, oneShot, sleeping, waking }

class _SalIdleDirectorState extends State<SalIdleDirector> {
  late final math.Random _random = widget.random ?? math.Random();
  List<String> _pool = const [];
  bool _hasSleep = false;
  bool _hasWake = false;
  _DirectorPhase _phase = _DirectorPhase.hero;
  String _clip = kSalHeroLoop;
  String? _last;
  Timer? _timer;
  Timer? _sleepTimer;
  bool _reduce = false;
  int _cue = 0;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    unawaited(_loadPool());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reduce) {
      _reduce = reduce;
      if (reduce) {
        _timer?.cancel();
        _sleepTimer?.cancel();
        _phase = _DirectorPhase.hero;
        _clip = kSalHeroLoop;
      } else {
        _armNext();
        _armSleep();
      }
    }
  }

  Future<void> _loadPool() async {
    final pool = await SalSpriteCache.group('hero', defaults: kSalHeroOneShots);
    final sleep = await SalSpriteCache.exists(kSalHeroSleep);
    final wake = await SalSpriteCache.exists(kSalHeroWake);
    if (!mounted) return;
    setState(() {
      // The loop clips are not one-shots to cut in.
      _pool = [
        for (final c in pool)
          if (c != kSalHeroLoop && c != kSalHeroSleep && c != kSalHeroWake) c
      ];
      _hasSleep = sleep;
      _hasWake = wake;
    });
    _armNext();
    _armSleep();
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent &&
        event is! PointerMoveEvent &&
        event is! PointerSignalEvent) {
      return;
    }
    SalIdleDirector.lastInput = DateTime.now();
    if (!mounted || _reduce) return;
    if (_phase == _DirectorPhase.sleeping) {
      _wake();
    } else {
      _armSleep();
    }
  }

  /// The next one-shot, [minGap]–[maxGap] from now.
  void _armNext() {
    _timer?.cancel();
    if (_reduce || _pool.isEmpty || _phase != _DirectorPhase.hero) return;
    final span = widget.maxGap.inMilliseconds - widget.minGap.inMilliseconds;
    final wait = widget.minGap.inMilliseconds +
        (span > 0 ? _random.nextInt(span + 1) : 0);
    _timer = Timer(Duration(milliseconds: wait), _playOneShot);
  }

  void _armSleep() {
    _sleepTimer?.cancel();
    if (_reduce || !_hasSleep) return;
    _sleepTimer = Timer(widget.sleepAfter, _sleep);
  }

  void _playOneShot() {
    if (!mounted || _phase != _DirectorPhase.hero || _pool.isEmpty) return;
    // Never the same twice in a row (one clip alone repeats, there is
    // nothing else).
    final choices = _pool.length > 1
        ? [for (final c in _pool) if (c != _last) c]
        : _pool;
    final pick = choices[_random.nextInt(choices.length)];
    setState(() {
      _phase = _DirectorPhase.oneShot;
      _clip = pick;
      _last = pick;
      _cue++;
    });
  }

  void _sleep() {
    if (!mounted || !_hasSleep || _phase == _DirectorPhase.sleeping) return;
    _timer?.cancel();
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
      _backToHero();
    }
    _armSleep();
  }

  void _backToHero() {
    if (!mounted) return;
    setState(() {
      _phase = _DirectorPhase.hero;
      _clip = kSalHeroLoop;
      _cue++;
    });
    _armNext();
  }

  /// A clip that cannot be read leaves the pool, and the loop goes on.
  void _unavailable(String clip) {
    if (!mounted) return;
    if (clip == kSalHeroSleep) _hasSleep = false;
    if (clip == kSalHeroWake) _hasWake = false;
    _pool = [for (final c in _pool) if (c != clip) c];
    if (_clip == clip) _backToHero();
  }

  /// The clip on screen now (tests).
  String get clip => _clip;

  @override
  void dispose() {
    _timer?.cancel();
    _sleepTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final oneShot =
        _phase == _DirectorPhase.oneShot || _phase == _DirectorPhase.waking;
    return SalSprite(
      // A new cue starts the clip at its first frame.
      key: ValueKey('sal-director-$clip#$_cue'),
      clip: clip,
      size: widget.size,
      loop: oneShot ? false : null,
      onComplete: oneShot ? _backToHero : null,
      onUnavailable: () => _unavailable(clip),
      fallback: clip == kSalHeroLoop
          ? widget.fallback
          // A missing one-shot: the loop stands in while [_unavailable]
          // puts it back for good.
          : SalSprite(
              clip: kSalHeroLoop, size: widget.size, fallback: widget.fallback),
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

class _SalSpritePainter extends CustomPainter {
  _SalSpritePainter({required this.clip, required this.frame})
      : super(repaint: frame);

  final SalClip clip;
  final ValueListenable<int> frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      clip.image,
      clip.cell(frame.value),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _SalSpritePainter old) =>
      old.clip != clip || old.frame != frame;
}
