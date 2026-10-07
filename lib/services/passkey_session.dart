/// Invalidates asynchronous derivations without waiting for an OS ceremony.
/// Wipe waits only for storage writes already started, then deletes local data.
class PasskeySession {
  int _generation = 0;
  final Set<Future<void>> _writes = {};

  int get generation => _generation;

  void clear() => _generation++;

  void check(int generation) {
    if (generation != _generation) {
      throw StateError('Passkey operation cancelled. Authenticate again.');
    }
  }

  Future<void> write(int generation, Future<void> Function() operation) async {
    check(generation);
    final pending = Future<void>.sync(operation);
    _writes.add(pending);
    try {
      await pending;
    } finally {
      _writes.remove(pending);
    }
    check(generation);
  }

  Future<void> drainWrites() async {
    while (_writes.isNotEmpty) {
      await Future.wait(_writes.toList().map((pending) async {
        try {
          await pending;
        } catch (_) {
          // Wipe deletes the local store whether an earlier write succeeded.
        }
      }));
    }
  }
}
