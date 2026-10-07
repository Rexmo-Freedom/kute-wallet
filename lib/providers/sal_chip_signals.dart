import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidHeldPositionsProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider;
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';

// What Sal's opening questions are chosen from. Every read here is
// synchronous and only of state the device already holds: a provider that
// is not alive is skipped, never started, so opening Sal never waits on
// (or causes) a network read. Nothing here leaves the device.

/// The public facts of a Hyperliquid market already on screen.
SalChipSignals salSignalsForHlMarket(HlMarket m) => SalChipSignals(
      dayChangePct: m.prevDayPx > 0 ? m.dayChangePct : null,
      funding: m.isSpot ? null : m.funding,
    );

/// The public facts of a Polymarket event already on screen.
SalChipSignals salSignalsForPolyEvent(PolymarketEvent e) => SalChipSignals(
      oddsChange1d: e.oneDayPriceChange,
      closesAt: e.endDate,
      liveGame: e.isInPlay,
    );

/// Adds the private signals (a position held in this market, the market on
/// the watchlist) to [base]. They only rank the public chips.
SalChipSignals withLocalSalSignals(
  ProviderContainer container,
  AdvisorContext context,
  SalChipSignals base,
) {
  final market = context.toRequestMarket;
  if (market == null) return base;
  final id = market['id']!;
  var holds = base.holdsPosition || context.surface.endsWith('position_detail');
  var watched = base.onWatchlist;
  try {
    if (market['venue'] == 'hyperliquid') {
      holds = holds ||
          container
              .read(hyperliquidHeldPositionsProvider)
              .any((p) => p.coin == id);
      final keys = container.read(hlWatchlistProvider);
      watched =
          watched || keys.contains('perp:$id') || keys.contains('spot:$id');
    } else {
      watched = watched || container.read(polyWatchlistProvider).contains(id);
      if (!holds && container.exists(polymarketTradingProvider)) {
        holds = container
            .read(polymarketActivePositionsProvider)
            .any((p) => p.eventSlug == id);
      }
    }
  } catch (_) {
    // Ranking only: without local state the public order stands.
  }
  return base.withLocal(holdsPosition: holds, onWatchlist: watched);
}

/// Search: the biggest public Hyperliquid movers and the starred perps,
/// from the market list only when it is already loaded.
SalChipSignals searchSalSignals(ProviderContainer container) {
  List<HlMarket> perps = const [];
  List<String> starred = const [];
  try {
    if (container.exists(hyperliquidPerpMarketsProvider)) {
      perps = container.read(hyperliquidPerpMarketsProvider).valueOrNull ??
          const [];
    }
    starred = container.read(hlWatchlistProvider);
  } catch (_) {
    // No chips from markets; the general questions still show.
  }
  SalMarketRef ref(HlMarket m) => SalMarketRef(
      wireCoin: m.wireCoin,
      label: m.coin,
      dayChangePct: m.prevDayPx > 0 ? m.dayChangePct : null);
  final movers = perps
      .where((m) =>
          !m.isLowLiquidity &&
          m.prevDayPx > 0 &&
          m.dayChangePct.abs() >= kSalMoveThreshold)
      .toList()
    ..sort((a, b) => b.dayChangePct.abs().compareTo(a.dayChangePct.abs()));
  final byWire = {for (final m in perps) m.wireCoin: m};
  final watchlist = <SalMarketRef>[
    for (final key in starred.take(10))
      if (key.startsWith('perp:'))
        byWire[key.substring(5)] != null
            ? ref(byWire[key.substring(5)]!)
            : SalMarketRef(
                wireCoin: key.substring(5), label: key.split(':').last),
  ];
  return SalChipSignals(
    movers: [for (final m in movers.take(2)) ref(m)],
    watchlist: watchlist,
  );
}
