// A look by eye at the Investing Advanced order page (order_slip_sheet.dart
// on the shared Advanced pieces, advanced_ticket.dart): the amount as the
// hero, the type tiles, the steppers with their presets, the price map,
// the protection switches, the summary card and the primary floating over
// the form. Each state on a phone (402 x 874) light and dark, a small
// phone (375 x 667) and the web's side panel (1440 x 900). Written only
// when asked: HL_ADV_RENDER=<dir>.
//   HL_ADV_RENDER=<dir> flutter test test/render/hl_advanced_ticket_render_test.dart
//
// Without the variable every state still pumps, and nothing may overflow
// or sit under the floating primary once scrolled to the foot.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_swap_orders.dart';
import '../helpers/shell_bar_harness.dart';

final _dir = Platform.environment['HL_ADV_RENDER'];

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// The account: 1,000 of cash, and (when [held]) a 10x BTC long opened
/// elsewhere, which the exposure rule only lets this ticket reduce.
class _Account extends HlAccountNotifier {
  _Account({required this.held});
  final bool held;
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
        accountValue: 1000,
        withdrawable: 1000,
        totalMarginUsed: held ? 66 : 0,
        positions: [
          if (held)
            const HlPerpPosition(
              coin: 'BTC',
              szi: 0.01,
              entryPx: 66000,
              positionValue: 660,
              unrealizedPnl: 0,
              returnOnEquity: 0,
              liquidationPx: null,
              marginUsed: 66,
              leverageType: 'isolated',
              leverageValue: 10,
              maxLeverage: 40,
            ),
        ],
        spotBalances: const [],
      );
}

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}

const _long = HlPerpPosition(
  coin: 'BTC',
  szi: 0.01,
  entryPx: 64000,
  positionValue: 660,
  unrealizedPnl: 20,
  returnOnEquity: 0.03,
  liquidationPx: null,
  marginUsed: 640,
  leverageType: 'isolated',
  leverageValue: 1,
  maxLeverage: 40,
);

/// The close sheet over a page, its Advanced page opened.
Future<void> _pumpClose(WidgetTester tester,
    {required Size size, required bool dark}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  OpenOnce.reset();
  addTearDown(OpenOnce.reset);
  installShellBar();
  final theme = dark ? buildDarkTheme() : buildLightTheme();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => [_long]),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      aiEnabledProvider.overrideWith((_) async => false),
    ],
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: shellBarObservers(),
        builder: shellBarBuilder,
        home: const Scaffold(
          body: Align(
              alignment: Alignment.bottomCenter,
              child: HlClosePositionSheet(position: _long, market: _btc)),
        ),
      ),
    ),
  ));
  await _settle(tester);
  final button = find.byKey(const ValueKey('slip-advanced-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settle(tester);
}

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

Future<void> _fonts() async {
  for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
    final inter = FontLoader(family);
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  }
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester,
    {required Size size, required bool dark, bool held = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  installShellBar();
  final wide = size.width >= 1200;
  final ticket = wide
      ? HlOrderSlipSheet.inPlace(
          market: _btc,
          entrySource: 'test',
          onDone: () {},
          isLong: true,
          typedAmount: true)
      : HlOrderSlipSheet(market: _btc, initialIsLong: true);
  final theme = dark ? buildDarkTheme() : buildLightTheme();
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
            reviewDone: false,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(() => _Account(held: held)),
      hyperliquidWithdrawableProvider.overrideWith((_) => 1000),
      hyperliquidSpotBalancesProvider.overrideWith((_) => []),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
    ],
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: shellBarObservers(),
        builder: shellBarBuilder,
        home: Scaffold(
          body: wide
              ? Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(width: 420, height: 860, child: ticket))
              : Align(alignment: Alignment.bottomCenter, child: ticket),
        ),
      ),
    ),
  ));
  await _settle(tester);
  final button = find.byKey(const ValueKey('slip-advanced-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settle(tester);
}

Future<void> _shoot(WidgetTester tester, String name) async {
  if (_dir == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size,
        pixelRatio: view.size.width > 1000 ? 1.25 : 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Finder get _scroll => find.byKey(const ValueKey('hl-advanced-form-scroll'));

/// The close page's shots: its top, a screen at a time, its foot (the
/// summary clear of the floating button).
Future<void> _closeShots(WidgetTester tester, String name) async {
  final state = tester.state<ScrollableState>(find
      .descendant(
          of: find.byKey(const ValueKey('hl-close-adv-scroll')),
          matching: find.byType(Scrollable))
      .first);
  state.position.jumpTo(0);
  await _settle(tester, 4);
  await _shoot(tester, '${name}_top');
  state.position.jumpTo(state.position.maxScrollExtent);
  await _settle(tester, 4);
  await _shoot(tester, '${name}_foot');
  final summary =
      tester.getRect(find.byKey(const ValueKey('hl-close-adv-summary')));
  final primary =
      tester.getRect(find.byKey(const ValueKey('advanced-ticket-primary')));
  expect(summary.bottom, lessThanOrEqualTo(primary.top + 1),
      reason: '$name: the summary scrolls clear of the floating button');
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f, warnIfMissed: false);
  await _settle(tester, 6);
}

/// Types the amount into the hero, then leaves it (a focused field keeps
/// its caret on screen, so the page would not stay scrolled).
Future<void> _amount(WidgetTester tester, String text) async {
  await tester.enterText(
      find.descendant(
          of: find.byKey(const ValueKey('hl-advanced-amount')),
          matching: find.byType(TextField)),
      text);
  await _settle(tester, 4);
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester, 4);
}

/// The page at its top, then scrolled to its foot (where the last card
/// must clear the floating primary).
Future<void> _topAndFoot(WidgetTester tester, String name) async {
  final scrollable = find.descendant(
      of: _scroll, matching: find.byType(Scrollable)).first;
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(0);
  await _settle(tester, 4);
  await _shoot(tester, '${name}_top');
  // The middle, a screen at a time, so every card is seen once.
  final step = state.position.viewportDimension - 220;
  var k = 1;
  for (var at = step;
      at < state.position.maxScrollExtent - 40;
      at += step, k++) {
    state.position.jumpTo(at);
    await _settle(tester, 2);
    await _shoot(tester, '${name}_mid$k');
  }
  state.position.jumpTo(state.position.maxScrollExtent);
  await _settle(tester, 4);
  await _shoot(tester, '${name}_foot');
  // The last card ends above the primary's room.
  final summary = tester.getRect(
      find.byKey(const ValueKey('order-slip-adv-summary')));
  final primary =
      tester.getRect(find.byKey(const ValueKey('advanced-ticket-primary')));
  expect(summary.bottom, lessThanOrEqualTo(primary.top + 1),
      reason: '$name: the summary scrolls clear of the floating primary');
  state.position.jumpTo(0);
  await _settle(tester, 2);
}

typedef _State = Future<void> Function(WidgetTester tester);

final Map<String, _State> _states = {
  'market': (tester) async {
    await _amount(tester, '250');
  },
  'limit_chips': (tester) async {
    await _amount(tester, '250');
    await _tap(tester, find.byKey(const ValueKey('hl-adv-type-limit')));
    await _tap(tester,
        find.descendant(
            of: find.byKey(const ValueKey('hl-adv-chips-limitPrice')),
            matching: find.byKey(const ValueKey('advanced-chip-1'))));
  },
  'limit_tpsl_map': (tester) async {
    await _amount(tester, '250');
    await _tap(tester, find.byKey(const ValueKey('hl-adv-type-limit')));
    await _tap(tester,
        find.descendant(
            of: find.byKey(const ValueKey('hl-adv-chips-limitPrice')),
            matching: find.byKey(const ValueKey('advanced-chip-1'))));
    await _tap(tester, find.byKey(const ValueKey('order-slip-tpsl-switch')));
    await _tap(tester,
        find.descendant(
            of: find.byKey(const ValueKey('hl-adv-chips-takeProfit')),
            matching: find.byKey(const ValueKey('advanced-chip-1'))));
    await _tap(tester,
        find.descendant(
            of: find.byKey(const ValueKey('hl-adv-chips-stopLoss')),
            matching: find.byKey(const ValueKey('advanced-chip-0'))));
  },
  'scale': (tester) async {
    await _amount(tester, '500');
    await _tap(tester, find.byKey(const ValueKey('hl-adv-type-scale')));
  },
  'twap': (tester) async {
    await _amount(tester, '500');
    await _tap(tester, find.byKey(const ValueKey('hl-adv-type-twap')));
  },
  'market_trailing': (tester) async {
    await _amount(tester, '250');
    await _tap(tester, find.byKey(const ValueKey('order-slip-trailing-switch')));
    await _tap(tester, find.byKey(const ValueKey('order-slip-expert-settings')));
  },
};

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _fonts();
  });

  const phone = Size(402, 874);
  const small = Size(375, 667);
  const wide = Size(1440, 900);

  for (final entry in _states.entries) {
    for (final (label, size, dark) in [
      ('phone_light', phone, false),
      ('phone_dark', phone, true),
      ('small_light', small, false),
      ('wide_light', wide, false),
    ]) {
      testWidgets('${entry.key} · $label', (tester) async {
        await _pump(tester, size: size, dark: dark);
        await entry.value(tester);
        await _topAndFoot(tester, '${entry.key}_$label');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (label, size, dark) in [
    ('phone_light', phone, false),
    ('phone_dark', phone, true),
    ('small_light', small, false),
  ]) {
    testWidgets('a refusal line (a held 10x position) · $label',
        (tester) async {
      await _pump(tester, size: size, dark: dark, held: true);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('hl-advanced-amount')),
              matching: find.byType(TextField)),
          '50');
      await _settle(tester, 6);
      expect(
          find.text('This position uses leverage, so here you can only '
              'reduce or close it.'),
          findsOneWidget);
      await _topAndFoot(tester, 'refusal_$label');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (type, label) in [
    (null, 'market'),
    ('Limit', 'limit'),
    ('Stop market', 'stop'),
    ('TWAP', 'twap'),
  ]) {
    for (final (theme, size, dark) in [
      ('phone_light', phone, false),
      ('phone_dark', phone, true),
      ('small_light', small, false),
    ]) {
      testWidgets('close · $label · $theme', (tester) async {
        await _pumpClose(tester, size: size, dark: dark);
        if (type == 'Limit') {
          await _tap(tester, find.text('Limit'));
        } else if (type != null) {
          await _tap(tester, find.text('More options'));
          await tester.tap(find.text(type).last);
          await _settle(tester, 8);
        }
        if (type == 'Stop market') {
          await _tap(tester,
              find.descendant(
                  of: find.byKey(const ValueKey('hl-close-chips-trigger')),
                  matching: find.byKey(const ValueKey('advanced-chip-1'))));
        }
        await _closeShots(tester, 'close_${label}_$theme');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
