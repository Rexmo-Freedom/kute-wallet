// The Portfolio's Activity tab is ONE list (owner decision October
// 2026): the venues' activity (Investing fills, predictions placed and
// settled) merged with the wallet's deposit and move activity (the
// dollar ledger: Investments deposits, per-order funding moves, sweeps),
// sorted by time, with no venue switch above it. A conversion the dollar
// ledger and a venue both list is one row.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/portfolio/portfolio_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityDaySection, assembleActivityRows;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart';

final _t0 = DateTime.utc(2026, 10, 5, 12);

SwapOrderTransaction _swap(String id,
        {required String coinFrom,
        required String networkFrom,
        required String coinTo,
        required String networkTo,
        required DateTime at,
        String? routeVersion}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: SwapOrder(
        id: id,
        coinFrom: coinFrom,
        networkFrom: networkFrom,
        coinTo: coinTo,
        networkTo: networkTo,
        depositAddress: 'deposit-$id',
        depositAmount: '10',
        withdrawalAmount: '10',
        status: 'success',
        timestamp: at.millisecondsSinceEpoch,
        withdrawalAddress: networkTo == 'SPARK' ? 'sp1self' : '0xvenue',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'spending',
        routeVersion: routeVersion,
      ),
    );

/// A per-order funding move: dollars into a venue.
SwapOrderTransaction _fundingMove(String id, String network, DateTime at) =>
    _swap(id,
        coinFrom: kOrchestraUsdAssetCode,
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: network,
        at: at);

/// An Investing move paid in bitcoin, before one balance (its route says
/// what it was): on no dollar ledger.
SwapOrderTransaction _bitcoinMove(String id, DateTime at) => _swap(id,
    coinFrom: 'BTC',
    networkFrom: 'SPARK',
    coinTo: 'USDC',
    networkTo: 'HYPERCORE',
    at: at,
    routeVersion: 'spark_to_hypercore_v1');

UsdbTokenTransaction _dollars(String id,
        {required double usd,
        required breez.PaymentType type,
        required DateTime at}) =>
    UsdbTokenTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: breez.Payment(
        id: id,
        paymentType: type,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from((usd * 1e6).round()),
        fees: BigInt.zero,
        timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.token,
        details: breez.PaymentDetails.token(
          metadata: breez.TokenMetadata(
            identifier: 'btkn1usdb',
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false,
          ),
          txHash: 'tx-$id',
          txType: breez.TokenTransactionType.transfer,
        ),
      ),
    );

PolymarketTransaction _bet(String id, DateTime at) => PolymarketTransaction(
      id: id,
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0xrain',
        type: 'TRADE',
        size: 10,
        usdcSize: 5,
        transactionHash: '0x$id',
        side: 'BUY',
        asset: 'yes',
        outcomeIndex: 0,
        title: 'Will it rain tomorrow?',
        outcome: 'Yes',
        eventSlug: '',
      ),
    );

HlFill _fill(DateTime at) => HlFill(
      coin: 'BTC',
      px: 60000,
      sz: 0.01,
      side: 'B',
      time: at.millisecondsSinceEpoch,
      closedPnl: 0,
      fee: 0.1,
      feeToken: 'USDC',
      oid: 1,
      hash: '0xfill',
      dir: 'Open Long',
      cloid: null,
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('mergePortfolioActivity', () {
    test('one list, newest first, every kind of row', () {
      final deposit = _dollars('dep',
          usd: 20, type: breez.PaymentType.receive, at: _t0);
      final move = _fundingMove(
          'move', 'HYPERCORE', _t0.add(const Duration(minutes: 1)));
      final bet = _bet('bet', _t0.add(const Duration(minutes: 2)));
      final fill = _fill(_t0.add(const Duration(minutes: 3)));
      final entries = mergePortfolioActivity(
        dollarRows: [move, deposit],
        swaps: [move],
        bets: [bet],
        fills: [fill],
      );
      expect(entries.map((e) => e.tx?.id ?? 'fill:${e.fill!.hash}'),
          ['fill:0xfill', 'bet', 'move', 'dep']);
      expect(entries.map((e) => e.time.millisecondsSinceEpoch), [
        fill.time,
        bet.timestamp.millisecondsSinceEpoch,
        move.timestamp.millisecondsSinceEpoch,
        deposit.timestamp.millisecondsSinceEpoch,
      ]);
    });

    test('a move the dollar ledger lists is one row, not two', () {
      final move = _fundingMove('move', 'POLYGON', _t0);
      final entries = mergePortfolioActivity(
          dollarRows: [move], swaps: [move], bets: [], fills: []);
      expect(entries, hasLength(1));
    });

    test('a venue move the dollar ledger does not carry is still listed',
        () {
      final old = _bitcoinMove('old', _t0);
      final entries = mergePortfolioActivity(
          dollarRows: [], swaps: [old], bets: [], fills: []);
      expect(entries.single.tx?.id, 'old');
    });

    test('a conversion that is no venue move is the dollar ledger\'s call',
        () {
      // Bitcoin into dollars: on the ledger, listed; not on it, not.
      final buy = _swap('buy',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          at: _t0);
      expect(
          mergePortfolioActivity(
              dollarRows: [buy], swaps: [buy], bets: [], fills: []),
          hasLength(1));
      expect(
          mergePortfolioActivity(
              dollarRows: [], swaps: [buy], bets: [], fills: []),
          isEmpty);
    });
  });

  // The Dollars ↔ venue moves the Bitcoin tab no longer lists (they moved
  // no bitcoin) are this list's: each one row, through the dollar ledger.
  test(
      'Dollars and venue moves, sweeps and the CCTP withdrawal included, '
      'are each listed once', () {
    final deposit = _fundingMove('to_hl', 'HYPERCORE', _t0);
    final cctp = _swap('cctp',
        coinFrom: 'USDC',
        networkFrom: 'HYPERCORE',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        at: _t0.add(const Duration(minutes: 5)),
        routeVersion: 'hypercore_cctp_v1');
    final pmSweep = _swap('pm_sweep',
        coinFrom: 'USDC.E',
        networkFrom: 'POLYGON',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        at: _t0.add(const Duration(minutes: 9)));
    final toPm =
        _fundingMove('to_pm', 'POLYGON', _t0.add(const Duration(minutes: 12)));
    const kinds = {
      'to_hl': SwapActivityKind.investingDeposit,
      'cctp': SwapActivityKind.investingWithdrawal,
      'pm_sweep': SwapActivityKind.predictionsWithdrawal,
      'to_pm': SwapActivityKind.predictionsDeposit,
    };
    final swaps = [toPm, pmSweep, cctp, deposit];
    final dollarRows = assembleActivityRows(
      swaps,
      ownAddresses: const {'sp1self'},
      isHardwareOrWatchOnly: false,
      onlyUsdb: true,
      classify: (o) => kinds[o.id]!,
    );
    final entries = mergePortfolioActivity(
        dollarRows: dollarRows, swaps: swaps, bets: [], fills: []);
    expect(
        entries.map((e) => e.tx?.id), ['to_pm', 'pm_sweep', 'cctp', 'to_hl']);
  });

  group('the Portfolio screen\'s Activity', () {
    Future<void> pump(WidgetTester tester, {Transaction? history}) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            ...portfolioOverrides(history: history),
            ...offlineVenueOverrides,
            settingsProvider.overrideWith((_) => SettingsModel(Settings(
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: false,
                biometricsEnabled: false,
                bitcoinElectrumNode: '',
                nodeType: '',
                reviewDone: true,
                activeWalletId: 'spending',
                wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
          ],
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              theme: ThemeData(
                  splashFactory: NoSplash.splashFactory,
                  fontFamily: 'Inter',
                  extensions: [AppColorsExtension.light()]),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const OpenInvestmentsScreen(source: 'test'),
            ),
          )));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
        'one merged list, no venue switch: the dollar deposit, the funding '
        'move and the prediction on the same day cards', (tester) async {
      await pump(tester,
          history: Transaction(
            bitcoinTransactions: const [],
            sparkTransactions: const [],
            sparkUnclaimedDeposits: const [],
            usdbTokenTransactions: [
              _dollars('dep',
                  usd: 20, type: breez.PaymentType.receive, at: _t0),
            ],
            swapOrderTransactions: [
              _fundingMove(
                  'move', 'POLYGON', _t0.add(const Duration(minutes: 1))),
            ],
            polymarketTransactions: [
              _bet('bet', _t0.add(const Duration(days: 1))),
            ],
          ));
      expect(find.byType(PortfolioActivitySliver), findsOneWidget);
      // Under its heading; never traded, so nothing above it.
      expect(find.byKey(const ValueKey('portfolio-activity-heading')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('statistics-chart-empty')),
          findsNothing);
      expect(find.byKey(const ValueKey('portfolio-activity-trading')),
          findsNothing);
      expect(find.byKey(const ValueKey('portfolio-activity-predictions')),
          findsNothing);
      // The prediction, a day later, on its own day card above the
      // deposit and the move.
      expect(find.byType(ActivityDaySection), findsNWidgets(2));
      expect(find.text('Prediction · Yes'), findsOneWidget);
      final bet = tester.getTopLeft(find.text('Prediction · Yes')).dy;
      final days = find.byType(ActivityDaySection);
      expect(tester.getTopLeft(days.at(0)).dy, lessThan(bet + 1));
      expect(tester.getTopLeft(days.at(1)).dy, greaterThan(bet));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'nothing yet, never traded: the page is the app\'s one empty state',
        (tester) async {
      await pump(tester);
      expect(find.byType(PortfolioActivitySliver), findsNothing);
      expect(find.byKey(const ValueKey('portfolio-activity-heading')),
          findsNothing);
      expect(find.text('No history yet'), findsOneWidget);
      expect(find.byType(NoActivityState), findsOneWidget);
      expect(find.byType(ActivityDaySection), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
