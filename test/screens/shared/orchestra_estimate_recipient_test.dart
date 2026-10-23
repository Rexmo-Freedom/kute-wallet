// Orchestra's estimate takes the recipient "for validation and network
// costs". Without it a HyperCore estimate assumes an account Hyperliquid
// has never seen and counts the one-time activation (about $1.22): a $5
// dollars deposit read $3.76 instead of $4.96 for an activated account.
// The fee block therefore asks with the address the move's quote names,
// the estimate is keyed by it, and it never reaches a log.

import 'dart:async';
import 'dart:convert';

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
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/screens/shared/orchestra_fee_summary.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_network.dart';

const _venue = '0x2222222222222222222222222222222222222222';
const _other = '0x3333333333333333333333333333333333333333';
const _sparkSelf = 'sprt1qselfaddress';

// The Investing deposit as the Move sheet prices it: $5 of dollars into
// HyperCore USDC.
const _route = (
  fromChain: 'spark',
  fromAsset: 'USDB',
  toChain: 'hypercore',
  toAsset: 'USDC',
  amount: '5000000'
);

class _CurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _CurrencyNotifier()
      : super(CurrencyState({
          'USD': Fixed.fromInt(100),
          'BTC': Fixed.parse('0.00001', decimalDigits: 8),
        }));
  @override
  Future<void> updateRates() async {}
}

/// Direct HyperCore funding is available; nothing else is asked of it.
class _DirectFunding extends SparkHypercoreFundingService {
  _DirectFunding(super.read);
  @override
  Future<bool> tryDirect({required bool deposit}) async => true;
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
          home: Scaffold(body: SafeArea(child: child)),
        ),
      ),
    );

/// The Investing account, the own Spark address and direct HyperCore
/// funding.
/// [account] stands in for an Investing account still being derived.
List<Override> _funding([Future<String?>? account]) => [
      hyperliquidAddressProvider
          .overrideWith((_) => account ?? Future.value(_venue)),
      sparkSelfAddressProvider.overrideWith((_) async => _sparkSelf),
      sparkHypercoreFundingServiceProvider
          .overrideWith((ref) => _DirectFunding(ref.read)),
    ];

http.Response _ok() => http.Response(jsonEncode({'estimatedOut': '1'}), 200);

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
  });
  setUp(() {
    Intl.defaultLocale = 'en_US';
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() {
    Intl.defaultLocale = null;
    AffiliateService.debugSessionToken = null;
    SharedHttpClient.debugOverride = null;
  });

  group('getEstimate', () {
    Future<Map<String, String>> query(String? recipient) async {
      late Map<String, String> sent;
      await withFakeNetwork(
        () => OrchestraService.getEstimate(
            sourceChain: 'spark',
            sourceAsset: 'USDB',
            destinationChain: 'hypercore',
            destinationAsset: 'USDC',
            amount: '5000000',
            recipientAddress: recipient),
        () => MockClient((request) async {
          sent = request.url.queryParameters;
          return _ok();
        }),
      );
      return sent;
    }

    test('sends the recipient when given', () async {
      expect((await query(_venue))['recipientAddress'], _venue);
      // Surrounding whitespace is not part of an address.
      expect((await query(' $_venue '))['recipientAddress'], _venue);
    });

    test('omits it when there is none to send', () async {
      expect((await query(null)).containsKey('recipientAddress'), isFalse);
      expect((await query('')).containsKey('recipientAddress'), isFalse);
      expect((await query('  ')).containsKey('recipientAddress'), isFalse);
    });

    test('a failure never carries the recipient', () async {
      final result = await withFakeNetwork(
        () => OrchestraService.getEstimate(
            sourceChain: 'spark',
            sourceAsset: 'USDB',
            destinationChain: 'hypercore',
            destinationAsset: 'USDC',
            amount: '5000000',
            recipientAddress: _venue),
        // A transport error quotes the request URL, query included.
        () => MockClient((request) async =>
            throw http.ClientException('connection reset', request.url)),
      );
      expect(result.data, isNull);
      expect(result.error, isNotNull);
      expect(result.error, isNot(contains(_venue)));
    });
  });

  group('fee estimate provider', () {
    test('asks with the recipient its key carries', () async {
      final asked = <String?>[];
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await withFakeNetwork(
        () async {
          for (final key in [
            feeEstimateKey(_route, recipient: _venue),
            feeEstimateKey(_route),
          ]) {
            final sub =
                container.listen(orchestraFeeEstimateProvider(key), (_, __) {});
            await container.read(orchestraFeeEstimateProvider(key).future);
            sub.close();
          }
        },
        () => MockClient((request) async {
          asked.add(request.url.queryParameters['recipientAddress']);
          return _ok();
        }),
      );
      expect(asked, [_venue, null]);
    });

    test('two recipients never share an estimate', () {
      expect(feeEstimateKey(_route, recipient: _venue),
          isNot(feeEstimateKey(_route, recipient: _other)));
      expect(feeEstimateKey(_route, recipient: _venue),
          isNot(feeEstimateKey(_route)));
      expect(
          orchestraFeeEstimateProvider(
              feeEstimateKey(_route, recipient: _venue)),
          isNot(orchestraFeeEstimateProvider(
              feeEstimateKey(_route, recipient: _other))));
      expect(
          orchestraOnrampFeeEstimateProvider(
              feeEstimateKey(_route, recipient: _venue)),
          isNot(orchestraOnrampFeeEstimateProvider(feeEstimateKey(_route))));
      // The same address, however it is written, is one estimate; a blank
      // one is the same as none.
      expect(feeEstimateKey(_route, recipient: ' $_venue'),
          feeEstimateKey(_route, recipient: _venue));
      expect(feeEstimateKey(_route, recipient: ''), feeEstimateKey(_route));
    });
  });

  group('fee block', () {
    Future<List<String?>> pumpAndCapture(
        WidgetTester tester, Widget child, List<Override> overrides) async {
      final asked = <String?>[];
      SharedHttpClient.debugOverride = MockClient((request) async {
        if (request.url.path.endsWith('/estimate')) {
          asked.add(request.url.queryParameters['recipientAddress']);
        }
        return _ok();
      });
      await tester.pumpWidget(_host(child, overrides));
      // The availability check and the addresses land.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // The estimate waits out its 350 ms debounce, then asks.
      await tester.pump(const Duration(milliseconds: 400));
      // The session and HTTP layers settle on real time.
      for (var i = 0; i < 20 && asked.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      return asked;
    }

    testWidgets('a HyperCore destination is asked with the venue recipient',
        (tester) async {
      final asked = await pumpAndCapture(
          tester,
          const OrchestraFeeSummary(
              route: _route, bitcoinFirst: false, recipient: _venue),
          const []);
      expect(asked, [_venue]);
    });

    testWidgets('an Investing deposit waits for the Investing account',
        (tester) async {
      final account = Completer<String?>();
      final asked = <String?>[];
      SharedHttpClient.debugOverride = MockClient((request) async {
        asked.add(request.url.queryParameters['recipientAddress']);
        return _ok();
      });
      await tester.pumpWidget(_host(
          const MoveHyperliquidFees(
              deposit: true,
              fromDollars: true,
              sats: 0,
              usd: 5,
              bitcoinFirst: false),
          _funding(account.future)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // No estimate priced as a brand new account in the meantime.
      expect(find.text('Calculating…'), findsOneWidget);
      expect(asked, isEmpty);
      account.complete(_venue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 20 && asked.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(asked, [_venue]);
    });

    testWidgets('an Investing deposit names the Investing account',
        (tester) async {
      final asked = await pumpAndCapture(
          tester,
          const MoveHyperliquidFees(
              deposit: true,
              fromDollars: true,
              sats: 0,
              usd: 5,
              bitcoinFirst: false),
          _funding());
      expect(asked, [_venue]);
    });

    testWidgets('an Investing withdrawal names the own Spark address',
        (tester) async {
      final asked = await pumpAndCapture(
          tester,
          const MoveHyperliquidFees(
              deposit: false,
              toDollars: true,
              sats: 0,
              usd: 5,
              bitcoinFirst: false),
          _funding());
      expect(asked, [_sparkSelf]);
    });
  });
}
