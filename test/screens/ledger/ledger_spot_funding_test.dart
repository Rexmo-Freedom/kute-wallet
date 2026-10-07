import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_config_provider.dart';
import 'package:kute/providers/ledger/ledger_executors_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_transfer_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _CurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _CurrencyNotifier() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

const _walletId = 'ledger-spot-deposit';
const _address = '0x14791697260E4c9A71f18484C9f997B308e59325';
// CI runs this file with the production default and with explicit
// acceptance of the opaque Hyperliquid actions (O1). The spot to perps
// transfer is readable on the device, so it is offered either way: the
// build define must change nothing below.

Future<void> _pump(
  WidgetTester tester,
  Widget sheet, {
  List<HlSpotBalance> spot = const [
    HlSpotBalance(coin: 'USDC', total: 25, hold: 5),
  ],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currencyProvider.overrideWith((_) => _CurrencyNotifier()),
      hyperliquidGeoAllowedProvider.overrideWithValue(true),
      hyperliquidTradingEnabledProvider.overrideWithValue(true),
      ledgerHlExecutorFactoryProvider.overrideWith((_) =>
          throw StateError('Opening funding must not initialize signing')),
      ledgerHlAccountProvider(_walletId)
          .overrideWith((_) async => LedgerHlAccount(
                walletId: _walletId,
                address: _address,
                account: HlAccountSnapshot(
                  accountValue: 0,
                  withdrawable: 0,
                  totalMarginUsed: 0,
                  positions: const [],
                  spotBalances: spot,
                ),
              )),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: sheet),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('spot cash opens scoped explicit transfer', (tester) async {
    await _pump(
      tester,
      const LedgerTransferSheet(walletId: _walletId),
    );
    final transfer =
        tester.widget<LedgerTransferSheet>(find.byType(LedgerTransferSheet));
    expect(transfer.walletId, _walletId);
    expect(transfer.initialToPerp, isTrue);
    // Held USDC is not made available, and opening the flow cannot sign.
    expect(find.text('Available: \$20.00'), findsOneWidget);
    final buttons = tester.widgetList<AppButton>(find.descendant(
        of: find.byType(LedgerTransferSheet),
        matching: find.byType(AppButton)));
    expect(buttons.first.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('held or non-USDC cash leaves nothing to move', (tester) async {
    await _pump(
      tester,
      const LedgerTransferSheet(walletId: _walletId),
      spot: const [
        HlSpotBalance(coin: 'USDC', total: 25, hold: 25),
        HlSpotBalance(coin: 'BTC', total: 1, hold: 0),
      ],
    );
    expect(find.text('Available: \$0.00'), findsOneWidget);
    expect(find.textContaining(r'$25.00'), findsNothing);
    final buttons = tester.widgetList<AppButton>(find.descendant(
        of: find.byType(LedgerTransferSheet),
        matching: find.byType(AppButton)));
    expect(buttons.first.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the perps side offers withdrawable cash, not spot',
      (tester) async {
    await _pump(
        tester,
        const LedgerTransferSheet(
            walletId: _walletId, initialToPerp: false));
    final transfer =
        tester.widget<LedgerTransferSheet>(find.byType(LedgerTransferSheet));
    expect(transfer.initialToPerp, isFalse);
    expect(find.textContaining(r'$20.00'), findsNothing);
    expect(find.text('Available: \$0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
