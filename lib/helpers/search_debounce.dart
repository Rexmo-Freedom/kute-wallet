import 'dart:async';

/// Cancels work before it starts, including providers disposed during a delay.
class SearchDebounce {
  final _ready = Completer<bool>();
  late final Timer _timer;

  SearchDebounce(Duration delay) {
    _timer = Timer(delay, () => _ready.complete(true));
  }

  Future<bool> get ready => _ready.future;

  void cancel() {
    _timer.cancel();
    if (!_ready.isCompleted) _ready.complete(false);
  }
}

/// Local lists remain on-device. Yield between small batches so an older
/// phone can draw/edit, and abandoned queries stop before scanning the rest.
Future<List<T>> searchInBatches<T>(Iterable<T> items, {
  required bool Function(T) matches,
  required bool Function() isCancelled,
  required int limit,
}) async {
  final result = <T>[];
  var visited = 0;
  for (final item in items) {
    if (isCancelled()) return [];
    if (++visited % 64 == 0) {
      await Future<void>.delayed(Duration.zero);
      if (isCancelled()) return [];
    }
    if (matches(item)) {
      result.add(item);
      if (result.length >= limit) break;
    }
  }
  return result;
}
