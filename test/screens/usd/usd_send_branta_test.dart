// The Dollars Send with a payee Branta verifies (services/branta; founder,
// 12 November 2026): a Branta `pol:` code for USDC on Polygon handed over
// (a scan or a paste) pins USDC on Polygon, the resolved row and the
// Review name the payee with its logo and "Verified by Branta", and
// analytics gets a yes/no only (`verified_payee`): never the address, the
// code's id or secret, nor the payee's name. Nothing here reaches a money
// call: the case stops on Review.

import 'dart:convert';
import 'dart:io';

import 'package:branta/branta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/handlers/response_handlers.dart' show Result;
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/send/send_branta_payee.dart';
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _evm = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';
const _brantaId = '8rnGGWZcg%2Fg3He1OK6yZ6OLOEyusldwIDaoPImRzWjoUGgu';
const _secret = '0515039f-2c31-4467-b62a-4e919079a44e';
const _code = 'pol:$_evm?value=50&user=send&currency=USD'
    '&branta_id=$_brantaId&branta_secret=$_secret';
const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';

final _l10n = AppLocalizationsEn();
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes() {
    state = OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          _row('arbitrum', 'USDC'),
          _row('polygon', 'USDC'),
          _row('polygon', 'USDT'),
          _row('base', 'USDC'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 11, 12),
    );
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

Future<void> _pump(WidgetTester tester, BrantaPayeeService branta,
    {String recipient = _code}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      usdBalanceProvider.overrideWith((_) => 100),
      venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          sources: const [], readDollars: () => 100, minimumUsd: (_) async => 1)),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes()),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      usdSendEstimatorProvider.overrideWithValue((
              {required String destinationChain,
              required String destinationAsset,
              required String amount,
              String? recipientAddress}) async =>
          Result(
              data: OrchestraEstimate(
                  estimatedOut: '4950000',
                  feeAmount: '0',
                  feeBps: 0,
                  route: const [],
                  estimateIncludesAppFee: true))),
      usdSendRouteLimitsProvider.overrideWithValue((_) async => null),
      aiEnabledProvider.overrideWith((_) async => false),
      brantaPayeeServiceProvider.overrideWithValue(branta),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        builder: withKuteShellBar,
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UsdSendScreen(initialRecipient: recipient),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d).last);
    await tester.pump();
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory hiveDir;
  late BrantaPayeeService savedShared;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('usd_send_branta');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SalSpriteCache.debugSetManifest(null);
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(_png);
    savedShared = BrantaPayeeService.shared;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    SalSpriteCache.debugReset();
    AffiliateService.debugSessionToken = null;
    BrantaPayeeLogo.debugImageProvider = null;
    BrantaPayeeService.shared = savedShared;
    TrackingService.debugTrackObserver = null;
  });

  testWidgets(
      'a Branta USDC code on Polygon: the payee on the row and on Review, '
      'analytics a yes/no only', (tester) async {
    final inputs = <String>[];
    // The screens note the code on the app's service and read the same.
    final branta = BrantaPayeeService(verifier: (input) async {
      inputs.add(input);
      return VerifyResult(
        status: VerifyStatus.match,
        payments: [
          Payment(
            destinations: [
              Destination(
                  value: _evm,
                  type: DestinationType.usdcPolygon,
                  isEncrypted: false)
            ],
            platform: 'Bitfinex',
            platformLogoUrl: 'https://guardrail.branta.pro/l.png',
          ),
        ],
        matchedDestinations: [
          Destination(
              value: _evm, type: DestinationType.usdcPolygon, isEncrypted: false)
        ],
        verifyUrl: '',
      );
    });
    BrantaPayeeService.shared = branta;
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));

    await _pump(tester, branta);

    // The code pins USDC on Polygon and fills the field with the address.
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, _evm);
    expect(find.text('Bitfinex'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-branta-logo')), findsOneWidget);
    // Looked up by the code as handed over, its Branta params intact.
    expect(inputs.toSet(), {_code});

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    await _type(tester, '5');
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();

    // Review: the To square names the payee over the line and the address.
    final to = find.byKey(const ValueKey('send-review-to'));
    expect(to, findsOneWidget);
    expect(find.descendant(of: to, matching: find.text('Bitfinex')),
        findsOneWidget);
    expect(
        find.descendant(
            of: to,
            matching: find.textContaining(_l10n.sendVerifiedByBranta)),
        findsOneWidget);
    expect(find.descendant(
            of: to, matching: find.byKey(const ValueKey('send-branta-logo'))),
        findsOneWidget);

    // Analytics: the yes/no on the send's own steps ...
    final steps = events
        .where((e) => e.$2?.containsKey('verified_payee') ?? false)
        .toList();
    expect(steps, isNotEmpty);
    expect(steps.last.$2!['verified_payee'], isTrue);
    expect(steps.last.$2!['to_network'], 'polygon');
    // ... and nothing that names the address, the code or the payee, in
    // any event at all.
    final forbidden = [
      _evm.toLowerCase(),
      _evm.substring(2, 12).toLowerCase(),
      _secret,
      Uri.decodeComponent(_brantaId).toLowerCase(),
      'bitfinex',
      'branta',
      'pol:',
    ];
    for (final (name, params) in events) {
      final text = '$name ${jsonEncode(params?.map((k, v) => MapEntry(k, '$v')))}'
          .toLowerCase();
      for (final f in forbidden) {
        expect(text.contains(f), isFalse,
            reason: 'event "$name" carried "$f": $text');
      }
    }
  });

  testWidgets('a bare address: no lookup, verified_payee false',
      (tester) async {
    var calls = 0;
    final branta = BrantaPayeeService(verifier: (_) async {
      calls++;
      return const VerifyResult(status: VerifyStatus.unknown, verifyUrl: '');
    });
    BrantaPayeeService.shared = branta;
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    // The same address and network, as a plain request: no Branta params.
    await _pump(tester, branta, recipient: 'ethereum:$_evm@137');
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, _evm);
    expect(find.byKey(const ValueKey('send-resolved-row')), findsOneWidget);
    expect(find.text(_l10n.sendVerifiedByBranta), findsNothing);
    expect(find.byKey(const ValueKey('send-branta-logo')), findsNothing);
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    await _type(tester, '5');
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-review-to-address')),
        findsOneWidget);
    expect(calls, 0);
    final flagged = events
        .where((e) => e.$2?.containsKey('verified_payee') ?? false)
        .map((e) => e.$2!['verified_payee'])
        .toSet();
    expect(flagged, isNot(contains(true)));
  });
}
