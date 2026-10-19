// The receive of another coin: every way into the Dollars receive (the
// dock's Receive included) opens on the coin step, two labelled choices:
// "From your wallet" over the Bitcoin card (its Add button and the card
// itself open the Investments deposit from the spending bitcoin), then
// "From another wallet or exchange" over the coin grid. Into Bitcoin (the
// Bitcoin receive's "other coins") it is the grid alone. Nothing is
// picked for the person. Here the standing route serves no coin, so a
// coin they tap falls back to the one-time flow and asks its amount in
// the "Request amount" sheet (the reusable address is covered by
// usd_receive_standing_test.dart). Nothing here reaches a money call.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide;
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart'
    show AppButton, AppButtonVariant;
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showOtherCoinsReceiveSheet, showUsdReceiveSheet;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame;
import 'package:kute/screens/shared/stepper/stepper_widgets.dart'
    show StepperProgress;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListRow;
import 'package:kute/screens/usd/usd_receive_screen.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import 'package:money2/money2.dart';

import '../../helpers/runtime_policy_fixture.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog({bool stables = true}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          if (stables) ...[
            _row('arbitrum', 'USDC'),
            _row('base', 'USDC'),
            _row('polygon', 'USDC'),
            _row('solana', 'USDC'),
            _row('ethereum', 'USDT'),
          ],
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.now(),
    );

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

const _bitcoinRow = ValueKey('usd-receive-from-bitcoin');
const _bitcoinButton = ValueKey('usd-receive-from-bitcoin-button');

/// Opens the receive the way the dock does: a sheet over a screen, at a
/// 390pt-wide phone unless [size] says otherwise.
Future<void> _pump(WidgetTester tester,
    {bool stables = true,
    int? spendingSats,
    Size size = const Size(390, 844),
    double? textScale,
    bool bitcoin = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
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
      orchestraSupportedRoutesProvider
          .overrideWith((_) => _Routes(_catalog(stables: stables))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      // spark:USDB is not a standing destination here: every coin is
      // served by a one-time address (usd_receive_standing_test.dart has
      // the reusable address).
      standingDestinationsProvider.overrideWith((_) async => {'bitcoin:BTC'}),
      // No limits read answers: the $1.00 floor.
      receiveMinimumsProvider
          .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
      // Bitcoin at $60,000; the spending balance only when given.
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            if (spendingSats != null)
              'spending': WalletBalance(
                  onChainBtcBalance: 0, sparkBitcoinbalance: spendingSats),
          })),
      // The wallet never answers: no address is ever asked for.
      breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
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
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => bitcoin
                    ? showOtherCoinsReceiveSheet(context)
                    : showUsdReceiveSheet(context),
                child: const Text(_underneath),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text(_underneath));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const _underneath = 'open receive';

/// Unmounts the screen and lets its timers (the shimmer, the sheet) go.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Finder _tile(String symbol) => find.widgetWithText(CoinAssetTile, symbol).first;

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    UsdReceiveScreen.debugDepositSheetOpener = null;
  });

  Iterable<String> names() => events.map((e) => e.$1);

  testWidgets(
      'opens on the coin step: "From your wallet" over the Bitcoin card, '
      'then "From another wallet or exchange" over the coin grid, nothing '
      'picked and no sheet over it', (tester) async {
    await _pump(tester);
    final yours = find.text(_l10n.usdReceiveFromYourWallet);
    expect(yours, findsOneWidget);
    final row = find.byKey(_bitcoinRow);
    expect(row, findsOneWidget);
    final another = find.text(_l10n.usdReceiveFromAnotherWallet);
    expect(another, findsOneWidget);
    expect(find.text(_l10n.receiveAlsoAccepts), findsNothing);
    expect(find.byType(CoinAssetGrid), findsOneWidget);
    expect(_tile('USDC'), findsOneWidget);
    expect(_tile('USDT'), findsOneWidget);
    // Top to bottom: the first label, the Bitcoin card, the second
    // label, the grid. Both labels share one style.
    expect(tester.getTopLeft(yours).dy, lessThan(tester.getTopLeft(row).dy));
    expect(
        tester.getBottomLeft(row).dy, lessThan(tester.getTopLeft(another).dy));
    expect(tester.getTopLeft(another).dy,
        lessThan(tester.getTopLeft(find.byType(CoinAssetGrid)).dy));
    expect(tester.getTopLeft(yours).dx, tester.getTopLeft(another).dx);
    expect(
        tester.widget<Text>(yours).style, tester.widget<Text>(another).style);

    // No amount sheet, no auto pick, no network sheet.
    expect(find.byType(RequestAmountSheet), findsNothing);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    expect(names(), isNot(contains('usd_receive_coin_picker_opened')));
    expect(find.byType(CoinAssetPickerSheet), findsNothing);
    expect(names(), contains('usd_receive_opened'));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'the Bitcoin choice is one button under its label: "Bitcoin" over the '
      'spending balance and a filled Add button, no chevron', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, spendingSats: 100000);
    final row = tester.widget<SendToListRow>(find.byKey(_bitcoinRow));
    expect(row.title, _l10n.bitcoin);
    // The Bitcoin balance in dollars, alone: never "spending wallet".
    expect(row.subtitle, '\$60.00');
    expect(
        find.descendant(
            of: find.byKey(_bitcoinRow),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsNothing);
    final button = find.descendant(
        of: find.byKey(_bitcoinButton), matching: find.byType(AppButton));
    expect(button, findsOneWidget);
    final app = tester.widget<AppButton>(button);
    expect(app.text, _l10n.moveAdd);
    expect(app.variant, AppButtonVariant.primary);
    expect(app.compact, isTrue);
    // The button sits at the card's trailing edge, inside it.
    final card = tester.getRect(find.byKey(_bitcoinRow));
    final pill = tester.getRect(find.byKey(_bitcoinButton));
    expect(card.contains(pill.center), isTrue);
    expect(pill.right, greaterThan(card.center.dx));

    // One button for assistive tech, named by the card and its action.
    final node = tester.getSemantics(find.byKey(_bitcoinRow));
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    final label = node.getSemanticsData().label;
    expect(label, contains(_l10n.bitcoin));
    expect(label, isNot(contains('spending wallet')));
    expect(label, contains(_l10n.moveAdd));
    // The label above is plain text, not a button.
    expect(tester.getSemantics(find.text(_l10n.usdReceiveFromYourWallet)),
        isNot(isSemantics(isButton: true)));
    semantics.dispose();
    await _unmount(tester);
  });

  for (final target in ['card', 'button']) {
    testWidgets(
        'tapping the Bitcoin $target opens the Investments deposit from the '
        'spending bitcoin', (tester) async {
      final opened = <MoveLockedSide>[];
      UsdReceiveScreen.debugDepositSheetOpener =
          (_, {required lockedSide}) async => opened.add(lockedSide);
      await _pump(tester, spendingSats: 100000);
      await tester.tap(target == 'card'
          ? find.descendant(
              of: find.byKey(_bitcoinRow), matching: find.text(_l10n.bitcoin))
          : find.byKey(_bitcoinButton));
      await tester.pump();
      expect(opened, [MoveLockedSide.depositToUsd]);
      expect(
          TrackingService.takeEntrySource('move'), 'usd_receive_bitcoin_row');
      await _unmount(tester);
    });
  }

  testWidgets(
      'at 375pt and text x1.3 both choices fit inside the sheet without '
      'overflow', (tester) async {
    await _pump(tester,
        spendingSats: 123456789, size: const Size(375, 812), textScale: 1.3);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byKey(_bitcoinRow));
    final pill = tester.getRect(find.byKey(_bitcoinButton));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(375));
    expect(pill.right, lessThanOrEqualTo(card.right));
    expect(pill.height, lessThan(card.height));
    // The label is not clipped out of the button.
    final label = tester.getRect(find.descendant(
        of: find.byKey(_bitcoinButton), matching: find.text(_l10n.moveAdd)));
    expect(label.left, greaterThanOrEqualTo(pill.left));
    expect(label.right, lessThanOrEqualTo(pill.right));
    expect(find.text(_l10n.usdReceiveFromYourWallet), findsOneWidget);
    expect(find.text(_l10n.usdReceiveFromAnotherWallet), findsOneWidget);
    expect(find.byType(CoinAssetGrid), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'without a balance the row is just "Bitcoin", never the spending '
      'wallet', (tester) async {
    await _pump(tester);
    expect(
        tester.widget<SendToListRow>(find.byKey(_bitcoinRow)).subtitle, isNull);
    expect(find.textContaining('spending wallet'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'a coin on one network asks its amount in the "Request amount" sheet, '
      'in dollars; dismissing it leaves the coin step as '
      'it was', (tester) async {
    await _pump(tester);
    final sheet = ModalRoute.of(tester.element(find.byKey(_bitcoinRow)));
    expect(sheet, isA<ModalBottomSheetRoute<void>>());
    expect(find.byType(KuteCloseButton), findsOneWidget);
    // The close X on the left, as on the Bitcoin receive.
    expect(tester.getCenter(find.byType(KuteCloseButton)).dx,
        lessThan(tester.getCenter(find.byType(UsdReceiveScreen)).dx));
    await tester.tap(_tile('USDT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final amount =
        tester.widget<RequestAmountSheet>(find.byType(RequestAmountSheet));
    expect(amount.fixedCurrency, 'USD');
    // The limits read gave nothing: no minimum line (no app floor).
    expect(amount.limits!.value.minimumLabel, isNull);
    expect(
        find.descendant(
            of: find.byType(RequestAmountSheet),
            matching: find.text(_l10n.receiveRequestAmount)),
        findsOneWidget);
    // Dollars only: the unit chip names USD and has no picker.
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
    final selected =
        events.where((e) => e.$1 == 'usd_receive_coin_selected').single.$2;
    expect(selected, {
      'asset': 'USDT',
      'chain': 'ethereum',
      'address_kind': 'onetime',
      'fallback_reason': 'standing_unserved',
      'preselected': false,
      'preselect_reason': 'none',
    });

    // Its close X is on the left too; it dismisses the sheet: back on the
    // coin step, nothing created.
    final amountClose = find.descendant(
        of: find.byType(RequestAmountSheet),
        matching: find.byType(KuteCloseButton));
    expect(amountClose, findsOneWidget);
    expect(tester.getCenter(amountClose).dx,
        lessThan(tester.getCenter(find.byType(RequestAmountSheet)).dx));
    // Over the heading, in the receive sheets' header row.
    expect(
        tester.getCenter(amountClose).dy,
        lessThan(tester
            .getTopLeft(find.descendant(
                of: find.byType(RequestAmountSheet),
                matching: find.text(_l10n.receiveRequestAmount)))
            .dy));
    await tester.tap(amountClose);
    await tester.pumpAndSettle();
    expect(find.byType(RequestAmountSheet), findsNothing);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(names(), isNot(contains('receive_address_generated')));

    // On the coin step the header's close closes the sheet.
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the sheet opens with presentation: sheet and swipes away',
      (tester) async {
    await _pump(tester);
    final opened = events.where((e) => e.$1 == 'usd_receive_opened').single.$2!;
    expect(opened['presentation'], 'sheet');
    expect(opened['source'], 'usd');
    // Tall: about 90% of the screen.
    final frame = tester.getSize(find.byType(ReceiveSheetFrame));
    expect(frame.height, greaterThan(844 * 0.8));
    expect(frame.height, lessThanOrEqualTo(844 * 0.9 + 0.5));

    // The sheet's title names the balance the money lands in,
    // "Investments", never the spending wallet; no step bar.
    expect(find.text(_l10n.usdReceiveTitle), findsNothing);
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.text(_l10n.assetDollars)),
        findsOneWidget);
    expect(find.textContaining('spending wallet'), findsNothing);
    expect(find.byType(StepperProgress), findsNothing);

    await tester.fling(
        find.byType(KuteCloseButton), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
    expect(find.byType(UsdReceiveScreen), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    expect(names(), contains('usd_receive_abandoned'));
    await _unmount(tester);
  });

  testWidgets('a coin on several networks asks which one, then its amount',
      (tester) async {
    await _pump(tester);
    await tester.tap(_tile('USDC'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    // Its close X on the left, as on every receive sheet.
    final pickerClose = find.descendant(
        of: find.byType(CoinAssetPickerSheet),
        matching: find.byType(KuteCloseButton));
    expect(pickerClose, findsOneWidget);
    expect(tester.getCenter(pickerClose).dx,
        lessThan(tester.getCenter(find.byType(CoinAssetPickerSheet)).dx));
    expect(names(), contains('usd_receive_coin_picker_opened'));
    expect(names(), isNot(contains('usd_receive_coin_selected')));

    // Open on USDC's networks, not on the sheet's grid.
    final networks = find.byType(PickerRow);
    expect(networks, findsNWidgets(4));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is PickerRow && w.title.toLowerCase().contains('solana')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    final selected =
        events.where((e) => e.$1 == 'usd_receive_coin_selected').single.$2!;
    expect(selected['chain'], 'solana');
    expect(selected['preselected'], false);
    expect(selected['preselect_reason'], 'none');
    await _unmount(tester);
  });

  testWidgets('nothing offered: the Bitcoin row still leads, then the note',
      (tester) async {
    await _pump(tester, stables: false);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsOneWidget);
    expect(find.byType(CoinAssetGrid), findsNothing);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    await _unmount(tester);
  });

  testWidgets(
      'opened from the Bitcoin receive it delivers bitcoin: titled Bitcoin, '
      'no Bitcoin row, no Investments note, and a coin asks its amount in '
      'the receive unit', (tester) async {
    await _pump(tester, bitcoin: true);
    final screen =
        tester.widget<UsdReceiveScreen>(find.byType(UsdReceiveScreen));
    expect(screen.destinationAsset, 'BTC');
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.text(_l10n.bitcoin)),
        findsOneWidget);
    expect(find.text(_l10n.assetDollars), findsNothing);
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(find.text(_l10n.usdReceiveFromYourWallet), findsNothing);
    expect(find.text(_l10n.usdReceiveFromAnotherWallet), findsOneWidget);
    expect(names(), isNot(contains('usd_receive_opened')));

    await tester.tap(_tile('USDT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final amount =
        tester.widget<RequestAmountSheet>(find.byType(RequestAmountSheet));
    expect(amount.fixedCurrency, isNull);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    await _unmount(tester);
  });
}
