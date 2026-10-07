import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/auth_model.dart';

export 'package:kute/services/secure/seed_access.dart';

final authModelProvider = StateProvider<AuthModel>((ref) {
  return AuthModel();
});

/// How the current session was unlocked.
enum UnlockMethod { pin, biometric }

@immutable
class SessionAuth {
  const SessionAuth({required this.method, required this.unlockedAt});
  final UnlockMethod method;
  final DateTime unlockedAt;
}

/// Set by a verified unlock, in memory only, so a cold start always locks
/// through splash. The lock overlay keeps it; [sessionUnlockedProvider] is
/// what tells whether the app is usable right now.
final sessionAuthProvider = StateProvider<SessionAuth?>((ref) => null);

/// The Kute PIN typed in this process. Never filled from storage, and
/// cleared right after unlock unless a stored wallet still needs the PIN
/// to decrypt a PIN-encrypted copy.
final typedPinProvider = StateProvider<String?>((ref) => null);

/// True while the in-place lock overlay covers the app (background gap
/// exceeded the auto-lock grace). Deliberately in-memory only: process
/// death also wipes [sessionAuthProvider], so a cold boot always locks
/// through splash regardless — "unlocked" must never be persisted.
/// Unlike the old relock (`router.go('/splash')` → `/home`), flipping
/// this does NOT touch navigation, so unlocking resumes the exact
/// screen/sheet the user left.
final appLockedProvider = StateProvider<bool>((ref) => false);

/// The session is unlocked and the lock overlay is down.
final sessionUnlockedProvider = Provider<bool>((ref) =>
    ref.watch(sessionAuthProvider) != null && !ref.watch(appLockedProvider));

/// What seed readers need from the session.
final seedSessionProvider = Provider<SeedSession>((ref) => SeedSession(
      unlocked: ref.watch(sessionUnlockedProvider),
      typedPin: ref.watch(typedPinProvider),
    ));

/// Returns whether the session is unlocked. A provider built while locked
/// also subscribes to the lock, so it builds again once the app unlocks.
/// Call it before the provider's first await.
bool watchSessionUnlock(Ref ref) {
  final unlocked = ref.read(sessionUnlockedProvider);
  if (!unlocked) ref.watch(sessionUnlockedProvider);
  return unlocked;
}

/// False from the moment the app resigns active (inactive/paused/hidden)
/// until it resumes. Drives the opaque privacy cover so balances are
/// never readable in the OS app switcher — which is what makes skipping
/// the lock inside the grace window safe.
final appVisibleProvider = StateProvider<bool>((ref) => true);
