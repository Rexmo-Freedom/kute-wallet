import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_released.dart';

import '../../helpers/fake_swap_orders.dart';

class _UninitializedHl extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState();
}

class _UninitializedPm extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

void main() {
  group('OneBalanceState', () {
    test('total adds dollars, invested, in flight and waiting', () {
      const state = OneBalanceState(
        dollarsUsd: 100,
        investedUsd: 50,
        inFlight: [
          InFlightMove(
              kind: InFlightKind.toVenue,
              venue: OneBalanceVenue.investing,
              usd: 20),
          InFlightMove(kind: InFlightKind.incomingDollars, usd: 5),
        ],
        waiting: {OneBalanceVenue.predictions: 7},
        investingKnown: true,
        predictionsKnown: true,
      );
      expect(state.totalUsd, 182);
      expect(state.availableUsd, 100);
      expect(state.inFlightUsd, 25);
      expect(state.waitingUsd, 7);
    });

    test('an empty state totals zero and knows nothing', () {
      const state = OneBalanceState();
      expect(state.totalUsd, 0);
      expect(state.investingKnown, isFalse);
      expect(state.predictionsKnown, isFalse);
    });

    test('equality is by value, copyWith keeps the rest', () {
      const a = OneBalanceState(
        dollarsUsd: 1,
        inFlight: [InFlightMove(kind: InFlightKind.incomingDollars, usd: 2)],
        waiting: {OneBalanceVenue.investing: 3},
      );
      final b = a.copyWith();
      expect(b, a);
      expect(b.hashCode, a.hashCode);
      expect(a.copyWith(dollarsUsd: 2), isNot(a));
      expect(a.copyWith(investingKnown: true).waiting, a.waiting);
      expect(
        const InFlightMove(kind: InFlightKind.incomingDollars, usd: 2),
        const InFlightMove(kind: InFlightKind.incomingDollars, usd: 2),
      );
    });
  });

  test('VenueCashReleased delivers every emit to listeners', () async {
    final seen = <(OneBalanceVenue, String)>[];
    final sub = VenueCashReleased.stream.listen(seen.add);
    VenueCashReleased.emit(OneBalanceVenue.predictions, 'market_resolved');
    VenueCashReleased.emit(OneBalanceVenue.investing, 'position_closed');
    await Future<void>.delayed(Duration.zero);
    expect(seen, [
      (OneBalanceVenue.predictions, 'market_resolved'),
      (OneBalanceVenue.investing, 'position_closed'),
    ]);
    await sub.cancel();
  });

  group('stub providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [
        hyperliquidTradingProvider.overrideWith(_UninitializedHl.new),
        polymarketTradingProvider.overrideWith(_UninitializedPm.new),
        // The real store opens a Hive box in its constructor.
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      ]);
    });

    tearDown(() => container.dispose());

    test('one balance builds with unknown venues as zero', () {
      final state = container.read(oneBalanceProvider);
      expect(state.dollarsUsd, 0);
      expect(state.investedUsd, 0);
      expect(state.inFlight, isEmpty);
      expect(state.waiting, isEmpty);
      expect(state.investingKnown, isFalse);
      expect(state.predictionsKnown, isFalse);
    });

    test('venue sweeper starts idle and trigger is a no-op', () async {
      expect(container.read(venueSweeperProvider), const VenueSweeperState());
      await container.read(venueSweeperProvider.notifier).trigger('manual');
      expect(container.read(venueSweeperProvider).sweeping, isEmpty);
    });

    test('the Investing rail binds to the direct HyperCore rail', () async {
      final rail = container.read(hyperliquidMoveRailProvider);
      expect(rail, isA<HyperCoreMoveRail>());
      // No gas of its own, no push signal: the slip's poll sees credits.
      await rail.ensureGasFloat();
      expect(await rail.credited.isEmpty, isTrue);
    });
  });
}
