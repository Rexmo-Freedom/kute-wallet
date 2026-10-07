// Max out of Investing must send what the account can actually send.
//
// João's report: Max from Investing into Dollars said "The move could not
// be completed", while a typed $5 went through. Max sends the whole
// balance, and the HyperCore send checks it against the account read
// again: perpetuals cash first, the rest moved over from spot. A balance
// like $19.99 arrives as the double 19.989999999..., and the check
// floored it to 1998999999 eight-decimal units while the amount (rounded)
// was 1999000000. One unit short, it asked spot for a micro-dollar spot
// did not have and refused the move. $5 never needed spot. The same Max
// failed into Bitcoin on any balance that reads this way.
//
// These pump the real sheet, tap Max and Continue, and hand the amount
// it sends to the same budget, reserve and shortfall checks the HyperCore
// send runs before anything is signed.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

const _usdPerBtc = 100000.0;
const _account = '0x1111111111111111111111111111111111111111';
const _depositAddress = '0x2222222222222222222222222222222222222222';
const _generic = 'The move could not be completed. Check its status before '
    'trying again.';
const _insufficient = 'Insufficient balance';

MockClient _orchestra() => MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      final asset = request.url.queryParameters['destinationAsset']!;
      final chain = request.url.queryParameters['destinationChain']!;
      final amount = request.url.queryParameters['amount'] ?? '0';
      final usd = (BigInt.tryParse(amount) ?? BigInt.zero).toDouble() / 1e8;
      final out = doubleToOrchestraAmount(
          asset == 'BTC' ? usd / _usdPerBtc : usd, asset,
          chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({'USD': Fixed.fromInt(_usdPerBtc.round())}));

  @override
  Future<void> updateRates() async {}
}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

/// The Investing account as the venue reports it, every read.
class _Account extends HlAccountNotifier {
  _Account(this.snapshot);
  final HlAccountSnapshot snapshot;

  @override
  Future<HlAccountSnapshot> build() async => snapshot;
}

/// What the HyperCore send checks before it signs anything, run on the
/// amount the sheet asks for against the same account: the quote budget
/// (floored to the usdSend's six decimals), the sender's reserve and the
/// perpetuals shortfall spot has to cover. A refusal is thrown exactly
/// as the real send throws it; a pass parks the move in flight.
class _Hypercore extends SparkHypercoreFundingService {
  _Hypercore(super.read, this.account);

  /// The account the send reads when it checks. Same as the sheet's
  /// unless a test moves it in between.
  HlAccountSnapshot account;
  final sent = <({double usd, SparkFundingAsset destination})>[];
  final requested = <BigInt>[];

  @override
  Future<void> ensureAvailable({required bool deposit}) async {}

  @override
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
  }) async {
    sent.add((usd: usd, destination: destination));
    final quoted = await quoteHypercoreBudget<BigInt>(
      budget: hypercoreUsdcBaseUnits(usd),
      request: (amount, _) async => HypercoreBudgetQuote(
          value: amount,
          amount: amount,
          activationFee: await hypercoreUsdSendSenderFee(_depositAddress)),
    );
    requested.add(quoted.amount);
    final reserve = hypercoreTransferReserve(
      amountBaseUnits: quoted.amount,
      currentFeeBaseUnits: quoted.activationFee,
      reviewedFeeBaseUnits: quoted.activationFee,
    );
    hypercorePerpShortfall(
      requiredBaseUnits: reserve,
      activationFeeBaseUnits: reserve - quoted.amount,
      spotAvailable: hypercoreAvailableUsdc(0, account.spotBalances),
      perpAvailable: account.withdrawable,
    );
    return Completer<DirectHypercoreResult>().future;
  }
}

HlAccountSnapshot _snapshot({
  required double perp,
  double spot = 0,
  double spotHold = 0,
  bool position = false,
}) =>
    HlAccountSnapshot(
      accountValue: perp + (position ? 40 : 0),
      withdrawable: perp,
      totalMarginUsed: position ? 40 : 0,
      positions: [
        if (position)
          HlPerpPosition.fromJson({
            'coin': 'BTC',
            'szi': '0.004',
            'entryPx': '100000',
            'positionValue': '400',
            'unrealizedPnl': '0',
            'returnOnEquity': '0',
            'liquidationPx': '80000',
            'marginUsed': '40',
            'leverage': {'type': 'cross', 'value': 10},
          }),
      ],
      spotBalances: [
        if (spot > 0) HlSpotBalance(coin: 'USDC', total: spot, hold: spotHold),
      ],
    );

Future<(ProviderContainer, _Hypercore)> _open(
    WidgetTester tester, HlAccountSnapshot account) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _Hypercore hypercore;
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => _Settings()),
    currencyProvider.overrideWith((_) => _Currency()),
    hyperliquidAddressProvider.overrideWith((_) async => _account),
    hyperliquidAccountProvider.overrideWith(() => _Account(account)),
    sparkHypercoreFundingServiceProvider
        .overrideWith((ref) => hypercore = _Hypercore(ref.read, account)),
  ]);
  await http.runWithClient(
    () => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme:
              buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DepositSheet(
              lockedSide: MoveLockedSide.withdrawFromHyperliquid),
        ),
      ),
    )),
    _orchestra,
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  container.read(sparkHypercoreFundingServiceProvider);
  return (container, hypercore);
}

Future<void> _pickDollars(WidgetTester tester) async {
  await tester.tap(find.text('Bitcoin').first);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  await tester.tap(find.text('Dollars').last);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> _maxAndContinue(WidgetTester tester) async {
  await tester.tap(find.text('Max'));
  await tester.pump();
  await tester.tap(find.byType(AppButton).last);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  // Balances as the venue prints them. 19.99 and 0.29 are among the
  // values whose double sits just under the decimal.
  final cases = <String, (HlAccountSnapshot, BigInt)>{
    'perpetuals only, \$19.99': (
      _snapshot(perp: 19.99),
      BigInt.from(1999000000)
    ),
    'perpetuals and spot, \$23.456789 + \$0.29': (
      _snapshot(perp: 23.456789, spot: 0.29),
      BigInt.from(2374678900)
    ),
    'spot with dust and a held part, \$23.456789 + \$0.12345678 - 0.1': (
      _snapshot(perp: 23.456789, spot: 0.12345678, spotHold: 0.1),
      BigInt.from(2348024500)
    ),
    'an open position, \$19.99 withdrawable': (
      _snapshot(perp: 19.99, position: true),
      BigInt.from(1999000000)
    ),
  };

  for (final dollars in [true, false]) {
    final to = dollars ? 'Dollars' : 'Bitcoin';
    for (final MapEntry(key: name, value: (account, expected))
        in cases.entries) {
      testWidgets('Investing → $to: Max sends everything ($name)',
          (tester) async {
        final (container, hypercore) = await _open(tester, account);
        if (dollars) await _pickDollars(tester);
        await _maxAndContinue(tester);

        expect(hypercore.sent, hasLength(1));
        expect(hypercore.sent.single.destination,
            dollars ? SparkFundingAsset.dollars : SparkFundingAsset.bitcoin);
        // The whole sendable balance, nothing held back.
        expect(hypercore.requested.single, expected);
        expect(find.text(_generic), findsNothing);
        expect(find.text(_insufficient), findsNothing);
        expect(tester.widget<AppButton>(find.byType(AppButton).last).isLoading,
            isTrue,
            reason: 'the move passed every check and is in flight');
        await _close(tester, container);
      });
    }
  }

  testWidgets(
      'Investing → Dollars: a real shortfall says so, not "could not be '
      'completed"', (tester) async {
    // The account reads \$10 at Max and \$9.50 by the time the send
    // checks it (a position moved), with nothing in spot to cover it.
    final (container, hypercore) = await _open(tester, _snapshot(perp: 10));
    await _pickDollars(tester);
    hypercore.account = _snapshot(perp: 9.5);
    await _maxAndContinue(tester);

    expect(hypercore.sent.single.usd, 10);
    expect(find.text(_generic), findsNothing);
    expect(find.text(_insufficient), findsWidgets);
    expect(tester.widget<AppButton>(find.byType(AppButton).last).isLoading,
        isFalse);
    await _close(tester, container);
  });
}
