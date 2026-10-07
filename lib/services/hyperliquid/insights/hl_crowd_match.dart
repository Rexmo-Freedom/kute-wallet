// lib/services/hyperliquid/insights/hl_crowd_match.dart
//
// Which Polymarket markets are about a Hyperliquid asset, for the chart's
// optional Predictions layers: the odds of the price reaching or dipping
// to a strike by a date (drawn as levels at the strike), and the dates of
// the next Fed decisions and US inflation report. Pure: it works on
// events already read through the app's Polymarket feed.
//
// Matching is deliberately narrow. A market is used only when ALL of
// these hold; anything else is ignored, so an unsure match shows nothing:
//   * the Hyperliquid market is the venue's own perp or spot market of
//     one of [kHlCrowdAssets] (never a builder-dex market that happens to
//     share the ticker);
//   * the event carries that asset's Polymarket tag AND its title is
//     exactly Polymarket's recurring "hit" series for it:
//       "What price will <Asset> hit …?"   outcomes "↑ 100,000" / "↓ 60,000"
//   * the outcome label parses to a strike on the far side of the current
//     price (a reach above it, a dip below it), and its chance is between
//     [kHlCrowdMinChance] and [kHlCrowdMaxChance] (a settled or dead
//     outcome says nothing);
//   * the event is open and ends in the future.
// Macro: "Fed Decision in <Month>?" tagged `fed-rates`, and
// "<Month> Inflation US - Annual" tagged `cpi`.
//
// Dates: Polymarket ends these markets at midnight US Eastern after the
// day in question, stored in UTC. The day shown is therefore the end
// instant less [kHlCrowdDayShift], which lands on the day the market
// names for every series above.

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';

/// An asset the Predictions levels know: its Polymarket tag and the name
/// Polymarket's titles use for it.
typedef HlCrowdAsset = ({String tag, String name});

/// Hyperliquid ticker → Polymarket asset. Only assets whose recurring
/// price series were seen on Polymarket under exactly these names.
const Map<String, HlCrowdAsset> kHlCrowdAssets = {
  'BTC': (tag: 'bitcoin', name: 'Bitcoin'),
  'ETH': (tag: 'ethereum', name: 'Ethereum'),
  'SOL': (tag: 'solana', name: 'Solana'),
  'XRP': (tag: 'xrp', name: 'XRP'),
  'DOGE': (tag: 'dogecoin', name: 'Dogecoin'),
  'HYPE': (tag: 'hyperliquid', name: 'Hyperliquid'),
  'BNB': (tag: 'bnb', name: 'BNB'),
};

/// The Polymarket tags the macro events are read from.
const String kHlCrowdFedTag = 'fed-rates';
const String kHlCrowdCpiTag = 'cpi';

/// An outcome outside this band is settled, dead or says nothing.
const double kHlCrowdMinChance = 0.03;
const double kHlCrowdMaxChance = 0.97;

/// End instant → the day the market names (see the header).
const Duration kHlCrowdDayShift = Duration(hours: 12);

/// Chart levels drawn on each side of the price.
const int kHlCrowdLevelsPerSide = 2;

/// Macro dates kept, soonest first.
const int kHlCrowdMaxDates = 3;

/// The Polymarket asset of [market], or null when the Predictions levels
/// do not cover it.
HlCrowdAsset? hlCrowdAssetFor(HlMarket market) {
  if (market.isHip3 || market.dex.isNotEmpty) return null;
  if (market.category != 'crypto') return null;
  return kHlCrowdAssets[market.coin.toUpperCase()];
}

enum HlCrowdKind { reach, dip }

/// The odds of the price reaching (or dipping to) one strike, with the
/// event they come from.
class HlCrowdLevel {
  final HlCrowdKind kind;

  /// Chance of the outcome, 0 to 1.
  final double chance;
  final double strike;

  /// The day the market names (see [kHlCrowdDayShift]), UTC.
  final DateTime day;

  /// The event to open on tap.
  final PolymarketEvent event;

  const HlCrowdLevel({
    required this.kind,
    required this.chance,
    required this.strike,
    required this.day,
    required this.event,
  });
}

enum HlMacroKind { fedDecision, usInflation }

/// A scheduled macro date, from the Polymarket market about it.
class HlMacroDate {
  final HlMacroKind kind;
  final DateTime day;
  final PolymarketEvent event;
  const HlMacroDate(this.kind, this.day, this.event);
}

/// What the chart's Predictions layers draw for one market.
class HlCrowdView {
  /// Strikes to draw on the price chart, nearest to the price first.
  final List<HlCrowdLevel> levels;

  /// Upcoming Fed decision and US inflation report days, soonest first.
  final List<HlMacroDate> dates;

  const HlCrowdView({this.levels = const [], this.dates = const []});

  static const empty = HlCrowdView();
}

final RegExp _kStrike = RegExp(r'^([↑↓])?\s*\$?(\d[\d,]*(?:\.\d+)?)$');
final RegExp _kFedTitle = RegExp(r'^Fed Decision in [A-Z][a-z]+\?$');
final RegExp _kCpiTitle = RegExp(r'^[A-Z][a-z]+ Inflation US - Annual$');

/// A strike label ("↑ 100,000", "↓ 0.52", "86,000"): its direction mark
/// (null when it has none) and the price. Null when it is anything else.
({String? mark, double strike})? hlCrowdParseStrike(String label) {
  final m = _kStrike.firstMatch(label.trim());
  if (m == null) return null;
  final strike = double.tryParse(m.group(2)!.replaceAll(',', ''));
  if (strike == null || strike <= 0) return null;
  return (mark: m.group(1), strike: strike);
}

bool _open(PolymarketEvent e, DateTime now) {
  final end = e.endDate;
  return e.active && !e.closed && !e.ended && end != null && end.isAfter(now);
}

DateTime _day(DateTime end) => end.toUtc().subtract(kHlCrowdDayShift);

/// The usable outcomes of one of [asset]'s "hit" series events, or
/// nothing when [e] is not one of them.
List<HlCrowdLevel> hlCrowdLevelsOfEvent(
  PolymarketEvent e,
  HlCrowdAsset asset,
  double price,
  DateTime now,
) {
  if (!_open(e, now) || !e.tags.contains(asset.tag)) return const [];
  final title = e.title.trim();
  if (!title.startsWith('What price will ${asset.name} hit ') ||
      !title.endsWith('?')) {
    return const [];
  }
  final day = _day(e.endDate!);
  final out = <HlCrowdLevel>[];
  for (final o in e.outcomes) {
    final parsed = hlCrowdParseStrike(o.name);
    if (parsed == null) continue;
    if (o.price < kHlCrowdMinChance || o.price > kHlCrowdMaxChance) continue;
    // A hit series marks every outcome with its direction.
    final HlCrowdKind kind;
    if (parsed.mark == '↑' && parsed.strike > price) {
      kind = HlCrowdKind.reach;
    } else if (parsed.mark == '↓' && parsed.strike < price) {
      kind = HlCrowdKind.dip;
    } else {
      continue;
    }
    out.add(HlCrowdLevel(
      kind: kind,
      chance: o.price,
      strike: parsed.strike,
      day: day,
      event: e,
    ));
  }
  return out;
}

/// What the Predictions layers draw for [asset] at [price]. A market the
/// levels do not cover ([asset] null) gets the macro dates only.
///
/// [assetEvents] are the open events carrying the asset's tag, and
/// [macroEvents] the open events of the Fed and inflation tags, both most
/// traded first. The levels come from one event only, the most traded
/// "hit" series: the [kHlCrowdLevelsPerSide] strikes nearest the price on
/// each side.
HlCrowdView hlCrowdView({
  required HlCrowdAsset? asset,
  required double price,
  required List<PolymarketEvent> assetEvents,
  required List<PolymarketEvent> macroEvents,
  required DateTime now,
}) {
  if (price <= 0 || !price.isFinite) return HlCrowdView.empty;

  final levels = <HlCrowdLevel>[];
  if (asset != null) {
    for (final e in assetEvents) {
      final of = hlCrowdLevelsOfEvent(e, asset, price, now);
      if (of.isEmpty) continue;
      final up = of.where((l) => l.kind == HlCrowdKind.reach).toList()
        ..sort((a, b) => a.strike.compareTo(b.strike));
      final down = of.where((l) => l.kind == HlCrowdKind.dip).toList()
        ..sort((a, b) => b.strike.compareTo(a.strike));
      levels
        ..addAll(up.take(kHlCrowdLevelsPerSide))
        ..addAll(down.take(kHlCrowdLevelsPerSide));
      levels.sort((a, b) =>
          (a.strike - price).abs().compareTo((b.strike - price).abs()));
      break;
    }
  }

  final dates = <HlMacroDate>[];
  for (final e in macroEvents) {
    if (!_open(e, now)) continue;
    final title = e.title.trim();
    if (_kFedTitle.hasMatch(title) && e.tags.contains(kHlCrowdFedTag)) {
      dates.add(HlMacroDate(HlMacroKind.fedDecision, _day(e.endDate!), e));
    } else if (_kCpiTitle.hasMatch(title) && e.tags.contains(kHlCrowdCpiTag)) {
      dates.add(HlMacroDate(HlMacroKind.usInflation, _day(e.endDate!), e));
    }
  }
  dates.sort((a, b) => a.day.compareTo(b.day));

  return HlCrowdView(
    levels: levels,
    dates: dates.length > kHlCrowdMaxDates
        ? dates.sublist(0, kHlCrowdMaxDates)
        : dates,
  );
}
