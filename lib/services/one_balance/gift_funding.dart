// lib/services/one_balance/gift_funding.dart
//
// PAYING A CLAIMED GIFT, FUNDED LIKE AN ORDER (founder, 8 November 2026:
// "just literally do like normal fills"). A share link pays in Dollars, so
// a person holding Bitcoin or venue cash and no Dollars can still pay it:
// "Send now" brings the shortfall into Dollars with the engine a funded
// order uses, then pays the friend. No separate path: the same decision
// (`decideOrderSources`), the same legs (`BitcoinToDollarsLeg`,
// `VenueCashPuller`), the same grant shape (`BitcoinLegGrants`) and the
// same steps (`MoneyStepsView`).
//
// THE ORDER, FOR A DOLLARS DESTINATION. An order's first source is the
// venue's own cash, already in place. A gift's place is Dollars, so:
//
//   1. Dollars give what they hold (no route, no fee, instant);
//   2. Bitcoin the rest (about a minute); a rest under the route's $1
//      minimum is raised to it and the extra stays in Dollars;
//   3. venue cash ONLY for what those two cannot cover, Predictions before
//      Investing (`planDollarsShortfall`: minutes, slower and dearer).
//
// That is `planOrderSources` with the amount as the move. A venue never
// comes before Bitcoin here: "venue cash first" holds for an order only
// because that cash is already at the venue.
//
// [giftSpendableProvider] is that reach for the slip in send mode: its
// Available, its Max and its over-balance refusal. Nothing moves there.
//
// ONE APPROVAL ([GiftFundingRunner.pay]): everything is decided first and
// nothing moves before the approval. The send intent binds the exact
// destination and amount, and, with a Bitcoin leg, that leg
// (`VenueLimit.fundBtc`: at most N sats to the wallet's own Spark address)
// as a funded order's does. Legs home to Dollars run under the automatic
// authorization, which only Dollars accept. A funded grant lives
// [kGiftFundingGrantTtl] so it survives the legs; it is still single use,
// held in memory only, and consumed only once Dollars hold the amount and
// the session is unlocked.
//
// NEVER TWICE. The link's own row (`PendingShareLink`) is the one record:
// the payment id, written the moment it is known, and the funding
// ([GiftFundingRecord]), written BEFORE any money moves. The leg's `ref` is
// stored before its sats may leave. So at every point of a kill:
//
//   * before the leg went: its settlement never broadcast
//     ([GiftLegState.notSent]), so a new tap plans again;
//   * the leg on its way: it stays running on the row and is followed (a
//     read, nothing moves), counted as on its way, never sent again; a new
//     tap asks a new approval (grants are memory only, D-10) for the payment
//     alone and waits for it;
//   * the leg landed, nothing paid: Dollars cover it, a new tap pays;
//   * paid, `POST /paid` not acknowledged: the next pass retries the report
//     (`ShareLinkClaims._reportUnreported`), never the send.
//
// A leg that fails, or a payment that fails, leaves the money where it is
// (back in Bitcoin, on its venue, or in Dollars) and the link payable: the
// prompt comes back. Later is free: only a leg already sent keeps going.
//
// CONCURRENT PROMPTS never spend the same Dollars: a run holds its amount
// from its first synchronous line ([GiftFundingRunner.reservedUsd]), and a
// link whose legs moved money keeps its hold until it is paid, so another
// prompt plans on what is left. Two Bitcoin legs on one route cannot race
// either: the settlement runner refuses the second while the first is
// unresolved.
//
// Analytics: the funding journey's own events (`order_funding_*`, venue
// `wallet`, entry_source `share_link`), exact amounts, never ids; the leg's
// `convert_success` is `purpose: conversion_leg`, so one movement counts
// once. Revenue is only what the provider confirms on the backend's order
// row. Money reads through `formatDollars`.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart'
    show
        AuthGrant,
        AuthGrantException,
        AuthGrants,
        IntentLimit,
        SensitiveAction,
        SensitiveIntent;
import 'package:kute/helpers/require_fresh_auth.dart'
    show stepUpSessionStateProvider;
import 'package:kute/helpers/venue_intents.dart'
    show BitcoinLegGrants, VenueLimit;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/breez_provider.dart'
    show executeSparkTransactionProvider, prepareSparkTokenPaymentProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceCheckProvider, usdBalanceProvider, usdBalanceReadingProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/usdb_provider.dart' show usdbTokenIdentifier;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown, SettlementStepUpHook;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funding_fees.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart'
    show planOrderSources;
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraCapabilityRequirements;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/runtime_capabilities_service.dart'
    show
        CapabilityDecision,
        CapabilityUnavailableException,
        RuntimeCapabilitiesService,
        runtimeCapabilitiesProvider;
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';

/// How long a funded send's one approval lives: as long as an order's, so
/// it outlives its legs. Still single use, and only ever in memory.
const Duration kGiftFundingGrantTtl = AuthGrants.autofireTtl;

/// A leg older than this no longer counts as on its way: the longest a leg
/// is waited on. Its money, if it lands later, simply shows in Dollars.
const Duration kGiftLegCountsFor = Duration(minutes: 15);

/// A funding record older than this holds no Dollars for its link.
const Duration kGiftHoldFor = Duration(hours: 24);

/// How long one tap waits for the legs before it stops and leaves them
/// going ("Kute will ask again").
const Duration kGiftLandingWait = Duration(minutes: 12);

const String _kBitcoinLegId = 'leg:bitcoin';
const String _kEntrySource = 'share_link';

double _clean(double v) => v.isFinite && v > 0 ? v : 0;

double _floorCents(double usd) =>
    usd.isFinite && usd > 0 ? ((usd * 100) + 1e-6).floor() / 100 : 0;

double _ceilCents(double usd) =>
    usd.isFinite && usd > 0 ? ((usd * 100) - 1e-6).ceil() / 100 : 0;

// ── The plan and the reach ─────────────────────────────────────────────

/// How a gift of some amount would be funded on the figures in hand.
@immutable
class GiftFundingPreview {
  const GiftFundingPreview({
    required this.amountUsd,
    required this.dollarsUsd,
    required this.bitcoinUsd,
    required this.pulls,
    required this.covers,
    required this.fees,
  });

  final double amountUsd;

  /// What Dollars give.
  final double dollarsUsd;

  /// What a Bitcoin leg lands (0: none).
  final double bitcoinUsd;

  /// The venue legs home to Dollars (empty: none).
  final List<VenueCashPull> pulls;

  /// Together they pay the amount.
  final bool covers;

  /// Each leg's fee, an estimate until its quote.
  final OrderFundingFees fees;

  /// Something must move before the friend can be paid.
  bool get needsFunding => bitcoinUsd > 0 || pulls.isNotEmpty;
}

/// How [amountUsd] would be funded: [sources] are what venue legs may draw
/// on, the closed venues already gone. Pure.
GiftFundingPreview planGiftFunding({
  required double amountUsd,
  required double dollarsUsd,
  required double bitcoinMaxUsd,
  required List<VenueCashCandidate> sources,
  double bitcoinSpread = BitcoinLegRules.fallbackSpread,
}) {
  final amount = _clean(amountUsd);
  final held = _clean(dollarsUsd);
  final split = planOrderSources(
    fundUsd: amount,
    dollarsUsd: held,
    bitcoinMaxUsd: _clean(bitcoinMaxUsd),
    otherVenueUsd: venueCashReachUsd(dollarsUsd: 0, sources: sources),
    bitcoinMinimumUsd: BitcoinLegRules.routeMinimumUsd,
  );
  final pulls = split.otherVenueUsd > 0
      ? planDollarsShortfall(
              neededUsd: split.otherVenueUsd, dollarsUsd: 0, sources: sources)
          .pulls
      : const <VenueCashPull>[];
  final legs = <FundingLegFee>[
    if (split.bitcoinUsd > 0)
      () {
        final sent = split.bitcoinUsd / (1 - bitcoinSpread);
        return FundingLegFee(FundingLegSource.bitcoin,
            sentUsd: sent, feeUsd: _ceilCents(sent - split.bitcoinUsd));
      }(),
    for (final p in pulls)
      FundingLegFee(
          p.venue == OneBalanceVenue.predictions
              ? FundingLegSource.predictions
              : FundingLegSource.investing,
          sentUsd: p.usd,
          feeUsd: _ceilCents(p.usd - p.arrivingUsd)),
  ];
  return GiftFundingPreview(
    amountUsd: amount,
    dollarsUsd: split.dollarsUsd,
    bitcoinUsd: split.bitcoinUsd,
    pulls: pulls,
    covers: split.covers,
    fees: OrderFundingFees(List.unmodifiable(legs)),
  );
}

/// The most a gift can be: Dollars, what the Bitcoin lands (a Bitcoin leg
/// under the route's minimum cannot go, so it counts for nothing) and the
/// venue cash net of its moves, to a figure [planGiftFunding] covers. Pure.
double giftReachUsd({
  required double dollarsUsd,
  required double bitcoinMaxUsd,
  required List<VenueCashCandidate> sources,
}) {
  final dollars = _clean(dollarsUsd);
  final bitcoin = _clean(bitcoinMaxUsd);
  final usable =
      bitcoin + 1e-9 >= BitcoinLegRules.routeMinimumUsd ? bitcoin : 0.0;
  final venues = investmentsSpendable(dollarsUsd: 0, sources: sources).maxUsd;
  var max = _floorCents(dollars + usable + venues);
  // The plan has the last word, as for the venues' own Max.
  for (var i = 0; i < 100 && max > dollars; i++) {
    final plan = planGiftFunding(
        amountUsd: max,
        dollarsUsd: dollars,
        bitcoinMaxUsd: usable,
        sources: sources);
    if (plan.covers) break;
    max = _floorCents(max - 0.01);
  }
  return max < dollars ? _floorCents(dollars) : max;
}

/// The capability a Bitcoin → Dollars leg is refused by under [policy], or
/// null while the route is open (backend policy alone decides).
CapabilityDecision? bitcoinToDollarsDenied(RuntimeCapabilitiesService policy) {
  for (final id in orchestraCapabilityRequirements(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: kOrchestraUsdChain,
      destinationAsset: kOrchestraUsdAssetCode,
      policy: policy)) {
    final decision = policy.decision(id);
    if (!decision.allowed || decision.comingSoon) return decision;
  }
  return null;
}

/// The venue cash a gift may reach right now, closed venues gone: the
/// engine's last read for the spending wallet, else the one-balance seed.
final _giftVenueSourcesProvider =
    Provider.autoDispose<List<VenueCashCandidate>>((ref) {
  final walletId =
      ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
  final last = ref.watch(venueCashLastReadProvider);
  final sources = last != null && last.walletId == walletId
      ? last.candidates
      : ref.watch(venueCashSeedProvider);
  final closed = ref.watch(venueCashClosedProvider);
  return [
    for (final s in sources)
      if (!closed.contains(s.venue)) s,
  ];
});

/// What the slip in send mode measures an amount against, from the last
/// known values, synchronous, never loading. Null while Dollars are not
/// known yet: an unloaded balance is never taken for no money.
final giftSpendableProvider = Provider.autoDispose<double?>((ref) {
  final dollars = ref.watch(usdBalanceReadingProvider);
  if (dollars == null) return null;
  final denied =
      bitcoinToDollarsDenied(ref.watch(runtimeCapabilitiesProvider)) != null;
  final bitcoin = denied ? 0.0 : ref.watch(spendingBitcoinLandingUsdProvider);
  return giftReachUsd(
      dollarsUsd: dollars,
      bitcoinMaxUsd: bitcoin,
      sources: ref.watch(_giftVenueSourcesProvider));
});

/// How [amountUsd] would be funded on the figures the app holds: for the
/// prompt's lines and fee, before any tap. Reads nothing new. [heldUsd] is
/// what other links' runs hold.
GiftFundingPreview giftFundingPreviewNow(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double amountUsd,
  double heldUsd = 0,
  double? bitcoinSpread,
  double pendingUsd = 0,
}) {
  final policy = read(runtimeCapabilitiesProvider);
  final closed = read(venueCashClosedProvider);
  return planGiftFunding(
    amountUsd: math.max(0, amountUsd - pendingUsd),
    dollarsUsd: math.max(0, read(usdBalanceProvider) - heldUsd),
    bitcoinMaxUsd: bitcoinToDollarsDenied(policy) != null
        ? 0
        : read(spendingBitcoinLandingUsdProvider),
    sources: [
      for (final s in venueCashCandidatesNow(read))
        if (!closed.contains(s.venue)) s,
    ],
    bitcoinSpread: bitcoinSpread ?? BitcoinLegRules.fallbackSpread,
  );
}

// ── What can go wrong ──────────────────────────────────────────────────

/// Nothing moved: the sources cannot pay it. The link stays payable.
class GiftFundingRefused implements Exception {
  const GiftFundingRefused(this.category, {this.denied});

  /// A fixed analytics category.
  final String category;

  /// The policy decision that kept Bitcoin out, for its own words.
  final CapabilityDecision? denied;

  @override
  String toString() => 'GiftFundingRefused($category)';
}

/// The funding stopped before the payment: whatever went keeps going, the
/// rest stayed where it was, nothing was paid.
class GiftFundingStopped implements Exception {
  const GiftFundingStopped(this.category, {this.cause});

  /// A fixed analytics category (a leg's reason, `timeout`, `approval`).
  final String category;

  /// What the leg threw, for the settlement copy.
  final Object? cause;

  @override
  String toString() => 'GiftFundingStopped($category)';
}

// ── The environment ────────────────────────────────────────────────────

/// Where a leg a previous attempt recorded stands.
enum GiftLegState {
  /// Still on its way, or nothing is known yet.
  onItsWay,
  delivered,

  /// Orchestra failed or refunded it: its money goes back.
  failed,

  /// It never left: its settlement never reached broadcasting.
  notSent,
}

/// The wallet as the runner reads and moves it, as functions so tests can
/// stand in for the SDK, Orchestra and the clock.
class GiftFundingEnv {
  const GiftFundingEnv({
    required this.walletId,
    required this.dollarsNow,
    required this.freshDollars,
    required this.bitcoinDenied,
    required this.venueSources,
    required this.decide,
    required this.ownSpark,
    required this.sendBitcoin,
    required this.pullVenue,
    required this.legState,
    required this.payDollars,
    required this.sessionUnlocked,
    this.nudge,
    this.dollarsKnown,
    this.venueLanded,
    this.sleep = _realSleep,
    this.clock = DateTime.now,
    this.pollEvery = const Duration(seconds: 1),
    this.landingWait = kGiftLandingWait,
  });

  /// The spending wallet, the one every leg and the payment run on.
  final String Function() walletId;
  final double Function() dollarsNow;
  final Future<double?> Function() freshDollars;

  /// The decision refusing a Bitcoin → Dollars leg, asked fresh of the
  /// backend's policy; null while it is open.
  final Future<CapabilityDecision?> Function() bitcoinDenied;

  /// The venues' free cash, read fresh, closed venues gone.
  final Future<List<VenueCashCandidate>> Function() venueSources;

  /// The funded order's decision ([decideOrderSources]).
  final Future<OrderSources> Function({
    required double fundUsd,
    required double dollarsUsd,
    required double otherVenueUsd,
    required bool investmentsCover,
  }) decide;

  /// The wallet's own Spark address, or null.
  final Future<String?> Function() ownSpark;

  /// The Bitcoin → Dollars leg ([sendBitcoinLegToDollars]).
  final BitcoinLegSend sendBitcoin;

  /// Venue legs home to Dollars, exactly [plan] ([VenueCashPuller]).
  final Future<VenueCashPullOutcome> Function(
    VenueCashPlan plan, {
    required void Function(String moveId) onStarted,
    required void Function(VenueCashLegOutcome leg) onLeg,
  }) pullVenue;

  /// Where the leg known as [ref] stands (a read).
  final Future<GiftLegState> Function(String ref) legState;

  /// Pays USDB [amount] to [destination]; the Spark payment id.
  final Future<String> Function(String destination, BigInt amount) payDollars;
  final bool Function() sessionUnlocked;

  /// Asks the Dollars reading to catch up (never awaited).
  final void Function()? nudge;

  /// Whether the Dollars figure is a reading, not a balance still loading.
  /// Null: it is.
  final bool Function()? dollarsKnown;

  /// Venue legs landed: the engine stops counting them as on their way.
  final void Function()? venueLanded;
  final Future<void> Function(Duration) sleep;
  final DateTime Function() clock;
  final Duration pollEvery;
  final Duration landingWait;

  factory GiftFundingEnv.live(Ref ref) {
    final legEnv = BitcoinLegEnv.live(ref);
    return GiftFundingEnv(
      walletId: () => HotSettlement.spendingWalletId(ref.read),
      dollarsNow: legEnv.dollarsNow,
      freshDollars: legEnv.freshDollars,
      bitcoinDenied: () async {
        final policy = ref.read(runtimeCapabilitiesProvider);
        try {
          await policy.ensureAllAllowed(orchestraCapabilityRequirements(
              sourceChain: 'spark',
              sourceAsset: 'BTC',
              destinationChain: kOrchestraUsdChain,
              destinationAsset: kOrchestraUsdAssetCode,
              policy: policy));
          return null;
        } on CapabilityUnavailableException catch (e) {
          return e.decision;
        } catch (_) {
          // Unknown: the leg's own quote gate asks again before any sats.
          return null;
        }
      },
      venueSources: () => ref
          .read(venueCashPullerProvider)
          .candidates(closed: ref.read(venueCashClosedProvider)),
      decide: ({
        required double fundUsd,
        required double dollarsUsd,
        required double otherVenueUsd,
        required bool investmentsCover,
      }) =>
          decideOrderSources(ref.read,
              fundUsd: fundUsd,
              dollarsUsd: dollarsUsd,
              otherVenueUsd: otherVenueUsd,
              investmentsCover: investmentsCover),
      ownSpark: () => ownSparkForBitcoinLeg(ref.read),
      sendBitcoin: ({
        required String sparkAddress,
        required BitcoinLegPlan plan,
        required SettlementStepUpHook stepUp,
        required void Function() onSending,
      }) =>
          sendBitcoinLegToDollars(ref.read,
              sparkAddress: sparkAddress,
              plan: plan,
              stepUp: stepUp,
              onSending: onSending,
              flow: 'share_link_funding_bitcoin',
              purpose: 'conversion_leg'),
      pullVenue: (plan, {required onStarted, required onLeg}) =>
          ref.read(venueCashPullerProvider).pullShortfall(
              neededUsd: plan.neededUsd,
              forAction: VenueCashFor.shareLink,
              plan: plan,
              // The runner waits on the Dollars itself.
              waitFor: Duration.zero,
              onStarted: onStarted,
              onLeg: onLeg),
      legState: _liveLegState,
      payDollars: (destination, amount) async {
        final prepared = await ref.read(prepareSparkTokenPaymentProvider((
          destination: destination,
          amountBaseUnits: amount,
          tokenIdentifier: usdbTokenIdentifier,
        )).future);
        final response =
            await ref.read(executeSparkTransactionProvider(prepared).future);
        return response.payment.id;
      },
      sessionUnlocked: () =>
          ref.read(stepUpSessionStateProvider).isSessionUnlocked,
      nudge: () => ref.read(usdBalanceCheckProvider).request('gift_leg'),
      dollarsKnown: () => ref.read(usdBalanceReadingProvider) != null,
      venueLanded: () =>
          unawaited(ref.read(venueCashPullerProvider).waitForDollars(0)),
    );
  }
}

Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

/// The leg [ref] by Orchestra's status, then by the settlement's own record:
/// one that never reached `broadcasting` paid nothing (the store flushes
/// that stage before any funds move).
Future<GiftLegState> _liveLegState(String ref) async {
  final status = await orchestraLegStatus(ref);
  if (status != null) {
    if (kOrchestraDeliveredStatuses.contains(status)) {
      return GiftLegState.delivered;
    }
    if (kOrchestraFailedStatuses.contains(status)) return GiftLegState.failed;
    return GiftLegState.onItsWay;
  }
  try {
    final store = await SettlementStore.shared();
    for (final SettlementOperation op in await store.all()) {
      if (op.orderId != ref && op.quote?.quoteId != ref) continue;
      if (!op.everBroadcast || op.stage == SettlementStage.abandoned) {
        return GiftLegState.notSent;
      }
      return GiftLegState.onItsWay;
    }
  } catch (_) {/* unknown: still on its way */}
  return GiftLegState.onItsWay;
}

// ── The runner ─────────────────────────────────────────────────────────

/// What asks the one approval: the grant it answers is bound to [intent].
/// Null: declined, nothing moves.
typedef GiftApprove = Future<AuthGrant?> Function(SensitiveIntent intent);

final giftFundingRunnerProvider = Provider<GiftFundingRunner>(
    (ref) => GiftFundingRunner(GiftFundingEnv.live(ref)));

class GiftFundingRunner {
  GiftFundingRunner(this._env);

  final GiftFundingEnv _env;

  /// Every run on now, by link: a sheet reopened finds it.
  static final Map<String, Future<String?>> _runs = {};

  /// What each run on now holds of Dollars, from its first line.
  static final Map<String, double> _holds = {};

  /// Bitcoin legs dispatching in this process: their settlement is ours,
  /// mid-flight, not a leftover to read.
  static final Set<String> _dispatching = {};
  static final Set<String> _following = {};

  @visibleForTesting
  static void debugReset() {
    _runs.clear();
    _holds.clear();
    _dispatching.clear();
    _following.clear();
  }

  /// Whether a run is on for link [id].
  static bool isRunning(String id) => _runs.containsKey(id);

  /// What other links hold of Dollars: their runs on now, and any link
  /// whose legs moved money for it and is not yet paid.
  static double reservedUsd({required String except, required DateTime now}) {
    var held = 0.0;
    // Runs started earlier hold ahead of this one (a later one must fund
    // itself): the first prompt is the one its Dollars pay.
    for (final e in _holds.entries) {
      if (e.key == except) break;
      held += e.value;
    }
    for (final row in ShareLinksStore.all()) {
      if (row.id == except || _holds.containsKey(row.id)) continue;
      if (row.paymentId != null || row.funding == null) continue;
      if (row.kind != ShareLinkKind.dollars) continue;
      if (row.status != ShareLinkStatus.claimed) continue;
      if (now.difference(row.funding!.startedAt) > kGiftHoldFor) continue;
      if (row.funding!.steps.legs.any((s) =>
          s.id != kGiftFundingSendId &&
          (s.status == MoneyStepStatus.done ||
              s.status == MoneyStepStatus.running))) {
        held += row.amountMinor / 100;
      }
    }
    return held;
  }

  /// Pays [claim] (a dollars link), funding what Dollars lack under
  /// [approve]'s one approval. The payment id, or null when declined.
  /// Throws [GiftFundingRefused] or [GiftFundingStopped] with nothing paid,
  /// or whatever the payment threw.
  Future<String?> pay(ClaimedShareLink claim, {required GiftApprove approve}) {
    final running = _runs[claim.id];
    if (running != null) return running;
    // The hold is set before the first await: a prompt on top sees it.
    _holds[claim.id] = claim.amountMinor / 100;
    final run = _pay(claim, approve);
    _runs[claim.id] = run;
    void end() {
      _runs.remove(claim.id);
      _holds.remove(claim.id);
    }

    run.then((_) => end(), onError: (_) => end());
    return run;
  }

  Future<String?> _pay(ClaimedShareLink claim, GiftApprove approve) async {
    final existing = ShareLinksStore.byId(claim.id);
    if (existing?.paymentId case final paid?) return paid;
    final amountUsd = claim.amountMinor / 100;

    // Legs an earlier attempt left: where they stand now.
    await followOnce(claim.id);
    final record = ShareLinksStore.byId(claim.id)?.funding;
    final pending = _pendingUsd(record);
    final decision = await _decide(claim, amountUsd, pending);

    final destination = claim.claimDestination.trim();
    final amount = dollarsBaseUnitsFromCents(claim.amountMinor);
    final funded = decision.needsLegs || pending > 0;
    String? ownSpark;
    if (decision.bitcoin != null) {
      ownSpark = await _env.ownSpark();
      if (ownSpark == null) {
        _failedBeforeMoving(amountUsd, 'plan', 'no_route');
        throw const GiftFundingRefused('no_route');
      }
    }
    final intent = SensitiveIntent(
      action: SensitiveAction.send,
      walletId: _env.walletId(),
      venue: 'spark',
      destination: destination,
      asset: claim.kind.asset,
      amountMax: amount,
      limits: {
        IntentLimit.provider: 'share_link',
        IntentLimit.maxMode: false,
        'sourcePool': 'usd',
        if (decision.bitcoin case final leg?)
          VenueLimit.fundBtc:
              BitcoinLegGrants.limit(maxSats: leg.maxSats, ownSpark: ownSpark!),
      },
      ttl: funded ? kGiftFundingGrantTtl : AuthGrants.defaultTtl,
    );
    final grant = await approve(intent);
    if (grant == null) return null;

    if (!funded) {
      // Dollars hold it: exactly the plain send.
      try {
        AuthGrants.consume(grant, intent);
      } on AuthGrantException {
        return null;
      }
      // (An earlier attempt's leg may have brought them: its steps close.)
      _updateSteps(claim.id, (g) => _sendState(g, MoneyStepStatus.running));
      try {
        final paymentId = await _env.payDollars(destination, amount);
        _updateSteps(claim.id, (g) => _sendState(g, MoneyStepStatus.done));
        _recordPaid(claim, paymentId, fees: OrderFundingFees.none);
        return paymentId;
      } catch (_) {
        _updateSteps(claim.id, (g) => _sendState(g, MoneyStepStatus.failed));
        rethrow;
      }
    }

    final started = _env.clock();
    final fees = decision.fees;
    TrackingService.track('order_funding_started',
        params: _params(amountUsd, {
          'order_usd': amountUsd,
          'fund_usd': _cents(amountUsd - decision.dollarsUsd),
          'ready_usd': _cents(decision.dollarsUsd),
          'dollars_usd': _cents(decision.dollarsUsd),
          'entry_source': _kEntrySource,
          'wallet_kind': 'hot',
          'funding_source': decision.source,
          'other_venue_used': decision.venuePlan != null,
          if (pending > 0) 'resumed': true,
          ...fundingFeeAnalytics(fees),
        }));

    final prior = _landedAndGoing(record);
    final graph = _graph(prior, decision, amountUsd);
    final lands = <String, double>{
      if (record != null)
        for (final s in prior)
          if (record.landsUsd[s.id] case final usd?) s.id: usd,
      if (decision.bitcoin != null) _freshBitcoinId(prior): decision.bitcoinUsd,
      if (decision.venuePlan case final plan?)
        for (final p in plan.pulls) MoveSteps.legId(p.venue): p.arrivingUsd,
    };
    // On the row BEFORE any money moves.
    ShareLinksStore.setFunding(
      claim,
      GiftFundingRecord(
          steps: graph,
          startedAt: record?.startedAt ?? _env.clock(),
          landsUsd: lands,
          moveId: record?.moveId),
    );

    try {
      await Future.wait([
        if (decision.bitcoin case final leg?)
          _runBitcoinLeg(claim, leg, grant, ownSpark!, _freshBitcoinId(prior)),
        if (decision.venuePlan case final plan?) _runVenueLegs(claim, plan),
      ]);
      if (decision.needsLegs) {
        TrackingService.track('order_funding_step',
            params: _params(amountUsd,
                {'step': decision.bitcoin != null ? 'bitcoin' : 'fund'}));
        TrackingService.track('order_funding_submitted',
            params: _params(amountUsd, {
              'fund_usd': _cents(amountUsd - decision.dollarsUsd),
              'funding_source': decision.source,
            }));
      }
      final landing = await _land(claim.id, amountUsd);
      if (landing != null) throw GiftFundingStopped(landing);
      if (decision.venuePlan != null) _env.venueLanded?.call();
      TrackingService.track('order_funding_step',
          params: _params(amountUsd, {'step': 'credit'}));
      if (!_env.sessionUnlocked()) {
        throw const GiftFundingStopped('session_locked');
      }
      try {
        AuthGrants.consume(grant, intent);
      } on AuthGrantException {
        throw const GiftFundingStopped('approval');
      }
    } on GiftFundingStopped catch (e) {
      grant.revoke();
      _stop(claim.id, e.category);
      TrackingService.track('order_funding_failed',
          params: _params(amountUsd, {
            'stage': 'funding',
            'error_category': TrackingService.errorCategory(e.category),
            'duration_ms': _env.clock().difference(started).inMilliseconds,
            'funding_source': decision.source,
          }));
      rethrow;
    }

    _updateSteps(claim.id, (g) => _sendState(g, MoneyStepStatus.running));
    try {
      final paymentId = await _env.payDollars(destination, amount);
      _updateSteps(claim.id, (g) => _sendState(g, MoneyStepStatus.done));
      _recordPaid(claim, paymentId, fees: fees);
      TrackingService.track('order_funding_completed',
          params: _params(amountUsd, {
            'fund_usd': _cents(amountUsd - decision.dollarsUsd),
            'duration_ms': _env.clock().difference(started).inMilliseconds,
            'funding_source': decision.source,
            ...fundingFeeAnalytics(fees),
          }));
      return paymentId;
    } catch (e) {
      // The money stays in Dollars; a new tap pays it with no second leg.
      _updateSteps(claim.id, (g) => _sendState(g, MoneyStepStatus.failed));
      _stop(claim.id, 'payment');
      TrackingService.track('order_funding_failed',
          params: _params(amountUsd, {
            'stage': 'payment',
            'error_category': TrackingService.errorCategory(e),
            'duration_ms': _env.clock().difference(started).inMilliseconds,
            'funding_source': decision.source,
          }));
      rethrow;
    }
  }

  void _recordPaid(ClaimedShareLink claim, String paymentId,
      {required OrderFundingFees fees}) {
    final funded = !fees.isEmpty ||
        (ShareLinksStore.byId(claim.id)
                ?.funding
                ?.steps
                .legs
                .any((s) => s.id != kGiftFundingSendId) ??
            false);
    if (ShareLinksStore.recordPaid(claim, paymentId)) {
      ShareLinkEvents.paid(claim.kind, claim.amountMinor,
          funded: funded, fees: fees);
    }
  }

  /// What funds it, with no money moved. Throws [GiftFundingRefused].
  Future<_GiftDecision> _decide(
      ClaimedShareLink claim, double amountUsd, double pending) async {
    final now = _env.clock();
    final fresh = await _env.freshDollars();
    // A balance still loading is never taken for no money: that would swap
    // bitcoin the person did not need to.
    if (fresh == null && !(_env.dollarsKnown?.call() ?? true)) {
      _failedBeforeMoving(amountUsd, 'plan', 'balance_unknown');
      throw const GiftFundingRefused('balance_unknown');
    }
    final held = reservedUsd(except: claim.id, now: now);
    final dollars = _clean((fresh ?? _env.dollarsNow()) - held);
    if (dollars + pending + 1e-6 >= amountUsd) {
      return _GiftDecision.none(math.min(dollars, amountUsd));
    }
    final fund = _ceilCents(amountUsd - pending);
    final sources = await _safeSources();
    final venues = venueCashReachUsd(dollarsUsd: 0, sources: sources);
    final denied = await _env.bitcoinDenied();
    final OrderSources decided;
    if (denied != null) {
      // Swap refused for this person: the venues are their own exits and
      // answer to their own capabilities; Bitcoin alone is out.
      if (dollars + venues + 1e-9 < fund) {
        _failedBeforeMoving(amountUsd, 'plan', 'capability');
        throw GiftFundingRefused('capability', denied: denied);
      }
      decided = OrderSources(OrderSourceRoute.otherVenue,
          otherVenueUsd: _ceilCents(fund - dollars));
    } else {
      decided = await _env.decide(
        fundUsd: fund,
        dollarsUsd: dollars,
        otherVenueUsd: venues,
        investmentsCover: dollars + venues + 1e-9 >= fund,
      );
    }
    switch (decided.route) {
      case OrderSourceRoute.dollars:
        return _GiftDecision.none(math.min(dollars, amountUsd));
      case OrderSourceRoute.bitcoin:
      case OrderSourceRoute.otherVenue:
        break;
      case OrderSourceRoute.insufficient:
      case OrderSourceRoute.addChanged:
        _failedBeforeMoving(amountUsd, 'plan', 'insufficient_funds');
        throw const GiftFundingRefused('insufficient_funds');
      case OrderSourceRoute.unavailable:
        _failedBeforeMoving(amountUsd, 'plan', 'no_route');
        throw const GiftFundingRefused('no_route');
    }
    VenueCashPlan? venuePlan;
    if (decided.otherVenueUsd > 0) {
      // Only what comes home: that is the move's own row in Activity.
      venuePlan = planDollarsShortfall(
          neededUsd: decided.otherVenueUsd, dollarsUsd: 0, sources: sources);
      if (!venuePlan.covers || venuePlan.pulls.isEmpty) {
        _failedBeforeMoving(amountUsd, 'plan', 'insufficient_funds');
        throw const GiftFundingRefused('insufficient_funds');
      }
    }
    final legs = <FundingLegFee>[
      if (decided.plan case final leg?)
        () {
          final worth = leg.sats / 1e8 * leg.usdPerBtc;
          final fee = worth > leg.targetUsd ? worth - leg.targetUsd : 0.0;
          return FundingLegFee(FundingLegSource.bitcoin,
              sentUsd: worth, feeUsd: _ceilCents(fee));
        }(),
      if (venuePlan case final plan?)
        for (final p in plan.pulls)
          FundingLegFee(
              p.venue == OneBalanceVenue.predictions
                  ? FundingLegSource.predictions
                  : FundingLegSource.investing,
              sentUsd: p.usd,
              feeUsd: _ceilCents(p.usd - p.arrivingUsd)),
    ];
    return _GiftDecision(
      dollarsUsd: math.min(dollars, amountUsd),
      bitcoin: decided.route == OrderSourceRoute.bitcoin ? decided.plan : null,
      bitcoinUsd: decided.bitcoinUsd,
      venuePlan: venuePlan,
      fees: OrderFundingFees(List.unmodifiable(legs)),
    );
  }

  Future<List<VenueCashCandidate>> _safeSources() async {
    try {
      return await _env.venueSources().timeout(const Duration(seconds: 8));
    } catch (_) {
      return const [];
    }
  }

  void _failedBeforeMoving(double amountUsd, String stage, String category) {
    TrackingService.track('order_funding_failed',
        params: _params(amountUsd, {
          'stage': stage,
          'error_category': TrackingService.errorCategory(category),
        }));
  }

  // ── The legs ─────────────────────────────────────────────────────────

  Future<void> _runBitcoinLeg(ClaimedShareLink claim, BitcoinLegPlan leg,
      AuthGrant grant, String ownSpark, String stepId) async {
    final key = '${claim.id}|$stepId';
    _dispatching.add(key);
    final guard = BitcoinLegGrants.stepUp(grant, ownSpark: ownSpark);
    try {
      final ticket = await _env.sendBitcoin(
        sparkAddress: ownSpark,
        plan: leg,
        stepUp: (settlement) async {
          // Its name goes on the row before the sats may leave: a kill from
          // here on is followed, never paid again.
          final quote = settlement.reviewedQuote;
          if (quote != null) {
            _updateStep(
                claim.id, stepId, (s) => s.copyWith(ref: quote.quoteId));
          }
          return guard(settlement);
        },
        onSending: () {},
      );
      // The sats left.
      _updateStep(
          claim.id,
          stepId,
          (s) => s.copyWith(
              status: MoneyStepStatus.running,
              ref: ticket.orderId ?? ticket.quoteId));
      unawaited(ticket.registration?.then((orderId) {
        if (orderId == null) return;
        _updateStep(claim.id, stepId, (s) => s.copyWith(ref: orderId));
      }, onError: (_) {}));
      _env.nudge?.call();
    } on SettlementFundingUnknown catch (e) {
      // It may have left: it stays on its way, and nothing sends it again.
      _updateStep(claim.id, stepId, (s) => s.copyWith(reason: 'maybe_sent'));
      throw GiftFundingStopped('settlement', cause: e);
    } catch (e) {
      _updateStep(
          claim.id,
          stepId,
          (s) => s.copyWith(
              status: MoneyStepStatus.failed,
              reason: 'not_sent',
              endedAt: _env.clock()));
      throw GiftFundingStopped(TrackingService.errorCategory(e), cause: e);
    } finally {
      _dispatching.remove(key);
    }
  }

  Future<void> _runVenueLegs(ClaimedShareLink claim, VenueCashPlan plan) async {
    Object? failed;
    final VenueCashPullOutcome outcome;
    try {
      outcome = await _env.pullVenue(
        plan,
        onStarted: (moveId) => ShareLinksStore.updateFunding(
            claim.id, (r) => r.copyWith(moveId: moveId)),
        onLeg: (leg) {
          final id = MoveSteps.legId(leg.venue);
          if (leg.ok) {
            final result = leg.result!;
            _updateStep(
                claim.id,
                id,
                (s) => s.copyWith(
                    ref: result.orderId ?? result.quoteId,
                    status: MoneyStepStatus.running));
          } else {
            failed ??= leg.error ?? 'not_sent';
            _updateStep(
                claim.id,
                id,
                (s) => s.copyWith(
                    status: MoneyStepStatus.failed,
                    reason: 'not_sent',
                    endedAt: _env.clock()));
          }
        },
      );
    } catch (e) {
      // It refused before its legs answered: the ones with no answer never
      // went.
      _updateSteps(
          claim.id,
          (g) => MoneyStepGraph([
                for (final s in g.steps)
                  s.from != MoneyPlace.bitcoin &&
                          s.id != kGiftFundingSendId &&
                          s.status == MoneyStepStatus.running &&
                          s.ref == null
                      ? s.copyWith(
                          status: MoneyStepStatus.failed,
                          reason: 'not_sent',
                          endedAt: _env.clock())
                      : s,
              ]));
      throw GiftFundingStopped(TrackingService.errorCategory(e), cause: e);
    }
    if (failed != null || outcome.failedLegs.isNotEmpty) {
      throw GiftFundingStopped('venue_leg', cause: failed);
    }
  }

  /// Waits for Dollars to hold [amountUsd] on top of what others hold. Null
  /// when they do; else the fixed reason it stopped. Moves nothing.
  Future<String?> _land(String id, double amountUsd) async {
    final start = _env.clock();
    while (true) {
      final failed = await followOnce(id);
      final need = amountUsd + reservedUsd(except: id, now: _env.clock());
      final fresh = await _env.freshDollars();
      final dollars = math.max(fresh ?? 0, _env.dollarsNow());
      if (dollars + 1e-6 >= need) {
        _updateSteps(id, (g) => _allLanded(g, _env.clock()));
        return null;
      }
      if (failed) return 'leg_failed';
      final record = ShareLinksStore.byId(id)?.funding;
      if (record == null) return 'short';
      // A leg delivered a moment ago: the wallet's own reading catches up.
      final now = _env.clock();
      final justLanded = record.steps.legs.any((s) =>
          s.id != kGiftFundingSendId &&
          s.status == MoneyStepStatus.done &&
          s.endedAt != null &&
          now.difference(s.endedAt!) < const Duration(seconds: 60));
      if (!record.onItsWay && !justLanded) return 'short';
      if (_env.clock().difference(start) >= _env.landingWait) return 'timeout';
      _env.nudge?.call();
      await _env.sleep(_env.pollEvery);
    }
  }

  /// One read of every leg link [id] shows as running; true when one of
  /// them ended badly. A read only: nothing moves. Never throws.
  Future<bool> followOnce(String id) async {
    final record = ShareLinksStore.byId(id)?.funding;
    if (record == null) return false;
    var failed = false;
    for (final s in record.steps.legs.toList()) {
      if (s.id == kGiftFundingSendId) continue;
      if (s.status != MoneyStepStatus.running) continue;
      if (_dispatching.contains('$id|${s.id}')) continue;
      final ref = s.ref;
      if (ref == null) {
        // A Bitcoin leg names its quote before its sats may leave: one with
        // no name and no live dispatch never paid anything.
        if (s.from == MoneyPlace.bitcoin) {
          _updateStep(
              id,
              s.id,
              (x) => x.copyWith(
                  status: MoneyStepStatus.failed,
                  reason: 'not_sent',
                  endedAt: _env.clock()));
        }
        continue;
      }
      GiftLegState state;
      try {
        state = await _env.legState(ref);
      } catch (_) {
        state = GiftLegState.onItsWay;
      }
      switch (state) {
        case GiftLegState.onItsWay:
          break;
        case GiftLegState.delivered:
          _updateStep(
              id,
              s.id,
              (x) => x.copyWith(
                  status: MoneyStepStatus.done, endedAt: _env.clock()));
          _env.nudge?.call();
        case GiftLegState.failed:
        case GiftLegState.notSent:
          failed = true;
          _updateStep(
              id,
              s.id,
              (x) => x.copyWith(
                  status: MoneyStepStatus.failed,
                  reason:
                      state == GiftLegState.notSent ? 'not_sent' : 'refunded',
                  endedAt: _env.clock()));
      }
    }
    return failed;
  }

  /// Follows link [id]'s legs while they run, for a sheet open after a
  /// restart. A read only. One per link.
  Future<void> resume(String id) async {
    if (!_following.add(id) || isRunning(id)) {
      _following.remove(id);
      return;
    }
    try {
      final start = _env.clock();
      while (_env.clock().difference(start) < kGiftLegCountsFor) {
        await followOnce(id);
        final record = ShareLinksStore.byId(id)?.funding;
        if (record == null || !record.onItsWay || isRunning(id)) return;
        final dollars = _env.dollarsNow();
        final amount = (ShareLinksStore.byId(id)?.amountMinor ?? 0) / 100;
        if (amount > 0 && dollars + 1e-6 >= amount) {
          _updateSteps(id, (g) => _allLanded(g, _env.clock()));
          return;
        }
        await _env.sleep(const Duration(seconds: 5));
      }
    } finally {
      _following.remove(id);
    }
  }

  // ── The record ───────────────────────────────────────────────────────

  /// What legs on the row still bring (never one past [kGiftLegCountsFor]).
  double _pendingUsd(GiftFundingRecord? record) {
    if (record == null) return 0;
    final now = _env.clock();
    var sum = 0.0;
    for (final s in record.steps.legs) {
      if (s.id == kGiftFundingSendId) continue;
      if (s.status != MoneyStepStatus.running) continue;
      final from = s.startedAt ?? record.startedAt;
      if (now.difference(from) > kGiftLegCountsFor) continue;
      sum += record.landsUsd[s.id] ?? s.usd;
    }
    return sum;
  }

  /// The legs an earlier attempt moved (kept on the screen and on the row).
  List<MoneyStep> _landedAndGoing(GiftFundingRecord? record) => [
        if (record != null)
          for (final s in record.steps.legs)
            if (s.id != kGiftFundingSendId &&
                (s.status == MoneyStepStatus.done ||
                    s.status == MoneyStepStatus.running))
              s,
      ];

  String _freshBitcoinId(List<MoneyStep> prior) {
    var id = _kBitcoinLegId;
    var n = 2;
    final used = {for (final s in prior) s.id};
    while (used.contains(id)) {
      id = '$_kBitcoinLegId$n';
      n++;
    }
    return id;
  }

  MoneyStepGraph _graph(
      List<MoneyStep> prior, _GiftDecision decision, double amountUsd) {
    final now = _env.clock();
    final steps = <MoneyStep>[
      ...prior,
      if (decision.bitcoin != null)
        MoneyStep(
          id: _freshBitcoinId(prior),
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          to: MoneyPlace.dollars,
          usd: _cents(decision.bitcoinUsd),
          route: MoneyRoute.viaDollars,
          status: MoneyStepStatus.running,
          startedAt: now,
        ),
      if (decision.venuePlan case final plan?)
        for (final p in plan.pulls)
          if (!prior.any((s) => s.id == MoveSteps.legId(p.venue)))
            MoneyStep(
              id: MoveSteps.legId(p.venue),
              kind: MoneyStepKind.leg,
              from: MoveSteps.placeOf(p.venue),
              to: MoneyPlace.dollars,
              usd: _cents(p.usd),
              route: MoneyRoute.viaDollars,
              status: MoneyStepStatus.running,
              startedAt: now,
            ),
    ];
    final after = [for (final s in steps) s.id];
    return MoneyStepGraph([
      ...steps,
      MoveSteps.finalStep(
              MoveSteps.sendId, VenueCashDestination.dollars, amountUsd)
          .copyWith(after: after),
    ]);
  }

  MoneyStepGraph _sendState(MoneyStepGraph g, MoneyStepStatus status) =>
      MoneyStepGraph([
        for (final s in g.steps)
          s.id == kGiftFundingSendId
              ? s.copyWith(
                  status: status,
                  startedAt: status == MoneyStepStatus.running
                      ? _env.clock()
                      : s.startedAt,
                  endedAt: status.ended ? _env.clock() : null,
                  clearEnd: !status.ended)
              : s,
      ]);

  MoneyStepGraph _allLanded(MoneyStepGraph g, DateTime at) => MoneyStepGraph([
        for (final s in g.steps)
          s.id != kGiftFundingSendId && s.status == MoneyStepStatus.running
              ? s.copyWith(status: MoneyStepStatus.done, endedAt: at)
              : s,
      ]);

  void _stop(String id, String reason) =>
      ShareLinksStore.updateFunding(id, (r) => r.copyWith(reason: reason));

  void _updateSteps(
          String id, MoneyStepGraph Function(MoneyStepGraph) change) =>
      ShareLinksStore.updateFunding(
          id, (r) => r.copyWith(steps: change(r.steps)));

  void _updateStep(
          String id, String stepId, MoneyStep Function(MoneyStep) change) =>
      _updateSteps(
          id,
          (g) => MoneyStepGraph([
                for (final s in g.steps) s.id == stepId ? change(s) : s,
              ]));

  static double _cents(double usd) => (usd * 100).round() / 100;

  /// The funding journey's shape for a gift: its venue is the wallet, its
  /// amount exact.
  static Map<String, Object> _params(
          double amountUsd, Map<String, Object> params) =>
      {
        'venue': 'wallet',
        'entry_source': _kEntrySource,
        'amount_usd': _cents(amountUsd),
        ...params,
      };
}

/// What [GiftFundingRunner] decided before the one approval.
class _GiftDecision {
  const _GiftDecision({
    required this.dollarsUsd,
    required this.bitcoin,
    required this.bitcoinUsd,
    required this.venuePlan,
    required this.fees,
  });

  const _GiftDecision.none(this.dollarsUsd)
      : bitcoin = null,
        bitcoinUsd = 0,
        venuePlan = null,
        fees = OrderFundingFees.none;

  final double dollarsUsd;
  final BitcoinLegPlan? bitcoin;
  final double bitcoinUsd;
  final VenueCashPlan? venuePlan;
  final OrderFundingFees fees;

  bool get needsLegs => bitcoin != null || venuePlan != null;

  /// `funding_source`: the fixed ids of the legs that go.
  String get source => [
        if (bitcoin != null) 'bitcoin',
        if (venuePlan != null) 'venue_cash',
        if (!needsLegs) 'pending',
      ].join(',');
}
