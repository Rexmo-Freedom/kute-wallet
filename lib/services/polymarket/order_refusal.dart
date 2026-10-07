// What a placement does after the order book answered "no" to an order.
//
// Only a definitive refusal (PolymarketOrderNotAcceptedException) reaches
// here: the order was not accepted, so a replacement may be signed. Each
// self-heal runs at most once per placement.
//
// The balance refusal ("not enough balance / allowance") used to fall into
// the approvals repair the second time it came back, because it contains
// the word "allowance": the slip said "Setting up your Predictions
// wallet…", re-ran the whole account setup for up to 90 s, and the grant
// often expired meanwhile, so the person saw "Your approval expired" and
// never the refusal. The venue appends what it counted, and that detail
// decides the heal:
//  - "…: the balance is not enough -> balance: …": wrap held USDC.e and ask
//    the venue to re-read the balance, once;
//  - "…: the allowance is not enough -> spender: …, allowance: 0": an
//    approval the venue checks is missing, so the approvals check runs
//    once (bounded), then the cached allowance is re-read once.
//    When the refusal names the spender and it is one of Polymarket's
//    pinned contracts ([polymarketPinnedSpenders]), that one approval is
//    set instead (bounded, once); an address the app does not know is
//    never approved and ends the placement;
//  - "…sum of matched orders: N…" with N above zero while the balance it
//    counted covers the order: the venue still reserves an earlier trade
//    (py-clob-client-v2#112), not a shortage, so the person is told to try
//    again in a moment, never that they lack funds.
// A refusal that comes back after that ends the placement with what the
// venue said.

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/venue_analytics.dart';

enum PolymarketRefusalHeal {
  /// Wrap held USDC.e and ask the venue to re-read the balance, then sign
  /// again. Once per placement.
  refreshBalance,

  /// Re-derive the API key bound to the signer, then sign again.
  rebindKey,

  /// Re-run the account setup (deployment and missing approvals), then
  /// sign again. Only for refusals that name approvals or the maker.
  repairSetup,

  /// Approve the pinned contract the allowance refusal names, then sign
  /// again. Once per placement, never for an unknown address.
  approveSpender,

  /// Nothing more to try: the refusal ends the placement.
  stop,
}

/// Approval and maker refusals that a setup repair can clear: the deposit
/// wallet is missing on chain, or an exchange allowance / operator approval
/// is missing. Never the balance refusal, whatever words it carries.
bool isPolymarketApprovalRefusal(String reason) {
  if (isPolymarketBalanceRefusal(reason)) return false;
  final text = reason.toLowerCase();
  return text.contains('not approved') ||
      text.contains('transfer amount exceeds allowance') ||
      text.contains('maker address');
}

/// Whether the balance refusal's appended detail names a missing
/// allowance ("the allowance is not enough -> spender: …") rather than a
/// short balance.
bool isPolymarketAllowanceShortfall(String reason) =>
    isPolymarketBalanceRefusal(reason) &&
    reason.toLowerCase().contains('allowance is not enough');

/// One approval a refusal heal may set for a pinned contract.
enum PolymarketSpenderApproval {
  /// pUSD `approve(spender, MAX)` (collateral the contract pulls).
  pusd,

  /// CTF `setApprovalForAll(spender, true)` (CTF shares it moves).
  ctfOperator,

  /// PositionManager `setApprovalForAll(spender, true)` (Protocol V2
  /// shares it moves).
  positionOperator,
}

const _pusd = {PolymarketSpenderApproval.pusd};
const _pusdAndCtf = {
  PolymarketSpenderApproval.pusd,
  PolymarketSpenderApproval.ctfOperator,
};

/// Polymarket's pinned contracts an allowance refusal may name: the name
/// analytics records and the approvals that contract takes. Only these
/// are ever approved from a refusal.
const List<(String, String, Set<PolymarketSpenderApproval>)>
    _pinnedSpenderTable = [
  (PolymarketConstants.exchangeAddress, 'exchange', _pusd),
  (
    PolymarketConstants.negRiskExchangeAddress,
    'neg_risk_exchange',
    _pusdAndCtf
  ),
  (
    PolymarketConstants.legacyNegRiskAdapterAddress,
    'neg_risk_adapter',
    _pusdAndCtf
  ),
  (
    PolymarketConstants.ctfCollateralAdapterAddress,
    'ctf_collateral_adapter',
    _pusd
  ),
  (
    PolymarketConstants.negRiskCtfCollateralAdapterAddress,
    'neg_risk_ctf_collateral_adapter',
    _pusd
  ),
  // ExchangeV3 settles every Protocol V2 market (binary and neg-risk) and
  // combos: pUSD for buys, PositionManager shares for sells. The analytics
  // name predates V2 markets and is kept for continuity.
  (
    PolymarketConstants.comboExchangeV3Address,
    'combo_exchange_v3',
    {
      PolymarketSpenderApproval.pusd,
      PolymarketSpenderApproval.positionOperator,
    }
  ),
  (PolymarketConstants.collateralOfframpAddress, 'collateral_offramp', _pusd),
  // The V2 Router burns PositionManager shares on a claim.
  (
    PolymarketConstants.comboRouterAddress,
    'v2_router',
    {PolymarketSpenderApproval.positionOperator}
  ),
  // The V2 market modules, as @polymarket/client approves them: CTF
  // operators only (they move CTF shares into V2), never pUSD.
  (
    PolymarketConstants.v2BinaryModuleAddress,
    'v2_binary_module',
    {PolymarketSpenderApproval.ctfOperator}
  ),
  (
    PolymarketConstants.v2NegRiskModuleAddress,
    'v2_neg_risk_module',
    {PolymarketSpenderApproval.ctfOperator}
  ),
];

/// Pinned contract (lower-case address) → analytics name.
final Map<String, String> polymarketPinnedSpenders = {
  for (final (address, name, _) in _pinnedSpenderTable)
    address.toLowerCase(): name,
};

/// Pinned contract (lower-case address) → the approvals a refusal naming
/// it sets.
final Map<String, Set<PolymarketSpenderApproval>>
    polymarketPinnedSpenderApprovals = {
  for (final (address, _, approvals) in _pinnedSpenderTable)
    address.toLowerCase(): approvals,
};

/// The spender an allowance refusal names ("-> spender: 0x…"), lower
/// case, or null when it names none.
String? polymarketRefusalSpender(String reason) {
  final match = RegExp(r'spender:\s*(0x[0-9a-fA-F]{40})\b').firstMatch(reason);
  return match?.group(1)!.toLowerCase();
}

/// The analytics name of [spender]: a pinned contract's name, else
/// "unknown". Never the address.
String polymarketSpenderName(String? spender) =>
    polymarketPinnedSpenders[spender?.toLowerCase()] ?? 'unknown';

int? _figure(String reason, String label) {
  final match = RegExp('$label:\\s*(\\d+)').firstMatch(reason.toLowerCase());
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// The CLOB's stale reservation (py-clob-client-v2#112): a balance refusal
/// that counts a non-zero "sum of matched orders" while the balance it
/// read covers the order on its own. Earlier matched trades are still
/// reserved against the balance; nothing is short.
bool isPolymarketStaleReservation(String reason) {
  if (!isPolymarketBalanceRefusal(reason)) return false;
  final matched = _figure(reason, 'sum of matched orders');
  final balance = _figure(reason, 'balance');
  final order = _figure(reason, r'order amount(?: \(inc\. fees\))?');
  return matched != null &&
      matched > 0 &&
      balance != null &&
      order != null &&
      balance >= order;
}

/// The next step after a definitive refusal with [reason], given which
/// heals this placement already ran.
PolymarketRefusalHeal polymarketRefusalHeal(
  String reason, {
  required bool balanceRefreshed,
  required bool keyRebound,
  required bool approvalsFixed,
  bool spenderApproved = false,
}) {
  if (isPolymarketBalanceRefusal(reason)) {
    if (isPolymarketAllowanceShortfall(reason)) {
      final spender = polymarketRefusalSpender(reason);
      if (spender != null) {
        // An address the app does not know is never approved.
        if (!polymarketPinnedSpenders.containsKey(spender)) {
          return PolymarketRefusalHeal.stop;
        }
        if (!spenderApproved) return PolymarketRefusalHeal.approveSpender;
      } else if (!approvalsFixed) {
        return PolymarketRefusalHeal.repairSetup;
      }
    }
    return balanceRefreshed
        ? PolymarketRefusalHeal.stop
        : PolymarketRefusalHeal.refreshBalance;
  }
  if (!keyRebound &&
      reason.toLowerCase().contains('signer address has to be the address')) {
    return PolymarketRefusalHeal.rebindKey;
  }
  if (!approvalsFixed && isPolymarketApprovalRefusal(reason)) {
    return PolymarketRefusalHeal.repairSetup;
  }
  return PolymarketRefusalHeal.stop;
}

/// The venue refused the order for balance again after the one refresh.
/// Still a definitive refusal (nothing was accepted, the journal settles
/// it), told apart so the slip names it instead of a generic failure.
class PolymarketBalanceRefused extends PolymarketOrderNotAcceptedException {
  const PolymarketBalanceRefused(super.reason);
}

/// The venue still reserves earlier matched trades against a balance that
/// covers this order ([isPolymarketStaleReservation]), after the one
/// refresh. Nothing is short: the slip says to try again in a moment.
class PolymarketStaleReservation extends PolymarketBalanceRefused {
  const PolymarketStaleReservation(super.reason);
}

/// The venue refused the order and the approval ran out during the
/// repair that followed, before a replacement could be signed. Nothing was
/// placed; [reason] is the refusal that ended it. Never retried: a new
/// order needs a new approval.
class PolymarketRefusalOutlivedApproval
    extends PolymarketOrderNotAcceptedException {
  const PolymarketRefusalOutlivedApproval(super.reason);
}

/// Runs a placement's self-heal loop [body], which reports each venue
/// refusal it handles through `refused`. When the approval expires after
/// a refusal (the repair took longer than the approval lasts), what comes
/// out is that refusal as [PolymarketRefusalOutlivedApproval], so the slip
/// and the failure event name it instead of "Your approval expired". An
/// expiry before any refusal stays [GrantExpired].
Future<void> polymarketSurfaceRefusalOnExpiry(
    Future<void> Function(
            void Function(PolymarketOrderNotAcceptedException refusal) refused)
        body) async {
  PolymarketOrderNotAcceptedException? last;
  try {
    await body((refusal) => last = refusal);
  } on GrantExpired {
    final refusal = last;
    if (refusal == null) rethrow;
    throw PolymarketRefusalOutlivedApproval(refusal.reason);
  }
}

/// The venue's refusal text for analytics: not typed by anyone and never
/// carrying secrets, but it appends figures and addresses ("-> spender:
/// 0x…, allowance: 0, order amount: …"), so the text before that arrow is
/// kept, hex and numbers are taken out, anything but plain text is
/// dropped and the rest is bounded. TrackingService.safeReason scrubs it
/// again on the way out.
String polymarketRefusalForAnalytics(String reason) =>
    VenueAnalytics.refusalText(reason);

/// A closed class for a venue refusal, for dashboards and alerts: the
/// refusal's free text ([polymarketRefusalForAnalytics]) rides beside it.
String polymarketRefusalClass(String reason) {
  final t = reason.toLowerCase();
  if (isPolymarketStaleReservation(reason)) return 'stale_matched_orders';
  if (isPolymarketBalanceRefusal(reason)) {
    return isPolymarketAllowanceShortfall(reason)
        ? 'allowance_not_enough'
        : 'not_enough_balance';
  }
  if (t.contains("couldn't be fully filled") || t.contains('fok order')) {
    return 'fok_not_filled';
  }
  if (t.contains('no orders found to match')) return 'fak_no_match';
  if (t.contains('tick')) return 'invalid_tick';
  if (t.contains('not yet ready') || t.contains('not accepting')) {
    return 'market_not_ready';
  }
  if (t.contains('expiration') || t.contains('expired')) {
    return 'order_expired';
  }
  if (t.contains('post-only') || t.contains('crosses book')) {
    return 'post_only_crosses';
  }
  if (t.contains('invalid order payload')) return 'invalid_payload';
  if (t.contains('api key')) return 'api_key_mismatch';
  if (t.contains('maker address')) return 'maker_not_allowed';
  if (t.contains('not approved') ||
      t.contains('transfer amount exceeds allowance')) {
    return 'not_approved';
  }
  if (t.contains('minimum') ||
      t.contains('min size') ||
      t.contains('too small')) {
    return 'below_minimum';
  }
  if (t.contains('signature')) return 'invalid_signature';
  if (t.contains('canceled in the ctf') || t.contains('cancelled in the ctf')) {
    return 'canceled_on_chain';
  }
  if (t.contains('closed') || t.contains('resolved')) return 'market_closed';
  return 'other';
}

/// The analytics properties for a venue refusal: its class and its text.
/// For an allowance refusal, the spender it names, as a contract name
/// ("neg_risk_adapter", or "unknown"), so a newly required spender shows
/// at once. Never the address.
Map<String, Object> polymarketRefusalParams(String reason) => {
      'refusal_class': polymarketRefusalClass(reason),
      'venue_refusal': polymarketRefusalForAnalytics(reason),
      if (isPolymarketAllowanceShortfall(reason))
        'spender': polymarketSpenderName(polymarketRefusalSpender(reason)),
    };
