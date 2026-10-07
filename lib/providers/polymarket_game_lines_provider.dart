// The game centre's main lines: the moneyline, the main spread and the main
// total of a match. Polymarket lists a match's spreads and totals as sibling
// markets in the same event (`sportsMarketType` moneyline / spreads /
// totals, each with its `line`), and names the main line of each kind in
// `bestLines` when the event is read with `include_best_lines=true`.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart';

/// One two-sided market of a match, as a compact row shows it.
class PolyGameLine {
  /// moneyline, spreads or totals.
  final String kind;

  /// The market's question, e.g. "Spread: Colts (-4.5)".
  final String question;

  /// Gamma `line` (-4.5, 46.5); null on the moneyline.
  final double? line;

  /// The two sides' names ("Colts" / "Commanders", "Over" / "Under").
  final String sideA;
  final String sideB;
  final double priceA;
  final double priceB;
  final String? tokenA;
  final String? tokenB;
  final String? conditionId;
  final String? gammaMarketId;

  /// In-play order delay in seconds (Gamma `secondsDelay`); 0 when none.
  final int secondsDelay;

  const PolyGameLine({
    required this.kind,
    required this.question,
    this.line,
    required this.sideA,
    required this.sideB,
    required this.priceA,
    required this.priceB,
    this.tokenA,
    this.tokenB,
    this.conditionId,
    this.gammaMarketId,
    this.secondsDelay = 0,
  });

  /// This market as an outcome of its event, the shape the detail sheet
  /// opens as its own Yes/No market.
  PolymarketOutcome toOutcome() => PolymarketOutcome(
        name: question,
        price: priceA,
        tokenId: tokenA,
        noTokenId: tokenB,
        conditionId: conditionId,
        gammaMarketId: gammaMarketId,
      );

  /// "-4.5", "+3.5", "46.5".
  String get lineText {
    final l = line;
    if (l == null) return '';
    final s = l == l.roundToDouble() ? l.toStringAsFixed(0) : '$l';
    return kind == 'spreads' && l > 0 ? '+$s' : s;
  }
}

class PolyGameLines {
  final PolyGameLine? moneyline;
  final PolyGameLine? spread;
  final PolyGameLine? total;

  /// The winner market once it has closed: Polymarket closes a game's
  /// moneyline minutes after the final whistle, and [moneyline] (a row to
  /// bet on) is then gone. The game's chart still draws it.
  final PolyGameLine? settledMoneyline;

  /// The Over token of the event's most even traded totals line
  /// ([pickOverToken]), when this was read from Gamma; the momentum's
  /// pressure signal starts from it instead of reading the event again.
  final String? overToken;

  /// When these lines were read from Gamma (epoch ms); null when they
  /// were laid out from the event the card had ([fromEvent]).
  final int? readAtMs;

  const PolyGameLines({
    this.moneyline,
    this.spread,
    this.total,
    this.settledMoneyline,
    this.overToken,
    this.readAtMs,
  });

  /// The winner market for the game's chart and its Momentum: the open
  /// moneyline, else the closed one of a finished game.
  PolyGameLine? get winner => moneyline ?? settledMoneyline;

  bool get isEmpty => moneyline == null && spread == null && total == null;

  List<PolyGameLine> get rows =>
      [if (moneyline != null) moneyline!, if (spread != null) spread!, if (total != null) total!];

  /// The largest in-play delay among the rows (seconds).
  int get secondsDelay => rows.fold(
      0, (m, r) => r.secondsDelay > m ? r.secondsDelay : m);

  static const empty = PolyGameLines();

  /// Picks the lines out of one raw Gamma event (with `bestLines` when it
  /// was read with `include_best_lines=true`). Without `bestLines` the main
  /// line of a kind is the one priced closest to even, which is how
  /// Polymarket chooses it.
  static PolyGameLines fromRawEvent(Map<String, dynamic> e,
      {int? readAtMs}) {
    final every = (e['markets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final best = <String, double>{};
    for (final b in (e['bestLines'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final type = b['lineType']?.toString() ?? '';
      final line = _num(b['line']);
      if (line == null) continue;
      // "spreads-away" / "spreads-home" / "totals"; first-half, quarter
      // and team totals carry a prefix and are not the main lines.
      if (type.startsWith('spreads')) best.putIfAbsent('spreads', () => line);
      if (type == 'totals') best['totals'] = line;
    }
    return _fromMarkets(every, best,
        overToken: pickOverToken(e), readAtMs: readAtMs);
  }

  /// The lines of [event] laid out from the event itself, as the feed
  /// card has it ([PolymarketOutcome.marketLine]): the sheet draws its
  /// board and its chart from these at once, and the Gamma read
  /// ([polyGameLinesProvider]) refines them when it lands (its
  /// `bestLines`, the in-play delay, the Over token). Without
  /// `bestLines` the main line of a kind is the one priced closest to
  /// even, which is how Polymarket chooses it. Empty for an event whose
  /// outcomes carry no sports type (search results). Memoized per event.
  static PolyGameLines fromEvent(PolymarketEvent event) =>
      _fromEventMemo[event] ??= _fromEvent(event);

  static final Expando<PolyGameLines> _fromEventMemo = Expando();

  static PolyGameLines _fromEvent(PolymarketEvent event) {
    final markets = <Map<String, dynamic>>[
      for (final o in event.outcomes)
        if (o.marketLine case final l?)
          {
            'sportsMarketType': l.kind,
            'question': l.question,
            'line': l.line,
            'outcomes': l.sides,
            'outcomePrices': [for (final p in l.prices) '$p'],
            'clobTokenIds': [
              if (o.tokenId != null) o.tokenId!,
              if (o.noTokenId != null) o.noTokenId!,
            ],
            'conditionId': o.conditionId,
            'id': o.gammaMarketId,
            'closed': l.closed,
          },
    ];
    if (markets.isEmpty) return empty;
    return _fromMarkets(markets, const {});
  }

  static PolyGameLines _fromMarkets(
    List<Map<String, dynamic>> every,
    Map<String, double> best, {
    String? overToken,
    int? readAtMs,
  }) {
    final markets = every.where((m) => m['closed'] != true).toList();

    PolyGameLine? pick(String kind) {
      final candidates = [
        for (final m in markets)
          if (m['sportsMarketType'] == kind) _lineOf(kind, m)
      ].whereType<PolyGameLine>().toList();
      if (candidates.isEmpty) return null;
      final target = best[kind];
      var pool = candidates;
      if (target != null) {
        final matching = candidates
            .where((c) => c.line != null && (c.line!.abs() - target.abs()).abs() < 1e-6)
            .toList();
        if (matching.isNotEmpty) pool = matching;
      }
      pool.sort((a, b) =>
          (a.priceA - 0.5).abs().compareTo((b.priceA - 0.5).abs()));
      return pool.first;
    }

    final moneyline = pick('moneyline');
    PolyGameLine? settled;
    if (moneyline == null) {
      for (final m in every) {
        if (m['closed'] == true && m['sportsMarketType'] == 'moneyline') {
          settled = _lineOf('moneyline', m);
          if (settled != null) break;
        }
      }
    }
    return PolyGameLines(
      moneyline: moneyline,
      spread: pick('spreads'),
      total: pick('totals'),
      settledMoneyline: settled,
      overToken: overToken,
      readAtMs: readAtMs,
    );
  }

  static PolyGameLine? _lineOf(String kind, Map<String, dynamic> m) {
    final names = _strings(m['outcomes']);
    final prices = _strings(m['outcomePrices']).map(double.tryParse).toList();
    final tokens = _strings(m['clobTokenIds']);
    if (names.length != 2 || prices.length != 2) return null;
    if (prices[0] == null || prices[1] == null) return null;
    return PolyGameLine(
      kind: kind,
      question: (m['question'] as String?)?.trim() ?? '',
      line: _num(m['line']),
      sideA: names[0],
      sideB: names[1],
      priceA: prices[0]!,
      priceB: prices[1]!,
      tokenA: tokens.isNotEmpty ? tokens[0] : null,
      tokenB: tokens.length > 1 ? tokens[1] : null,
      conditionId: m['conditionId'] as String?,
      gammaMarketId: m['id']?.toString(),
      secondsDelay: _num(m['secondsDelay'])?.toInt() ?? 0,
    );
  }

  static double? _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static List<String> _strings(dynamic v) {
    try {
      final parsed = v is String ? jsonDecode(v) : v;
      if (parsed is List) return [for (final x in parsed) '$x'];
    } catch (_) {}
    return const [];
  }
}

/// The main lines of the match with event slug [slug], read from Gamma
/// with `include_best_lines=true` (a parameter the Kute feed does not
/// pass on). Empty when the read fails or the event has none. Kept for
/// five minutes after the last screen on it closes, so reopening the
/// game reads nothing.
///
/// Screens read a game's lines through [polyGameLinesFor], which lays
/// them out from the event at once and takes this read when it lands.
final polyGameLinesProvider =
    FutureProvider.autoDispose.family<PolyGameLines, String>((ref, slug) async {
  if (slug.isEmpty) return PolyGameLines.empty;
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() => timer = Timer(const Duration(minutes: 5), link.close));
  ref.onResume(() => timer?.cancel());
  ref.onDispose(() => timer?.cancel());
  try {
    final page = await PolymarketModel.readGammaKeysetPage(
      'events',
      {'slug': slug, 'include_best_lines': 'true'},
      limit: 1,
      direct: true,
    );
    if (page.rows.isEmpty) return PolyGameLines.empty;
    return PolyGameLines.fromRawEvent(page.rows.first,
        readAtMs: DateTime.now().millisecondsSinceEpoch);
  } catch (_) {
    return PolyGameLines.empty;
  }
});

/// The lines of [event]'s game for a screen: the Gamma read
/// ([polyGameLinesProvider]) once it has answered with any, and until
/// then (or when it fails) the lines laid out from the event itself
/// ([PolyGameLines.fromEvent]), so the board and the chart never wait on
/// a second read of a game the card already had.
PolyGameLines polyGameLinesFor(WidgetRef ref, PolymarketEvent event) {
  final read = ref.watch(polyGameLinesProvider(event.slug)).valueOrNull;
  if (read != null && (!read.isEmpty || read.settledMoneyline != null)) {
    return read;
  }
  return PolyGameLines.fromEvent(event);
}

/// A totals line counts as traded when its book is this tight. Polymarket
/// lists many totals lines per game and most sit empty (spread 0.99,
/// price 0.495): those say nothing.
const double kOverMaxSpread = 0.10;

/// The Over token of the event's most even traded totals line, or null
/// when [rawEvent] has none.
String? pickOverToken(Map<String, dynamic> rawEvent) {
  String? best;
  var bestDistance = double.infinity;
  for (final m in (rawEvent['markets'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()) {
    if (m['sportsMarketType'] != 'totals' || m['closed'] == true) continue;
    final spread = PolyGameLines._num(m['spread']);
    if (spread == null || spread > kOverMaxSpread) continue;
    final names = PolyGameLines._strings(m['outcomes']);
    final prices =
        PolyGameLines._strings(m['outcomePrices']).map(double.tryParse).toList();
    final tokens = PolyGameLines._strings(m['clobTokenIds']);
    if (names.length != 2 || prices.length != 2 || tokens.length != 2) {
      continue;
    }
    final over = names.indexWhere((n) => n.toLowerCase() == 'over');
    final price = over < 0 ? null : prices[over];
    if (price == null || tokens[over].isEmpty) continue;
    final distance = (price - 0.5).abs();
    // A line already decided either way no longer moves with the game.
    if (distance > 0.42) continue;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = tokens[over];
    }
  }
  return best;
}
