// A Cash App deposit into Investing or Predictions is created through
// /onramp, which the backend charges at the fiat deposit rule (100 bps),
// not the venue rule a quote would use (50 bps). The fee block on that
// route asks the estimate with onramp=true so the Kute fee and what
// arrives are the ones the order is charged. Every other route asks
// without the flag and shows exactly what it did before.
//
// A Cash App purchase of Dollars is the same kind of order (1%
// fiat_deposit): its block shows the Kute fee and "You receive" before
// Continue, and both match what the order charges to within one base unit.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/orchestra_fee_summary.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/source_scan.dart';

class _CurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  // $100,000 per bitcoin.
  _CurrencyNotifier()
      : super(CurrencyState({
          'USD': Fixed.fromInt(100),
          'BTC': Fixed.parse('0.00001', decimalDigits: 8),
        }));
  @override
  Future<void> updateRates() async {}
}

Widget _host(Widget child, List<Override> overrides) => ProviderScope(
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
            body: SafeArea(
                child:
                    Padding(padding: const EdgeInsets.all(20), child: child)),
          ),
        ),
      ),
    );

// The Cash App → Investing route the Move sheet prices: 25,000 sats of
// Lightning bitcoin ($25) into HyperCore USDC.
const _route = (
  fromChain: 'lightning',
  fromAsset: 'BTC',
  toChain: 'hypercore',
  toAsset: 'USDC',
  amount: '25000'
);

/// The estimate as the backend serves it: 24.75 USDC out before the Kute
/// fee, a 3 cent provider fee, and the Kute rate in the headers.
OrchestraEstimate _estimate({required int bps, int discount = 0}) =>
    OrchestraEstimate.fromJson({
      'feeBps': 10,
      'feeAmount': '0',
      'totalFeeAmount': '30000',
      'totalFeeAmountUsd': '0.03',
      'feeAsset': 'USDC',
      'feeAssetDetails': {'chain': 'hypercore', 'asset': 'USDC', 'decimals': 6},
      'estimatedOut': '2475000000',
      'destination': {'chain': 'hypercore', 'asset': 'USDC', 'decimals': 8},
    }, headers: {
      'x-kute-app-fee-bps': '$bps',
      'x-kute-referral-discount-bps': '$discount',
      'x-kute-estimate-includes-app-fee': 'false',
    });

// The Cash App → Dollars route: 25,000 sats of Lightning bitcoin ($25)
// into the spending account's dollars (USDB on Spark, 6 decimals).
const _dollarsRoute = (
  fromChain: 'lightning',
  fromAsset: 'BTC',
  toChain: 'spark',
  toAsset: 'USDB',
  amount: '25000'
);

/// 24.75 USDB out before the Kute fee, a 3 cent provider fee.
OrchestraEstimate _dollarsEstimate({required int bps}) =>
    OrchestraEstimate.fromJson({
      'feeBps': 10,
      'feeAmount': '0',
      'totalFeeAmount': '30000',
      'totalFeeAmountUsd': '0.03',
      'feeAsset': 'USDB',
      'feeAssetDetails': {'chain': 'spark', 'asset': 'USDB', 'decimals': 6},
      'estimatedOut': '24750000',
      'destination': {'chain': 'spark', 'asset': 'USDB', 'decimals': 6},
    }, headers: {
      'x-kute-app-fee-bps': '$bps',
      'x-kute-referral-discount-bps': '0',
      'x-kute-estimate-includes-app-fee': 'false',
    });

Future<void> _openDetails(WidgetTester tester, String headline) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(headline));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Intl.defaultLocale = 'en_US');
  tearDown(() => Intl.defaultLocale = null);

  group('getEstimate', () {
    setUpAll(() {
      dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    });
    setUp(() => AffiliateService.debugSessionToken = 'test-session');
    tearDown(() => AffiliateService.debugSessionToken = null);

    Future<Map<String, String>> query({bool? onramp}) async {
      late Map<String, String> sent;
      await http.runWithClient(
        () => onramp == null
            ? OrchestraService.getEstimate(
                sourceChain: 'lightning',
                sourceAsset: 'BTC',
                destinationChain: 'hypercore',
                destinationAsset: 'USDC',
                amount: '25000')
            : OrchestraService.getEstimate(
                sourceChain: 'lightning',
                sourceAsset: 'BTC',
                destinationChain: 'hypercore',
                destinationAsset: 'USDC',
                amount: '25000',
                onramp: onramp),
        () => MockClient((request) async {
          sent = request.url.queryParameters;
          return http.Response(jsonEncode({'estimatedOut': '1'}), 200);
        }),
      );
      return sent;
    }

    test('asks for the onramp rule only when told to', () async {
      expect((await query(onramp: true))['onramp'], 'true');
      expect((await query(onramp: false)).containsKey('onramp'), isFalse);
      // Every existing caller: the request is exactly what it was.
      expect(await query(), {
        'sourceChain': 'lightning',
        'sourceAsset': 'BTC',
        'destinationChain': 'hypercore',
        'destinationAsset': 'USDC',
        'amount': '25000',
      });
    });

    test('the onramp fee estimate asks for the onramp rule', () async {
      Future<String?> flagFor(
          AutoDisposeFutureProviderFamily<OrchestraEstimate, FeeRoute>
              family) async {
        String? flag;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await http.runWithClient(
          () async {
            final sub = container.listen(family(_route), (_, __) {});
            await container.read(family(_route).future);
            sub.close();
          },
          () => MockClient((request) async {
            flag = request.url.queryParameters['onramp'];
            return http.Response(jsonEncode({'estimatedOut': '1'}), 200);
          }),
        );
        return flag;
      }

      expect(await flagFor(orchestraOnrampFeeEstimateProvider), 'true');
      expect(await flagFor(orchestraFeeEstimateProvider), isNull);
    });
  });

  testWidgets(
      'Cash App venue deposit shows the 1% fiat deposit fee it is charged',
      (tester) async {
    await tester.pumpWidget(_host(
        const OrchestraFeeSummary(
            route: _route, bitcoinFirst: false, onramp: true),
        [
          orchestraOnrampFeeEstimateProvider(_route)
              .overrideWith((_) async => _estimate(bps: 100)),
          orchestraFeeEstimateProvider(_route)
              .overrideWith((_) async => _estimate(bps: 50)),
        ]));
    // $25 in, 24.75 × 0.99 = $24.5025 arrives: $0.4975 in all.
    await _openDetails(tester, r'$0.50');
    expect(find.text('Kute fee (1.00%)'), findsOneWidget);
    // 1% of 24.75 USDC, the amount the order's 100 bps takes.
    expect(find.text(r'$0.25'), findsOneWidget);
    expect(find.text('Kute fee (0.50%)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a referred account sees the discounted onramp rate',
      (tester) async {
    await tester.pumpWidget(_host(
        const OrchestraFeeSummary(
            route: _route, bitcoinFirst: false, onramp: true),
        [
          orchestraOnrampFeeEstimateProvider(_route)
              .overrideWith((_) async => _estimate(bps: 80, discount: 20)),
        ]));
    // 24.75 × 0.992 = $24.552 arrives: $0.448 in all.
    await _openDetails(tester, r'$0.45');
    expect(find.text('Kute fee (0.80%)'), findsOneWidget);
    expect(find.text(r'$0.20'), findsOneWidget);
    // The Kute row opens on the discount it already holds.
    await tester.tap(find.text('Kute fee (0.80%)'));
    await tester.pumpAndSettle();
    expect(find.text('Includes your 20% friend discount.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('any other route keeps the quote estimate it showed before',
      (tester) async {
    await tester.pumpWidget(
        _host(const OrchestraFeeSummary(route: _route, bitcoinFirst: false), [
      orchestraOnrampFeeEstimateProvider(_route)
          .overrideWith((_) async => _estimate(bps: 100)),
      orchestraFeeEstimateProvider(_route)
          .overrideWith((_) async => _estimate(bps: 50)),
    ]));
    // 24.75 × 0.995 = $24.62625 arrives: $0.37375 in all.
    await _openDetails(tester, r'$0.37');
    expect(find.text('Kute fee (0.50%)'), findsOneWidget);
    expect(find.text(r'$0.12'), findsOneWidget);
    expect(find.text('Kute fee (1.00%)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Cash App dollars purchase shows the Kute fee and what arrives first',
      (tester) async {
    await tester.pumpWidget(_host(
        const OrchestraFeeSummary(
            route: _dollarsRoute,
            bitcoinFirst: false,
            onramp: true,
            showReceive: true),
        [
          orchestraOnrampFeeEstimateProvider(_dollarsRoute)
              .overrideWith((_) async => _dollarsEstimate(bps: 100)),
          orchestraFeeEstimateProvider(_dollarsRoute)
              .overrideWith((_) async => _dollarsEstimate(bps: 0)),
        ]));
    // $25 in, 24.75 × 0.99 = $24.5025 arrives: $0.4975 in all.
    await _openDetails(tester, r'$0.50');
    expect(find.text('Kute fee (1.00%)'), findsOneWidget);
    expect(find.text(r'$0.25'), findsOneWidget);
    expect(find.text('You receive'), findsOneWidget);
    expect(find.text(r'$24.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the dollars fee and what arrives match the order to one base unit', () {
    // The onramp order takes the fiat_deposit rate on what remains after
    // the provider's own fee: 1% of 24,750,000 USDB base units.
    const bps = 100;
    final quote = _dollarsEstimate(bps: bps);
    const out = 24750000;
    const charged = out * bps ~/ 10000;
    final kute = orchestraKuteFeeAmount(quote,
        destinationChain: 'spark', destinationAsset: 'USDB');
    final received = orchestraNetReceiveAmount(quote,
        destinationChain: 'spark', destinationAsset: 'USDB');
    expect(((kute.usd! * 1e6) - charged).abs(), lessThanOrEqualTo(1));
    expect(
        ((received.usd! * 1e6) - (out - charged)).abs(), lessThanOrEqualTo(1));
  });

  test(
      'the deposit sheet prices its Cash App dollar-landing block as an onramp',
      () {
    final source = stripComments(
        File('lib/screens/home/components/deposit_sheet.dart')
            .readAsStringSync());
    // Venues and the Dollars both land in dollars: one onramp block, with
    // the Kute fee and "You receive" in its breakdown.
    expect(
      RegExp(r'if \(_sourceCashApp &&\s*'
              r'_cashAppDestination\.deliversDollars\)\s*'
              r'OrchestraFeeSummary\(\s*bitcoinFirst: false,\s*onramp: true,'
              r'\s*showReceive: true,')
          .hasMatch(source),
      isTrue,
    );
    // Exactly one fee block is priced as an onramp: the Cash App one.
    expect(RegExp(r'onramp: true').allMatches(source).length, 1);
  });
}
