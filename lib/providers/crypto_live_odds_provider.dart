// lib/providers/crypto_live_odds_provider.dart
//
// Live Up chance for the crypto Up/Down cards on screen, keyed by the Up
// token. See lib/services/polymarket/crypto_live_odds.dart for the
// sources and why they are read raw.
//
// Cards register their Up token through CryptoOddsScope while they can be
// seen (their tickers run); the notifier reads the market feed's live book
// for each registered token whenever the feed commits a frame and on a
// short timer. Tokens the feed has no current book for are read from the
// CLOB's REST midpoint every [kCryptoOddsRestEvery], all in one request,
// one request at a time, backing off after failures. A chance nobody
// confirmed for [kCryptoOddsMaxAge] is dropped. Nothing runs while no card
// is registered or while the app is in the background.

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/services/polymarket/crypto_live_odds.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

/// The clock the notifier stamps with; tests move it by hand.
final cryptoOddsClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

/// Whether the app is in the foreground. Tests override it.
final cryptoOddsForegroundProvider = Provider<bool Function()>((_) => () {
      final s = WidgetsBinding.instance.lifecycleState;
      return s == null || s == AppLifecycleState.resumed;
    });

/// The market feed's books; tests hand in a reset instance.
final cryptoOddsBooksProvider =
    Provider<PolymarketLiveBooks>((_) => PolymarketLiveBooks.instance);

/// Reads the CLOB midpoints for some tokens (`POST /midpoints`); tests
/// count and answer the calls.
final cryptoOddsMidpointsProvider =
    Provider<Future<Map<String, double>> Function(Iterable<String> tokens)>(
        (_) => (tokens) => fetchClobMidpoints(tokens));

/// How often the notifier looks at the books and drops stale chances
/// between feed commits.
const Duration kCryptoOddsTick = Duration(milliseconds: 500);

class CryptoLiveOddsNotifier
    extends AutoDisposeNotifier<Map<String, CryptoLiveOdds>> {
  /// Registered Up tokens with how many on-screen cards show each.
  final Map<String, int> _watched = {};

  /// When each token's chance was last confirmed (feed or REST).
  final Map<String, DateTime> _confirmedAt = {};

  /// Tokens the feed confirmed on the last read; REST leaves them alone.
  final Set<String> _onFeed = {};

  Timer? _timer;
  bool _disposed = false;

  bool _restInFlight = false;
  DateTime? _restAskedAt;
  int _restFailures = 0;

  /// REST reads sent so far (diagnostics and tests).
  int restReads = 0;

  DateTime _now() => ref.read(cryptoOddsClockProvider)();
  bool _foreground() => ref.read(cryptoOddsForegroundProvider)();

  @override
  Map<String, CryptoLiveOdds> build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      _watched.clear();
      _confirmedAt.clear();
      _onFeed.clear();
    });
    // Every commit of the market feed (about every 80 ms while frames
    // flow) is a moment the books may have moved.
    ref.listen<LivePriceState>(livePriceProvider, (_, __) => _readBooks());
    return const {};
  }

  /// Tokens registered right now.
  Set<String> get watched => _watched.keys.toSet();

  /// A card showing [token] is on screen. Pair with one [unwatch].
  void watch(String token) {
    if (token.isEmpty || _disposed) return;
    _watched[token] = (_watched[token] ?? 0) + 1;
    _timer ??= Timer.periodic(kCryptoOddsTick, (_) => tick());
    tick();
  }

  /// Releases one [watch]. The last release of a token forgets it; the
  /// last release of all stops the timer. Called from a widget's dispose,
  /// so the state write is deferred to a microtask.
  void unwatch(String token) {
    final n = _watched[token];
    if (n == null) return;
    if (n > 1) {
      _watched[token] = n - 1;
      return;
    }
    _watched.remove(token);
    _confirmedAt.remove(token);
    _onFeed.remove(token);
    if (_watched.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
    scheduleMicrotask(() {
      if (_disposed || _watched.containsKey(token)) return;
      if (state.containsKey(token)) {
        state = {...state}..remove(token);
      }
    });
  }

  /// One round: read the books, ask REST for the tokens the feed has no
  /// current book for (when due), drop what went stale.
  void tick() {
    if (_disposed || _watched.isEmpty || !_foreground()) return;
    _readBooks();
    _maybeReadRest();
    _dropStale();
  }

  /// One `POST /midpoints` for every registered token the feed has no
  /// current book for, at most every [kCryptoOddsRestEvery] (longer after
  /// failures, see [cryptoOddsRestInterval]) and never while the last one
  /// is still out.
  void _maybeReadRest() {
    if (_restInFlight) return;
    final wanted = [
      for (final t in _watched.keys)
        if (!_onFeed.contains(t)) t,
    ];
    if (wanted.isEmpty) return;
    final now = _now();
    final asked = _restAskedAt;
    if (asked != null &&
        now.difference(asked) < cryptoOddsRestInterval(_restFailures)) {
      return;
    }
    _restInFlight = true;
    _restAskedAt = now;
    restReads++;
    ref.read(cryptoOddsMidpointsProvider)(wanted).then((mids) {
      _restFailures = 0;
      _applyRest(mids);
    }, onError: (Object _) {
      _restFailures++;
    }).whenComplete(() => _restInFlight = false);
  }

  void _applyRest(Map<String, double> mids) {
    if (_disposed || mids.isEmpty) return;
    final now = _now();
    Map<String, CryptoLiveOdds>? next;
    mids.forEach((token, up) {
      // The feed is preferred: a book that came back while the request
      // was out wins, and a card that left takes its token with it.
      if (!_watched.containsKey(token) || _onFeed.contains(token)) return;
      if (!cryptoOddsSane(up)) return;
      _confirmedAt[token] = now;
      final odds = CryptoLiveOdds(up, CryptoOddsSource.rest);
      if (state[token] != odds) (next ??= {...state})[token] = odds;
    });
    if (next != null) state = next!;
  }

  void _readBooks() {
    if (_disposed || _watched.isEmpty || !_foreground()) return;
    final books = ref.read(cryptoOddsBooksProvider);
    final now = _now();
    Map<String, CryptoLiveOdds>? next;
    for (final token in _watched.keys) {
      final up = cryptoShownUp(books.snapshot(token),
          lastTrade: books.lastTrade(token));
      if (up == null) {
        _onFeed.remove(token);
        continue;
      }
      _onFeed.add(token);
      _confirmedAt[token] = now;
      final odds = CryptoLiveOdds(up, CryptoOddsSource.websocket);
      if (state[token] != odds) (next ??= {...state})[token] = odds;
    }
    if (next != null) state = next;
  }

  void _dropStale() {
    final now = _now();
    final stale = [
      for (final token in state.keys)
        if (!_watched.containsKey(token) ||
            now.difference(_confirmedAt[token] ?? DateTime(0)) >
                kCryptoOddsMaxAge)
          token,
    ];
    if (stale.isEmpty) return;
    state = {...state}..removeWhere((k, _) => stale.contains(k));
  }
}

/// Live Up chance per registered Up token (see [CryptoLiveOddsNotifier]).
/// A card reads `select((s) => s[upToken]?.up)` and falls back to the
/// market list's price when it is null.
final cryptoLiveOddsProvider = NotifierProvider.autoDispose<
    CryptoLiveOddsNotifier, Map<String, CryptoLiveOdds>>(
  CryptoLiveOddsNotifier.new,
);
