// The direct HyperCore rail between Dollars and Investing: estimates
// that name the move's recipient, the sweep's own-Spark-only rule, and a
// HyperCore-source route Orchestra refuses reported as RouteUnavailable
// before anything is signed or sent.

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
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';

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

    test('a sweep stops as RouteUnavailable with nothing signed', () async {
      final service = _ScriptedService(container.read, _refused());
      final rail = HyperCoreMoveRail(withService(service));
      await expectLater(
          rail.withdrawToDollars(
              usd: 12, auth: SweepAuthorization.automatic, purpose: 'sweep'),
          throwsA(isA<RouteUnavailable>()));
      expect(service.calls, ['withdraw:sweep:dollars:12.0']);
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
            withService(_ScriptedService(container.read, error)));
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
/// stops when the quote is refused: before the step-up and the send.
class _ScriptedService extends SparkHypercoreFundingService {
  _ScriptedService(super.read, this.error);

  final Object error;
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
    throw error;
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
    throw error;
  }
}
