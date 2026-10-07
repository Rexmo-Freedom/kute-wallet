// lib/services/polymarket/send_time_read.dart
//
// A read the placement needs the moment the approval returns (the order
// book, the deposit wallet's pUSD), started while the approval is still on
// screen so it is ready instead of awaited after it. A five-minute market
// moves in the second or two a biometric prompt takes; a cap computed from
// a book read before the prompt is already stale when the order is signed.
//
// [start] reads at once and, while nobody has taken the value, reads again
// every [refreshEvery] (when set) so what [take] gets is at most about
// [maxAge] old. [take] returns that value when it is fresh enough, joins a
// read still in flight that began within [maxAge], and otherwise reads
// anew. A failed read is never kept: [take] reads again.

import 'dart:async';

class PolymarketSendTimeRead<T> {
  PolymarketSendTimeRead(
    this._read, {
    required this.maxAge,
    this.refreshEvery,
    this.keepAlive = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<T> Function() _read;

  /// How old a value [take] may hand out.
  final Duration maxAge;

  /// While untaken, read again this often (null: read once).
  final Duration? refreshEvery;

  /// The refresh loop stops on its own after this long untaken.
  final Duration keepAlive;
  final DateTime Function() _clock;

  T? _value;
  DateTime? _valueAt;
  Future<T>? _inFlight;
  DateTime? _inFlightAt;
  DateTime? _startedAt;
  Timer? _timer;
  bool _taken = false;

  /// Reads issued, for tests and the latency trace.
  int reads = 0;

  bool get started => _startedAt != null;

  /// Starts reading now (and refreshing, when [refreshEvery] is set).
  void start() {
    _taken = false;
    _startedAt = _clock();
    _kick();
  }

  void _kick() {
    if (_inFlight != null) return;
    final at = _clock();
    final future = _issue();
    _inFlight = future;
    _inFlightAt = at;
    future.then((value) {
      _value = value;
      _valueAt = _clock();
    }, onError: (Object _) {}).whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightAt = null;
      }
      _scheduleRefresh();
    });
  }

  Future<T> _issue() {
    reads++;
    return _read();
  }

  void _scheduleRefresh() {
    final every = refreshEvery, started = _startedAt;
    if (every == null || _taken || started == null) return;
    if (_clock().difference(started) > keepAlive) return;
    _timer?.cancel();
    _timer = Timer(every, () {
      if (!_taken) _kick();
    });
  }

  /// A value at most [maxAge] old: the prefetched one, the read in flight
  /// when it began within [maxAge], or a new read. Ends the refresh loop.
  Future<T> take() {
    _taken = true;
    _timer?.cancel();
    _timer = null;
    final now = _clock();
    final valueAt = _valueAt;
    if (valueAt != null && now.difference(valueAt) <= maxAge) {
      return Future.value(_value as T);
    }
    final inFlight = _inFlight, inFlightAt = _inFlightAt;
    if (inFlight != null &&
        inFlightAt != null &&
        now.difference(inFlightAt) <= maxAge) {
      return inFlight;
    }
    return _issue();
  }

  /// Stops refreshing and forgets what was read.
  void cancel() {
    _taken = true;
    _timer?.cancel();
    _timer = null;
    _value = null;
    _valueAt = null;
    _startedAt = null;
  }
}
