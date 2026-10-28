// A refunded CCTP move's Activity detail (cctp_refund_outcome.dart): where
// the USDC went (the wallet's own address on Arbitrum, short, copied on
// tap) and how to move it, by the wallet's EVM key format. Read from the
// row alone: no balance reads, nothing on the Investing header.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/cctp_refund_outcome.dart';
import 'package:kute/screens/shared/investment_balance_header.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart'
    show kHypercoreCctpRouteVersion;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_swap_orders.dart';

const _owner = '0x1111111111111111111111111111111111112222';

SwapOrder _row(
        {String id = 'ord_1',
        String status = 'refunded',
        String? routeVersion,
        String refund = _owner,
        String? walletId = 'w1'}) =>
    SwapOrder(
      id: id,
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
      refundAddress: refund,
      provider: 'Orchestra',
      walletId: walletId,
      operationId: 'op1',
      routeVersion: routeVersion ?? kHypercoreCctpRouteVersion,
    );

Future<void> _pump(WidgetTester tester, Widget child,
    {EvmDerivationVersion? version = EvmDerivationVersion.standardBip39}) async {
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
              activeWalletId: 'w1',
              wallets: [
                if (version != null)
                  WalletConfig(
                      id: 'w1', name: 'Spending', evmDerivationVersion: version),
              ],
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

String _returnedLine(WidgetTester tester) => tester
    .widget<RichText>(find.descendant(
        of: find.byKey(const ValueKey('cctp-move-returned')),
        matching: find.byType(RichText)).first)
    .text
    .toPlainText();

String? _how(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('cctp-move-returned-how')))
    .data;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('which rows are refunded CCTP moves', () {
    expect(isRefundedCctpMoveRow(_row()), isTrue);
    expect(isRefundedCctpMoveRow(_row(id: 'cctp-op1', routeVersion: 'x_v1')),
        isTrue);
    expect(isRefundedCctpMoveRow(_row(status: 'success')), isFalse);
    expect(isRefundedCctpMoveRow(_row(routeVersion: 'other_v1')), isFalse);
  });

  testWidgets(
      'the Investing header says nothing of Arbitrum: the refund is only on '
      'its move\'s sheet', (tester) async {
    await _pump(tester,
        const InvestmentBalanceHeader(product: InvestmentsProduct.trading));
    expect(
        tester
            .widget<PoolBalanceHeader>(find.byType(PoolBalanceHeader))
            .balanceDetail,
        isNull);
    expect(find.textContaining('Arbitrum'), findsNothing);
  });

  group("a refunded CCTP move's Activity detail", () {
    testWidgets(
        'standard key format: refunded to the Arbitrum address, short; to '
        'move it, MetaMask with the same recovery phrase; no button',
        (tester) async {
      await _pump(tester, CctpRefundOutcome(row: _row()));
      expect(_returnedLine(tester),
          startsWith('Refunded to your Arbitrum address 0x11111111…11112222.'));
      expect(_how(tester),
          'To move it, use a wallet like MetaMask with the same recovery phrase.');
      // Plain captions: nothing to press but the line itself.
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap on the line copies the full address, tracked by type',
        (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, CctpRefundOutcome(row: _row()));
      await tester.tap(find.byKey(const ValueKey('cctp-move-returned')));
      await tester.pump();
      expect(copied, _owner);
      expect(events.single.$1, 'address_copied');
      expect(events.single.$2, {'type': 'cctp_refund'});
      // Let the toast run out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    for (final version in [EvmDerivationVersion.legacySha256, null]) {
      testWidgets(
          '${version == null ? 'a wallet the row cannot be tied to' : 'legacy key format'}: '
          'never MetaMask, contact Support', (tester) async {
        await _pump(tester, CctpRefundOutcome(row: _row()), version: version);
        expect(_returnedLine(tester),
            startsWith('Refunded to your Arbitrum address '));
        expect(_how(tester), 'To move it, contact Support.');
        expect(find.textContaining('MetaMask'), findsNothing);
      });
    }

    testWidgets(
        'not refunded, not a CCTP move, or no refund address: nothing',
        (tester) async {
      for (final row in [
        _row(status: 'success'),
        _row(routeVersion: 'other_route_v1'),
        _row(refund: ''),
      ]) {
        await _pump(tester, CctpRefundOutcome(row: row));
        expect(find.byKey(const ValueKey('cctp-move-returned')), findsNothing);
        expect(
            find.byKey(const ValueKey('cctp-move-returned-how')), findsNothing);
      }
    });
  });
}
