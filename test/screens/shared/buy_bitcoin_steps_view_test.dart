// A Buy bitcoin's steps on screen: the recorded graph brought up to date
// from the wallet's rows (each leg landing on its own, the purchase's
// order, the bitcoin counted), and the move's Activity detail showing one
// line per step, live as the rows move on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/shared/buy_bitcoin_steps_view.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

final _t0 = DateTime.utc(2026, 10, 15, 12);

SwapOrder _order(String id,
        {required String from,
        required String fromNet,
        required String to,
        required String toNet,
        required String operationId,
        String status = 'exchanging'}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: fromNet,
      coinTo: to,
      networkTo: toNet,
      depositAddress: 'deposit-$id',
      depositAmount: '5.00',
      withdrawalAmount: '4.95',
      status: status,
      timestamp: _t0.millisecondsSinceEpoch,
      withdrawalAddress: 'sp1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'w1',
      operationId: operationId,
    );

SwapOrder _hl({String status = 'exchanging'}) => _order('ord_hl',
    from: 'USDC',
    fromNet: 'HYPERCORE',
    to: 'BTC',
    toNet: 'SPARK',
    operationId: 'op-hl',
    status: status);
SwapOrder _pm({String status = 'exchanging'}) => _order('ord_pm',
    from: 'USDC.E',
    fromNet: 'POLYGON',
    to: kOrchestraUsdAssetCode,
    toNet: 'SPARK',
    operationId: 'op-pm',
    status: status);
SwapOrder _buy({String status = 'exchanging'}) => _order('ord_buy',
    from: kOrchestraUsdAssetCode,
    fromNet: 'SPARK',
    to: 'BTC',
    toNet: 'SPARK',
    operationId: 'op-buy',
    status: status);

SwapOrderTransaction _tx(SwapOrder o) => SwapOrderTransaction(
    id: o.id,
    timestamp: DateTime.fromMillisecondsSinceEpoch(o.timestamp),
    isConfirmed: o.isComplete,
    details: o);

MultiSourceMoveLeg _leg(OneBalanceVenue venue, String op,
        {required double usd, required bool direct}) =>
    MultiSourceMoveLeg(
      venue: venue,
      usd: usd,
      arrivingUsd: usd * 0.99,
      route: direct ? VenueCashRoute.direct : VenueCashRoute.viaDollars,
      ok: true,
      at: _t0,
      operationId: op,
    );

/// "Move $20 to Bitcoin": $12 Investing straight to Bitcoin, $5
/// Predictions home to Dollars, $3 in Dollars, as the puller recorded it.
MultiSourceMove _move({String? finalOp}) {
  final legs = [
    _leg(OneBalanceVenue.investing, 'op-hl', usd: 12, direct: true),
    _leg(OneBalanceVenue.predictions, 'op-pm', usd: 5, direct: false),
  ];
  var g = BuyBitcoinSteps.planned(
    legs: [
      (venue: OneBalanceVenue.investing, usd: 12, direct: true),
      (venue: OneBalanceVenue.predictions, usd: 5, direct: false),
    ],
    onwardUsd: 8,
    totalUsd: 20,
    at: _t0,
  );
  for (final l in legs) {
    g = BuyBitcoinSteps.legRecorded(g, l);
  }
  if (finalOp != null) g = BuyBitcoinSteps.buySent(g, finalOp);
  return MultiSourceMove(
    id: 'msm_buy',
    walletId: 'w1',
    forAction: VenueCashFor.buyBitcoin,
    destination: VenueCashDestination.bitcoin,
    totalUsd: 20,
    dollarsUsd: 3,
    createdAt: _t0.add(const Duration(seconds: 1)),
    legs: legs,
    finalOperationId: finalOp,
    steps: g,
  );
}

MoneyStepStatus _status(MoneyStepGraph g, String id) => g.byId(id)!.status;

void main() {
  setUp(() {
    OwnSparkArrivals.reset();
    MultiSourceMoveStore.reset();
    PendingBitcoinPurchaseStore.reset();
  });

  group('liveBuyBitcoinSteps', () {
    test('each leg lands on its own, from its row', () {
      final g = liveBuyBitcoinSteps(
          _move(), [_tx(_hl()), _tx(_pm(status: 'success'))]);
      expect(_status(g, 'leg:predictions'), MoneyStepStatus.done);
      expect(_status(g, 'leg:investing'), MoneyStepStatus.running);
      expect(_status(g, 'buy'), MoneyStepStatus.waiting);
      expect(_status(g, 'arrive'), MoneyStepStatus.waiting);
    });

    test('the purchase follows its record, then its order', () {
      final rows = [_tx(_hl(status: 'success')), _tx(_pm(status: 'success'))];
      final record =
          PendingBitcoinPurchase(moveId: 'msm_buy', usd: 8, createdAt: _t0);
      // Waiting for Dollars while the finisher runs.
      expect(
          _status(
              liveBuyBitcoinSteps(_move(), rows,
                  purchase: record, purchaseRunning: true),
              'buy'),
          MoneyStepStatus.waiting);
      // Buying.
      expect(
          _status(
              liveBuyBitcoinSteps(_move(), rows,
                  purchase: record.copyWith(stage: PendingPurchaseStage.buying),
                  purchaseRunning: true),
              'buy'),
          MoneyStepStatus.running);
      // After a restart nothing runs it: it waits on the person's tap.
      final stopped = liveBuyBitcoinSteps(_move(), rows, purchase: record);
      expect(_status(stopped, 'buy'), MoneyStepStatus.failed);
      expect(stopped.byId('buy')!.reason, 'needs_approval');

      // Sent, then done with its order; everything arrived.
      final sent = _move(finalOp: 'op-buy');
      expect(_status(liveBuyBitcoinSteps(sent, [...rows, _tx(_buy())]), 'buy'),
          MoneyStepStatus.running);
      final done =
          liveBuyBitcoinSteps(sent, [...rows, _tx(_buy(status: 'success'))]);
      expect(_status(done, 'buy'), MoneyStepStatus.done);
      expect(_status(done, 'arrive'), MoneyStepStatus.done);
      expect(done.allDone, isTrue);
    });

    test('an old record without steps maps and follows its rows too', () {
      final old = MultiSourceMove.fromJson(
          (_move(finalOp: 'op-buy').toJson()..remove('steps')))!;
      expect(old.steps.isEmpty, isTrue);
      final g = liveBuyBitcoinSteps(old, [
        _tx(_hl(status: 'success')),
        _tx(_pm(status: 'success')),
        _tx(_buy(status: 'success')),
      ]);
      expect([for (final s in g.steps) s.id],
          ['leg:investing', 'leg:predictions', 'buy', 'arrive']);
      expect(g.allDone, isTrue);
    });
  });

  group('the move\'s Activity detail', () {
    setUp(() => Intl.defaultLocale = 'en_US');
    tearDown(() => Intl.defaultLocale = null);

    Future<FakeSwapOrders> openSheet(WidgetTester tester, MultiSourceMove move,
        List<SwapOrder> orders) async {
      tester.view.physicalSize = const Size(430, 932) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      MultiSourceMoveStore.start(move);
      final store = FakeSwapOrders(orders);
      final tx = MultiSourceMoveTransaction(move: move, legRows: const []);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => SettingsModel(Settings(
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: false,
                balancePrivacy: 0,
                biometricsEnabled: false,
                bitcoinElectrumNode: 'localhost',
                nodeType: 'Blockstream',
                reviewDone: false,
                wallets: [WalletConfig(id: 'spending', name: 'Spending')],
                activeWalletId: 'spending',
              ))),
          swapOrdersProvider.overrideWith((_) => store),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                  builder: (context, ref, _) =>
                      buildUnifiedTransactionItem(tx, context, ref)),
            ),
          ),
        ),
      ));
      await tester.tap(find
          .byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_TransactionRow')
          .first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return store;
    }

    testWidgets('shows one line per step, each completing on its own',
        (tester) async {
      final store = await openSheet(tester, _move(), [_hl(), _pm()]);
      expect(find.byType(BuyBitcoinStepsSection), findsOneWidget);
      // The detail's compact lines: path, amount, state.
      expect(find.text('Investing → Bitcoin · \$12.00'), findsOneWidget);
      expect(find.text('Predictions → Dollars · \$5.00'), findsOneWidget);
      expect(find.text('Dollars → Bitcoin · \$8.00'), findsOneWidget);
      expect(find.text('Arriving in Bitcoin'), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-running-1')), findsOneWidget);

      // Predictions lands first: only its line completes, with what landed.
      store.set([_hl(), _pm(status: 'success')]);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Predictions → Dollars · \$4.95'), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
      expect(find.text('Dollars → Bitcoin · \$8.00'), findsOneWidget);
    });

    testWidgets('a finished move keeps its steps as the record',
        (tester) async {
      await openSheet(tester, _move(finalOp: 'op-buy'), [
        _hl(status: 'success'),
        _pm(status: 'success'),
        _buy(status: 'success'),
      ]);
      expect(find.text('Investing → Bitcoin · \$12.00'), findsOneWidget);
      expect(find.text('Predictions → Dollars · \$4.95'), findsOneWidget);
      expect(find.text('Dollars → Bitcoin · \$8.00'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('money-step-done-$i')), findsOneWidget);
      }
      expect(find.text('Arrived in Bitcoin'), findsOneWidget);
    });
  });
}
