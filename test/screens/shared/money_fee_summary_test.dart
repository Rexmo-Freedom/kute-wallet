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
import 'package:kute/screens/shared/slip_stat_tiles.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
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
          orchestraFeeEstimateProvider(feeEstimateKey(route))
              .overrideWith((_) async => quote),
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
          orchestraFeeEstimateProvider(feeEstimateKey(route))
              .overrideWith((_) async => quote),
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

  testWidgets('a move fee is folded into the venue fee row, one detail',
      (tester) async {
    const terms = PolymarketFeeTerms(
        rate: 0.03, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);
    await tester.pumpWidget(_host(
        const Column(mainAxisSize: MainAxisSize.min, children: [
          // 40 shares at 50c: $0.30 to Polymarket, $0.04 to Kute, plus
          // the $1.03 move = $1.37 in the one row.
          PolymarketFeeSummary(
              tokenId: 'yes',
              shares: 40,
              price: 0.5,
              bitcoinFirst: false,
              showNote: false,
              moveFeeUsd: 1.03),
          // No Kute fee on this one and no account to price the exchange
          // fee: the move is the whole figure.
          HyperliquidFeeSummary(
              notional: 20,
              spot: false,
              buy: true,
              builder: false,
              useHotAccount: false,
              moveFeeUsd: 1.03),
        ]),
        overrides: [
          polymarketFeeTermsProvider.overrideWith((ref, _) async => terms),
        ]));
    await tester.pumpAndSettle();
    expect(find.text('Estimated fee'), findsNWidgets(2));
    expect(find.text(r'$1.37'), findsOneWidget);
    expect(find.text(r'$1.03'), findsOneWidget);
    expect(find.text('Move fee'), findsNothing);
    // Each breakdown opens in its own bottom sheet, one line per part.
    final sheet = find.byKey(const ValueKey('money-fee-breakdown-sheet'));
    await tester.tap(find.text(r'$1.37'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    for (final part in ['Polymarket fee', 'Kute fee', 'Move fee']) {
      expect(find.descendant(of: sheet, matching: find.text(part)),
          findsOneWidget);
    }
    expect(find.descendant(of: sheet, matching: find.text(r'$1.03')),
        findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    await tester.tap(find.text(r'$1.03'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: sheet, matching: find.text('Move fee')),
        findsOneWidget);
    expect(
        find.descendant(of: sheet, matching: find.text('Exchange fee estimate')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a move whose cost is still being read holds the fee row',
      (tester) async {
    const terms = PolymarketFeeTerms(
        rate: 0.03, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);
    await tester.pumpWidget(_host(
        const Column(mainAxisSize: MainAxisSize.min, children: [
          PolymarketFeeSummary(
              tokenId: 'yes',
              shares: 40,
              price: 0.5,
              bitcoinFirst: false,
              showNote: false,
              moveFeePending: true),
          HyperliquidFeeSummary(
              notional: 20,
              spot: false,
              buy: true,
              builder: false,
              useHotAccount: false,
              moveFeePending: true),
        ]),
        overrides: [
          polymarketFeeTermsProvider.overrideWith((ref, _) async => terms),
        ]));
    // "Calculating…" spins, so settle by hand: the terms arrive on the
    // next frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Calculating…'), findsNWidgets(2));
    expect(find.text(r'$0.34'), findsNothing);
    expect(find.text(r'$0.00'), findsNothing);
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
    final before = tester.getSize(find.byType(RepaintBoundary).first);
    await tester.tap(find.text(r'$0.12'));
    await tester.pumpAndSettle();
    // In a bottom sheet: the summary under it did not grow.
    final sheet = find.byKey(const ValueKey('money-fee-breakdown-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('Kute fee')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet,
            matching: find.text('Final fee depends on the fill price.')),
        findsOneWidget);
    expect(tester.getSize(find.byType(RepaintBoundary).first), before);
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
    // The breakdown opens as ordinary rows in a sheet, not as captions.
    expect(find.text('Kute fee'), findsNothing);
    await tester.tap(find.text(r'Fee about $0.12'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('money-fee-breakdown-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('Kute fee')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(r'$0.10')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the fee figure on a slip', () {
    const parts = [
      MoneyFeeSummary(
          label: 'Polymarket fee', usd: 0.30, bitcoinFirst: false),
      MoneyFeeSummary(label: 'Kute fee', usd: 0.04, bitcoinFirst: false),
      MoneyFeeSummary(label: 'Move fee', usd: 1.03, bitcoinFirst: false),
    ];
    // The slip's two figures at the founder's phone width: the fee in
    // the right half.
    Widget slip(MoneyFeeSummary fee) => SizedBox(
          width: 370,
          child: SlipFigures(
            left: const SlipFigure(label: 'Payout', value: r'$20.68'),
            right: KeyedSubtree(
              key: const ValueKey('fee'),
              child: MoneyFeeFigure(child: fee),
            ),
          ),
        );
    final figure = find.byKey(const ValueKey('fee'));

    testWidgets('a tap opens the breakdown in a sheet; the figure never grows',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(slip(const MoneyFeeSummary(
          usd: 1.37, bitcoinFirst: false, details: parts))));
      await tester.pumpAndSettle();
      final height = tester.getSize(figure).height;
      // A title and one number: no box, no line under it, no parts.
      expect(find.descendant(of: figure, matching: find.text(r'$1.37')),
          findsOneWidget);
      expect(find.text('Polymarket fee'), findsNothing);

      await tester.tap(figure);
      await tester.pumpAndSettle();
      expect(tester.getSize(figure).height, height);
      expect(find.descendant(of: figure, matching: find.text('Kute fee')),
          findsNothing);
      final sheet = find.byKey(const ValueKey('money-fee-breakdown-sheet'));
      expect(sheet, findsOneWidget);
      // One line per part: the longest label is no taller than the
      // shortest, and each sits on the amount's line.
      final one = tester.getSize(find.text('Kute fee')).height;
      for (final part in ['Polymarket fee', 'Move fee']) {
        final label = find.descendant(of: sheet, matching: find.text(part));
        expect(tester.getSize(label).height, one, reason: part);
      }
      expect(
          tester.getCenter(find.text('Polymarket fee')).dy,
          closeTo(
              tester
                  .getCenter(find.descendant(
                      of: sheet, matching: find.text(r'$0.30')))
                  .dy,
              1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'zero before there is a fee, never a dash; the last fee stays, '
        'dimmed, while the next is worked out', (tester) async {
      await tester.pumpWidget(_host(slip(const MoneyFeeSummary(
          bitcoinFirst: false, state: 'Enter an amount'))));
      await tester.pumpAndSettle();
      expect(find.descendant(of: figure, matching: find.text(r'$0')),
          findsOneWidget);
      expect(find.text('—'), findsNothing);
      // Nothing to open yet.
      await tester.tap(figure, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('money-fee-breakdown-sheet')),
          findsNothing);

      // The first fee is still being read: zero, dimmed, no dash and no
      // "Calculating…" line.
      await tester.pumpWidget(_host(slip(const MoneyFeeSummary(
          bitcoinFirst: false, state: 'Calculating…'))));
      await tester.pumpAndSettle();
      expect(find.descendant(of: figure, matching: find.text(r'$0')),
          findsOneWidget);
      expect(find.text('Calculating…'), findsNothing);
      expect(find.text('—'), findsNothing);

      await tester.pumpWidget(_host(slip(
          const MoneyFeeSummary(usd: 0.43, bitcoinFirst: false))));
      await tester.pumpAndSettle();
      expect(find.text(r'$0.43'), findsOneWidget);
      double opacity() => tester
          .widget<AnimatedOpacity>(find.descendant(
              of: figure, matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(), 1);

      // A new amount: the fee is worked out again, the last one stays.
      await tester.pumpWidget(_host(slip(const MoneyFeeSummary(
          bitcoinFirst: false, state: 'Calculating…'))));
      await tester.pump();
      expect(find.text(r'$0.43'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.text('Calculating…'), findsNothing);
      expect(opacity(), lessThan(1));

      // The amount cleared: zero again.
      await tester.pumpWidget(_host(slip(const MoneyFeeSummary(
          bitcoinFirst: false, state: 'Enter an amount'))));
      await tester.pumpAndSettle();
      expect(find.text(r'$0.43'), findsNothing);
      expect(find.descendant(of: figure, matching: find.text(r'$0')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed estimate keeps the figure and offers Retry in the '
        'sheet', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_host(slip(MoneyFeeSummary(
          bitcoinFirst: false,
          state: 'Estimate unavailable',
          onRetry: () => retries++))));
      await tester.pumpAndSettle();
      expect(find.text('Estimate unavailable'), findsNothing);
      await tester.tap(figure);
      await tester.pumpAndSettle();
      expect(find.text('Estimate unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
