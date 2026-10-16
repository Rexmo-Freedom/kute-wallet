import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/auth_provider.dart' show sessionAuthProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/bet_funding_plan.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_cash_funded_order.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

/// Spendable pUSD must exist both on chain and on the venue's latest count.
/// USDC.e and unknown reads cannot authorize a bet.
double? predictionsPrefundSpendable(PolyBuyReads? reads,
    {required double reservedUsd}) {
  if (reads == null || reads.venue == null) return null;
  if (!reads.setupDone) return 0;
  return math.max(
      0.0,
      math.min(reads.pusd.toDouble(), reads.venue!.balance.toDouble()) / 1e6 -
          reservedUsd);
}

class PredictionsTransferUnavailable implements Exception {
  const PredictionsTransferUnavailable(this.reason);
  final String reason;
}

class PredictionsTransferPlan {
  const PredictionsTransferPlan(
      {required this.walletId,
      required this.accountContext,
      required this.ownSpark,
      required this.ownPredictions,
      required this.requiredUsd,
      required this.readyUsd,
      required this.funding,
      required this.sources,
      this.cashPlan,
      this.other,
      this.btcLeg});
  final String walletId;
  final Object accountContext;
  final String ownSpark;
  final String ownPredictions;
  final double requiredUsd;
  final double readyUsd;
  final OrderFundingPlan funding;
  final OrderSources sources;
  final VenueCashPlan? cashPlan;
  final OtherVenuePlan? other;
  final Map<String, Object?>? btcLeg;
}

/// A cash transfer, never a pending order. Closing the slip cannot submit a
/// bet: this coordinator owns neither an order intent nor an autofire grant.
class PredictionsPrefundTransfer extends ChangeNotifier {
  PredictionsPrefundTransfer(this._ref);
  final Ref _ref;
  double? _spendableUsd;
  Object? _spendableContext;
  double? get spendableUsd =>
      _spendableContext != null && _matches(_spendableContext!)
          ? _spendableUsd
          : null;
  set spendableUsd(double? value) {
    _spendableUsd = value;
    _spendableContext = _disposed ? null : _context();
  }

  String? runId;
  bool busy = false;
  bool checking = false;
  bool _preparing = false;
  String? failure;
  bool _disposed = false;
  Future<double?>? _read;
  final _phases = StreamController<String>.broadcast();
  String _phase = 'waiting';

  /// Once a run may have sent money, its failure is reviewed by reading its
  /// balance, never by automatically starting the transfer again.
  bool get needsTransferReview => runId != null && failure != null;
  static Duration maxWait = const Duration(minutes: 12);
  static Duration pollEvery = const Duration(seconds: 1);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(String phase) {
    _phase = phase;
    if (!_disposed) _phases.add(phase);
  }

  Stream<String> _phaseStream() => Stream<String>.multi((events) {
        events.add(_phase);
        final subscription = _phases.stream
            .listen(events.add, onError: events.addError, onDone: events.close);
        // Phase observers must detach without holding the money-step result
        // on a replay stream's cancellation future.
        events.onCancel = () => unawaited(subscription.cancel());
      });

  String? get _wallet =>
      _disposed ? null : pickSpendingWallet(_ref.read(settingsProvider))?.id;
  Object _context() {
    final wallet = pickSpendingWallet(_ref.read(settingsProvider));
    final trading = _ref.read(polymarketTradingProvider.notifier);
    final state = _ref.read(polymarketTradingProvider).valueOrNull;
    return (
      wallet: wallet?.id,
      evm: wallet?.evmDerivationVersion,
      session: _ref.read(sessionAuthProvider) != null,
      generation: trading.accountGeneration,
      proxy: state?.proxyWalletAddress?.toLowerCase(),
      signer: trading.signingWalletId
    );
  }

  bool _matches(Object context) => !_disposed && _context() == context;
  double _reserved(double cash) =>
      cash -
      PolymarketBetController.spendableUsdc(
          cash,
          _ref.read(polymarketTradingProvider).valueOrNull?.openOrders ??
              const []);

  Future<double?> refresh() {
    if (_disposed) return Future.value(null);
    final running = _read;
    if (running != null) return running;
    final wallet = _wallet;
    final accountContext = _context();
    final trading = _ref.read(polymarketTradingProvider.notifier);
    checking = true;
    _changed();
    final next = () async {
      try {
        final reads = await trading
            .readBuyReadiness(refreshVenue: true)
            .timeout(const Duration(seconds: 15));
        if (!_matches(accountContext) ||
            wallet != _wallet ||
            !identical(
                trading, _ref.read(polymarketTradingProvider.notifier))) {
          return null;
        }
        final total =
            reads == null ? 0.0 : (reads.pusd + reads.usdce).toDouble() / 1e6;
        spendableUsd =
            predictionsPrefundSpendable(reads, reservedUsd: _reserved(total));
        return spendableUsd;
      } catch (_) {
        if (!_disposed) spendableUsd = null;
        return null;
      } finally {
        checking = false;
        _read = null;
        _changed();
      }
    }();
    _read = next;
    return next;
  }

  Future<PredictionsTransferPlan> prepare(double requiredUsd) async {
    if (_disposed || busy || _preparing || needsTransferReview) {
      throw const PredictionsTransferUnavailable('transfer_pending');
    }
    if (FundedOrdersNotifier.activeOf(
            _ref.read(fundedOrdersProvider), OneBalanceVenue.predictions) !=
        null) {
      throw const PredictionsTransferUnavailable('transfer_pending');
    }
    _preparing = true;
    try {
      final wallet = _wallet;
      final accountContext = _context();
      final state = _ref.read(polymarketTradingProvider).valueOrNull;
      if (wallet == null || state == null || !state.balanceKnown) {
        throw const PredictionsTransferUnavailable('account_unread');
      }
      final reads = await _ref
          .read(polymarketTradingProvider.notifier)
          .readBuyReadiness(refreshVenue: true)
          .timeout(const Duration(seconds: 15));
      if (reads == null || !_matches(accountContext) || _wallet != wallet) {
        throw const PredictionsTransferUnavailable('balance_unread');
      }
      final total = (reads.pusd + reads.usdce).toDouble() / 1e6;
      final ready = math.max(0.0, total - _reserved(total));
      final funding = await readBetFunding(
          _ref.read(predictionsVenueFunderProvider),
          requiredUsd: requiredUsd,
          readyUsd: ready);
      final dollars = _ref.read(usdBalanceProvider);
      final puller = _ref.read(venueCashPullerProvider);
      final reach = dollars >= funding.fundUsd
          ? dollars
          : await puller
              .reachUsd(exclude: OneBalanceVenue.predictions)
              .timeout(const Duration(seconds: 8));
      final sources = await decideOrderSources(_ref.read,
          fundUsd: funding.fundUsd,
          dollarsUsd: dollars,
          otherVenueUsd: math.max(0, reach - dollars),
          investmentsCover: reach >= funding.fundUsd);
      if (sources.route == OrderSourceRoute.insufficient ||
          sources.route == OrderSourceRoute.unavailable ||
          sources.route == OrderSourceRoute.addChanged) {
        throw const PredictionsTransferUnavailable('insufficient_funds');
      }
      final ownSpark = await ownSparkForBitcoinLeg(_ref.read);
      final ownPm =
          await ownVenueDepositFor(_ref.read, OneBalanceVenue.predictions);
      if (ownSpark == null ||
          ownPm == null ||
          !_matches(accountContext) ||
          _wallet != wallet) {
        throw const PredictionsTransferUnavailable('account_unread');
      }
      VenueCashPlan? cash;
      OtherVenuePlan? other;
      Map<String, Object?>? btc;
      if (sources.route == OrderSourceRoute.bitcoin) {
        cash = await puller
            .plan(
                neededUsd:
                    math.max(0, funding.fundUsd - sources.plan!.targetUsd),
                exclude: OneBalanceVenue.predictions,
                destination: VenueCashDestination.predictions)
            .timeout(const Duration(seconds: 8));
        if (!cash.covers) {
          throw const PredictionsTransferUnavailable('insufficient_funds');
        }
        other = OtherVenuePlan(
            otherUsd: cash.pulledUsd,
            covers: cash.covers,
            directLegs:
                puller.directLegLimit(cash, VenueCashDestination.predictions));
        btc = await bitcoinLegLimitFor(_ref.read,
            venue: OneBalanceVenue.predictions,
            leg: sources.plan!,
            ownSpark: ownSpark);
      } else {
        cash = await puller
            .plan(
                neededUsd: funding.fundUsd,
                exclude: OneBalanceVenue.predictions,
                destination: VenueCashDestination.predictions)
            .timeout(const Duration(seconds: 8));
        if (!cash.covers) {
          throw const PredictionsTransferUnavailable('insufficient_funds');
        }
      }
      if (!_matches(accountContext)) {
        throw const PredictionsTransferUnavailable('account_changed');
      }
      return PredictionsTransferPlan(
          accountContext: accountContext,
          walletId: wallet,
          ownSpark: ownSpark,
          ownPredictions: ownPm,
          requiredUsd: requiredUsd,
          readyUsd: ready,
          funding: funding,
          sources: sources,
          cashPlan: cash,
          other: other,
          btcLeg: btc);
    } finally {
      _preparing = false;
    }
  }

  Future<void> start(PredictionsTransferPlan plan,
      {required Future<AuthGrant?> Function(SensitiveIntent) approve}) async {
    if (busy ||
        needsTransferReview ||
        !_matches(plan.accountContext) ||
        _wallet != plan.walletId) {
      return;
    }
    busy = true;
    failure = null;
    spendableUsd = null;
    _changed();
    AuthGrant? grant;
    try {
      if (plan.funding.fundUsd <= 0) {
        await _readyOnly(plan);
        return;
      }
      final currentCash = await refresh();
      if (!_matches(plan.accountContext)) return;
      if (currentCash != null && currentCash + 1e-6 >= plan.requiredUsd) return;
      final puller = _ref.read(venueCashPullerProvider);
      final intent = PredictionPrefundGrants.review(
          walletId: plan.walletId,
          ownSpark: plan.ownSpark,
          ownPredictions: plan.ownPredictions,
          fundUsd: plan.cashPlan!.dollarsUsd +
              (plan.sources.plan?.targetUsd ?? 0) +
              plan.cashPlan!.pulls.fold(0.0, (sum, leg) => sum + leg.usd),
          dollarsUsd: plan.cashPlan!.dollarsUsd +
              (plan.sources.plan?.targetUsd ?? 0) +
              plan.cashPlan!.pulls
                  .fold(0.0, (sum, leg) => sum + leg.arrivingUsd),
          bitcoinUsd: plan.sources.plan?.targetUsd ?? 0,
          btcLeg: plan.btcLeg,
          directLegs: plan.other?.directLegs ??
              (plan.cashPlan == null
                  ? null
                  : puller.directLegLimit(
                      plan.cashPlan!, VenueCashDestination.predictions)));
      grant = await approve(intent);
      if (grant == null) return;
      if (!_matches(plan.accountContext) || _wallet != plan.walletId) {
        grant.revoke();
        return;
      }
      final approved = grant;
      var cancelled = false;
      final transfer = FundingTransferCompletion(
          wait: ({required onCredited}) => _waitReady(plan,
              onCredited: onCredited, isCancelled: () => cancelled),
          cancel: () => cancelled = true,
          phases: _phaseStream);
      final label = FundedOrderLabel(
          venue: OneBalanceVenue.predictions,
          orderUsd: plan.requiredUsd,
          side: '',
          market: 'Polymarket',
          marketKey: 'prefund',
          kind: FundedOrderKind.transfer);
      Future<OrderFundingOutcome> move(
          OrderFundingController controller, double fundUsd, double readyUsd) {
        if (!_matches(plan.accountContext) || _wallet != plan.walletId) {
          return Future.value(const OrderFundingRefused('account_changed'));
        }
        if (fundUsd <= 0.005) {
          return Future.value(const OrderFundingNotNeeded());
        }
        return controller.fundAndQueue(
            venue: OneBalanceVenue.predictions,
            orderUsd: plan.requiredUsd,
            requiredUsd: plan.requiredUsd,
            readyUsd: readyUsd,
            auth: UserGrantAuthorization(approved),
            fundUsd: fundUsd,
            purpose: 'predictions_prefund',
            keepUnconfirmed: true,
            continueJourney: true,
            entrySource: 'bitcoin_5m_prefund');
      }

      final BitcoinFundedRun? run;
      if (plan.sources.route == OrderSourceRoute.bitcoin) {
        run = await _ref.read(bitcoinFundedOrderRunnerProvider).startApproved(
            approve: () async => approved,
            build: (_) => BitcoinFundedOrderRequest(
                  venue: OneBalanceVenue.predictions,
                  grant: approved,
                  plan: plan.sources.plan!,
                  label: label,
                  fundUsd: plan.funding.fundUsd,
                  readyUsd: plan.readyUsd,
                  otherVenueUsed: plan.other!.otherUsd > 0,
                  transfer: transfer,
                  entrySource: 'bitcoin_5m_prefund',
                  dropOrder: approved.revoke,
                  isCurrentAttempt: () =>
                      _matches(plan.accountContext) && _wallet == plan.walletId,
                  fundVenue: (controller, legs) => fundRestThenMove(
                      puller: puller,
                      venue: OneBalanceVenue.predictions,
                      fundUsd: plan.funding.fundUsd,
                      readyUsd: plan.readyUsd,
                      needsOtherVenue: plan.other!.otherUsd > 0,
                      grant: approved,
                      legs: legs,
                      approvedPlan: legs.bitcoinShareUsd > 0
                          ? plan.cashPlan
                          : VenueCashPlan(
                              neededUsd: plan.cashPlan!.neededUsd +
                                  plan.sources.plan!.targetUsd,
                              dollarsUsd: plan.cashPlan!.dollarsUsd +
                                  plan.sources.plan!.targetUsd,
                              pulls: plan.cashPlan!.pulls,
                              covers: plan.cashPlan!.covers,
                              eta: plan.cashPlan!.eta,
                              uncoveredUsd: plan.cashPlan!.uncoveredUsd),
                      queue: (
                              {required fundUsd,
                              required readyUsd,
                              required directArrivingUsd,
                              moveId}) =>
                          move(controller, fundUsd, readyUsd)),
                ));
      } else {
        run = _ref
            .read(venueCashFundedOrderRunnerProvider)
            .start(VenueCashFundedRequest(
              venue: OneBalanceVenue.predictions,
              grant: approved,
              label: label,
              fundUsd: plan.funding.fundUsd,
              readyUsd: plan.readyUsd,
              plan: plan.cashPlan!,
              transfer: transfer,
              entrySource: 'bitcoin_5m_prefund',
              dropOrder: approved.revoke,
              isCurrentAttempt: () =>
                  _matches(plan.accountContext) && _wallet == plan.walletId,
              queue: ({required fundUsd, required readyUsd}) => move(
                  _ref.read(orderFundingControllerProvider), fundUsd, readyUsd),
              fundMore: (controller, usd) => move(controller, usd, 0),
            ));
      }
      if (run == null) return;
      runId = run.id;
      _changed();
      final end = await run.ended;
      if (end != BitcoinFundedEnd.transferred) {
        failure = end.name;
      }
    } catch (e) {
      failure = e is PredictionsTransferUnavailable
          ? e.reason
          : 'transfer_unavailable';
    } finally {
      grant?.revoke();
      busy = false;
      _changed();
    }
  }

  Future<void> _readyOnly(PredictionsTransferPlan plan) async {
    final orders = _ref.read(fundedOrdersProvider.notifier);
    final id = orders.start(
        const FundedOrderLabel(
            venue: OneBalanceVenue.predictions,
            orderUsd: 0,
            side: '',
            market: 'Polymarket',
            marketKey: 'prefund',
            kind: FundedOrderKind.transfer),
        stage: FundedOrderStage.preparing);
    runId = id;
    OrderFundingJourney.instance.start(OneBalanceVenue.predictions,
        orderUsd: plan.requiredUsd,
        fundUsd: 0,
        readyUsd: plan.readyUsd,
        dollarsUsd: 0,
        purpose: 'predictions_prefund',
        entrySource: 'bitcoin_5m_prefund');
    final credited = Completer<void>();
    final completed = Completer<bool>();
    final steps = MoneyStepRunner(
      graph: fundedOrderGraph(
          venue: OneBalanceVenue.predictions,
          legs: const [],
          orderUsd: 0,
          transferOnly: true),
      actionFor: (step) => (_, update) => readinessPhaseStep(
          step.kind == MoneyStepKind.convert
              ? 'converting'
              : step.kind == MoneyStepKind.approve
                  ? 'approving'
                  : 'confirming',
          update,
          optional: step.kind != MoneyStepKind.confirm,
          phases: _phaseStream(),
          credited: credited.future,
          placement: completed.future),
      onChange: (graph) {
        if (!_disposed) orders.setSteps(id, graph);
      },
    );
    final waiting = _waitReady(plan, onCredited: () {
      if (!credited.isCompleted) credited.complete();
    });
    unawaited(waiting.then((ready) {
      if (!completed.isCompleted) completed.complete(ready);
    }));
    final graph = await steps.run();
    if (_disposed) return;
    if (graph.allDone && await waiting) {
      orders.setStage(id, FundedOrderStage.done);
      OrderFundingJourney.instance.transferReady(OneBalanceVenue.predictions);
    } else {
      OrderFundingJourney.instance.failed(OneBalanceVenue.predictions,
          OrderFundingStage.credit, 'balance_confirmation_timeout');
      failure = 'balance_confirmation_timeout';
      orders.stop(id,
          stage: FundedOrderStage.failed,
          reason: failure!,
          moneyAt: FundedMoneyAt.venue);
    }
  }

  Future<bool> _waitReady(PredictionsTransferPlan plan,
      {required void Function() onCredited,
      bool Function()? isCancelled}) async {
    final trading = _ref.read(polymarketTradingProvider.notifier);
    final until = DateTime.now().add(maxWait);
    while (_matches(plan.accountContext) &&
        isCancelled?.call() != true &&
        _wallet == plan.walletId &&
        DateTime.now().isBefore(until)) {
      try {
        final reads = await trading
            .readBuyReadiness(refreshVenue: true)
            .timeout(const Duration(seconds: 15));
        if (!_matches(plan.accountContext) ||
            isCancelled?.call() == true ||
            _wallet != plan.walletId ||
            !identical(
                trading, _ref.read(polymarketTradingProvider.notifier))) {
          return false;
        }
        if (reads != null) {
          if (!reads.setupDone) {
            _setPhase('approving');
            await trading.enableTrading();
            if (!_matches(plan.accountContext)) return false;
            // Setup may rebuild account state. Only a new read can prove ready.
            continue;
          } else if (reads.usdce > BigInt.from(10000) &&
              reads.pusd < IntentUnits.usd(plan.requiredUsd)) {
            _setPhase('converting');
            trading.nudgeConversion();
          } else {
            _setPhase('confirming');
          }
          final total = (reads.pusd + reads.usdce).toDouble() / 1e6;
          spendableUsd =
              predictionsPrefundSpendable(reads, reservedUsd: _reserved(total));
          _changed();
          if ((spendableUsd ?? -1) + 1e-6 >= plan.requiredUsd) {
            _setPhase('ready');
            onCredited();
            return true;
          }
        }
      } catch (_) {
        _setPhase('confirming');
      }
      await Future<void>.delayed(pollEvery);
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _phases.close();
    super.dispose();
  }
}

final predictionsPrefundTransferProvider =
    ChangeNotifierProvider<PredictionsPrefundTransfer>((ref) {
  ref.watch(settingsProvider.select((s) => (
        pickSpendingWallet(s)?.id,
        pickSpendingWallet(s)?.evmDerivationVersion
      )));
  ref.watch(sessionAuthProvider.select((s) => s != null));
  ref.watch(polymarketTradingProvider
      .select((s) => s.valueOrNull?.proxyWalletAddress));
  final transfer = PredictionsPrefundTransfer(ref);
  // Account readiness can rebuild this provider after the slip's listener ran.
  // The replacement must establish its own fresh reading as well.
  scheduleMicrotask(() => unawaited(transfer.refresh()));
  return transfer;
});
