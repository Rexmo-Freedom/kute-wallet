// The Predictions bet slip on a short phone (375 x 667, the iPhone SE),
// at the app's text size and at 1.3x: nothing overflows, the two tiles
// and their figures sit whole above the keypad, never under it or cut,
// and a stopped bet's notice and amount are whole on screen too.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.balance);
  final double balance;
  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(usdcBalance: balance);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.58, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.42, tokenId: 'no-token'),
];

FundedOrderRecord _stopped() => FundedOrderRecord(
      id: 'fo_stop',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.predictions,
        orderUsd: 12,
        side: 'Yes',
        market: 'q',
        marketKey: 'yes-token',
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

class _State {
  const _State(this.name, {this.amount, this.funded = _none});
  final String name;
  final double? amount;
  final List<FundedOrderRecord> Function() funded;
}

List<FundedOrderRecord> _none() => const [];
List<FundedOrderRecord> _stop() => [_stopped()];

/// The slip on an iPhone SE (375 x 667, 20 pt status bar), in the app's
/// own ScreenUtil set-up, at text size [scale].
Future<void> _pump(WidgetTester tester, _State s, {double scale = 1.0}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(750, 1334);
  tester.view.padding = const FakeViewPadding(top: 40);
  tester.view.viewPadding = const FakeViewPadding(top: 40);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      polymarketTradingProvider.overrideWith(() => _Trading(100)),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      aiEnabledProvider.overrideWith((ref) async => false),
      currencyProvider.overrideWith((ref) => _Currency()),
      usdBalanceProvider.overrideWithValue(0),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
      fundedOrdersProvider.overrideWith(() => _Funded(s.funded())),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Builder(builder: (context) {
          final c = context.colors;
          return Scaffold(backgroundColor: c.background);
        }),
      ),
    ),
  ));
  await tester.pump();
  final ctx = tester.element(find.byType(Scaffold));
  showModalBottomSheet(
    context: ctx,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => BetSlipSheet(
        marketQuestion: 'Will the Fed cut rates at the December meeting?',
        outcomes: _outcomes,
        initialAmountUsd: s.amount),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The tile's figure: its largest text.
Finder _figure(Finder tile) {
  Element? best;
  var size = 0.0;
  for (final e
      in find.descendant(of: tile, matching: find.byType(Text)).evaluate()) {
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
          of: find.byType(BetSlipSheet), matching: find.byType(Scrollable))
      .first);
  final keypadTop = tester.getRect(find.byType(AmountKeypad)).top;
  final rect = tester.getRect(what);
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.5), reason: '$what');
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5),
      reason: '$what');
  expect(rect.bottom, lessThanOrEqualTo(keypadTop + 0.5), reason: '$what');
}

void _expectTilesWhole(WidgetTester tester) {
  for (final key in ['bet-slip-payout-tile', 'bet-slip-fee-tile']) {
    final tile = find.byKey(ValueKey(key));
    expect(tile, findsOneWidget);
    _expectWhole(tester, tile);
    _expectWhole(tester, _figure(tile));
  }
}

void main() {
  late RuntimeCapabilitiesService policy;
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
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    AffiliateService.debugSessionToken = 'test-session';
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
  });
  tearDown(() {
    PredictionsVenueFunder.debugRouteShare = null;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    policy.dispose();
  }

  for (final scale in [1.0, 1.3]) {
    group('iPhone SE, text at ${scale}x', () {
      testWidgets('nothing typed: the tiles whole above the keypad',
          (tester) async {
        expect(await policy.refresh(), isTrue);
        await _pump(tester, const _State('empty', funded: _none), scale: scale);
        expect(tester.takeException(), isNull);
        _expectTilesWhole(tester);
        await release(tester);
      });

      testWidgets('a stake typed: the tiles whole above the keypad',
          (tester) async {
        expect(await policy.refresh(), isTrue);
        await _pump(tester, const _State('typed', amount: 12, funded: _none),
            scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text(r'$12'), findsOneWidget);
        _expectTilesWhole(tester);
        await release(tester);
      });

      testWidgets(
          'a stopped bet: the notice, the amount and the tiles whole above '
          'the keypad', (tester) async {
        expect(await policy.refresh(), isTrue);
        await _pump(tester, const _State('stopped', amount: 12, funded: _stop),
            scale: scale);
        expect(tester.takeException(), isNull);
        final notice = find.byKey(const ValueKey('bet-slip-funded-stop'));
        expect(notice, findsOneWidget);
        _expectWhole(tester, notice);
        _expectWhole(tester, find.byType(BigAmountDisplay));
        _expectTilesWhole(tester);
        await release(tester);
      });
    });
  }
}
