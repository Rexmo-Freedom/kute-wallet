// lib/screens/polymarket/components/instant_round_card.dart
//
// THE ONE CARD of Predictions › Instant (the pill page on the Dollars
// home, instant_pill_page.dart): the round in play of one asset at one
// length, live, with the strip of rounds around it and the one pair of Up
// and Down buttons on the whole page. The compact
// round card ([CompactCryptoCard], crypto_round_card.dart) draws it:
// logo, "BTC up or down · 5m", the past rounds as dots, the countdown; the
// live price with its move and the target; the live chart against the
// dashed target line; then the window strip ([InstantRoundStrip]); then
// the buttons with live odds.
//
// WHAT IS LIVE. The chart, the price, the target and the countdown are
// always the round in play ([cryptoRoundProvider] for the asset and
// length: Chainlink's TWAP over the shared PolyBolt socket, backfilled
// from Binance's candles for a round longer than five minutes so it is
// drawn from its start). The buttons bet on the SELECTED round
// (instant_strip.dart): the roll's choice by default (crypto_next_round.dart,
// five-minute rounds only), or the round the person tapped on the strip
// while that pick stands. When that is not the round on show, a line over
// the buttons names it ("BTC up or down · 7:20–7:25"), the same name the
// slip, the receipt and the position carry.
//
// WITHOUT GAMMA'S EVENT (the read on its way, Gamma listing no round for
// the slug, as happened for every four-hour round under standard time until
// 8 November 2026, crypto_round.dart, or only the round that just ended, an
// event with nothing left to bet on) the card says so and nothing else: the price and target skeletons, the countdown pill a skeleton bar
// (never "0:00:00"), the strip's round in play "No prices yet" and
// unpickable, the buttons "Up" and "Down" with no odds (never 50% / 50%)
// and opening nothing.
//
// WHAT IS READ. One round notifier (a Gamma read every 10 s and a seat on
// the price feed), Gamma's read of the two rounds ahead
// ([cryptoNextRoundProvider], asked again every 10 s only while Gamma has
// no open round), the books of all three rounds' tokens on the market
// socket ([LiveTokenScope]) so the strip knows which have real prices, the
// live odds of the round on show and of the selected one
// ([CryptoOddsScope]), and the last four results. All of it only while the
// card can be seen ([CryptoCardOnScreen], tickers), and gone with it.
//
// THE SLIP is the one money path: it opens on the selected round's market
// exactly as the list card's rolled buttons open the next window, with the
// odds on the button, and stays on that round whatever the card does while
// it is open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/crypto_next_round_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart'
    show placingPolymarketBetProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_instant_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/screens/home/components/btc_predict_chart.dart'
    show kBtcPredictChartWindow;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/crypto_odds_scope.dart';
import 'package:kute/screens/polymarket/components/crypto_round_card.dart';
import 'package:kute/screens/polymarket/components/instant_round_strip.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/round_window_label.dart'
    show polyRoundClock;
import 'package:kute/services/polymarket/crypto_live_odds.dart'
    show cryptoShownUp, cryptoOddsSane;
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/polymarket/instant_strip.dart';
import 'package:kute/services/tracking_service.dart';

class InstantRoundCard extends ConsumerWidget {
  const InstantRoundCard({
    super.key,
    required this.config,
    required this.length,
    this.onDeposit,
  });

  final CryptoAssetConfig config;

  /// The Crypto chip's key: '5m', '15m', '1h' or '4h'.
  final String length;
  final VoidCallback? onDeposit;

  /// The plot's height: the point of the screen, so taller than the list's
  /// 54.
  static const double sparkHeight = 110;

  /// Where the slip says it was opened from.
  static const String slipSource = 'instant';

  PolyInstantChoice get _choice =>
      PolyInstantChoice(asset: config.asset, length: length);

  /// The time left as the card writes it: "04:00" for the minutes-long
  /// rounds ([CryptoPredictState.countdownText]), "3:59:59" once a round is
  /// an hour or longer, never "239:59".
  static String _countdown(int seconds, int minutes) {
    final s = seconds < 0 ? 0 : seconds;
    String two(int n) => n.toString().padLeft(2, '0');
    if (minutes < 60) return '${two(s ~/ 60)}:${two(s % 60)}';
    return '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final minutes = polyInstantMinutes(length);
    final asset = config.asset;
    final key = (asset: asset, minutes: minutes);
    final predictAsync = ref.watch(cryptoRoundProvider(key));
    final predictState = predictAsync.asData?.value;
    if (predictAsync.hasError && !predictAsync.hasValue) {
      return const SizedBox.shrink();
    }
    final now = ref.read(cryptoOddsClockProvider)();
    // A round that has ended is no event to show: its time left is zero and
    // its odds its result (Gamma answers with the last round until the next
    // one is listed).
    final event = switch (predictState?.event) {
      final e? when e.endDate?.isAfter(now) ?? false => e,
      _ => null,
    };
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    String clock(DateTime t) =>
        polyRoundClock(t, locale: l10n.localeName, use24h: use24h);

    // The round on show and the ones ahead of it, from the clock.
    final liveStart = polyRoundStartAt(now, minutes);
    final liveRound = PolyCryptoRound(
      asset: asset.toLowerCase(),
      window: Duration(minutes: minutes),
      start: DateTime.fromMillisecondsSinceEpoch(liveStart * 1000, isUtc: true),
    );
    final aheadStarts = polyStripAheadStarts(liveStart, minutes);
    final ahead = <int, Btc5MinEvent?>{
      for (final start in aheadStarts)
        start: ref
            .watch(cryptoNextRoundProvider(
                (asset: asset, minutes: minutes, start: start)))
            .valueOrNull,
    };

    // Live odds: the round on show by its Up token; the rounds ahead from
    // the feed's books. Watching the chances repaints on every tick.
    final upTokenId = event?.upTokenId;
    final downTokenId = event?.downTokenId;
    final liveUpRaw = ref.watch(cryptoLiveOddsProvider
        .select((s) => upTokenId == null ? null : s[upTokenId]?.up));
    final livePctUp =
        (liveUpRaw ?? ((predictState?.upPct ?? 50) / 100.0)).clamp(0.0, 1.0);
    for (final e in ahead.values) {
      final t = e?.upTokenId;
      ref.watch(cryptoLiveOddsProvider.select((s) => t == null ? null : s[t]?.up));
    }
    final books = ref.read(cryptoOddsBooksProvider);

    // The roll (five-minute rounds): the next round once this one is two
    // minutes old and it has real prices.
    final nextEvent = ahead[aheadStarts.first];
    final rolled = polyNextRoundButtons(
      round: liveRound,
      next: nextEvent,
      upBook: nextEvent?.upTokenId == null
          ? null
          : books.snapshot(nextEvent!.upTokenId!),
      downBook: nextEvent?.downTokenId == null
          ? null
          : books.snapshot(nextEvent!.downTokenId!),
      now: now,
    );

    // The past rounds, the strip, the selected round.
    final resultsKey = (asset: asset, minutes: minutes, currentStart: liveStart);
    final past = ref.watch(cryptoRecentResultsProvider(resultsKey)).valueOrNull ??
        carriedCryptoResults(asset, minutes, liveStart);
    final held = <String>{
      for (final b in ref.watch(placingPolymarketBetProvider))
        if (b.eventSlug case final s?) s.toLowerCase(),
      for (final p in ref.watch(polymarketActivePositionsProvider))
        if (p.eventSlug case final s?) s.toLowerCase(),
    };
    final rounds = polyInstantStrip(
      asset: asset,
      minutes: minutes,
      now: now,
      past: past,
      live: event,
      ahead: ahead,
      books: books.snapshot,
      heldSlugs: held,
    );
    final picked = ref.watch(polyInstantPickedRoundProvider(_choice));
    final selectedStart = polyInstantSelectedStart(
      rounds: rounds,
      now: now,
      picked: picked,
      rolledStart:
          rolled == null ? null : rolled.start.millisecondsSinceEpoch ~/ 1000,
    );
    final selected = rounds.firstWhere((r) => r.start == selectedStart);
    final onShow = selected.slot == PolyRoundSlot.live;
    final target = onShow ? event : selected.event;
    final selectedUpToken = target?.upTokenId;
    // Null without a round to bet on: no odds on the buttons.
    final double? buttonsUp;
    if (target == null) {
      buttonsUp = null;
    } else if (onShow) {
      buttonsUp = livePctUp;
    } else {
      final up = cryptoShownUp(
          selectedUpToken == null ? null : books.snapshot(selectedUpToken));
      buttonsUp = cryptoOddsSane(up) ? up : null;
    }
    // Which round the buttons bet on, when it is not the one on show.
    final String? line = onShow
        ? null
        : l10n.predictRoundWindow(
            asset, clock(selected.startTime), clock(selected.endTime));

    final priceToBeat = predictState?.priceToBeat;
    final currentPrice = predictState?.currentPrice;
    final diff = currentPrice != null && priceToBeat != null
        ? currentPrice - priceToBeat
        : null;
    // The time left only once Gamma's event gives it.
    final countdown = event == null
        ? null
        : _countdown(predictState!.secondsRemaining, minutes);

    void openSide(String side) {
      if (target == null || buttonsUp == null) return;
      final outcomes = onShow
          ? [
              PolymarketOutcome(
                  name: 'Up',
                  price: target.upPrice,
                  tokenId: target.upTokenId,
                  conditionId: target.conditionId),
              PolymarketOutcome(
                  name: 'Down',
                  price: target.downPrice,
                  tokenId: target.downTokenId,
                  conditionId: target.conditionId),
            ]
          : [
              PolymarketOutcome(
                  name: 'Up',
                  price: buttonsUp,
                  tokenId: target.upTokenId,
                  conditionId: target.conditionId),
              PolymarketOutcome(
                  name: 'Down',
                  price: 1 - buttonsUp,
                  tokenId: target.downTokenId,
                  conditionId: target.conditionId),
            ];
      final idx = outcomes.indexWhere((o) => o.name.toLowerCase() == side);
      BetSlipSheet.show(context,
          marketQuestion: target.title,
          marketSlug: target.slug,
          marketImage: target.image,
          outcomes: outcomes,
          initialOutcomeIndex: idx >= 0 ? idx : 0,
          // The short-market funding gate (isShortMarket) keys off it.
          marketEndAt: target.endDate ??
              target.windowStartTime?.add(Duration(minutes: minutes)),
          marketCategory: 'crypto',
          onDeposit: onDeposit,
          source: slipSource);
    }

    void pick(PolyStripRound round) {
      TrackingService.track('predictions_instant_round_picked', params: {
        'which': polyInstantWhich(round),
        'length': length,
        'seconds_to_start':
            round.start - now.toUtc().millisecondsSinceEpoch ~/ 1000,
      });
      ref.read(polyInstantPickedRoundProvider(_choice).notifier).state =
          round.start;
    }

    final liveTokens = [
      if (upTokenId != null && upTokenId.isNotEmpty) upTokenId,
      if (downTokenId != null && downTokenId.isNotEmpty) downTokenId,
      for (final e in ahead.values) ...[
        if (e?.upTokenId case final t? when t.isNotEmpty) t,
        if (e?.downTokenId case final t? when t.isNotEmpty) t,
      ],
    ];

    return CryptoCardOnScreen(
      child: LiveTokenScope(
        tokens: liveTokens,
        child: CryptoOddsScope(
          token: upTokenId,
          child: CryptoOddsScope(
            token: onShow ? null : selectedUpToken,
            child: CompactCryptoCard(
              key: ValueKey('instant-card-$asset-$length'),
              config: config,
              title: l10n.predictUpOrDownLength(asset, length),
              countdown: countdown,
              pastResults: const [],
              loading: predictState == null || event == null,
              priceText: formatCryptoRoundPrice(currentPrice),
              diffText: diff == null
                  ? null
                  : '${diff >= 0 ? '▲' : '▼'} '
                      '${formatCryptoRoundDiff(diff.abs())}',
              diffUp: (diff ?? 0) >= 0,
              targetText: l10n
                  .predictTargetPrice(formatCryptoRoundPrice(priceToBeat)),
              history: predictState?.priceHistory,
              priceToBeat: priceToBeat,
              roundStart: event?.windowStartTime ?? liveRound.start,
              upFrac: buttonsUp,
              nextLabel: line,
              onUp: () => openSide('up'),
              onDown: () => openSide('down'),
              sparkHeight: sparkHeight,
              chartWindow: minutes > 5
                  ? Duration(minutes: minutes + 1)
                  : kBtcPredictChartWindow,
              strip: InstantRoundStrip(
                rounds: rounds,
                selectedStart: selectedStart,
                countdown: countdown,
                onPick: pick,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
