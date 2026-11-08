// The real [AppShell] (pager, top bar, tracking) over offline providers, for
// the Bitcoin | Dollars switch's tests and renders. By default each branch is
// a blank page; a render passes the real homes in [pages].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
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
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart';
import '../usd/investments_harness.dart'
    show
        InvestmentsTestPolicy,
        RecordingRefresh,
        RecordingRewardsApi,
        kEarnOff,
        kInvestmentsTestBalance;

final kTopSwitchSpending = WalletConfig(id: 'spending', name: 'Spending');
final kTopSwitchLedger = WalletConfig(
    id: 'ledger',
    name: 'Ledger',
    sparkEnabled: false,
    isHardware: true,
    walletType: 'ledger');

ThemeData topSwitchTheme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _Blank extends StatelessWidget {
  const _Blank(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: context.colors.background,
      body: Center(child: Text('page $name')));
}

/// Mounts the shell on [location] and returns its router.
Future<GoRouter> pumpTopSwitchShell(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  bool dark = false,
  Locale? locale,
  double textScale = 1,
  bool reduceMotion = false,
  String location = '/home',
  Widget? home,
  Widget? dollars,
  List<Override> overrides = const [],
  List<WalletConfig>? wallets,
  String? shellWalletId,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final policy = InvestmentsTestPolicy(kEarnOff);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  final router = GoRouter(initialLocation: location, routes: [
    StatefulShellRoute(
      navigatorContainerBuilder: (context, shell, children) =>
          AppShell(navigationShell: shell, children: children),
      builder: (context, state, shell) => shell,
      branches: [
        for (final (path, page) in [
          ('/home', home ?? const _Blank('bitcoin')),
          ('/bank', const _Blank('bank')),
          ('/usd', dollars ?? const _Blank('dollars')),
          ('/hyperliquid', const _Blank('investing')),
          ('/polymarket', const _Blank('predictions')),
        ])
          StatefulShellBranch(routes: [
            GoRoute(
              path: path,
              pageBuilder: (_, state) => NoTransitionPage<void>(
                  key: state.pageKey, child: page),
            ),
          ]),
      ],
    ),
    GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('settings route'))),
    GoRoute(
        path: '/affiliate',
        builder: (_, __) => const Scaffold(body: Text('referral route'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...offlineVenueOverrides,
      ...portfolioOverrides(dollars: kInvestmentsTestBalance.dollarsUsd),
      currentBtcUsdProvider.overrideWithValue(100000),
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
            wallets: wallets ?? [kTopSwitchSpending],
          ))),
      shellWalletIdProvider.overrideWith((_) => shellWalletId),
      oneBalanceProvider.overrideWithValue(kInvestmentsTestBalance),
      usdBalanceProvider.overrideWithValue(kInvestmentsTestBalance.dollarsUsd),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      aiEnabledProvider.overrideWith((_) async => true),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      usdRewardsApiProvider.overrideWithValue(RecordingRewardsApi()),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      refreshEverythingProvider.overrideWith(RecordingRefresh.new),
      ...overrides,
    ],
    // The app's own ScreenUtil setup (app_widget.dart).
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: topSwitchTheme(dark),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  return router;
}
