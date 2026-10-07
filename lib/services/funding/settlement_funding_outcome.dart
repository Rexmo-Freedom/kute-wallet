/// What a funding call can say about whether money left.
///
/// The settlement runner wraps anything thrown by a funding call into
/// `SettlementFundingUnknown`, which tells the person we could not
/// confirm whether their transfer left and that we are checking. That is
/// the right thing to say when a request went out and its answer never
/// came back. It is the wrong thing to say, and alarming, when the call
/// refused before it sent anything: a locked wallet, a capability that
/// is switched off, a destination that failed validation, an earlier
/// transfer still settling. Nothing left, there is nothing to check, and
/// the person is owed the actual reason.
///
/// A funding path that KNOWS nothing was submitted says so by throwing
/// something that implements [SettlementFundingNotStarted]. The runner
/// abandons the operation and lets the original error through, so the
/// caller shows what really happened.
library;

/// Marker: this error was raised before anything was submitted, so no
/// funds moved. Only throw it where that is certain.
abstract interface class SettlementFundingNotStarted {}

/// A funding call that refused before submitting, carrying whatever it
/// refused with. Used where the refusal is an ordinary error (a locked
/// wallet, a disabled capability) that the caller already knows how to
/// put into words.
class SettlementFundingRefused
    implements Exception, SettlementFundingNotStarted {
  const SettlementFundingRefused(this.cause);

  final Object cause;

  @override
  String toString() => 'SettlementFundingRefused($cause)';
}
