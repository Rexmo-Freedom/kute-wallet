// Send dollars runs the bitcoin send's flow: Amount first, then a
// recipient field that decides the destination from what is pasted, then
// Review. Nothing here reaches a money call: every case stops at a gate
// or on Review.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/runtime_policy_fixture.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _evm = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog({bool arbitrumUsdc = true}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          if (arbitrumUsdc) _row('arbitrum', 'USDC'),
          _row('arbitrum', 'USDT'),
          _row('base', 'USDC'),
          _row('ethereum', 'USDC'),
          _row('tron', 'USDT'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 9, 30),
    );

/// The live catalog, with no network behind it.
class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

final _l10n = AppLocalizationsEn();
String? _clipboard;

Future<void> _pump(WidgetTester tester, {bool arbitrumUsdc = true}) async {
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
      usdBalanceProvider.overrideWithValue(100),
      orchestraSupportedRoutesProvider
          .overrideWith((_) => _Routes(_catalog(arbitrumUsdc: arbitrumUsdc))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
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
        home: const UsdSendScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

AppButton _cta(WidgetTester tester, String label) => tester.widget<AppButton>(
    find.ancestor(of: find.text(label), matching: find.byType(AppButton)));

bool _continueEnabled(WidgetTester tester) =>
    _cta(tester, _l10n.continueLabel).onPressed != null;

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d).last);
    await tester.pump();
  }
}

Future<void> _toSendTo(WidgetTester tester, {String amount = '5'}) async {
  await _type(tester, amount);
  expect(_continueEnabled(tester), isTrue);
  await tester.tap(find.text(_l10n.continueLabel));
  await tester.pumpAndSettle();
  expect(find.text(_l10n.sendWhereShouldItLand), findsOneWidget);
}

Future<void> _paste(WidgetTester tester, String value) async {
  _clipboard = value;
  await tester.tap(find.byTooltip(_l10n.paste));
  await tester.pumpAndSettle();
}

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('usd_send_flow');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    _clipboard = null;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> withClipboard(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return _clipboard == null ? null : {'text': _clipboard};
        case 'Clipboard.hasStrings':
          return {'value': _clipboard != null};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  testWidgets('amount comes first, in dollars, with the percent chips',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester);

    expect(find.text(_l10n.amount), findsOneWidget);
    expect(find.text(_l10n.usdSendAmountSubtitle), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    // Below the minimum: said, and Continue stays dead.
    await _type(tester, '0.5');
    expect(find.text(_l10n.usdSendMinimum('\$1.00')), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    // 100% shows the balance to the cent.
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    expect(find.text('100.00'), findsOneWidget);
    expect(_continueEnabled(tester), isTrue);
  });

  String label(String chain, String asset) {
    final d = usdSendDestinations(_catalog())
        .firstWhere((d) => d.chain == chain && d.assetCode == asset);
    return '${d.displaySymbol} · ${d.chainDisplayName}';
  }

  testWidgets(
      'Send to starts on USDC · Arbitrum; an EVM address from the '
      'clipboard goes there and reaches Review', (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    _clipboard = 'ethereum:$_evm?value=0';
    await _toSendTo(tester);

    // Preselected before any address.
    expect(find.text(label('arbitrum', 'USDC')), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    // The clipboard nudge, as on the bitcoin send.
    expect(find.text(_l10n.sendClipboardAddressFound), findsOneWidget);
    await tester.tap(find.text(_l10n.useIt));
    await tester.pumpAndSettle();

    expect(_field(tester), _evm);
    expect(find.text(label('arbitrum', 'USDC')), findsOneWidget);
    expect(find.text(_l10n.sendWhichNetworkIsThisAddressOn), findsNothing);
    expect(_continueEnabled(tester), isTrue);

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sendConfirmTheDetails), findsOneWidget);
    expect(find.text('\$5.00'), findsWidgets);
    expect(find.text(_l10n.assetDollars), findsOneWidget);
    expect(find.text(label('arbitrum', 'USDC')), findsOneWidget);
  });

  testWidgets('a chain id picks its chain; Tron picks its route',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    await _toSendTo(tester);

    await _paste(tester, 'ethereum:$_evm@8453');
    expect(_field(tester), _evm);
    expect(find.text(label('base', 'USDC')), findsOneWidget);
    expect(find.text(_l10n.usdSendConvertedFromDollars), findsOneWidget);
    expect(_continueEnabled(tester), isTrue);

    await tester.tap(find.byTooltip(_l10n.close));
    await tester.pumpAndSettle();
    await _paste(tester, _tron);
    expect(find.text(label('tron', 'USDT')), findsOneWidget);
    expect(_continueEnabled(tester), isTrue);
  });

  testWidgets('without the Arbitrum USDC route an EVM address asks',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester, arbitrumUsdc: false);
    await _toSendTo(tester);

    await _paste(tester, _evm);
    expect(_field(tester), _evm);
    expect(find.text(_l10n.sendWhichNetworkIsThisAddressOn), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets('Spark, Lightning and unknown chains keep Continue dead',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    await _toSendTo(tester);

    await _paste(tester, 'spark:$_spark');
    expect(_field(tester), _spark);
    expect(find.text(_l10n.usdSendAddressUnsupported), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    await tester.tap(find.byTooltip(_l10n.close));
    await tester.pumpAndSettle();
    await _paste(tester, 'alice@getalby.com');
    expect(find.text(_l10n.sendAddressNotIdentified), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    await tester.tap(find.byTooltip(_l10n.close));
    await tester.pumpAndSettle();
    await _paste(tester, 'ethereum:$_evm@424242');
    expect(find.text(_l10n.usdSendAddressUnsupported), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);
  });
}
