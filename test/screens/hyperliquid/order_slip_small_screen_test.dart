// The Investing order slip on a short phone (375 x 667, the iPhone SE),
// at the app's text size and at 1.3x: nothing overflows, the two tiles
// and their figures sit whole above the keypad, never under it or cut,
// and a stopped order's notice is whole on screen too.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
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

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 500,
        withdrawable: 500,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      );
}

class _Funded extends FundedOrdersNotifier {
  @override
  List<FundedOrderRecord> build() => const [];
  void put(List<FundedOrderRecord> next) => state = next;
}

const _market = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

/// A Long already held, so the order adds to it.
const _held = HlPerpPosition(
  coin: 'BTC',
  szi: 0.01,
  entryPx: 60000,
  positionValue: 600,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: null,
  marginUsed: 600,
  leverageType: 'isolated',
  leverageValue: 1,
  maxLeverage: 40,
);

/// A funded $12 Long the venue rejected once the money landed.
FundedOrderRecord _stopped() => FundedOrderRecord(
      id: 'fo_stop',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.investing,
        orderUsd: 12,
        side: 'Long',
        market: 'BTC',
        marketKey: 'BTC',
      ),
      stage: FundedOrderStage.failed,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      venueRowIds: const {'q_move'},
      stoppedAt: FundedOrderStage.placing,
      moneyAt: FundedMoneyAt.venue,
      reason: 'placement',
      message: 'Order rejected.',
    );

late FakeHyperliquidMoveRail _rail;

Future<void> _frames(WidgetTester tester, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the slip on an iPhone SE, types $12 on its keypad and, when
/// [stopped], stops the funded order.
Future<void> _open(WidgetTester tester,
    {required double scale,
    List<HlPerpPosition> positions = const [],
    bool stopped = false}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(375 * 2, 667 * 2);
  tester.view.padding = const FakeViewPadding(top: 40);
  tester.view.viewPadding = const FakeViewPadding(top: 40);
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
            reviewDone: false,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => 0),
      hyperliquidMoveRailProvider.overrideWithValue(_rail),
      hyperliquidPerpPositionsProvider.overrideWith((_) => positions),
      fundedOrdersProvider.overrideWith(_Funded.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const Scaffold(),
      ),
    ),
  ));
  await tester.pump();
  showModalBottomSheet(
    context: tester.element(find.byType(Scaffold)),
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        const HlOrderSlipSheet(market: _market, initialIsLong: true),
  );
  await _frames(tester);
  final pad = find.byType(AmountKeypad);
  for (final key in ['1', '2']) {
    await tester.tap(find.descendant(of: pad, matching: find.text(key)));
    await tester.pump();
  }
  await _frames(tester);
  if (stopped) {
    (ProviderScope.containerOf(tester.element(find.byType(HlOrderSlipSheet)))
            .read(fundedOrdersProvider.notifier) as _Funded)
        .put([_stopped()]);
    await _frames(tester);
  }
}

/// The tile's figure: its largest text.
Finder _figure(WidgetTester tester, Finder tile) {
  final texts = find.descendant(of: tile, matching: find.byType(Text));
  Element? best;
  var size = 0.0;
  for (final e in texts.evaluate()) {
    final s = (e.widget as Text).style?.fontSize ?? 0;
    if (s > size) {
      size = s;
      best = e;
    }
  }
  expect(best, isNotNull);
  return find.byElementPredicate((e) => e == best);
}

/// [what] is whole inside the form's viewport and above the keypad.
void _expectWhole(WidgetTester tester, Finder what) {
  final viewport = tester.getRect(find
      .descendant(
          of: find.byType(HlOrderSlipSheet), matching: find.byType(Scrollable))
      .first);
  final keypadTop = tester.getRect(find.byType(AmountKeypad)).top;
  final rect = tester.getRect(what);
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.5), reason: '$what');
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5),
      reason: '$what');
  expect(rect.bottom, lessThanOrEqualTo(keypadTop + 0.5), reason: '$what');
}

void _expectTilesWhole(WidgetTester tester) {
  for (final key in ['order-slip-size-tile', 'order-slip-fee-tile']) {
    final tile = find.byKey(ValueKey(key));
    expect(tile, findsOneWidget);
    _expectWhole(tester, tile);
    _expectWhole(tester, _figure(tester, tile));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    _rail = FakeHyperliquidMoveRail();
    _rail.quote = const VenueMoveQuote(
        arrivingUsd: 0,
        feeUsd: 0.02,
        fixedCostUsd: 1,
        minUsd: 0.8,
        maxUsd: 107600);
  });
  tearDown(() => _rail.creditedController.close());

  for (final scale in [1.0, 1.3]) {
    group('iPhone SE, text at ${scale}x', () {
      testWidgets('an order typed: the tiles whole above the keypad',
          (tester) async {
        await _open(tester, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text(r'$12'), findsOneWidget);
        _expectTilesWhole(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets(
          'adding to a held Long: the pill and the tiles whole above the '
          'keypad', (tester) async {
        await _open(tester, scale: scale, positions: const [_held]);
        expect(tester.takeException(), isNull);
        final pill = find.byKey(const ValueKey('slip-position-pill'));
        expect(pill, findsOneWidget);
        _expectWhole(tester, pill);
        _expectTilesWhole(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets(
          'a stopped order: the notice and the tiles whole above the keypad',
          (tester) async {
        await _open(tester, scale: scale, stopped: true);
        expect(tester.takeException(), isNull);
        final notice = find.byKey(const ValueKey('order-slip-funded-stop'));
        expect(notice, findsOneWidget);
        _expectWhole(tester, notice);
        _expectTilesWhole(tester);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}
