// Founder, 20 October 2026: when a money move runs longer than expected,
// say so calmly ("Taking longer than expected, please wait a bit longer,
// we are almost done"), on its own line under the journey's status line:
// on the slip while the order's funding runs, and in a processing move's
// Activity detail, counted from when the move started. Longer than
// expected: 1.5 times the route's estimate, 90 s without one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/screens/shared/move_steps_view.dart';
import 'package:kute/screens/shared/slip_shortfall.dart' show SlipFundingSteps;
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart'
    show LegDelivery, watchLegDelivery;
import 'package:kute/services/one_balance/money_steps.dart' show MoneyPlace;
import 'package:kute/services/orchestra/venue_arrivals.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

const _message = 'Taking longer than expected. Hang tight, almost done.';
final _start = DateTime(2026, 10, 20, 18, 5);

SwapOrder _deposit({String status = 'exchanging'}) => SwapOrder(
      id: 'q_direct',
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: 'spark1deposit',
      depositAmount: '0.00005705',
      withdrawalAmount: '4.67',
      status: status,
      timestamp: _start.millisecondsSinceEpoch,
      withdrawalAddress: '0x0088aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'spark1own',
      provider: 'Orchestra',
      operationId: 'op-direct',
    );

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(VenueArrivals.debugReset);
  tearDown(() => SlowMoveBuilder.now = DateTime.now);

  testWidgets(
      'the slip: the calm line sits on its own under the status line, not '
      'beside it', (t) async {
    await t.pumpWidget(_app(const SlipFundingSteps(
      steps: ['Moving your money', 'Placing \$5.00 on Yes'],
      active: 0,
      from: MoneyPlace.bitcoin,
      to: MoneyPlace.predictions,
      slow: true,
    )));
    await t.pump();
    final line = find.byKey(const ValueKey('slip-funding-slow'));
    expect(line, findsOneWidget);
    expect((t.widget(line) as Text).data, _message);
    final words = find.byKey(const ValueKey('money-steps-words'));
    expect(t.getTopLeft(line).dy,
        greaterThanOrEqualTo(t.getBottomLeft(words).dy));
    expect(t.getTopLeft(line).dx, t.getTopLeft(words).dx);
  });

  testWidgets('the slip without a slow leg says nothing more', (t) async {
    await t.pumpWidget(_app(const SlipFundingSteps(
      steps: ['Moving your money', 'Placing \$5.00 on Yes'],
      active: 0,
    )));
    await t.pump();
    expect(find.text(_message), findsNothing);
  });

  testWidgets(
      'a leg flags slow after 90 s without an estimate (the slip\'s line), '
      'not before', (t) async {
    var slow = 0;
    var done = false;
    final watch = watchLegDelivery(
      id: () => 'ord_direct',
      statusOf: (_) async => done ? 'completed' : 'processing',
      onSlow: () => slow++,
    );
    await t.pump(const Duration(seconds: 88));
    expect(slow, 0);
    await t.pump(const Duration(seconds: 3));
    expect(slow, 1);
    done = true;
    await t.pump(const Duration(seconds: 2));
    expect(await watch, LegDelivery.delivered);
  });

  testWidgets(
      'the Activity detail of a processing move says so once it runs '
      'longer than expected, from when it started', (t) async {
    var now = _start.add(const Duration(seconds: 30));
    SlowMoveBuilder.now = () => now;
    final orders = FakeSwapOrders([_deposit()]);
    await t.pumpWidget(_app(SwapRowStepsSection(row: _deposit()),
        overrides: [swapOrdersProvider.overrideWith((_) => orders)]));
    await t.pump();
    expect(find.byKey(const ValueKey('money-steps')), findsOneWidget);
    expect(find.text(_message), findsNothing);

    // 90 s after the start: the moment comes on its own.
    now = _start.add(const Duration(seconds: 91));
    await t.pump(const Duration(seconds: 61));
    expect(find.byKey(const ValueKey('money-steps-slow')), findsOneWidget);
    expect(find.text(_message), findsOneWidget);

    // Seen arriving: nothing is running any more, the line goes.
    VenueArrivals.mark(_deposit());
    await t.pump();
    expect(find.text(_message), findsNothing);
  });

  testWidgets('an ended move never says it', (t) async {
    SlowMoveBuilder.now = () => _start.add(const Duration(hours: 1));
    final row = _deposit(status: 'success');
    await t.pumpWidget(_app(SwapRowStepsSection(row: row), overrides: [
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders([row])),
    ]));
    await t.pump();
    expect(find.text(_message), findsNothing);
  });
}
