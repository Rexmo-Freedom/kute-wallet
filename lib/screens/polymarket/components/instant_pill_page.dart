// lib/screens/polymarket/components/instant_pill_page.dart
//
// PREDICTIONS › INSTANT, A PILL PAGE ON THE DOLLARS HOME (founder, 8
// November 2026: "I don't want Instant to take me to another screen. It
// should all be on the Dollars home under Predictions. We select Instant,
// and then we select there the coin and all that."). The page of
// [PolyPill.instant] (polymarket_browse_provider.dart), drawn by the
// Predictions browser (polymarket_screen.dart) under its pills in place of
// a list, as any category's page is; the Dollars pill reads "Predictions ·
// Instant". Picked from the Predictions sheet's Instant card and the Sal
// grid's Instant tile (investments_category_sheet.dart); nothing is pushed.
// For a few hours that day it was a screen of its own (instant_screen.dart,
// gone): the content is that screen's, the frame is the page's.
//
// What polymarket.com does (read 8 November 2026): one tab per length (5
// Min, 15 Min, 1 Hour, 4 Hours, Daily …), a row of coin filters under it,
// a card per market with Up and Down; the event page shows one round with
// its live chart and "Price to Beat", a "Past" menu of results, and a strip
// of the next windows ("11:10AM · 11:15AM · 11:20AM …") to move to. Taken
// for a phone: the length and the coin as two chip rows, ONE round card with
// its live chart, and the next windows as a strip ON the card; left out: a
// page per window and the feed of cards.
//
// The page, as slivers under the browser's pills:
//   * the filter: the coins on offer at the picked length and the lengths
//     the venue runs (instant_filter.dart), remembered on this device
//     (polymarket_instant_provider.dart);
//   * ONE card, the picked coin's round in play at the picked length
//     (instant_round_card.dart), with the strip of rounds and the one pair
//     of Up and Down buttons on the whole page;
//   * the person's own rounds under it, on the Portfolio's rows.
// A pick on the filter switches the card as a chip switch does; nothing
// else on the page moves. Gating: the browser shows this page only under
// `polymarket.browse`, as the Predictions lists (the discovery notice
// otherwise, nothing read).
//
// THE COST. One asset on the page is one live card: one round notifier,
// one set of sockets. The Dollars home keeps its pill pages mounted behind
// one another (Investing · Predictions · Portfolio) with their tickers off,
// and the shell keeps the Dollars home mounted behind the other tabs the
// same way (`Offstage` + `TickerMode`), so the card is built only while its
// page can be seen ([_InstantCardGate]): hidden, the card goes (and with it
// its provider, its timers and its seat on the sockets) and a box of its
// height holds the list's scroll position; shown again, it comes back and
// reads afresh. Another Predictions pill unmounts the page outright.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart'
    show placingPolymarketBetProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_instant_provider.dart';
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoRoundAssets;
import 'package:kute/screens/polymarket/components/instant_filter.dart';
import 'package:kute/screens/polymarket/components/instant_round_card.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polySubsFor;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PlacingBetRow, PolyPositionRow, PortfolioCardList;
import 'package:kute/screens/shared/kute_motion.dart'
    show SliverSelectionFade;
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/theme/app_theme.dart';

/// The filter, the one card and the person's own rounds, as one sliver
/// group for the browser's scroll view.
class PolyInstantPage extends ConsumerWidget {
  const PolyInstantPage({super.key, this.onDeposit});

  /// The slip's deposit path (the browser's own).
  final VoidCallback? onDeposit;

  /// The Crypto list the filter reads for the coins on offer at [length]:
  /// none at five minutes (every known coin runs), else that length's
  /// window list. The browser refreshes it with the page.
  static PolyFeedQuery? feedFor(String length) => length == '5m'
      ? null
      : PolyFeedQuery(pill: PolyPill.crypto, sub: length);

  /// The length the page shows for [choice] given the lengths the venue
  /// runs: a remembered length the venue no longer runs reads five minutes;
  /// the choice itself stays for when it is back.
  static String shownLength(PolyInstantChoice choice, List<String> lengths) =>
      lengths.contains(choice.length) ? choice.length : '5m';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final choice = ref.watch(polyInstantChoiceProvider);
    final lengths = polyInstantLengthsOffered(
        polySubsFor(ref, PolyPill.crypto).map((s) => s.key));
    final length = shownLength(choice, lengths);
    // The coins the venue runs at this length, from its own list of that
    // length's rounds (Crypto › 15 Min and so on); every known coin at five
    // minutes and until the list is in.
    final feedQuery = feedFor(length);
    final feed =
        feedQuery == null ? null : ref.watch(polyBrowseFeedProvider(feedQuery));
    // The coins the app has a card for: the venue also lists others (ZEC at
    // 15 minutes and 4 hours, 8 November 2026), which get no chip.
    bool known(String asset) => kCryptoRoundAssets.any((c) => c.asset == asset);
    final assets = polyInstantAssetsOffered(
            feed?.events ?? const [],
            chosen: choice.asset,
            fallback: kCryptoRoundAssets.map((c) => c.asset))
        .where(known)
        .toList();
    final shown = PolyInstantChoice(asset: choice.asset, length: length);
    final config = kCryptoRoundAssets.firstWhere(
        (c) => c.asset == choice.asset,
        orElse: () => kCryptoRoundAssets.first);
    // The venue's list is in and does not run this coin at this length.
    final absent = feed != null &&
        !feed.loading &&
        feed.events.isNotEmpty &&
        !feed.events.any((e) => polyInstantAssetOf(e) == choice.asset);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: PolyInstantFilter(
            assets: assets,
            lengths: lengths,
            asset: choice.asset,
            length: length,
          ),
        ),
        SliverSelectionFade(
          selection: shown,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
                child: absent
                    ? Padding(
                        key: const ValueKey('instant-no-round'),
                        padding: EdgeInsets.symmetric(vertical: 24.h),
                        child: Text(
                          l10n.predictNoOpenMarketsCategory,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : _InstantCardGate(
                        child: InstantRoundCard(
                          config: config,
                          length: length,
                          onDeposit: onDeposit,
                        ),
                      ),
              ),
            ),
          ],
        ),
        const _InstantOwnRounds(),
        SliverToBoxAdapter(child: SizedBox(height: 24.h)),
      ],
    );
  }
}

/// The card only while its page can be seen (see the file header). A
/// hidden Dollars pill or shell branch stays mounted with its tickers off,
/// and the card's reads would run on behind it. Hidden, the card goes (and
/// with it its provider and timers) and a box of its height holds the
/// list's scroll position.
class _InstantCardGate extends StatefulWidget {
  const _InstantCardGate({required this.child});

  final Widget child;

  @override
  State<_InstantCardGate> createState() => _InstantCardGateState();
}

class _InstantCardGateState extends State<_InstantCardGate> {
  double? _height;

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled) {
      return SizedBox(
          key: const ValueKey('instant-card-hidden'), height: _height);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _height = context.size?.height;
    });
    return widget.child;
  }
}

/// The person's own rounds, under the card, whatever the filter says:
/// bets on their way, then the rounds held, on the Portfolio's card and
/// rows (position_rows.dart); rows, never buttons. Its own widget so a
/// position tick rebuilds this and not the card. Nothing at all with no
/// round held.
class _InstantOwnRounds extends ConsumerWidget {
  const _InstantOwnRounds();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool isRound(String? slug) =>
        slug != null && polyCryptoRoundOf(slug) != null;
    final placing = [
      for (final b in ref.watch(placingPolymarketBetProvider))
        if (isRound(b.eventSlug)) b,
    ];
    final held = [
      for (final p in ref.watch(polymarketActivePositionsProvider))
        if (p.eventSlug != null &&
            polyCryptoRoundOf(p.eventSlug!,
                    endDate: DateTime.tryParse(p.endDateStr ?? '')) !=
                null)
          p,
    ];
    if (placing.isEmpty && held.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      key: const ValueKey('instant-own-rounds'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        child: PortfolioCardList(
          rows: [
            for (final b in placing)
              PlacingBetRow(key: ValueKey('placing-${b.placementId}'), bet: b),
            for (final p in held)
              PolyPositionRow(key: ValueKey('poly-${p.tokenId}'), position: p),
          ],
        ),
      ),
    );
  }
}
