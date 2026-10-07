import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/screens/shared/orchestra_fee_summary.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _CurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _CurrencyNotifier([Map<String, Fixed> extra = const {}])
      : super(CurrencyState({'USD': Fixed.fromInt(100), ...extra}));
  @override
  Future<void> updateRates() async {}
}

Widget _host(Widget child,
        {double textScale = 1, List<Override> overrides = const []}) =>
    ProviderScope(
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
            ))),
        currencyProvider.overrideWith((ref) => _CurrencyNotifier()),
        ...overrides,
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme:
              buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SafeArea(
                  child:
                      Padding(padding: const EdgeInsets.all(20), child: child)),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => Intl.defaultLocale = 'en_US');
  tearDown(() => Intl.defaultLocale = null);

  testWidgets(
      'conversion summary leads with the whole cost and lists the full quote',
      (tester) async {
    const route = (
      fromChain: 'spark',
      fromAsset: 'BTC',
      toChain: 'hypercore',
      toAsset: 'USDC',
      amount: '100000'
    );
    // 100,000 sats at \$100,000 per bitcoin is \$100 sent. 98 USDC is
    // quoted out before a 0.5% Kute fee (\$0.49), so \$97.51 arrives and
    // the transfer costs \$2.49 in all.
    final quote = OrchestraEstimate.fromJson({
      'feeBps': 10,
      'feeAmount': '81419',
      'totalFeeAmount': '1041619',
      'feeAsset': 'USDC',
      'feeAssetDetails': {'chain': 'solana', 'asset': 'USDC', 'decimals': 6},
      'estimatedOut': '9800000000',
      'destination': {'chain': 'hypercore', 'asset': 'USDC', 'decimals': 8},
    }, headers: {
      'x-kute-app-fee-bps': '50',
      'x-kute-estimate-includes-app-fee': 'false',
    });
    await tester.pumpWidget(_host(
        const OrchestraFeeSummary(route: route, bitcoinFirst: false),
        overrides: [
          currencyProvider.overrideWith((ref) => _CurrencyNotifier(
              {'BTC': Fixed.parse('0.00001', decimalDigits: 8)})),
          orchestraFeeEstimateProvider(route).overrideWith((_) async => quote),
        ]));
    await tester.pumpAndSettle();
    // The headline is what does not arrive, not the declared fees.
    expect(find.text(r'$2.49'), findsOneWidget);
    expect(find.text('Shown before you confirm'), findsNothing);
    await tester.tap(find.text(r'$2.49'));
    await tester.pumpAndSettle();
    // The provider row is the full quote, never the bare platform rate.
    expect(find.text('Provider fee'), findsOneWidget);
    expect(find.text(r'$1.04'), findsOneWidget);
    expect(find.text(r'$0.08'), findsNothing);
    expect(find.text(r'< $0.01'), findsNothing);
    expect(find.text(r'$0.49'), findsOneWidget);
    // The route's own cost inside the output makes up the rest.
    expect(find.text('Network fee'), findsOneWidget);
    expect(find.text(r'$0.96'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversion summary never presents declared fees as the cost',
      (tester) async {
    const route = (
      fromChain: 'spark',
      fromAsset: 'BTC',
      toChain: 'hypercore',
      toAsset: 'USDC',
      amount: '100000'
    );
    // No bitcoin price and no Kute rate: the whole cost cannot be worked
    // out, so the block quotes nothing rather than the provider's figure.
    final quote = OrchestraEstimate.fromJson({
      'feeBps': 10,
      'feeAmount': '81419',
      'totalFeeAmount': '1041619',
      'feeAsset': 'USDC',
      'feeAssetDetails': {'chain': 'solana', 'asset': 'USDC', 'decimals': 6},
      'estimatedOut': '8009000000',
      'destination': {'chain': 'hypercore', 'asset': 'USDC', 'decimals': 8},
    });
    await tester.pumpWidget(_host(
        const OrchestraFeeSummary(route: route, bitcoinFirst: false),
        overrides: [
          orchestraFeeEstimateProvider(route).overrideWith((_) async => quote),
        ]));
    await tester.pumpAndSettle();
    expect(find.text('Shown before you confirm'), findsOneWidget);
    expect(find.text(r'$1.04'), findsNothing);
    expect(find.text(r'< $0.01'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('small positive fees never look free in either unit', () {
    final value = formatFeeAmount(
        usd: 0.0001,
        currency: 'USD',
        btcFormat: 'sats',
        bitcoinFirst: false,
        usdPerBtc: 100000);
    expect(value.primary, r'< $0.01');
    expect(value.secondary, '< ₿1');
    final zero = formatFeeAmount(
        usd: 0,
        currency: 'USD',
        btcFormat: 'sats',
        bitcoinFirst: false,
        usdPerBtc: 100000);
    expect(zero.primary, r'$0.00');
  });

  test('missing conversion rates retain the known source denomination', () {
    final dollars = formatFeeAmount(
        usd: 1.25, currency: 'EUR', btcFormat: 'sats', bitcoinFirst: true);
    expect(dollars.primary, r'$1.25 USD');
    expect(dollars.secondary, isNull);
    final bitcoin = formatFeeAmount(
        sats: 2000, currency: 'EUR', btcFormat: 'sats', bitcoinFirst: false);
    expect(bitcoin.primary, '₿2,000');
    expect(bitcoin.secondary, isNull);
  });

  test('invalid values stay unavailable instead of showing zero or NaN', () {
    for (final amount in [double.nan, double.infinity, -1.0]) {
      expect(
          formatFeeAmount(
                  usd: amount,
                  currency: 'USD',
                  btcFormat: 'sats',
                  bitcoinFirst: false)
              .primary,
          'Unavailable');
    }
  });

  test('fee formatting follows locale and selected currency', () {
    Intl.defaultLocale = 'pt_PT';
    final value = formatFeeAmount(
        usd: 1.25,
        currency: 'EUR',
        btcFormat: 'sats',
        bitcoinFirst: false,
        fiatPerUsd: 0.8);
    expect(value.primary, NumberFormat.simpleCurrency(name: 'EUR').format(1));
  });

  testWidgets(
      'empty trading accounts show funding state before amount or quote',
      (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      PolymarketFeeSummary(
          tokenId: null,
          shares: 0,
          price: 0,
          bitcoinFirst: false,
          hasFunds: false),
      HyperliquidFeeSummary(
          notional: 0, spot: false, buy: true, hasFunds: false),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Add funds to continue'), findsNWidgets(2));
    expect(find.text('Enter an amount'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed estimate offers a separate working retry on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    await tester.pumpWidget(_host(
        MoneyFeeSummary(
          state: 'Estimate unavailable',
          onRetry: () => retries++,
        ),
        textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Estimate unavailable'), findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fee details are available without crowding the amount',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const MoneyFeeSummary(
              usd: 0.12,
              bitcoinFirst: false,
              note: 'Final fee depends on the fill price.',
              details: [
                MoneyFeeSummary(
                    label: 'Kute fee', usd: 0.1, bitcoinFirst: false)
              ]),
          MoneyFeeSummary(state: 'Estimate unavailable', onRetry: () {}),
          const MoneyFeeSummary(state: 'Add funds to continue'),
        ]))));
    await tester.pumpAndSettle();
    expect(find.text(r'$0.12'), findsOneWidget);
    expect(find.text('Kute fee'), findsNothing);
    await tester.tap(find.text(r'$0.12'));
    await tester.pumpAndSettle();
    expect(find.text('Kute fee'), findsOneWidget);
    expect(find.text('Final fee depends on the fill price.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('under a caption scope the fee is one line with its breakdown',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(_host(MoneyFeeCaption(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      const MoneyFeeSummary(usd: 0.12, bitcoinFirst: false, details: [
        MoneyFeeSummary(label: 'Kute fee', usd: 0.1, bitcoinFirst: false)
      ]),
      const MoneyFeeSummary(label: 'Fees', state: 'Calculating…'),
      MoneyFeeSummary(
          label: 'Fees',
          state: 'Estimate unavailable',
          onRetry: () => retries++),
      const MoneyFeeSummary(
          label: 'Fees', state: 'Shown before you confirm'),
      // Nothing to say: the button and the source row already say it.
      const MoneyFeeSummary(state: 'Add funds to continue'),
      const MoneyFeeSummary(state: 'Enter an amount'),
      const MoneyFeeSummary(state: 'Insufficient balance'),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text(r'Fee about $0.12'), findsOneWidget);
    expect(find.text('Estimated fee'), findsNothing);
    expect(find.text('Calculating…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Fees · Shown before you confirm'), findsOneWidget);
    expect(find.text('Add funds to continue'), findsNothing);
    expect(find.text('Enter an amount'), findsNothing);
    expect(find.text('Insufficient balance'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    // The breakdown opens as ordinary rows, not as captions.
    expect(find.text('Kute fee'), findsNothing);
    await tester.tap(find.text(r'Fee about $0.12'));
    await tester.pumpAndSettle();
    expect(find.text('Kute fee'), findsOneWidget);
    expect(find.text(r'$0.10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
