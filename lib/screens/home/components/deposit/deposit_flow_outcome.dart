import 'package:kute/services/tracking_service.dart';

/// The Move sheet's funnel outcome: `move_submitted` when the user
/// commits, then `move_completed` (the move left the sheet) or
/// `move_failed` (a fixed error category, never raw text), and one
/// `move_sheet_abandoned` when the sheet closes without a completion.
///
/// A route that hands the action to a flow with its own outcome (the
/// Ledger device flow, a Cash App order paid in Cash App) marks the
/// hand-off; if the sheet then closes before that flow reports back, the
/// abandon carries `handed_off_to_<flow>` instead of `user_closed`.
///
/// Nothing is sent after the sheet closed or after a completion, so one
/// sheet never reports two terminal outcomes.
class MoveFlowOutcome {
  static const String flow = 'move';

  /// The route and exact entered amount last reported.
  Map<String, Object> lastInputs = const {};

  bool _done = false;
  bool _closed = false;
  bool _failureTracked = false;
  String? _handoff;

  /// True once `move_completed` fired.
  bool get done => _done;

  /// The abandon reason a close would carry for a pending hand-off.
  String? get handoffReason => _handoff;

  bool get _ended => _done || _closed;

  /// The user committed to a move with [inputs].
  void submitted(Map<String, Object> inputs) {
    if (_ended) return;
    lastInputs = inputs;
    _failureTracked = false;
    _handoff = null;
    TrackingService.moneyFlowSubmitted(flow, props: inputs);
  }

  /// The move left the sheet. [outcome] says how far it got; the
  /// settlement pipelines report the final result.
  void completed({String outcome = 'submitted'}) {
    if (_ended) return;
    _done = true;
    _handoff = null;
    TrackingService.track('move_completed', params: {
      ...lastInputs,
      'outcome': outcome,
    });
    TrackingService.moneyFlowFinished(flow);
  }

  /// The submitted move did not go through. Once per submit: a retry is a
  /// new [submitted].
  void failed(String category, {required String stage}) {
    if (_ended || _failureTracked) return;
    _failureTracked = true;
    _handoff = null;
    TrackingService.track('move_failed', params: {
      ...lastInputs,
      'error_category': TrackingService.errorCategory(category),
      'stage': stage,
    });
    TrackingService.moneyFlowError(flow, category);
  }

  /// The action continues in [to]'s own flow (`ledger`, `cashapp`).
  void handedOff(String to) {
    if (_ended) return;
    _handoff = 'handed_off_to_$to';
  }

  /// The user came back and picked something else.
  void clearHandoff() => _handoff = null;

  /// The sheet closed: one abandon unless the move completed.
  void closed() {
    if (_closed) return;
    _closed = true;
    if (_done) {
      TrackingService.moneyFlowFinished(flow);
      return;
    }
    TrackingService.moneyFlowAbandoned(flow,
        reason: _handoff, props: lastInputs);
  }
}
