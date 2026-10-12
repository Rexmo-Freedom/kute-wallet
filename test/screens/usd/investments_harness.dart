// The Investments tab's test harness: mounts the real screen with every
// venue browser inside it (the IndexedStack mounts the Investing and
// Predictions browsers from the start) over offline providers, so a test
// can drive the pills, the dock and the gate without a network, a Hive
// box or a socket.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/api/usd_rewards_api.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';

/// Records every rewards read so a test can prove none happened.
class RecordingRewardsApi implements UsdRewardsApi {
  RecordingRewardsApi({this.estimatedSatsToday = 0});

  final calls = <String>[];

  /// What the venue says today pays: the Earn headline.
  final int estimatedSatsToday;

  @override
  Future<UserRewardsSummary> getUserSummary(String pubkey) async {
    calls.add('summary');
    return UserRewardsSummary(
      pubkey: 'pub',
      usdbBalanceRaw: 25000000,
      usdbBalanceDisplay: 25,
      swapSats: 0,
      swapCount: 0,
      rewardsBracket: 0,
      rewardsPercent: 4.5,
      estimatedSatsToday: estimatedSatsToday,
    );
  }

  @override
  Future<PayoutHistoryResponse> getPayoutHistory(String pubkey,
      {int limit = 30, int offset = 0}) async {
    calls.add('payouts');
    return const PayoutHistoryResponse(
        pubkey: 'pub', payouts: [], total: 0, limit: 30, offset: 0);
  }
}

/// A policy that answers `usd.earn` with [earn], denies browsing both
/// venues (so the embedded browsers show their notice and read no feed)
/// and allows everything else.
class InvestmentsTestPolicy extends Fake implements RuntimeCapabilitiesService {
  InvestmentsTestPolicy(this.earn);
  final CapabilityDecision earn;

  @override
  CapabilityDecision decision(String id) => switch (id) {
        'usd.earn' => earn,
        'hyperliquid.browse' ||
        'polymarket.browse' =>
          const CapabilityDecision(allowed: false, reason: 'disabled'),
        _ => const CapabilityDecision(allowed: true),
      };

  @override
  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  // The browsers' builder-code prefetches read the policy singleton: no
  // snapshot, no code, nothing to refresh.
  @override
  RuntimeCapabilities? get snapshot => null;
  @override
  String? get polymarketBuilderCode => null;
  @override
  Future<bool> refresh() async => false;

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

const kEarnOn = CapabilityDecision(allowed: true);
const kEarnOff = CapabilityDecision(allowed: false, reason: 'disabled');

/// The one-balance state the hero shows unless a test passes its own.
const kInvestmentsTestBalance = OneBalanceState(
    dollarsUsd: 25,
    investedUsd: 0,
    investingKnown: true,
    predictionsKnown: true);

/// Mounts [child] (the whole [UsdAccountScreen] by default) and returns
/// the rewards API so a test can prove what was, or was not, read.
Future<RecordingRewardsApi> pumpInvestments(
  WidgetTester tester, {
  CapabilityDecision earn = kEarnOff,
  int estimatedSatsToday = 0,
  OneBalanceState balance = kInvestmentsTestBalance,
  Widget? child,
  List<Override> overrides = const [],
  bool settle = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = RecordingRewardsApi(estimatedSatsToday: estimatedSatsToday);
  final settings = Settings(
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
  );
  final policy = InvestmentsTestPolicy(earn);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(dollars: balance.dollarsUsd),
      settingsProvider.overrideWith((_) => SettingsModel(settings)),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      oneBalanceProvider.overrideWithValue(balance),
      usdBalanceProvider.overrideWithValue(balance.dollarsUsd),
      sparkIdentityPubkeyProvider.overrideWith((_) async => 'pub'),
      usdRewardsApiProvider.overrideWithValue(api),
      aiEnabledProvider.overrideWith((_) async => true),
      // The Investing browser: no markets, no stars, no account.
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidPerpCoreMarketsProvider
          .overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      // The Predictions browser: no stars.
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      ...overrides,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child ?? const UsdAccountScreen(),
      ),
    ),
  ));
  // The Earn chart keeps a one-second countdown timer and the browsers'
  // skeletons shimmer, so settle by hand rather than wait for a quiet
  // frame that may never come.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return api;
}

/// Unmounts the tree and lets every stray delayed future elapse so the
/// test ends with no timer pending.
Future<void> unmountInvestments(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 7));
}

/// Taps [finder] and lets the switch settle by hand (see [pumpInvestments]).
Future<void> tapAndPump(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A pill of the Investments strip, by label.
Finder investmentsPill(String label) => find.descendant(
    of: find.byType(KutePillTabs).first,
    matching: find.widgetWithText(KutePill, label));

/// Scrolls the pill strip (four pills side-scroll at natural width, the
/// Home strip's rule) until the pill with [label] is built and on screen.
Future<Finder> revealPill(WidgetTester tester, String label) async {
  final pill = investmentsPill(label);
  // Three pills or fewer share a plain row: nothing to scroll.
  final scrollable = find.descendant(
      of: find.byType(KutePillTabs).first, matching: find.byType(Scrollable));
  if (scrollable.evaluate().isEmpty) return pill;
  // Later pills first, then back towards the start.
  for (final step in const [Offset(-60, 0), Offset(60, 0)]) {
    for (var i = 0; i < 12 && pill.evaluate().isEmpty; i++) {
      await tester.drag(scrollable, step, warnIfMissed: false);
      await tester.pump();
    }
    if (pill.evaluate().isNotEmpty) break;
  }
  await tester.ensureVisible(pill);
  await tester.pump();
  return pill;
}

/// Reveals and taps the pill with [label], then settles by hand.
Future<void> tapPill(WidgetTester tester, String label) async =>
    tapAndPump(tester, await revealPill(tester, label));

/// Every tracked event from now until the test ends.
List<(String, Map<String, Object>?)> recordEvents() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}
