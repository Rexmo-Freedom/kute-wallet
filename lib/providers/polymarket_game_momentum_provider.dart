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

/// The Over token to read beside the match with event slug [slug]: from
/// the event's own totals, else from its "more markets" sibling event
/// (where Polymarket keeps a soccer match's totals). Null when neither has
/// a traded line or the read fails. Re-read every two minutes, since the
/// most even line moves on after a goal.
final polyGameOverTokenProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, slug) async {
  if (slug.isEmpty) return null;
  final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  // The game's lines read is the same event: while it is a minute old or
  // less, its Over token stands and the event is not read a second time.
  try {
    final lines = await ref.watch(polyGameLinesProvider(slug).future);
    final at = lines.readAtMs;
    if (lines.overToken != null &&
        at != null &&
        DateTime.now().millisecondsSinceEpoch - at <= 60 * 1000) {
      return lines.overToken;
    }
  } catch (_) {}
  for (final s in [slug, '$slug-more-markets']) {
    try {
      final page = await PolymarketModel.readGammaKeysetPage(
        'events',
        {'slug': s},
        limit: 1,
        direct: true,
      );
      if (page.rows.isEmpty) continue;
      final token = pickOverToken(page.rows.first);
      if (token != null) return token;
    } catch (_) {
      // Fail soft: no totals input.
    }
  }
  return null;
});

/// One game's momentum inputs. [startMs] is the kickoff; [endMs] is null
/// while the game is in play. [axisMs] is the usual length of a game of
/// this sport while it is in play (null: the time played). [aIsHome] says
/// which side of the feed's score token A is (null: unknown).
typedef PolyMomentumKey = ({
  String gameId,
  String tokenA,
  String? tokenB,
  String? overToken,
  int startMs,
  int? endMs,
  int? axisMs,
  bool? aIsHome,
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

class PolyGameMomentumNotifier
    extends AutoDisposeFamilyNotifier<PolyGameMomentum, PolyMomentumKey> {
  List<OddsPoint> _a = const [];
  List<OddsPoint>? _b;
  List<OddsPoint>? _over;
  bool _loaded = false;
  bool _disposed = false;
  Timer? _debounce;
  PressureSignal? _pressure;

  @override
  PolyGameMomentum build(PolyMomentumKey arg) {
    _disposed = false;
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
        livePriceProvider.select((s) => (
              s.prices[arg.tokenA],
              arg.tokenB == null ? null : s.prices[arg.tokenB],
              arg.overToken == null ? null : s.prices[arg.overToken],
            )),
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
      // The Over token is not one of the sheet's own outcomes: join it to
      // the live feed (after this build; a provider may not change another
      // while it initializes).
      Future.microtask(() {
        if (_disposed) return;
        ref.read(livePriceProvider.notifier).addTokens([
          arg.tokenA,
          if (arg.tokenB != null) arg.tokenB!,
          if (arg.overToken != null) arg.overToken!,
        ]);
      });
    }
    return const PolyGameMomentum();
  }

  static List<OddsPoint> _appended(List<OddsPoint> list, int tMs, double p) {
    if (!p.isFinite || p < 0 || p > 1) return list;
    // One point per five seconds is plenty for one-minute buckets.
    if (list.isNotEmpty && tMs - list.last.tMs < 5000) {
      return [...list.take(list.length - 1), (tMs: list.last.tMs, p: p)];
    }
    return [...list, (tMs: tMs, p: p)];
  }

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
    final model = PolymarketModel();
    Future<List<OddsPoint>?> read(String? token, int fromMs) async {
      if (token == null || token.isEmpty) return null;
      final points = await model.getPriceHistoryWindow(
        token,
        // A few minutes before kickoff, so the first bucket has a price
        // to start from.
        startSec: (fromMs - 5 * 60000) ~/ 1000,
        endSec: end ~/ 1000 + 60,
        bucketSeconds: 60,
      );
      if (points == null) return null;
      return [
        for (final p in points)
          (tMs: p.timestamp.millisecondsSinceEpoch, p: p.price)
      ]..sort((x, y) => x.tMs.compareTo(y.tMs));
    }

    try {
      final results = await Future.wait([
        read(arg.tokenA, start),
        read(arg.tokenB, start),
        // The totals market only feeds the pressure signal, which looks a
        // few minutes back.
        if (arg.endMs == null)
          read(arg.overToken,
              now - (_kPressureLookbackMinutes + 5) * 60000)
        else
          Future<List<OddsPoint>?>.value(null),
      ]);
      if (_disposed) return;
      // History first, then whatever the live feed added while it loaded.
      List<OddsPoint> joined(List<OddsPoint>? history, List<OddsPoint> live) {
        if (history == null || history.isEmpty) return live;
        final cut = history.last.tMs;
        return [...history, for (final p in live) if (p.tMs > cut) p];
      }

      _a = joined(results[0], _a);
      if (arg.tokenB != null) _b = joined(results[1], _b ?? const []);
      if (arg.overToken != null) _over = joined(results[2], _over ?? const []);
    } catch (_) {
      // Fail soft: the live feed alone still builds the strip from now on.
    } finally {
      model.dispose();
    }
    if (_disposed) return;
    _loaded = true;
    _recompute();
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
    final ws = sportsUpdateFor(
      ref.read(sportsLiveProvider),
      gameId: int.tryParse(arg.gameId),
      metadataGameId: arg.gameId,
    );
    // Only a game the feed shows in play, and not at a break.
    if (ws == null || !ws.isInPlay) return null;
    final period = ws.period?.trim().toUpperCase() ?? '';
    final status = ws.status?.trim().toLowerCase() ?? '';
    if (period == 'HT' || status == 'break' || status == 'halftime') {
      return null;
    }
    final timeline = ref.read(polyGameTimelineProvider(arg.gameId));
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
    final aIsHome = arg.aIsHome;
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
