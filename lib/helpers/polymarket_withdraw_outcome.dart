import 'package:kute/services/funding/settlement_funding_outcome.dart';

/// What a Predictions withdrawal that threw [error] hands its caller.
///
/// The settlement runner reads any throw from a funding call as "money
/// may have left": it parks the operation as unresolved and tells the
/// person we could not confirm whether their transfer left. That is
/// right once the signed batch has gone to the relayer. Before that
/// ([submitted] false) nothing moved: a balance read that failed, a
/// locked wallet, a grant that drifted, a batch the guard would not
/// start. Those come back as a [SettlementFundingRefused] carrying the
/// real cause, so the runner ends the operation as not funded and the
/// caller shows what actually happened.
///
/// An error that already says it never submitted
/// ([SettlementFundingNotStarted]) passes through as it is, and so does
/// anything thrown after the hand-over.
Object polymarketWithdrawalFailure(Object error, {required bool submitted}) {
  if (submitted || error is SettlementFundingNotStarted) return error;
  return SettlementFundingRefused(error);
}
