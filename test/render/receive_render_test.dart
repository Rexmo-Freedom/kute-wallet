// A look by eye at the Receive work (founder, 6 and 7 November 2026),
// light and dark, written only when asked: RECEIVE_RENDER=<dir>.
// "rows": the Bitcoin and Dollars action rows at 375 pt, the moving
// Receive arrow at rest beside the other icons, and large; "bitcoin": the
// Bitcoin receive's first sheet (two squares, Bitcoin and Another crypto)
// at 375 pt, at 430 pt and in the longer languages;
// "dollars": the Dollars receive's first sheet (two squares, Dollars and
// Another crypto) at 375 pt, at 430 pt and in the longer languages, and
// the coin sheet its "Dollars" opens; "qr": the Bitcoin QR receive in every
// state its bar has (bitcoin_receive_harness.dart), and the sheets over it,
// at 375 x 812 and 320 x 568 and at 375 in a long language, under the real
// shell bar; "standing": the reusable address's sheet in every state. The
// cards' soft shadows are drawn as on a phone (a test draws them
// unblurred, a hard grey band under every card). One render per run, so:
//   for v in 'rows light' 'rows dark' 'bitcoin light' 'bitcoin dark' \
//       'dollars light' 'dollars dark' 'qr light' 'qr dark' \
//       'standing light' 'standing dark'; do
//     RECEIVE_RENDER=<dir> flutter test \
//       test/render/receive_render_test.dart --plain-name "$v"; done

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show
        BreezSdk,
        ReceivePaymentMethod,
        ReceivePaymentRequest,
        ReceivePaymentResponse;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
import 'package:kute/screens/shared/receive_arrow_glyph.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show UsdAccountActionBar;
import 'package:kute/screens/shared/app_bottom_sheet.dart'
    show showAppBottomSheet;
import 'package:kute/screens/usd/usd_receive_screen.dart'
    show kUsdReceiveDollarsKey, UsdStandingAddressSheet;
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show
        DepositAddressModel,
        ReusableDepositAddress,
        ReusableDepositAddressService,
        StandingFallbackReason,
        standingDestinationsProvider;
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show StandingDepositStore;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:money2/money2.dart';

import '../helpers/bitcoin_receive_harness.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../helpers/shell_bar_harness.dart' show shellBarBuilder;

final _dir = Platform.environment['RECEIVE_RENDER'];

/// The languages whose Receive squares are worth a look at 375 pt.
const _longLanguages = ['de', 'fi', 'lt', 'ja'];

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

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

final _spending = WalletConfig(id: 'spending', name: 'Spending');

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

const _baseUsdc = OrchestraReceiveOption(
  assetCode: 'USDC',
  displayName: 'USD Coin',
  displaySymbol: 'USDC',
  chain: 'base',
  chainDisplayName: 'Base',
  decimals: 6,
);

const _standingAddress = '0x1111111111111111111111111111111111111111';

/// The reusable address's sheet, under the bar. [resolve] answers its
/// registration.
Future<void> _openStanding(
  WidgetTester tester, {
  required bool dark,
  required Size size,
  StandingFallbackReason? unavailable,
  Locale? locale,
  required Future<ReusableDepositAddress> Function() resolve,
}) async {
  tester.view.padding = size.height >= 800
      ? const FakeViewPadding(top: 47, bottom: 34)
      : const FakeViewPadding(top: 20);
  ReusableDepositAddressService.debugResolver = (
          {required sourceChain,
          required sourceAsset,
          required destinationAsset}) =>
      resolve();
  final sdk = _Sdk();
  when(() => sdk.receivePayment(request: any(named: 'request'))).thenAnswer(
      (_) async => ReceivePaymentResponse(
          paymentRequest: 'sp1pgssy7d7vel0nh9m4', fee: BigInt.zero));
  final wrapper = _Wrapper();
  when(() => wrapper.instance).thenReturn(sdk);
  await _app(
    tester,
    dark,
    size,
    _opener((context) => showAppBottomSheet<void>(
          context: context,
          builder: (_) => UsdStandingAddressSheet(
            option: _baseUsdc,
            destinationAsset: 'USDB',
            unavailable: unavailable,
          ),
        )),
    locale: locale,
    bar: true,
    breez: wrapper,
  );
  await _openSheet(tester);
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _shoot(WidgetTester tester, String name) async {
  // The soft shadows as on a phone for the shot, then flat again.
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

Future<void> _app(WidgetTester tester, bool dark, Size size, Widget home,
    {Locale? locale, bool bar = false, BreezSdkSpark? breez}) async {
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
            wallets: [_spending],
          ))),
      selectedAccountProvider.overrideWithValue(BtcSpendingAccount(_spending)),
      swapOffersEnabledProvider.overrideWithValue(true),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(
            OrchestraRoutesCatalog.fromJson(
              {
                'assets': [
                  _row('spark', 'BTC', decimals: 8),
                  _row('spark', 'USDB'),
                  _row('base', 'USDC'),
                  _row('ethereum', 'USDT'),
                  _row('ethereum', 'ETH', decimals: 18),
                  _row('solana', 'SOL', decimals: 9),
                  _row('tron', 'USDT'),
                ],
              },
              source: OrchestraCatalogSource.live,
              fetchedAt: DateTime.now(),
            ),
          )),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      standingDestinationsProvider.overrideWith((_) async => {'spark:USDB'}),
      receiveMinimumsProvider
          .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
      usdBalanceProvider.overrideWithValue(4.75),
      usdBalanceUnknownProvider.overrideWithValue(false),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            'spending': WalletBalance(
                onChainBtcBalance: 0, sparkBitcoinbalance: 123456),
          })),
      breezSDKProvider.overrideWith((_) =>
          breez != null ? Future.value(breez) : Completer<BreezSdkSpark>().future),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(dark),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => RepaintBoundary(
            key: const ValueKey('shot'),
            child: bar ? shellBarBuilder(context, child) : child),
        home: home,
      ),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(text,
          style: TextStyle(
              color: context.colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _opener(Future<void> Function(BuildContext) open) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
              onPressed: () => open(context), child: const Text('open')),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    if (_dir == null) return;
    Hive.init((await Directory.systemTemp.createTemp('receive_render_')).path);
    await Hive.openBox<String>(StandingDepositStore.boxName,
        bytes: Uint8List(0));
    registerFallbackValue(const ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.sparkAddress()));
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    await policy.refresh();
    TrackingService.debugTrackObserver = (_, __) {};
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('render: qr $mode', skip: _dir == null, (tester) async {
      await loadReceiveFonts(tester);
      Future<void> settled(String name) async {
        await tester.pump(const Duration(milliseconds: 400));
        await _shoot(tester, name);
        expect(tester.takeException(), isNull, reason: name);
      }

      for (final (w, h) in [(375.0, 812.0), (320.0, 568.0)]) {
        final size = Size(w, h);
        for (final state in receiveStates) {
          await openBitcoinReceive(tester, state.world(),
              dark: dark, size: size);
          await state.after?.call(tester);
          await settled('qr_${state.name}_${w.toInt()}_$mode');
          if (w == 320) {
            // The page scrolled to its end.
            final scroll = find.byType(Scrollable);
            if (scroll.evaluate().isNotEmpty) {
              final pos = tester.state<ScrollableState>(scroll.first).position;
              if (pos.maxScrollExtent > 0) {
                pos.jumpTo(pos.maxScrollExtent);
                await settled('qr_${state.name}_320_scrolled_$mode');
              }
            }
          }
          await closeBitcoinReceive(tester, reopen: true);
        }
        // The sheets over it keep their own bars.
        await openBitcoinReceive(tester, ReceiveWorld(),
            dark: dark, size: size);
        await tester.tap(find.byIcon(Icons.edit_rounded));
        await settleReceive(tester);
        await settled('qr_over_edit_${w.toInt()}_$mode');
        await closeBitcoinReceive(tester, reopen: true);
        await openBitcoinReceive(tester, ReceiveWorld(),
            dark: dark, size: size);
        await tester.tap(find.byKey(const ValueKey('receive-request-amount')));
        await settleReceive(tester);
        await settled('qr_over_request_${w.toInt()}_$mode');
        await closeBitcoinReceive(tester, reopen: true);
      }
      // A long language at 375.
      for (final lang in ['de', 'fi']) {
        for (final state in receiveStates.where((s) =>
            s.name == 'unified' ||
            s.name == 'amount_invoice' ||
            s.name == 'address_failed' ||
            s.name == 'ledger' ||
            s.name == 'signer')) {
          await openBitcoinReceive(tester, state.world(),
              dark: dark, locale: Locale(lang));
          await state.after?.call(tester);
          await settled('qr_${state.name}_375_${lang}_$mode');
          await closeBitcoinReceive(tester, reopen: true);
        }
      }
      RuntimeCapabilitiesService.instance.dispose();
    });

    testWidgets('render: standing $mode', skip: _dir == null, (tester) async {
      await loadReceiveFonts(tester);
      addTearDown(() => ReusableDepositAddressService.debugResolver = null);
      const shown = ReusableDepositAddress(
          address: _standingAddress,
          id: 'sda_render',
          kuteFeeBps: 50,
          model: DepositAddressModel.standing);
      for (final (w, h, locale) in [
        (375.0, 812.0, null),
        (320.0, 568.0, null),
        (375.0, 812.0, const Locale('de')),
      ]) {
        final tag = locale == null
            ? '${w.toInt()}_$mode'
            : '${w.toInt()}_${locale.languageCode}_$mode';
        for (final (name, unavailable, resolve)
            in <(String, StandingFallbackReason?,
                Future<ReusableDepositAddress> Function())>[
          ('shown', null, () async => shown),
          ('creating', null, () => Completer<ReusableDepositAddress>().future),
          ('failed', null, () async => throw StateError('the rail is down')),
          ('unavailable', StandingFallbackReason.standingPolicyOff,
              () async => shown),
        ]) {
          await _openStanding(tester,
              dark: dark,
              size: Size(w, h),
              unavailable: unavailable,
              locale: locale,
              resolve: resolve);
          await tester.pump(const Duration(milliseconds: 400));
          await _shoot(tester, 'standing_${name}_$tag');
          expect(tester.takeException(), isNull, reason: name);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        }
      }
      RuntimeCapabilitiesService.instance.dispose();
    });

    testWidgets('render: rows $mode', skip: _dir == null, (tester) async {
      await _fonts(tester);
      await _app(
        tester,
        dark,
        const Size(375, 640),
        Scaffold(
          body: Consumer(builder: (context, ref, _) {
            final c = context.colors;
            return ListView(children: [
              _label(context, 'Bitcoin home row'),
              KuteCompactActions(
                  source: 'home',
                  actions: bitcoinHomeDockActions(context, ref, _spending,
                      source: 'home')),
              _label(context, 'Dollars home row'),
              KuteCompactActions(
                  source: 'usd',
                  actions: UsdAccountActionBar.moneyActions(context)),
              _label(context, 'The Receive glyph at rest beside the icons'),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ReceiveArrowGlyph(color: c.textPrimary, size: 22),
                const SizedBox(width: 24),
                Icon(Icons.north_east_rounded, size: 22, color: c.textPrimary),
                const SizedBox(width: 24),
                Icon(Icons.qr_code_scanner_rounded,
                    size: 22, color: c.textPrimary),
              ]),
              _label(context, 'Large'),
              Center(
                child: Container(
                    color: c.textPrimary.withValues(alpha: 0.05),
                    child: ReceiveArrowGlyph(color: c.textPrimary, size: 140)),
              ),
            ]);
          }),
        ),
      );
      await _shoot(tester, 'rows_$mode');
      expect(tester.takeException(), isNull);
    });

    testWidgets('render: bitcoin $mode', skip: _dir == null, (tester) async {
      await _fonts(tester);
      for (final (w, h) in [(375.0, 812.0), (430.0, 932.0)]) {
        await _app(
            tester, dark, Size(w, h), _opener(showBitcoinReceiveSheet));
        await _openSheet(tester);
        await _shoot(tester, 'bitcoin_options_${w.toInt()}_$mode');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
      // Longer languages at 375 pt (Lithuanian's title takes two lines; the
      // test's Inter draws no Japanese, so ja shows widths, not its glyphs).
      for (final lang in _longLanguages) {
        await _app(tester, dark, const Size(375, 812),
            _opener(showBitcoinReceiveSheet),
            locale: Locale(lang));
        await _openSheet(tester);
        await _shoot(tester, 'bitcoin_options_375_${lang}_$mode');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('render: dollars $mode', skip: _dir == null, (tester) async {
      await _fonts(tester);
      for (final (w, h) in [(375.0, 812.0), (430.0, 932.0)]) {
        await _app(tester, dark, Size(w, h), _opener(showUsdReceiveSheet));
        await _openSheet(tester);
        await _shoot(tester, 'dollars_receive_${w.toInt()}_$mode');
        expect(tester.takeException(), isNull);
        if (w == 375) {
          // "Dollars" opens the coin sheet with the dollar coins alone.
          await tester.tap(find.byKey(kUsdReceiveDollarsKey));
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump(const Duration(milliseconds: 100));
          }
          await _shoot(tester, 'dollars_receive_coins_375_$mode');
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
      // Longer languages at 375 pt.
      for (final lang in _longLanguages) {
        await _app(
            tester, dark, const Size(375, 812), _opener(showUsdReceiveSheet),
            locale: Locale(lang));
        await _openSheet(tester);
        await _shoot(tester, 'dollars_receive_375_${lang}_$mode');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
    });
  }
}
