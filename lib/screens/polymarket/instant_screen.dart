// lib/screens/polymarket/instant_screen.dart
//
// PREDICTIONS › INSTANT, A SCREEN OF ITS OWN (founder, 8 November 2026:
// "when clicking instant we should be able to choose on the instant new
// screen here, not in the here"; "think about this screen and improve it
// massively"; "check how Polymarket does this and make it good for
// mobile"). Pushed from the Predictions sheet's Instant card and the Sal
// grid's Instant tile (investments_category_sheet.dart); the pill on the
// Dollars home stays whatever it was.
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
// The screen:
//   * the app's full-screen header (AppBar with [KuteBackButton], the title
//     centred: open_investments_screen.dart), title "Instant";
//   * the filter: the coins on offer at the picked length and the lengths
//     the venue runs (instant_filter.dart), remembered on this device
//     (polymarket_instant_provider.dart);
//   * ONE card, the picked coin's round in play at the picked length
//     (instant_round_card.dart), with the strip of rounds and the one pair
//     of Up and Down buttons on the screen;
//   * the person's own rounds under it, on the Portfolio's rows.
// A pick on the filter switches the card as a chip switch does; nothing
// else on the screen moves. Gating: `polymarket.browse` as the Predictions
// lists (the discovery notice, nothing read). One asset on screen is one
// live card: one round notifier, one set of sockets, all gone when the
// screen is popped.

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
import 'package:kute/screens/polymarket/polymarket_screen.dart'
    show openPredictionsDeposit;
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PlacingBetRow, PolyPositionRow, PortfolioCardList;
import 'package:kute/screens/shared/investment_balance_header.dart'
    show InvestmentDiscoveryNotice;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show SliverSelectionFade;
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class PolyInstantScreen extends ConsumerStatefulWidget {
  const PolyInstantScreen({super.key, required this.source});

  /// Where it was opened from, for `predictions_instant_opened`: `sheet`
  /// (the Predictions sheet's card), `sal` (the Sal grid's tile),
  /// `deep_link`.
  final String source;

  static const routeName = 'polymarket-instant';

  /// Opens the screen over everything, on the root navigator.
  static Future<void> show(BuildContext context, {required String source}) =>
      push(Navigator.of(context, rootNavigator: true), source: source);

  /// [show] with the navigator in hand (a sheet that has closed).
  static Future<void> push(NavigatorState navigator,
          {required String source}) =>
      navigator.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => PolyInstantScreen(source: source),
      ));

  @override
  ConsumerState<PolyInstantScreen> createState() => _PolyInstantScreenState();
}

class _PolyInstantScreenState extends ConsumerState<PolyInstantScreen> {
  @override
  void initState() {
    super.initState();
    // Once per mount, no market data attached.
    TrackingService.track('predictions_instant_opened',
        params: {'source': widget.source});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final canBrowse =
        ref.watch(runtimeCapabilitiesProvider).allows('polymarket.browse');
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const KuteBackButton(),
        title: Text(
          l10n.predictionsInstant,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: canBrowse
                ? const _InstantBody()
                : const SingleChildScrollView(
                    child: InvestmentDiscoveryNotice(
                        capability: 'polymarket.browse'),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The filter, the one card and the person's own rounds.
class _InstantBody extends ConsumerWidget {
  const _InstantBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final choice = ref.watch(polyInstantChoiceProvider);
    // A remembered length the venue no longer runs reads five minutes; the
    // choice itself stays for when it is back.
    final lengths = polyInstantLengthsOffered(
        polySubsFor(ref, PolyPill.crypto).map((s) => s.key));
    final length = lengths.contains(choice.length) ? choice.length : '5m';
    // The coins the venue runs at this length, from its own list of that
    // length's rounds (Crypto › 15 Min and so on); every known coin at five
    // minutes and until the list is in.
    final feed = length == '5m'
        ? null
        : ref.watch(polyBrowseFeedProvider(
            PolyFeedQuery(pill: PolyPill.crypto, sub: length)));
    final assets = polyInstantAssetsOffered(feed?.events ?? const [],
        chosen: choice.asset,
        fallback: kCryptoRoundAssets.map((c) => c.asset));
    final shown = PolyInstantChoice(asset: choice.asset, length: length);
    final config = kCryptoRoundAssets.firstWhere(
        (c) => c.asset == choice.asset,
        orElse: () => kCryptoRoundAssets.first);
    // The venue's list is in and does not run this coin at this length.
    final absent = feed != null &&
        !feed.loading &&
        feed.events.isNotEmpty &&
        !feed.events.any((e) => polyInstantAssetOf(e) == choice.asset);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
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
                    : InstantRoundCard(
                        config: config,
                        length: length,
                        onDeposit: () =>
                            openPredictionsDeposit(context, ref),
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
