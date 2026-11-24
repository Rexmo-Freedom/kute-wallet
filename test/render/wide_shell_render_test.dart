// A look by eye at the shell on wide windows (kute_layout.dart): the
// Bitcoin home (its panes), the top nav, the floating Sal bar, a sheet, a
// pushed form (the PIN pad) and a toast, at 1440x900, 1180x820, 820x1180
// and 430x932, light and dark, written only when asked:
//   WIDE_SHELL_RENDER=<dir> flutter test test/render/wide_shell_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:money2/money2.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show CurrencyNotifier, currencyProvider, currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/app_shell.dart';
import 'package:kute/screens/home/bitcoin_home_panes.dart';
import 'package:kute/screens/home/home.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_pin_scaffold.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/offline_venue_overrides.dart';
import '../helpers/portfolio_overrides.dart';
import '../helpers/shell_bar_harness.dart';
import '../screens/usd/investments_harness.dart'
    show
        InvestmentsTestPolicy,
        RecordingRefresh,
        RecordingRewardsApi,
        kEarnOff,
        kInvestmentsTestBalance;

final _dir = Platform.environment['WIDE_SHELL_RENDER'];

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Blank extends StatelessWidget {
  const _Blank(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: context.colors.background,
      body: Center(child: Text('page $name')));
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
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

Widget _pin() => KutePinScaffold(
      title: 'Welcome back',
      dots: const PinProgressIndicator(currentLength: 2),
      keypad: CustomKeypad(
        chromed: true,
        onDigitPressed: (_) {},
        onBackspacePressed: () {},
      ),
    );

Future<GoRouter> _pump(WidgetTester tester, Size size, bool dark) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final policy = InvestmentsTestPolicy(kEarnOff);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  final router = GoRouter(initialLocation: '/home', routes: [
    StatefulShellRoute(
      navigatorContainerBuilder: (context, shell, children) =>
          AppShell(navigationShell: shell, children: children),
      builder: (context, state, shell) => shell,
      branches: [
        for (final (path, page) in [
          ('/home', const BitcoinHomePanes(home: Home())),
          ('/bank', const _Blank('bank')),
          ('/usd', const _Blank('dollars')),
          ('/hyperliquid', const _Blank('investing')),
          ('/polymarket', const _Blank('predictions')),
        ])
          StatefulShellBranch(routes: [
            GoRoute(
              path: path,
              pageBuilder: (_, state) =>
                  NoTransitionPage<void>(key: state.pageKey, child: page),
            ),
          ]),
      ],
    ),
    GoRoute(
        path: '/pin', builder: (_, __) => KuteFormColumn(child: _pin())),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...offlineVenueOverrides,
      ...portfolioOverrides(dollars: kInvestmentsTestBalance.dollarsUsd),
      currentBtcUsdProvider.overrideWithValue(100000),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
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
      shellWalletIdProvider.overrideWith((_) => null),
      oneBalanceProvider.overrideWithValue(kInvestmentsTestBalance),
      usdBalanceProvider.overrideWithValue(kInvestmentsTestBalance.dollarsUsd),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      aiEnabledProvider.overrideWith((_) async => true),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      usdRewardsApiProvider.overrideWithValue(RecordingRewardsApi()),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      refreshEverythingProvider.overrideWith(RecordingRefresh.new),
    ],
    // The app's own ScreenUtil setup (app_widget.dart).
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: shellBarBuilder,
      ),
    ),
  ));
  await tester.pump();
  return router;
}

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (label, size) in [
    ('1440x900', const Size(1440, 900)),
    ('1180x820', const Size(1180, 820)),
    ('820x1180', const Size(820, 1180)),
    ('430x932', const Size(430, 932)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('wide shell $label $mode', skip: _dir == null,
          (tester) async {
        debugDisableShadows = true;
        addTearDown(() => debugDisableShadows = true);
        installShellBar();
        await _fonts(tester);
        final router = await _pump(tester, size, dark);
        await _settle(tester, 30);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'home_${label}_$mode');

        // A sheet over the home.
        final ctx = tester.element(find.byType(Home));
        // ignore: discarded_futures
        showAppBottomSheet<void>(
          context: ctx,
          useRootNavigator: false,
          builder: (c) => AppBottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppBottomSheetHeader(
                    title: 'Language', subtitle: 'The app speaks it'),
                for (final (i, l) in ['English', 'Deutsch', 'Português']
                    .indexed)
                  AppBottomSheetListTile(
                      title: l, isSelected: i == 0, onTap: () {}),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: AppBottomSheetButton(text: 'Done', onPressed: () {}),
                ),
              ],
            ),
          ),
        );
        await _settle(tester, 10);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'sheet_${label}_$mode');
        Navigator.of(ctx).pop();
        await _settle(tester, 10);

        // A toast over the home.
        SalToast.show(ctx,
            message: 'Address copied', tone: SalToastTone.success);
        await _settle(tester, 8);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'toast_${label}_$mode');
        await _settle(tester, 40);

        // A pushed form: the PIN pad.
        // ignore: discarded_futures
        router.push('/pin');
        await _settle(tester, 10);
        expect(tester.takeException(), isNull);
        await _shoot(tester, 'pin_${label}_$mode');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 7));
      });
    }
  }
}
