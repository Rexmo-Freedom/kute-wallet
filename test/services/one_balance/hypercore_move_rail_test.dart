// The direct HyperCore rail between Dollars and Investing: estimates
// that name the move's recipient, the sweep's own-Spark-only rule, and a
// HyperCore-source route Orchestra refuses: the withdrawal to Dollars falls
// back to Circle CCTP, and only when that cannot run either it is reported
// as RouteUnavailable, before anything is signed or sent.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart'
    show HypercoreBalanceShortfall;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/money_movement_route.dart'
    show moneyMovementFailureReason, moneyMovementProvesNothingSent;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show InvestingWithdrawalDestination;
import 'package:kute/services/runtime_capabilities_service.dart'
    show CapabilityDecision, capabilityDenialFromResponse;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

const _eoa = '0x1111111111111111111111111111111111111111';
const _sparkSelf = 'sprt1qself';

/// The wallet's own Predictions deposit wallet.
const _pmWallet = '0x3333333333333333333333333333333333333333';

/// The Predictions account, already loaded with its deposit wallet.
class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(proxyWalletAddress: _pmWallet);
}

/// Flashnet's answer to every HyperCore-source quote today, as the quote
/// gate raises it (`unsupported_route` read through
/// [RouteQuoteErrorCode.fromCode]).
OrchestraQuoteFailure _refused() => OrchestraQuoteFailure(
      'HyperCore source routes require independent deposit verification '
      'and are unavailable',
      routeError:
          RouteQuoteError(RouteQuoteErrorCode.fromCode('unsupported_route')!),
    );

void main() {
  late ProviderContainer container;
  final asked = <RouteKey>[];
  final recipients = <String?>[];

  setUp(() {
    container = ProviderContainer(overrides: [
      hyperliquidAddressProvider.overrideWith((_) async => _eoa),
      sparkSelfAddressProvider.overrideWith((_) async => _sparkSelf),
    ]);
    addTearDown(container.dispose);
    asked.clear();
    recipients.clear();
  });

  HyperCoreMoveRail rail({
    HyperCoreRouteBounds? bounds,
    bool noEstimate = false,
    ProviderReader? read,
  }) =>
      HyperCoreMoveRail(
        read ?? container.read,
        estimate: (route, amount, recipient) async {
          asked.add(route);
          recipients.add(recipient);
          if (noEstimate) return null;
          return OrchestraEstimate.fromJson({
            // 24.90 HyperCore USDC (8 decimals) in, 24.85 USDB (6) out.
            'estimatedOut':
                route.toChain == 'hypercore' ? '2490000000' : '24850000',
            'feeAmount': '25000',
            'totalFeeAmount': '25000',
            'totalFeeAmountUsd': '0.025',
            'feeBps': 10,
          });
        },
        limits: (_) async => bounds,
        sendableUsd: (_) async => 14.75,
      );

  ProviderReader withService(SparkHypercoreFundingService service) {
    final scoped = ProviderContainer(overrides: [
      hyperliquidAddressProvider.overrideWith((_) async => _eoa),
      sparkSelfAddressProvider.overrideWith((_) async => _sparkSelf),
      polymarketTradingProvider.overrideWith(_Trading.new),
      sparkHypercoreFundingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(scoped.dispose);
    // Held for the test, as the sheet holds it: the autoDispose account
    // keeps its loaded deposit wallet between reads.
    scoped.listen(polymarketTradingProvider, (_, __) {});
    return scoped.read;
  }

  test('the provider binds the direct HyperCore rail', () {
    expect(
        container.read(hyperliquidMoveRailProvider), isA<HyperCoreMoveRail>());
  });

  test('estimates ask the direct HyperCore routes', () async {
    final deposit = await rail().estimate(usd: 25, deposit: true);
    expect(asked.single, kSparkUsdToHypercoreRoute);
    expect(deposit.arrivingUsd, 24.9);
    expect(deposit.feeUsd, 0.025);
    expect(deposit.fixedCostUsd, 0, reason: 'no gas float on HyperCore');
    expect(deposit.minUsd, kHyperCoreMinMoveUsd);
    final withdraw = await rail(bounds: (minUsd: 0.8, maxUsd: 96700))
        .estimate(usd: 25, deposit: false);
    expect(asked.last, kHypercoreToSparkUsdRoute);
    expect(withdraw.arrivingUsd, 24.85);
    expect(withdraw.maxUsd, 96700);
  });

  test('estimates name the address each move\'s quote pays', () async {
    // In: the Investing account, so an account Hyperliquid already knows
    // is not priced with the one-time activation.
    await rail().estimate(usd: 25, deposit: true);
    // Out: the own Spark address.
    await rail().estimate(usd: 25, deposit: false);
    expect(recipients, [_eoa, _sparkSelf]);
  });

  test('the route\'s limits are read beside the estimate, not after it',
      () async {
    final estimating = Completer<OrchestraEstimate?>();
    var limitsAsked = false;
    final quick = HyperCoreMoveRail(
      container.read,
      estimate: (route, amount, recipient) => estimating.future,
      limits: (_) async {
        limitsAsked = true;
        return (minUsd: 1.0, maxUsd: 500.0);
      },
    );
    final quote = quick.estimate(usd: 25, deposit: true);
    await Future<void>.delayed(Duration.zero);
    expect(limitsAsked, isTrue, reason: 'asked while the estimate is out');
    estimating.complete(OrchestraEstimate.fromJson({
      'estimatedOut': '2490000000',
      'feeAmount': '25000',
      'totalFeeAmount': '25000',
      'totalFeeAmountUsd': '0.025',
      'feeBps': 10,
    }));
    final q = await quote;
    expect(q.minUsd, 1.0);
    expect(q.maxUsd, 500.0);
  });

  test('no estimate (a refused route) is a route the rail cannot carry',
      () async {
    await expectLater(rail(noEstimate: true).estimate(usd: 5, deposit: false),
        throwsA(isA<RouteUnavailable>()));
  });

  test('the minimum is the live floor, else the 80 cents Orchestra sets',
      () async {
    expect(await rail().minimumUsd(deposit: true), kHyperCoreMinMoveUsd);
    expect(
        await rail(bounds: (minUsd: 1.5, maxUsd: null))
            .minimumUsd(deposit: false),
        1.5);
  });

  test('withdrawable is what the account can send, nothing without one',
      () async {
    expect(await rail().withdrawableUsd(), 14.75);
    final none = ProviderContainer(overrides: [
      hyperliquidAddressProvider.overrideWith((_) async => null),
    ]);
    addTearDown(none.dispose);
    expect(await rail(read: none.read).withdrawableUsd(), 0);
  });

  test('no gas float and no push signal', () async {
    await rail().ensureGasFloat();
    expect(await rail().credited.isEmpty, isTrue);
  });

  group('a sweep\'s authorization', () {
    SettlementAuthorizationIntent intent(RouteKey route,
            {String recipient = _sparkSelf}) =>
        SettlementAuthorizationIntent(
          flow: SettlementFlow.investingToSparkUsdDirect,
          walletId: 'w',
          destination: '$recipient|$kHypercoreToSparkUsdRouteVersion',
          routeLabel: route.label,
          amountIn: BigInt.from(1000000000),
          minReceive: BigInt.from(9900000),
          maxFeeBps: 10,
        );

    test('is accepted only for dollars home to the own Spark address',
        () async {
      final hook = rail().stepUpFor(SweepAuthorization.automatic);
      expect(await hook(intent(kHypercoreToSparkUsdRoute)), isTrue);
      expect(
          await hook(
              intent(kHypercoreToSparkUsdRoute, recipient: 'sprt1qother')),
          isFalse);
      expect(await hook(intent(kHypercoreToSparkRoute)), isFalse);
      expect(await hook(intent(kSparkUsdToHypercoreRoute)), isFalse);
    });
  });

  group('straight to the final destination', () {
    SettlementAuthorizationIntent intent(RouteKey route,
            {String recipient = _sparkSelf}) =>
        SettlementAuthorizationIntent(
          flow: SettlementFlow.investingToBtcCctp,
          walletId: 'w',
          destination: '$recipient|hypercore_cctp_to_spark_btc_v1',
          routeLabel: route.label,
          amountIn: BigInt.from(1200000000),
          minReceive: BigInt.from(1),
          maxFeeBps: 100,
        );

    AuthGrant approval({String to = 'bitcoin', double cap = 12}) =>
        AuthGrants.issue(
          SensitiveIntent(
            action: SensitiveAction.moveTransfer,
            walletId: 'w',
            venue: IntentVenue.orchestra,
            asset: 'USDB',
            amountMax: IntentUnits.usd(100),
            limits: {
              VenueLimit.directLegs: DirectLegGrants.limit(
                  destination: to, capsUsd: {'investing': cap}),
            },
          ),
          method: AuthGrantMethod.biometric,
        );

    test(
        'Bitcoin: unsupported native route uses CCTP with the same own-Spark rule',
        () async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final cctp = _FakeCctp();
      final native = _ScriptedService(container.read, _refused());
      final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
      final grant = approval();
      final result = await rail.withdrawDirect(
          destination: InvestingWithdrawalDestination.bitcoin,
          usd: 12,
          auth: ApprovedLegAuthorization(grant));
      expect(cctp.calls, ['bitcoin:cash_pull:12.0']);
      expect(result.operationId, 'op-direct');
      expect(result.quoteId, 'op-direct');
      final btc = cctpRouteFor(InvestingWithdrawalDestination.bitcoin);
      expect(await cctp.lastStepUp!(intent(btc, recipient: 'sprt1qother')),
          isFalse);
      expect(await cctp.lastStepUp!(intent(kHypercoreToSparkUsdRoute)),
          isFalse,
          reason: 'only the route it was asked for');
      expect(await cctp.lastStepUp!(intent(btc)), isTrue);
      expect(await cctp.lastStepUp!(intent(btc)), isFalse,
          reason: 'the leg cap is spent');
      expect(grant.consumed, isFalse, reason: 'the purchase consumes it');
      final submitted =
          events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_submitted');
      expect(submitted.$2?['destination'], 'btc');
      expect(submitted.$2?['route'], 'cctp');
    });

    test(
        'native Bitcoin success preserves its operation, registration and eight-decimal source amount',
        () async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final native = _ScriptedService(container.read, null);
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
      final grant = approval(cap: 5);
      final result = await rail.withdrawDirect(
          destination: InvestingWithdrawalDestination.bitcoin,
          usd: 5,
          auth: ApprovedLegAuthorization(grant),
          purpose: 'buy_bitcoin');
      expect(native.calls, ['withdraw:buy_bitcoin:bitcoin:5.0']);
      expect(cctp.calls, isEmpty);
      expect(result.operationId, 'op-direct');
      expect(result.quoteId, _verifiedQuote().quoteId);
      expect(result.orderId, 'ord_direct');
      expect(result.sentUsd, 5);
      expect(result.arrivingUsdEstimate, closeTo(4.975, 0.000000001),
          reason:
              'USD estimate uses actual source USD less the paid 50 bps, never BTC quantity');
      expect(await result.registration, 'ord_direct');
      final submitted = events
          .singleWhere((e) => e.$1 == 'hyperliquid_withdraw_submitted')
          .$2!;
      expect(submitted['route'], 'direct');
      expect(submitted['destination'], 'btc');
      expect(events.where((e) => e.$1 == 'hyperliquid_withdraw_step'), isEmpty);
      expect(await native.lastStepUp!(intent(kHypercoreToSparkRoute)), isFalse,
          reason: '12 USD cannot use a 5 USD cap');
    });

    test(
        'a missing Bitcoin pair opens CCTP once without spending the native grant',
        () async {
      const missing = SettlementStopped(SettlementStopReason.routeUnavailable,
          routeReason: RouteUnavailableReason.pairMissing);
      final native = _ScriptedService(container.read, missing);
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
      final grant = approval();
      await rail.withdrawDirect(
          destination: InvestingWithdrawalDestination.bitcoin,
          usd: 12,
          auth: ApprovedLegAuthorization(grant));
      expect(native.calls, hasLength(1));
      expect(cctp.calls, ['bitcoin:cash_pull:12.0']);
      expect(DirectLegGrants.takenBy(grant), BigInt.zero);
      expect(await cctp.lastStepUp!(intent(kHypercoreToSparkRoute)), isTrue);
      expect(await cctp.lastStepUp!(intent(kHypercoreToSparkRoute)), isFalse);
    });

    SettlementAuthorizationIntent predictionsIntent(
            {String recipient = _pmWallet, int atoms = 1200000000}) =>
        SettlementAuthorizationIntent(
            flow: SettlementFlow.investingToPredictionsDirect,
            walletId: 'w',
            destination: '$recipient|$kHypercoreToPredictionsRouteVersion',
            routeLabel: kHypercoreToPredictionsRoute.label,
            amountIn: BigInt.from(atoms),
            minReceive: BigInt.one,
            maxFeeBps: 100);

    test(
        'Predictions: native HyperCore served goes native, never CCTP, and '
        'the leg approval accepts the native intent', () async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final native = _ScriptedService(container.read, null);
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
      final result = await rail.withdrawDirect(
          destination: InvestingWithdrawalDestination.predictions,
          usd: 12,
          auth: ApprovedLegAuthorization(approval(to: 'predictions')));
      expect(native.calls, ['withdraw:cash_pull:predictions:12.0']);
      expect(cctp.calls, isEmpty);
      expect(result.operationId, 'op-direct');
      expect(result.orderId, 'ord_direct');
      expect(result.sentUsd, 5, reason: 'eight-decimal HyperCore amount in');
      expect(result.arrivingUsdEstimate, 4.99,
          reason: 'Polygon USDC.e out is already dollars');
      final submitted = events
          .singleWhere((e) => e.$1 == 'hyperliquid_withdraw_submitted')
          .$2!;
      expect(submitted['route'], 'direct');
      expect(submitted['destination'], 'predictions');
      expect(events.where((e) => e.$1 == 'hyperliquid_withdraw_step'), isEmpty);
      // The native route carries the same label the CCTP route does.
      expect(kHypercoreToPredictionsRoute.label,
          cctpRouteFor(InvestingWithdrawalDestination.predictions).label);
      expect(await native.lastStepUp!(predictionsIntent(recipient: _eoa)),
          isFalse,
          reason: 'only the own Predictions account');
      expect(
          await native.lastStepUp!(SettlementAuthorizationIntent(
              flow: SettlementFlow.investingToPredictionsDirect,
              walletId: 'w',
              destination: '$_pmWallet|$kHypercoreToPredictionsRouteVersion',
              routeLabel: kHypercoreToSparkRoute.label,
              amountIn: BigInt.from(1200000000),
              minReceive: BigInt.one,
              maxFeeBps: 100)),
          isFalse,
          reason: 'only the Predictions route');
      expect(await native.lastStepUp!(predictionsIntent(atoms: 1200000001)),
          isFalse,
          reason: 'past the cap');
      expect(
          await native.lastStepUp!(predictionsIntent(
              recipient: _pmWallet.toUpperCase().replaceFirst('0X', '0x'))),
          isTrue);
      expect(await native.lastStepUp!(predictionsIntent()), isFalse,
          reason: 'the leg cap is spent');
    });

    for (final (name, refusal) in <(String, Object)>[
      (
        'the catalogue missing the pair',
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.pairMissing)
      ),
      ('the quote refusing the route', _refused()),
    ]) {
      test('Predictions: $name opens CCTP once, to Predictions', () async {
        final events = <(String, Map<String, Object?>?)>[];
        TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
        addTearDown(() => TrackingService.debugTrackObserver = null);
        final native = _ScriptedService(container.read, refusal);
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
        final grant = approval(to: 'predictions');
        final result = await rail.withdrawDirect(
            destination: InvestingWithdrawalDestination.predictions,
            usd: 12,
            auth: ApprovedLegAuthorization(grant));
        expect(native.calls, ['withdraw:cash_pull:predictions:12.0']);
        expect(cctp.calls, ['predictions:cash_pull:12.0']);
        expect(result.operationId, 'op-direct');
        expect(DirectLegGrants.takenBy(grant), BigInt.zero,
            reason: 'the refused native attempt spent nothing');
        expect(
            events
                .where((e) => e.$1 == 'hyperliquid_withdraw_step')
                .single
                .$2?['step'],
            'cctp_fallback');
        final submitted = events
            .singleWhere((e) => e.$1 == 'hyperliquid_withdraw_submitted')
            .$2!;
        expect(submitted['route'], 'cctp');
        expect(submitted['destination'], 'predictions');
        expect(events.where((e) => e.$1 == 'hyperliquid_withdraw_initiated'),
            hasLength(1));
        // The CCTP intent passes the same own-Predictions rule.
        final predictions =
            cctpRouteFor(InvestingWithdrawalDestination.predictions);
        expect(await cctp.lastStepUp!(intent(predictions, recipient: _eoa)),
            isFalse);
        expect(await cctp.lastStepUp!(intent(predictions, recipient: _pmWallet)),
            isTrue);
      });
    }

    test(
        'Predictions: a policy denial, a decline or an expiry on the native '
        'route never opens CCTP', () async {
      final denial = capabilityDenialFromResponse(403,
          '{"error":"feature_unavailable","capability":"polymarket.deposit",'
          '"reason":"country_blocked"}')!;
      for (final error in <Object>[
        OrchestraQuoteFailure('unsupported_route', denial: denial),
        const SettlementStopped(SettlementStopReason.declined),
        const SettlementStopped(SettlementStopReason.quoteExpired),
        const WalletGuardException(WalletGuardReason.quoteExpired),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.stale),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.paused),
        const OrchestraQuoteFailure('too small',
            routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)),
        const SettlementStopped(SettlementStopReason.blockedPending),
        SettlementFundingUnknown('operation', _refused()),
        const SocketException('offline'),
      ]) {
        final native = _ScriptedService(container.read, error);
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
        await expectLater(
            rail.withdrawDirect(
                destination: InvestingWithdrawalDestination.predictions,
                usd: 12,
                auth: ApprovedLegAuthorization(approval(to: 'predictions'))),
            throwsA(error is HypercoreFundingUnavailable ||
                    error is OrchestraQuoteFailure ||
                    (error is SettlementStopped &&
                        error.reason != SettlementStopReason.blockedPending)
                ? isA<SettlementFundingRefused>()
                    .having((e) => e.cause, 'cause', same(error))
                : same(error)),
            reason: '$error');
        expect(native.calls, ['withdraw:cash_pull:predictions:12.0']);
        expect(cctp.calls, isEmpty, reason: '$error');
      }
    });

    test(
        'a send the CCTP service proved never posted keeps its proof through '
        'both doors: not sent, the shortfall as its category', () async {
      final failed = <Map<String, Object?>?>[];
      TrackingService.debugTrackObserver = (event, params) {
        if (event == 'hyperliquid_withdraw_failed') failed.add(params);
      };
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final stop = SettlementFundingRefused(HypercoreBalanceShortfall());
      final cctp = _FakeCctp(error: stop);
      final rail = HyperCoreMoveRail(
          withService(_ScriptedService(container.read, _refused())),
          cctp: () => cctp);
      await expectLater(
          rail.withdrawDirect(
              destination: InvestingWithdrawalDestination.predictions,
              usd: 12,
              auth: ApprovedLegAuthorization(approval(to: 'predictions'))),
          throwsA(same(stop)));
      expect(failed.last?['reason'], 'insufficient_funds');
      expect(failed.last?['route'], 'cctp');
      await expectLater(
          rail.withdrawToDollars(
              usd: 12, auth: SweepAuthorization.automatic, purpose: 'sweep'),
          throwsA(same(stop)));
      expect(failed.last?['reason'], 'insufficient_funds');
      expect(failed.last?['route'], 'cctp');
      expect(cctp.calls, ['predictions:cash_pull:12.0', 'sweep:12.0']);
      // What a leg or the Move sheet reads from it once funding started.
      expect(moneyMovementProvesNothingSent(stop, fundingStarted: true), isTrue);
      expect(moneyMovementFailureReason(stop, fundingStarted: true), 'not_sent');
    });

    test(
        'native stops and ambiguous outcomes never trigger CCTP or a home detour',
        () async {
      for (final error in <Object>[
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.paused),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.flagOff),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.accountUnavailable),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.reverseNotReady),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.stale),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.noLiveData),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.decimalsMismatch),
        const SettlementStopped(SettlementStopReason.declined),
        const SettlementStopped(SettlementStopReason.blockedPending),
        const SettlementStopped(SettlementStopReason.quoteExpired),
        const OrchestraQuoteFailure('too small',
            routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)),
        const WalletGuardException(WalletGuardReason.recipientNotOwn),
        const WalletGuardException(WalletGuardReason.amountMismatch),
        const SocketException('offline'),
        SettlementFundingUnknown(
            'operation', StateError('after native submission')),
        SettlementFundingUnknown('operation', _refused()),
        StateError('ambiguous native failure'),
      ]) {
        final native = _ScriptedService(container.read, error);
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
        await expectLater(
            rail.withdrawDirect(
                destination: InvestingWithdrawalDestination.bitcoin,
                usd: 12,
                auth: ApprovedLegAuthorization(approval())),
            throwsA(error is HypercoreFundingUnavailable ||
                    error is OrchestraQuoteFailure ||
                    (error is SettlementStopped &&
                        error.reason != SettlementStopReason.blockedPending)
                ? isA<SettlementFundingRefused>()
                    .having((e) => e.cause, 'cause', same(error))
                : same(error)));
        expect(native.calls, ['withdraw:cash_pull:bitcoin:12.0']);
        expect(cctp.calls, isEmpty);
      }
    });

    test(
        'native authorization refusal cannot fall back or consume another source budget',
        () async {
      for (final review in [
        SettlementAuthorizationIntent(
            flow: SettlementFlow.investingToSparkDirect,
            walletId: 'other',
            destination: '$_sparkSelf|$kHypercoreToSparkRouteVersion',
            routeLabel: kHypercoreToSparkRoute.label,
            amountIn: BigInt.from(500000000),
            minReceive: BigInt.one,
            maxFeeBps: 100),
        SettlementAuthorizationIntent(
            flow: SettlementFlow.investingToSparkDirect,
            walletId: 'w',
            destination: 'other|$kHypercoreToSparkRouteVersion',
            routeLabel: kHypercoreToSparkRoute.label,
            amountIn: BigInt.from(500000000),
            minReceive: BigInt.one,
            maxFeeBps: 100),
        SettlementAuthorizationIntent(
            flow: SettlementFlow.investingToSparkDirect,
            walletId: 'w',
            destination: '$_sparkSelf|$kHypercoreToSparkRouteVersion',
            routeLabel: kHypercoreToSparkRoute.label,
            amountIn: BigInt.from(500000001),
            minReceive: BigInt.one,
            maxFeeBps: 100),
      ]) {
        final native =
            _ScriptedService(container.read, null, authorization: review);
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
        final grant = approval(cap: 5);
        await expectLater(
            rail.withdrawDirect(
                destination: InvestingWithdrawalDestination.bitcoin,
                usd: 5,
                auth: ApprovedLegAuthorization(grant)),
            throwsA(isA<SettlementFundingRefused>().having(
                (e) => e.cause,
                'cause',
                isA<SettlementStopped>().having((e) => e.reason, 'reason',
                    SettlementStopReason.declined))));
        expect(cctp.calls, isEmpty);
        expect(DirectLegGrants.takenBy(grant), BigInt.zero);
      }
    });

    test(
        'parallel real rail exposes only proven-unsent native stops for a fresh-approved Retry',
        () async {
      final failed = <Map<String, Object?>?>[];
      TrackingService.debugTrackObserver = (event, params) {
        if (event == 'hyperliquid_withdraw_failed') failed.add(params);
      };
      addTearDown(() => TrackingService.debugTrackObserver = null);
      for (final (stop, reason) in <(Object, String)>[
        (
          const HypercoreFundingUnavailable(
              HypercoreFundingUnavailableReason.paused),
          'paused'
        ),
        (
          const SettlementStopped(SettlementStopReason.declined),
          'settlement_declined'
        ),
        (
          const OrchestraQuoteFailure('below minimum',
              routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)),
          'amount_too_small'
        ),
      ]) {
        MultiSourceMoveStore.reset();
        DirectRouteRefusals.reset();
        final native = _ScriptedService(container.read, stop);
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
        final source = HyperliquidCashSource(rail,
            readGuard: () async => (positions: const <HlPerpPosition>[], openOrders: const <HlOpenOrder>[]),
            direct: (destination, usd, purpose, auth) => rail.withdrawDirect(
                destination: destination,
                usd: usd,
                purpose: purpose,
                auth: auth));
        final puller = VenueCashPuller(
            sources: [source],
            readDollars: () => 5,
            minimumUsd: (_) async => 1,
            walletId: () => 'w');
        const amount = 5.0;
        final plan = VenueCashPlan(
            neededUsd: 10,
            dollarsUsd: 5,
            pulls: [
              VenueCashPull(
                  venue: OneBalanceVenue.investing,
                  usd: amount,
                  arrivingUsd: amount,
                  eta: Duration.zero)
            ],
            covers: true,
            uncoveredUsd: 0,
            eta: Duration.zero);
        final original = approval(cap: amount);
        final outcome = await puller.pullShortfall(
            neededUsd: plan.neededUsd,
            forAction: VenueCashFor.buyBitcoin,
            destination: VenueCashDestination.bitcoin,
            approval: original,
            plan: plan,
            waitFor: Duration.zero,
            onStarted: MultiSourceMoveStore.markParallelPurchase);
        final move = MultiSourceMoveStore.get(outcome.moveId!)!;
        expect(move.provenUnsentLegs.single.venue, OneBalanceVenue.investing);
        expect(move.legs.single.uncertain, isFalse);
        expect(move.legs.single.error, 'not_sent');
        expect(failed.last?['reason'], reason);
        expect(failed.last?['route'], 'direct');
        expect(cctp.calls, isEmpty);
        expect(native.calls, ['withdraw:cash_pull:bitcoin:5.0'],
            reason: 'no automatic native retry or Dollars detour');
        final retryPlan = await puller.planRetry(move.id);
        expect(retryPlan!.pulls.single.usd, amount);
        original.revoke();
        native.error = null;
        final retried = await puller.retryMove(move.id,
            approval: approval(cap: amount), plan: retryPlan);
        expect(retried!.failedLegs, isEmpty);
        expect(native.calls, [
          'withdraw:cash_pull:bitcoin:5.0',
          'withdraw:cash_pull:bitcoin:5.0'
        ]);
        expect(cctp.calls, isEmpty);
        expect(MultiSourceMoveStore.get(move.id)!.provenUnsentLegs, isEmpty);
      }
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
    });

    test(
        'parallel real rail keeps unresolved native outcomes held without Retry',
        () async {
      for (final stop in <Object>[
        const SocketException('connection lost'),
        const SettlementStopped(SettlementStopReason.blockedPending),
        SettlementFundingUnknown('pending-native', _refused()),
      ]) {
        MultiSourceMoveStore.reset();
        DirectRouteRefusals.reset();
        final native = _ScriptedService(container.read, stop);
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(withService(native), cctp: () => cctp);
        final source = HyperliquidCashSource(rail,
            readGuard: () async => (positions: const <HlPerpPosition>[], openOrders: const <HlOpenOrder>[]),
            direct: (destination, usd, purpose, auth) => rail.withdrawDirect(
                destination: destination,
                usd: usd,
                purpose: purpose,
                auth: auth));
        final puller = VenueCashPuller(
            sources: [source],
            readDollars: () => 5,
            minimumUsd: (_) async => 1,
            walletId: () => 'w');
        final plan = VenueCashPlan(
            neededUsd: 10,
            dollarsUsd: 5,
            pulls: [
              VenueCashPull(
                  venue: OneBalanceVenue.investing,
                  usd: 5,
                  arrivingUsd: 5,
                  eta: Duration.zero)
            ],
            covers: true,
            uncoveredUsd: 0,
            eta: Duration.zero);
        final outcome = await puller.pullShortfall(
            neededUsd: 10,
            forAction: VenueCashFor.buyBitcoin,
            destination: VenueCashDestination.bitcoin,
            approval: approval(cap: 5),
            plan: plan,
            waitFor: Duration.zero,
            onStarted: MultiSourceMoveStore.markParallelPurchase);
        final move = MultiSourceMoveStore.get(outcome.moveId!)!;
        expect(move.provenUnsentLegs, isEmpty);
        expect(move.legs.single.uncertain, isTrue);
        expect(await puller.planRetry(move.id), isNull);
        expect(native.calls, ['withdraw:cash_pull:bitcoin:5.0']);
        expect(cctp.calls, isEmpty);
      }
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
    });

    test('native step-up binds wallet, recipient and all eight source decimals',
        () async {
      final hook = rail().stepUpForDirect(ApprovedLegAuthorization(approval()),
          InvestingWithdrawalDestination.bitcoin);
      SettlementAuthorizationIntent nativeIntent(
              {String wallet = 'w',
              String recipient = _sparkSelf,
              int atoms = 1200000000,
              int fee = 0}) =>
          SettlementAuthorizationIntent(
              flow: SettlementFlow.investingToSparkDirect,
              walletId: wallet,
              destination: '$recipient|$kHypercoreToSparkRouteVersion',
              routeLabel: kHypercoreToSparkRoute.label,
              amountIn: BigInt.from(atoms),
              sourceFeeBaseUnits: BigInt.from(fee),
              sourceFeeAsset: 'USDC',
              minReceive: BigInt.one,
              maxFeeBps: 100);
      expect(await hook(nativeIntent(wallet: 'other')), isFalse);
      expect(await hook(nativeIntent(recipient: 'other')), isFalse);
      expect(await hook(nativeIntent(atoms: 1200000001)), isFalse,
          reason: 'round up rather than hide a source sub-micro above the cap');
      expect(await hook(nativeIntent(fee: 1)), isFalse,
          reason:
              'usdSend has no separately paid fee; do not approve an unexpected charge');
      expect(await hook(nativeIntent()), isTrue);
      expect(await hook(nativeIntent()), isFalse,
          reason: 'same source allowance cannot pay twice');
    });

    test(
        'the automatic authorization never moves Investing cash anywhere '
        'but home to Dollars', () async {
      final rail = HyperCoreMoveRail(container.read);
      final btc = cctpRouteFor(InvestingWithdrawalDestination.bitcoin);
      expect(
          await rail.stepUpForDirect(SweepAuthorization.automatic,
              InvestingWithdrawalDestination.bitcoin)(intent(btc)),
          isFalse);
      expect(
          await rail.stepUpForDirect(SweepAuthorization.automatic,
              InvestingWithdrawalDestination.predictions)(intent(btc)),
          isFalse);
      // A leg approval never brings cash home either (that is the
      // automatic authorization's move).
      expect(
          await rail.stepUpFor(ApprovedLegAuthorization(approval()))(intent(
              kHypercoreToSparkUsdRoute)),
          isFalse);
    });

    test('a leg is accepted only within the approval that binds it',
        () async {
      final rail = HyperCoreMoveRail(container.read);
      final btc = cctpRouteFor(InvestingWithdrawalDestination.bitcoin);
      Future<bool> run(AuthGrant g) => rail.stepUpForDirect(
          ApprovedLegAuthorization(g),
          InvestingWithdrawalDestination.bitcoin)(intent(btc));
      expect(await run(approval(cap: 11.99)), isFalse, reason: 'past the cap');
      expect(await run(approval(to: 'predictions')), isFalse,
          reason: 'approved for another destination');
      final spent = approval();
      AuthGrants.consume(spent, spent.boundIntent);
      expect(await run(spent), isFalse, reason: 'the action already went');
      expect(await run(approval()..revoke()), isFalse);
    });

    test('a refusal before signing is a DirectRouteRefused', () async {
      final cctp = _FakeCctp(
          error:
              const CctpUnavailable(CctpUnavailableReason.feeTermsUnavailable));
      // Native first: Orchestra refuses the route, so CCTP runs and refuses
      // before signing.
      final rail = HyperCoreMoveRail(
          withService(_ScriptedService(container.read, _refused())),
          cctp: () => cctp);
      await expectLater(
          rail.withdrawDirect(
              destination: InvestingWithdrawalDestination.predictions,
              usd: 12,
              auth: SweepAuthorization.automatic),
          throwsA(isA<DirectRouteRefused>().having(
              (e) => e.reason, 'reason', 'cctp_fee_terms_unavailable')));
    });

    test('a failure after the signature is never a refusal', () async {
      final cctp = _FakeCctp(error: StateError('posted'));
      final rail = HyperCoreMoveRail(
          withService(_ScriptedService(container.read, _refused())),
          cctp: () => cctp);
      await expectLater(
          rail.withdrawDirect(
              destination: InvestingWithdrawalDestination.bitcoin,
              usd: 12,
              auth: SweepAuthorization.automatic),
          throwsA(isNot(isA<DirectRouteRefused>())));
    });
  });

  group('when Orchestra refuses the HyperCore-source route', () {
    test('Flashnet\'s unsupported_route reads as route_unavailable', () {
      expect(RouteQuoteErrorCode.fromCode('unsupported_route'),
          RouteQuoteErrorCode.routeUnavailable);
      expect(
          parseRouteQuoteErrorCode({
            'error': {
              'code': 'unsupported_route',
              'message': 'HyperCore source routes require independent '
                  'deposit verification and are unavailable',
            }
          }),
          RouteQuoteErrorCode.routeUnavailable);
    });

    test('the Move sheet says nothing was sent', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(HotSettlement.messageFor(_refused(), l10n),
          l10n.routeUnavailableNothingSent);
    });

    test('a sweep falls back to CCTP after the refusal', () async {
      final service = _ScriptedService(container.read, _refused());
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(withService(service), cctp: () => cctp);
      final result = await rail.withdrawToDollars(
          usd: 12, auth: SweepAuthorization.automatic, purpose: 'sweep');
      // The normal route is asked first; CCTP only after its refusal.
      expect(service.calls, ['withdraw:sweep:dollars:12.0']);
      expect(cctp.calls, ['sweep:12.0']);
      expect(result.quoteId, 'op-1');
      expect(result.orderId, isNull);
      expect(await result.registration, 'ord_cctp');
      expect(result.sentUsd, 12);
      expect(result.arrivingUsdEstimate, 11.8);
      // The sweep's step-up the fallback is handed is the own-Spark rule.
      final ok = await cctp.lastStepUp!(SettlementAuthorizationIntent(
        flow: SettlementFlow.investingToDollarsCctp,
        walletId: 'w',
        destination: '$_sparkSelf|hypercore_cctp_to_spark_usd_v1',
        routeLabel: kHypercoreToSparkUsdRoute.label,
        amountIn: BigInt.from(1200000000),
        minReceive: BigInt.from(11000000),
        maxFeeBps: 100,
      ));
      expect(ok, isTrue);
      final stranger = await cctp.lastStepUp!(SettlementAuthorizationIntent(
        flow: SettlementFlow.investingToDollarsCctp,
        walletId: 'w',
        destination: 'sprt1qother|hypercore_cctp_to_spark_usd_v1',
        routeLabel: kHypercoreToSparkUsdRoute.label,
        amountIn: BigInt.from(1200000000),
        minReceive: BigInt.from(11000000),
        maxFeeBps: 100,
      ));
      expect(stranger, isFalse);
    });

    test('CCTP that cannot run either leaves the cash waiting', () async {
      final service = _ScriptedService(container.read, _refused());
      final cctp = _FakeCctp(
          error: const CctpUnavailable(CctpUnavailableReason.belowMinimum));
      final rail = HyperCoreMoveRail(withService(service), cctp: () => cctp);
      await expectLater(
          rail.withdrawToDollars(
              usd: 0.9, auth: SweepAuthorization.automatic, purpose: 'sweep'),
          throwsA(isA<RouteUnavailable>()
              .having((e) => e.reason, 'reason', 'cctp_below_minimum')));
      expect(cctp.calls, ['sweep:0.9']);
    });

    test('a withheld hyperliquid.withdraw leaves the cash waiting until the '
        'switch is back', () async {
      final service = _ScriptedService(container.read, _refused());
      final cctp = _FakeCctp(
          error: const CctpUnavailable(CctpUnavailableReason.capability,
              decision:
                  CapabilityDecision(allowed: false, reason: 'disabled')));
      final rail = HyperCoreMoveRail(withService(service), cctp: () => cctp);
      await expectLater(
          rail.withdrawToDollars(
              usd: 12, auth: SweepAuthorization.automatic, purpose: 'sweep'),
          throwsA(isA<RouteUnavailable>()
              .having((e) => e.reason, 'reason', 'cctp_capability')));
      // The switch comes back: the next pass moves the cash, nothing held.
      cctp.error = null;
      final result = await rail.withdrawToDollars(
          usd: 12, auth: SweepAuthorization.automatic, purpose: 'sweep');
      expect(result.sentUsd, 12);
      expect(cctp.calls, ['sweep:12.0', 'sweep:12.0']);
    });

    test('only a route refusal opens the fallback', () async {
      for (final error in <Object>[
        const OrchestraQuoteFailure('too small',
            routeError: RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)),
        const OrchestraQuoteFailure('quote expired'),
        const SettlementStopped(SettlementStopReason.routeUnavailable),
        const SettlementStopped(SettlementStopReason.blockedPending),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.paused),
      ]) {
        final cctp = _FakeCctp();
        final rail = HyperCoreMoveRail(
            withService(_ScriptedService(container.read, error)),
            cctp: () => cctp);
        await expectLater(
            rail.withdrawToDollars(usd: 5, auth: SweepAuthorization.automatic),
            throwsA(anything),
            reason: '$error');
        expect(cctp.calls, isEmpty, reason: '$error');
      }
    });

    test('the catalog listing no destination for HyperCore opens the '
        'fallback too', () async {
      // Flashnet's catalog lists `hypercore:USDC` with `to: []`: the
      // runner's availability check stops on the missing pair before any
      // quote is asked, so the quote's refusal is never seen.
      const missing = SettlementStopped(SettlementStopReason.routeUnavailable,
          routeReason: RouteUnavailableReason.pairMissing);
      expect(HyperCoreMoveRail.opensCctpFallback(missing), isTrue);
      final service = _ScriptedService(container.read, missing);
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(withService(service), cctp: () => cctp);
      final result = await rail.withdrawToDollars(
          usd: 6.54, auth: SweepAuthorization.automatic, purpose: 'sweep');
      expect(service.calls, ['withdraw:sweep:dollars:6.54']);
      expect(cctp.calls, ['sweep:6.54']);
      expect(result.sentUsd, 6.54);
    });

    test('a stale or unread catalog, a pause or a decline keep the stop',
        () {
      for (final error in <Object>[
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.stale),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.noLiveData),
        const SettlementStopped(SettlementStopReason.routeUnavailable,
            routeReason: RouteUnavailableReason.paused),
        const SettlementStopped(SettlementStopReason.declined),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.paused),
        StateError('boom'),
      ]) {
        expect(HyperCoreMoveRail.opensCctpFallback(error), isFalse,
            reason: '$error');
      }
      expect(HyperCoreMoveRail.opensCctpFallback(_refused()), isTrue);
    });

    test('the normal route is used when Orchestra accepts it', () async {
      final service = _ScriptedService(container.read, null);
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(withService(service), cctp: () => cctp);
      final result = await rail.withdrawToDollars(
          usd: 5, auth: SweepAuthorization.automatic, purpose: 'sweep');
      expect(service.calls, ['withdraw:sweep:dollars:5.0']);
      expect(cctp.calls, isEmpty);
      expect(result.orderId, 'ord_direct');
    });

    test('a route refusal named only in the text is still a refusal', () {
      expect(
          HyperCoreMoveRail.isRouteRefusal(const OrchestraQuoteFailure(
              'Unsupported route: unsupported_route')),
          isTrue);
      expect(
          HyperCoreMoveRail.isRouteRefusal(
              const OrchestraQuoteFailure('quote expired')),
          isFalse);
    });

    test('the runner\'s route stop and the service\'s own stops map too',
        () async {
      for (final error in <Object>[
        const SettlementStopped(SettlementStopReason.routeUnavailable),
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.paused),
      ]) {
        final rail = HyperCoreMoveRail(
            withService(_ScriptedService(container.read, error)),
            cctp: _FakeCctp.new);
        await expectLater(
            rail.withdrawToDollars(
                usd: 5,
                auth: SweepAuthorization.automatic,
                purpose: 'rollout_sweep'),
            throwsA(isA<RouteUnavailable>()),
            reason: '$error');
      }
    });

    test('an amount refusal reaches the sweeper as its RouteQuoteError',
        () async {
      final rail = HyperCoreMoveRail(withService(_ScriptedService(
          container.read,
          const OrchestraQuoteFailure('too small',
              routeError:
                  RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)))));
      await expectLater(
          rail.withdrawToDollars(usd: 0.5, auth: SweepAuthorization.automatic),
          throwsA(isA<RouteQuoteError>().having(
              (e) => e.code, 'code', RouteQuoteErrorCode.amountTooSmall)));
    });
  });

  group('a sweep reports the Investing withdrawal funnel', () {
    final events = <(String, Map<String, Object>?)>[];
    setUp(() {
      events.clear();
      TrackingService.debugTrackObserver = (e, p) {
        if (e.startsWith('hyperliquid_withdraw_')) events.add((e, p));
      };
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    List<String> names() => [for (final e in events) e.$1];
    Map<String, Object> only(String name) =>
        events.singleWhere((e) => e.$1 == name).$2!;

    test('direct: initiated then submitted, purpose sweep', () async {
      final rail = HyperCoreMoveRail(
          withService(_ScriptedService(container.read, null)),
          cctp: _FakeCctp.new);
      await rail.withdrawToDollars(
          usd: 5, auth: SweepAuthorization.automatic, purpose: 'sweep');
      expect(names(),
          ['hyperliquid_withdraw_initiated', 'hyperliquid_withdraw_submitted']);
      final initiated = only('hyperliquid_withdraw_initiated');
      expect(initiated['route'], 'direct');
      expect(initiated['purpose'], 'sweep');
      expect(initiated['destination'], 'usd');
      expect(initiated['amount_usd'], 5);
      final submitted = only('hyperliquid_withdraw_submitted');
      expect(submitted['route'], 'direct');
      expect(submitted['purpose'], 'sweep');
      expect(submitted['amount_usd'], 5);
      expect(submitted.containsKey('amount_bucket'), isFalse);
    });

    test('CCTP fallback: one initiated, the switch as a step, submitted '
        'with route cctp', () async {
      final rail = HyperCoreMoveRail(
          withService(_ScriptedService(container.read, _refused())),
          cctp: _FakeCctp.new);
      await rail.withdrawToDollars(
          usd: 12, auth: SweepAuthorization.automatic, purpose: 'rollout_sweep');
      expect(names(), [
        'hyperliquid_withdraw_initiated',
        'hyperliquid_withdraw_step',
        'hyperliquid_withdraw_submitted',
      ]);
      expect(only('hyperliquid_withdraw_initiated')['route'], 'direct');
      expect(only('hyperliquid_withdraw_step')['step'], 'cctp_fallback');
      expect(only('hyperliquid_withdraw_step')['route'], 'cctp');
      final submitted = only('hyperliquid_withdraw_submitted');
      expect(submitted['route'], 'cctp');
      expect(submitted['purpose'], 'rollout_sweep');
      expect(submitted['amount_usd'], 12);
      expect(submitted.containsKey('amount_bucket'), isFalse);
    });

    test('a stop before submission is a failed with its route', () async {
      final rail = HyperCoreMoveRail(
          withService(_ScriptedService(container.read, _refused())),
          cctp: () => _FakeCctp(
              error:
                  const CctpUnavailable(CctpUnavailableReason.belowMinimum)));
      await expectLater(
          rail.withdrawToDollars(
              usd: 0.9, auth: SweepAuthorization.automatic, purpose: 'sweep'),
          throwsA(isA<RouteUnavailable>()));
      expect(names(), [
        'hyperliquid_withdraw_initiated',
        'hyperliquid_withdraw_step',
        'hyperliquid_withdraw_failed',
      ]);
      final failed = only('hyperliquid_withdraw_failed');
      expect(failed['route'], 'cctp');
      expect(failed['purpose'], 'sweep');
      expect(failed['reason'], 'cctp_below_minimum');
      expect(failed['amount_usd'], 0.9);
    });

    test('an amount refusal on the direct route fails with route direct',
        () async {
      final rail = HyperCoreMoveRail(withService(_ScriptedService(
          container.read,
          const OrchestraQuoteFailure('too small',
              routeError:
                  RouteQuoteError(RouteQuoteErrorCode.amountTooSmall)))));
      await expectLater(
          rail.withdrawToDollars(usd: 0.5, auth: SweepAuthorization.automatic),
          throwsA(isA<RouteQuoteError>()));
      final failed = only('hyperliquid_withdraw_failed');
      expect(failed['route'], 'direct');
      expect(failed['reason'], RouteQuoteErrorCode.amountTooSmall.code);
      expect(only('hyperliquid_withdraw_initiated')['purpose'], 'sweep');
    });
  });

  test('a move\'s purpose reaches the funding service, both ways', () async {
    final service = _ScriptedService(
        container.read,
        const HypercoreFundingUnavailable(
            HypercoreFundingUnavailableReason.flagOff));
    final rail = HyperCoreMoveRail(withService(service));
    await expectLater(
        rail.depositDollars(
            usd: 10,
            amountBaseUnits: BigInt.from(10000000),
            purpose: 'order_funding'),
        throwsA(isA<RouteUnavailable>()));
    await expectLater(
        rail.withdrawToDollars(
            usd: 10,
            auth: SweepAuthorization.automatic,
            purpose: 'rollout_sweep'),
        throwsA(isA<RouteUnavailable>()));
    expect(service.calls, [
      'deposit:order_funding:dollars:10000000',
      'withdraw:rollout_sweep:dollars:10.0',
    ]);
  });
}

/// Records each move and stops it with [error], the way the real service
/// stops when the quote is refused: before the step-up and the send. A
/// null [error] is a route Orchestra accepted.
class _ScriptedService extends SparkHypercoreFundingService {
  _ScriptedService(super.read, this.error, {this.authorization});

  Object? error;
  final SettlementAuthorizationIntent? authorization;
  final calls = <String>[];
  SettlementStepUpHook? lastStepUp;

  @override
  Future<DirectHypercoreResult> depositFromSpark({
    required SparkFundingAsset asset,
    required BigInt amountBaseUnits,
    double? amountUsd,
    void Function()? onFundingStarted,
    SettlementStepUpHook? stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    calls.add('deposit:$purpose:${asset.name}:$amountBaseUnits');
    throw error!;
  }

  @override
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    calls.add('withdraw:$purpose:${destination.name}:$usd');
    lastStepUp = stepUp;
    expect(registerInBackground, isTrue);
    final failure = error;
    if (failure != null) throw failure;
    final review = authorization;
    if (review != null && !await stepUp(review)) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    return DirectHypercoreResult(
      run: SettlementRunResult(
        operation: SettlementOperation(
          operationId: 'op-direct',
          walletId: 'w',
          accountKind: SettlementAccountKind.hlHot,
          flow: SettlementFlow.investingToSparkUsdDirect,
          route: kHypercoreToSparkUsdRoute,
          amountInBaseUnits: '500000000',
          stage: SettlementStage.funded,
          createdAt: DateTime.utc(2026, 10, 13),
          updatedAt: DateTime.utc(2026, 10, 13),
        ),
        quote: _verifiedQuote(nativeBitcoin: destination.isBitcoin),
        proof: const SettlementFundingProof.hyperliquid('0xhash'),
        orderId: 'ord_direct',
        registration: Future.value('ord_direct'),
      ),
      amountIn: BigInt.from(500000000),
      estimatedOut: destination.isBitcoin ? 0.00008317 : 4.99,
    );
  }

  @override
  Future<DirectHypercoreResult> withdrawToPredictions({
    required double usd,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    calls.add('withdraw:$purpose:predictions:$usd');
    lastStepUp = stepUp;
    expect(registerInBackground, isTrue);
    final failure = error;
    if (failure != null) throw failure;
    return DirectHypercoreResult(
      run: SettlementRunResult(
        operation: SettlementOperation(
          operationId: 'op-direct',
          walletId: 'w',
          accountKind: SettlementAccountKind.hlHot,
          flow: SettlementFlow.investingToPredictionsDirect,
          route: kHypercoreToPredictionsRoute,
          amountInBaseUnits: '500000000',
          stage: SettlementStage.funded,
          createdAt: DateTime.utc(2026, 10, 19),
          updatedAt: DateTime.utc(2026, 10, 19),
        ),
        quote: _verifiedQuote(),
        proof: const SettlementFundingProof.hyperliquid('0xhash'),
        orderId: 'ord_direct',
        registration: Future.value('ord_direct'),
      ),
      amountIn: BigInt.from(500000000),
      estimatedOut: 4.99,
    );
  }
}

/// A verified quote: the rail retains its id and uses its paid fee for the
/// BTC destination's USD source-value estimate.
VerifiedOrchestraQuote _verifiedQuote({bool nativeBitcoin = false}) {
  final json = jsonDecode(
      File('test/services/fixtures/orchestra_quote_polygon_to_spark.json')
          .readAsStringSync()) as Map<String, dynamic>;
  if (nativeBitcoin) {
    json.addAll({
      'amountIn': '500000000', // $5 HyperCore USDC (eight decimals).
      'estimatedOut': '8317', // BTC base units, not a dollar figure.
      'feeBps': 50,
      'route': ['hypercore:USDC', 'spark:BTC'],
    });
  }
  final source = nativeBitcoin ? 'hypercore' : 'polygon';
  return verifyOrchestraQuote(
    OrchestraQuoteRequest(
      sourceChain: source,
      sourceAsset: nativeBitcoin ? 'USDC' : 'USDC.e',
      destinationChain: 'spark',
      destinationAsset: 'BTC',
      amountBaseUnits: BigInt.from(nativeBitcoin ? 500000000 : 50000000),
      recipientAddress: _ownSpark,
      refundAddress: '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      recipientKind: RecipientKind.ownSpark,
      ownAddress: _ownSpark,
    ),
    OrchestraQuote.fromJson(json),
    now: DateTime.utc(2026, 9, 15, 12),
    bounds: OrchestraQuoteBounds.forSource(source,
        inputValueInOutputUnits: nativeBitcoin ? 8359 : 83333),
    mainnet: true,
  );
}

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';

/// The CCTP fallback, scripted.
class _FakeCctp implements HypercoreCctpWithdrawal {
  _FakeCctp({this.error});

  Object? error;
  final calls = <String>[];
  SettlementStepUpHook? lastStepUp;

  @override
  Future<CctpWithdrawalResult> withdrawToDollars({
    required double usd,
    required SettlementStepUpHook stepUp,
    String purpose = 'manual_move',
  }) async {
    calls.add('$purpose:$usd');
    lastStepUp = stepUp;
    final failure = error;
    if (failure != null) throw failure;
    return CctpWithdrawalResult(
      operationId: 'op-1',
      sentUsd: usd,
      arrivingUsdEstimate: usd - 0.2,
      registration: Future.value('ord_cctp'),
    );
  }

  @override
  Future<CctpWithdrawalResult> withdrawTo({
    required InvestingWithdrawalDestination destination,
    required double usd,
    required SettlementStepUpHook stepUp,
    String purpose = 'manual_move',
  }) async {
    calls.add('${destination.name}:$purpose:$usd');
    lastStepUp = stepUp;
    final failure = error;
    if (failure != null) throw failure;
    return CctpWithdrawalResult(
      operationId: 'op-direct',
      sentUsd: usd,
      arrivingUsdEstimate: usd - 0.2,
      registration: Future.value('ord_direct'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
