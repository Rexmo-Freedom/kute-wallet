// lib/providers/hyperliquid_candles_provider.dart
//
// LIVE OHLC candles for ONE Hyperliquid market + timeframe, family-keyed
// by (WIRE coin, interval, window hours). This is the source the detail
// chart's candlesticks paint from — it replaces the old 30 s REST-poll
// FutureProvider that fed the monotone line chart.
//
// Mirrors hyperliquid_orderbook_provider.dart's WS lifecycle: REST seed
// first (candleSnapshot) so the chart paints its history within a few
// hundred ms, then a dedicated WS `candle` subscription keeps the leading
// bar ticking. onDispose unsubscribes and tears the socket down.
//
// LIVE UPSERT — the crux of a live candlestick chart. HL's `candle`
// channel re-sends the SAME open-time bucket many times per second as the
// in-progress candle mutates (its high/low/close/volume drift), then once
// per interval it starts emitting a NEW open-time bucket. So on each
// HlCandleMessage we UPSERT by openTime:
//   * openTime == last bar's openTime  → replace the last bar in place
//     (the in-progress candle just moved).
//   * openTime  > last bar's openTime  → append (a fresh bucket opened).
//   * openTime  < last bar's openTime  → stale/out-of-order frame; ignore.
// The working list is trimmed to the visible window so a long session
// doesn't grow unbounded.
//
// COALESCING — the in-progress bar can tick faster than the display needs.
// We mutate the working list synchronously but debounce state EMISSIONS to
// ~250 ms (same cadence as the order book), so the painter repaints at a
// sane rate regardless of frame volume.
//
// CRASH CONTRACT: the WS `messages` stream emits errors (terminal
// reconnect exhaustion included). The listener below attaches onError and
// degrades to the last-known candles with isLive=false — WITHOUT an
// onError handler the broadcast-stream error escapes to main.dart's zone
// guard as a FATAL crash. Same contract as the order book provider.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

/// Family key for [hyperliquidLiveCandlesProvider]. [wireCoin] MUST be the
/// wire coin (HlMarket.wireCoin) — a spot display symbol silently yields
/// no frames. [interval] is an HL candle interval ('1m','5m','1h','4h',…);
/// [windowHours] bounds how much trailing history the REST seed pulls and
/// how many bars the live list retains. [exact] keeps [interval] as asked
/// (the detail chart: the user picked it, older bars are paged in on
/// demand); otherwise a sparse market's seed may refine to a finer
/// interval so a small tape stays readable.
typedef HlLiveCandleKey = ({
  String wireCoin,
  String interval,
  int windowHours,
  bool exact,
});

/// Snapshot of a market's live candle series. [isLive] is the LIVE-dot
/// signal: true only while the WS is delivering candle frames; it drops to
/// false on reconnect exhaustion (candles stay on screen, frozen).
class HlLiveCandlesState {
  final List<HyperliquidCandle> candles;
  final bool isLive;

  const HlLiveCandlesState({
    this.candles = const [],
    this.isLive = false,
  });

  HlLiveCandlesState copyWith({
    List<HyperliquidCandle>? candles,
    bool? isLive,
  }) {
    return HlLiveCandlesState(
      candles: candles ?? this.candles,
      isLive: isLive ?? this.isLive,
    );
  }
}

/// Approximate minutes per HL candle interval — used to bound the retained
/// bar count to the requested window. Unknown intervals fall back to 60.
/// NOTE: '1M' (month) must be checked BEFORE lowercasing — lowercased it
/// collides with '1m' (minute) and turns a month of bars into minutes.
int _intervalMinutes(String interval) {
  final raw = interval.trim();
  if (raw.isEmpty) return 60;
  if (raw.endsWith('M')) {
    final n = int.tryParse(raw.substring(0, raw.length - 1)) ?? 1;
    return n * 60 * 24 * 30;
  }
  final s = raw.toLowerCase();
  final unit = s[s.length - 1];
  final n = int.tryParse(s.substring(0, s.length - 1)) ?? 1;
  switch (unit) {
    case 'm':
      return n;
    case 'h':
      return n * 60;
    case 'd':
      return n * 60 * 24;
    case 'w':
      return n * 60 * 24 * 7;
    default:
      return 60;
  }
}

/// One step finer on HL's interval ladder, for sparse markets.
const Map<String, String> _finerInterval = {
  '1M': '1w',
  '1w': '1d',
  '1d': '4h',
  '4h': '1h',
  '1h': '15m',
  '15m': '5m',
  '5m': '1m',
};

/// A seed the chart can actually paint: candles plus the interval they
/// were ultimately fetched at (the WS subscription must match it).
typedef _SeedResult = ({
  List<HyperliquidCandle> candles,
  String interval,
  int windowHours,
});

/// Fetches the REST seed, ADAPTING to thin markets. HL's candleSnapshot
/// returns only buckets that traded, so a HIP-3 equity like QQQ yields
/// ZERO bars for "last 24h × 1h" outside US market hours and a handful
/// of giant bars for "last week × 4h". Two ladders fix that:
///   * EMPTY  → widen the window (×4, then ×12) so the most recent
///     SESSIONS come into view — a weekend 1D request then shows
///     Friday's session instead of "No chart data".
///   * SPARSE (< 20 bars) → refine the interval one or two steps so the
///     traded periods yield a dense tape (~30-60 bars) instead of eight
///     22px blocks. Index-positioned painting over traded buckets is
///     exactly how equity charts collapse closed-market gaps.
/// The refined interval is returned so the live subscription ticks the
/// same buckets the seed painted.
Future<_SeedResult> _adaptiveSeed(
  dynamic model, {
  required String wireCoin,
  required String interval,
  required int windowHours,
  bool exact = false,
}) async {
  Future<List<HyperliquidCandle>> fetch(String iv, int hours) async {
    try {
      final list = await model.getCandles(
        coin: wireCoin,
        interval: iv,
        window: Duration(hours: hours),
      ) as List<HyperliquidCandle>;
      return list;
    } catch (_) {
      return const [];
    }
  }

  var effInterval = interval;
  var effHours = windowHours;
  var candles = await fetch(effInterval, effHours);

  // Ladder 1: nothing traded in the window — widen it. Skipped for
  // already-huge windows (widening a year tells us nothing new).
  if (candles.isEmpty && windowHours <= 24 * 45) {
    for (final mult in const [4, 12]) {
      // The venue keeps the newest 5000 candles per interval; a wider
      // window than that only costs weight for the same answer.
      final capHours = 5000 * _intervalMinutes(effInterval) ~/ 60;
      effHours = math.min(windowHours * mult, math.max(capHours, 1));
      candles = await fetch(effInterval, effHours);
      if (candles.isNotEmpty) break;
    }
    if (candles.isEmpty) effHours = windowHours;
  }

  // Ladder 2: too few traded buckets for a readable tape — refine the
  // interval, keeping the better (denser) result each step.
  var steps = 0;
  while (!exact && candles.length < 20 && steps < 2) {
    final finer = _finerInterval[effInterval];
    if (finer == null) break;
    final refined = await fetch(finer, effHours);
    if (refined.length <= candles.length) break;
    candles = refined;
    effInterval = finer;
    steps++;
  }

  // Keep the tape bounded — the freshest bars win. The detail chart asks
  // for about this many and pages older bars in on demand
  // (hl_chart_history.dart), so the cap never limits its history.
  const cap = 240;
  if (candles.length > cap) {
    candles = candles.sublist(candles.length - cap);
  }
  return (candles: candles, interval: effInterval, windowHours: effHours);
}

HyperliquidCandle _candleFromMessage(HlCandleMessage m) => HyperliquidCandle(
      openTime: DateTime.fromMillisecondsSinceEpoch(m.openTime),
      closeTime: DateTime.fromMillisecondsSinceEpoch(m.closeTime),
      open: m.open,
      high: m.high,
      low: m.low,
      close: m.close,
      volume: m.volume,
    );

final hyperliquidLiveCandlesProvider = StreamProvider.autoDispose
    .family<HlLiveCandlesState, HlLiveCandleKey>((ref, key) async* {
  final wireCoin = key.wireCoin;

  // 1. REST seed — historical fill so the chart paints immediately,
  //    ADAPTED for thin markets (see _adaptiveSeed): the interval the
  //    seed settled on is the one the live subscription must tick.
  final model = ref.read(hyperliquidTradingModelProvider);
  final seed = await _adaptiveSeed(
    model,
    wireCoin: wireCoin,
    interval: key.interval,
    windowHours: key.windowHours,
    exact: key.exact,
  );
  final interval = seed.interval;

  // Cap the retained bars to the visible window (+ a small buffer) so a
  // long live session doesn't grow the list without bound as new buckets
  // append.
  final minutesPerBar = _intervalMinutes(interval);
  final expectedBars = minutesPerBar > 0
      ? (seed.windowHours * 60 / minutesPerBar).ceil()
      : 200;
  final maxBars = (expectedBars + 4).clamp(8, 2000);

  // Working list, mutated in place by the upsert below. Kept ascending by
  // openTime (candleSnapshot already returns it that way).
  var candles = List<HyperliquidCandle>.from(seed.candles);
  if (candles.length > maxBars) {
    candles.removeRange(0, candles.length - maxBars);
  }
  var state = HlLiveCandlesState(candles: List.unmodifiable(candles));
  yield state;

  // 2. Live updates over a dedicated socket for this coin+interval.
  final ws = HyperliquidWebSocket();
  ref.onDispose(() {
    ws.unsubscribeCandle(wireCoin, interval);
    ws.dispose();
  });

  try {
    await ws.connect();
    state = state.copyWith(isLive: true);
    yield state;
    ws.subscribeCandle(wireCoin, interval);

    Timer? throttle;
    Timer? retryTimer;
    ref.onDispose(() => retryTimer?.cancel());
    var dirty = false;
    final controller = StreamController<HlLiveCandlesState>();

    void scheduleEmit() {
      // Coalesce emissions to ~250 ms; the in-progress bar can tick far
      // faster than the painter needs.
      throttle ??= Timer(const Duration(milliseconds: 250), () {
        throttle = null;
        if (!dirty) return;
        dirty = false;
        state = state.copyWith(candles: List.unmodifiable(candles));
        if (!controller.isClosed) controller.add(state);
      });
    }

    final msgSub = ws.messages.listen((msg) {
      if (msg is! HlCandleMessage) return;
      if (msg.coin != wireCoin || msg.interval != interval) return;

      final incoming = _candleFromMessage(msg);
      final openMs = msg.openTime;

      if (candles.isEmpty) {
        candles = [incoming];
      } else {
        final lastMs = candles.last.openTime.millisecondsSinceEpoch;
        if (openMs == lastMs) {
          // In-progress bar moved — replace the last bar in place.
          candles[candles.length - 1] = incoming;
        } else if (openMs > lastMs) {
          // A fresh interval bucket opened — append it.
          candles.add(incoming);
          if (candles.length > maxBars) {
            candles.removeRange(0, candles.length - maxBars);
          }
        } else {
          // Stale/out-of-order frame — ignore.
          return;
        }
      }
      dirty = true;
      scheduleEmit();
    }, onError: (Object err, StackTrace st) {
      // Socket errored mid-stream or exhausted its reconnects. Without this
      // handler the broadcast-stream error escapes to main.dart's zone
      // guard as a FATAL crash. Degrade: keep the last candles, LIVE off —
      // then SELF-HEAL via a provider rebuild (fresh socket + REST seed)
      // instead of freezing until the sheet is reopened.
      if (!controller.isClosed && state.isLive) {
        state = state.copyWith(isLive: false);
        controller.add(state);
      }
      retryTimer ??= Timer(const Duration(seconds: 30), () {
        ref.invalidateSelf();
      });
    });

    // On a RE-connect, the WS only replays the current in-progress
    // bucket — any bars that closed during the outage are gone from the
    // stream forever. Re-pull the REST seed to backfill them; the next
    // live frame keeps ticking the leading bar as usual.
    var everConnected = true; // we get here only after the first connect
    var reseeding = false;
    Future<void> reseedAfterReconnect() async {
      if (reseeding) return;
      reseeding = true;
      try {
        final fresh = await _adaptiveSeed(
          model,
          wireCoin: wireCoin,
          interval: interval,
          windowHours: seed.windowHours,
          exact: key.exact,
        );
        // Only accept a same-interval, non-empty backfill — an interval
        // drift would desync the live upsert's bucket matching.
        if (fresh.candles.isNotEmpty && fresh.interval == interval) {
          candles = List<HyperliquidCandle>.from(fresh.candles);
          if (candles.length > maxBars) {
            candles.removeRange(0, candles.length - maxBars);
          }
          dirty = true;
          scheduleEmit();
        }
      } catch (_) {
        // Backfill is best-effort; the live bar keeps the chart moving.
      } finally {
        reseeding = false;
      }
    }

    final connSub = ws.connectionState.listen((s) {
      final live = s == HlWsState.connected;
      if (live && everConnected && !state.isLive) {
        // disconnected → connected transition: backfill the gap.
        // ignore: unawaited_futures
        reseedAfterReconnect();
      }
      everConnected = everConnected || live;
      if (state.isLive != live) {
        state = state.copyWith(isLive: live);
        if (!controller.isClosed) controller.add(state);
      }
    });

    ref.onDispose(() {
      msgSub.cancel();
      connSub.cancel();
      throttle?.cancel();
      controller.close();
    });

    yield* controller.stream;
  } catch (_) {
    // WebSocket failed to open — keep the static REST seed (no LIVE dot).
    if (state.isLive) yield state.copyWith(isLive: false);
  }
});
