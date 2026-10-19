// USDC returned on Arbitrum on screen: the Investing header's quiet line
// and a refunded CCTP move's Activity detail (arbitrum_refund_lines.dart).
// The watch is a fake holding a fixed state: no RPC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/arbitrum_refund_provider.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/arbitrum_refund_lines.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/services/hyperliquid/arbitrum_refund_watch.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart'
    show kHypercoreCctpRouteVersion;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

const _owner = '0x1111111111111111111111111111111111111111';

class _NoReports implements ArbitrumRefundReports {
  @override
  Future<BigInt?> lastReported(String walletId) async => null;
  @override
  Future<void> setReported(String walletId, BigInt? usdc6) async {}
}

/// A watch already holding [fixed]; a scan never reads anything.
class _FixedWatch extends ArbitrumRefundWatch {
  _FixedWatch(ArbitrumRefundState fixed)
      : super(
          account: () async => null,
          knownRefund: (_) => false,
          readBalance: (_) async => throw StateError('no reads in tests'),
          reports: _NoReports(),
        ) {
    state = fixed;
  }
}

BigInt _usdc(double usd) => BigInt.from((usd * 1e6).round());

SwapOrder _row({String status = 'refunded', String? routeVersion}) => SwapOrder(
      id: 'ord_1',
      coinFrom: 'USDC',
      networkFrom: 'HYPERCORE',
      coinTo: 'USDB',
      networkTo: 'SPARK',
      depositAddress: '0xdeposit',
      depositAmount: '12.40',
      withdrawalAmount: '12.30',
      status: status,
      timestamp: 0,
      withdrawalAddress: 'spark1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: _owner,
      provider: 'Orchestra',
      walletId: 'w1',
      operationId: 'op1',
      routeVersion: routeVersion ?? kHypercoreCctpRouteVersion,
    );

Future<void> _pump(WidgetTester tester, Widget child,
    {required ArbitrumRefundState refund}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: '',
              reviewDone: true,
            ))),
        pendingPredictionsDepositUsdProvider.overrideWith((_) => 0),
        pendingPredictionsWithdrawalUsdProvider.overrideWith((_) => 0),
        pendingTradingDepositUsdProvider.overrideWith((_) => 0),
        pendingTradingWithdrawalUsdProvider.overrideWith((_) => 0),
        for (final product in InvestmentsProduct.values)
          investmentBalancesProvider(product).overrideWith((_) =>
              const InvestmentBalances(
                  available: 42,
                  portfolio: 58,
                  total: 100,
                  positions: 48,
                  committed: 0)),
        arbitrumRefundProvider.overrideWith((_) => _FixedWatch(refund)),
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      )));
  await tester.pumpAndSettle();
}

String? _detail(WidgetTester tester) => tester
    .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
    .balanceDetail;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the Investing header', () {
    testWidgets('balance found: one quiet line under the split',
        (tester) async {
      await _pump(tester,
          const InvestmentBalanceHeader(product: InvestmentsProduct.trading),
          refund: ArbitrumRefundState(usdc6: _usdc(12.4)));
      expect(_detail(tester), r'$12.40 returned on Arbitrum');
      expect(find.text(r'$12.40 returned on Arbitrum'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dust from a known refund: the line and the minimum note',
        (tester) async {
      await _pump(tester,
          const InvestmentBalanceHeader(product: InvestmentsProduct.trading),
          refund: ArbitrumRefundState(usdc6: _usdc(3.1), fromRefund: true));
      expect(_detail(tester),
          r'$3.10 returned on Arbitrum · Below the minimum to move');
    });

    testWidgets('dust with no refund, or nothing read: no line',
        (tester) async {
      await _pump(tester,
          const InvestmentBalanceHeader(product: InvestmentsProduct.trading),
          refund: ArbitrumRefundState(usdc6: _usdc(3.1)));
      expect(_detail(tester), isNull);
      await _pump(tester,
          const InvestmentBalanceHeader(product: InvestmentsProduct.trading),
          refund: ArbitrumRefundState.none);
      expect(_detail(tester), isNull);
    });

    testWidgets('Predictions never shows it', (tester) async {
      await _pump(
          tester,
          const InvestmentBalanceHeader(
              product: InvestmentsProduct.predictions),
          refund: ArbitrumRefundState(usdc6: _usdc(12.4)));
      expect(_detail(tester), isNull);
      expect(find.textContaining('Arbitrum'), findsNothing);
    });
  });

  group("a refunded CCTP move's Activity detail", () {
    testWidgets('says it was returned to the own address on Arbitrum',
        (tester) async {
      await _pump(tester, CctpRefundOutcome(row: _row()),
          refund: ArbitrumRefundState(usdc6: _usdc(12.4), fromRefund: true));
      final line = tester
          .widget<Text>(find.byKey(const ValueKey('cctp-move-returned')))
          .data!;
      expect(line, startsWith('Returned to 0x'));
      expect(line, endsWith(' on Arbitrum'));
      expect(find.byKey(const ValueKey('cctp-move-returned-below-minimum')),
          findsNothing);
      // No action is offered: nothing can pay the gas to move it.
      expect(find.byType(ButtonStyleButton), findsNothing);
    });

    testWidgets('below the Bridge2 minimum: the note under it', (tester) async {
      await _pump(tester, CctpRefundOutcome(row: _row()),
          refund: ArbitrumRefundState(usdc6: _usdc(3.1), fromRefund: true));
      expect(find.byKey(const ValueKey('cctp-move-returned')), findsOneWidget);
      expect(find.text('Below the minimum to move'), findsOneWidget);
    });

    testWidgets('not refunded, or not a CCTP move: nothing', (tester) async {
      await _pump(tester, CctpRefundOutcome(row: _row(status: 'success')),
          refund: ArbitrumRefundState(usdc6: _usdc(12.4)));
      expect(find.byKey(const ValueKey('cctp-move-returned')), findsNothing);
      await _pump(
          tester, CctpRefundOutcome(row: _row(routeVersion: 'other_route_v1')),
          refund: ArbitrumRefundState(usdc6: _usdc(12.4)));
      expect(find.byKey(const ValueKey('cctp-move-returned')), findsNothing);
    });
  });
}
