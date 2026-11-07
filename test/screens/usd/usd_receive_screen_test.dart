// The receive of another coin: every way into the Dollars receive (the
// dock's Receive included) opens on two big square cards side by side
// (founder, 5 November 2026: "Here should be big cards, square"), in a
// sheet as tall as they are, the floating bar away: "From your Bitcoin"
// (the Bitcoin mark and its balance, opening the Investments deposit from
// the spending bitcoin) and "From another wallet or exchange" (the coins
// stacked) opening the coin sheet. No inline grid. Into Bitcoin (the Bitcoin
// receive's "other coins") it is the grid alone. Nothing is
// picked for the person. Here the standing route serves no coin, so a
// coin they tap falls back to the one-time flow and asks its amount in
// the "Request amount" sheet (the reusable address is covered by
// usd_receive_standing_test.dart). Nothing here reaches a money call.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show BigAmountDisplay;
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
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart'
    show AppButton;
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showOtherCoinsReceiveSheet, showUsdReceiveSheet;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame;
import 'package:kute/screens/shared/stepper/stepper_widgets.dart'
    show StepperProgress;
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show kuteBarShortSheetFraction;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarContextProvider, kuteBarTop;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendCoinStack;
import 'package:kute/screens/usd/usd_receive_screen.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import 'package:money2/money2.dart';

import '../../helpers/receive_coin_tap.dart';
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

/// Opens the receive the way the dock does: a sheet over a screen, at a
/// 390pt-wide phone unless [size] says otherwise.
Future<void> _pump(WidgetTester tester,
    {bool stables = true,
    int? spendingSats,
    Size size = const Size(390, 844),
    double? textScale,
    Locale? locale,
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
        locale: locale,
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

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

/// How many lines [title] takes inside [card].
int _lines(WidgetTester tester, Finder card, String title) {
  final p = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.descendant(of: card, matching: find.text(title)),
      matching: find.byType(RichText)));
  final painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
  )..layout(maxWidth: p.constraints.maxWidth);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// Every coin of the stack under [card] lies whole inside the stack's box
/// and the card: nothing clipped.
void _expectCoinsWhole(WidgetTester tester, Finder card) {
  final stack = find.descendant(of: card, matching: find.byType(SendCoinStack));
  final box = tester.getRect(stack);
  final coins = find.descendant(
      of: stack,
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle));
  expect(coins, findsWidgets);
  for (final coin in coins.evaluate()) {
    final r = tester.getRect(find.byWidget(coin.widget));
    expect(r.left, greaterThanOrEqualTo(box.left - 0.01));
    expect(r.top, greaterThanOrEqualTo(box.top - 0.01));
    expect(r.right, lessThanOrEqualTo(box.right + 0.01),
        reason: 'a coin is cut at the right');
    expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.01));
    expect(r.right, lessThanOrEqualTo(tester.getRect(card).right));
  }
}

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
    debugMoneyMovementSheetOpener = null;
  });

  Iterable<String> names() => events.map((e) => e.$1);

  testWidgets(
      'opens on two big square cards side by side: "From your Bitcoin" and '
      '"Another wallet" ("Or an exchange", the coins stacked, none cut), '
      'both titles on one line; no list rows, no inline grid, nothing '
      'picked', (tester) async {
    // The app's own font: the one-line rule measures real glyphs.
    await tester.runAsync(_loadInter);
    await _pump(tester);
    final row = find.byKey(_bitcoinRow);
    expect(row, findsOneWidget);
    final grid = find.byKey(const ValueKey('usd-receive-card'));
    expect(tester.widget<KuteActionCardGrid>(grid).cards.map((c) => c.key),
        [_bitcoinRow, const ValueKey('usd-receive-from-another')]);
    final bitcoin = tester.widget<KuteActionCard>(row);
    expect(bitcoin.title, _l10n.usdReceiveFromYourBitcoin);
    expect(bitcoin.compact, isFalse);
    expect(receiveFromAnotherRow, findsOneWidget);
    final another = tester.widget<KuteActionCard>(receiveFromAnotherRow);
    expect(another.title, _l10n.receiveAnotherWallet);
    expect(another.title, 'Another wallet');
    expect(another.subtitle, _l10n.receiveOrAnExchangeLine('USDC, USDT'));
    expect(another.subtitle, 'Or an exchange · USDC, USDT');
    expect(another.visual, isA<SendCoinStack>());
    expect(tester.widget<KuteActionCardGrid>(grid).oneLineTitles, isTrue);
    _expectCoinsWhole(tester, receiveFromAnotherRow);
    for (final (card, title) in [
      (row, bitcoin.title),
      (receiveFromAnotherRow, another.title),
    ]) {
      expect(_lines(tester, card, title), 1, reason: title);
    }
    // Side by side, equally wide and tall, 12 apart; squares, no chevron.
    final a = tester.getRect(row);
    final b = tester.getRect(receiveFromAnotherRow);
    expect(a.top, moreOrLessEquals(b.top));
    expect(a.height, moreOrLessEquals(b.height));
    expect(a.width, moreOrLessEquals(b.width));
    expect(a.right, lessThan(b.left));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    // The old labels and the inline grid are gone.
    expect(find.text(_l10n.usdReceiveFromYourWallet), findsNothing);
    expect(find.byType(CoinAssetGrid), findsNothing);
    expect(find.byType(CoinAssetTile), findsNothing);
    expect(find.byType(AppButton), findsNothing);

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
      '"From your Bitcoin" says the Bitcoin balance in dollars, never the '
      'spending wallet', (tester) async {
    await _pump(tester, spendingSats: 100000);
    final row = tester.widget<KuteActionCard>(find.byKey(_bitcoinRow));
    expect(row.subtitle, _l10n.usdBitcoinBalanceLine('\$60.00'));
    expect(find.textContaining('spending wallet'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'tapping "From your Bitcoin" opens Move money straight on the amount, '
      'Bitcoin to Dollars, pinned: no source picker in between',
      (tester) async {
    final opened = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => opened.add(request);
    await _pump(tester, spendingSats: 100000);
    await tester.tap(find.byKey(_bitcoinRow));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(opened.single.route,
        const MoneyMovementRoute(MoneyMovementAccount.bitcoin,
            MoneyMovementAccount.dollars));
    expect(opened.single.pinned, isTrue);
    expect(opened.single.entrySource, kUsdReceiveBitcoinRowSource);
    expect(TrackingService.takeEntrySource('move'), 'usd_receive_bitcoin_row');
    await _unmount(tester);
  });

  testWidgets(
      '"From another wallet or exchange" opens the coin sheet, as the '
      'Bitcoin receive\'s "Also accepts" does', (tester) async {
    await _pump(tester);
    await openReceiveCoins(tester);
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(names(), contains('usd_receive_coin_picker_opened'));
    expect(_tile('USDC'), findsOneWidget);
    expect(_tile('USDT'), findsOneWidget);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    await _unmount(tester);
  });

  testWidgets(
      'at 375pt and text x1.3 the cards fit inside the sheet without '
      'overflow', (tester) async {
    await _pump(tester,
        spendingSats: 123456789, size: const Size(375, 812), textScale: 1.3);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byKey(const ValueKey('usd-receive-card')));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(375));
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(receiveFromAnotherRow, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'without a balance the row is just "From your Bitcoin", never the '
      'spending wallet', (tester) async {
    await _pump(tester);
    expect(
        tester.widget<KuteActionCard>(find.byKey(_bitcoinRow)).subtitle,
        isNull);
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
    await tapReceiveCoin(tester, 'USDT');
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
        findsNothing,
        reason: 'no title on the Request amount sheet');
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
    // Over the amount, in the receive sheets' header row.
    expect(
        tester.getCenter(amountClose).dy,
        lessThan(tester
            .getTopLeft(find.descendant(
                of: find.byType(RequestAmountSheet),
                matching: find.byType(BigAmountDisplay)))
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
    // As tall as the two cards (founder, 5 November 2026: no "big empty
    // area"): short, so the floating bar goes while it is up.
    final frame = tester.getRect(find.byType(ReceiveSheetFrame));
    expect(frame.height, lessThan(844 * kuteBarShortSheetFraction));
    expect(frame.bottom - tester.getRect(receiveFromAnotherRow).bottom,
        lessThan(80));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(UsdReceiveScreen)));
    expect(kuteBarTop(container.read(kuteBarContextProvider))?.hidden, isTrue);

    // The sheet's title is "Receive" (founder, 7 November 2026: the word
    // swap appears nowhere), as on the Bitcoin receive's first sheet: no
    // balance pill, never the spending wallet; no step bar.
    expect(find.text(_l10n.usdReceiveTitle), findsNothing);
    expect(find.text(_l10n.receive), findsOneWidget);
    expect(find.textContaining('swap'), findsNothing);
    expect(find.byType(AccountSwitcherPill), findsNothing);
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
    await tapReceiveCoin(tester, 'USDC');
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

  testWidgets(
      'nothing offered: the Bitcoin card alone, full width and compact (a '
      'chevron at its right), then the note', (tester) async {
    await _pump(tester, stables: false);
    expect(find.byKey(_bitcoinRow), findsOneWidget);
    expect(receiveFromAnotherRow, findsNothing);
    final lone = tester.getRect(find.byKey(_bitcoinRow));
    expect(lone.width, moreOrLessEquals(390 - 2 * 20 * 390 / 430, epsilon: 1));
    expect(lone.height, lessThan(110));
    expect(
        find.descendant(
            of: find.byKey(_bitcoinRow),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);
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

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: the two cards side '
      'by side, equally tall, every word whole inside its card, nothing '
      'overflowing; the sheet short and the bar away', (tester) async {
    await tester.runAsync(_loadInter);
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester,
          spendingSats: 123456789,
          size: const Size(375, 812),
          locale: locale);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: why);
      final bitcoin = find.byKey(_bitcoinRow);
      final a = tester.getRect(bitcoin);
      final b = tester.getRect(receiveFromAnotherRow);
      expect(a.top, moreOrLessEquals(b.top), reason: why);
      expect(a.height, moreOrLessEquals(b.height), reason: why);
      expect(a.right, lessThan(b.left), reason: why);
      expect(a.left, greaterThanOrEqualTo(0), reason: why);
      expect(b.right, lessThanOrEqualTo(375), reason: why);
      expect(
          find.descendant(
              of: receiveFromAnotherRow,
              matching: find.text(l10n.receiveAnotherWallet)),
          findsOneWidget,
          reason: why);
      // Both titles on one line (founder, 7 November 2026: "sizes are
      // strange here"), the coins whole in their box.
      expect(_lines(tester, bitcoin, l10n.usdReceiveFromYourBitcoin), 1,
          reason: why);
      expect(
          _lines(tester, receiveFromAnotherRow, l10n.receiveAnotherWallet), 1,
          reason: why);
      _expectCoinsWhole(tester, receiveFromAnotherRow);
      for (final (card, box) in [(bitcoin, a), (receiveFromAnotherRow, b)]) {
        final texts =
            find.descendant(of: card, matching: find.byType(RichText));
        expect(texts, findsWidgets, reason: why);
        for (var i = 0; i < texts.evaluate().length; i++) {
          final p = tester.renderObject<RenderParagraph>(texts.at(i));
          expect(p.didExceedMaxLines, isFalse, reason: '$why: a line is cut');
          final shown = tester.getRect(texts.at(i));
          expect(shown.right, lessThanOrEqualTo(box.right + 0.5),
              reason: why);
          expect(shown.bottom, lessThanOrEqualTo(box.bottom + 0.5),
              reason: '$why: a line runs past its card');
        }
      }
      final frame = tester.getRect(find.byType(ReceiveSheetFrame));
      expect(frame.height, lessThan(812 * kuteBarShortSheetFraction),
          reason: why);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(UsdReceiveScreen)));
      expect(kuteBarTop(container.read(kuteBarContextProvider))?.hidden,
          isTrue,
          reason: why);
      await _unmount(tester);
    }
  });
}
