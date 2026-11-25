// lib/services/polymarket/remembered_setup.dart
//
// What the app remembers of a deposit wallet's one-time setup, and when a
// buy may lean on that memory.
//
// Every Polymarket order first re-verifies the deposit wallet on chain:
// that it has code and that its exchange approvals are set. The reads run
// on public Polygon RPCs and fail closed when none answers. On 2026-11-08
// that is what kept a person from betting for eight minutes: every RPC
// read on their phone timed out all evening, and each buy was declined in
// the re-check (`polymarket_placement_declined reason=setup_failed`, four
// times) before a single request reached the order book, although the
// same wallet had been verified deployed and approved days before. A
// deployed contract does not undeploy, and the approvals are only ever
// changed by the person, so a verification that succeeded lately is good
// evidence when a fresh one cannot be made at all.
//
// The memory is written only by a verification that ran on chain and is
// consulted only when the fresh one failed for want of the chain (every
// RPC failed, or the phone is offline). A refusal (the relayer, the order
// book), a changed account or a wallet whose EVM format is still moving
// is never papered over, and a forced repair (the book refused an order
// for a missing approval) always verifies afresh. The order book stays the
// arbiter: a refusal that names a missing approval still runs the setup
// repair the self-heal has.

import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException, RelayerSubmitRejected;

/// How long a chain verification counts as current.
const Duration kPolySetupMemoryTtl = Duration(days: 14);

/// One deposit wallet's last on-chain verification: it was deployed and
/// every trading approval was present at [verifiedAt].
class PolySetupMemory {
  const PolySetupMemory({required this.depositWallet, required this.verifiedAt});

  final String depositWallet;
  final DateTime verifiedAt;

  /// Stored as `<deposit wallet>:<epoch ms>`.
  String encode() =>
      '${depositWallet.toLowerCase()}:${verifiedAt.millisecondsSinceEpoch}';

  /// Null for anything that is not an [encode]d memory.
  static PolySetupMemory? decode(String? raw) {
    if (raw == null) return null;
    final at = raw.lastIndexOf(':');
    if (at <= 0) return null;
    final wallet = raw.substring(0, at);
    final ms = int.tryParse(raw.substring(at + 1));
    if (ms == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(wallet)) {
      return null;
    }
    return PolySetupMemory(
      depositWallet: wallet,
      verifiedAt: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// Verified within [within] of [now] (a clock set back is not current).
  bool isCurrentAt(DateTime now, {Duration within = kPolySetupMemoryTtl}) {
    final age = now.difference(verifiedAt);
    return !age.isNegative && age <= within;
  }
}

/// Whether the account counts as set up although its fresh verification
/// threw [error]: [memory] says the wallet was verified within
/// [kPolySetupMemoryTtl] of [now], it is the deposit wallet the account
/// knows ([knownDepositWallet], when known), and the failure was the
/// chain being unreachable, never a refusal. [offline] is the caller's
/// read of [error] (no internet, DNS, a stalled request).
bool polySetupRemembered(
  Object error, {
  required bool offline,
  required PolySetupMemory? memory,
  required String? knownDepositWallet,
  required DateTime now,
}) {
  if (memory == null || !memory.isCurrentAt(now)) return false;
  if (knownDepositWallet != null &&
      knownDepositWallet.isNotEmpty &&
      knownDepositWallet.toLowerCase() != memory.depositWallet.toLowerCase()) {
    return false;
  }
  // A changed account, a relayer that answered and refused, or anything
  // thrown on purpose by the setup itself: not about reaching the chain.
  if (error is StateError || error is RelayerSubmitRejected) return false;
  return error is PolymarketReadException || offline;
}
