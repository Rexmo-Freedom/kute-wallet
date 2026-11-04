// The Portfolio screen's bar shares what the section shows (founder, 2
// November 2026: "On share and brag portfolio we should say share
// portfolio on the bottom. PnL should say [something else]"): "Share
// portfolio" on Activity and Positions, "Share P&L" on P&L, the label
// morphing on a switch like every bar label; "Share P&L" opens the P&L
// card for the range picked on the hero's chart, and `brag_shared` says
// which card and which range.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/portfolio_screen.dart';
import 'package:kute/screens/share/brag/brag_preview_sheet.dart';
import 'package:kute/screens/share/brag/pnl_share_card.dart';
import 'package:kute/screens/shared/kute_morph_label.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/portfolio_overrides.dart';

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();
  @override
  Future<void> preview() async {}
  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// Both venues' P&L: Investing a year and a half of it, Predictions a
/// month and a half.
List<Override> _history() {
  final now = DateTime.now().toUtc();
  PortfolioPerformance perf(List<(int, double)> points, String source) =>
      PortfolioPerformance(
          points: [
            for (final (days, pnl) in points)
              PortfolioPnlPoint(
                  timestamp: now.subtract(Duration(days: days)), pnlUsd: pnl)
          ],
          totalPnlUsd: points.last.$2,
          asOf: now.subtract(Duration(days: points.last.$1)),
          sourceLabel: source,
          basisLabel: 'P&L',
          coverageLabel: 'All time');
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => perf([
              (540, 0),
              (300, 40),
              (200, -12),
              (60, 22),
              (22, -4),
              (8, 3.2),
              (1, 12.4)
            ], 'Hyperliquid')),
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.predictions))
        .overrideWith((_) async =>
            perf([(45, 0), (20, 2.5), (2, 7.61)], 'Polymarket')),
  ];
}

/// Nothing ever traded at either venue.
List<Override> _none() => [
      for (final v in PortfolioPerformanceVenue.values)
        portfolioPerformanceProvider(PortfolioPerformanceRequest(venue: v))
            .overrideWith((_) async => kPortfolioNoPerformance),
    ];

Future<void> _mount(WidgetTester tester, {required List<Override> extra}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 1400) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
      hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
      hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      oneBalanceProvider.overrideWith((ref) => const OneBalanceState(
            investingKnown: true,
            predictionsKnown: true,
          )),
      usdBalanceUnknownProvider.overrideWithValue(false),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      hyperliquidActivityFillsProvider.overrideWithValue(const []),
      portfolioSectionProvider.overrideWith((_) => PortfolioSection.balances),
      ...extra,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        builder: withKuteShellBar,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PortfolioScreen(),
      ),
    ),
  ));
  await _settle(tester);
}

/// Sal loops: a fixed run of frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pick(WidgetTester tester, PortfolioSection section) async {
  await tester
      .tap(find.byKey(ValueKey('portfolio-section-pill-${section.key}')));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late List<(String, Map<String, Object>?)> events;
  setUp(() {
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    BragPreviewSheet.debugSharer = null;
    BragPreviewSheet.debugLineSeed = null;
  });

  testWidgets(
      'the bar says "Share portfolio" on Positions and Activity and "Share '
      'P&L" on P&L, the words morphing on the switch, the same button',
      (tester) async {
    await _mount(tester, extra: _history());
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    expect(find.text('Share and brag'), findsNothing);
    final button = tester.state(find.byType(KuteBarPrimaryButton));

    await _pick(tester, PortfolioSection.charts);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-morph: the old words on their way out, the new ones rising, in
    // the bar's one morph (KuteMorphLabel), on the same button.
    expect(find.byType(KuteMorphLabel), findsWidgets);
    expect(kuteBarPrimaryWithText('Share P&L'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    expect(tester.state(find.byType(KuteBarPrimaryButton)),
        same(button));
    await _settle(tester);
    expect(kuteBarPrimaryWithText('Share P&L'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsNothing);

    await _pick(tester, PortfolioSection.balances);
    await _settle(tester);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    await _pick(tester, PortfolioSection.activity);
    await _settle(tester);
    expect(kuteBarPrimaryWithText('Share portfolio'), findsOneWidget);
    expect(kuteBarPrimaryWithText('Share P&L'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('nothing ever traded: the default bar on every section',
      (tester) async {
    await _mount(tester, extra: _none());
    expect(kuteBarPrimary, findsNothing);
    for (final s in [PortfolioSection.charts, PortfolioSection.activity]) {
      await _pick(tester, s);
      await _settle(tester);
      expect(kuteBarPrimary, findsNothing, reason: '$s');
    }
    expect(find.text('Share P&L'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      '"Share P&L" opens the P&L card for the range picked on the hero '
      '(1Y): the hero\'s P&L, the range, its line; Share sends card pnl and '
      'the range', (tester) async {
    BragPreviewSheet.debugLineSeed = 0;
    final sent = <String>[];
    BragPreviewSheet.debugSharer = (_, text) async => sent.add(text);
    await _mount(tester, extra: _history());
    await _pick(tester, PortfolioSection.charts);
    await _settle(tester);
    await tester.tap(find.text('1Y'));
    await _settle(tester);
    // The hero's P&L over the year ("▲ $12.40 · Past year").
    final headline = tester
        .widget<Text>(find.byKey(const ValueKey('portfolio-hero-change')))
        .textSpan!
        .toPlainText()
        .split(' · ')
        .first;

    await tester.tap(kuteBarPrimary);
    await _settle(tester);
    final card = tester.widget<PnlShareCard>(find.byType(PnlShareCard));
    expect(card.data.range, BalanceRange.year);
    expect(card.data.venue, isNull);
    // The card's figure is the hero's, the range its pill's.
    expect(card.data.result!.text.replaceAll(RegExp(r'[^\d.,]'), ''),
        headline.replaceAll(RegExp(r'[^\d.,]'), ''));
    Finder onCard(Finder f) =>
        find.descendant(of: find.byType(PnlShareCard), matching: f);
    expect(onCard(find.text('MY P&L · 1Y')), findsOneWidget);
    expect(onCard(find.text('Past year')), findsOneWidget);
    expect(find.byKey(const ValueKey('pnl-card-chart')), findsOneWidget);
    expect(card.data.series, isNotNull);
    // The sheet's title and its own Share.
    expect(find.text('Share P&L'), findsWidgets);
    expect(kuteBarPrimaryWithText('Share'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(kuteBarPrimary);
      for (var i = 0; i < 100 && sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await _settle(tester);
    expect(sent.single, startsWith('My P&L on Kute '));
    expect(events.where((e) => e.$1 == 'brag_shared').map((e) => e.$2),
        [
          {'kind': 'portfolio', 'card': 'pnl', 'range': '1Y'}
        ]);
    await _unmount(tester);
  });
}
