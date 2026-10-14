// Send dollars runs the bitcoin send's flow: a recipient field that
// decides the destination from what is pasted first, then the amount on
// the keypad, then Review. It opens as the send sheet: medium on the
// recipient, full from there on, and it cannot be swiped away once the
// send is past its first step or running. Nothing here reaches a money
// call: every case stops at a gate or on Review.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show UsdAccountActionBar;
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
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

/// The dollar balance the screen reads, settable mid-test.
final _balance = StateProvider<double>((_) => 100);

/// The puller the screen uses; null is one with no venue cash.
VenueCashPuller? _puller;

/// A venue whose cash the test sets, recording each pull. With [gate]
/// set, a pull waits on it, so a test can look at the send mid-pull.
class _Venue implements VenueCashSource {
  _Venue(this.venue, this.available);

  @override
  final OneBalanceVenue venue;
  double available;
  final pulls = <double>[];
  Completer<void>? gate;

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    await gate?.future;
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

/// [home] replaces the bare screen (a launcher, the dock); [router]
/// mounts the app under a GoRouter instead (the scanner route).
Future<void> _pump(WidgetTester tester,
    {bool arbitrumUsdc = true, Widget? home, GoRouter? router}) async {
  final theme = ThemeData(
      splashFactory: NoSplash.splashFactory,
      fontFamily: 'Inter',
      extensions: [AppColorsExtension.light()]);
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
      // The dock's square reads it; Sal off keeps the plain magnifier.
      aiEnabledProvider.overrideWith((_) async => false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => router != null
          ? MaterialApp.router(
              routerConfig: router,
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            )
          : MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home ?? const UsdSendScreen(),
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

Future<void> _paste(WidgetTester tester, String value) async {
  _clipboard = value;
  await tester.tap(find.byTooltip(_l10n.paste));
  await tester.pumpAndSettle();
}

/// Send to → Amount with [address] pasted.
Future<void> _toAmount(WidgetTester tester, {String address = _evm}) async {
  expect(find.text(_l10n.sendWhereShouldItLand), findsOneWidget);
  await _paste(tester, address);
  expect(_continueEnabled(tester), isTrue);
  await tester.tap(find.text(_l10n.continueLabel));
  await tester.pumpAndSettle();
  expect(find.text(_l10n.usdSendAmountSubtitle), findsOneWidget);
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
      'the recipient comes first; the amount follows, in dollars, with '
      'the percent chips', (tester) async {
    await withClipboard(tester);
    await _pump(tester);

    expect(find.text(_l10n.sendTo), findsOneWidget);
    expect(find.text(_l10n.usdSendAmountSubtitle), findsNothing);
    expect(_continueEnabled(tester), isFalse);

    await _toAmount(tester);
    expect(find.text(_l10n.amount), findsOneWidget);
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

  test('the shortfall is what the balance misses, up to the cent', () {
    BigInt u(String usd) => BigInt.from((double.parse(usd) * 1e6).round());
    expect(usdSendShortfallUsd(u('150'), u('100')), 50.0);
    expect(usdSendShortfallUsd(u('100.01'), u('100.004')), 0.01);
    expect(usdSendShortfallUsd(u('100'), u('100')), 0);
    expect(usdSendShortfallUsd(u('5'), u('100')), 0);
  });

  testWidgets(
      'over the balance, one button opens the Investments deposit with the '
      'shortfall; back with the dollars, the send carries on to Review '
      'with the amount kept', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final opened = <(MoveLockedSide, double?)>[];
    VoidCallback? completed;
    UsdSendScreen.debugDepositSheetOpener =
        (_, {required lockedSide, initialTargetUsd, onCompleted}) async {
      opened.add((lockedSide, initialTargetUsd));
      completed = onCompleted;
    };
    addTearDown(() => UsdSendScreen.debugDepositSheetOpener = null);
    // A phone-sized screen, so the hero has the room it has on a phone.
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await withClipboard(tester);
    await _pump(tester);
    await _toAmount(tester);

    final button = find.byKey(const ValueKey('usd-send-top-up'));
    expect(button, findsNothing);
    await _type(tester, '150');
    expect(find.text(_l10n.sendMoreThanAvailable), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);
    expect(button, findsOneWidget);
    expect(find.text(_l10n.slipAddToInvestments('\$50.00')), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(opened, [(MoveLockedSide.depositToUsd, 50.0)]);
    expect(events.where((e) => e.$1 == 'usd_send_top_up_opened').single.$2,
        {'shortfall_usd': 50.0});
    expect(TrackingService.takeEntrySource('move'), 'usd_send_shortfall');

    // The deposit went through but the dollars are not in yet: still on
    // Amount, the figure kept.
    completed!();
    await tester.pumpAndSettle();
    expect(find.text(_l10n.usdSendAmountSubtitle), findsOneWidget);
    expect(find.text('150'), findsOneWidget);

    // They land: on to Review, where the person still decides.
    ProviderScope.containerOf(tester.element(find.byType(UsdSendScreen)))
        .read(_balance.notifier)
        .state = 160;
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sendConfirmTheDetails), findsOneWidget);
    expect(find.text('\$150.00'), findsWidgets);
  });

  String label(String chain, String asset) {
    final d = usdSendDestinations(_catalog())
        .firstWhere((d) => d.chain == chain && d.assetCode == asset);
    return '${d.displaySymbol} · ${d.chainDisplayName}';
  }

  testWidgets(
      'Send to starts on USDC · Arbitrum; an EVM address from the '
      'clipboard goes there and, with an amount, reaches Review',
      (tester) async {
    await withClipboard(tester);
    _clipboard = 'ethereum:$_evm?value=0';
    await _pump(tester);

    // Preselected before any address.
    expect(find.text(label('arbitrum', 'USDC')), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    // The clipboard nudge, as on the bitcoin send, on opening.
    expect(find.text(_l10n.sendClipboardAddressFound), findsOneWidget);
    await tester.tap(find.text(_l10n.useIt));
    await tester.pumpAndSettle();

    expect(_field(tester), _evm);
    expect(find.text(label('arbitrum', 'USDC')), findsOneWidget);
    expect(find.text(_l10n.sendWhichNetworkIsThisAddressOn), findsNothing);
    expect(_continueEnabled(tester), isTrue);

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.usdSendAmountSubtitle), findsOneWidget);
    await _type(tester, '5');
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

    await _paste(tester, _evm);
    expect(_field(tester), _evm);
    expect(find.text(_l10n.sendWhichNetworkIsThisAddressOn), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets('Spark, Lightning and unknown chains keep Continue dead',
      (tester) async {
    await withClipboard(tester);
    await _pump(tester);

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
      'over Dollars but within venue cash: no "not enough", the available '
      'line is the Max the plan covers, and Continue goes on',
      (tester) async {
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
    expect(find.byKey(const ValueKey('usd-send-top-up')), findsNothing);
    expect(_continueEnabled(tester), isTrue);

    // Past the reach it is "more than available" again, with the top-up
    // for what the reach misses.
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text(_l10n.sendMoreThanAvailable), findsOneWidget);
    expect(find.text(_l10n.slipAddToInvestments('\$1321.60')), findsOneWidget);
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
    expect(find.text(_l10n.sendConfirmTheDetails), findsOneWidget);

    await tester.tap(find.text(_l10n.send));
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
      'the Investments dock\'s Send opens the sheet at medium height on '
      'Send to, and says so in usd_send_opened', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester,
        home: const Scaffold(
            body: SizedBox.expand(), bottomNavigationBar: UsdAccountActionBar()));

    await tester.tap(find.text(_l10n.send));
    await tester.pumpAndSettle();

    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(find.text(_l10n.sendWhereShouldItLand), findsOneWidget);
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));
    // The screen it came from stays behind the scrim.
    expect(find.byType(UsdAccountActionBar), findsOneWidget);
    expect(events.where((e) => e.$1 == 'usd_send_opened').single.$2,
        containsPair('presentation', 'sheet'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a recipient expands the sheet; past Send to neither a drag nor the '
      'scrim closes it, and system back steps back inside it',
      (tester) async {
    _phone(tester);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), moreOrLessEquals(_medium(tester)));

    await _paste(tester, _evm);
    expect(_sheetHeight(tester), moreOrLessEquals(_full(tester)));

    await tester.tap(find.text(_l10n.continueLabel));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.usdSendAmountSubtitle), findsOneWidget);

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
    expect(find.text(_l10n.sendWhereShouldItLand), findsOneWidget);
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
    await tester.tap(find.text(_l10n.send));
    await tester.pump();
    await tester.pump();
    expect(venue.pulls, isNotEmpty, reason: 'the pull is in flight');

    await _dragSheetDown(tester, 600, settle: false);
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(tester.getTopLeft(_sheet).dy, moreOrLessEquals(8));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(find.text(_l10n.sendConfirmTheDetails), findsOneWidget,
        reason: 'not even a step back while it runs');

    venue.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'the scanner opens full screen over the sheet and its result lands '
      'in the sheet', (tester) async {
    _phone(tester);
    await withClipboard(tester);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const _Launcher()),
      GoRoute(
        path: '/scan',
        name: 'smartScanner',
        builder: (context, state) {
          expect((state.extra as Map)['returnRaw'], isTrue);
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.pop('tron:$_tron'),
                child: const Text('Scanned'),
              ),
            ),
          );
        },
      ),
    ]);
    addTearDown(router.dispose);
    await _pump(tester, router: router);
    await tester.tap(find.text('Open send'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_l10n.scan));
    await tester.pumpAndSettle();
    expect(find.text('Scanned'), findsOneWidget);
    expect(find.byType(UsdSendScreen, skipOffstage: false), findsOneWidget,
        reason: 'the sheet waits under the scanner');

    await tester.tap(find.text('Scanned'));
    await tester.pumpAndSettle();
    expect(find.byType(UsdSendScreen), findsOneWidget);
    expect(_field(tester), _tron);
    expect(find.text(label('tron', 'USDT')), findsOneWidget);
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
    await tester.tap(find.text(_l10n.sendWhereShouldItLand));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()));
    expect(find.byType(UsdSendScreen), findsOneWidget);

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.usdSendAmountSubtitle), findsOneWidget);
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
    addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await withClipboard(tester);
    await _pump(tester, home: const _Launcher());
    await tester.tap(find.text('Open send'));
    await tester.pump();
    await tester.pump();
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
}
