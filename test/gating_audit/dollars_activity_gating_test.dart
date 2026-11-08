// Gating audit (fw36, v2.2): the Dollars Overview pill under a backend
// policy that withholds new positions. What is already held is never
// gated (founder: exits and existing positions always open): the open
// positions' squares, the Open P&L card and the bar's "See full portfolio
// and activity" stay whatever the policy says about trading, deposits or
// browsing, a swap country block and its cascade included. Closing a
// position is driven in portfolio_exits_gating_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolyFeedNotifier, PolyFeedQuery, PolyFeedState, polyBrowseFeedProvider;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show HlPositionRow;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarContextProvider, kuteBarTop;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

import '../helpers/offline_venue_overrides.dart';
import '../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../screens/usd/investments_harness.dart';
import 'market_gating_fixtures.dart';

HlPerpPosition _perp(String coin, double margin) => HlPerpPosition(
    coin: coin,
    szi: 1,
    entryPx: 100,
    positionValue: margin * 2,
    unrealizedPnl: 3,
    returnOnEquity: 0.03,
    liquidationPx: null,
    marginUsed: margin,
    leverageType: 'cross',
    leverageValue: 2,
    maxLeverage: 40);

class _EmptyFeed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => const PolyFeedState(done: true);
}

const _browseOff = {
  'hyperliquid.browse': {'allowed': false, 'reason': 'disabled'},
  'polymarket.browse': {'allowed': false, 'reason': 'disabled'},
};

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });
  tearDown(uninstallMarketGatingPolicy);

  /// Every way the backend withholds new positions, as the audit reads it.
  final cases = <String, (MarketDenial, Set<String>)>{
    'swap country block (cascade to both venues)': (
      MarketDenial.swapCountryBlock,
      const {}
    ),
    for (final how in [
      MarketDenial.platform,
      MarketDenial.masterOff,
      MarketDenial.comingSoon,
    ])
      '${how.label} on trading and deposits of both venues': (
        how,
        const {
          'hyperliquid.trade',
          'hyperliquid.deposit',
          'polymarket.trade',
          'polymarket.deposit',
        }
      ),
  };

  for (final MapEntry(key: name, value: (how, targets)) in cases.entries) {
    for (final browse in [false, true]) {
      testWidgets(
          '$name, browsing ${browse ? 'open' : 'withheld'}: the open '
          'positions, the Open profits and the bar stay', (tester) async {
        final policy = (await tester.runAsync(() => installMarketGatingPolicy(
            how,
            targets: targets,
            overrides: browse ? const {} : _browseOff)))!;
        expect(policy.allows('hyperliquid.trade'), isFalse);
        expect(policy.allows('polymarket.trade'), isFalse);
        for (final exit in kVenueExits) {
          expect(policy.allows(exit), isTrue, reason: exit);
        }
        await pumpInvestments(tester, policy: policy, overrides: [
          if (browse) ...[
            ...offlineVenueOverrides,
            polyBrowseFeedProvider.overrideWith(_EmptyFeed.new),
          ],
          hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
                  HyperliquidTradingState(isInitialized: true, positions: [
                _perp('BTC', 100),
                _perp('ETH', 500),
              ]))),
        ]);
        final container = ProviderScope.containerOf(
            tester.element(find.byType(InvestmentsBody, skipOffstage: false)));
        // The page opens on Overview whatever the policy says (founder, 8
        // November 2026).
        expect(container.read(investmentsTabProvider), InvestmentsTab.activity);
        final squares = find.byKey(const ValueKey('dollars-activity-squares'));
        expect(squares, findsOneWidget);
        expect(
            tester
                .widgetList<HlPositionRow>(find.descendant(
                    of: squares, matching: find.byType(HlPositionRow)))
                .map((r) => (r.key! as ValueKey<String>).value),
            ['hl-ETH', 'hl-BTC']);
        expect(find.byKey(const ValueKey('dollars-pnl-strip')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('dollars-activity-empty')), findsNothing);
        final bar = kuteBarTop(container.read(kuteBarContextProvider));
        expect(bar!.isPrimary, isTrue);
        expect(bar.label, 'See full portfolio and activity');
        expect(bar.actionable, isTrue);
        expect(tester.takeException(), isNull);
        await unmountInvestments(tester);
        RuntimeCapabilitiesService.debugInstance?.dispose();
        RuntimeCapabilitiesService.debugInstance = null;
      });
    }
  }
}
