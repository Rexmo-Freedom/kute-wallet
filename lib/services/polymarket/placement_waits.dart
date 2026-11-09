// How long a Predictions placement waits on the steps before its order,
// and what it says when one of them does not finish in that time.
//
// The account's one-time setup (deploying the deposit wallet, its
// approvals, the order book credentials) and the conversion of a fresh
// deposit to pUSD both run on Polygon through the relayer. Each request in
// them is bounded, but together they can take minutes when the network is
// slow, and the slip used to wait on them behind "Setting up your
// Predictions wallet…" for as long as they took, or end with nothing said
// when they failed. These are the limits the placement waits for, and the
// errors that name the step, so the slip can say which one and offer a
// retry. A step that runs out of time keeps going in the background: the
// retry joins it rather than starting another.

/// The one-time account setup did not finish before the order: it failed,
/// or [timedOut] it is still running. No order was signed or sent.
class PolymarketSetupIncomplete implements Exception {
  const PolymarketSetupIncomplete({this.timedOut = false, this.cause});
  final bool timedOut;
  final Object? cause;

  @override
  String toString() => timedOut
      ? 'Predictions account setup is still running.'
      : 'Predictions account setup did not finish: $cause';
}

/// Whether a SELL goes to the venue although the account's setup re-check
/// did not finish ([error] is what it threw).
///
/// Every order first re-verifies the deposit wallet on chain: that it has
/// code and that its exchange approvals are set. The reads run on public
/// Polygon RPCs and fail closed when none answers. On 2026-11-08 a person's
/// second sell ended there, with no order posted (the setup failure and the
/// sell failure were recorded in the same millisecond), on a mobile
/// connection where 85% of requests to every host timed out, our backend
/// and the order book included; their first sell had reached the POST and
/// failed on the network after 18.7 s. This removes the chain read as a
/// reason to refuse; it cannot make a sale work on a connection that does
/// not reach the order book. A position the account
/// holds was bought through that wallet, so the wallet exists and its
/// approvals were set when it was created; the re-check adds nothing a
/// sell needs. The order book is the arbiter: a refusal that names a
/// missing approval still runs the setup repair the self-heal has.
///
/// A sell needs the [depositWallet] it signs for, so an account whose
/// address is not known yet still waits for setup, and a [StateError]
/// (the account changed under the order, no spending wallet) still ends
/// it: those are not about reaching the chain.
bool polySellProceedsWithoutSetup(Object error,
        {required String? depositWallet}) =>
    depositWallet != null && depositWallet.isNotEmpty && error is! StateError;

/// The deposit waiting in the wallet as USDC.e was still being converted
/// to pUSD when the order was ready to sign. No order was signed or sent.
class PolymarketFundsConverting implements Exception {
  const PolymarketFundsConverting();

  @override
  String toString() => 'The deposit is still being converted for trading.';
}

/// The wallet or the order book has not confirmed the buy's full all-in
/// collateral yet. No order was signed or sent; a live approved order may
/// wait and check again without sending another funding leg.
class PolymarketCollateralPending implements Exception {
  const PolymarketCollateralPending();

  @override
  String toString() => 'The trading balance is still being confirmed.';
}

class PolymarketPlacementWaits {
  PolymarketPlacementWaits._();

  /// Longest the slip waits for the account setup before telling the
  /// person it is taking longer than usual. A first setup normally takes
  /// well under a minute.
  static Duration setup = const Duration(seconds: 90);

  /// Longest an order waits for the conversion of a fresh deposit that it
  /// needs. One conversion is a single relayer batch (about 10 to 30 s).
  static Duration conversion = const Duration(seconds: 90);

  /// Longest an order waits for the order book to count money the wallet
  /// holds (after a conversion or a re-read request) before it is posted
  /// anyway. The book normally catches up within a block or two.
  static Duration venueCount = const Duration(seconds: 10);

  /// How often the order book's count is read while waiting for it: twice
  /// a second (a re-read request and a read each time), so the order goes
  /// out within half a second of the book counting the money. The budget
  /// ([venueCount]) is unchanged.
  static Duration venueCountPoll = const Duration(milliseconds: 500);
}
