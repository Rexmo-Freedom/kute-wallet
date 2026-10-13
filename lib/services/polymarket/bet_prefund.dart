// lib/services/polymarket/bet_prefund.dart
//
// Getting a fast prediction ready before Confirm (founder option A,
// 2026-10). On a 5- or 15-minute round or a game in play the move from
// Dollars takes about as long as the window the bet has, so the slip
// starts it while the person is still on the ticket:
//
// - An amount held for a second on such a market, short of Predictions
//   cash ([planBetFunding] says what moves), asks the step-up ONCE. That
//   one approval is the funded bet's own (`PmGrants.fundedBetReview`, the
//   30 min autofire grant): market and side, the stake, the worst price,
//   the slippage and the funding cap. The move starts at once under it,
//   through the shared funding engine (Dollars first, then Investing cash
//   pulled home), exactly as at Confirm.
// - Confirm then queues the bet behind that move with no second prompt:
//   it fires the moment the money lands, or at once when it already has
//   (the autofire, exactly like the Confirm-time funded path).
// - A larger amount tops up under the same approval only while it stays
//   inside the stake and funding caps approved; past them it asks again.
//   A smaller one just leaves the rest on Predictions.
// - Closing the slip leaves the moved cash on Predictions (one balance);
//   nothing comes back and the approval is dropped.
// - Declining the prompt never asks again on this slip: Confirm funds the
//   bet as before, with its own one prompt.
//
// Before any funding (here or at Confirm) the market must still take
// orders and must not end before a move could land: the funding p95 plus
// a margin ([predictionsFundingBlock]).
//
// The security model is unchanged: the funding rail only takes a move
// approved by a fresh step-up grant, and the small-action allowance and
// the fast-bet window never cover a funding leg (an autofire grant always
// prompts).

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/helpers/auth_grant.dart' show AuthGrant;
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/event_trading_over.dart'
    show polyTradingOver;
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart'
    show isPolymarketFastRound;
import 'package:kute/services/tracking_service.dart';

/// How long a move from Dollars into Predictions takes to land, at the
/// 95th percentile (Polygon funding; the app keeps no measured figure).
const Duration kPredictionsFundingP95 = Duration(seconds: 90);

/// Room on top of [kPredictionsFundingP95] for the order itself.
const Duration kPredictionsFundingMargin = Duration(seconds: 30);

/// How long an amount must stay unchanged before the slip gets it ready.
const Duration kPrefundHold = Duration(seconds: 1);

/// Why a market cannot be funded now.
enum PredictionsFundingBlock {
  /// Closed, not taking orders, or a short round already over.
  ended,

  /// It ends before a move could land and the order go in.
  closing,

  /// The market's state could not be read. Pre-funding needs a positive
  /// read and skips; Confirm-time funding goes on (the order itself is
  /// refused by a market that is shut).
  unread,
}

/// The CLOB's own word on a market (`GET /markets/{condition_id}`).
class PolymarketMarketWindow {
  const PolymarketMarketWindow({
    required this.acceptingOrders,
    required this.closed,
    this.endAt,
  });

  final bool acceptingOrders;
  final bool closed;
  final DateTime? endAt;
}

/// Whether a bet on this market may be funded now: it takes orders
/// ([market], when read) and does not end within [landing] plus [margin]
/// of [now]. [endAt] is the slip's own end (Gamma), else the CLOB's.
///
/// An end already past only blocks a short round: a longer market's end
/// date is for display and it trades until it resolves (see
/// `event_trading_over.dart`), so whether it takes orders decides.
PredictionsFundingBlock? predictionsFundingBlock({
  PolymarketMarketWindow? market,
  DateTime? endAt,
  required bool fastRound,
  bool requireRead = false,
  DateTime? now,
  Duration landing = kPredictionsFundingP95,
  Duration margin = kPredictionsFundingMargin,
}) {
  if (market != null && (market.closed || !market.acceptingOrders)) {
    return PredictionsFundingBlock.ended;
  }
  final at = now ?? DateTime.now();
  final end = endAt ?? market?.endAt;
  if (end != null) {
    final left = end.difference(at);
    if (left <= Duration.zero) {
      if (fastRound) return PredictionsFundingBlock.ended;
    } else if (left < landing + margin) {
      return PredictionsFundingBlock.closing;
    }
  }
  if (market == null && requireRead) return PredictionsFundingBlock.unread;
  return null;
}

/// Whether a slip must not open on this market: its event says it is
/// closed, inactive or ended ([polyTradingOver] by its explicit flags,
/// never a live game's paused book), or it is a short round whose end has
/// passed.
bool polymarketSlipEnded({
  PolymarketEvent? event,
  String? slug,
  String? question,
  DateTime? endAt,
  DateTime? now,
}) {
  if (event != null && polyTradingOver(event, inPlay: true)) return true;
  final at = now ?? DateTime.now();
  return endAt != null &&
      !endAt.isAfter(at) &&
      isPolymarketFastRound(
          slug: slug, question: question, endAt: endAt, now: at);
}

/// The fast markets a slip gets ready before Confirm.
enum PrefundMarketKind { short, live }

/// [PrefundMarketKind.short] for a 5- or 15-minute round, `live` for a
/// game in play ([live]: the venue holds its orders for an in-play
/// delay), else null: the same flags the slippage default and the fast
/// fill read.
PrefundMarketKind? prefundMarketKind({
  String? slug,
  String? question,
  DateTime? endAt,
  required bool live,
  DateTime? now,
}) {
  if (isPolymarketFastRound(
      slug: slug, question: question, endAt: endAt, now: now)) {
    return PrefundMarketKind.short;
  }
  return live ? PrefundMarketKind.live : null;
}

/// What an armed approval binds besides the stake: the outcome token
/// (market and side) and the order's shape.
class PrefundSelection {
  const PrefundSelection({
    required this.tokenId,
    required this.isLimit,
    required this.slippagePct,
  });

  final String tokenId;
  final bool isLimit;
  final double slippagePct;

  @override
  bool operator ==(Object other) =>
      other is PrefundSelection &&
      other.tokenId == tokenId &&
      other.isLimit == isLimit &&
      other.slippagePct == slippagePct;

  @override
  int get hashCode => Object.hash(tokenId, isLimit, slippagePct);
}

/// The slip as it stands, read when the hold fires or Confirm is tapped.
class PrefundSnapshot {
  const PrefundSnapshot({
    required this.kind,
    required this.selection,
    required this.amountUsd,
    required this.minBetUsd,
    required this.requiredUsd,
    required this.readyUsd,
    required this.balanceUsd,
    required this.dollarsUsd,
    required this.allowed,
    this.busy = false,
  });

  /// Null on a market that is not fast.
  final PrefundMarketKind? kind;
  final PrefundSelection selection;
  final double amountUsd;
  final double minBetUsd;

  /// The Predictions cash this stake takes (stake, fees at the worst
  /// price, the rounding cent).
  final double requiredUsd;

  /// What a new buy may spend of the venue cash now (resting buys out).
  final double readyUsd;

  /// The venue cash itself, for when a move has landed.
  final double balanceUsd;

  /// What a move can reach: Dollars, plus the Investing cash the shared
  /// funding engine pulls home when Dollars fall short.
  final double dollarsUsd;

  /// Hot wallet, account read, and every gate open: the policy (region,
  /// predictions and the market's category), deposits into Predictions,
  /// advanced trading when used.
  final bool allowed;

  /// A placement running, another funded bet queued, Predictions cash
  /// being swept: nothing starts.
  final bool busy;
}

/// What the approval is asked for.
class PrefundRequest {
  const PrefundRequest({
    required this.amountUsd,
    required this.fundingCapUsd,
    required this.kind,
    required this.atConfirm,
  });

  final double amountUsd;

  /// The move the approval covers ([planBetFunding]'s `fundUsd`, 0 when
  /// the money is already on its way).
  final double fundingCapUsd;
  final PrefundMarketKind? kind;

  /// Asked at Confirm (the bet's own prompt) rather than to get it ready.
  final bool atConfirm;
}

enum PrefundApprovalResult { approved, declined, unavailable }

/// The step-up's answer: the grant and the prepared bet it binds, or why
/// there is none ([PrefundApprovalResult.declined]: the person said no).
class PrefundApproval {
  const PrefundApproval.approved(AuthGrant this.grant, PendingBetIntent this.intent)
      : result = PrefundApprovalResult.approved;
  const PrefundApproval.declined()
      : result = PrefundApprovalResult.declined,
        grant = null,
        intent = null;
  const PrefundApproval.unavailable()
      : result = PrefundApprovalResult.unavailable,
        grant = null,
        intent = null;

  final PrefundApprovalResult result;
  final AuthGrant? grant;

  /// The prepared bet (executable quote, fee terms) the grant binds, its
  /// `fundUsd` the approved funding cap.
  final PendingBetIntent? intent;
}

typedef PrefundApprove = Future<PrefundApproval> Function(
    PrefundRequest request);
typedef PrefundFund = Future<OrderFundingOutcome> Function(
    double fundUsd, AuthGrant grant,
    {required double requiredUsd, required double readyUsd});
typedef PrefundPlan = Future<OrderFundingPlan> Function(
    {required double requiredUsd, required double readyUsd});
typedef PrefundWindow = Future<PredictionsFundingBlock?> Function(
    {required bool requireRead});

/// One move made for the slip.
class PrefundMove {
  PrefundMove({
    required this.ref,
    required this.sentUsd,
    required this.arrivingUsd,
    required this.readyBeforeUsd,
  });

  /// The move's one-way analytics reference (never the raw quote id).
  final String ref;
  final double sentUsd;
  final double arrivingUsd;

  /// The venue cash before it, counting earlier moves still on their way:
  /// it has landed once the venue holds this plus 99% of [arrivingUsd].
  final double readyBeforeUsd;
  bool landed = false;
}

class _Arm {
  _Arm({
    required this.grant,
    required this.intent,
    required this.selection,
    required this.maxStakeUsd,
    required this.fundingCapUsd,
  });

  final AuthGrant grant;
  final PendingBetIntent intent;
  final PrefundSelection selection;
  final double maxStakeUsd;
  final double fundingCapUsd;

  /// Moved under this approval so far.
  double fundedUsd = 0;
}

/// What Confirm does with the slip's pre-funding.
sealed class PrefundConfirm {
  const PrefundConfirm();
}

/// Nothing was got ready: Confirm runs as before.
final class PrefundNotUsed extends PrefundConfirm {
  const PrefundNotUsed();
}

/// The bet is queued behind the money: put [intent] in the pending
/// provider; the autofire places it on landing (at once when landed).
final class PrefundQueued extends PrefundConfirm {
  const PrefundQueued(this.intent, {required this.fundUsd});
  final PendingBetIntent intent;

  /// What moved from Dollars for this bet.
  final double fundUsd;
}

/// The person declined the prompt Confirm needed: nothing placed.
final class PrefundDeclined extends PrefundConfirm {
  const PrefundDeclined();
}

/// The market cannot take a funded bet in time: nothing moved.
final class PrefundBlocked extends PrefundConfirm {
  const PrefundBlocked(this.block);
  final PredictionsFundingBlock block;
}

/// A top-up the bet needed was refused or Dollars fell short: nothing
/// placed, the cash already moved stays.
final class PrefundFundingFailed extends PrefundConfirm {
  const PrefundFundingFailed(this.outcome);
  final OrderFundingOutcome outcome;
}

/// The slip's pre-funding: the hold timer, the one armed approval, the
/// moves made under it, and the hand-off to the autofire at Confirm.
/// Owned by one slip (its draft); [close] when the slip goes.
class BetPrefund {
  BetPrefund({
    required PrefundApprove approve,
    required PrefundFund fund,
    required PrefundPlan plan,
    required PrefundWindow window,
    void Function()? onDisarm,
    void Function()? onChanged,
    DateTime Function()? clock,
    this.hold = kPrefundHold,
  })  : _approve = approve,
        _fund = fund,
        _plan = plan,
        _window = window,
        _onDisarm = onDisarm,
        _onChanged = onChanged,
        _clock = clock ?? DateTime.now;

  final PrefundApprove _approve;
  final PrefundFund _fund;
  final PrefundPlan _plan;
  final PrefundWindow _window;
  final void Function()? _onDisarm;
  final void Function()? _onChanged;
  final DateTime Function() _clock;
  final Duration hold;

  _Arm? _arm;
  final List<PrefundMove> _moves = [];
  Timer? _timer;
  Future<void>? _running;
  PrefundSnapshot Function()? _again;
  DateTime? _firstStartedAt;
  bool _closed = false;
  bool _handedOff = false;
  bool _declined = false;
  bool _stopped = false;

  /// The person declined the prompt on this slip: it is never asked again
  /// here, and Confirm funds as before.
  bool get declined => _declined;

  /// An approval is held for the slip's bet.
  bool get armed {
    final arm = _arm;
    return arm != null &&
        !arm.grant.revoked &&
        !arm.grant.consumed &&
        !arm.grant.isExpiredAt(_clock());
  }

  /// A prompt or a move is running.
  bool get running => _running != null;

  /// The slip's pre-funding is in play: armed, running, or money it moved
  /// still on its way. The slip's button is then the bet.
  bool get engaged =>
      !_handedOff && (armed || running || inFlightArrivingUsd > 0);

  /// What the moves still on their way will bring.
  double get inFlightArrivingUsd => _moves
      .where((m) => !m.landed)
      .fold<double>(0, (sum, m) => sum + m.arrivingUsd);

  /// Everything moved for this slip.
  double get movedUsd =>
      _moves.fold<double>(0, (sum, m) => sum + m.sentUsd);

  @visibleForTesting
  List<PrefundMove> get moves => List.unmodifiable(_moves);

  /// The amount (or the side, or the order) changed: wait [hold] for it to
  /// settle, then look again with [read].
  void scheduleHold(PrefundSnapshot Function() read) {
    _timer?.cancel();
    if (_closed || _handedOff) return;
    _timer = Timer(hold, () {
      _timer = null;
      unawaited(_onHold(read));
    });
  }

  /// The hold firing now, for tests.
  @visibleForTesting
  Future<void> holdFired(PrefundSnapshot Function() read) => _onHold(read);

  void cancelHold() {
    _timer?.cancel();
    _timer = null;
  }

  /// The venue now holds [balanceUsd]: the moves it covers have landed.
  void observeBalance(double balanceUsd) {
    for (final m in _moves) {
      if (m.landed) continue;
      if (balanceUsd + 1e-9 >= m.readyBeforeUsd + m.arrivingUsd * 0.99) {
        m.landed = true;
        PredictionFundingLedger.instance.landed(m.ref);
      }
    }
  }

  Future<void> _onHold(PrefundSnapshot Function() read) async {
    if (_running != null) {
      // Looked at again once the running step is done.
      _again = read;
      return;
    }
    final run = _evaluate(read());
    _running = run;
    try {
      await run;
    } catch (_) {
      // A failed read or prompt leaves Confirm to fund as before.
    } finally {
      _running = null;
      _onChanged?.call();
    }
    final again = _again;
    _again = null;
    if (again != null && !_closed && !_handedOff) {
      await _onHold(again);
    }
  }

  Future<void> _evaluate(PrefundSnapshot s) async {
    if (_closed || _handedOff || _stopped || s.busy || !s.allowed) return;
    if (s.kind == null || s.selection.isLimit) return;
    if (!s.amountUsd.isFinite ||
        s.amountUsd <= 0 ||
        s.amountUsd + 1e-9 < s.minBetUsd) {
      return;
    }
    if (_arm != null && (!armed || _arm!.selection != s.selection)) {
      _disarm();
    }
    final ready = s.readyUsd + inFlightArrivingUsd;
    final plan = await _plan(requiredUsd: s.requiredUsd, readyUsd: ready);
    // Enough Predictions cash, or on its way: nothing to get ready.
    if (plan.fundUsd <= 0 || _closed) return;
    final arm = _arm;
    if (arm != null && armed && _withinCaps(arm, s.amountUsd, plan.fundUsd)) {
      // Inside what was approved: top up under the same approval.
      if (s.dollarsUsd + 1e-9 < plan.fundUsd) return;
      if (await _window(requireRead: true) != null) return;
      await _move(arm, plan.fundUsd, s, ready);
      return;
    }
    if (_declined) return;
    // Dollars short of the move: Confirm shows the Add path as before.
    if (s.dollarsUsd + 1e-9 < plan.fundUsd) return;
    if (await _window(requireRead: true) != null) return;
    if (_closed) return;
    final approval = await _approve(PrefundRequest(
        amountUsd: s.amountUsd,
        fundingCapUsd: plan.fundUsd,
        kind: s.kind,
        atConfirm: false));
    switch (approval.result) {
      case PrefundApprovalResult.declined:
        _declined = true;
        _arm = null;
        TrackingService.track('prediction_prefund_declined', params: {
          'amount_usd': s.amountUsd,
          'market_kind': s.kind!.name,
        });
        return;
      case PrefundApprovalResult.unavailable:
        _arm = null;
        return;
      case PrefundApprovalResult.approved:
        break;
    }
    final next = _armWith(approval, s, plan.fundUsd);
    if (_closed) {
      _disarm();
      return;
    }
    _firstStartedAt ??= _clock();
    TrackingService.track('prediction_prefund_started', params: {
      'amount_usd': s.amountUsd,
      'fund_usd': plan.fundUsd,
      'market_kind': s.kind!.name,
    });
    await _move(next, plan.fundUsd, s, ready);
  }

  bool _withinCaps(_Arm arm, double amountUsd, double extraUsd) =>
      amountUsd <= arm.maxStakeUsd + 1e-9 &&
      arm.fundedUsd + extraUsd <= arm.fundingCapUsd + 1e-9;

  _Arm _armWith(PrefundApproval approval, PrefundSnapshot s, double capUsd) {
    final intent = approval.intent!;
    return _arm = _Arm(
      grant: approval.grant!,
      intent: intent,
      selection: s.selection,
      maxStakeUsd: intent.amount,
      fundingCapUsd: capUsd,
    );
  }

  /// Moves [usd] under [arm]'s approval. A refusal or Dollars falling
  /// short stops the slip's pre-funding (Confirm funds as before).
  Future<OrderFundingOutcome> _move(
      _Arm arm, double usd, PrefundSnapshot s, double readyUsd) async {
    final readyBefore = s.balanceUsd + inFlightArrivingUsd;
    final outcome = await _fund(usd, arm.grant,
        requiredUsd: s.requiredUsd, readyUsd: readyUsd);
    switch (outcome) {
      case OrderFundingFunded(:final move):
        final ref = TrackingService.orderRef(move.quoteId);
        PredictionFundingLedger.instance.sent(ref, usd: move.sentUsd);
        _moves.add(PrefundMove(
          ref: ref,
          sentUsd: move.sentUsd,
          arrivingUsd: move.arrivingUsdEstimate,
          readyBeforeUsd: readyBefore,
        ));
        arm.fundedUsd += move.sentUsd;
        // The slip went while the move was being sent: the cash stays on
        // Predictions, held by nothing.
        if (_closed) _releaseUnplaced();
      case OrderFundingNotNeeded():
        break;
      case OrderFundingRefused() || OrderFundingNeedsDollars():
        _stopped = true;
        if (identical(_arm, arm)) _disarm();
    }
    return outcome;
  }

  /// Confirm was tapped with [s] on the slip. Waits for a running step,
  /// then: nothing got ready ([PrefundNotUsed]); or the bet queued behind
  /// the money under the approval already held, topped up inside its caps
  /// ([PrefundQueued], no prompt); or, when the slip changed past what
  /// was approved while money is on its way, the bet's own one prompt
  /// first ([PrefundRequest.atConfirm]).
  Future<PrefundConfirm> confirm(PrefundSnapshot s) async {
    cancelHold();
    _again = null;
    final running = _running;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    if (_closed || _handedOff) return const PrefundNotUsed();
    if (_arm != null && (!armed || _arm!.selection != s.selection)) {
      _disarm();
    }
    if (!armed && inFlightArrivingUsd <= 0) return const PrefundNotUsed();
    if (s.selection.isLimit) {
      _disarm();
      return const PrefundNotUsed();
    }
    final ready = s.readyUsd + inFlightArrivingUsd;
    final plan = await _plan(requiredUsd: s.requiredUsd, readyUsd: ready);
    final moves = plan.fundUsd > 0;
    if (moves) {
      // Nothing more moves for a market that cannot take the bet in time.
      final block = await _window(requireRead: false);
      if (block != null && block != PredictionsFundingBlock.unread) {
        return PrefundBlocked(block);
      }
    }
    var arm = _arm;
    final covered = arm != null &&
        armed &&
        _withinCaps(arm, s.amountUsd, moves ? plan.fundUsd : 0);
    if (!covered) {
      // Past what was approved (or the approval went) with money on its
      // way: the bet's own one prompt, covering only what still moves.
      if (moves && s.dollarsUsd + 1e-9 < plan.fundUsd) {
        _disarm();
        return const PrefundNotUsed();
      }
      final approval = await _approve(PrefundRequest(
          amountUsd: s.amountUsd,
          fundingCapUsd: moves ? plan.fundUsd : 0,
          kind: s.kind,
          atConfirm: true));
      switch (approval.result) {
        case PrefundApprovalResult.declined:
        case PrefundApprovalResult.unavailable:
          _arm = null;
          return const PrefundDeclined();
        case PrefundApprovalResult.approved:
          break;
      }
      arm = _armWith(approval, s, moves ? plan.fundUsd : 0);
    }
    if (moves) {
      final outcome = await _move(arm, plan.fundUsd, s, ready);
      if (outcome is OrderFundingRefused || outcome is OrderFundingNeedsDollars) {
        return PrefundFundingFailed(outcome);
      }
    }
    final last = _moves.isEmpty ? null : _moves.last;
    final now = _clock();
    final queued = arm.intent.copyWith(
      amount: s.amountUsd,
      status: PendingBetStatus.awaitingBalance,
      // The funding cap the approval binds, exactly: the autofire puts
      // it on the order it signs.
      fundUsd: arm.fundingCapUsd,
      fundQuoteRef: last?.ref,
      fundReadyUsd: last?.readyBeforeUsd,
      fundArrivingUsd: last?.arrivingUsd,
      queuedAt: now,
    );
    _handedOff = true;
    if (_moves.isNotEmpty) {
      final started = _firstStartedAt ?? now;
      TrackingService.track('prediction_prefund_used', params: {
        'amount_usd': s.amountUsd,
        'seconds_to_confirm':
            (now.difference(started).inMilliseconds / 1000).round(),
      });
    }
    return PrefundQueued(queued, fundUsd: movedUsd);
  }

  void _disarm() {
    final arm = _arm;
    _arm = null;
    if (arm == null) return;
    arm.grant.revoke();
    _onDisarm?.call();
  }

  /// Moves made here that no bet will use: released, the cash stays on
  /// Predictions as available cash.
  void _releaseUnplaced() {
    if (_handedOff) return;
    for (final m in _moves) {
      PredictionFundingLedger.instance.release(m.ref, reason: 'abandoned');
    }
    if (_moves.isNotEmpty) {
      OrderFundingJourney.instance.abandoned(OneBalanceVenue.predictions);
    }
  }

  /// The slip is gone: the approval goes, the moved cash stays.
  void close() {
    if (_closed) return;
    _closed = true;
    cancelHold();
    _again = null;
    if (_handedOff) return;
    _disarm();
    _releaseUnplaced();
  }
}
