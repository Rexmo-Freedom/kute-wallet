// lib/screens/usd/components/dollars_overview_browse.dart
//
// THE OVERVIEW'S LEFT PANE ON EXPANDED (founder, 24 November 2026: "on
// larger screens show the graphs on the left with the interfaces on the
// right ... with what we already have, we just have to move stuff
// around"). On a laptop or an iPad in landscape the Dollars page is two
// panes (usd_account_screen.dart): the right one holds the balance, the
// open positions the Overview shows on a phone (its own cards, its P&L)
// and the money buttons, always in view. The Overview pill's left side is
// then what the two venues open on, each in the shape its own pill draws
// it, nothing new:
//
//   * Investing: the four squares Trending opens on (the hyped stocks and
//     commodities, [hlTrendingStrip], with logos only: [hlStripWithLogos]),
//     in one row of four ([HlSquaresRow]); a tap opens the market as the
//     Investing pill's squares do;
//   * Predictions: the big cards Trending opens on ([polyTopMarkets]), one
//     still row of as many as fit ([polyTopMarketsFitting]); a tap opens
//     the market as the Predictions pill's strip does (source
//     `top_markets`);
//   * 5 minute markets: the BTC round card Crypto › All leads with
//     ([CryptoPredictBanner], compact) beside the other coins' rounds
//     ([CryptoMoreRoundsCard]), Crypto › 5 Min's own two cards.
//
// Each section stands only while its venue may be browsed (the backend
// policy's `hyperliquid.browse` / `polymarket.browse`, as the pills' own
// browsers check), under the Overview's own heading style
// ([DollarsOverviewHeading]) with the names the pills and the category
// sheet already use. No analytics of its own: the cards send their own.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolyBrowseSelection, polyBrowseFeedProvider;
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoPredictAssets;
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart'
    show HlIconAvailability;
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart';
import 'package:kute/screens/polymarket/components/top_markets_strip.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart'
    show CryptoMoreRoundsCard, CryptoPredictBanner, openPredictionsDeposit;
import 'package:kute/screens/usd/components/dollars_activity_tab.dart'
    show DollarsOverviewHeading;
import 'package:kute/services/runtime_capabilities_service.dart';

/// The Overview pill's left pane on EXPANDED (see the file header).
class DollarsOverviewBrowse extends ConsumerWidget {
  const DollarsOverviewBrowse({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final investing = policy.allows('hyperliquid.browse');
    final predictions = policy.allows('polymarket.browse');
    Widget heading(String label) => Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: DollarsOverviewHeading(label),
        );
    return CustomScrollView(
      key: const ValueKey('dollars-overview-browse'),
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        if (investing) const SliverToBoxAdapter(child: _InvestingSquares()),
        if (predictions) ...[
          const SliverToBoxAdapter(child: _PredictionsTop()),
          SliverToBoxAdapter(child: heading(l10n.categoryFiveMinuteMarkets)),
          const SliverToBoxAdapter(child: _FiveMinuteRounds()),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: 24.h + kuteDockScrollClearance(context)),
        ),
      ],
    );
  }
}

/// Investing's Trending squares, one row of four, under "Investing";
/// their skeleton while the logos settle; nothing when there are none.
class _InvestingSquares extends ConsumerWidget {
  const _InvestingSquares();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final universe =
        ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ?? const [];
    // Trending's strip waits for the full perp list, as on its pill
    // (hyperliquid_screen.dart): never the crypto movers first.
    final perpsLanded = ref.watch(hyperliquidPerpMarketsProvider
        .select((perps) => perps.valueOrNull != null));
    return ValueListenableBuilder<int>(
      valueListenable: HlIconAvailability.revision,
      builder: (context, _, __) {
        final Widget squares;
        if (!perpsLanded || universe.isEmpty) {
          squares = const HlMovingNowStripSkeleton();
        } else {
          final trending = hlBrowseListForTab(HlBrowseTab.trending, universe);
          final pick = hlStripWithLogos(
              (keep) => hlTrendingStrip(universe, trending, keep: keep));
          if (pick.pending.isNotEmpty) {
            unawaited(HlIconAvailability.ensure(pick.pending));
          }
          if (pick.loading) {
            squares = const HlMovingNowStripSkeleton();
          } else if (pick.shown.length < kHlMoverCardMax) {
            return const SizedBox.shrink();
          } else {
            squares = HlMovingNowStrip(markets: pick.shown);
          }
        }
        return Column(
          key: const ValueKey('dollars-overview-investing'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: DollarsOverviewHeading(context.l10n.trading),
            ),
            squares,
          ],
        );
      },
    );
  }
}

/// Predictions' Trending big cards, one still row, under "Predictions";
/// nothing until the list lands.
class _PredictionsTop extends ConsumerWidget {
  const _PredictionsTop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The default list, the one the Predictions pill opens on (the same
    // feed, read once for both).
    final feed =
        ref.watch(polyBrowseFeedProvider(const PolyBrowseSelection().query));
    return LayoutBuilder(builder: (context, box) {
      final top =
          polyTopMarkets(feed.events, max: polyTopMarketsFitting(box.maxWidth));
      if (top.isEmpty) return const SizedBox.shrink();
      return Column(
        key: const ValueKey('dollars-overview-predictions'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: DollarsOverviewHeading(context.l10n.predictions),
          ),
          PolyTopMarketsStrip(
            markets: top,
            onOpenDown: MarketDetailSheet.prefetch,
            onOpen: (market) {
              HapticFeedback.mediumImpact();
              MarketDetailSheet.show(
                context,
                event: market,
                onDeposit: () async {
                  if (context.mounted) openPredictionsDeposit(context, ref);
                },
                source: 'top_markets',
              );
            },
          ),
          SizedBox(height: 4.h),
        ],
      );
    });
  }
}

/// Crypto › 5 Min's two cards side by side: the BTC round and the other
/// coins' rounds; one over the other where the pane is narrower.
class _FiveMinuteRounds extends ConsumerWidget {
  const _FiveMinuteRounds();

  /// The least width the two cards stand side by side in.
  static const double _kSideBySide = 640;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void deposit() => openPredictionsDeposit(context, ref);
    final round = RepaintBoundary(
      child: CryptoPredictBanner(
        key: const ValueKey('dollars-overview-round'),
        config: kCryptoPredictAssets.first,
        showLiveIndicator: true,
        compact: true,
        onDeposit: deposit,
      ),
    );
    final others = CryptoMoreRoundsCard(minutes: 5, onDeposit: deposit);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < _kSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [round, SizedBox(height: 12.h), others],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: round),
            SizedBox(width: 16.w),
            Expanded(child: others),
          ],
        );
      }),
    );
  }
}
