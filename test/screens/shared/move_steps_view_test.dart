// Every move's steps on screen, the same widget for all: a send's legs
// and the send, a move into a venue, and the single moves read from their
// row (a purchase paid by Dollars alone, Add to Investments from Bitcoin),
// each live in its Activity detail and kept there as the record once done.

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
import 'package:kute/screens/shared/move_steps_view.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
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
        String deposit = '20.00',
        String withdrawal = '19.80',
        String status = 'exchanging',
        String? direction}) =>
    SwapOrder(
      id: id,
      coinFrom: from,
      networkFrom: fromNet,
      coinTo: to,
      networkTo: toNet,
      depositAddress: 'deposit-$id',
      depositAmount: deposit,
      withdrawalAmount: withdrawal,
      status: status,
      timestamp: _t0.millisecondsSinceEpoch,
      withdrawalAddress: 'self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'w1',
      operationId: 'op-$id',
      activityDirection: direction,
    );

MultiSourceMoveLeg _leg(OneBalanceVenue venue, String op,
        {required double usd, bool direct = false}) =>
    MultiSourceMoveLeg(
      venue: venue,
      usd: usd,
      arrivingUsd: usd * 0.99,
      route: direct ? VenueCashRoute.direct : VenueCashRoute.viaDollars,
      ok: true,
      at: _t0,
      operationId: op,
    );

/// "Send $50": $30 in Dollars, $20 home from Predictions, then the send.
SwapOrder _pm({String status = 'exchanging'}) => _order('pm',
    from: 'USDC.E',
    fromNet: 'POLYGON',
    to: kOrchestraUsdAssetCode,
    toNet: 'SPARK',
    deposit: '20.00',
    withdrawal: '19.80',
    status: status);
SwapOrder _send({String status = 'exchanging'}) => _order('send',
    from: kOrchestraUsdAssetCode,
    fromNet: 'SPARK',
    to: 'USDC',
    toNet: 'POLYGON',
    deposit: '50.00',
    withdrawal: '49.50',
    status: status,
    direction: 'send');

MultiSourceMove _sendMove({String? finalOp}) {
  final leg = _leg(OneBalanceVenue.predictions, 'op-pm', usd: 20);
  return MultiSourceMove(
    id: 'msm_send',
    walletId: 'w1',
    forAction: VenueCashFor.send,
    destination: VenueCashDestination.dollars,
    totalUsd: 50,
    dollarsUsd: 30,
    createdAt: _t0.add(const Duration(seconds: 1)),
    legs: [leg],
    finalOperationId: finalOp,
    steps: _went(
        MoveSteps.planned(
          destination: VenueCashDestination.dollars,
          forAction: VenueCashFor.send,
          legs: const [
            (venue: OneBalanceVenue.predictions, usd: 20, direct: false)
          ],
          onwardUsd: 50,
          totalUsd: 50,
          at: _t0,
        ),
        [leg],
        VenueCashDestination.dollars,
        VenueCashFor.send),
  );
}

/// [g] once [legs] went, as the puller records them.
MoneyStepGraph _went(MoneyStepGraph g, List<MultiSourceMoveLeg> legs,
    VenueCashDestination destination, String forAction) {
  for (final l in legs) {
    g = MoveSteps.legRecorded(g, l,
        destination: destination, forAction: forAction);
  }
  return g;
}

Widget _app(FakeSwapOrders store, BaseTransaction tx) => ProviderScope(
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
    );

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<FakeSwapOrders> _open(
    WidgetTester tester, BaseTransaction tx, List<SwapOrder> orders) async {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final store = FakeSwapOrders(orders);
  await tester.pumpWidget(_app(store, tx));
  await tester.tap(find
      .byWidgetPredicate((w) => w.runtimeType.toString() == '_TransactionRow')
      .first);
  await _frames(tester);
  return store;
}

SwapOrderTransaction _tx(SwapOrder o) => SwapOrderTransaction(
    id: o.id,
    timestamp: DateTime.fromMillisecondsSinceEpoch(o.timestamp),
    isConfirmed: o.isComplete,
    details: o);

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  setUp(() {
    Intl.defaultLocale = 'en_US';
    OwnSparkArrivals.reset();
    MultiSourceMoveStore.reset();
    PendingBitcoinPurchaseStore.reset();
  });
  tearDown(() => Intl.defaultLocale = null);

  test('the send reads as itself: Sending, then Sent', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    var g = _sendMove().steps;
    expect(moveStepLines(l10n, g).map((l) => l.text), [
      r'Moving $20.00 from Predictions → Dollars',
      r'Sending $50.00',
    ]);
    g = g.update('send', (s) => s.copyWith(status: MoneyStepStatus.done));
    expect(moveStepLines(l10n, g).last.text, r'Sent $50.00');
  });

  group('a send in Activity', () {
    testWidgets('live: the leg lands on its own, the send waits on it',
        (tester) async {
      final move = _sendMove();
      MultiSourceMoveStore.start(move);
      final store = await _open(tester,
          MultiSourceMoveTransaction(move: move, legRows: const []), [_pm()]);
      expect(_inSheet(find.text(r'Predictions → Dollars · $20.00')),
          findsOneWidget);
      // Not sent yet: no recipient to name.
      expect(_inSheet(find.text(r'Sending $50.00')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-step-waiting-1')), findsOneWidget);

      store.set([_pm(status: 'success')]);
      await _frames(tester);
      expect(_inSheet(find.text(r'Predictions → Dollars · $19.80')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
    });

    testWidgets('done: every step is kept as the record', (tester) async {
      final move = _sendMove(finalOp: 'op-send');
      MultiSourceMoveStore.start(move);
      await _open(
          tester,
          MultiSourceMoveTransaction(move: move, legRows: const []),
          [_pm(status: 'success'), _send(status: 'success')]);
      expect(_inSheet(find.text(r'Predictions → Dollars · $19.80')),
          findsOneWidget);
      // The send, to where it went, with what arrived.
      expect(
          _inSheet(find.textContaining(RegExp(r'^Dollars → .+ · \$49\.50$'))),
          findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-1')), findsOneWidget);
      expect(_inSheet(find.text('Date')), findsOneWidget);
      expect(_inSheet(find.text('Status')), findsOneWidget);
    });
  });

  testWidgets('a move into Predictions: Investing straight there, Dollars on',
      (tester) async {
    final legs = [
      _leg(OneBalanceVenue.investing, 'op-hl', usd: 15, direct: true),
    ];
    var g = MoveSteps.planned(
      destination: VenueCashDestination.predictions,
      forAction: VenueCashFor.predictions,
      legs: const [(venue: OneBalanceVenue.investing, usd: 15, direct: true)],
      onwardUsd: 5,
      totalUsd: 20,
      at: _t0,
    );
    final move = MultiSourceMove(
      id: 'msm_pm',
      walletId: 'w1',
      forAction: VenueCashFor.predictions,
      destination: VenueCashDestination.predictions,
      totalUsd: 20,
      dollarsUsd: 5,
      createdAt: _t0.add(const Duration(seconds: 1)),
      legs: legs,
      steps: _went(
          g, legs, VenueCashDestination.predictions, VenueCashFor.predictions),
    );
    MultiSourceMoveStore.start(move);
    await _open(
        tester, MultiSourceMoveTransaction(move: move, legRows: const []), [
      _order('hl',
              from: 'USDC',
              fromNet: 'HYPERCORE',
              to: 'USDC.E',
              toNet: 'POLYGON',
              deposit: '15.00',
              withdrawal: '14.80',
              status: 'success')
          .copyWith(operationId: 'op-hl'),
    ]);
    expect(_inSheet(find.text(r'Investing → Predictions · $14.80')),
        findsOneWidget);
    expect(
        _inSheet(find.text(r'Dollars → Predictions · $5.00')), findsOneWidget);
    expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
  });

  group('a single move, from its row', () {
    SwapOrder buy({String status = 'exchanging'}) => _order('buy',
        from: kOrchestraUsdAssetCode,
        fromNet: 'SPARK',
        to: 'BTC',
        toNet: 'SPARK',
        deposit: '5.00',
        withdrawal: '0.00005000',
        status: status);

    testWidgets(
        'a purchase paid by Dollars alone: the purchase, then the arrival, '
        'live and then as the record', (tester) async {
      final store = await _open(tester, _tx(buy()), [buy()]);
      expect(_inSheet(find.text(r'Dollars → Bitcoin · $5.00')), findsOneWidget);
      expect(_inSheet(find.text('Arriving in Bitcoin')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-step-running-0')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-step-waiting-1')), findsOneWidget);

      store.set([buy(status: 'success')]);
      await _frames(tester);
      expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
      expect(_inSheet(find.text('Arrived in Bitcoin')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-1')), findsOneWidget);
    });

    testWidgets('Add to Investments from Bitcoin: Bitcoin → Dollars',
        (tester) async {
      final row = _order('btc',
          from: 'BTC',
          fromNet: 'SPARK',
          to: kOrchestraUsdAssetCode,
          toNet: 'SPARK',
          deposit: '0.00010000',
          withdrawal: '9.87',
          status: 'success');
      await _open(tester, _tx(row), [row]);
      expect(_inSheet(find.text(r'Bitcoin → Dollars · $9.87')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-step-done-0')), findsOneWidget);
      // The path is the step line's: never twice.
      expect(_inSheet(find.text('Arriving in Bitcoin')), findsNothing);
    });
  });
}
