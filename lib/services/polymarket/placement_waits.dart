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

/// The deposit waiting in the wallet as USDC.e was still being converted
/// to pUSD when the order was ready to sign. No order was signed or sent.
class PolymarketFundsConverting implements Exception {
  const PolymarketFundsConverting();

  @override
  String toString() => 'The deposit is still being converted for trading.';
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
}
