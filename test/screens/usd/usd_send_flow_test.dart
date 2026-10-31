// Send dollars runs the bitcoin send's flow with the coin first: Send to
// opens on the coin grid and only a picked coin brings the recipient
// field (checked against that network alone), then the amount on the
// keypad, then Review, with the picked coin as a chip on every step. It
// opens as the send sheet: medium on Send to, full once a recipient is
// in, and it cannot be swiped away once the send is past its first step
// or running. The steps have no visible headings. Nothing here reaches a
// money call: every case stops at a gate or on Review.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/scanner/scanner_sheet.dart' show ScannerSheet;
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart'
    show CoinAssetPickerSheet;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendAmountUnitPill;
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show UsdAccountActionRow;
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/screens/usd/usd_withdraw_screen.dart'
    show UsdWithdrawScreen, kUsdWithdrawRouteName;
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteBareCloseButton;
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart'
    show RouteLimitsFetcher;
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/fake_scanner_camera.dart';
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

/// The dollar balance the screen reads, settable mid-test.
final _balance = StateProvider<double>((_) => 100);

/// The puller the screen uses; null is one with no venue cash.
VenueCashPuller? _puller;

/// What Review's estimate answers: $9.90 out by default.
Future<Result<OrchestraEstimate>> _priced({
  required String destinationChain,
  required String destinationAsset,
  required String amount,
  String? recipientAddress,
}) async =>
    Result(
        data: OrchestraEstimate(
            estimatedOut: '9900000',
            feeAmount: '0',
            feeBps: 0,
            route: const [],
            estimateIncludesAppFee: true));

/// A refused estimate, as the API reports one.
UsdSendEstimator _refused({String? code, int? status}) => ({
      required String destinationChain,
      required String destinationAsset,
      required String amount,
      String? recipientAddress,
    }) async =>
        Result(error: 'refused', statusCode: status, errorCode: code);

/// The Review estimate and the route limits the screen reads; set per
/// test.
UsdSendEstimator _estimator = _priced;
RouteLimitsFetcher _limits = (_) async => null;

/// Limits naming [cents] as the route's order minimum.
OrchestraRouteLimits _minimumOf(int cents) => OrchestraRouteLimits(
    orderMinUsdCents: cents);

/// A venue whose cash the test sets, recording each pull. With [gate]
/// set, a pull waits on it, so a test can look at the send mid-pull.
class _Venue implements VenueCashSource {
  _Venue(this.venue, this.available);

  @override
  final OneBalanceVenue venue;
  double available;
  final pulls = <double>[];
  Completer<void>? gate;

  /// Thrown by a pull (after [gate]): the leg did not go.
  Object? error;

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return VenueMoveResult(
        quoteId: 'q', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }
}

/// Opens the dollar send as the send sheet, the way the dock does.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showSendSheet<void>(context,
                builder: (_) => const UsdSendScreen()),
            child: const Text('Open send'),
          ),
        ),
      );
}

/// The scanner sheet's stand-in cameras for the current test.
FakeScannerCameras _cameras = FakeScannerCameras();

/// [home] replaces the bare screen (a launcher, the dock).
Future<void> _pump(WidgetTester tester,
    {bool arbitrumUsdc = true, Widget? home, String? initialRecipient}) async {
  final theme = ThemeData(
      splashFactory: NoSplash.splashFactory,
      fontFamily: 'Inter',
      extensions: [AppColorsExtension.light()]);
  _cameras = FakeScannerCameras();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      _cameras.override,
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
      usdBalanceProvider.overrideWith((ref) => ref.watch(_balance)),
      venueCashPullerProvider.overrideWith((ref) =>
          _puller ??
          VenueCashPuller(
              sources: const [],
              readDollars: () => ref.read(_balance),
              minimumUsd: (_) async => 1)),
      orchestraSupportedRoutesProvider
          .overrideWith((_) => _Routes(_catalog(arbitrumUsdc: arbitrumUsdc))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      usdSendEstimatorProvider.overrideWithValue(
          ({
            required String destinationChain,
            required String destinationAsset,
            required String amount,
            String? recipientAddress,
          }) =>
              _estimator(
                  destinationChain: destinationChain,
                  destinationAsset: destinationAsset,
                  amount: amount,
                  recipientAddress: recipientAddress)),
      usdSendRouteLimitsProvider.overrideWithValue((r) => _limits(r)),
      // The dock's square reads it; Sal off keeps the plain magnifier.
      aiEnabledProvider.overrideWith((_) async => false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home ?? UsdSendScreen(initialRecipient: initialRecipient),
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

/// The step on screen, by the header its page announces (the steps have
/// no visible heading).
Finder _step(String title) => find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.header == true &&
    w.properties.label == title);

Finder get _grid => find.byKey(const ValueKey('usd-send-coin-grid'));
Finder get _chip => find.byKey(const ValueKey('usd-send-coin-chip'));

String _chipLabel(WidgetTester tester) =>
    tester.widget<SendAmountUnitPill>(_chip).code;

UsdSendDestination _dest(String chain, String asset) =>
    usdSendDestinations(_catalog())
        .firstWhere((d) => d.chain == chain && d.assetCode == asset);

String label(String chain, String asset) {
  final d = _dest(chain, asset);
  return '${d.displaySymbol} · ${d.chainDisplayName}';
}

/// Taps [asset]'s tile in [within] and, for a coin on several networks,
/// [chain]'s row in the sheet that opens.
Future<void> _tapCoin(
    WidgetTester tester, Finder within, String chain, String asset) async {
  final d = _dest(chain, asset);
  await tester
      .tap(find.descendant(of: within, matching: find.text(d.displaySymbol)));
  await tester.pumpAndSettle();
  final sheet = find.byType(CoinAssetPickerSheet);
  if (sheet.evaluate().isEmpty) return;
  await tester
      .tap(find.descendant(of: sheet, matching: find.text(d.chainDisplayName)));
  await tester.pumpAndSettle();
}

/// Picks the coin on the Send to grid.
Future<void> _pickCoin(WidgetTester tester, String chain, String asset) =>
    _tapCoin(tester, _grid, chain, asset);

/// Changes the coin from its chip, on any step.
Future<void> _changeCoin(
    WidgetTester tester, String chain, String asset) async {
  await tester.tap(_chip);
  await tester.pumpAndSettle();
  await _tapCoin(tester, find.byType(CoinAssetPickerSheet), chain, asset);
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d).last);
    await tester.pump();
  }
}

Future<void> _paste(WidgetTester tester, String value) async {
  _clipboard = value;
  await tester.tap(find.byTooltip(_l10n.paste));
  await tester.pumpAndSettle();
}

/// Send to → Amount: USDC · Arbitrum picked and [address] pasted.
Future<void> _toAmount(WidgetTester tester, {String address = _evm}) async {
  expect(_step(_l10n.sendTo), findsOneWidget);
  await _pickCoin(tester, 'arbitrum', 'USDC');
  await _paste(tester, address);
  expect(_continueEnabled(tester), isTrue);
  await tester.tap(find.text(_l10n.continueLabel));
  await tester.pumpAndSettle();
  expect(_step(_l10n.amount), findsOneWidget);
}

/// A 375 x 812 phone (an iPhone mini / X class screen).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1125, 2436);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder get _sheet => find.byKey(const ValueKey('send-sheet'));

double _sheetHeight(WidgetTester tester) => tester.getSize(_sheet).height;

/// The sheet's full height on the test view: the screen less the 8 pt
/// gap under the status bar (no status bar inset in tests).
double _full(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio - 8;

double _medium(WidgetTester tester) =>
    tester.view.physicalSize.height /
    tester.view.devicePixelRatio *
    kSendSheetMediumFraction;

/// Drags the sheet down by [dy] from its handle.
/// Drags the sheet down by [dy] from its handle. [settle] false pumps a
/// fixed second instead (a spinner on screen never settles).
Future<void> _dragSheetDown(WidgetTester tester, double dy,
    {bool settle = true}) async {
  final top = tester.getTopLeft(_sheet) + const Offset(180, 8);
  await tester.dragFrom(top, Offset(0, dy));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }
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
    _puller = null;
    _estimator = _priced;
    _limits = (_) async => null;
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

  testWidgets(
      'Send to opens on the coin grid: no address field, Paste, Scan or '
      'Continue until a coin is picked', (tester) async {
    await withClipboard(tester);
    _clipboard = _evm;
    await _pump(tester);

    expect(_step(_l10n.sendTo), findsOneWidget);
    expect(_grid, findsOneWidget);
    expect(find.text(_l10n.usdFlowStepCoin), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip(_l10n.paste), findsNothing);
    expect(find.byTooltip(_l10n.scan), findsNothing);
    // Nothing is picked for the person, and the clipboard waits.
    expect(_chip, findsNothing);
    expect(find.text(_l10n.sendClipboardAddressFound), findsNothing);
    expect(_continueEnabled(tester), isFalse);
    // No visible step heading; the step is announced by name only.
    expect(find.text(_l10n.sendTo), findsNothing);
    expect(find.text(_l10n.sendWhereShouldItLand), findsNothing);
  });

  testWidgets(
      'picking a coin shows its chip over the field; the recipient, then '
      'the amount in dollars with the percent chips, and the chip stays on '
      'Amount and Review', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await withClipboard(tester);
    _clipboard = 'ethereum:$_evm?value=0';
    await _pump(tester);

    await _pickCoin(tester, 'arbitrum', 'USDC');
    expect(_grid, findsNothing);
    expect(_chipLabel(tester), label('arbitrum', 'USDC'));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip(_l10n.paste), findsOneWidget);
    expect(find.byTooltip(_l10n.scan), findsOneWidget);
    expect(events.where((e) => e.$1 == 'usd_send_coin_selected').single.$2,
        {'asset': 'USDC', 'network': 'arbitrum', 'preselected': false});
    expect(_continueEnabled(tester), isFalse);

    // The clipboard nudge, now that the network can take it.
    expect(find.text(_l10n.sendClipboardAddressFound), findsOneWidget);
    await tester.tap(find.text(_l10n.useIt));
    await tester.pumpAndSettle();
    expect(_field(tester), _evm);
    expect(_continueEnabled(tester), isTrue);

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(_step(_l10n.amount), findsOneWidget);
    expect(find.text(_l10n.amount), findsNothing);
    expect(_chipLabel(tester), label('arbitrum', 'USDC'));
    expect(
        tester
            .widgetList<SendAmountUnitPill>(find.byType(SendAmountUnitPill))
            .map((p) => p.code),
        contains('USD'));
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

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(_step(_l10n.sendReview), findsOneWidget);
    expect(find.text(_l10n.sendReview), findsNothing);
    // "Investments" twice: the sheet's title (the balance the dollars
    // leave from, never the spending wallet) and Review's From line.
    expect(find.text(_l10n.assetDollars), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.text(_l10n.assetDollars)),
        findsOneWidget);
    expect(_chipLabel(tester), label('arbitrum', 'USDC'));
    // Route params name the coin and its network; never the address.
    final step = events.lastWhere((e) => e.$1 == 'usd_send_step').$2!;
    expect(step, containsPair('to_asset', 'usdc'));
    expect(step, containsPair('to_network', 'arbitrum'));
    expect(events.expand<Object>((e) => e.$2?.values ?? const <Object>[]),
        isNot(contains(_evm)));
  });

  test('the shared helper: a payment request pins its own network only', () {
    final offered = usdSendDestinations(_catalog());
    expect(usdSendPaymentRequestDestination('ethereum:$_evm@8453', offered)?.id,
        'base:USDC');
    expect(usdSendPaymentRequestDestination('tron:$_tron', offered)?.id,
        'tron:USDT');
    // A bare address, or an EVM request with no chain, pins nothing.
    expect(usdSendPaymentRequestDestination(_evm, offered), isNull);
    expect(usdSendPaymentRequestDestination(_tron, offered), isNull);
    expect(usdSendPaymentRequestDestination('ethereum:$_evm', offered), isNull);
    expect(usdSendPaymentRequestDestination('ethereum:$_evm@424242', offered),
        isNull);
  });

  testWidgets(
      'a payment request handed over on open with its chain preselects that '
      'coin and fills the field', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await withClipboard(tester);
    await _pump(tester, initialRecipient: 'ethereum:$_evm@8453');

    expect(_grid, findsNothing);
    expect(_chipLabel(tester), label('base', 'USDC'));
    expect(_field(tester), _evm);
    expect(_continueEnabled(tester), isTrue);
    expect(events.where((e) => e.$1 == 'usd_send_coin_selected').single.$2,
        {'asset': 'USDC', 'network': 'base', 'preselected': true});
  });

  testWidgets(
      'a bare address handed over on open waits for the coin, then fills '
      'the field when that network takes it', (tester) async {
    await withClipboard(tester);
    await _pump(tester, initialRecipient: _evm);

    expect(_grid, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await _pickCoin(tester, 'arbitrum', 'USDT');
    expect(_field(tester), _evm);
    expect(_continueEnabled(tester), isTrue);
  });

  testWidgets(
      'the address is checked against the picked network only: another '
      'network\'s address is refused and the coin does not move',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    await _pickCoin(tester, 'arbitrum', 'USDC');

    await _paste(tester, 'ethereum:$_evm@8453');
    expect(_field(tester), _evm);
    expect(
        find.text(_l10n.usdSendAddressWrongNetwork(
            _dest('arbitrum', 'USDC').chainDisplayName)),
        findsOneWidget);
    expect(_chipLabel(tester), label('arbitrum', 'USDC'));
    expect(_continueEnabled(tester), isFalse);

    await tester.tap(find.byTooltip(_l10n.close));
    await tester.pumpAndSettle();
    await _paste(tester, _tron);
    expect(
        find.text(_l10n.usdSendAddressWrongNetwork(
            _dest('arbitrum', 'USDC').chainDisplayName)),
        findsOneWidget);
    expect(_chipLabel(tester), label('arbitrum', 'USDC'));
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets(
      'changing the coin keeps an address the new network takes and clears '
      'one it does not', (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    await _pickCoin(tester, 'arbitrum', 'USDC');
    await _paste(tester, _evm);

    // Same network family: the address stays.
    await _changeCoin(tester, 'arbitrum', 'USDT');
    expect(_chipLabel(tester), label('arbitrum', 'USDT'));
    expect(_field(tester), _evm);
    expect(_continueEnabled(tester), isTrue);

    // Tron cannot take an EVM address: cleared, Continue dead.
    await _changeCoin(tester, 'tron', 'USDT');
    expect(_chipLabel(tester), label('tron', 'USDT'));
    expect(_field(tester), isEmpty);
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets(
      'from Amount, a coin the address still fits stays on Amount; one it '
      'does not goes back to Send to with the field cleared', (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);

    await _changeCoin(tester, 'base', 'USDC');
    expect(_step(_l10n.amount), findsOneWidget);
    expect(_chipLabel(tester), label('base', 'USDC'));

    await _changeCoin(tester, 'tron', 'USDT');
    expect(_step(_l10n.sendTo), findsOneWidget);
    expect(_chipLabel(tester), label('tron', 'USDT'));
    expect(_field(tester), isEmpty);
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets('without the Arbitrum USDC route the sheet does not offer it',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester, arbitrumUsdc: false);

    await tester.tap(find.descendant(of: _grid, matching: find.text('USDC')));
    await tester.pumpAndSettle();
    final sheet = find.byType(CoinAssetPickerSheet);
    expect(sheet, findsOneWidget);
    expect(
        find.descendant(
            of: sheet,
            matching: find.text(_dest('base', 'USDC').chainDisplayName)),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet,
            matching: find.text(_dest('arbitrum', 'USDT').chainDisplayName)),
        findsNothing);
  });

  testWidgets('Spark, Lightning and unknown chains keep Continue dead',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester);
    await _pickCoin(tester, 'arbitrum', 'USDC');

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

  testWidgets(
      'over what can be sent: only "more than available", no top-up '
      'button, Continue dead', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);

    await _type(tester, '150');
    expect(find.text(_l10n.sendMoreThanAvailable), findsOneWidget);
    expect(find.text(_l10n.slipAddToInvestments('\$50.00')), findsNothing);
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets(
      'over Dollars but within venue cash: no "not enough", the available '
      'line is the Max the plan covers, and Continue goes on', (tester) async {
    // $100 of Dollars and $80 of Predictions cash: $178.40 can be sent
    // once the move's planned cost ($80 x 2%) is out, and that is shown.
    _puller = VenueCashPuller(
      sources: [_Venue(OneBalanceVenue.predictions, 80)],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
    );
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);

    expect(find.text(_l10n.hlYieldAvailableLine('\$178.40')), findsOneWidget);
    expect(find.text(_l10n.hlYieldAvailableLine('\$180.00')), findsNothing);
    await _type(tester, '150');
    expect(find.text(_l10n.sendMoreThanAvailable), findsNothing);
    expect(_continueEnabled(tester), isTrue);

    // Past the reach it is "more than available" again, and nothing else.
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text(_l10n.sendMoreThanAvailable), findsOneWidget);
    expect(find.text(_l10n.slipAddToInvestments('\$1321.60')), findsNothing);
    expect(_continueEnabled(tester), isFalse);

    // Max: the most the engine's plan covers.
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    expect(find.text('178.40'), findsOneWidget);
    expect(find.text(_l10n.sendMoreThanAvailable), findsNothing);
    expect(_continueEnabled(tester), isTrue);
    final plan = await _puller!.plan(neededUsd: 178.40);
    expect(plan.covers, isTrue);
  });

  testWidgets(
      'typing exactly the shown figure is fine; one cent above it is '
      '"more than available"', (tester) async {
    _puller = VenueCashPuller(
      sources: [_Venue(OneBalanceVenue.predictions, 80)],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
    );
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);
    expect(find.text(_l10n.hlYieldAvailableLine('\$178.40')), findsOneWidget);

    await _type(tester, '178.4');
    expect(find.text(_l10n.sendMoreThanAvailable), findsNothing);
    expect(_continueEnabled(tester), isTrue);
    expect((await _puller!.plan(neededUsd: 178.40)).covers, isTrue);

    await _type(tester, '1');
    expect(find.text(_l10n.sendMoreThanAvailable), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets(
      'the available line is instant: the last venue read shows as Amount '
      'opens, and a fresh read updates it in place', (tester) async {
    final venue = _Venue(OneBalanceVenue.predictions, 80);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
    );
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(UsdSendScreen)));
    expect(find.text(_l10n.hlYieldAvailableLine('\$178.40')), findsOneWidget);
    // The venue moves; the figure follows the next read, never blanking.
    venue.available = 50;
    container.invalidate(venueCashRefreshProvider);
    await tester.pump();
    expect(find.text(_l10n.hlYieldAvailableLine('\$178.40')), findsOneWidget,
        reason: 'the last read stays up while the venues are read again');
    await tester.pumpAndSettle();
    expect(find.text(_l10n.hlYieldAvailableLine('\$149.00')), findsOneWidget);
  });

  testWidgets(
      'Send past Dollars pulls the shortfall first; when it has not landed '
      'in time it stops and says so, and nothing is sent', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final venue = _Venue(OneBalanceVenue.predictions, 100);
    var now = DateTime(2026, 10, 13, 12);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);
    await _type(tester, '150');
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(_step(_l10n.sendReview), findsOneWidget);

    // Review's button says Withdraw: Investments never says Send.
    expect(find.text(_l10n.send), findsNothing);
    await tester.tap(find.text(_l10n.withdraw));
    await tester.pumpAndSettle();

    // 50 missing: 50 / 0.98 → $51.03 from Predictions, once.
    expect(venue.pulls, [51.03]);
    expect(
        find.text('${_l10n.oneBalanceComingBack('\$51.03', _l10n.predictions)}'
            '\n${_l10n.activityBitcoinAddedPending}'),
        findsOneWidget);
    expect(events.map((e) => e.$1), contains('predictions_cash_pulled'));
    // The send itself never started.
    expect(events.map((e) => e.$1), isNot(contains('usd_send_initiated')));
  });

  // ─── The send sheet ───────────────────────────────────────────────

  testWidgets(
      'the Investments row\'s Send opens the Add sheet turned '
      'around; a coin on it opens the send sheet at medium height on Send '
      'to, the coin picked, and closing it comes back', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester,
        home: const Scaffold(
            body: SizedBox.expand(),
            bottomNavigationBar: UsdAccountActionRow()));

    await tester.tap(find.text(_l10n.send));
    await tester.pumpAndSettle();

    // The Withdraw sheet: the Deposit's bottom sheet, "To your wallet"
    // over the Bitcoin card, then the coins. No send yet.
    final withdraw = find.byType(UsdWithdrawScreen);
    expect(withdraw, findsOneWidget);
    final route = ModalRoute.of(tester.element(withdraw));
    expect(route, isA<ModalBottomSheetRoute<void>>());
    expect(route!.settings.name, kUsdWithdrawRouteName);
    expect(find.text(_l10n.usdWithdrawToYourWallet), findsOneWidget);
    expect(
        find.byKey(const ValueKey('usd-withdraw-to-bitcoin')), findsOneWidget);
    expect(find.text(_l10n.usdWithdrawToAnotherWallet), findsOneWidget);
    expect(find.byType(UsdSendScreen), findsNothing);

    // USDC is on several networks: its networks, then the send.
    await _tapCoin(tester, find.byKey(const ValueKey('usd-withdraw-coin-grid')),
        'arbitrum', 'USDC');

    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(_step(_l10n.sendTo), findsOneWidget);
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));
    // The coin is picked: its chip over the field, no grid.
    expect(_chipLabel(tester), label('arbitrum', 'USDC'));
    expect(_grid, findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    // The screen it came from stays behind the scrim.
    expect(find.byType(UsdAccountActionRow), findsOneWidget);
    final opened = events.where((e) => e.$1 == 'usd_send_opened').single.$2;
    expect(opened, containsPair('presentation', 'sheet'));
    expect(events.where((e) => e.$1 == 'usd_send_coin_selected').single.$2,
        containsPair('preselected', true));

    // Closing the send comes back to the Withdraw sheet as it was.
    await tester.tap(find.byType(KuteBareCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(UsdSendScreen), findsNothing);
    expect(withdraw, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a recipient expands the sheet; past Send to neither a drag nor the '
      'scrim closes it, and system back steps back inside it', (tester) async {
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));

    // A coin alone keeps it medium; the recipient expands it.
    await _pickCoin(tester, 'arbitrum', 'USDC');
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));
    await _paste(tester, _evm);
    expect(_sheetHeight(tester), moreOrLessEquals(_full(tester)));

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(_step(_l10n.amount), findsOneWidget);

    // A long, fast drag down rubber-bands and comes back.
    await _dragSheetDown(tester, 600);
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(tester.getTopLeft(_sheet).dy, moreOrLessEquals(8));
    // A tap on the scrim strip above it does nothing either.
    await tester.tapAt(const Offset(4, 3));
    await tester.pumpAndSettle();
    expect(find.byType(UsdSendScreen), findsOneWidget);

    // System back is a step back, not a dismissal.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(_step(_l10n.sendTo), findsOneWidget);
    expect(_field(tester), _evm);
    // It stays full: the sheet never shrinks under the person.
    expect(_sheetHeight(tester), moreOrLessEquals(_full(tester)));

    // Back on the first step, a drag down closes it.
    await _dragSheetDown(tester, 600);
    expect(find.byType(UsdSendScreen), findsNothing);
  });

  testWidgets('on Send to, a drag down or a scrim tap closes the sheet',
      (tester) async {
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();

    // A short drag is not a dismissal.
    await _dragSheetDown(tester, 40);
    expect(find.byType(UsdSendScreen), findsOneWidget);

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.byType(UsdSendScreen), findsNothing);

    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    await _dragSheetDown(tester, 500);
    expect(find.byType(UsdSendScreen), findsNothing);
  });

  testWidgets(
      'while the send runs (venue cash coming home), nothing closes the '
      'sheet: not a drag, not system back', (tester) async {
    final venue = _Venue(OneBalanceVenue.predictions, 100)
      ..gate = Completer<void>();
    var now = DateTime(2026, 10, 13, 12);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    await _toAmount(tester);
    await _type(tester, '150');
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.withdraw));
    await tester.pump();
    await tester.pump();
    expect(venue.pulls, isNotEmpty, reason: 'the pull is in flight');

    await _dragSheetDown(tester, 600, settle: false);
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(tester.getTopLeft(_sheet).dy, moreOrLessEquals(8));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(_step(_l10n.sendReview), findsOneWidget,
        reason: 'not even a step back while it runs');

    venue.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'the scanner opens as a sheet over the send sheet and its result '
      'lands in the sheet', (tester) async {
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    await _pickCoin(tester, 'tron', 'USDT');

    await tester.tap(find.byTooltip(_l10n.scan));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(ScannerSheet))),
        isA<ModalBottomSheetRoute<dynamic>>());
    expect(find.byType(UsdSendScreen, skipOffstage: false), findsOneWidget,
        reason: 'the sheet waits under the scanner');

    _cameras.last.scan('tron:$_tron');
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(_cameras.last.disposed, isTrue);
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(_field(tester), _tron);
    expect(_chipLabel(tester), label('tron', 'USDT'));
    expect(_sheetHeight(tester), moreOrLessEquals(_full(tester)));
  });

  testWidgets(
      'the keyboard: the sheet grows, the field and Continue sit above it '
      'and Continue works; a tap outside the field puts the keyboard away '
      'and keeps the sheet; no overflow at 375 pt with text x1.3',
      (tester) async {
    _phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));
    await _pickCoin(tester, 'arbitrum', 'USDC');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), _evm);
    // A 336 pt keyboard.
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(_sheetHeight(tester), moreOrLessEquals(_full(tester)));
    const keyboardTop = 812 - keyboard;
    final field = tester.getRect(find.byType(TextField));
    expect(field.top, greaterThanOrEqualTo(tester.getTopLeft(_sheet).dy));
    expect(field.bottom, lessThanOrEqualTo(keyboardTop));
    final cta = find.ancestor(
        of: find.text(_l10n.continueLabel), matching: find.byType(AppButton));
    expect(tester.getRect(cta).bottom, lessThanOrEqualTo(keyboardTop));
    expect(_continueEnabled(tester), isTrue);

    // Outside the field: keyboard away, sheet kept.
    await tester.tap(find.text(_l10n.sendDetectedEthereumStyleAddress));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()));
    expect(find.byType(UsdSendScreen), findsOneWidget);

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(_step(_l10n.amount), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The keypad's 1 is on screen and tappable at this size.
    await _type(tester, '5');
    expect(_continueEnabled(tester), isTrue);
  });

  testWidgets('Reduce Motion: the sheet grows at once, with no animation',
      (tester) async {
    _phone(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pump();
    await tester.pump();
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));
    await _pickCoin(tester, 'arbitrum', 'USDC');
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));

    _clipboard = _evm;
    await tester.tap(find.byTooltip(_l10n.paste));
    // The paste lands, the flow reports after its frame, the sheet takes
    // the new height on the next: no animation frames in between.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(_sheetHeight(tester), moreOrLessEquals(_full(tester)));
  });

  /// Amount → Review with [digits] typed, USDC · Arbitrum to an address.
  Future<void> toReview(WidgetTester tester, String digits) async {
    await _toAmount(tester);
    await _type(tester, digits);
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(_step(_l10n.sendReview), findsOneWidget);
  }

  bool sendEnabled(WidgetTester tester) =>
      _cta(tester, _l10n.withdraw).onPressed != null;

  testWidgets(
      'Review: an amount under the route\'s minimum is said once under the '
      'card, never as the fee, and Send stays off', (tester) async {
    _estimator = _refused(code: 'amount_too_small', status: 400);
    await withClipboard(tester);
    await _pump(tester);
    await toReview(tester, '5');

    expect(find.text(_l10n.routeAmountTooSmallGeneric), findsOneWidget);
    expect(find.text(_l10n.swapRouteTemporarilyUnavailable), findsNothing);
    expect(find.text(_l10n.youReceive), findsNothing,
        reason: 'no fee line carries the refusal');
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets(
      'Review: with the route\'s minimum known, the refusal names it',
      (tester) async {
    _estimator = _refused(code: 'amount_too_small', status: 400);
    var reads = 0;
    // Unread when the coin is picked; read once the estimate refuses.
    _limits = (_) async {
      if (reads++ == 0) throw TimeoutException('limits');
      return _minimumOf(800);
    };
    await withClipboard(tester);
    await _pump(tester);
    await toReview(tester, '5');

    expect(find.text(_l10n.usdSendMinimum('\$8.00')), findsOneWidget);
    expect(find.text(_l10n.youReceive), findsNothing);
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets(
      'Review: a route refused for now is said once and keeps Send off',
      (tester) async {
    _estimator = _refused(code: 'route_unavailable', status: 400);
    await withClipboard(tester);
    await _pump(tester);
    await toReview(tester, '20');

    expect(find.text(_l10n.swapRouteTemporarilyUnavailable), findsOneWidget);
    expect(find.text(_l10n.youReceive), findsNothing);
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets(
      'Review: a passing failure is asked once more and the price lands; '
      'Send waits for it', (tester) async {
    var calls = 0;
    _estimator = ({
      required String destinationChain,
      required String destinationAsset,
      required String amount,
      String? recipientAddress,
    }) async {
      calls++;
      if (calls == 1) return Result(error: 'timeout');
      return _priced(
          destinationChain: destinationChain,
          destinationAsset: destinationAsset,
          amount: amount);
    };
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);
    await _type(tester, '20');
    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    expect(find.text(_l10n.receiveNetworkErrorTapToRetry), findsNothing,
        reason: 'not shown before the second ask');
    expect(sendEnabled(tester), isFalse, reason: 'the price is not in yet');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('≈ 9.90 USDC'), findsOneWidget);
    expect(sendEnabled(tester), isTrue);
  });

  testWidgets(
      'Amount: the picked coin\'s own minimum is the floor, said before '
      'Review', (tester) async {
    _limits = (_) async => _minimumOf(2500);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);

    await _type(tester, '10');
    expect(find.text(_l10n.usdSendMinimum('\$25.00')), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);
    await _type(tester, '0');
    expect(find.text(_l10n.usdSendMinimum('\$25.00')), findsNothing);
    expect(_continueEnabled(tester), isTrue);
  });

  testWidgets(
      'a send under its route\'s minimum never brings venue cash home for '
      'it: refused before any leg goes', (tester) async {
    var reads = 0;
    // Unread when the coin is picked; the send reads it again first.
    _limits = (_) async {
      if (reads++ == 0) throw TimeoutException('limits');
      return _minimumOf(20000);
    };
    final venue = _Venue(OneBalanceVenue.predictions, 100);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
    );
    await withClipboard(tester);
    await _pump(tester);
    await toReview(tester, '150');
    expect(sendEnabled(tester), isTrue);

    await tester.tap(find.text(_l10n.withdraw));
    await tester.pumpAndSettle();
    expect(venue.pulls, isEmpty, reason: 'no leg went');
    expect(find.text(_l10n.usdSendMinimum('\$200.00')), findsOneWidget);
    expect(reads, 2);
  });

  testWidgets(
      'a leg that does not go stops the send at once, while another leg '
      'is still on its way: the band lets go, its rumble stops, one '
      'failure tap, and the line says where the money is', (tester) async {
    ContinuousHaptics.debugReset();
    KuteHaptics.debugReset();
    ContinuousHaptics.debugLog = [];
    addTearDown(() {
      ContinuousHaptics.debugLog = null;
      KuteHaptics.debugReset();
    });
    final predictions = _Venue(OneBalanceVenue.predictions, 30)
      ..error = const RouteUnavailable('paused')
      ..gate = Completer<void>();
    final investing = _Venue(OneBalanceVenue.investing, 500)
      ..gate = Completer<void>();
    var now = DateTime(2026, 10, 23, 12);
    _puller = VenueCashPuller(
      sources: [predictions, investing],
      readDollars: () => 100,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    await withClipboard(tester);
    await _pump(tester);
    await toReview(tester, '150');

    await tester.tap(find.text(_l10n.withdraw));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(predictions.pulls, hasLength(1));
    expect(investing.pulls, hasLength(1));
    final log = ContinuousHaptics.debugLog!;
    expect(log.map((c) => c.method), contains('start'),
        reason: 'the band rumbles while the legs go');
    expect(ContinuousHaptics.isRunning(), isTrue);

    // The Predictions leg does not go; Investing is still on its way.
    predictions.gate!.complete();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(ContinuousHaptics.isRunning(), isFalse,
        reason: 'the rumble stops at once');

    // Stopped already: Retry, a line saying the Investing leg is coming
    // home, and the band at rest.
    final investingUsd = '\$${investing.pulls.single.toStringAsFixed(2)}';
    expect(
        find.text(
            '${_l10n.oneBalanceComingBack(investingUsd, _l10n.trading)}\n'
            '${_l10n.activityBitcoinAddedPending}'),
        findsOneWidget);
    expect(_cta(tester, _l10n.retry).onPressed, isNotNull,
        reason: 'Retry for the remainder, at once');

    // A while later, still waiting on the Investing leg: nothing rumbles,
    // ticks or beats after the release, and the failure tap played once.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final methods = log.map((c) => c.method).toList();
    final tap = methods.indexOf('softTap');
    expect(methods.where((m) => m == 'softTap'), hasLength(1));
    expect(methods.lastIndexOf('stop'), lessThan(tap),
        reason: 'the rumble stopped before the tap');
    expect(
        methods.sublist(tap).where(const {'start', 'update', 'tick', 'pulse'}
            .contains),
        isEmpty,
        reason: 'nothing keeps vibrating after the stop');

    // The Investing leg answers: no second tap, the line still says where
    // the money is.
    investing.gate!.complete();
    await tester.pumpAndSettle();
    expect(log.where((c) => c.method == 'softTap'), hasLength(1));
    expect(find.textContaining(_l10n.trading), findsWidgets);
    expect(find.text(_l10n.retry), findsOneWidget);
  });
}

