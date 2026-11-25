// The one-time receive's address sheet in every state it has (founder, 8
// November 2026: "the text is too dense, use the cards, and the share
// button should be the sal on the bottom"), under the real shell bar and
// with a phone's real insets: QuotedReceiveSheet at 375 x 812 and 320 x 568,
// light and dark, and at 375 in a long language.
//
// The two tests at the top always run: on a 375 x 812 phone everything
// stands above the bar without a scroll, and no state leaves the bar on the
// default search. The looks are written only when asked, RECEIVE_RENDER=<dir>:
//   RECEIVE_RENDER=<dir> flutter test test/render/quoted_receive_render_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:money2/money2.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/runtime_policy_fixture.dart';

final _dir = Platform.environment['RECEIVE_RENDER'];
final _l10n = AppLocalizationsEn();

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _deposit = '0xd473045065fe1a2b3c4d5e6f708192a3b1957cd4';
const _refund = '0x2222222222222222222222222222222222222222';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

class _Settings extends SettingsModel {
  _Settings(super.state);

  void switchTo(String walletId) =>
      state = state.copyWith(activeWalletId: walletId);
}

class _Balances extends WalletBalanceCacheNotifier {
  _Balances() {
    state = const {};
  }
}

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

const _usdtOnBase = OrchestraReceiveOption(
  assetCode: 'USDT',
  displayName: 'Tether',
  displaySymbol: 'USDT',
  chain: 'base',
  chainDisplayName: 'Base',
  decimals: 6,
);

_Wrapper _wrapper() {
  final sdk = _Sdk();
  when(() => sdk.receivePayment(request: any(named: 'request'))).thenAnswer(
      (_) async =>
          ReceivePaymentResponse(paymentRequest: _spark, fee: BigInt.zero));
  final wrapper = _Wrapper();
  when(() => wrapper.instance).thenReturn(sdk);
  return wrapper;
}

/// A quote for [request], paid for [life] from now.
VerifiedOrchestraQuote _quote(OrchestraQuoteRequest request, Duration life) {
  final now = DateTime.now();
  return verifyOrchestraQuote(
    request,
    OrchestraQuote.fromJson({
      'quoteId': 'q_onetime_1',
      'depositAddress': _deposit,
      'amountIn': request.amountBaseUnits.toString(),
      'estimatedOut': '7000',
      'feeAmount': '0',
      'feeBps': 10,
      'appFees': [
        {'feeBps': 50}
      ],
      'route': <String>[],
      'expiresAt': now.add(life).toUtc().toIso8601String(),
    }),
    now: now,
    bounds: const OrchestraQuoteBounds(
      maxFeeBps: OrchestraQuoteBounds.defaultMaxFeeBps,
      minOutRatio: OrchestraQuoteBounds.defaultMinOutRatio,
      inputValueInOutputUnits: null,
      expiryMargin: Duration(seconds: 1),
    ),
    mainnet: true,
  );
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      // The address's 'monospace' has no font in a test: bars, not letters.
      final mono = FontLoader('monospace')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
      await mono.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets the sheet's SVG logos decode, then the frame after them.
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await _settle(tester);
}

late _Settings _settings;
void Function(SwapOrder)? _progress;
SwapOrder? _row0;

Future<void> _open(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(375, 812),
  EdgeInsets? insets,
  Locale? locale,
  OrchestraReceiveOption option = _usdtOnBase,
  String? refund,
  String destination = 'BTC',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final inset = insets ??
      (size.height >= 800
          ? const EdgeInsets.only(top: 47, bottom: 34)
          : const EdgeInsets.only(top: 20));
  tester.view.padding = FakeViewPadding(top: inset.top, bottom: inset.bottom);
  addTearDown(tester.view.reset);
  final base = dark ? buildDarkTheme() : buildLightTheme();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => _settings = _Settings(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [
              WalletConfig(id: 'spending', name: 'Spending'),
              WalletConfig(id: 'other', name: 'Other'),
            ],
          ))),
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(
            OrchestraRoutesCatalog.fromJson(
              {
                'assets': [
                  _row('spark', 'BTC', decimals: 8),
                  _row('spark', 'USDB'),
                  _row('base', 'USDT'),
                ],
              },
              source: OrchestraCatalogSource.live,
              fetchedAt: DateTime.now(),
            ),
          )),
      orchestraRoutesReadyProvider.overrideWith((_) async {}),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances()),
      breezSDKProvider.overrideWith((_) async => _wrapper()),
      sparkSelfAddressProvider.overrideWith((_) async => _spark),
      receiveMinimumsProvider
          .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          splashFactory: NoSplash.splashFactory,
          textTheme: base.textTheme.apply(fontFamily: 'Inter'),
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => RepaintBoundary(
            key: const ValueKey('shot'), child: withKuteShellBar(context, child)),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  builder: (_) => QuotedReceiveSheet(
                    option: option,
                    destinationAsset: destination,
                    amount: (
                      usdCents: 422,
                      minimum: kReceiveMinimumNone,
                      unit: 'USD',
                    ),
                    refundAddress: refund,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await _settle(tester);
  await _settleImages(tester);
}

Future<void> _shoot(WidgetTester tester, String name) async {
  if (_dir == null) return;
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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// The deposit reached [status], as the poller reports it.
Future<void> _arrive(WidgetTester tester, String status) async {
  _progress!(_row0!.copyWith(id: 'ord_1', status: status));
  await _settle(tester);
}

typedef _State = ({
  String name,
  String bar,
  bool busy,
  void Function()? before,
  Future<void> Function(WidgetTester)? after,
  OrchestraReceiveOption option,
  String? refund,
});

_State _s(String name, String bar,
        {bool busy = false,
        void Function()? before,
        Future<void> Function(WidgetTester)? after,
        OrchestraReceiveOption option = _usdtOnBase,
        String? refund}) =>
    (
      name: name,
      bar: bar,
      busy: busy,
      before: before,
      after: after,
      option: option,
      refund: refund
    );

final _unsupported = const OrchestraReceiveOption(
  assetCode: 'USDT',
  displayName: 'Tether',
  displaySymbol: 'USDT',
  chain: 'base',
  chainDisplayName: 'Base',
  decimals: 30,
);

final List<_State> _states = [
  _s('creating', _l10n.share, busy: true, before: () {
    OneTimeReceive.debugFetch = (_) => Completer<VerifiedOrchestraQuote>().future;
  }),
  _s('error', _l10n.tryAgain, before: () {
    OneTimeReceive.debugFetch = (_) async =>
        throw const WalletGuardException(WalletGuardReason.noReferencePrice);
  }),
  _s('payable', _l10n.share),
  _s('payable_refund', _l10n.share, refund: _refund),
  _s('expired', _l10n.receiveOneOffNewAddress, before: () {
    OneTimeReceive.debugFetch =
        (r) async => _quote(r, const Duration(seconds: 5));
  }),
  _s('processing', _l10n.done, after: (t) => _arrive(t, 'exchanging')),
  _s('completed', _l10n.receiveOneOffNewAddress,
      after: (t) => _arrive(t, 'success')),
  _s('refunded', _l10n.receiveOneOffNewAddress,
      after: (t) => _arrive(t, 'refunded'), refund: _refund),
  _s('failed', _l10n.done, after: (t) => _arrive(t, 'failed')),
  _s('wallet_changed', _l10n.done, after: (t) async {
    _settings.switchTo('other');
    await _settle(t);
  }),
  _s('unsupported', _l10n.done, option: _unsupported),
];

void main() {
  setUpAll(() {
    registerFallbackValue(const ReceivePaymentRequest(
        paymentMethod: ReceivePaymentMethod.sparkAddress()));
  });

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    await policy.refresh();
    TrackingService.debugTrackObserver = (_, __) {};
    OneTimeReceive.debugFetch =
        (r) async => _quote(r, const Duration(minutes: 2));
    OneTimeReceive.debugRecord = (row, _, __) async => _row0 = row;
    OneTimeReceive.debugWatch = (onProgress) => _progress = onProgress;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
    OneTimeReceive.debugFetch = null;
    OneTimeReceive.debugRecord = null;
    OneTimeReceive.debugWatch = null;
    _progress = null;
    _row0 = null;
  });

  testWidgets('on a 375 x 812 phone it all stands above the bar, unscrolled',
      (tester) async {
    await _fonts(tester);
    for (final (refund, lang) in [
      (null, 'en'),
      (_refund, 'en'),
      (null, 'de'),
      (_refund, 'de'),
      (_refund, 'fi'),
    ]) {
      await _open(tester, refund: refund, locale: Locale(lang));
      final barTop = tester.getTopLeft(kuteBarPrimary).dy;
      final last = refund == null
          ? find.byKey(const ValueKey('onetime-receive-network-warning'))
          : find.byKey(const ValueKey('onetime-receive-returns-to'));
      expect(tester.getBottomLeft(last).dy, lessThan(barTop),
          reason: 'nothing under the bar');
      final scroll = tester.state<ScrollableState>(find.descendant(
          of: find.byType(QuotedReceiveSheet),
          matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, 0, reason: 'nothing to scroll');
      final plate = tester.getSize(find.byType(ReceiveQrPlate));
      expect(plate.width, greaterThanOrEqualTo(kReceiveQrMinSide));
      await _unmount(tester);
    }
    RuntimeCapabilitiesService.instance.dispose();
  });

  for (final state in _states) {
    testWidgets('the bar is the sheet\'s own: ${state.name}', (tester) async {
      await _fonts(tester);
      state.before?.call();
      await _open(tester, option: state.option, refund: state.refund);
      await state.after?.call(tester);
      final bar = kuteBarPrimaryContext(tester);
      expect(bar.primaryLabel, state.bar);
      expect(kuteBarPrimaryWithText(state.bar), findsOneWidget);
      expect(bar.busy, state.busy);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
      RuntimeCapabilitiesService.instance.dispose();
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final (w, h) in [(375.0, 812.0), (320.0, 568.0)]) {
      testWidgets('render: ${w.toInt()} $mode', skip: _dir == null,
          (tester) async {
        await _fonts(tester);
        for (final state in _states) {
          OneTimeReceive.debugFetch =
              (r) async => _quote(r, const Duration(minutes: 2));
          state.before?.call();
          await _open(tester,
              dark: dark,
              size: Size(w, h),
              option: state.option,
              refund: state.refund);
          await state.after?.call(tester);
          await _shoot(tester, '${state.name}_${w.toInt()}_$mode');
          expect(tester.takeException(), isNull, reason: state.name);
          await _unmount(tester);
        }
        RuntimeCapabilitiesService.instance.dispose();
      });
    }
    testWidgets('render: long languages $mode', skip: _dir == null,
        (tester) async {
      await _fonts(tester);
      for (final lang in ['de', 'fi', 'ja']) {
        for (final state in [_states[3], _states[4], _states[5]]) {
          OneTimeReceive.debugFetch =
              (r) async => _quote(r, const Duration(minutes: 2));
          state.before?.call();
          await _open(tester,
              dark: dark,
              locale: Locale(lang),
              option: state.option,
              refund: state.refund);
          await state.after?.call(tester);
          await _shoot(tester, '${state.name}_375_${lang}_$mode');
          expect(tester.takeException(), isNull, reason: state.name);
          await _unmount(tester);
        }
      }
      RuntimeCapabilitiesService.instance.dispose();
    });
  }
}
