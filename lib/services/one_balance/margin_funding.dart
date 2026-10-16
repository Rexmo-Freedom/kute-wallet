// lib/services/one_balance/margin_funding.dart
//
// Adding margin to an ISOLATED Investing position beyond the Investing
// cash, funded exactly the way the order slips fund an order (founder,
// 14 October 2026: "identical to the order slips"). The sources, in order:
//
//   1. the Investing cash itself;
//   2. Dollars, moved into Investing by the order-funding controller;
//   3. the other venue's cash (Predictions), straight into Investing
//      (`VenueCashPuller`, its direct legs bound into the one approval);
//   4. the person's own bitcoin, for X = what the TOTAL Investments
//      balance lacks (`decideSlipFunding`, `BitcoinFundedOrderRunner`).
//
// [decideMarginFunding] works everything out BEFORE the one approval and
// moves nothing. [MarginFundingRunner] runs after it, headless, so the
// sheet may close at any point: the legs, the Dollars move, the Investing
// credit, then the margin change signed once under a grant chained to the
// change alone (`GrantGuard.chain`). The approval binds the change, the
// Dollars move (`kFundUsdLimit`), the direct legs' caps
// (`VenueLimit.directLegs`) and the Bitcoin leg (`VenueLimit.fundBtc`).
//
// The change is signed only on the very position it was approved for: the
// account is read fresh once the money landed, and a position that closed,
// flipped, went cross or changed size is never signed for. The money then
// stays in Investments. Progress lives in `fundedOrdersProvider` (a margin
// record), which the sheet and the Investments header read.
//
// No ids, addresses or keys reach analytics from here.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAccountProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider, isolatedMarginTarget;
import 'package:kute/services/funding/venue_shortfall.dart' show ShortfallRules;
import 'package:kute/services/hyperliquid/hypercore_cash.dart'
    show hypercoreAvailableUsdc;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart'
    show directMaxSatsFor;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show venueCashPullerProvider;
import 'package:kute/services/one_balance/venue_funder.dart'
    show
        RouteUnavailable,
        UserGrantAuthorization,
        VenueCashDestination,
        VenueFunder;
import 'package:kute/services/tracking_service.dart';

/// The funding journey's `entry_source` for a margin change.
const String kMarginEntrySource = 'add_margin';

/// How long the chain waits for the Investing account to hold the margin
/// once the money left.
const Duration kHlMarginCreditWait = Duration(minutes: 12);

/// `funding_source` values of a margin change (`hyperliquid_margin_adjust_*`).
abstract final class MarginFundingSource {
  static const investing = 'investing';
  static const dollars = 'dollars';
  static const predictions = 'predictions';
  static const bitcoin = 'bitcoin';
}

double _cents(double usd) =>
    usd.isFinite && usd > 0 ? (usd * 100).round() / 100 : 0;

/// The move into Investing for [shortfallUsd] more margin than the
/// Investing cash holds: the engine's target (the shortfall plus its
/// buffer, never under $1), sized on what ARRIVES. Throws when the route
/// cannot land the shortfall. A read: nothing moves.
Future<FundingSize> sizeMarginFunding(
  VenueFunder funder, {
  required double shortfallUsd,
}) async {
  final target = OrderFundingEngine.targetUsd(shortfallUsd: shortfallUsd);
  final size =
      await HyperliquidVenueFunder.sizeFunding(funder, neededUsd: target)
          .timeout(const Duration(seconds: 12));
  if (!size.covers(shortfallUsd)) {
    throw const RouteUnavailable('arriving_below_needed');
  }
  return size;
}

/// What an Add beyond the Investing cash takes from each source, worked
/// out BEFORE the one approval. Nothing here moves money.
@immutable
class MarginFundingPlan {
  const MarginFundingPlan({
    required this.amountUsd,
    required this.readyUsd,
    required this.fundUsd,
    required this.dollarsUsd,
    this.predictionsUsd = 0,
    this.needsOtherVenue = false,
    this.directLegs,
    this.bitcoin,
    this.ownSpark,
    this.ownInvesting,
  });

  /// The margin added.
  final double amountUsd;

  /// The Investing cash at the tap.
  final double readyUsd;

  /// The move into Investing (what may leave Dollars for it): bound into
  /// the approval as `kFundUsdLimit`.
  final double fundUsd;

  /// Dollars held at the tap.
  final double dollarsUsd;

  /// What the other venue gives (planned).
  final double predictionsUsd;

  /// The other venue's cash is pulled before the Dollars move.
  final bool needsOtherVenue;

  /// The other venue's legs straight into Investing, bound into the
  /// approval (`VenueLimit.directLegs`). Null: none goes direct.
  final Map<String, Object?>? directLegs;

  /// The Bitcoin → Dollars leg for X, when bitcoin funds part of it.
  final BitcoinLegPlan? bitcoin;

  /// The wallet's own Spark address the Bitcoin leg is pinned to.
  final String? ownSpark;

  /// The wallet's own Investing account a direct Bitcoin leg is pinned
  /// to (`spark:BTC → hypercore:USDC`). Null: the leg goes via Dollars.
  final String? ownInvesting;

  /// The Investing cash the change uses.
  double get investingUsd => _cents(math.min(readyUsd, amountUsd));

  /// What the Bitcoin leg adds (X).
  double get bitcoinUsd => bitcoin?.targetUsd ?? 0;

  /// What Dollars give to the move: the move less what the other venue
  /// and the Bitcoin leg bring, never more than Dollars held.
  double get dollarsPartUsd => _cents(math.min(math.max(0.0, dollarsUsd),
      math.max(0.0, fundUsd - predictionsUsd - bitcoinUsd)));

  /// The sources used, in order.
  List<String> get sources => [
        if (investingUsd > 0) MarginFundingSource.investing,
        if (dollarsPartUsd > 0) MarginFundingSource.dollars,
        if (_cents(predictionsUsd) > 0) MarginFundingSource.predictions,
        if (bitcoin != null) MarginFundingSource.bitcoin,
      ];

  /// What the one approval binds on top of the margin change: the Dollars
  /// move into Investing, the direct legs' caps and the Bitcoin leg.
  Map<String, Object?> grantLimits() => {
        kFundUsdLimit: dollarsBaseUnits(fundUsd),
        kFundVenueLimit: kFundVenueInvesting,
        if (directLegs != null) VenueLimit.directLegs: directLegs,
        if (bitcoin != null && ownSpark != null)
          VenueLimit.fundBtc: BitcoinLegGrants.limitWithDirect(
              maxSats: bitcoin!.maxSats,
              ownSpark: ownSpark!,
              venue: OneBalanceVenue.investing.name,
              ownVenue: ownInvesting,
              directMaxSats: directMaxSatsFor(bitcoin!)),
      };

  /// `funding_source` (the sources used, comma-separated, in order) and
  /// the exact amount from each. No ids or addresses.
  Map<String, Object> analyticsParams() => {
        'funding_source': sources.join(','),
        if (investingUsd > 0)
          ...TrackingService.exactUsd('investing_usd', investingUsd),
        if (dollarsPartUsd > 0)
          ...TrackingService.exactUsd('dollars_usd', dollarsPartUsd),
        if (_cents(predictionsUsd) > 0)
          ...TrackingService.exactUsd('predictions_usd', predictionsUsd),
        if (bitcoin != null)
          ...TrackingService.exactUsd('bitcoin_usd', bitcoinUsd),
      };

  /// The same for an Add the Investing cash covers on its own.
  static Map<String, Object> investingOnlyParams(double amountUsd) => {
        'funding_source': MarginFundingSource.investing,
        ...TrackingService.exactUsd('investing_usd', amountUsd),
      };
}

// ── The decision, before the approval ───────────────────────────────────

/// Where an Add beyond the Investing cash goes, decided at the tap.
sealed class MarginFundingDecision {
  const MarginFundingDecision();
}

/// Planned: one approval, then [MarginFundingRunner].
final class MarginFundingPlanned extends MarginFundingDecision {
  const MarginFundingPlanned(this.plan);
  final MarginFundingPlan plan;
}

/// The whole Investments balance and the spending bitcoin cannot cover it:
/// the money has to come from outside (the Investments Receive sheet), for
/// [addUsd]. Nothing moves.
final class MarginFundingNeedsReceive extends MarginFundingDecision {
  const MarginFundingNeedsReceive(this.addUsd);
  final double addUsd;
}

/// "Add $X" was tapped but the change now needs more than X: nothing
/// moves, the button names the new figure.
final class MarginFundingAddChanged extends MarginFundingDecision {
  const MarginFundingAddChanged(this.addUsd);
  final double addUsd;
}

/// Nothing could be worked out (no route, no bitcoin price, the wallet's
/// own Spark address or the other venue's plan unread): nothing moves.
final class MarginFundingUnavailable extends MarginFundingDecision {
  const MarginFundingUnavailable(this.reason, {this.error});

  /// A fixed analytics category.
  final String reason;
  final Object? error;
}

double _dollarsShortUsd(double fundUsd, double haveUsd) {
  final short = fundUsd - haveUsd;
  if (short <= 1e-6) return 0;
  return ((short * 100) - 1e-9).ceilToDouble() / 100;
}

/// The order slip's funding decision, for adding [amountUsd] of margin
/// with [readyUsd] of Investing cash and [dollarsUsd] in Dollars, in the
/// founder's order ([decideOrderSources]): Dollars when they cover the
/// move; else the spending bitcoin for what Dollars lack, and the other
/// venue's cash only for what Bitcoin cannot bring; else the other venue's
/// cash when no Bitcoin can help; else the Investments Receive sheet.
///
/// [shownAddUsd] is the X an "Add $X to Investments" tap showed (what
/// Investments lacked; a larger X now moves nothing); [tapLeg] the leg it
/// sized. A read: nothing is quoted to pay, approved or moved.
Future<MarginFundingDecision> decideMarginFunding(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double amountUsd,
  required double readyUsd,
  required double dollarsUsd,
  double? shownAddUsd,
  BitcoinLegPlan? tapLeg,
}) async {
  final shortfall =
      ShortfallRules.shortfallUsd(requiredUsd: amountUsd, readyUsd: readyUsd);
  final dollars = dollarsUsd.isFinite && dollarsUsd > 0 ? dollarsUsd : 0.0;
  FundingSize size;
  try {
    size = await sizeMarginFunding(read(hyperliquidVenueFunderProvider),
        shortfallUsd: shortfall);
  } catch (e) {
    return MarginFundingUnavailable('funding_quote', error: e);
  }
  final fund = size.fundUsd;
  MarginFundingPlan plan({
    double predictionsUsd = 0,
    bool needsOtherVenue = false,
    Map<String, Object?>? directLegs,
    BitcoinLegPlan? bitcoin,
    String? ownSpark,
    String? ownInvesting,
  }) =>
      MarginFundingPlan(
        amountUsd: amountUsd,
        readyUsd: readyUsd,
        fundUsd: fund,
        dollarsUsd: dollars,
        predictionsUsd: predictionsUsd,
        needsOtherVenue: needsOtherVenue,
        directLegs: directLegs,
        bitcoin: bitcoin,
        ownSpark: ownSpark,
        ownInvesting: ownInvesting,
      );

  // 1. Dollars cover the move.
  if (dollars + 1e-9 >= fund) return MarginFundingPlanned(plan());

  // 2. Dollars short: Bitcoin for the rest, and the other venue's cash
  // only for what Dollars and Bitcoin cannot cover (founder decision, 15
  // October 2026: venue to venue is the slow way; [decideOrderSources]).
  final puller = read(venueCashPullerProvider);
  var reach = dollars;
  try {
    reach = await puller
        .reachUsd(exclude: OneBalanceVenue.investing)
        .timeout(const Duration(seconds: 8));
  } catch (_) {}
  final sources = await decideOrderSources(
    read,
    fundUsd: fund,
    dollarsUsd: dollars,
    otherVenueUsd: reach - dollars,
    shownAddUsd: shownAddUsd,
    sized: tapLeg,
    investmentsCover: OrderFundingEngine.decide(
          needUsd: fund,
          haveHereUsd: dollars,
          investmentsUsd: reach - dollars,
        ).route ==
        OrderFundingRoute.move,
  );
  switch (sources.route) {
    case OrderSourceRoute.dollars:
      return MarginFundingPlanned(plan());
    case OrderSourceRoute.addChanged:
      return MarginFundingAddChanged(sources.missingUsd);
    case OrderSourceRoute.insufficient:
      return MarginFundingNeedsReceive(sources.missingUsd > 0
          ? sources.missingUsd
          : _dollarsShortUsd(fund, dollars));
    case OrderSourceRoute.unavailable:
      return const MarginFundingUnavailable('bitcoin_price_unread');
    case OrderSourceRoute.otherVenue:
    case OrderSourceRoute.bitcoin:
      break;
  }
  if (sources.route == OrderSourceRoute.otherVenue) {
    // No Bitcoin leg can help: Dollars and the other venue's cash.
    // The legs are planned before the approval, which binds the ones
    // that go straight into the Investing account.
    Map<String, Object?>? legs;
    var predictions = math.max(0.0, fund - dollars);
    try {
      final legPlan = await puller
          .plan(
            neededUsd: fund,
            exclude: OneBalanceVenue.investing,
            destination: VenueCashDestination.investing,
          )
          .timeout(const Duration(seconds: 8));
      legs = puller.directLegLimit(legPlan, VenueCashDestination.investing);
      predictions = legPlan.pulledUsd;
    } catch (_) {
      // No plan read: every leg comes home to Dollars instead.
      legs = null;
    }
    return MarginFundingPlanned(plan(
        predictionsUsd: predictions, needsOtherVenue: true, directLegs: legs));
  }

  // 3. Dollars and the Bitcoin leg (the other venue only for the rest).
  final leg = sources.plan!;
  final ownSpark = await ownSparkForBitcoinLeg(read);
  // The own Investing account a direct Bitcoin leg is pinned to.
  final ownInvesting =
      await ownVenueDepositFor(read, OneBalanceVenue.investing);
  OtherVenuePlan? other;
  try {
    other = await planOtherVenueCash(puller,
            venue: OneBalanceVenue.investing,
            fundUsd: fund,
            addUsd: leg.targetUsd,
            dollarsUsd: dollars)
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    other = null;
  }
  if (ownSpark == null) {
    return const MarginFundingUnavailable('own_spark_unread');
  }
  if (other == null) {
    return const MarginFundingUnavailable('venue_cash_unread');
  }
  if (!other.covers) {
    return MarginFundingNeedsReceive(_dollarsShortUsd(fund, dollars));
  }
  return MarginFundingPlanned(plan(
    bitcoin: leg,
    ownSpark: ownSpark,
    ownInvesting: ownInvesting,
    directLegs: other.directLegs,
    needsOtherVenue: other.otherUsd > 0,
    predictionsUsd: other.otherUsd,
  ));
}

// ── The chain, after the approval ───────────────────────────────────────

/// The Investing account as a fresh read: its cash (perp plus spot USDC)
/// and its positions.
typedef MarginAccountRead = ({double cashUsd, List<HlPerpPosition> positions});

/// What the chain reads and signs with. Overridden in tests.
class MarginChainEnv {
  const MarginChainEnv({
    required this.account,
    required this.adjust,
    required this.hold,
    required this.sleep,
    this.clock = DateTime.now,
  });

  /// A fresh read of the Investing account; null when unreadable.
  final Future<MarginAccountRead?> Function() account;

  /// Signs the margin change under [grant] (the trading notifier's
  /// `adjustIsolatedMargin`, which re-checks the position itself).
  final Future<void> Function({
    required HlMarket market,
    required HlPerpPosition position,
    required double usd,
    required AuthGrant grant,
  }) adjust;

  /// Keeps the account and the trading notifier alive for the chain's
  /// life, whatever happens to the sheet. Returns the release.
  final void Function() Function() hold;

  final Future<void> Function(Duration) sleep;
  final DateTime Function() clock;

  factory MarginChainEnv.live(Ref ref) => MarginChainEnv(
        account: () async {
          try {
            final snap = await ref
                .read(hyperliquidAccountProvider.future)
                .timeout(const Duration(seconds: 10));
            // The next read is a fresh one.
            ref.invalidate(hyperliquidAccountProvider);
            return (
              cashUsd:
                  hypercoreAvailableUsdc(snap.withdrawable, snap.spotBalances),
              positions: snap.positions,
            );
          } catch (_) {
            return null;
          }
        },
        adjust: ({
          required HlMarket market,
          required HlPerpPosition position,
          required double usd,
          required AuthGrant grant,
        }) async {
          // Built, with its own read of the positions, before it signs.
          await ref.read(hyperliquidTradingProvider.future);
          await ref
              .read(hyperliquidTradingProvider.notifier)
              .adjustIsolatedMargin(
                market: market,
                position: position,
                usd: usd,
                grant: grant,
              );
        },
        hold: () {
          final subs = <ProviderSubscription<Object?>>[
            ref.listen(hyperliquidAccountProvider, (_, __) {}),
            ref.listen(hyperliquidTradingProvider, (_, __) {}),
          ];
          return () {
            for (final s in subs) {
              s.close();
            }
          };
        },
        sleep: (d) => Future<void>.delayed(d),
      );
}

/// The live chain environment. Overridden in tests.
final marginChainEnvProvider =
    Provider<MarginChainEnv>((ref) => MarginChainEnv.live(ref));

/// Whether [live] still holds the very position the change was approved
/// on ([approved]): the same instrument, open, the same side, isolated,
/// the same size and leverage. Anything else is a different position and
/// is never signed for. Pure.
bool marginPositionUnchanged({
  required HlMarket market,
  required HlPerpPosition approved,
  required List<HlPerpPosition> live,
}) {
  final HlPerpPosition current;
  try {
    current =
        isolatedMarginTarget(market: market, position: approved, live: live);
  } on StateError {
    return false;
  }
  final tolerance = 1e-9 * math.max(1.0, approved.szi.abs());
  return (current.szi - approved.szi).abs() <= tolerance &&
      current.leverageValue == approved.leverageValue;
}

/// How the signing step ended.
enum MarginSignResult {
  /// Signed: the venue took the margin change.
  signed,

  /// The credit did not come in time: nothing signed.
  timeout,

  /// The position closed or changed: nothing signed.
  changed,

  /// The signature failed (the venue, the approval): nothing signed.
  failed,
}

/// [MarginSignResult] and what stopped it.
@immutable
class MarginSignOutcome {
  const MarginSignOutcome(this.result, {this.error});
  final MarginSignResult result;
  final Object? error;
}

/// The step after the money moved: waits (bounded) until the Investing
/// account holds [usd], re-reads the position, then signs [change] ONCE
/// under a grant chained to it alone; [grant] is revoked whatever happens,
/// so nothing else can ever run under it. [onCredited] runs once the money
/// is there.
Future<MarginSignOutcome> waitCreditThenSign(
  MarginChainEnv env, {
  required AuthGrant grant,
  required SensitiveIntent change,
  required HlMarket market,
  required HlPerpPosition position,
  required double usd,
  required void Function() onCredited,
  Duration wait = kHlMarginCreditWait,
}) async {
  final deadline = env.clock().add(wait);
  var interval = const Duration(seconds: 1);
  MarginAccountRead? credited;
  while (true) {
    final read = await env.account();
    if (read != null && read.cashUsd + 1e-6 >= usd) {
      credited = read;
      break;
    }
    if (!env.clock().isBefore(deadline)) break;
    await env.sleep(interval);
    interval = const Duration(seconds: 4);
  }
  if (credited == null) {
    grant.revoke();
    return const MarginSignOutcome(MarginSignResult.timeout);
  }
  onCredited();
  if (!marginPositionUnchanged(
      market: market, approved: position, live: credited.positions)) {
    grant.revoke();
    return MarginSignOutcome(MarginSignResult.changed,
        error: StateError('Position changed. Review again.'));
  }
  try {
    // The approval covered the moves and the change together: the change
    // signs under a grant bound to it alone.
    final child = GrantGuard.chain(grant, change);
    grant.revoke();
    await env.adjust(
        market: market, position: position, usd: usd, grant: child);
    return const MarginSignOutcome(MarginSignResult.signed);
  } on StateError catch (e) {
    grant.revoke();
    return MarginSignOutcome(MarginSignResult.changed, error: e);
  } catch (e) {
    grant.revoke();
    return MarginSignOutcome(MarginSignResult.failed, error: e);
  }
}

/// How a funded margin change ended.
enum MarginFundedEnd {
  /// The margin change was signed.
  signed,

  /// Stopped with the bitcoin's money in Investments, nothing signed:
  /// "Your $X is in Investments. Tap to add margin."
  ready,

  /// Stopped after money moved within Investments (the credit took too
  /// long, the move or the signature was refused): nothing signed.
  stopped,

  /// The position closed or changed before signing: nothing signed, the
  /// money stays in Investments.
  changed,

  /// Orchestra failed the Bitcoin leg: the bitcoin goes back home.
  refunded,

  /// Refused before any money moved.
  notSent,

  /// The Bitcoin leg's outcome is unknown: the reconciler resolves it.
  maybeSent,
}

/// What the margin change is, captured at the tap: everything the chain
/// needs, nothing read from the sheet afterwards.
@immutable
class MarginTarget {
  const MarginTarget({
    required this.market,
    required this.position,
    required this.change,
    required this.label,
  });

  final HlMarket market;

  /// The position as it was approved.
  final HlPerpPosition position;

  /// The margin change alone (`HlIntents.isolatedMargin`).
  final SensitiveIntent change;

  /// The record's label (kind margin).
  final FundedOrderLabel label;
}

/// A run the sheet follows: its record and its end.
class MarginFundedRun {
  const MarginFundedRun(this.id, this.ended);
  final String id;
  final Future<MarginFundedEnd> ended;
}

/// The chain. See the file header.
class MarginFundingRunner {
  MarginFundingRunner(this._ref);

  final Ref _ref;

  final Map<String, Object> _errors = {};

  /// What stopped [recordId]'s chain, if anything.
  Object? errorOf(String recordId) => _errors[recordId];

  /// The sheet's tap past [decideMarginFunding]: [approve] asks for the ONE
  /// approval (the margin change bound with [MarginFundingPlan.grantLimits]);
  /// only a grant starts the chain, which then runs whatever happens to
  /// the sheet. Declined: nothing is quoted, sent or funded, and nothing
  /// is recorded.
  Future<MarginFundedRun?> startApproved({
    required MarginFundingPlan plan,
    required MarginTarget target,
    required Future<AuthGrant?> Function() approve,
  }) async {
    final env = _ref.read(marginChainEnvProvider);
    final orders = _ref.read(fundedOrdersProvider.notifier);
    final journey = OrderFundingJourney.instance;
    MarginSignOutcome? signed;

    Future<bool> signStep(AuthGrant grant, void Function() onCredited) async {
      final outcome = await waitCreditThenSign(
        env,
        grant: grant,
        change: target.change,
        market: target.market,
        position: target.position,
        usd: plan.amountUsd,
        onCredited: () {
          journey.credited(OneBalanceVenue.investing);
          onCredited();
        },
      );
      signed = outcome;
      switch (outcome.result) {
        case MarginSignResult.signed:
          journey.completed(OneBalanceVenue.investing,
              resized: false, amountUsd: plan.amountUsd);
        case MarginSignResult.timeout:
          journey.failed(
              OneBalanceVenue.investing, OrderFundingStage.credit, 'timeout');
        case MarginSignResult.changed:
        case MarginSignResult.failed:
          journey.failed(OneBalanceVenue.investing, OrderFundingStage.order,
              TrackingService.errorCategory(outcome.error));
      }
      return outcome.result == MarginSignResult.signed;
    }

    final bitcoin = plan.bitcoin;
    if (bitcoin != null) {
      final release = env.hold();
      final run =
          await _ref.read(bitcoinFundedOrderRunnerProvider).startApproved(
                approve: approve,
                build: (grant) => BitcoinFundedOrderRequest(
                  venue: OneBalanceVenue.investing,
                  grant: grant,
                  plan: bitcoin,
                  label: target.label,
                  fundUsd: plan.fundUsd,
                  readyUsd: plan.readyUsd,
                  entrySource: kMarginEntrySource,
                  otherVenueUsed: plan.needsOtherVenue,
                  fundVenue: (controller, legs) =>
                      _fundRest(controller, grant, plan, legs: legs),
                  dropOrder: grant.revoke,
                  // The step after the venue move: the margin change.
                  awaitPlacement: ({required onCredited}) =>
                      signStep(grant, onCredited),
                ),
              );
      if (run == null) {
        release();
        return null;
      }
      final runner = _ref.read(bitcoinFundedOrderRunnerProvider);
      final ended = run.ended.then((end) {
        release();
        final error = runner.errorOf(run.id) ?? signed?.error;
        if (error != null) _errors[run.id] = error;
        switch (end) {
          case BitcoinFundedEnd.placed:
            return MarginFundedEnd.signed;
          case BitcoinFundedEnd.placementFailed:
            switch (signed?.result) {
              case MarginSignResult.timeout:
                // The bitcoin's money is in Investments: the ready note.
                orders.setStage(run.id, FundedOrderStage.ready,
                    reason: 'timeout');
                return MarginFundedEnd.ready;
              case MarginSignResult.changed:
                orders.setStage(run.id, FundedOrderStage.failed,
                    reason: 'position_changed');
                return MarginFundedEnd.changed;
              case MarginSignResult.signed:
              case MarginSignResult.failed:
              case null:
                return MarginFundedEnd.stopped;
            }
          case BitcoinFundedEnd.transferred:
          case BitcoinFundedEnd.ready:
            return MarginFundedEnd.ready;
          case BitcoinFundedEnd.refunded:
            return MarginFundedEnd.refunded;
          case BitcoinFundedEnd.notSent:
            return MarginFundedEnd.notSent;
          case BitcoinFundedEnd.maybeSent:
            return MarginFundedEnd.maybeSent;
        }
      });
      return MarginFundedRun(run.id, ended);
    }

    // Investing cash, Dollars and the other venue's cash only.
    final grant = await approve();
    if (grant == null) return null;
    final release = env.hold();
    final id = orders.start(target.label, stage: FundedOrderStage.preparing);
    journey.start(
      OneBalanceVenue.investing,
      orderUsd: plan.amountUsd,
      fundUsd: plan.fundUsd,
      readyUsd: plan.readyUsd,
      dollarsUsd: plan.dollarsUsd,
      entrySource: kMarginEntrySource,
      fundingSource: plan.sources.join(','),
      otherVenueUsed: plan.needsOtherVenue,
    );
    Future<MarginFundedEnd> run() async {
      OrderFundingOutcome outcome;
      try {
        outcome = await _fundRest(
            _ref.read(orderFundingControllerProvider), grant, plan);
      } catch (e) {
        outcome =
            OrderFundingRefused(TrackingService.errorCategory(e), error: e);
      }
      MarginFundedEnd stop(String reason, String category, Object? error,
          {required MarginFundedEnd end}) {
        grant.revoke();
        if (error != null) _errors[id] = error;
        orders.setStage(id, FundedOrderStage.failed, reason: reason);
        journey.failed(
            OneBalanceVenue.investing, OrderFundingStage.fund, category);
        return end;
      }

      switch (outcome) {
        case OrderFundingFunded(:final move):
          orders.addVenueRow(id, move.quoteId);
          if (move.orderId != null) orders.addVenueRow(id, move.orderId!);
          final reg = move.registration;
          if (reg != null) {
            unawaited(reg.then((orderId) {
              if (orderId != null && orderId.isNotEmpty) {
                orders.addVenueRow(id, orderId);
              }
            }).catchError((Object _) {}));
          }
        case OrderFundingNotNeeded():
        case OrderFundingUnconfirmed():
          break;
        case OrderFundingRefused(:final reason, :final error):
          // Some of the other venue's cash may have moved (within
          // Investments) before Dollars fell short.
          return stop('venue_refused', reason, error ?? reason,
              end: reason == 'venue_cash_pending'
                  ? MarginFundedEnd.stopped
                  : MarginFundedEnd.notSent);
        case OrderFundingNeedsDollars():
          return stop('venue_refused', 'insufficient_funds', null,
              end: MarginFundedEnd.notSent);
      }
      final placed = await signStep(grant, () {
        orders.setStage(id, FundedOrderStage.placing);
      });
      if (placed) {
        orders.setStage(id, FundedOrderStage.done);
        return MarginFundedEnd.signed;
      }
      final result = signed;
      if (result?.error != null) _errors[id] = result!.error!;
      switch (result?.result) {
        case MarginSignResult.changed:
          orders.setStage(id, FundedOrderStage.failed,
              reason: 'position_changed');
          return MarginFundedEnd.changed;
        case MarginSignResult.timeout:
          orders.setStage(id, FundedOrderStage.failed, reason: 'timeout');
          return MarginFundedEnd.stopped;
        case MarginSignResult.signed:
        case MarginSignResult.failed:
        case null:
          orders.setStage(id, FundedOrderStage.failed, reason: 'placement');
          return MarginFundedEnd.stopped;
      }
    }

    final ended = run().whenComplete(release);
    return MarginFundedRun(id, ended);
  }

  /// The rest of the money after the Bitcoin leg (or without one): the
  /// other venue's cash under the same [grant] (legs straight into
  /// Investing within the caps it binds, the others home to Dollars), then
  /// the Dollars move for what the direct legs do not bring. The slips'
  /// own path ([fundRestThenMove]).
  Future<OrderFundingOutcome> _fundRest(OrderFundingController controller,
          AuthGrant grant, MarginFundingPlan plan,
          {FundingLegContext legs = const FundingLegContext()}) =>
      fundRestThenMove(
        legs: legs,
        puller: _ref.read(venueCashPullerProvider),
        venue: OneBalanceVenue.investing,
        fundUsd: plan.fundUsd,
        readyUsd: plan.readyUsd,
        needsOtherVenue: plan.needsOtherVenue,
        grant: grant,
        queue: ({
          required double fundUsd,
          required double readyUsd,
          required double directArrivingUsd,
          String? moveId,
        }) async {
          final outcome = await controller.fundAndQueue(
            venue: OneBalanceVenue.investing,
            orderUsd: plan.amountUsd,
            requiredUsd: plan.amountUsd,
            readyUsd: readyUsd,
            auth: UserGrantAuthorization(grant),
            fundUsd: fundUsd,
            entrySource: kMarginEntrySource,
            purpose: 'order_funding',
            keepUnconfirmed: true,
            continueJourney: true,
          );
          if (outcome case OrderFundingFunded(:final move)) {
            // The change's own move is the last leg of its multi-source
            // move: one Activity row.
            MultiSourceMoveStore.attachFinal(
                moveId, move.operationId ?? move.quoteId);
          }
          return outcome;
        },
      );
}

final marginFundingRunnerProvider =
    Provider<MarginFundingRunner>((ref) => MarginFundingRunner(ref));
