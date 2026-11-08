// A look by eye at Swap, the two-way screen between the person's own
// Bitcoin and Dollars (founder, 7 November 2026: "on dollars we add a
// button that says move money and it basically allows for [both
// directions] but with a button in a reversible way. Also this screen make
// it with the squares"; renamed "Swap" the same day): the real sheet
// (showOwnMoneyMove) in both directions, From and To as two squares with
// the swap circle on their shared edge, the hero centred, the chips as
// wide as the keypad; and both homes' action rows with their Swap, the
// Bitcoin home's also on a cold wallet, which keeps Scan.
// Light and dark, at 320, 375 and 430 pt, at the default text size and a
// large one. And the result sheet Swap closes into, from over the Dollars
// home holding its own bar context (founder, 8 November 2026: "swapped
// should say ok, not with the search sal"): the bar is its Done. Every
// frame lays out without an overflow; the PNGs are written only when asked:
//
//   MOVE_RENDER=<dir> flutter test test/render/money_movement_render_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_model.dart'
    show OrchestraEstimate, OrchestraEstimateAsset;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdSdkBalanceProvider;
import 'package:kute/screens/home/components/move_sent_overlay.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteCompactActions;
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart'
    show bitcoinHomeDockActions;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart'
    show KuteConfirmation;
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/orchestra_fee_summary.dart'
    show orchestraFeeEstimateProvider;
import 'package:kute/screens/usd/usd_account_screen.dart'
    show UsdAccountActionRow;
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show venueCashLastReadProvider;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        VenueCashPuller,
        VenueCashSource,
        kVenuePullEta,
        venueCashPullerProvider;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueMoveResult;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../helpers/kute_bar_test_support.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../screens/share/cards/share_card_test_fonts.dart';

final _dir = Platform.environment['MOVE_RENDER'];

const _usdPerBtc = 100000.0;

MockClient _orchestra() => MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      final q = request.url.queryParameters;
      final asset = q['destinationAsset']!;
      final chain = q['destinationChain']!;
      final source = q['sourceAsset']!;
      final input = orchestraAmountToDouble(q['amount'] ?? '0', source,
          chain: q['sourceChain']!);
      final usd = source == 'BTC' ? input * _usdPerBtc : input;
      final out = doubleToOrchestraAmount(
          asset == 'BTC' ? usd / _usdPerBtc : usd, asset,
          chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({
          'USD': Fixed.fromInt(_usdPerBtc.round()),
          'BTC': Fixed.fromNum(1 / _usdPerBtc, decimalDigits: 16),
        }));

  @override
  Future<void> updateRates() async {}
}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => const PolymarketTradingState(
      walletAddress: '0xeoa',
      proxyWalletAddress: '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      usdcBalance: 40);
}

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
      accountValue: 60,
      withdrawable: 60,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const []);
}

/// A venue holding [cash], as the engine reads it; never pulled here.
class _VenueCash implements VenueCashSource {
  _VenueCash(this.venue, this.cash);

  @override
  final OneBalanceVenue venue;
  final double cash;

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => cash;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) =>
      Completer<VenueMoveResult>().future;
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final error = tester.takeException();
  expect(error, isNull, reason: '$name overflowed: $error');
  final dir = _dir;
  if (dir == null) return;
  // The cards' soft shadows drawn as on a phone for the shot (a test
  // draws them unblurred), then flat again.
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image =
        await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

final _nav = GlobalKey<NavigatorState>();

Future<ProviderContainer> _pump(WidgetTester tester, Widget home,
    {required double width,
    required bool dark,
    double scale = 1,
    double? height,
    Locale? locale}) async {
  await tester.runAsync(loadShareCardFonts);
  AffiliateService.debugSessionToken = 'test-session';
  final policy = runtimePolicyFixture();
  RuntimeCapabilitiesService.debugInstance = policy;
  await tester.runAsync(policy.refresh);
  tester.view.physicalSize =
      Size(width, height ?? (width >= 430 ? 932 : 812));
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final base = dark ? buildDarkTheme() : buildLightTheme();
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => _Settings()),
    currencyProvider.overrideWith((_) => _Currency()),
    polymarketTradingProvider.overrideWith(_Trading.new),
    polymarketBalanceProvider.overrideWith((_) => 40),
    hyperliquidAccountProvider.overrideWith(_Account.new),
    hyperliquidAddressProvider.overrideWith(
        (_) => Future.value('0x1111111111111111111111111111111111111111')),
    sparkBitcoinBalanceProvider.overrideWith((ref) async => BigInt.from(ref
            .watch(walletBalanceCacheProvider)['spending']
            ?.sparkBitcoinbalance ??
        0)),
    breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
    usdBalanceProvider.overrideWith((_) => 150.25),
    usdSdkBalanceProvider.overrideWith((_) => Stream.value(150.25)),
    sparkSelfAddressProvider.overrideWith((_) async =>
        'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9'),
    dollarsToBitcoinMinimumProvider
        .overrideWith((_) => DollarsToBitcoinMinimum(fetch: (_) async => null)),
    // A fee to show on the line under the figure: $0.12 short of the
    // amount at the sample price.
    orchestraFeeEstimateProvider.overrideWith((ref, key) async {
      final r = key.route;
      final input =
          orchestraAmountToDouble(r.amount, r.fromAsset, chain: r.fromChain);
      final usd = (r.fromAsset == 'BTC' ? input * _usdPerBtc : input) - 0.12;
      final decimals = r.toAsset == 'BTC' ? 8 : 6;
      return OrchestraEstimate(
          estimatedOut: doubleToOrchestraAmount(
              r.toAsset == 'BTC' ? usd / _usdPerBtc : usd, r.toAsset,
              chain: r.toChain),
          feeAmount: '0',
          feeBps: 0,
          route: const [],
          kuteAppFeeBps: 0,
          totalFeeAmountUsd: '0.12',
          destination: OrchestraEstimateAsset(
              chain: r.toChain, asset: r.toAsset, decimals: decimals));
    }),
    // Predictions and Investing cash in reach of "From your Dollars".
    venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          walletId: () => 'spending',
          sources: [
            _VenueCash(OneBalanceVenue.predictions, 40),
            _VenueCash(OneBalanceVenue.investing, 60),
          ],
          readDollars: () => 150.25,
          minimumUsd: (venue) async =>
              venue == OneBalanceVenue.investing ? 5 : 1,
        )),
    venueCashLastReadProvider.overrideWith((_) => (
          walletId: 'spending',
          candidates: [
            (
              venue: OneBalanceVenue.predictions,
              availableUsd: 40.0,
              eta: kVenuePullEta[OneBalanceVenue.predictions]!,
              minimumUsd: 1.0,
            ),
            (
              venue: OneBalanceVenue.investing,
              availableUsd: 60.0,
              eta: kVenuePullEta[OneBalanceVenue.investing]!,
              minimumUsd: 5.0,
            ),
          ],
        )),
  ]);
  // 273,440 sats: $273.44 at the sample price.
  container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
      WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 273440));
  SharedHttpClient.debugOverride = _orchestra();
  addTearDown(() => SharedHttpClient.debugOverride = null);
  await http.runWithClient(
    () => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: withKuteShellBar,
          navigatorKey: _nav,
          navigatorObservers: [KuteBarRouteObserver()],
          locale: locale,
          theme: base.copyWith(
              splashFactory: NoSplash.splashFactory,
              textTheme: base.textTheme.apply(fontFamily: 'Inter')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    )),
    _orchestra,
  );
  await _frames(tester);
  return container;
}

/// Unmounts the page and lets the policy's refresh timers run out.
Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    KuteBarRouteObserver.reset();
  });

  // The result sheet, as Swap closes into it over the Dollars home (a tab's
  // navigator nested in the root's, holding the Investing pill's context
  // while its tickers run): Swap popped and the sheet pushed in one tick.
  for (final dark in [false, true]) {
    for (final (from, name, to) in [
      (MoneyMovementAccount.bitcoin, 'Bitcoin', 'Dollars'),
      (MoneyMovementAccount.dollars, 'Dollars', 'Bitcoin'),
    ]) {
      final shot = 'swapped_to_${to.toLowerCase()}_375_'
          '${dark ? 'dark' : 'light'}';
      testWidgets(shot, (tester) async {
        KuteConfirmation.debugFeedbackOverride = () async {};
        addTearDown(() => KuteConfirmation.debugFeedbackOverride = null);
        // Sal's face on the bar, for the shot.
        if (_dir != null) {
          await tester.runAsync(() async {
            SalSpriteCache.debugSetManifest(jsonDecode(await rootBundle
                .loadString('$kSalSpriteDir/manifest.json')) as Map<String, dynamic>);
            // The density the sprite picks for this harness's view (1 px).
            for (final density in [1, 2, 3]) {
              await SalSpriteCache.clip('happy', density);
            }
          });
        }
        final c = await _pump(
            tester,
            Navigator(
              observers: [KuteBarRouteObserver()],
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (context, _, __) => KuteBarContextScope(
                  active: TickerMode.valuesOf(context).enabled,
                  barContext: KuteBarContext(
                      label: context.l10n.searchInvestmentsOrManageAi),
                  child: const Scaffold(body: SizedBox()),
                ),
              ),
            ),
            width: 375,
            dark: dark);
        unawaited(showOwnMoneyMove(_nav.currentContext!,
            from: from, entrySource: 'usd_home_swap'));
        await _frames(tester, 16);
        final navigator = _nav.currentState!;
        final l10n = navigator.context.l10n;
        navigator.pop();
        pushMoveSentOverlay(
          navigator: navigator,
          amount: r'$4.99',
          fromWalletName: name,
          toWalletName: to,
          note: l10n.settlementRegistering,
          swapped: true,
        );
        await _frames(tester, 24);
        expect(find.text(l10n.done), findsOneWidget);
        expect(find.text(l10n.searchInvestmentsOrManageAi), findsNothing);
        await _capture(tester, shot);
        await _close(tester, c);
      });
    }
  }

  // A short phone too (375 × 667): the screen scrolls rather than cut.
  for (final dark in [false, true]) {
    for (final from in [
      MoneyMovementAccount.bitcoin,
      MoneyMovementAccount.dollars,
    ]) {
      final name = 'swap_${from.name}_to_'
          '${from == MoneyMovementAccount.bitcoin ? 'dollars' : 'bitcoin'}'
          '_375x667_${dark ? 'dark' : 'light'}';
      testWidgets(name, (tester) async {
        final c = await _pump(tester, const Scaffold(body: SizedBox()),
            width: 375, height: 667, dark: dark);
        unawaited(showOwnMoneyMove(_nav.currentContext!,
            from: from, entrySource: 'usd_home_swap'));
        await _frames(tester, 16);
        for (final key in ['2', '5']) {
          await tester.tap(find.text(key).last);
          await tester.pump();
        }
        await _frames(tester, 12);
        await _capture(tester, name);
        await _close(tester, c);
      });
    }
  }

  for (final width in [320.0, 375.0, 430.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        for (final from in [
          MoneyMovementAccount.bitcoin,
          MoneyMovementAccount.dollars,
        ]) {
          final mode = dark ? 'dark' : 'light';
          final text = scale > 1 ? '_large' : '';
          final name = 'swap_${from.name}_to_'
              '${from == MoneyMovementAccount.bitcoin ? 'dollars' : 'bitcoin'}'
              '_${width.round()}_$mode$text';
          testWidgets(name, (tester) async {
            final c = await _pump(tester, const Scaffold(body: SizedBox()),
                width: width, dark: dark, scale: scale);
            unawaited(showOwnMoneyMove(_nav.currentContext!,
                from: from, entrySource: 'usd_home_swap'));
            await _frames(tester, 16);
            // An amount typed: the hero, the fee line and the bar's verb.
            for (final key in ['2', '5']) {
              await tester.tap(find.text(key).last);
              await tester.pump();
            }
            await _frames(tester, 12);
            await _capture(tester, name);
            await _close(tester, c);
          });
        }
      }
    }
  }

  // The Bitcoin home's row, in the same columns: the spending wallet's Swap
  // in English and in the languages whose Swap is the longest, and a cold
  // wallet's Scan.
  final spendingWallet = WalletConfig(id: 'spending', name: 'Spending');
  final coldWallet = WalletConfig(id: 'cold', name: 'Cold', isHardware: true);
  for (final (width, dark, lang, wallet) in [
    (320.0, false, 'en', spendingWallet),
    (320.0, true, 'en', spendingWallet),
    (375.0, false, 'en', spendingWallet),
    (375.0, true, 'en', spendingWallet),
    (320.0, false, 'es', spendingWallet),
    (320.0, false, 'el', spendingWallet),
    (320.0, false, 'en', coldWallet),
    (320.0, true, 'en', coldWallet),
    (375.0, false, 'en', coldWallet),
    (375.0, true, 'en', coldWallet),
  ]) {
    final mode = dark ? 'dark' : 'light';
    final name = 'bitcoin_home_actions_'
        '${wallet.isSparkWallet ? '' : 'cold_'}${width.round()}_$mode'
        '${lang == 'en' ? '' : '_$lang'}';
    testWidgets(name, (tester) async {
      // The row as Home lays it out under the balance.
      final c = await _pump(
          tester,
          Consumer(
            builder: (context, ref, _) => Scaffold(
              backgroundColor: context.colors.background,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: KuteCompactActions(
                      source: 'home',
                      actions: bitcoinHomeDockActions(context, ref, wallet,
                          source: 'home')),
                ),
              ),
            ),
          ),
          width: width,
          dark: dark,
          locale: Locale(lang));
      tester.view.physicalSize = Size(width, 160);
      await _frames(tester, 4);
      await _capture(tester, name);
      await _close(tester, c);
    });
  }

  // And its Swap, tapped for real: the Swap screen, on Bitcoin → Dollars.
  for (final dark in [false, true]) {
    final name = 'bitcoin_home_swap_opened_375_${dark ? 'dark' : 'light'}';
    testWidgets(name, (tester) async {
      final c = await _pump(
          tester,
          Consumer(
            builder: (context, ref, _) => Scaffold(
              body: SafeArea(
                child: KuteCompactActions(
                    source: 'home',
                    actions: bitcoinHomeDockActions(
                        context, ref, spendingWallet,
                        source: 'home')),
              ),
            ),
          ),
          width: 375,
          dark: dark);
      await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
      await _frames(tester, 16);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('money-movement-from')),
              matching: find.text('Bitcoin')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('money-movement-to')),
              matching: find.text('Dollars')),
          findsOneWidget);
      await _capture(tester, name);
      await _close(tester, c);
    });
  }

  // The row in English, and in Spanish and Greek, whose Swap and Buy
  // dollars are the longest.
  for (final (width, dark, lang) in [
    (320.0, false, 'en'),
    (320.0, true, 'en'),
    (375.0, false, 'en'),
    (375.0, true, 'en'),
    (320.0, false, 'es'),
    (320.0, false, 'el'),
  ]) {
    {
      final mode = dark ? 'dark' : 'light';
      final name = 'dollars_home_actions_${width.round()}_$mode'
          '${lang == 'en' ? '' : '_$lang'}';
      testWidgets(name, (tester) async {
        // The row as the Dollars home lays it out under the balance.
        final c = await _pump(
            tester,
            Builder(
              builder: (context) => Scaffold(
                backgroundColor: context.colors.background,
                body: const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: UsdAccountActionRow(),
                  ),
                ),
              ),
            ),
            width: width,
            dark: dark,
            locale: Locale(lang));
        tester.view.physicalSize = Size(width, 160);
        await _frames(tester, 4);
        await _capture(tester, name);
        await _close(tester, c);
      });
    }
  }
}
