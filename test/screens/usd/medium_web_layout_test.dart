// The web has no MEDIUM (founder, 27 November 2026, a 960 window: "too
// many rows of stuff. Make it more like the desktop"): in a browser the
// desktop structure starts where the phone ends. The Dollars page at a
// medium width is the left navigation and the browse (no pill rows), its
// positions column only from 1100; a phone's width keeps the pills; the
// native rule is untouched. Off the web the browser's rule is forced
// (KuteLayout.debugWeb, KuteBarPane.debugWeb).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart'
    show HlIconAvailability;
import 'package:kute/screens/shared/kute_desk_market.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';

import '../../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import 'investments_harness.dart';

Override _holding() =>
    hyperliquidTradingProvider.overrideWith(() => PortfolioTestTrading(
        HyperliquidTradingState(isInitialized: true, positions: const [
          HlPerpPosition(
              coin: 'BTC',
              szi: 1,
              entryPx: 100,
              positionValue: 200,
              unrealizedPnl: 3,
              returnOnEquity: 0.03,
              liquidationPx: null,
              marginUsed: 100,
              leverageType: 'cross',
              leverageValue: 2,
              maxLeverage: 40),
        ])));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HlIconAvailability.debugEveryLogoKnown = true;
  });
  tearDown(() {
    HlIconAvailability.debugEveryLogoKnown = false;
    KuteLayout.debugWeb = false;
    KuteBarPane.debugWeb = false;
  });

  void web() {
    KuteLayout.debugWeb = true;
    KuteBarPane.debugWeb = true;
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    await pumpInvestments(tester,
        browseInvesting: true,
        size: size,
        designSize: KuteLayout.designSizeFor(size),
        child: const UsdAccountScreen(initialTab: InvestmentsTab.investing),
        overrides: [_holding()]);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final nav = find.byKey(const ValueKey('dollars-desk-nav-investing'));
  bool positionsColumnShown(WidgetTester tester) => !tester
      .widget<Offstage>(
          find.byKey(const ValueKey('dollars-positions-column')))
      .offstage;

  test('the thresholds: the browser\'s EXPANDED from the phone\'s end', () {
    expect(KuteLayout.forWidth(599), KuteFormFactor.compact);
    expect(KuteLayout.forWidth(700), KuteFormFactor.medium,
        reason: 'native: MEDIUM as before');
    KuteLayout.debugWeb = true;
    expect(KuteLayout.forWidth(599), KuteFormFactor.compact);
    expect(KuteLayout.forWidth(600), KuteFormFactor.expanded);
    expect(KuteLayout.forWidth(960), KuteFormFactor.expanded);
    expect(kuteDeskNavFrom, 600);
    expect(kutePositionsColumnFrom, 1100);
    // A market page is the desk from where its chart keeps 520.
    expect(kuteWebDeskMarketMinWidth, inInclusiveRange(1000, 1060));
    KuteLayout.debugWeb = false;
    expect(kuteDeskNavFrom, kuteDeskNavMinWidth);
  });

  for (final width in [640.0, 960.0]) {
    testWidgets('web at $width: the left navigation, no pill rows, no '
        'positions column', (tester) async {
      web();
      await pump(tester, Size(width, 800));
      expect(nav, findsOneWidget);
      expect(find.byType(KutePillTabs), findsNothing);
      expect(positionsColumnShown(tester), isFalse);
      expect(tester.takeException(), isNull);
      await unmountInvestments(tester);
    });
  }

  testWidgets('web at 1440: the navigation and the positions column',
      (tester) async {
    web();
    await pump(tester, const Size(1440, 900));
    expect(nav, findsOneWidget);
    expect(positionsColumnShown(tester), isTrue);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });

  testWidgets('a phone\'s width keeps the pills', (tester) async {
    web();
    await pump(tester, const Size(390, 844));
    expect(nav, findsNothing);
    expect(find.byType(KutePillTabs), findsWidgets);
    expect(tester.takeException(), isNull);
    await unmountInvestments(tester);
  });
}
