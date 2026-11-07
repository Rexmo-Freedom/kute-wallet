// The Bitcoin receive's first sheet, "Receive" (founder, 6 and 7
// November 2026: "Bitcoin should be on top, more prevalent here"; the
// word swap appears nowhere): the Bitcoin tab's Receive opens Bitcoin
// ("Bitcoin and Lightning") on top, full width and larger, then two
// squares under it, From your Dollars (its balance) and From another
// wallet or exchange (the coins stacked), in a sheet as tall as they
// are, the floating bar away. Each card opens its sheet over this one:
// the QR receive, Move money straight on the amount (Dollars to Bitcoin,
// pinned), the other coins sheet. From your Dollars is only on the
// spending wallet (a watch-only or hardware wallet has no Dollars); From
// another wallet or exchange only while a coin can be offered; with one
// hidden the other is full width and compact under Bitcoin. Nothing here
// reaches a money call.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/receive/bitcoin_receive_options.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show kuteBarShortSheetFraction;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarContextProvider, kuteBarTop;
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendCoinStack;
import 'package:kute/screens/usd/usd_receive_screen.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/runtime_policy_fixture.dart';

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog({bool coins = true}) =>
    OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8),
          _row('spark', 'USDB'),
          if (coins) ...[
            _row('base', 'USDC'),
            _row('ethereum', 'USDT'),
            _row('ethereum', 'ETH', decimals: 18),
            _row('solana', 'SOL', decimals: 9),
          ],
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime.now(),
    );

final _l10n = AppLocalizationsEn();

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _cold = WalletConfig(
    id: 'cold', name: 'Cold', isWatchOnly: true, sparkEnabled: false);

const _fromDollars = ValueKey('bitcoin-receive-from-dollars');
const _fromAnother = ValueKey('bitcoin-receive-from-another');
const _bitcoin = ValueKey('bitcoin-receive-bitcoin');
const _underneath = 'open receive';

/// Opens Receive or swap the way the Bitcoin row does, over a screen.
Future<void> _pump(WidgetTester tester,
    {Size size = const Size(390, 844),
    Locale? locale,
    bool coins = true,
    bool swaps = true,
    double? dollars = 4.75,
    Account? account}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
            wallets: [_spending, _cold],
          ))),
      selectedAccountProvider
          .overrideWithValue(account ?? BtcSpendingAccount(_spending)),
      swapOffersEnabledProvider.overrideWithValue(swaps),
      orchestraSupportedRoutesProvider
          .overrideWith((_) => _Routes(_catalog(coins: coins))),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      standingDestinationsProvider.overrideWith((_) async => {'spark:USDB'}),
      receiveMinimumsProvider
          .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
      usdBalanceProvider.overrideWithValue(dollars ?? 0),
      usdBalanceUnknownProvider.overrideWithValue(dollars == null),
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
                onPressed: () => showBitcoinReceiveSheet(context),
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

KuteActionCard _card(WidgetTester tester, Key key) =>
    tester.widget<KuteActionCard>(find.byKey(key));

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
    ReceiveSheets.debugBitcoinBody = null;
  });

  testWidgets(
      'the spending wallet: "Receive" over Bitcoin ("Bitcoin and '
      'Lightning") on top, full width and larger, then From your Dollars '
      '(its balance) and From another wallet or exchange (the coins '
      'stacked) as two squares; a short sheet with the bar away',
      (tester) async {
    await _pump(tester);
    final sheet = ModalRoute.of(tester.element(find.byKey(_bitcoin)));
    expect(sheet, isA<ModalBottomSheetRoute<void>>());
    expect(sheet!.settings.name, kBitcoinReceiveOptionsRouteName);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.textContaining('swap'), findsNothing);
    expect(find.textContaining('Swap'), findsNothing);
    expect(find.byType(AccountSwitcherPill), findsNothing);
    // The close X on the left, as on every receive sheet.
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expect(tester.getCenter(find.byType(KuteCloseButton)).dx,
        lessThan(tester.getCenter(find.byType(BitcoinReceiveOptions)).dx));

    final grid = tester.widget<KuteActionCardGrid>(
        find.byKey(const ValueKey('bitcoin-receive-options')));
    expect(grid.lead?.key, _bitcoin);
    expect(grid.cards.map((c) => c.key), [_fromDollars, _fromAnother]);
    expect(_card(tester, _bitcoin).title, 'Bitcoin');
    expect(_card(tester, _bitcoin).subtitle, 'Bitcoin and Lightning');
    expect(_card(tester, _fromDollars).title, 'From your Dollars');
    expect(_card(tester, _fromDollars).subtitle, r'$4.75 in Dollars');
    expect(_card(tester, _fromAnother).title,
        'From another wallet or exchange');
    expect(_card(tester, _fromAnother).title,
        _l10n.usdReceiveFromAnotherWallet);
    // Three coins named, the rest counted ("USDC, USDT, ETH and N more").
    expect(_card(tester, _fromAnother).subtitle,
        matches(RegExp(r'^\w+, \w+, \w+ and 1 more$')));
    expect(
        find.descendant(
            of: find.byKey(_fromAnother), matching: find.byType(SendCoinStack)),
        findsOneWidget);

    // Bitcoin on top across the whole width, its chevron at the right and
    // a larger title than the squares'; the two squares side by side
    // under it, equally tall.
    final top = tester.getRect(find.byKey(_bitcoin));
    final a = tester.getRect(find.byKey(_fromDollars));
    final b = tester.getRect(find.byKey(_fromAnother));
    expect(top.bottom, lessThan(a.top));
    expect(top.left, moreOrLessEquals(a.left));
    expect(top.right, moreOrLessEquals(b.right));
    expect(a.top, moreOrLessEquals(b.top));
    expect(a.height, moreOrLessEquals(b.height));
    expect(a.right, lessThan(b.left));
    expect(
        find.descendant(
            of: find.byKey(_bitcoin),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);
    for (final square in [_fromDollars, _fromAnother]) {
      expect(
          find.descendant(
              of: find.byKey(square),
              matching: find.byIcon(Icons.chevron_right_rounded)),
          findsNothing);
    }
    double titleSize(Key card, String title) => tester
        .widget<Text>(find.descendant(
            of: find.byKey(card), matching: find.text(title)))
        .style!
        .fontSize!;
    expect(titleSize(_bitcoin, 'Bitcoin'),
        greaterThan(titleSize(_fromDollars, 'From your Dollars')));

    // As tall as the cards: short, so the floating bar goes while it is up.
    final frame = tester.getRect(find.byType(ReceiveSheetFrame));
    expect(frame.height, lessThan(844 * kuteBarShortSheetFraction));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BitcoinReceiveOptions)));
    expect(kuteBarTop(container.read(kuteBarContextProvider))?.hidden, isTrue);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'From your Dollars opens Move money straight on the amount, Dollars '
      'to Bitcoin, pinned, under its own entry source', (tester) async {
    final opened = <MoneyMovementRequest>[];
    debugMoneyMovementSheetOpener = (_, request) => opened.add(request);
    await _pump(tester);
    await tester.tap(find.byKey(_fromDollars));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(opened.single.route,
        const MoneyMovementRoute(MoneyMovementAccount.dollars,
            MoneyMovementAccount.bitcoin));
    expect(opened.single.pinned, isTrue);
    expect(opened.single.entrySource, kBitcoinReceiveDollarsSource);
    expect(TrackingService.takeEntrySource('move'), 'bitcoin_receive_dollars');
    // Nothing in between: the sheet stays as it was under the Move screen.
    expect(find.byType(BitcoinReceiveOptions), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'From another wallet or exchange opens the other coins sheet over '
      'this one, delivering bitcoin', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_fromAnother));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final coins =
        tester.widget<UsdReceiveScreen>(find.byType(UsdReceiveScreen));
    expect(coins.destinationAsset, 'BTC');
    expect(ModalRoute.of(tester.element(find.byType(UsdReceiveScreen)))!
        .settings
        .name, kOtherCoinsReceiveRouteName);
    expect(find.byType(BitcoinReceiveOptions, skipOffstage: false),
        findsOneWidget);
    expect(
        events
            .where((e) => e.$1 == 'receive_also_accepts_opened')
            .map((e) => e.$2),
        [
          {'source': 'receive_options', 'coins': 4},
        ]);
    await _unmount(tester);
  });

  testWidgets(
      'Bitcoin opens the QR receive over this one; closing it comes back '
      'here', (tester) async {
    ReceiveSheets.debugBitcoinBody = (context) => Center(
        child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('qr receive')));
    await _pump(tester);
    await tester.tap(find.byKey(_bitcoin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('qr receive'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('qr receive')))!.settings.name,
        kBitcoinReceiveRouteName);
    expect(TrackingService.takeEntrySource('receive'), 'receive_options');
    await tester.tap(find.text('qr receive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('qr receive'), findsNothing);
    expect(find.byKey(_bitcoin), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'no Dollars account (a watch-only wallet): no From your Dollars, and '
      'no other coin either; Bitcoin alone, full width', (tester) async {
    await _pump(tester, account: BtcSpendingAccount(_cold));
    expect(find.byKey(_fromDollars), findsNothing);
    expect(find.byKey(_fromAnother), findsNothing);
    expect(find.byKey(_bitcoin), findsOneWidget);
    expect(
        tester
            .widget<KuteActionCardGrid>(
                find.byKey(const ValueKey('bitcoin-receive-options')))
            .cards,
        isEmpty);
    expect(
        find.descendant(
            of: find.byKey(_bitcoin),
            matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'no coin to offer (or no swaps for the account): Bitcoin on top, '
      'From your Dollars under it full width and compact, never a square '
      'alone', (tester) async {
    for (final (coins, swaps) in [(false, true), (true, false)]) {
      await _pump(tester, coins: coins, swaps: swaps);
      expect(find.byKey(_fromAnother), findsNothing);
      final top = tester.getRect(find.byKey(_bitcoin));
      final under = tester.getRect(find.byKey(_fromDollars));
      expect(under.top, greaterThan(top.bottom));
      expect(under.left, moreOrLessEquals(top.left));
      expect(under.right, moreOrLessEquals(top.right));
      // The compact full-width card: its chevron at the right, shorter
      // than the lead.
      expect(
          find.descendant(
              of: find.byKey(_fromDollars),
              matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget);
      expect(under.height, lessThan(top.height));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }
  });

  testWidgets('a Dollars figure not known yet: no balance line',
      (tester) async {
    await _pump(tester, dollars: null);
    expect(_card(tester, _fromDollars).subtitle, isNull);
    await _unmount(tester);
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: Bitcoin across the '
      'top, the two squares side by side under it, every word whole inside '
      'its card, nothing overflowing; the sheet short', (tester) async {
    await tester.runAsync(_loadInter);
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester,
          size: const Size(375, 812), locale: locale, dollars: 1234.56);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: why);
      expect(find.text(l10n.receive), findsOneWidget, reason: why);
      final title = tester.renderObject<RenderParagraph>(find
          .descendant(
              of: find.text(l10n.receive), matching: find.byType(RichText))
          .first);
      expect(title.didExceedMaxLines, isFalse,
          reason: '$why: the title is cut');
      final cards = [_bitcoin, _fromDollars, _fromAnother];
      final rects = [for (final k in cards) tester.getRect(find.byKey(k))];
      expect(rects[1].top, greaterThan(rects[0].bottom), reason: why);
      expect(rects[1].top, moreOrLessEquals(rects[2].top), reason: why);
      expect(rects[0].left, moreOrLessEquals(rects[1].left), reason: why);
      expect(rects[0].right, moreOrLessEquals(rects[2].right), reason: why);
      for (var c = 0; c < cards.length; c++) {
        final box = rects[c];
        expect(box.left, greaterThanOrEqualTo(0), reason: why);
        expect(box.right, lessThanOrEqualTo(375), reason: why);
        final texts = find.descendant(
            of: find.byKey(cards[c]), matching: find.byType(RichText));
        expect(texts, findsWidgets, reason: why);
        for (var i = 0; i < texts.evaluate().length; i++) {
          final p = tester.renderObject<RenderParagraph>(texts.at(i));
          expect(p.didExceedMaxLines, isFalse, reason: '$why: a line is cut');
          final shown = tester.getRect(texts.at(i));
          expect(shown.right, lessThanOrEqualTo(box.right + 0.5), reason: why);
          expect(shown.bottom, lessThanOrEqualTo(box.bottom + 0.5),
              reason: '$why: a line runs past its card');
        }
      }
      final frame = tester.getRect(find.byType(ReceiveSheetFrame));
      expect(frame.height, lessThan(812 * kuteBarShortSheetFraction),
          reason: why);
      await _unmount(tester);
    }
  });
}
