// The Bitcoin receive's first sheet, "Receive" (founder, 6 and 7
// November 2026: "Bitcoin should be on top, more prevalent here"; the
// word swap appears nowhere), in the first steps' header: "Receive" big on
// the left, the compact X at the top right ("it is strange the size" of
// the old big X on the left). The Bitcoin tab's Receive opens Bitcoin
// ("Bitcoin and Lightning") on top, full width and larger, then Another
// crypto under it, the grid's lone card, compact and full width ("USDC,
// ETH and more", those two coins' marks side by side, whole; founder, 7
// November 2026: "Another crypto", was "Another wallet"), in a sheet as
// tall as they are, the floating bar away. No "From your Dollars"
// (founder, 7 November 2026: "On bitcoin receive we get rid of from your
// dollars"). Each card opens its sheet over this one: the QR receive, the
// other coins sheet. Another crypto only while a coin can be offered (the
// spending wallet, an account that may be offered swaps); without it,
// Bitcoin alone. Nothing here reaches a money call.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
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
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
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
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveSheetFrame, SheetTitleHeader;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show AnotherCryptoMarks;
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

/// The door the founder took away (7 November 2026), to say it is gone.
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
      usdBalanceProvider.overrideWithValue(4.75),
      usdBalanceUnknownProvider.overrideWithValue(false),
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

/// The coins of the "Another crypto" [card] lie whole, side by side and
/// inside the card, none over another, each a circle at the grid's visual
/// size (the Bitcoin lead's mark is the lead's larger one: 40 to its 48).
void _expectCoinsWhole(WidgetTester tester, Finder card) {
  final marks =
      find.descendant(of: card, matching: find.byType(AnotherCryptoMarks));
  expect(marks, findsOneWidget);
  final coins = find.descendant(of: marks, matching: find.byType(AssetIcon));
  expect(coins, findsNWidgets(2));
  final box = tester.getRect(card);
  final lead = tester.getSize(find
      .descendant(
          of: find.byKey(_bitcoin),
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

/// The first steps' header: [title] big on the left, on the content's left
/// edge; the compact X at the top right, its circle's right edge on the
/// content's right edge ([content]), centred on the title's line.
void expectSheetTitleHeader(WidgetTester tester, String title, Finder content) {
  final header = find.byType(SheetTitleHeader);
  expect(header, findsOneWidget);
  final text = find.descendant(of: header, matching: find.text(title));
  expect(text, findsOneWidget);
  expect(tester.widget<Text>(text).style!.fontWeight, FontWeight.w800);
  final close = find.byKey(SheetTitleHeader.closeKey);
  expect(close, findsOneWidget);
  final x = find.descendant(of: close, matching: find.byType(KuteCloseButton));
  final circle = find.descendant(of: x, matching: find.byType(CustomPaint));
  final t = tester.getRect(text);
  final c = tester.getRect(circle.first);
  final body = tester.getRect(content);
  expect(t.left, moreOrLessEquals(body.left, epsilon: 0.5));
  expect(c.right, moreOrLessEquals(body.right, epsilon: 0.5));
  expect(c.center.dy, moreOrLessEquals(t.top + t.height / 2, epsilon: 1.5),
      reason: 'the X on the title\'s line');
  // Compact: smaller than the title line is tall, never the 40 circle.
  expect(c.height, lessThan(t.height + 4));
  expect(c.height, lessThan(33));
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
    ReceiveSheets.debugBitcoinBody = null;
  });

  testWidgets(
      'the spending wallet: "Receive" big on the left with the compact X at '
      'the top right, Bitcoin ("Bitcoin and Lightning") on top, full width '
      'and larger, then Another crypto ("USDC, ETH and more", those two '
      'coins side by side, whole) under it, the grid\'s lone card, compact '
      'and full width; no From your Dollars; a short sheet with the bar '
      'away', (tester) async {
    await tester.runAsync(_loadInter);
    await _pump(tester);
    final sheet = ModalRoute.of(tester.element(find.byKey(_bitcoin)));
    expect(sheet, isA<ModalBottomSheetRoute<void>>());
    expect(sheet!.settings.name, kBitcoinReceiveOptionsRouteName);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.textContaining('swap'), findsNothing);
    expect(find.textContaining('Swap'), findsNothing);
    expect(find.byType(AccountSwitcherPill), findsNothing);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    expectSheetTitleHeader(tester, 'Receive', find.byKey(_bitcoin));
    expect(
        tester.getSemantics(find.text('Receive')),
        matchesSemantics(label: 'Receive', isHeader: true));

    final grid = tester.widget<KuteActionCardGrid>(
        find.byKey(const ValueKey('bitcoin-receive-options')));
    expect(grid.lead?.key, _bitcoin);
    expect(grid.cards.map((c) => c.key), [_fromAnother]);
    expect(find.byKey(_fromDollars), findsNothing);
    expect(find.text(_l10n.receiveFromYourDollars), findsNothing);
    expect(_card(tester, _bitcoin).title, 'Bitcoin');
    expect(_card(tester, _bitcoin).subtitle, 'Bitcoin and Lightning');
    expect(_card(tester, _fromAnother).title, 'Another crypto');
    expect(_card(tester, _fromAnother).title, _l10n.receiveAnotherCrypto);
    expect(find.text('Another wallet'), findsNothing);
    expect(_card(tester, _fromAnother).subtitle, 'USDC, ETH and more');
    _expectCoinsWhole(tester, find.byKey(_fromAnother));

    // Bitcoin on top across the whole width, then Another crypto across
    // it too, compact (shorter than the lead), both with their chevron.
    final top = tester.getRect(find.byKey(_bitcoin));
    final under = tester.getRect(find.byKey(_fromAnother));
    expect(top.bottom, lessThan(under.top));
    expect(top.left, moreOrLessEquals(under.left));
    expect(top.right, moreOrLessEquals(under.right));
    expect(under.height, lessThan(top.height));
    for (final card in [_bitcoin, _fromAnother]) {
      expect(
          find.descendant(
              of: find.byKey(card),
              matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget);
    }

    // As tall as the cards: short, so the floating bar goes while it is up.
    final frame = tester.getRect(find.byType(ReceiveSheetFrame));
    expect(frame.height, lessThan(844 * kuteBarShortSheetFraction));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BitcoinReceiveOptions)));
    expect(kuteBarTop(container.read(kuteBarContextProvider))?.hidden, isTrue);
    expect(tester.takeException(), isNull);

    // The X closes the sheet.
    await tester.tap(find.byKey(SheetTitleHeader.closeKey));
    await tester.pumpAndSettle();
    expect(find.byType(BitcoinReceiveOptions), findsNothing);
    expect(find.text(_underneath), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'Another crypto opens the other coins sheet over this one, '
      'delivering bitcoin', (tester) async {
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
    // An inner step: its own header, the X on the left.
    expect(
        find.descendant(
            of: find.byType(UsdReceiveScreen),
            matching: find.byType(SheetTitleHeader)),
        findsNothing);
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
      'no coin to offer (no coin in the catalogue, no swaps for the account, '
      'or a watch-only wallet): Bitcoin alone, full width', (tester) async {
    for (final (coins, swaps, account) in [
      (false, true, null),
      (true, false, null),
      (true, true, BtcSpendingAccount(_cold)),
    ]) {
      await _pump(tester, coins: coins, swaps: swaps, account: account);
      expect(find.byKey(_fromAnother), findsNothing);
      expect(find.byKey(_fromDollars), findsNothing);
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
    }
  });

  testWidgets(
      'at 375 pt, in Inter, in every shipped language: the title whole on '
      'the left and the X at the right, Bitcoin across the top, Another '
      'crypto under it across the width, every word whole inside its card, '
      'the coins whole, nothing overflowing; the sheet short',
      (tester) async {
    await tester.runAsync(_loadInter);
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = l10nForLanguage(locale.languageCode);
      final why = locale.languageCode;
      await _pump(tester, size: const Size(375, 812), locale: locale);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: why);
      expect(find.text(l10n.receive), findsOneWidget, reason: why);
      final title = tester.renderObject<RenderParagraph>(find
          .descendant(
              of: find.text(l10n.receive), matching: find.byType(RichText))
          .first);
      expect(title.didExceedMaxLines, isFalse,
          reason: '$why: the title is cut');
      expectSheetTitleHeader(tester, l10n.receive, find.byKey(_bitcoin));
      final cards = [_bitcoin, _fromAnother];
      final rects = [for (final k in cards) tester.getRect(find.byKey(k))];
      expect(rects[1].top, greaterThan(rects[0].bottom), reason: why);
      expect(rects[0].left, moreOrLessEquals(rects[1].left), reason: why);
      expect(rects[0].right, moreOrLessEquals(rects[1].right), reason: why);
      _expectCoinsWhole(tester, find.byKey(_fromAnother));
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
