import 'package:flutter/foundation.dart';
import 'package:kute/l10n/l10n.dart' show AppLocalizations;
import 'package:kute/models/advisor_context.dart';

export 'package:kute/services/advisor/sal_chip_templates.dart';

/// At most this many opening questions show.
const kSalMaxChips = 4;

/// 24 h price move (as a fraction) from which a market counts as moving.
const kSalMoveThreshold = 0.03;

/// Hourly funding rate (as a fraction) from which funding counts as
/// unusual: four times Hyperliquid's base rate of 0.00125 % an hour.
const kSalFundingExtreme = 0.00005;

/// One-day odds move (probability points as a fraction) from which a
/// prediction market counts as moving.
const kSalOddsMoveThreshold = 0.05;

/// A prediction market closing within this window counts as closing soon.
const kSalClosingSoon = Duration(hours: 24);

/// One opening question. [template] is the allowlisted id the request and
/// analytics carry; null for a fixed help question with no template.
/// [context] is set when the chip asks about a market other than the
/// screen's own (search), so Sal is grounded on that public market.
@immutable
class SalChip {
  final String? template;
  final String text;
  final AdvisorContext? context;
  const SalChip(this.template, this.text, {this.context});

  @override
  String toString() => 'SalChip($template, $text)';
}

/// A public Hyperliquid market a search chip can ask about: its wire coin
/// (the request id) and its public ticker (the chip label).
@immutable
class SalMarketRef {
  final String wireCoin;
  final String label;
  final double? dayChangePct;
  const SalMarketRef(
      {required this.wireCoin, required this.label, this.dayChangePct});
}

/// What the device already knows when Sal opens. Everything here stays on
/// the device: it only chooses and orders which public question shows.
///
/// The public facts (price move, funding, odds move, closing time, a live
/// game) are market data anyone can read. [holdsPosition] and
/// [onWatchlist] are private: they only raise a chip's rank and never
/// appear in a chip's text, the request or analytics.
@immutable
class SalChipSignals {
  final double? dayChangePct;
  final double? funding;
  final double? oddsChange1d;
  final DateTime? closesAt;
  final bool liveGame;
  final bool holdsPosition;
  final bool onWatchlist;
  final List<SalMarketRef> movers;
  final List<SalMarketRef> watchlist;

  const SalChipSignals({
    this.dayChangePct,
    this.funding,
    this.oddsChange1d,
    this.closesAt,
    this.liveGame = false,
    this.holdsPosition = false,
    this.onWatchlist = false,
    this.movers = const [],
    this.watchlist = const [],
  });

  SalChipSignals withLocal({bool? holdsPosition, bool? onWatchlist}) =>
      SalChipSignals(
        dayChangePct: dayChangePct,
        funding: funding,
        oddsChange1d: oddsChange1d,
        closesAt: closesAt,
        liveGame: liveGame,
        holdsPosition: holdsPosition ?? this.holdsPosition,
        onWatchlist: onWatchlist ?? this.onWatchlist,
        movers: movers,
        watchlist: watchlist,
      );

  bool get moving => (dayChangePct?.abs() ?? 0) >= kSalMoveThreshold;
  bool get fundingExtreme => (funding?.abs() ?? 0) >= kSalFundingExtreme;
}

class _Input {
  final AdvisorContext context;
  final SalChipSignals signals;
  final DateTime now;
  final AppLocalizations l10n;
  _Input(this.context, this.signals, this.now, this.l10n);

  late final bool hasMarket = context.toRequestMarket != null;
  late final bool hl = hasMarket && context.marketVenue == 'hyperliquid';
  late final bool pm = hasMarket && context.marketVenue == 'polymarket';
  late final bool spot = hl && context.isSpot;
  late final bool perp = hl && !spot;
  late final String? label = context.publicMarketLabel;
  late final String? orderType = context.educationalOrderType;

  /// A Hyperliquid or Polymarket screen that did not name its market.
  late final bool hlOnly = !hasMarket &&
      (context.surface.startsWith('hl_') ||
          context.surface.startsWith('hyperliquid'));
  late final bool pmOnly = !hasMarket &&
      (context.surface.startsWith('polymarket') ||
          context.surface == 'bet_slip');
  bool get venueOnly => hlOnly || pmOnly;
  bool get closingSoon {
    final at = signals.closesAt;
    return at != null &&
        at.isAfter(now) &&
        at.difference(now) <= kSalClosingSoon;
  }
}

/// One entry of the catalogue: when it applies (public facts only), its
/// base priority, how local signals raise it, and its localized text.
class _Template {
  final String id;
  final int priority;
  final bool Function(_Input i) trigger;
  final int Function(_Input i)? boost;
  final String Function(_Input i) text;
  const _Template(this.id, this.priority, this.trigger, this.text,
      {this.boost});
}

int _if(bool condition, int points) => condition ? points : 0;

final List<_Template> _marketTemplates = [
  // Hyperliquid: the market's public ticker is the only label.
  _Template(
      'hl.moving_today',
      90,
      (i) => i.hl && i.label != null && i.signals.moving,
      (i) => i.l10n.salChipHlMovingToday(i.label!),
      boost: (i) => _if(i.signals.onWatchlist, 10)),
  _Template(
      'hl.funding_flip',
      80,
      (i) => i.perp && i.label != null && (i.signals.funding ?? 0) < 0,
      (i) => i.l10n.salChipHlFundingFlip(i.label!),
      boost: (i) => _if(i.signals.holdsPosition, 15)),
  _Template('hl.funding_explain', 40, (i) => i.perp && i.label != null,
      (i) => i.l10n.salChipHlFundingExplain(i.label!),
      boost: (i) =>
          _if(i.signals.fundingExtreme, 35) + _if(i.signals.holdsPosition, 5)),
  _Template('hl.protect_position', 20, (i) => i.perp && i.label != null,
      (i) => i.l10n.salChipHlProtectPosition(i.label!),
      boost: (i) => _if(i.signals.holdsPosition, 75)),
  _Template('hl.liquidation_explain', 30, (i) => i.perp && i.label != null,
      (i) => i.l10n.salChipHlLiquidationExplain(i.label!),
      boost: (i) => _if(i.signals.holdsPosition, 60)),
  _Template('hl.what_drives', 55, (i) => i.hl && i.label != null,
      (i) => i.l10n.salChipHlWhatDrives(i.label!),
      boost: (i) => _if(i.signals.onWatchlist, 25)),
  _Template('hl.compare_related', 15, (i) => i.hl && i.label != null,
      (i) => i.l10n.salChipHlCompareRelated(i.label!),
      boost: (i) => _if(i.signals.onWatchlist, 10)),
  // Polymarket: the screen shows the market, so the text says "this market".
  _Template('pm.live_game', 95, (i) => i.pm && i.signals.liveGame,
      (i) => i.l10n.salChipPmLiveGame),
  _Template('pm.closing_soon', 88, (i) => i.pm && i.closingSoon,
      (i) => i.l10n.salChipPmClosingSoon),
  _Template(
      'pm.odds_moving',
      85,
      (i) =>
          i.pm && (i.signals.oddsChange1d?.abs() ?? 0) >= kSalOddsMoveThreshold,
      (i) => i.l10n.salChipPmOddsMoving,
      boost: (i) =>
          _if(i.signals.onWatchlist, 10) + _if(i.signals.holdsPosition, 10)),
  _Template('pm.resolution_rules', 60, (i) => i.pm,
      (i) => i.l10n.salChipPmResolutionRules),
  _Template(
      'pm.what_moves_it', 50, (i) => i.pm, (i) => i.l10n.salChipPmWhatMovesIt,
      boost: (i) =>
          _if(i.signals.holdsPosition, 40) + _if(i.signals.onWatchlist, 15)),
  _Template('pm.related_markets', 20, (i) => i.pm,
      (i) => i.l10n.salChipPmRelatedMarkets,
      boost: (i) => _if(i.signals.onWatchlist, 5)),
  // Mechanics. On an order slip the order type leads.
  _Template('edu.limit_order', 10, (i) => i.hl || i.pm || i.venueOnly, (i) {
    final type = i.orderType;
    if (type != null &&
        type != 'market' &&
        type != 'limit' &&
        i.label != null) {
      return i.l10n
          .salChipEduOrderType(salOrderTypeName(i.l10n, type), i.label!);
    }
    return i.l10n.salChipEduMarketVsLimit;
  }, boost: (i) => _if(i.orderType != null, 200)),
  _Template('edu.leverage', 12, (i) => i.perp || i.hlOnly,
      (i) => i.l10n.salChipEduLeverage,
      boost: (i) => _if(i.orderType != null, 5)),
  _Template('edu.funding', 5, (i) => (i.perp && i.label == null) || i.hlOnly,
      (i) => i.l10n.salChipEduFunding),
  _Template('edu.prediction_basics', 8, (i) => i.pm || i.pmOnly,
      (i) => i.l10n.salChipEduPredictionBasics),
];

/// The order type's name inside a sentence, in the app language.
String salOrderTypeName(AppLocalizations l10n, String type) =>
    l10n.salOrderTypeName(switch (type) {
      'stop_market' => 'stopMarket',
      'stop_limit' => 'stopLimit',
      'take_profit_market' => 'takeProfitMarket',
      'take_profit_limit' => 'takeProfitLimit',
      _ => type,
    });

/// Picks the opening questions for a screen. Deterministic and synchronous:
/// opening Sal never waits on inference or a network read.
class SalChipCatalogue {
  SalChipCatalogue._();

  static List<SalChip> select(
    AdvisorContext context,
    AppLocalizations l10n, {
    SalChipSignals signals = const SalChipSignals(),
    DateTime? now,
  }) {
    final input = _Input(context, signals, now ?? DateTime.now(), l10n);
    if (context.surface == 'search') return _search(input);
    if (input.hasMarket || input.venueOnly) return _ranked(input);
    final s = context.surface;
    if (s.contains('backup')) {
      return [
        SalChip(null, l10n.salChipRecoveryPhrase),
        SalChip(null, l10n.salChipBackupHow),
        SalChip(null, l10n.salChipRecoveryPrivate),
      ];
    }
    if (s.contains('transaction') ||
        s.contains('tx_detail') ||
        s == 'send_review') {
      return [
        SalChip(null, l10n.salChipNetworkConfirmation),
        SalChip(null, l10n.salChipNetworkFees),
        SalChip(null, l10n.salChipTxPending),
      ];
    }
    return _general(l10n);
  }

  static List<SalChip> _general(AppLocalizations l10n) => [
        SalChip('wallet.receive', l10n.salChipWalletReceive),
        SalChip('wallet.send', l10n.salChipWalletSend),
        SalChip(null, l10n.salChipStocksVsPerps),
        SalChip('edu.prediction_basics', l10n.salChipEduPredictionBasics),
      ];

  static List<SalChip> _ranked(_Input input) {
    final scored = <(int, int, _Template)>[];
    for (var k = 0; k < _marketTemplates.length; k++) {
      final t = _marketTemplates[k];
      if (!t.trigger(input)) continue;
      scored.add((t.priority + (t.boost?.call(input) ?? 0), k, t));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
    return [
      for (final (_, _, t) in scored.take(kSalMaxChips))
        SalChip(t.id, t.text(input)),
    ];
  }

  /// Search: public movers and watchlist markets already loaded, then the
  /// general questions.
  static List<SalChip> _search(_Input input) {
    final l10n = input.l10n;
    AdvisorContext grounded(SalMarketRef m) => AdvisorContext(
          surface: 'search',
          marketVenue: 'hyperliquid',
          marketId: m.wireCoin,
          marketDisplayName: m.label,
        );
    final chips = <SalChip>[];
    final used = <String>{};
    // A starred market that is moving leads; then the biggest movers; then
    // the rest of the watchlist.
    final watched = [...input.signals.watchlist]..sort((a, b) =>
        (b.dayChangePct?.abs() ?? 0).compareTo(a.dayChangePct?.abs() ?? 0));
    void add(String template, SalMarketRef m, String text) {
      if (chips.length >= 2 || !used.add(m.wireCoin)) return;
      final context = grounded(m);
      if (context.toRequestMarket == null) return;
      chips.add(SalChip(template, text, context: context));
    }

    for (final m in watched) {
      if ((m.dayChangePct?.abs() ?? 0) >= kSalMoveThreshold) {
        add('search.watchlist_news', m,
            l10n.salChipSearchWatchlistNews(m.label));
      }
    }
    for (final m in input.signals.movers) {
      add('search.top_movers', m, l10n.salChipHlMovingToday(m.label));
    }
    for (final m in watched) {
      add('search.watchlist_news', m, l10n.salChipSearchWatchlistNews(m.label));
    }
    return [...chips, ..._general(l10n)].take(kSalMaxChips).toList();
  }

  /// The line above the chips, in the app language.
  static String introduction(AdvisorContext context, AppLocalizations l10n) {
    if (context.toRequestMarket == null) return l10n.salIntroGeneral;
    final type = context.educationalOrderType;
    if (type != null) return l10n.salIntroOrder(salOrderTypeName(l10n, type));
    final label = context.publicMarketLabel;
    return label == null ? l10n.salIntroThisMarket : l10n.salIntroMarket(label);
  }
}
