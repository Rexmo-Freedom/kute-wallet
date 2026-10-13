// The direct HyperCore rail between Dollars and Investing: estimates
// that name the move's recipient, the sweep's own-Spark-only rule, and a
// HyperCore-source route Orchestra refuses: the withdrawal to Dollars falls
// back to Circle CCTP, and only when that cannot run either it is reported
// as RouteUnavailable, before anything is signed or sent.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show InvestingWithdrawalDestination;
import 'package:kute/services/runtime_capabilities_service.dart'
    show CapabilityDecision;
import 'package:kute/services/tracking_service.dart';

const _eoa = '0x1111111111111111111111111111111111111111';
const _sparkSelf = 'sprt1qself';

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

  ProviderReader withService(SparkHypercoreFundingService service) =>
      ProviderContainer(overrides: [
        hyperliquidAddressProvider.overrideWith((_) async => _eoa),
        sparkSelfAddressProvider.overrideWith((_) async => _sparkSelf),
        sparkHypercoreFundingServiceProvider.overrideWithValue(service),
      ]).read;

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

  group('straight to the final destination by CCTP', () {
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

    test('Bitcoin: CCTP with the own-Spark rule for the BTC route', () async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final cctp = _FakeCctp();
      final rail = HyperCoreMoveRail(container.read, cctp: () => cctp);
      final result = await rail.withdrawDirect(
          destination: InvestingWithdrawalDestination.bitcoin,
          usd: 12,
          auth: SweepAuthorization.automatic);
      expect(cctp.calls, ['bitcoin:cash_pull:12.0']);
      expect(result.operationId, 'op-direct');
      expect(result.quoteId, 'op-direct');
      final btc = cctpRouteFor(InvestingWithdrawalDestination.bitcoin);
      expect(await cctp.lastStepUp!(intent(btc)), isTrue);
      expect(await cctp.lastStepUp!(intent(btc, recipient: 'sprt1qother')),
          isFalse);
      expect(await cctp.lastStepUp!(intent(kHypercoreToSparkUsdRoute)),
          isFalse,
          reason: 'only the route it was asked for');
      final submitted =
          events.singleWhere((e) => e.$1 == 'hyperliquid_withdraw_submitted');
      expect(submitted.$2?['destination'], 'btc');
      expect(submitted.$2?['route'], 'cctp');
    });

    test('a refusal before signing is a DirectRouteRefused', () async {
      final cctp = _FakeCctp(
          error:
              const CctpUnavailable(CctpUnavailableReason.feeTermsUnavailable));
      final rail = HyperCoreMoveRail(container.read, cctp: () => cctp);
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
      final rail = HyperCoreMoveRail(container.read, cctp: () => cctp);
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
  _ScriptedService(super.read, this.error);

  final Object? error;
  final calls = <String>[];

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
    expect(registerInBackground, isTrue);
    final failure = error;
    if (failure != null) throw failure;
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
        quote: _verifiedQuote(),
        proof: const SettlementFundingProof.hyperliquid('0xhash'),
        orderId: 'ord_direct',
      ),
      amountIn: BigInt.from(500000000),
      estimatedOut: 4.99,
    );
  }
}

/// Any verified quote: the rail reads only its id.
VerifiedOrchestraQuote _verifiedQuote() => verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'polygon',
        sourceAsset: 'USDC.e',
        destinationChain: 'spark',
        destinationAsset: 'BTC',
        amountBaseUnits: BigInt.from(50000000),
        recipientAddress: _ownSpark,
        refundAddress: '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
        recipientKind: RecipientKind.ownSpark,
        ownAddress: _ownSpark,
      ),
      OrchestraQuote.fromJson(jsonDecode(
          File('test/services/fixtures/orchestra_quote_polygon_to_spark.json')
              .readAsStringSync()) as Map<String, dynamic>),
      now: DateTime.utc(2026, 9, 15, 12),
      bounds: OrchestraQuoteBounds.forSource('polygon',
          inputValueInOutputUnits: 83333),
      mainnet: true,
    );

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
