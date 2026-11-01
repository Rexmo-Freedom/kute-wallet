// The Portfolio screen's three sections under the pinned strip
// (investments_portfolio.dart, sharesHeader): their empty states are ONE
// treatment at one place (portfolio_empty_state.dart), and P&L Charts
// never opens on a blank frame.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalIdleDirector, SalSprite;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';

class _Sweeper extends VenueSweeperNotifier {
  @override
  VenueSweeperState build() => const VenueSweeperState();

  @override
  Future<void> preview() async {}

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// Nothing open anywhere, the cash read.
const _nothingOpen = OneBalanceState(
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 17.21,
    OneBalanceVenue.predictions: 0.43,
  },
);

/// A month of Investing P&L that dips under zero and ends above it.
List<Override> _history() {
  final now = DateTime.now().toUtc();
  final points = [(30, 0.0), (22, -4.0), (15, -9.5), (8, 3.2), (1, 12.4)];
  return [
    portfolioPerformanceProvider(const PortfolioPerformanceRequest(
            venue: PortfolioPerformanceVenue.trading))
        .overrideWith((_) async => PortfolioPerformance(
            points: [
              for (final (days, pnl) in points)
                PortfolioPnlPoint(
                    timestamp: now.subtract(Duration(days: days)),
                    pnlUsd: pnl)
            ],
            totalPnlUsd: 12.4,
            asOf: now.subtract(const Duration(days: 1)),
            sourceLabel: 'Hyperliquid',
            basisLabel: 'P&L',
            coverageLabel: 'All time')),
  ];
}

Future<void> _mount(WidgetTester tester,
    {List<Override> extra = const []}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 844) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      oneBalanceProvider.overrideWith((ref) => _nothingOpen),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: Material(
              child: Consumer(
                builder: (context, ref, _) => InvestmentsPortfolio(
                  sharesHeader: true,
                  onSection: (s) =>
                      ref.read(portfolioSectionProvider.notifier).state = s,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

/// Sal never settles (he loops), so a fixed run of frames, not
/// pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pick(WidgetTester tester, PortfolioSection section) async {
  await tester
      .tap(find.byKey(ValueKey('portfolio-section-pill-${section.key}')));
}

/// Equal up to float rounding.
void _expectSameRect(Rect actual, Rect expected, String reason) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, moreOrLessEquals(e, epsilon: 0.01), reason: reason);
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
      'the three sections empty: one empty state, Sal and the title at the '
      'same place, only the copy changes', (tester) async {
    await _mount(tester);
    final titles = {
      PortfolioSection.balances: 'No open positions',
      PortfolioSection.charts: 'No P&L yet',
      PortfolioSection.activity: 'No activity yet',
    };
    final sal = <PortfolioSection, Rect>{};
    final title = <PortfolioSection, Rect>{};
    for (final section in [
      PortfolioSection.balances,
      PortfolioSection.charts,
      PortfolioSection.activity,
      PortfolioSection.balances,
    ]) {
      if (section != PortfolioSection.balances || sal.isNotEmpty) {
        await _pick(tester, section);
        await _settle(tester);
      }
      expect(find.byType(PortfolioSectionEmpty), findsOneWidget,
          reason: '$section draws the sections\' one empty state');
      expect(find.byType(SalIdleDirector), findsOneWidget);
      // The hero Sal alone: no pixel Sal anywhere.
      expect(find.byType(SalSprite), findsOneWidget);
      final s = tester.getRect(find.byType(SalIdleDirector));
      final t = tester.getRect(find.text(titles[section]!));
      // Back on the first section: exactly where it was.
      if (sal[section] case final before?) {
        _expectSameRect(s, before, 'Sal back on $section');
        _expectSameRect(t, title[section]!, 'title back on $section');
      }
      sal[section] = s;
      title[section] = t;
      // The title: 22 w600.
      final text = tester.widget<Text>(find.text(titles[section]!));
      expect(text.style?.fontWeight, FontWeight.w600);
    }
    final base = sal[PortfolioSection.balances]!;
    for (final section in PortfolioSection.values) {
      _expectSameRect(sal[section]!, base, 'Sal on $section');
      final t0 = title[PortfolioSection.balances]!;
      expect(title[section]!.top, moreOrLessEquals(t0.top, epsilon: 0.01),
          reason: 'title top on $section');
      expect(
          title[section]!.height, moreOrLessEquals(t0.height, epsilon: 0.01),
          reason: 'title height on $section');
      expect(title[section]!.center.dx,
          moreOrLessEquals(title[PortfolioSection.balances]!.center.dx),
          reason: 'title centred on $section');
    }
    // The same size the P&L one had: the hero 160.
    expect(base.width, moreOrLessEquals(160.sp));
    await _unmount(tester);
  });
}
