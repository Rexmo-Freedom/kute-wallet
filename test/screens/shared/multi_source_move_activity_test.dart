// One Activity row per action that took money from more than one place:
// the legs fold into it on the Dollars activity (and the Portfolio's,
// which lists the dollar ledger) and on Bitcoin when Bitcoin is the
// destination; partial failures show what was delivered and what is left;
// the detail sheet's Retry pulls only the failed remainder, once.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/helpers/venue_intents.dart' show DirectLegGrants;
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/shared/pending_bitcoin_purchase_continue.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart';
import 'package:kute/screens/portfolio/portfolio_activity.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/screens/shared/venue_cash_pull_copy.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

final _t0 = DateTime.utc(2026, 10, 13, 12);

SwapOrderTransaction _row(String id,
        {required String from,
        required String fromNet,
        required String to,
        required String toNet,
        String? operationId,
        String status = 'exchanging',
        Duration after = Duration.zero}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: _t0.add(after),
      isConfirmed: false,
      details: SwapOrder(
        id: id,
        coinFrom: from,
        networkFrom: fromNet,
        coinTo: to,
        networkTo: toNet,
        depositAddress: 'deposit-$id',
        depositAmount: '20.00',
        withdrawalAmount: '19.80',
        status: status,
        timestamp: _t0.add(after).millisecondsSinceEpoch,
        withdrawalAddress: 'sp1self',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'w1',
        operationId: operationId,
      ),
    );

MultiSourceMoveLeg _leg(OneBalanceVenue venue,
        {bool ok = true, String? op, double usd = 20, bool direct = true}) =>
    MultiSourceMoveLeg(
      venue: venue,
      usd: usd,
      arrivingUsd: usd * 0.99,
      route: direct ? VenueCashRoute.direct : VenueCashRoute.viaDollars,
      ok: ok,
      at: _t0,
      operationId: op,
      error: ok ? null : 'route',
    );

MultiSourceMove _move({
  String id = 'msm_1',
  String forAction = VenueCashFor.buyBitcoin,
  VenueCashDestination destination = VenueCashDestination.bitcoin,
  List<MultiSourceMoveLeg>? legs,
  String? finalOp,
  String? walletId = 'w1',
}) =>
    MultiSourceMove(
      id: id,
      walletId: walletId,
      forAction: forAction,
      destination: destination,
      totalUsd: 50,
      dollarsUsd: 10,
      createdAt: _t0.add(const Duration(seconds: 1)),
      legs: legs ??
          [
            _leg(OneBalanceVenue.predictions, op: 'op-pm'),
            _leg(OneBalanceVenue.investing, op: 'op-hl'),
          ],
      finalOperationId: finalOp,
    );

/// No settlement box in a pure test: classify by the row's shape.
SwapActivityKind _classify(SwapOrder o) => classifySwapActivity(o);

void main() {
  group('collapse', () {
    final pmLeg = _row('ord_pm',
        from: 'USDC',
        fromNet: 'POLYGON',
        to: 'BTC',
        toNet: 'SPARK',
        operationId: 'op-pm');
    final hlLeg = _row('cctp-op-hl',
        from: 'USDC',
        fromNet: 'HYPERCORE',
        to: 'BTC',
        toNet: 'SPARK',
        operationId: 'op-hl');
    final purchase = _row('ord_buy',
        from: 'USDB',
        fromNet: 'SPARK',
        to: 'BTC',
        toNet: 'SPARK',
        operationId: 'op-buy');
    final unrelated = _row('ord_other',
        from: 'BTC',
        fromNet: 'LIGHTNING',
        to: 'BTC',
        toNet: 'SPARK',
        after: const Duration(minutes: 5));

    test('Bitcoin as the destination: one row on the Bitcoin tab', () {
      final rows = collapseMultiSourceMoves(
          [unrelated, purchase, hlLeg, pmLeg], [_move(finalOp: 'op-buy')],
          onlyUsdb: false, walletId: 'w1');
      expect(rows.map((r) => r.id), ['ord_other', 'msm_1']);
      final parent = rows.last as MultiSourceMoveTransaction;
      expect(parent.legRows.map((r) => r.id),
          containsAll(['ord_pm', 'cctp-op-hl', 'ord_buy']));
      expect(parent.complete, isFalse, reason: 'legs still on their way');
    });

    test('a send is one row on Dollars, never on the Bitcoin tab', () {
      final send = _move(
          forAction: VenueCashFor.send,
          destination: VenueCashDestination.dollars,
          finalOp: 'op-buy');
      final dollars = collapseMultiSourceMoves([purchase, pmLeg], [send],
          onlyUsdb: true, walletId: 'w1');
      expect(dollars.single, isA<MultiSourceMoveTransaction>());
      final bitcoin = collapseMultiSourceMoves([purchase, pmLeg], [send],
          onlyUsdb: false, walletId: 'w1');
      expect(bitcoin.map((r) => r.id), ['ord_buy', 'ord_pm'],
          reason: 'untouched where the move has no row');
    });

    test('another wallet\'s move, or one where nothing moved, has no row', () {
      expect(
          collapseMultiSourceMoves([pmLeg], [_move(walletId: 'w2')],
                  onlyUsdb: true, walletId: 'w1')
              .single
              .id,
          'ord_pm');
      final nothing = _move(legs: [
        _leg(OneBalanceVenue.investing, ok: false),
      ]);
      expect(
          collapseMultiSourceMoves([pmLeg], [nothing],
                  onlyUsdb: true, walletId: 'w1')
              .single
              .id,
          'ord_pm');
    });

    test('assembleActivityRows folds the legs on Dollars', () {
      final rows = assembleActivityRows(
        [purchase, pmLeg],
        ownAddresses: const {'sp1self'},
        isHardwareOrWatchOnly: false,
        onlyUsdb: true,
        classify: _classify,
        moves: [_move(finalOp: 'op-buy')],
        walletId: 'w1',
      );
      expect(rows.whereType<MultiSourceMoveTransaction>(), hasLength(1));
      expect(rows.whereType<SwapOrderTransaction>(), isEmpty);
    });

    test('the Portfolio never lists a leg beside its move', () {
      final move = _move(finalOp: 'op-buy');
      final dollarRows = collapseMultiSourceMoves([purchase], [move],
          onlyUsdb: true, walletId: 'w1');
      final entries = mergePortfolioActivity(
        dollarRows: dollarRows,
        swaps: [pmLeg, hlLeg, purchase],
        bets: const [],
        fills: const [],
        movedLegIds: multiSourceMoveLegIds([pmLeg, hlLeg, purchase], [move]),
      );
      expect(entries.map((e) => e.tx!.id), ['msm_1']);
    });
  });

  group('settled only when the destination has the money', () {
    setUp(OwnSparkArrivals.reset);
    tearDown(OwnSparkArrivals.reset);

    final directPm = _row('ord_pm',
        from: 'USDC',
        fromNet: 'POLYGON',
        to: 'BTC',
        toNet: 'SPARK',
        operationId: 'op-pm',
        status: 'success');
    MultiSourceMove direct() => _move(legs: [
          _leg(OneBalanceVenue.predictions, op: 'op-pm'),
        ]);

    test('a direct leg Orchestra finished waits for the wallet to count it',
        () {
      OwnSparkArrivals.refresh = (_) => Completer<void>().future;
      OwnSparkArrivals.landed(directPm.details);
      final waiting =
          MultiSourceMoveTransaction(move: direct(), legRows: [directPm]);
      expect(waiting.complete, isFalse);
      OwnSparkArrivals.reset();
      expect(
          MultiSourceMoveTransaction(move: direct(), legRows: [directPm])
              .complete,
          isTrue);
    });

    test('every leg that went needs its own settled row', () {
      final move = _move(legs: [
        _leg(OneBalanceVenue.predictions, op: 'op-pm'),
        _leg(OneBalanceVenue.investing, op: 'op-hl'),
      ]);
      expect(
          MultiSourceMoveTransaction(move: move, legRows: [directPm]).complete,
          isFalse,
          reason: 'the Investing leg has no row yet');
    });

    test('dollars brought home for Bitcoin: settled once the purchase is', () {
      final viaDollars = _move(legs: [
        _leg(OneBalanceVenue.predictions, op: 'op-pm', direct: false),
      ]);
      final home = _row('ord_pm',
          from: 'USDC',
          fromNet: 'POLYGON',
          to: 'USDB',
          toNet: 'SPARK',
          operationId: 'op-pm',
          status: 'success');
      expect(
          MultiSourceMoveTransaction(move: viaDollars, legRows: [home])
              .complete,
          isFalse);
      final bought = _row('ord_buy',
          from: 'USDB',
          fromNet: 'SPARK',
          to: 'BTC',
          toNet: 'SPARK',
          operationId: 'op-buy',
          status: 'success');
      expect(
          MultiSourceMoveTransaction(
              move: viaDollars.copyWith(finalOperationId: 'op-buy'),
              legRows: [home, bought]).complete,
          isTrue);
    });

    test('a surface that does not list a leg still reads it', () {
      // The Dollars activity never lists a USDC → BTC leg; the move's row
      // settles on it all the same.
      final rows = assembleActivityRows(
        [directPm],
        ownAddresses: const {'sp1self'},
        isHardwareOrWatchOnly: false,
        onlyUsdb: true,
        classify: _classify,
        moves: [direct()],
        walletId: 'w1',
      );
      final move = rows.single as MultiSourceMoveTransaction;
      expect(move.legRows.map((r) => r.id), ['ord_pm']);
      expect(move.complete, isTrue);
    });
  });

  group('the standard row', () {
    test('to Bitcoin: an Investments withdrawal of the bitcoin delivered', () {
      final pm = _row('ord_pm',
          from: 'USDC',
          fromNet: 'POLYGON',
          to: 'BTC',
          toNet: 'SPARK',
          operationId: 'op-pm',
          status: 'success');
      final hl = _row('ord_hl',
          from: 'USDC',
          fromNet: 'ARBITRUM',
          to: 'BTC',
          toNet: 'SPARK',
          operationId: 'op-hl',
          status: 'success');
      final tx = MultiSourceMoveTransaction(move: _move(), legRows: [pm, hl]);
      final row = multiSourceMoveStandardRow(tx)!;
      expect(row.id, 'msm_1');
      expect(
          classifySwapActivity(row.details), SwapActivityKind.dollarWithdrawal);
      expect(row.details.withdrawalAmount, '39.60000000',
          reason: 'what both legs delivered (fixture amounts)');
      expect(row.details.depositAmount, '50.00');
      expect(row.details.status, 'success');
      expect(row.timestamp, _move().createdAt);
    });

    test('a send that went is the send\'s own row for the whole amount', () {
      final send = SwapOrderTransaction(
        id: 'ord_send',
        timestamp: _t0,
        isConfirmed: false,
        details: _row('ord_send',
                from: 'USDB',
                fromNet: 'SPARK',
                to: 'BTC',
                toNet: 'LIGHTNING',
                operationId: 'op-send')
            .details
            .copyWith(activityDirection: 'send'),
      );
      final move = _move(
          forAction: VenueCashFor.send,
          destination: VenueCashDestination.dollars,
          finalOp: 'op-send');
      final row = multiSourceMoveStandardRow(
          MultiSourceMoveTransaction(move: move, legRows: [send]))!;
      expect(row.id, 'msm_1');
      expect(row.details.activityDirection, 'send');
      expect(row.details.depositAmount, '50.00');
      expect(row.details.status, 'exchanging');
      expect(classifySwapActivity(row.details), SwapActivityKind.send);
    });

    test('a move into Dollars or a venue keeps its own row', () {
      expect(
          multiSourceMoveStandardRow(MultiSourceMoveTransaction(
              move: _move(destination: VenueCashDestination.predictions),
              legRows: const [])),
          isNull);
    });
  });

  group('rows on screen', () {
    setUp(() {
      Intl.defaultLocale = 'en_US';
      OwnSparkArrivals.reset();
    });
    tearDown(() {
      Intl.defaultLocale = null;
      OwnSparkArrivals.reset();
    });

    Future<void> pumpRow(WidgetTester tester, BaseTransaction tx) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
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
    }

    testWidgets(
        'Predictions to Bitcoin reads "Withdraw · from Investments", '
        'the bitcoin received from the dollars spent', (tester) async {
      final pm = SwapOrderTransaction(
        id: 'ord_pm',
        timestamp: _t0,
        isConfirmed: true,
        details: _row('ord_pm',
                from: 'USDC',
                fromNet: 'POLYGON',
                to: 'BTC',
                toNet: 'SPARK',
                operationId: 'op-pm',
                status: 'success')
            .details
            .copyWith(withdrawalAmount: '0.00009300'),
      );
      final move = _move(legs: [
        _leg(OneBalanceVenue.predictions, op: 'op-pm', usd: 7.78),
      ]);
      await pumpRow(
          tester, MultiSourceMoveTransaction(move: move, legRows: [pm]));
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.textContaining('from Investments'), findsOneWidget);
      expect(find.textContaining('Predictions'), findsNothing);
      expect(find.textContaining('9,300'), findsOneWidget);
      expect(find.text('from \$50.00'), findsOneWidget);
      expect(find.textContaining('Pending', findRichText: true), findsNothing);
    });

    testWidgets(
        'a plain Investing to Bitcoin move reads as the same row, '
        '"from Investments"', (tester) async {
      final hl = _row('ord_hl',
              from: 'USDC',
              fromNet: 'HYPERCORE',
              to: 'BTC',
              toNet: 'SPARK',
              status: 'success')
          .details
          .copyWith(
              routeVersion: 'hypercore_to_spark_v1',
              withdrawalAmount: '0.00008002',
              depositAmount: '6.66');
      expect(classifySwapActivity(hl), SwapActivityKind.investingWithdrawal);
      await pumpRow(
          tester,
          SwapOrderTransaction(
              id: hl.id, timestamp: _t0, isConfirmed: true, details: hl));
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.textContaining('from Investments'), findsOneWidget);
      expect(find.textContaining('Investing'), findsNothing);
      expect(find.textContaining('8,002'), findsOneWidget);
    });

    testWidgets('a delivery the wallet has not counted yet stays Pending',
        (tester) async {
      OwnSparkArrivals.refresh = (_) => Completer<void>().future;
      final pm = _row('ord_pm',
          from: 'USDC',
          fromNet: 'POLYGON',
          to: 'BTC',
          toNet: 'SPARK',
          operationId: 'op-pm',
          status: 'success');
      OwnSparkArrivals.landed(pm.details);
      final move =
          _move(legs: [_leg(OneBalanceVenue.predictions, op: 'op-pm')]);
      await pumpRow(
          tester, MultiSourceMoveTransaction(move: move, legRows: [pm]));
      expect(find.text('Withdraw'), findsOneWidget);
      expect(
          find.textContaining('Pending', findRichText: true), findsOneWidget);
    });

    testWidgets('a multi-source send reads as the Dollars send row',
        (tester) async {
      final send = SwapOrderTransaction(
        id: 'ord_send',
        timestamp: _t0,
        isConfirmed: false,
        details: _row('ord_send',
                from: 'USDB',
                fromNet: 'SPARK',
                to: 'BTC',
                toNet: 'LIGHTNING',
                operationId: 'op-send',
                status: 'success')
            .details
            .copyWith(activityDirection: 'send'),
      );
      final move = _move(
          forAction: VenueCashFor.send,
          destination: VenueCashDestination.dollars,
          finalOp: 'op-send',
          legs: [_leg(OneBalanceVenue.predictions, direct: false)]);
      await pumpRow(
          tester, MultiSourceMoveTransaction(move: move, legRows: [send]));
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Send \$50.00'), findsNothing);
      expect(find.textContaining('to Lightning'), findsOneWidget);
    });
  });

  group('copy', () {
    late AppLocalizations l10n;
    setUpAll(() async =>
        l10n = await AppLocalizations.delegate.load(const Locale('en')));

    test('the person\'s intent is the title', () {
      expect(multiSourceMoveTitle(l10n, _move()), 'Move \$50.00 to Bitcoin');
      expect(
          multiSourceMoveTitle(
              l10n,
              _move(
                  forAction: VenueCashFor.send,
                  destination: VenueCashDestination.dollars,
                  finalOp: 'op-send')),
          'Send \$50.00');
    });

    test('a partial failure says what was delivered and what is left', () {
      final partial = _move(legs: [
        _leg(OneBalanceVenue.predictions, op: 'op-pm'),
        _leg(OneBalanceVenue.investing, ok: false, usd: 21),
      ]);
      expect(partial.partial, isTrue);
      expect(multiSourceMoveProgress(l10n, partial),
          '\$29.80 delivered · \$20.20 remaining');
      expect(multiSourceMoveProgress(l10n, _move()), isNull);
      // The action's own step went: nothing is left.
      expect(
          multiSourceMoveProgress(
              l10n, partial.copyWith(finalOperationId: 'op-buy')),
          isNull);
    });
  });

  group('detail sheet', () {
    setUp(() {
      Intl.defaultLocale = 'en_US';
      OwnSparkArrivals.reset();
      MultiSourceMoveStore.reset();
    });
    tearDown(() {
      Intl.defaultLocale = null;
      OwnSparkArrivals.reset();
    });

    // A withdraw to Bitcoin of $50: $10 from Dollars, $20 from Investing
    // straight to Bitcoin (landed), $15 from Predictions home to Dollars
    // (on its way) and $5 more from Investing, home first, that failed.
    SwapOrder hlLanded() => _row('ord_hl',
            from: 'USDC',
            fromNet: 'HYPERCORE',
            to: 'BTC',
            toNet: 'SPARK',
            operationId: 'op-hl',
            status: 'success')
        .details
        .copyWith(withdrawalAmount: '0.00030000', depositAmount: '19.80');
    SwapOrder pmRow({String status = 'exchanging', String got = '14.85'}) =>
        _row('ord_pm',
                from: 'USDC.E',
                fromNet: 'POLYGON',
                to: kOrchestraUsdAssetCode,
                toNet: 'SPARK',
                operationId: 'op-pm',
                status: status)
            .details
            .copyWith(depositAmount: '15.00', withdrawalAmount: got);
    MultiSourceMove threeLegs() => _move(legs: [
          _leg(OneBalanceVenue.investing, op: 'op-hl', usd: 20),
          _leg(OneBalanceVenue.predictions,
              op: 'op-pm', usd: 15, direct: false),
          _leg(OneBalanceVenue.investing, ok: false, usd: 5, direct: false),
        ]);

    Future<FakeSwapOrders> openSheet(
      WidgetTester tester,
      MultiSourceMove move, {
      List<SwapOrder> orders = const [],
      Size size = const Size(430, 932),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      MultiSourceMoveStore.start(move);
      final store = FakeSwapOrders(orders);
      // The surface hands the sheet no rows: they come from the store.
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
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
      // A pending row's spinner never settles: pump frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return store;
    }

    /// The section titled [title] on the sheet.
    Finder section(String title) => find
        .ancestor(of: find.text(title), matching: find.byType(Column))
        .first;
    Finder inSection(String title, String text) =>
        find.descendant(of: section(title), matching: find.text(text));

    testWidgets('every leg shows its rows, under the intent', (tester) async {
      await openSheet(tester, threeLegs(), orders: [hlLanded(), pmRow()]);
      // Header: the intent, then the move's own Date and Status.
      expect(find.text('from Investments to Bitcoin'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      // One section per part, each with its own rows.
      expect(find.text('Investing → Bitcoin'), findsOneWidget);
      expect(find.text('Predictions → Dollars'), findsOneWidget);
      expect(find.text('Investing → Dollars'), findsOneWidget);
      expect(find.text('Dollars → Bitcoin'), findsOneWidget);

      // Landed straight to Bitcoin: what left, what arrived, its order.
      expect(inSection('Investing → Bitcoin', 'Completed'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Sent'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', '\$20.00'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Received'), findsOneWidget);
      expect(
          find.descendant(
              of: section('Investing → Bitcoin'),
              matching: find.textContaining('30,000')),
          findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Nerd data'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Track this exchange'),
          findsOneWidget);

      // On its way home to Dollars.
      expect(
          inSection('Predictions → Dollars', 'Processing'), findsOneWidget);
      expect(inSection('Predictions → Dollars', '\$15.00'), findsOneWidget);
      expect(
          inSection('Predictions → Dollars', 'Arriving'), findsOneWidget);
      expect(inSection('Predictions → Dollars', '\$14.85'), findsOneWidget);

      // Dollars' own part.
      expect(inSection('Dollars → Bitcoin', '\$10.00'), findsOneWidget);

      // The Nerd data are the swap order sheet's own rows.
      await tester.ensureVisible(inSection('Investing → Bitcoin', 'Nerd data'));
      await tester.tap(inSection('Investing → Bitcoin', 'Nerd data'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(inSection('Investing → Bitcoin', 'Provider'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Orchestra'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Exchange ID'), findsOneWidget);
      expect(
          inSection('Investing → Bitcoin', 'Deposit Network'), findsOneWidget);
      expect(
          inSection('Investing → Bitcoin', 'Receive Network'), findsOneWidget);
    });

    testWidgets('a leg moves from Arriving to Received live as it lands',
        (tester) async {
      final store =
          await openSheet(tester, threeLegs(), orders: [hlLanded(), pmRow()]);
      expect(
          inSection('Predictions → Dollars', 'Arriving'), findsOneWidget);
      expect(inSection('Predictions → Dollars', 'Received'), findsNothing);
      expect(inSection('Predictions → Dollars', 'Fee'), findsNothing);

      store.set([hlLanded(), pmRow(status: 'success', got: '14.80')]);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          inSection('Predictions → Dollars', 'Completed'), findsOneWidget);
      expect(inSection('Predictions → Dollars', 'Arriving'), findsNothing);
      expect(
          inSection('Predictions → Dollars', 'Received'), findsOneWidget);
      expect(inSection('Predictions → Dollars', '\$14.80'), findsOneWidget);
      // Both sides in dollars and known: the fee, exactly.
      expect(inSection('Predictions → Dollars', 'Fee'), findsOneWidget);
      expect(inSection('Predictions → Dollars', '\$0.20'), findsOneWidget);
    });

    testWidgets('a failed leg says so, a refunded one too, with Retry',
        (tester) async {
      await openSheet(tester, threeLegs(),
          orders: [hlLanded(), pmRow(status: 'refunded')]);
      // The failed $5 stayed on Investing: its Failed status and what was
      // asked of it, nothing arriving and no order.
      const failed = 'Investing → Dollars';
      expect(inSection(failed, 'Failed'), findsOneWidget);
      expect(inSection(failed, '\$5.00'), findsOneWidget);
      expect(inSection(failed, 'Arriving'), findsNothing);
      expect(inSection(failed, 'Received'), findsNothing);
      expect(inSection(failed, 'Nerd data'), findsNothing);
      // The refunded leg reads as the swap order sheet reads it.
      expect(
          inSection('Predictions → Dollars', 'Refunded'), findsOneWidget);
      // What was delivered and what is left, and Retry for the rest.
      expect(find.text('\$44.65 delivered · \$5.35 remaining'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a value not known is left out, never a dash', (tester) async {
      // No row yet for the Predictions leg; the Investing leg landed in
      // bitcoin (no dollar fee to state); Dollars' part waits for Retry.
      await openSheet(tester, threeLegs(), orders: [hlLanded()]);
      expect(inSection('Predictions → Dollars', 'Pending'), findsOneWidget);
      expect(
          inSection('Predictions → Dollars', 'Arriving'), findsOneWidget);
      expect(inSection('Predictions → Dollars', 'Received'), findsNothing);
      expect(inSection('Predictions → Dollars', 'Nerd data'), findsNothing);
      expect(inSection('Predictions → Dollars', 'Track this exchange'),
          findsNothing);
      expect(inSection('Investing → Bitcoin', 'Fee'), findsNothing);
      expect(inSection('Dollars → Bitcoin', 'Status'), findsNothing);
      expect(inSection('Dollars → Bitcoin', 'Date'), findsNothing);
      for (final dash in ['—', '-', '–', '\$0.00']) {
        expect(find.text(dash), findsNothing, reason: dash);
      }
    });

    testWidgets('a CCTP move with no order yet has no explorer button',
        (tester) async {
      final cctp = _row('cctp-op-hl',
              from: 'USDC',
              fromNet: 'HYPERCORE',
              to: 'BTC',
              toNet: 'SPARK',
              operationId: 'op-hl')
          .details
          .copyWith(withdrawalAmount: '0');
      await openSheet(
          tester, _move(legs: [_leg(OneBalanceVenue.investing, op: 'op-hl')]),
          orders: [cctp]);
      expect(inSection('Investing → Bitcoin', 'Processing'), findsOneWidget);
      expect(inSection('Investing → Bitcoin', 'Arriving'), findsOneWidget);
      expect(find.text('Track this exchange'), findsNothing);
    });

    testWidgets('fits 375pt at text scale 1.3 with every Nerd data open',
        (tester) async {
      await openSheet(tester, threeLegs(),
          orders: [hlLanded(), pmRow()],
          size: const Size(375, 812),
          textScale: 1.3);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 2; i++) {
        final nerd = find.text('Nerd data').at(i);
        await tester.ensureVisible(nerd);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(nerd);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('detail sheet Retry', () {
    late List<String> events;
    setUp(() {
      Intl.defaultLocale = 'en_US';
      events = [];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      MultiSourceMoveStore.reset();
      DirectRouteRefusals.reset();
    });
    tearDown(() {
      Intl.defaultLocale = null;
      TrackingService.debugTrackObserver = null;
      debugMultiSourceRetryApproval = null;
    });

    testWidgets('pulls the remainder once and the row stops needing it',
        (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final hl = _RetrySource();
      // A remainder to Bitcoin asks its own one approval, before any leg.
      final prompts = <SensitiveIntent>[];
      final pulledAtPrompt = <int>[];
      debugMultiSourceRetryApproval = (intent) async {
        prompts.add(intent);
        pulledAtPrompt.add(hl.pulls.length);
        return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
      };
      final puller = VenueCashPuller(
        sources: [hl],
        readDollars: () => 0,
        minimumUsd: (_) async => 1,
      );
      MultiSourceMoveStore.start(_move(legs: [
        _leg(OneBalanceVenue.predictions, op: 'op-pm'),
        _leg(OneBalanceVenue.investing, ok: false, usd: 21),
      ]));
      final tx = MultiSourceMoveTransaction(
          move: MultiSourceMoveStore.get('msm_1')!, legRows: const []);
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
          venueCashPullerProvider.overrideWithValue(puller),
          swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
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
      // The standard Investments withdrawal row; what is left is in the
      // detail.
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Move \$50.00 to Bitcoin'), findsNothing);
      expect(find.textContaining('remaining'), findsNothing);

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('\$20.20 remaining'), findsOneWidget);

      hl.gate = Completer<void>();
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      // A second tap while it runs pulls nothing more.
      expect(MultiSourceMoveStore.retrying('msm_1'), isTrue);
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      await tester.pump();
      hl.gate!.complete();
      // The row is pending again (its spinner never settles): pump.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(hl.pulls, hasLength(1));
      expect(hl.pulls.single, greaterThanOrEqualTo(20.2));
      expect(prompts, hasLength(1), reason: 'one prompt, the second tap none');
      expect(pulledAtPrompt, [0], reason: 'nothing moved before it');
      expect(prompts.single.action, SensitiveAction.moveTransfer);
      expect(events, contains('multi_source_move_retry_tapped'));
      expect(MultiSourceMoveStore.get('msm_1')!.partial, isFalse);
      expect(find.text('Retry'), findsNothing);
    });
  });

  // The founder's move of 15 October, made with an older build: $20.23 to
  // Bitcoin from Investments, one Investing leg home to Dollars ($20.95
  // sent, $20.69 landed), and the purchase from Dollars never ran (it was
  // tied to the open sheet), with no pending record. It must never read
  // Pending forever.
  group('a move whose own step never went', () {
    late List<double> bought;
    late List<SensitiveIntent> prompts;
    late List<(String, Map<String, Object>?)> events;
    late BitcoinPurchaseFinisher finisher;
    late double dollars;
    Completer<void>? waitGate;
    late BuildContext lastContext;
    late WidgetRef lastRef;

    setUp(() {
      Intl.defaultLocale = 'en_US';
      OwnSparkArrivals.reset();
      MultiSourceMoveStore.reset();
      PendingBitcoinPurchaseStore.reset();
      bought = [];
      prompts = [];
      events = [];
      dollars = 25.71;
      waitGate = null;
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      debugPendingPurchaseApproval = (intent) async {
        prompts.add(intent);
        return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
      };
      finisher = BitcoinPurchaseFinisher(
        readDollars: () => dollars,
        buy: (double usd, SettlementStepUpHook stepUp,
            {required String moveId,
            required void Function() onFunding}) async {
          bought.add(usd);
          onFunding();
        },
        sleep: (_) =>
            waitGate?.future ??
            Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    });
    tearDown(() {
      Intl.defaultLocale = null;
      OwnSparkArrivals.reset();
      TrackingService.debugTrackObserver = null;
      debugPendingPurchaseApproval = null;
    });

    SwapOrder hlHome({String status = 'success'}) => _row('ord_hl',
            from: 'USDC',
            fromNet: 'HYPERCORE',
            to: kOrchestraUsdAssetCode,
            toNet: 'SPARK',
            operationId: 'op-hl',
            status: status)
        .details
        .copyWith(depositAmount: '20.95', withdrawalAmount: '20.69');
    SwapOrderTransaction rowOf(SwapOrder o) => SwapOrderTransaction(
        id: o.id,
        timestamp: _t0,
        isConfirmed: o.isComplete,
        details: o);
    MultiSourceMove founderMove({
      String id = 'msm_f',
      String forAction = VenueCashFor.buyBitcoin,
      VenueCashDestination destination = VenueCashDestination.bitcoin,
      DateTime? createdAt,
      String? finalOp,
    }) =>
        MultiSourceMove(
          id: id,
          walletId: 'spending',
          forAction: forAction,
          destination: destination,
          totalUsd: 20.23,
          dollarsUsd: 0,
          createdAt: createdAt ?? _t0.add(const Duration(seconds: 1)),
          legs: [
            MultiSourceMoveLeg(
              venue: OneBalanceVenue.investing,
              usd: 20.95,
              arrivingUsd: 20.69,
              route: VenueCashRoute.viaDollars,
              ok: true,
              at: _t0,
              operationId: 'op-hl',
            ),
          ],
          finalOperationId: finalOp,
        );

    Future<void> pump(WidgetTester tester, MultiSourceMoveTransaction tx,
        {List<SwapOrder> orders = const []}) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // A fresh scope each time, so the balance override is read anew.
      await tester.pumpWidget(const SizedBox());
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
          usdBalanceProvider.overrideWith((_) => dollars),
          bitcoinPurchaseFinisherProvider.overrideWithValue(finisher),
          sparkSelfAddressProvider.overrideWith((_) async => 'spark1self'),
          swapOrdersProvider.overrideWith((_) => FakeSwapOrders(orders)),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(builder: (context, ref, _) {
                lastContext = context;
                lastRef = ref;
                return buildUnifiedTransactionItem(tx, context, ref);
              }),
            ),
          ),
        ),
      ));
    }

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Finder text(String s) => find.textContaining(s, findRichText: true);
    Finder row() => find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_TransactionRow')
        .first;
    Future<void> openDetail(
        WidgetTester tester, MultiSourceMoveTransaction tx) async {
      await openTransactionDetails(lastContext, lastRef, tx);
      await frames(tester);
    }

    testWidgets(
        'every leg landed, no record, Dollars hold it: Needs attention and '
        'one tap with a fresh approval buys what landed, capped at the move',
        (tester) async {
      final move = founderMove();
      final tx = MultiSourceMoveTransaction(
          move: move, legRows: [rowOf(hlHome())]);
      expect(multiSourceMoveFinalStepMissing(move, tx.legRows, now: _t0),
          isFalse,
          reason: 'inside its approval time it may still finish on its own');
      expect(
          multiSourceMoveFinalStepMissing(move, tx.legRows,
              now: _t0.add(const Duration(minutes: 31))),
          isTrue);
      expect(multiSourceMoveLandedInDollarsUsd(move, tx.legRows), 20.69);
      expect(multiSourceMoveMissingStepUsd(move, tx.legRows), 20.23);

      await pump(tester, tx);
      expect(text('Needs attention'), findsOneWidget);
      expect(text(r'Your $20.23 is in Investments. Tap to buy Bitcoin'),
          findsOneWidget);
      expect(text('Pending'), findsNothing);

      await tester.tap(row());
      await frames(tester);
      // ONE prompt, for this purchase alone: the own Spark address, at
      // most the amount.
      expect(prompts, hasLength(1));
      expect(prompts.single.action, SensitiveAction.moveTransfer);
      expect(prompts.single.destination, 'spark1self');
      expect(prompts.single.amountMax, BigInt.from(20230000));
      expect(bought, [20.23]);
      expect(PendingBitcoinPurchaseStore.get('msm_f'), isNull);
      final tapped = events.firstWhere(
          (e) => e.$1 == 'move_purchase_continue_tapped');
      expect(tapped.$2?['legacy'], true);
      expect(tapped.$2?['amount_usd'], 20.23);
      final finished =
          events.firstWhere((e) => e.$1 == 'move_purchase_finished');
      expect(finished.$2?['legacy'], true);
      expect(finished.$2?['outcome'], 'bought');
    });

    testWidgets(
        'the detail names Dollars plainly, says Needs attention and offers '
        'the purchase', (tester) async {
      final move = founderMove();
      MultiSourceMoveStore.start(move);
      final tx = MultiSourceMoveTransaction(
          move: move, legRows: [rowOf(hlHome())]);
      await pump(tester, tx, orders: [hlHome()]);
      await openDetail(tester, tx);
      expect(find.text('Investing → Dollars'), findsOneWidget);
      expect(find.text('Investing → Investments'), findsNothing);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      expect(find.text(r'Your $20.23 is in Investments. Tap to buy Bitcoin'),
          findsOneWidget);
      // The leg's cost reads as the swap sheets' plain Fee, never a Kute
      // fee.
      expect(find.textContaining('Kute'), findsNothing);
      await tester.ensureVisible(find.text('Buy bitcoin'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Buy bitcoin'));
      await frames(tester);
      expect(prompts, hasLength(1));
      expect(bought, [20.23]);
    });

    testWidgets('declined: nothing moves and the row keeps offering it',
        (tester) async {
      debugPendingPurchaseApproval = (intent) async {
        prompts.add(intent);
        return null;
      };
      final tx = MultiSourceMoveTransaction(
          move: founderMove(), legRows: [rowOf(hlHome())]);
      await pump(tester, tx);
      await tester.tap(row());
      await frames(tester);
      expect(prompts, hasLength(1));
      expect(bought, isEmpty);
      expect(text('Needs attention'), findsOneWidget);
      expect(text(r'Your $20.23 is in Investments'), findsOneWidget);
    });

    testWidgets(
        'Dollars spent since: no purchase is offered, the move is over and '
        'says its money stayed', (tester) async {
      dollars = 5;
      final move = founderMove();
      MultiSourceMoveStore.start(move);
      final tx = MultiSourceMoveTransaction(
          move: move, legRows: [rowOf(hlHome())]);
      await pump(tester, tx, orders: [hlHome()]);
      expect(text('The money stayed in Investments'), findsOneWidget);
      expect(text('Needs attention'), findsNothing);
      expect(text('Tap to buy Bitcoin'), findsNothing);
      expect(text('Pending'), findsNothing);
      await tester.tap(row());
      await frames(tester);
      expect(prompts, isEmpty);
      expect(bought, isEmpty);
      // The tap opened the detail: Completed, no purchase.
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Buy bitcoin'), findsNothing);
      expect(find.text('Investing → Dollars'), findsOneWidget);
    });

    testWidgets(
        'a send whose money came home but whose send never went: Needs '
        'attention while Dollars hold it, else its money stayed',
        (tester) async {
      final send = founderMove(
          forAction: VenueCashFor.send,
          destination: VenueCashDestination.dollars);
      MultiSourceMoveStore.start(send);
      final tx =
          MultiSourceMoveTransaction(move: send, legRows: [rowOf(hlHome())]);
      expect(tx.complete, isTrue, reason: 'every leg settled');
      await pump(tester, tx, orders: [hlHome()]);
      expect(text(r'Send $20.23'), findsOneWidget);
      expect(text('Needs attention'), findsOneWidget);
      expect(
          text(r"Your $20.23 is in Investments. The send didn't go through"),
          findsOneWidget);
      await tester.tap(row());
      await frames(tester);
      // No purchase for a send: the tap opens the detail.
      expect(prompts, isEmpty);
      expect(find.text('Investing → Dollars'), findsOneWidget);
      expect(find.text('Buy bitcoin'), findsNothing);
      expect(find.text('Needs attention'), findsWidgets);

      dollars = 5;
      await pump(tester, tx, orders: [hlHome()]);
      await frames(tester);
      expect(text('The money stayed in Investments'), findsOneWidget);
      expect(text('Needs attention'), findsNothing);
    });

    testWidgets('a normal completed move is unchanged', (tester) async {
      final purchase = _row('ord_buy',
              from: kOrchestraUsdAssetCode,
              fromNet: 'SPARK',
              to: 'BTC',
              toNet: 'SPARK',
              operationId: 'op-buy',
              status: 'success')
          .details
          .copyWith(depositAmount: '20.23', withdrawalAmount: '0.00020000');
      final move = founderMove(finalOp: 'op-buy');
      final tx = MultiSourceMoveTransaction(
          move: move, legRows: [rowOf(hlHome()), rowOf(purchase)]);
      expect(tx.complete, isTrue);
      await pump(tester, tx);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(text('Needs attention'), findsNothing);
      expect(text('Pending'), findsNothing);
      expect(text('Your '), findsNothing);
      expect(text('stayed'), findsNothing);
    });

    testWidgets(
        'a purchase still running with a live record stays Pending, and so '
        'does a fresh move inside its approval time', (tester) async {
      // The finisher holds the purchase, waiting for Dollars.
      dollars = 0;
      waitGate = Completer<void>();
      final intent = DirectLegGrants.buyBitcoin(
        walletId: 'spending',
        ownSpark: 'spark1self',
        route: 'spark:USDB>spark:BTC',
        asset: kOrchestraUsdAssetCode,
        totalUsd: 20.23,
        directLegs: null,
        ttl: AuthGrants.autofireTtl,
      );
      unawaited(finisher.start(
          moveId: 'msm_f',
          usd: 20.23,
          grant: AuthGrants.issue(intent, method: AuthGrantMethod.biometric)));
      expect(finisher.running('msm_f'), isTrue);
      final tx = MultiSourceMoveTransaction(
          move: founderMove(), legRows: [rowOf(hlHome())]);
      await pump(tester, tx);
      expect(text('Pending'), findsOneWidget);
      expect(text('Needs attention'), findsNothing);
      expect(text('Your '), findsNothing);
      expect(text('stayed'), findsNothing);

      // No record, but the move is minutes old: its own step may still
      // go (the sheet's own purchase under the same approval).
      dollars = 25.71;
      final fresh = MultiSourceMoveTransaction(
          move: founderMove(id: 'msm_fresh', createdAt: DateTime.now()),
          legRows: [rowOf(hlHome())]);
      await pump(tester, fresh);
      expect(text('Needs attention'), findsNothing);
      expect(text('Your '), findsNothing);
    });

    test('a record made from a record-less move is all or nothing', () {
      PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
          moveId: 'msm_f',
          usd: 20.23,
          createdAt: _t0,
          stage: PendingPurchaseStage.needsApproval,
          legacy: true));
      expect(pendingPurchaseWaitingUsd(finisher, 'msm_f', 25.71), 20.23);
      expect(pendingPurchaseWaitingUsd(finisher, 'msm_f', 19.5), isNull);
      expect(legacyPurchaseUsd(20.23, 20.23), 20.23);
      expect(legacyPurchaseUsd(20.23, 20.0), isNull);
      expect(legacyPurchaseUsd(0.5, 25), isNull);
      PendingBitcoinPurchaseStore.reload();
    });
  });
}

/// Investing cash with no direct door: the remainder comes home.
class _RetrySource implements VenueCashSource {
  final pulls = <double>[];
  Completer<void>? gate;

  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;

  @override
  Duration get estimatedArrival => const Duration(minutes: 5);

  @override
  Future<double> availableUsd() async => 500;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    final g = gate;
    if (g != null) await g.future;
    return VenueMoveResult(
        quoteId: 'q', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }
}
