import 'package:flutter/foundation.dart';

/// Who asks for a seed.
enum SeedAccess {
  /// A screen that already ran its own gate (seed reveal, backup, restore).
  interactive,

  /// Background work. It resolves a seed only while the session is
  /// unlocked and the lock overlay is down.
  automatic,
}

/// Where a stored seed was read from.
enum SeedSource { v2Local, v2Synced, v1, root }

enum SeedUnavailableReason {
  /// No copy exists for this wallet.
  absent,

  /// Secure storage kept failing after the retries.
  storage,

  /// A copy exists but does not decrypt with the verified PIN.
  unreadable,
}

/// The unlocked session as seed readers see it.
@immutable
class SeedSession {
  const SeedSession({this.unlocked = false, this.typedPin});

  static const locked = SeedSession();

  /// The session is unlocked and the lock overlay is down.
  final bool unlocked;

  /// The Kute PIN typed in this process, held only while a stored wallet
  /// still needs it to decrypt a PIN-encrypted copy.
  final String? typedPin;

  @override
  String toString() => 'SeedSession(unlocked: $unlocked)';
}

sealed class SeedRead {
  const SeedRead();
}

final class SeedOk extends SeedRead {
  const SeedOk(this.value, this.source);
  final String value;
  final SeedSource source;

  @override
  String toString() => 'SeedOk($source)';
}

/// The seed needs an unlocked session, or a PIN that is not held.
final class SeedLocked extends SeedRead {
  const SeedLocked();
}

final class SeedUnavailable extends SeedRead {
  const SeedUnavailable(this.reason);
  final SeedUnavailableReason reason;

  @override
  String toString() => 'SeedUnavailable($reason)';
}

class SeedLockedException implements Exception {
  const SeedLockedException();
  @override
  String toString() => 'Wallet locked. Please unlock first.';
}

class SeedUnavailableException implements Exception {
  const SeedUnavailableException(this.reason);
  final SeedUnavailableReason reason;
  @override
  String toString() => 'SeedUnavailableException($reason)';
}
