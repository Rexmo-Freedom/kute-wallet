// Momentum and the pressure signal of one game, computed here (never in a
// build) from the moneyline's price history at one-minute grain over the
// game window, extended by the live price feed while the game is open.
//
// Inputs are Polymarket data only: the two sides' win-chance tokens, the
// main total's Over token when the event (or its "more markets" sibling)
// has one, and the game's timeline for where the score changed. A missing
// input narrows what is shown; it never fails the rest.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_pressure.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';

// Moved beside the lines read, which picks the Over token too.
export 'package:kute/providers/polymarket_game_lines_provider.dart'
    show pickOverToken, kOverMaxSpread;

/// Reads the raw Gamma event with slug [slug]; null when there is none.
/// Replaceable in tests.
typedef GameEventRead = Future<Map<String, dynamic>?> Function(String slug);

GameEventRead gameOverEventRead = _readEvent;

Future<Map<String, dynamic>?> _readEvent(String slug) async {
  final page = await PolymarketModel.readGammaKeysetPage(
    'events',
    {'slug': slug},
    limit: 1,
    direct: true,
  );
  return page.rows.isEmpty ? null : page.rows.first;
}

/// The Over token to read beside the match with event slug [slug]: from
/// the event's own totals, else from its "more markets" sibling event
/// (where Polymarket keeps a soccer match's totals). Null when neither has
/// a traded line or the read fails. Re-read every two minutes, since the
/// most even line moves on after a goal.
///
/// Nothing waits on this: the momentum strip is drawn from the sides'
/// history and takes the token when it lands.
final polyGameOverTokenProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, slug) async {
  if (slug.isEmpty) return null;
  final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  // The game's lines read is the same event (the board reads it anyway):
  // while it is a minute old or less it stands for the event, which is
  // not read a second time.
  var fresh = false;
  try {
    final lines = await ref.watch(polyGameLinesProvider(slug).future);
    final at = lines.readAtMs;
    fresh = at != null &&
        DateTime.now().millisecondsSinceEpoch - at <= 60 * 1000;
    if (fresh && lines.overToken != null) return lines.overToken;
  } catch (_) {}
  Future<String?> overOf(String s) async {
    try {
      final row = await gameOverEventRead(s);
      return row == null ? null : pickOverToken(row);
    } catch (_) {
      // Fail soft: no totals input.
      return null;
    }
  }

  // The event and its sibling at once; the event's own line comes first.
  final tokens = await Future.wait([
    fresh ? Future<String?>.value(null) : overOf(slug),
    overOf('$slug-more-markets'),
  ]);
  return tokens[0] ?? tokens[1];
});

/// One game's momentum, keyed by what fixes the price history it reads:
/// the game, the two sides' win-chance tokens and the window. [startMs] is
/// the kickoff; [endMs] is null while the game is in play. [axisMs] is the
/// usual length of a game of this sport while it is in play (null: the
/// time played). What may change while the strip is up (which side is
/// home, the totals line) is not part of the key: it is passed in through
/// [PolyGameMomentumNotifier.updateInputs], so a change never starts a new
/// read of the sides' history.
typedef PolyMomentumKey = ({
  String gameId,
  String tokenA,
  String? tokenB,
  int startMs,
  int? endMs,
  int? axisMs,
});

class PolyGameMomentum {
  final MomentumStrip strip;
  final PressureSignal? pressure;

  /// The price history has been read (the strip may still be empty).
  final bool loaded;

  const PolyGameMomentum({
    this.strip = MomentumStrip.empty,
    this.pressure,
    this.loaded = false,
  });
}

/// The game window never reaches further back than this.
const Duration kMomentumMaxWindow = Duration(hours: 8);

const _kTick = Duration(seconds: 15);
const _kPressureLookbackMinutes = kPressureMaxMinutes + 2;

/// Reads [token]'s price history at one-minute grain between [startSec]
/// and [endSec], oldest first. Null when the read fails. Replaceable in
/// tests.
typedef MomentumHistoryRead = Future<List<OddsPoint>?> Function(
  String token, {
  required int startSec,
  required int endSec,
});

MomentumHistoryRead momentumHistoryRead = _readHistory;

Future<List<OddsPoint>?> _readHistory(
  String token, {
  required int startSec,
  required int endSec,
}) async {
  final model = PolymarketModel();
  try {
    final points = await model.getPriceHistoryWindow(
      token,
      startSec: startSec,
      endSec: endSec,
      bucketSeconds: 60,
    );
    if (points == null) return null;
    return [
      for (final p in points)
        (tMs: p.timestamp.millisecondsSinceEpoch, p: p.price)
    ]..sort((x, y) => x.tMs.compareTo(y.tMs));
  } finally {
    model.dispose();
  }
}

class PolyGameMomentumNotifier
    extends AutoDisposeFamilyNotifier<PolyGameMomentum, PolyMomentumKey> {
  List<OddsPoint> _a = const [];
  List<OddsPoint>? _b;
  List<OddsPoint>? _over;
  bool _loaded = false;
  bool _disposed = false;
  Timer? _debounce;
  PressureSignal? _pressure;

  /// The game is in play and this notifier follows it (its [build] ran).
  bool _following = false;

  /// Which side of the feed's score token A is (null: unknown).
  bool? _aIsHome;

  /// The main total's Over token, and a count of its changes (a read for
  /// a line that has since moved on is dropped).
  String? _overToken;
  int _overReads = 0;

  @override
  PolyGameMomentum build(PolyMomentumKey arg) {
    _disposed = false;
    _following = arg.endMs == null;
    Timer? ticker;
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      ticker?.cancel();
    });
    unawaited(_load());
    if (arg.endMs == null) {
      // In play: the feed's prices extend the series, and the clock moving
      // on is itself a reason to look again.
      ticker = Timer.periodic(_kTick, (_) => _recompute());
      ref.listen(
        livePriceProvider.select((s) {
          final over = _overToken;
          return (
            s.prices[arg.tokenA],
            arg.tokenB == null ? null : s.prices[arg.tokenB],
            over == null ? null : s.prices[over],
          );
        }),
        (previous, next) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (next.$1 != null && next.$1 != previous?.$1) {
            _a = _appended(_a, now, next.$1!);
          }
          if (next.$2 != null && next.$2 != previous?.$2) {
            _b = _appended(_b ?? const [], now, next.$2!);
          }
          if (next.$3 != null && next.$3 != previous?.$3) {
            _over = _appended(_over ?? const [], now, next.$3!);
          }
          _schedule();
        },
      );
      ref.listen(polyGameTimelineProvider(arg.gameId), (_, __) => _schedule());
      // Join the sides to the live feed (after this build; a provider may
      // not change another while it initializes).
      Future.microtask(() {
        if (_disposed) return;
        ref.read(livePriceProvider.notifier).addTokens([
          arg.tokenA,
          if (arg.tokenB != null) arg.tokenB!,
        ]);
      });
    }
    return const PolyGameMomentum();
  }

  /// Takes the inputs that may change while the strip is up: [aIsHome],
  /// which side of the feed's score token A is (null: unknown), and
  /// [overToken], the main total's Over token (null: none known yet).
  /// Safe to call from a widget's build: nothing changes at once. A new
  /// [aIsHome] only re-reads the signal; a new Over token reads that
  /// line's recent history and merges it in when it lands. The sides'
  /// history is never read again.
  void updateInputs({required bool? aIsHome, required String? overToken}) {
    var changed = false;
    if (aIsHome != _aIsHome) {
      _aIsHome = aIsHome;
      changed = true;
    }
    final over = overToken == null || overToken.isEmpty ? null : overToken;
    // The totals line only feeds the pressure signal of a game in play.
    if (_following && over != _overToken) {
      _overToken = over;
      _over = null;
      final read = ++_overReads;
      if (over != null) {
        // The Over token is not one of the sheet's own outcomes: join it
        // to the live feed.
        Future.microtask(() {
          if (_disposed || read != _overReads) return;
          ref.read(livePriceProvider.notifier).addTokens([over]);
        });
        unawaited(_loadOver(over, read));
      }
      changed = true;
    }
    if (changed && _loaded) {
      Future.microtask(_recompute);
    }
  }

  static List<OddsPoint> _appended(List<OddsPoint> list, int tMs, double p) {
    if (!p.isFinite || p < 0 || p > 1) return list;
    // One point per five seconds is plenty for one-minute buckets.
    if (list.isNotEmpty && tMs - list.last.tMs < 5000) {
      return [...list.take(list.length - 1), (tMs: list.last.tMs, p: p)];
    }
    return [...list, (tMs: tMs, p: p)];
  }

  /// History first, then whatever the live feed added while it loaded.
  static List<OddsPoint> _joined(
      List<OddsPoint>? history, List<OddsPoint> live) {
    if (history == null || history.isEmpty) return live;
    final cut = history.last.tMs;
    return [...history, for (final p in live) if (p.tMs > cut) p];
  }

  Future<List<OddsPoint>?> _read(String? token, int fromMs, int endMs) async {
    if (token == null || token.isEmpty) return null;
    try {
      return await momentumHistoryRead(
        token,
        // A few minutes before the window, so the first bucket has a price
        // to start from.
        startSec: (fromMs - 5 * 60000) ~/ 1000,
        endSec: endMs ~/ 1000 + 60,
      );
    } catch (_) {
      // Fail soft: the live feed alone still builds the series from now on.
      return null;
    }
  }

  /// The two sides' history over the game window. The totals line is not
  /// waited for: it is merged in when its token lands ([_loadOver]).
  Future<void> _load() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = arg.endMs ?? now;
    final floor = end - kMomentumMaxWindow.inMilliseconds;
    final start = arg.startMs < floor ? floor : arg.startMs;
    if (end <= start) {
      _loaded = true;
      _recompute();
      return;
    }
    final results = await Future.wait([
      _read(arg.tokenA, start, end),
      _read(arg.tokenB, start, end),
    ]);
    if (_disposed) return;
    _a = _joined(results[0], _a);
    if (arg.tokenB != null) _b = _joined(results[1], _b ?? const []);
    _loaded = true;
    _recompute();
  }

  /// The Over line's last few minutes (the pressure signal looks no
  /// further back), merged in when they land.
  Future<void> _loadOver(String token, int read) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final history = await _read(
        token, now - (_kPressureLookbackMinutes + 5) * 60000, now);
    if (_disposed || read != _overReads) return;
    _over = _joined(history, _over ?? const []);
    if (_loaded) _recompute();
  }

  void _schedule() {
    if (_debounce != null || _disposed) return;
    _debounce = Timer(const Duration(seconds: 1), () {
      _debounce = null;
      _recompute();
    });
  }

  void _recompute() {
    if (_disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = arg.endMs ?? now;
    final floor = end - kMomentumMaxWindow.inMilliseconds;
    final start = arg.startMs < floor ? floor : arg.startMs;
    final b = _b != null && _b!.isNotEmpty ? _b : null;
    final strip = buildMomentum(
      a: _a,
      b: b,
      startMs: start,
      endMs: end,
      axisMs: arg.endMs == null ? arg.axisMs : null,
    );
    _pressure = arg.endMs == null ? _evaluatePressure(now, b) : null;
    state = PolyGameMomentum(strip: strip, pressure: _pressure, loaded: _loaded);
  }

  PressureSignal? _evaluatePressure(int now, List<OddsPoint>? b) {
    if (_a.isEmpty) return null;
    final timeline = ref.read(polyGameTimelineProvider(arg.gameId));
    // The feed's view of the game, else (until the feed has spoken about
    // it) the backend's.
    final ws = timeline.liveOr(sportsUpdateFor(
      ref.read(sportsLiveProvider),
      gameId: int.tryParse(arg.gameId),
      metadataGameId: arg.gameId,
    ));
    // Only a game the feed shows in play, and not at a break.
    if (ws == null || !ws.isInPlay) return null;
    final period = ws.period?.trim().toUpperCase() ?? '';
    final status = ws.status?.trim().toLowerCase() ?? '';
    if (period == 'HT' || status == 'break' || status == 'halftime') {
      return null;
    }
    // No score change is only known from the moment someone was watching:
    // the backend, or this phone.
    final knownSince = timeline.knownSinceMs;
    if (knownSince == null) return null;
    var quietFrom = knownSince;
    for (final e in timeline.events) {
      if ((e.scoreChanged || e.periodChanged) && e.tMs > quietFrom) {
        quietFrom = e.tMs;
      }
    }
    final quietMinutes = (now - quietFrom) ~/ 60000;

    int? leader;
    final aIsHome = _aIsHome;
    if (aIsHome != null) {
      final sport = gameSportOf(
        league: ws.leagueAbbreviation,
        score: ws.score,
        period: ws.period,
        cricket: ws.gameId == null,
      );
      final score = GameScore.parse(ws.score, sport);
      if (score.hasPair) {
        final diff = score.home! - score.away!;
        leader = diff == 0 ? 0 : ((diff > 0) == aIsHome ? 1 : -1);
      }
    }

    const step = 60000;
    final from = now - _kPressureLookbackMinutes * step;
    List<double?> sample(List<OddsPoint> points) =>
        resampleOdds(points, from, step, _kPressureLookbackMinutes);
    final over = _over;
    return detectPressure(
      a: sample(_a),
      b: b == null ? null : sample(b),
      over: over == null || !_moves(over, from) ? null : sample(over),
      quietMinutes: quietMinutes,
      leader: leader,
      previous: _pressure,
    );
  }

  /// A totals line nobody trades sits on one price; it says nothing.
  static bool _moves(List<OddsPoint> points, int sinceMs) {
    final seen = <double>{};
    for (final p in points) {
      if (p.tMs >= sinceMs) seen.add(p.p);
    }
    return seen.length >= 3;
  }
}

final polyGameMomentumProvider = NotifierProvider.autoDispose
    .family<PolyGameMomentumNotifier, PolyGameMomentum, PolyMomentumKey>(
  PolyGameMomentumNotifier.new,
);
