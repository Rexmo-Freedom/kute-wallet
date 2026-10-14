// lib/services/one_balance/bitcoin_funded_order.dart
//
// An order slip short of the WHOLE Investments balance (founder decision
// 14 October 2026): one tap on "Add $X to Investments", ONE Face ID, then,
// with constant feedback on the slip,
//
//   1. Bitcoin → Dollars: the wallet's own bitcoin to its own dollars
//      ("Adding $X to Investments");
//   2. Dollars → the venue, the order's usual funding move ("Getting your
//      prediction ready" / "Preparing your order");
//   3. the order, placed by the venue's own autofire at a fresh price once
//      the venue holds the money ("Placing $Y on Yes").
//
// The slip validates everything and asks for the one approval BEFORE any
// money moves: the order's own autofire grant, extended with the Bitcoin
// leg (`BitcoinLegGrants.limit`: at most N sats, `spark:BTC →
// spark:USDB`, to the wallet's own Spark address). This runner then works
// headless, so the slip may close at any point:
//
//   * the Bitcoin leg pays only a verified quote that grant covers
//     (`BitcoinLegGrants.stepUp`, single use), no prompt;
//   * the dollars' landing is detected as fast as the app can tell
//     (`DollarsLandingWatcher`: the order's status every second, the
//     balance rising, then a fresh wallet read);
//   * the venue move runs under the SAME grant (`fundVenue`, the
//     controller's own Dollars check is the guard), no second prompt;
//   * the venue's autofire places the order; the runner follows it. (The
//     margin sheet runs the same chain and signs its margin change in
//     this step instead: `margin_funding.dart`.)
//
// Anything that stops the chain after the Bitcoin left leaves the money
// in Dollars, visible, with the order dropped and its approval cancelled:
// the slip then says "Your $X is in Investments. Tap to place." A leg
// Orchestra refunds sends the bitcoin back home. A refusal before the sats
// leave moves nothing. Progress and outcomes live in `fundedOrdersProvider`
// (persisted), which the slips and the Investments header read.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrant;
import 'package:kute/helpers/venue_intents.dart' show BitcoinLegGrants;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/models/breez/sdk_instance.dart'
    show ArrivalAsset, BreezSdkSpark;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show currencyProvider, selectedCurrencyProvider;
import 'package:kute/providers/pending_hyperliquid_order_provider.dart'
    show
        PendingHlOrderIntent,
        PendingHlOrderStatus,
        pendingHyperliquidOrderProvider;
import 'package:kute/providers/pending_polymarket_bet_provider.dart'
    show PendingBetIntent, PendingBetStatus, pendingPolymarketBetProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdDollarsFromNodeInfo;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown, SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashFor, VenueCashPullOutcome, VenueCashPuller;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination, VenueMoveResult;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/services/tracking_service.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show GetInfoRequest;

/// What a Bitcoin leg handed back once its sats left.
@immutable
class BitcoinLegTicket {
  const BitcoinLegTicket({
    required this.quoteId,
    required this.sats,
    required this.estimatedOutUsd,
    required this.minOutUsd,
    this.orderId,
    this.registration,
  });

  final String quoteId;
  final String? orderId;
  final Future<String?>? registration;
  final int sats;
  final double estimatedOutUsd;
  final double minOutUsd;
}

/// Everything the runner reads from the wallet, as functions so tests
/// can stand in for the SDK, Orchestra and the clock.
class BitcoinLegEnv {
  const BitcoinLegEnv({
    required this.ownSpark,
    required this.send,
    required this.watcher,
    required this.dollarsNow,
    required this.freshDollars,
  });

  /// The wallet's own Spark address, from the Spark SDK.
  final Future<String> Function() ownSpark;

  /// Sends the leg (quote, [stepUp], payment). [onSending] runs right
  /// before the payment call.
  final Future<BitcoinLegTicket> Function({
    required String sparkAddress,
    required BitcoinLegPlan plan,
    required SettlementStepUpHook stepUp,
    required void Function() onSending,
  }) send;

  /// A watcher for a leg whose sats left at [since].
  final DollarsLandingWatcher Function({required DateTime since}) watcher;
  final double Function() dollarsNow;
  final Future<double?> Function() freshDollars;

  /// The live wallet.
  factory BitcoinLegEnv.live(Ref ref) {
    double dollarsNow() {
      try {
        return ref.read(usdBalanceProvider);
      } catch (_) {
        return 0;
      }
    }

    Future<double?> freshDollars() async {
      try {
        final wrapper = await ref
            .read(breezSDKProvider.future)
            .timeout(const Duration(seconds: 3));
        final sdk = wrapper.instance;
        if (sdk == null) return null;
        final info = await sdk
            .getInfo(request: const GetInfoRequest())
            .timeout(const Duration(seconds: 3));
        return usdDollarsFromNodeInfo(info);
      } catch (_) {
        return null;
      }
    }

    Stream<double> dollarsStream() {
      ProviderSubscription<double>? sub;
      late final StreamController<double> controller;
      controller = StreamController<double>(
        onListen: () {
          sub = ref.listen<double>(usdBalanceProvider, (_, next) {
            if (!controller.isClosed) controller.add(next);
          });
        },
        onCancel: () => sub?.close(),
      );
      return controller.stream;
    }

    return BitcoinLegEnv(
      ownSpark: () => ref.read(sparkSelfAddressProvider.future),
      send: ({
        required String sparkAddress,
        required BitcoinLegPlan plan,
        required SettlementStepUpHook stepUp,
        required void Function() onSending,
      }) async {
        final sent = await BitcoinToDollarsLeg.send(
          ref.read,
          appRead: ref.read,
          sparkAddress: sparkAddress,
          approxUsd: plan.targetUsd,
          usdPerBtc: plan.usdPerBtc,
          stepUp: stepUp,
          requestQuote: (key) async {
            final (_, fetched) = await BitcoinToDollarsLeg.quoteForTarget(
              ref.read,
              sats: plan.sats,
              targetUsd: plan.targetUsd,
              maxSats: plan.maxSats,
              sparkAddress: sparkAddress,
              idempotencyKey: key,
            );
            return fetched;
          },
          onSending: onSending,
        );
        return BitcoinLegTicket(
          quoteId: sent.quoteId,
          orderId: sent.orderId,
          registration: sent.registration,
          sats: sent.sats,
          estimatedOutUsd: sent.estimatedOutUsd,
          minOutUsd: sent.minOutUsd,
        );
      },
      watcher: ({required DateTime since}) => DollarsLandingWatcher(
        statusOf: orchestraLegStatus,
        dollarsNow: dollarsNow,
        freshDollars: freshDollars,
        // The generic arrival path (ArrivalRefresher) re-reads the dollar
        // balance against its level before the sats left; asked for,
        // never waited on.
        kickSync: () => unawaited(BreezSdkSpark()
            .syncAndRefresh(asset: ArrivalAsset.dollars, since: since)),
        dollarsChanges: dollarsStream(),
      ),
      dollarsNow: dollarsNow,
      freshDollars: freshDollars,
    );
  }
}

/// The wallet behind the runner. Overridden in tests.
final bitcoinLegEnvProvider =
    Provider<BitcoinLegEnv>((ref) => BitcoinLegEnv.live(ref));

/// How a Bitcoin-funded order ended.
enum BitcoinFundedEnd {
  /// The order was placed.
  placed,

  /// The venue did not place it (price moved, refused, the credit never
  /// came): the money stays in Investments, the slip shows the venue's
  /// own message and retry.
  placementFailed,

  /// Stopped with the money in Dollars (the venue move was refused, the
  /// dollars took too long): "Tap to place".
  ready,

  /// Orchestra failed the Bitcoin leg: the bitcoin goes back home.
  refunded,

  /// Refused before any sats left. Nothing moved.
  notSent,

  /// The payment's outcome is unknown: the reconciler resolves it.
  maybeSent,
}

/// How the venue's autofire ended for the order.
typedef BitcoinPlacementWait = Future<bool> Function(
    {required void Function() onCredited});

/// What a slip hands the runner once the person approved.
class BitcoinFundedOrderRequest {
  BitcoinFundedOrderRequest({
    required this.venue,
    required this.grant,
    required this.plan,
    required this.label,
    required this.fundUsd,
    required this.readyUsd,
    required this.fundVenue,
    required this.dropOrder,
    this.entrySource,
    this.awaitPlacement,
  });

  final OneBalanceVenue venue;

  /// The order's one approval (its autofire grant), binding the order,
  /// the funding move and the Bitcoin leg.
  final AuthGrant grant;
  final BitcoinLegPlan plan;
  final FundedOrderLabel label;

  /// The approved Dollars → venue move.
  final double fundUsd;

  /// The venue's ready cash when the order was approved.
  final double readyUsd;
  final String? entrySource;

  /// The venue move and the queued order, once the dollars landed:
  /// [controller] reads the fresh balance. The slip's own funded path,
  /// minus its prompt.
  final Future<OrderFundingOutcome> Function(OrderFundingController controller,
      {required DateTime bitcoinSentAt,
      required DateTime bitcoinLandedAt}) fundVenue;

  /// Drops the queued order and cancels its approval: nothing will be
  /// placed for it.
  final void Function() dropOrder;

  /// The step after the venue move, in place of the venue's own placement
  /// watch: the margin sheet signs its margin change here once the credit
  /// lands (`MarginFundingRunner`); tests stand in for it too. Null
  /// follows the venue's autofire, which places the slip's queued order.
  final BitcoinPlacementWait? awaitPlacement;
}

/// A run the slip follows: its record and its end.
class BitcoinFundedRun {
  const BitcoinFundedRun(this.id, this.ended, {this.error});
  final String id;
  final Future<BitcoinFundedEnd> ended;
  final Object? error;
}

/// The chain. See the file header.
class BitcoinFundedOrderRunner {
  BitcoinFundedOrderRunner(this._ref);

  final Ref _ref;

  /// Test seam: the clock the stage timings use.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// The error the last refused leg threw, by record, for the slip's copy.
  final Map<String, Object> _errors = {};

  /// What stopped [recordId]'s leg before anything moved, if anything.
  Object? errorOf(String recordId) => _errors[recordId];

  /// Starts the chain for [r] and returns at once: the record is written
  /// now, the chain runs on whatever happens to the slip.
  /// The slip's Add tap, past its validation and sizing: [approve] asks
  /// for the ONE approval (the order with its funding and Bitcoin legs);
  /// only a grant starts the chain ([build] turns it into the request).
  /// Declined, nothing is quoted, sent or funded, and nothing recorded.
  Future<BitcoinFundedRun?> startApproved({
    required Future<AuthGrant?> Function() approve,
    required BitcoinFundedOrderRequest? Function(AuthGrant grant) build,
  }) async {
    final grant = await approve();
    if (grant == null) return null;
    final request = build(grant);
    if (request == null) {
      grant.revoke();
      return null;
    }
    return start(request);
  }

  BitcoinFundedRun start(BitcoinFundedOrderRequest r) {
    final orders = _ref.read(fundedOrdersProvider.notifier);
    final id = orders.start(r.label,
        stage: FundedOrderStage.adding, addUsd: r.plan.targetUsd);
    return BitcoinFundedRun(id, _run(id, r));
  }

  Future<BitcoinFundedEnd> _run(String id, BitcoinFundedOrderRequest r) async {
    final env = _ref.read(bitcoinLegEnvProvider);
    final orders = _ref.read(fundedOrdersProvider.notifier);
    final journey = OrderFundingJourney.instance;
    final venue = r.venue;

    BitcoinFundedEnd stop(FundedOrderStage stage, BitcoinFundedEnd end,
        {required String reason,
        String? category,
        FundedMoneyAt? moneyAt,
        String? message}) {
      // The step it was on is the one that failed; the slip says where
      // the money is.
      orders.stop(id,
          stage: stage, reason: reason, moneyAt: moneyAt, message: message);
      if (category != null) {
        journey.failed(venue, OrderFundingStage.bitcoin, category);
      }
      try {
        r.dropOrder();
      } catch (_) {}
      return end;
    }

    // The baseline the landing is measured from, read BEFORE any send.
    var baseline = env.dollarsNow();
    final fresh = await env.freshDollars();
    if (fresh != null && fresh > baseline) baseline = fresh;

    journey.start(
      venue,
      orderUsd: r.label.orderUsd,
      fundUsd: r.fundUsd,
      readyUsd: r.readyUsd,
      dollarsUsd: baseline,
      entrySource: r.entrySource,
      fundingSource: 'bitcoin',
      extra: {
        'add_usd': r.plan.targetUsd,
        'add_sats': r.plan.sats,
      },
    );

    // 1. Bitcoin → Dollars under the order's grant.
    String sparkAddress;
    try {
      sparkAddress = await env.ownSpark();
    } catch (e) {
      _errors[id] = e;
      return stop(FundedOrderStage.failed, BitcoinFundedEnd.notSent,
          reason: 'not_sent',
          category: TrackingService.errorCategory(e),
          moneyAt: FundedMoneyAt.bitcoin,
          message: _errorText(e));
    }
    DateTime? sentAt;
    BitcoinLegTicket ticket;
    try {
      ticket = await env.send(
        sparkAddress: sparkAddress,
        plan: r.plan,
        stepUp: BitcoinLegGrants.stepUp(r.grant, ownSpark: sparkAddress),
        onSending: () {
          sentAt = clock();
          journey.bitcoinSent(venue);
        },
      );
    } catch (e) {
      _errors[id] = e;
      if (e is SettlementFundingUnknown) {
        // The sats may have left: never resend, never place. The
        // reconciler resolves the leg; any dollars stay in Dollars.
        return stop(FundedOrderStage.ready, BitcoinFundedEnd.maybeSent,
            reason: 'maybe_sent',
            category: 'settlement_unknown',
            message: _l10n().settlementFundingUnknownBody);
      }
      return stop(FundedOrderStage.failed, BitcoinFundedEnd.notSent,
          reason: 'not_sent',
          category: TrackingService.errorCategory(e),
          moneyAt: FundedMoneyAt.bitcoin,
          message: _errorText(e));
    }
    sentAt ??= clock();
    orders.addBtcRow(id, ticket.quoteId);
    var legId = ticket.orderId ?? ticket.quoteId;
    if (ticket.orderId != null) orders.addBtcRow(id, ticket.orderId!);
    final registration = ticket.registration;
    if (registration != null) {
      unawaited(registration.then((orderId) {
        if (orderId == null || orderId.isEmpty) return;
        legId = orderId;
        orders.addBtcRow(id, orderId);
      }).catchError((Object _) {}));
    }

    // 2. Wait for the dollars, as fast as the app can know.
    final landing = await env.watcher(since: sentAt!).watch(
          id: () => legId,
          baselineUsd: baseline,
          // At least what the quote said lands, less a cent of rounding.
          minRiseUsd: math.max(0.01, ticket.minOutUsd - 0.01),
          // The leg's own target landed: what the button named.
          enoughUsd: baseline + r.plan.targetUsd - 0.01,
          onSlow: () => orders.update(id, (rec) => rec.copyWith(slow: true)),
        );
    switch (landing) {
      case DollarsLegFailed():
        return stop(FundedOrderStage.failed, BitcoinFundedEnd.refunded,
            reason: 'refunded',
            category: 'refunded',
            moneyAt: FundedMoneyAt.bitcoin,
            message: _l10n().slipFundingBitcoinBack);
      case DollarsLandingTimedOut():
        // Never placed later at a price nobody saw: the order goes, the
        // dollars land in Dollars whenever they do.
        return stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
            reason: 'timeout',
            category: 'timeout',
            moneyAt: FundedMoneyAt.investments);
      case DollarsLanded(:final freshDollarsUsd):
        final landedAt = clock();
        journey.bitcoinLanded(venue);
        orders.update(id,
            (rec) => rec.copyWith(stage: FundedOrderStage.preparing, slow: false));
        // 3. Dollars → the venue under the same grant. The controller's
        // own Dollars check is the guard; it reads the fresh balance.
        final base = _ref.read(orderFundingControllerProvider);
        final controller = base.withDollars(
            () => math.max(env.dollarsNow(), freshDollarsUsd));
        OrderFundingOutcome outcome;
        try {
          outcome = await r.fundVenue(controller,
              bitcoinSentAt: sentAt!, bitcoinLandedAt: landedAt);
        } catch (e) {
          outcome = OrderFundingRefused(TrackingService.errorCategory(e),
              error: e);
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
            if (error != null) _errors[id] = error;
            // Nothing left Dollars: the money is there, the order is not.
            orders.stop(id,
                stage: FundedOrderStage.ready,
                reason: 'venue_refused',
                moneyAt: FundedMoneyAt.investments);
            journey.failed(venue, OrderFundingStage.fund, reason);
            try {
              r.dropOrder();
            } catch (_) {}
            return BitcoinFundedEnd.ready;
          case OrderFundingNeedsDollars():
            orders.stop(id,
                stage: FundedOrderStage.ready,
                reason: 'venue_refused',
                moneyAt: FundedMoneyAt.investments);
            journey.failed(venue, OrderFundingStage.fund, 'insufficient_funds');
            try {
              r.dropOrder();
            } catch (_) {}
            return BitcoinFundedEnd.ready;
        }
        // 4. The venue's autofire places the order at a fresh price.
        String? failedText;
        String? failedCode;
        final wait = r.awaitPlacement ??
            _placementWait(venue, onFailed: (message, code) {
              failedText = message;
              failedCode = code;
            });
        final placed = await wait(onCredited: () {
          orders.setStage(id, FundedOrderStage.placing);
        });
        if (placed) {
          orders.setStage(id, FundedOrderStage.done);
          return BitcoinFundedEnd.placed;
        }
        // The money reached the venue (or is on its way there): it stays
        // as its cash, available.
        orders.stop(id,
            stage: FundedOrderStage.failed,
            reason: failedCode ?? 'placement',
            moneyAt: FundedMoneyAt.venue,
            message: failedText);
        return BitcoinFundedEnd.placementFailed;
    }
  }

  /// An order funded from Dollars alone (no Bitcoin leg): its move left
  /// Dollars as [move]. Recorded so the Investments header names the
  /// order instead of the move, and followed to its end. Never throws.
  void followDollarsFunded(FundedOrderLabel label, VenueMoveResult move) =>
      followFunded(beginFunded(label), move: move);

  /// An order funded from Dollars or the other venue's cash, recorded the
  /// moment the person approved it ("Getting your prediction ready"), so
  /// the slip shows its steps from the first second and the Investments
  /// header names it while its money moves. Returns the record's id.
  String beginFunded(FundedOrderLabel label) => _ref
      .read(fundedOrdersProvider.notifier)
      .start(label, stage: FundedOrderStage.preparing);

  /// [id]'s money left for the venue as [move] (null: nothing had to
  /// move, or what moved is in [rowIds]): its rows name the order, and
  /// the venue's autofire is followed to the end (placing on the credit,
  /// then placed or stopped with the venue's own words). Never throws.
  void followFunded(String id,
      {VenueMoveResult? move, Set<String> rowIds = const {}}) {
    try {
      final orders = _ref.read(fundedOrdersProvider.notifier);
      final record = orders.byId(id);
      if (record == null || !record.stage.active) return;
      for (final row in {
        ...rowIds,
        if (move != null) move.quoteId,
        if (move?.orderId case final orderId?) orderId,
      }) {
        orders.addVenueRow(id, row);
      }
      final reg = move?.registration;
      if (reg != null) {
        unawaited(reg.then((orderId) {
          if (orderId != null && orderId.isNotEmpty) {
            orders.addVenueRow(id, orderId);
          }
        }).catchError((Object _) {}));
      }
      String? failedText;
      String? failedCode;
      unawaited(_placementWait(record.label.venue, onFailed: (message, code) {
        failedText = message;
        failedCode = code;
      })(onCredited: () {
        orders.setStage(id, FundedOrderStage.placing);
      }).then((placed) {
        if (placed) {
          orders.setStage(id, FundedOrderStage.done);
          return;
        }
        orders.stop(id,
            stage: FundedOrderStage.failed,
            reason: failedCode ?? 'placement',
            moneyAt: FundedMoneyAt.venue,
            message: failedText);
      }));
    } catch (_) {}
  }

  /// [id] stopped before its order could go, with the money at [moneyAt]
  /// ([message]: what the rail said). Never throws.
  void stopFunded(String id,
      {required String reason,
      FundedMoneyAt moneyAt = FundedMoneyAt.investments,
      String? message}) {
    try {
      _ref.read(fundedOrdersProvider.notifier).stop(id,
          stage: FundedOrderStage.failed,
          reason: reason,
          moneyAt: moneyAt,
          message: message);
    } catch (_) {}
  }

  /// Nothing happened for [id] after all (the approval went, or the
  /// button turns into the Add door): it is forgotten. Never throws.
  void dropFunded(String id) {
    try {
      _ref.read(fundedOrdersProvider.notifier).remove(id);
    } catch (_) {}
  }

  AppLocalizations _l10n() =>
      l10nForLanguage(_ref.read(settingsProvider).language);

  /// The words for a leg that was refused before anything left.
  String? _errorText(Object e) {
    try {
      return HotSettlement.messageFor(e, _l10n());
    } catch (_) {
      return null;
    }
  }

  /// Follows the venue's queued order to its end: placing is the credit,
  /// done (or awaiting the venue's confirmation) is placed, failed or
  /// cleared before either is not. [onFailed] hears the venue's own words
  /// and code when it failed.
  BitcoinPlacementWait _placementWait(OneBalanceVenue venue,
          {void Function(String? message, String? code)? onFailed}) =>
      ({required void Function() onCredited}) {
        final done = Completer<bool>();
        void end(bool placed) {
          if (!done.isCompleted) done.complete(placed);
        }

        late final ProviderSubscription<void> sub;
        switch (venue) {
          case OneBalanceVenue.investing:
            sub = _ref.listen<PendingHlOrderIntent?>(
                pendingHyperliquidOrderProvider, (_, next) {
              if (next == null) return end(false);
              switch (next.status) {
                case PendingHlOrderStatus.placing:
                  onCredited();
                case PendingHlOrderStatus.done:
                  end(true);
                case PendingHlOrderStatus.failed:
                  final message = next.errorMessage;
                  onFailed?.call(
                      message,
                      message != null && message == _l10n().hlFundsTimeout
                          ? 'funds_timeout'
                          : null);
                  end(false);
                case PendingHlOrderStatus.awaitingDeposit:
                case PendingHlOrderStatus.awaitingBalance:
                  break;
              }
            }, fireImmediately: true);
          case OneBalanceVenue.predictions:
            sub = _ref.listen<PendingBetIntent?>(pendingPolymarketBetProvider,
                (_, next) {
              if (next == null) return end(false);
              switch (next.status) {
                case PendingBetStatus.placing:
                  onCredited();
                case PendingBetStatus.done:
                case PendingBetStatus.awaitingConfirmation:
                  end(true);
                case PendingBetStatus.failed:
                  onFailed?.call(
                      next.errorMessage,
                      next.failureCode ??
                          (next.retryMaxPrice != null ? 'price_moved' : null));
                  end(false);
                case PendingBetStatus.awaitingDeposit:
                case PendingBetStatus.converting:
                case PendingBetStatus.awaitingBalance:
                  break;
              }
            }, fireImmediately: true);
        }
        return done.future.whenComplete(sub.close);
      };
}

final bitcoinFundedOrderRunnerProvider = Provider<BitcoinFundedOrderRunner>(
    (ref) => BitcoinFundedOrderRunner(ref));

// ── Sizing from the wallet ─────────────────────────────────────────────

/// Test seam: stands in for the route's estimate of a Bitcoin leg.
@visibleForTesting
Future<double?> Function(int sats)? debugBitcoinLegEstimate;

/// Test seam: stands in for the fresh read of the spending wallet's
/// bitcoin (the SDK's `getInfo`) and the bitcoin price (a rates refresh).
/// Null from it means nothing could be read.
@visibleForTesting
Future<SpendingBitcoin?> Function()? debugFreshSpendingBitcoin;

/// The spending wallet's Spark bitcoin, in sats, and the app's bitcoin
/// price in dollars. A read, never sent anywhere.
typedef SpendingBitcoin = ({int sats, double usdPerBtc});

/// A bitcoin price a leg can be sized on. The rates read before their BTC
/// entry is known value 1 BTC at about $1 (`CurrencyState.convert`),
/// which is no price at all.
bool isUsableUsdPerBtc(double usdPerBtc) =>
    usdPerBtc.isFinite && usdPerBtc > 1000 && usdPerBtc < 10000000;

/// The spending wallet's bitcoin and price as the app holds them now (the
/// balance cache, send holds applied; the rates). Zero when unknown.
SpendingBitcoin cachedSpendingBitcoin(
    T Function<T>(ProviderListenable<T> provider) read) {
  var rate = 0.0;
  var sats = 0;
  try {
    rate = read(selectedCurrencyProvider('USD')).toDouble();
  } catch (_) {}
  try {
    final spending = pickSpendingWallet(read(settingsProvider));
    sats = spending == null
        ? 0
        : read(walletBalanceCacheProvider)[spending.id]?.sparkBitcoinbalance ??
            0;
  } catch (_) {}
  return (sats: sats, usdPerBtc: isUsableUsdPerBtc(rate) ? rate : 0.0);
}

/// The spending wallet's bitcoin read fresh, for a tap whose cached
/// figures do not cover the leg (the balance not synced yet on a cold
/// start, the price not loaded): the SDK's own `getInfo`, written through
/// the balance cache so its send holds still apply, and a rates refresh
/// when there is no usable price. Null when there is no spending wallet.
/// Never throws.
Future<SpendingBitcoin?> freshSpendingBitcoin(
    T Function<T>(ProviderListenable<T> provider) read) async {
  final seam = debugFreshSpendingBitcoin;
  if (seam != null) return seam();
  String? walletId;
  try {
    walletId = pickSpendingWallet(read(settingsProvider))?.id;
  } catch (_) {}
  if (walletId == null || walletId.isEmpty) return null;
  final spendingId = walletId;
  final cached = cachedSpendingBitcoin(read);
  Future<void> refreshPrice() async {
    try {
      await read(currencyProvider.notifier)
          .updateRates()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<void> refreshSats() async {
    try {
      final wrapper = await read(breezSDKProvider.future)
          .timeout(const Duration(seconds: 8));
      final sdk = wrapper.instance;
      if (sdk == null) return;
      final info = await sdk
          .getInfo(request: const GetInfoRequest())
          .timeout(const Duration(seconds: 4));
      // Only the wallet that was asked about.
      if (pickSpendingWallet(read(settingsProvider))?.id != spendingId) return;
      read(walletBalanceCacheProvider.notifier)
          .updateSparkBitcoinbalance(spendingId, info.balanceSats.toInt());
    } catch (_) {}
  }

  await Future.wait<void>([
    if (!isUsableUsdPerBtc(cached.usdPerBtc)) refreshPrice(),
    refreshSats(),
  ]);
  return cachedSpendingBitcoin(read);
}

/// The route's estimate of what [sats] of spending bitcoin land in
/// Dollars, or null when it does not answer within a few seconds.
Future<double?> _bitcoinLegEstimate(int sats) async {
  try {
    final seam = debugBitcoinLegEstimate;
    if (seam != null) return await seam(sats);
    final result = await OrchestraService.getEstimate(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: kOrchestraUsdChain,
      destinationAsset: kOrchestraUsdAssetCode,
      amount: sats.toString(),
    ).timeout(const Duration(seconds: 4));
    final OrchestraEstimate? est = result.data;
    if (est == null) return null;
    return orchestraAmountToDouble(est.estimatedOut, kOrchestraUsdAssetCode,
        chain: kOrchestraUsdChain);
  } catch (_) {
    return null;
  }
}

/// The leg [dollarsShortUsd] needs from [wallet]: sized on the route's own
/// estimate for that leg (its real spread, with the arrival buffer), or on
/// [BitcoinLegRules.fallbackSpread] only when the estimate does not
/// answer. The estimate is asked whether or not the fallback would fit,
/// so bitcoin that covers the leg at the route's real price is never
/// refused for a margin.
Future<BitcoinLegSizing> _sizeOn(
    SpendingBitcoin wallet, double dollarsShortUsd) async {
  if (wallet.sats <= 0) {
    return const BitcoinLegSizing.refused(
        BitcoinLegRefusal.insufficientBitcoin);
  }
  final rate = wallet.usdPerBtc;
  if (!isUsableUsdPerBtc(rate)) {
    return const BitcoinLegSizing.refused(BitcoinLegRefusal.noPrice);
  }
  final target = BitcoinLegRules.targetUsd(dollarsShortUsd);
  if (target <= 0) {
    return const BitcoinLegSizing.refused(
        BitcoinLegRefusal.insufficientBitcoin);
  }
  // Asked at what the fallback would send: an estimate is a read and
  // never needs the sats to be there.
  final probe = BitcoinLegRules.probeSats(target, usdPerBtc: rate);
  final estimatedOut = await _bitcoinLegEstimate(probe);
  return BitcoinLegRules.size(
    dollarsShortUsd: dollarsShortUsd,
    usdPerBtc: rate,
    availableSats: wallet.sats,
    estimate: estimatedOut == null ||
            !estimatedOut.isFinite ||
            estimatedOut <= 0
        ? null
        : (sats: probe, estimatedOutUsd: estimatedOut),
  );
}

/// The spending wallet's bitcoin and price, and the leg [dollarsShortUsd]
/// needs, sized on the route's own estimate when it answers within a few
/// seconds. When the figures the app holds do not cover it (or there is
/// no usable price), they are read fresh ([freshSpendingBitcoin]) and the
/// leg is sized again: a refusal always stands on the wallet's own
/// answer. A read: nothing is quoted or moved.
Future<BitcoinLegSizing> sizeBitcoinLegFor(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double dollarsShortUsd,
}) async {
  final cached = cachedSpendingBitcoin(read);
  final first = await _sizeOn(cached, dollarsShortUsd);
  if (first.plan != null) return first;
  final fresh = await freshSpendingBitcoin(read);
  if (fresh == null || fresh == cached) return first;
  return _sizeOn(fresh, dollarsShortUsd);
}

// ── The slip's decision ────────────────────────────────────────────────

/// Where a hot slip's tap goes when the whole Investments balance lacks X
/// for the order's move. One decision for the Predictions and the
/// Investing slip ([decideSlipFunding]).
enum SlipFundingRoute {
  /// The spending bitcoin covers X: one approval, then Bitcoin → Dollars →
  /// venue → order ([BitcoinFundedOrderRunner]).
  bitcoin,

  /// The bitcoin genuinely does not cover X (none, or too little once the
  /// route's spread is counted): money has to come from outside, so the
  /// slip opens the Investments Receive sheet, never the Bitcoin Move
  /// sheet.
  insufficient,

  /// Nothing could tell (no bitcoin price, even read fresh): no sheet
  /// opens and nothing moves; the slip says it did not go through.
  unavailable,
}

/// [SlipFundingRoute] for an X of [addUsd], with the sized leg when the
/// bitcoin covers it.
@immutable
class SlipFundingDecision {
  const SlipFundingDecision.bitcoin(BitcoinLegPlan this.plan, this.addUsd)
      : route = SlipFundingRoute.bitcoin;
  const SlipFundingDecision.insufficient(this.addUsd)
      : route = SlipFundingRoute.insufficient,
        plan = null;
  const SlipFundingDecision.unavailable(this.addUsd)
      : route = SlipFundingRoute.unavailable,
        plan = null;

  final SlipFundingRoute route;

  /// X: what the order's move lacks, exactly as the button names it.
  final double addUsd;

  /// The Bitcoin leg for X ([SlipFundingRoute.bitcoin] only).
  final BitcoinLegPlan? plan;

  @override
  String toString() => 'SlipFundingDecision(${route.name}, $addUsd)';
}

/// Test seam: stands in for the chain a slip's "Add" starts once
/// [decideSlipFunding] says bitcoin (the slip's confirm, its one approval
/// and the runner).
@visibleForTesting
Future<void> Function(OneBalanceVenue venue, SlipFundingDecision decision)?
    debugStartSlipBitcoinChain;

/// Runs [debugStartSlipBitcoinChain] instead of the slip's chain when a
/// test set it; true when it did. Always false in the app.
Future<bool> slipBitcoinChainStoodIn(
    OneBalanceVenue venue, SlipFundingDecision decision) async {
  final seam = debugStartSlipBitcoinChain;
  if (seam == null) return false;
  await seam(venue, decision);
  return true;
}

/// Both slips' one decision for an X of [addUsd]: the Bitcoin leg sized on
/// the spending wallet's bitcoin, read fresh when the app's figures do not
/// cover it yet ([sizeBitcoinLegFor]). Bitcoin whenever it covers X;
/// insufficient only when it genuinely does not; unavailable when no
/// price could be read. Never throws, never moves anything.
Future<SlipFundingDecision> decideSlipFunding(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double addUsd,
}) async {
  if (!addUsd.isFinite || addUsd <= 0) {
    return SlipFundingDecision.insufficient(addUsd.isFinite ? addUsd : 0);
  }
  BitcoinLegSizing sizing;
  try {
    sizing = await sizeBitcoinLegFor(read, dollarsShortUsd: addUsd);
  } catch (_) {
    return SlipFundingDecision.unavailable(addUsd);
  }
  final plan = sizing.plan;
  if (plan != null) return SlipFundingDecision.bitcoin(plan, addUsd);
  return sizing.refusal == BitcoinLegRefusal.noPrice
      ? SlipFundingDecision.unavailable(addUsd)
      : SlipFundingDecision.insufficient(addUsd);
}

/// The wallet's own Spark address for a Bitcoin leg, waited on while the
/// SDK connects (a cold start takes seconds): null only when it cannot be
/// read within [timeout]. A slip holds the provider from when its "Add"
/// shows, so the tap normally finds it ready.
Future<String?> ownSparkForBitcoinLeg(
  T Function<T>(ProviderListenable<T> provider) read, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    final address =
        await read(sparkSelfAddressProvider.future).timeout(timeout);
    return address.isEmpty ? null : address;
  } catch (_) {
    return null;
  }
}
// ── The rest of the order: the one-balance planner ─────────────────────

/// What the rest of an order funded from bitcoin takes from the other
/// venue, worked out BEFORE the one approval: the Bitcoin leg lands
/// [addUsd] in Dollars, Dollars cover what they can, and the other
/// venue's cash covers the rest of [fundUsd] (the move into [venue]). The
/// legs that can go straight into [venue] are bound into the approval
/// ([directLegs], `VenueLimit.directLegs`); the others come home to
/// Dollars under the automatic authorization. Moves nothing.
class OtherVenuePlan {
  const OtherVenuePlan({
    required this.otherUsd,
    required this.covers,
    this.directLegs,
  });

  /// What the other venue gives. Zero when Dollars and the leg cover it.
  final double otherUsd;

  /// Dollars, the Bitcoin leg and the other venue together cover the move.
  final bool covers;

  /// What the one approval binds for the legs straight into the venue.
  final Map<String, Object?>? directLegs;
}

/// The destination a move into [venue] has.
VenueCashDestination venueCashDestinationOf(OneBalanceVenue venue) =>
    switch (venue) {
      OneBalanceVenue.investing => VenueCashDestination.investing,
      OneBalanceVenue.predictions => VenueCashDestination.predictions,
    };

/// The `for` value of a move into [venue].
String venueCashForOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.investing => VenueCashFor.investing,
      OneBalanceVenue.predictions => VenueCashFor.predictions,
    };

/// See [OtherVenuePlan]. [dollarsUsd] is what Dollars hold now (before the
/// leg lands).
Future<OtherVenuePlan> planOtherVenueCash(
  VenueCashPuller puller, {
  required OneBalanceVenue venue,
  required double fundUsd,
  required double addUsd,
  required double dollarsUsd,
}) async {
  final other = fundUsd - addUsd - dollarsUsd;
  if (other <= 0.005) {
    return const OtherVenuePlan(otherUsd: 0, covers: true);
  }
  final destination = venueCashDestinationOf(venue);
  // The puller counts Dollars itself: what it is asked for is the move
  // less what the leg lands.
  final plan = await puller.plan(
    neededUsd: fundUsd - addUsd,
    exclude: venue,
    destination: destination,
  );
  return OtherVenuePlan(
    otherUsd: ((other * 100) - 1e-9).ceilToDouble() / 100,
    covers: plan.covers,
    directLegs: puller.directLegLimit(plan, destination),
  );
}

/// After the Bitcoin leg's dollars landed: the other venue's cash for the
/// rest of [fundUsd] (the one-balance puller, under the order's same
/// [grant]: legs straight into [venue] within what it binds, the others
/// home to Dollars), then [queue] the venue move from Dollars for what the
/// direct legs do not bring. When Dollars still do not cover it, nothing
/// more moves and the order is not queued: the money stays in Investments.
Future<OrderFundingOutcome> fundRestThenMove({
  required VenueCashPuller puller,
  required OneBalanceVenue venue,
  required double fundUsd,
  required double readyUsd,
  required bool needsOtherVenue,
  required AuthGrant grant,
  required Future<OrderFundingOutcome> Function({
    required double fundUsd,
    required double readyUsd,
    required double directArrivingUsd,
    String? moveId,
  }) queue,
}) async {
  if (!needsOtherVenue) {
    return queue(fundUsd: fundUsd, readyUsd: readyUsd, directArrivingUsd: 0);
  }
  VenueCashPullOutcome? pulled;
  try {
    pulled = await puller.pullShortfall(
      neededUsd: fundUsd,
      forAction: venueCashForOf(venue),
      destination: venueCashDestinationOf(venue),
      exclude: venue,
      approval: grant,
    );
  } catch (e) {
    return OrderFundingRefused('venue_cash', error: e);
  }
  if (!pulled.dollarsCover) {
    return const OrderFundingRefused('venue_cash_pending');
  }
  final direct = pulled.directArrivingUsd + pulled.alreadyDeliveredUsd;
  return queue(
    fundUsd: direct > 0 ? math.max(0.0, pulled.dollarsNeededUsd) : fundUsd,
    readyUsd: readyUsd + direct,
    directArrivingUsd: pulled.directArrivingUsd,
    moveId: pulled.moveId,
  );
}
