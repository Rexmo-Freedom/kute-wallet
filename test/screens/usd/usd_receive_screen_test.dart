// The receive of another coin: every way into the Dollars receive (the
// dock's Receive included) opens on the Bitcoin Receive's structure
// (founder, 7 November 2026: "these receive and send from dollars seem
// too small and strange"), in a sheet as tall as its cards, the floating
// bar away, under the first steps' header ("Receive" big on the left, the
// compact X at the top right): "Dollars" on top, the lead card (the
// Dollars mark, the dollar coins it takes: here "USDC and USDT", opening
// the coin sheet with those alone), then "Another crypto" under it, the
// grid's lone card, compact and full width (the other coins it names side
// by side, whole, over one short line: here "ETH and SOL") opening the
// coin sheet with those. No "From your Bitcoin" (founder, 7 November 2026:
// "On dollars receive we get rid of from your bitcoin"). No inline grid. Into Bitcoin (the Bitcoin
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
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
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
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/asset_network_picker.dart' show PickerRow;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart'
    show AppButton;
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showOtherCoinsReceiveSheet, showUsdReceiveSheet;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame, SheetTitleHeader;
import 'package:kute/screens/shared/stepper/stepper_widgets.dart'
    show StepperProgress;
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show kuteBarShortSheetFraction;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarContextProvider, kuteBarTop;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show AnotherCryptoMarks;
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

OrchestraRoutesCatalog _catalog(
        {bool stables = true, bool usdt = true, bool others = true}) =>
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
            if (usdt) _row('ethereum', 'USDT'),
          ],
          if (others) ...[
            _row('ethereum', 'ETH', decimals: 18),
            _row('solana', 'SOL', decimals: 9),
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

/// The door the founder took away (7 November 2026), to say it is gone.
const _bitcoinRow = ValueKey('usd-receive-from-bitcoin');

/// Opens the receive the way the dock does: a sheet over a screen, at a
/// 390pt-wide phone unless [size] says otherwise.
Future<void> _pump(WidgetTester tester,
    {bool stables = true,
    bool usdt = true,
    bool others = true,
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
          .overrideWith(
              (_) => _Routes(
                  _catalog(stables: stables, usdt: usdt, others: others))),
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

/// The coins of the "Another crypto" [card] lie whole, side by side and
/// inside the card, none over another, each a circle at the grid's visual
/// size (the Dollars lead's mark is the lead's larger one: 40 to its 48).
void _expectCoinsWhole(WidgetTester tester, Finder card) {
  final marks =
      find.descendant(of: card, matching: find.byType(AnotherCryptoMarks));
  expect(marks, findsOneWidget);
  final coins = find.descendant(of: marks, matching: find.byType(AssetIcon));
  expect(coins, findsNWidgets(2));
  final box = tester.getRect(card);
  final lead = tester.getSize(find
      .descendant(
          of: receiveDollarsLead,
          matching: find.byWidgetPredicate((w) => w is SvgPicture))
      .first);
  final rects = [for (var i = 0; i < 2; i++) tester.getRect(coins.at(i))];
  for (final r in rects) {
    expect(r.left, greaterThanOrEqualTo(box.left));
    expect(r.top, greaterThanOrEqualTo(box.top));
    expect(r.right, lessThanOrEqualTo(box.right), reason: 'a coin is cut');
    expect(r.bottom, lessThanOrEqualTo(box.bottom));
    expect(r.width, moreOrLessEquals(r.height));
    expect(r.height, moreOrLessEquals(lead.height * 40 / 48),
        reason: 'the grid\'s visual size');
  }
  expect(rects[0].right, lessThanOrEqualTo(rects[1].left),
      reason: 'one coin over another');
  expect(rects[0].top, moreOrLessEquals(rects[1].top));
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
  });

  Iterable<String> names() => events.map((e) => e.$1);

  testWidgets(
      'opens as the Bitcoin Receive does: "Receive" big on the left with the '
      'compact X at the top right, "Dollars" on top, full width and larger '
      '(the Dollars mark, the dollar coins it takes), then "Another crypto" '
      'under it, the lone card, compact and full width (the other coins, '
      'side by side, none cut); no From your Bitcoin, no list rows, no '
      'inline grid, nothing picked', (tester) async {
    // The app's own font: the one-line rule measures real glyphs.
    await tester.runAsync(_loadInter);
    await _pump(tester);
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(find.text(_l10n.usdReceiveFromYourBitcoin), findsNothing);
    expect(find.byType(SheetTitleHeader), findsOneWidget);
    expect(find.text(_l10n.receive), findsOneWidget);
    final title = tester.getRect(find.text(_l10n.receive));
    final close = tester.getRect(find.byKey(SheetTitleHeader.closeKey));
    expect(title.left,
        moreOrLessEquals(tester.getRect(receiveDollarsLead).left, epsilon: 0.5));
    expect(close.center.dx, greaterThan(title.right));
    expect(close.center.dy,
        moreOrLessEquals(title.center.dy, epsilon: 1.5));
    final grid = find.byKey(const ValueKey('usd-receive-card'));
    final cards = tester.widget<KuteActionCardGrid>(grid);
    // Dollars on top, the lead, as Bitcoin on the Bitcoin Receive.
    expect(cards.lead?.key, kUsdReceiveDollarsKey);
    expect(cards.cards.map((c) => c.key),
        [const ValueKey('usd-receive-from-another')]);
    final dollars = tester.widget<KuteActionCard>(receiveDollarsLead);
    expect(dollars.title, _l10n.portfolioBalanceDollars);
    expect(dollars.title, 'Dollars');
    // The dollar coins it takes, named as Another crypto names its coins.
    expect(dollars.subtitle, _l10n.anotherCryptoCoinsPair('USDC', 'USDT'));
    expect(dollars.subtitle, 'USDC and USDT');
    expect(dollars.visual, isA<SvgPicture>());
    expect(dollars.visualSlot, kKuteActionCardLeadVisualSlot);
    expect(receiveFromAnotherRow, findsOneWidget);
    final another = tester.widget<KuteActionCard>(receiveFromAnotherRow);
    expect(another.title, _l10n.receiveAnotherCrypto);
    expect(another.title, 'Another crypto');
    // The other coins, both named, never a dollar coin the lead names: no
    // "and more", no count, no "Wallet or exchange".
    expect(another.subtitle, _l10n.anotherCryptoCoinsPair('ETH', 'SOL'));
    expect(another.subtitle, 'ETH and SOL');
    expect(another.visual, isA<AnotherCryptoMarks>());
    expect(
        (another.visual as AnotherCryptoMarks)
            .coins
            .map((g) => g.displaySymbol),
        ['ETH', 'SOL']);
    _expectCoinsWhole(tester, receiveFromAnotherRow);
    for (final (card, title) in [
      (receiveDollarsLead, dollars.title),
      (receiveDollarsLead, dollars.subtitle!),
      (receiveFromAnotherRow, another.title),
      (receiveFromAnotherRow, another.subtitle!),
    ]) {
      expect(_lines(tester, card, title), 1, reason: title);
    }
    // The lead across the width, taller than the compact card under it;
    // both across the width with their chevron.
    final lead = tester.getRect(receiveDollarsLead);
    final b = tester.getRect(receiveFromAnotherRow);
    expect(lead.left, moreOrLessEquals(b.left));
    expect(lead.right, moreOrLessEquals(b.right));
    expect(lead.bottom, lessThan(b.top));
    expect(b.height, lessThan(lead.height));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
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
      '"Dollars" opens the coin sheet with the dollar coins alone',
      (tester) async {
    await _pump(tester);
    await tester.tap(receiveDollarsLead);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(names(), contains('usd_receive_coin_picker_opened'));
    expect(_tile('USDC'), findsOneWidget);
    expect(_tile('USDT'), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'ETH'), findsNothing);
    expect(find.widgetWithText(CoinAssetTile, 'SOL'), findsNothing);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    await _unmount(tester);
  });

  testWidgets(
      '"Another crypto" opens the coin sheet with the other coins, as the '
      'Bitcoin receive\'s own card does', (tester) async {
    await _pump(tester);
    await openReceiveCoins(tester, symbol: 'ETH');
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(names(), contains('usd_receive_coin_picker_opened'));
    expect(_tile('ETH'), findsOneWidget);
    expect(_tile('SOL'), findsOneWidget);
    expect(find.widgetWithText(CoinAssetTile, 'USDC'), findsNothing);
    expect(find.widgetWithText(CoinAssetTile, 'USDT'), findsNothing);
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    await _unmount(tester);
  });

  testWidgets(
      'one dollar coin and no other: "Dollars" names it alone and goes '
      'straight to its networks, as a coin tapped on a grid does; no '
      'Another crypto: the lead alone', (tester) async {
    await _pump(tester, usdt: false, others: false);
    expect(receiveFromAnotherRow, findsNothing);
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(tester.widget<KuteActionCard>(receiveDollarsLead).subtitle, 'USDC');
    expect(
        tester
            .widget<KuteActionCardGrid>(
                find.byKey(const ValueKey('usd-receive-card')))
            .cards,
        isEmpty);

    await tester.tap(receiveDollarsLead);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Open on USDC's networks, never a grid of one coin.
    expect(find.byType(CoinAssetPickerSheet), findsOneWidget);
    expect(find.byType(PickerRow), findsNWidgets(4));
    expect(find.byType(CoinAssetTile), findsNothing);
    final picked =
        events.where((e) => e.$1 == 'coin_picker_coin_picked').single.$2;
    expect(picked, {'flow': 'usd_receive', 'asset': 'USDC', 'networks': 4});
    expect(names(), isNot(contains('usd_receive_coin_selected')));
    expect(tester.takeException(), isNull);
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
    expect(receiveDollarsLead, findsOneWidget);
    expect(receiveFromAnotherRow, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'a coin on one network asks its amount in the "Request amount" sheet, '
      'in dollars; dismissing it leaves the coin step as '
      'it was', (tester) async {
    await _pump(tester);
    final sheet = ModalRoute.of(tester.element(receiveDollarsLead));
    expect(sheet, isA<ModalBottomSheetRoute<void>>());
    expect(find.byType(KuteCloseButton), findsOneWidget);
    // The first step's close X at the top right, as on the Bitcoin
    // receive.
    expect(tester.getCenter(find.byType(KuteCloseButton)).dx,
        greaterThan(tester.getCenter(find.byType(UsdReceiveScreen)).dx));
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
    expect(receiveDollarsLead, findsOneWidget);
    expect(names(), isNot(contains('receive_address_generated')));

    // On the coin step the header's close closes the sheet.
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(receiveDollarsLead, findsNothing);
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
      'nothing offered: no card, the note that says why under the header',
      (tester) async {
    await _pump(tester, stables: false, others: false);
    expect(find.byKey(_bitcoinRow), findsNothing);
    expect(receiveDollarsLead, findsNothing);
    expect(receiveFromAnotherRow, findsNothing);
    expect(find.byType(KuteActionCard), findsNothing);
    expect(find.text(_l10n.usdReceiveCoinsUnavailable), findsOneWidget);
    expect(find.byType(SheetTitleHeader), findsOneWidget);
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
      'at 375 pt, in Inter, in every shipped language: the title whole on '
      'the left and the X at the right, Dollars on top, Another crypto '
      'under it across the width, every word whole inside its card, '
      'nothing overflowing; the sheet short and the bar away',
      (tester) async {
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
      final lead = tester.getRect(receiveDollarsLead);
      final b = tester.getRect(receiveFromAnotherRow);
      expect(lead.bottom, lessThan(b.top), reason: why);
      expect(_lines(tester, receiveDollarsLead, l10n.portfolioBalanceDollars),
          1,
          reason: why);
      expect(b.left, moreOrLessEquals(lead.left), reason: why);
      expect(b.right, moreOrLessEquals(lead.right), reason: why);
      expect(b.right, lessThanOrEqualTo(375), reason: why);
      final heading = tester.renderObject<RenderParagraph>(find
          .descendant(
              of: find.text(l10n.receive), matching: find.byType(RichText))
          .first);
      expect(heading.didExceedMaxLines, isFalse, reason: '$why: title cut');
      expect(tester.getRect(find.byKey(SheetTitleHeader.closeKey)).left,
          greaterThan(tester.getRect(find.text(l10n.receive)).right),
          reason: why);
      expect(
          find.descendant(
              of: receiveFromAnotherRow,
              matching: find.text(l10n.receiveAnotherCrypto)),
          findsOneWidget,
          reason: why);
      // Its title on one line, the coins whole in their box.
      expect(
          _lines(tester, receiveFromAnotherRow, l10n.receiveAnotherCrypto), 1,
          reason: why);
      final line =
          tester.widget<KuteActionCard>(receiveFromAnotherRow).subtitle!;
      expect(_lines(tester, receiveFromAnotherRow, line), 1,
          reason: '$why: $line');
      _expectCoinsWhole(tester, receiveFromAnotherRow);
      for (final (card, box) in [
        (receiveDollarsLead, lead),
        (receiveFromAnotherRow, b),
      ]) {
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
