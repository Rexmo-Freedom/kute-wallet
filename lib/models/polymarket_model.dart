import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kute/services/polymarket/live_game/feed_score_order.dart';
import 'package:kute/services/polymarket/livestream_source.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket/shown_price.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart'
    show CryptoPriceFeed, kCryptoTwapLookbackSeconds;
// lib/models/polymarket_model.dart
//
// Polymarket API client for fetching prediction market data.
// Uses the polybrainz_polymarket package (Gamma API) + direct HTTP for CLOB
// price history (package bug: sends 'token_id' but API expects 'market').

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:kute/helpers/polymarket_artwork.dart';
import 'package:kute/helpers/prediction_results.dart'
    show closedPredictionWon, predictionClosedBySale, predictionPriceSettled;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    hide EthereumAddress, PolymarketConstants;
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

// Polybrainz removal (#199), step 1: structural copies of these types now
// live in lib/models/polymarket/. The re-export block below still points
// at the polybrainz package so direct-importing call sites (e.g.
// polymarket_trading_provider.dart, transaction_cache_codec.dart) stay
// type-compatible during this transition. Step 2 will switch each call
// site to the local types and then flip this re-export to:
//     export 'package:kute/models/polymarket/polymarket.dart' show ...;
export 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show
        OrderBook,
        OrderSummary,
        TradeRecord,
        ClobWebSocket,
        WsMessage,
        BookMessage,
        LastTradePriceMessage,
        PriceChangeMessage,
        TradeWsMessage,
        OrderWsMessage,
        OrderActionType,
        ClobWsConnectionState,
        OrderSide,
        OrderType,
        OrderResponse,
        Order,
        Position,
        ClosedPosition,
        HoldingsValue,
        ApiCredentials,
        HdWallet,
        WalletCredentials,
        SignedOrder,
        L2Auth,
        Activity,
        ActivityType,
        Tag,
        TagOrderBy,
        Comment,
        Profile;

/// A game's sub-market as Gamma types it (`sportsMarketType` moneyline,
/// spreads, totals, …), kept on its outcome so the game centre can lay out
/// its main lines from the event the card already has, before (or
/// without) reading the event again.
class PolymarketMarketLine {
  /// Gamma `sportsMarketType`.
  final String kind;

  /// The market's question ("Spread: Saints (-1.5)").
  final String question;

  /// Gamma `line` (-1.5, 47.5); null on a moneyline.
  final double? line;

  /// The market's own two outcome names and prices, in Gamma's order.
  final List<String> sides;
  final List<double> prices;
  final bool closed;

  const PolymarketMarketLine({
    required this.kind,
    required this.question,
    this.line,
    this.sides = const [],
    this.prices = const [],
    this.closed = false,
  });
}

class PolymarketOutcome {
  /// Public Gamma market ID; shared by both sides of one outcome market.
  final String? gammaMarketId;
  final String name; // "Yes", "No", "RBLS", "SAW2", etc.
  final double price; // 0-1 probability (YES price for multi-outcome sub-markets)
  final String? tokenId; // YES token id for multi-outcome sub-markets
  final String? noTokenId; // NO token id (only set on multi-outcome sub-markets)
  final String? imageUrl; // Per-candidate image (only set on multi-outcome sub-markets)
  final double? volume; // Per-candidate 24h volume
  final String? conditionId; // Per-candidate conditionId (for placing Yes/No orders)

  /// The sub-market's sports type and line, on a game's markets only.
  final PolymarketMarketLine? marketLine;

  /// Its book is wider than 10¢ and it has never traded, so Polymarket
  /// shows no chance for it ([polyGammaShownPrice]): a list writes "—"
  /// and puts it last. [price] is then Gamma's own figure, kept as the
  /// slip's starting point only.
  final bool unpriced;

  const PolymarketOutcome({
    this.gammaMarketId,
    required this.name,
    required this.price,
    this.tokenId,
    this.noTokenId,
    this.imageUrl,
    this.volume,
    this.conditionId,
    this.marketLine,
    this.unpriced = false,
  });

  /// True when this outcome came from a binary YES/NO sub-market (i.e. a
  /// candidate in a multi-outcome event).
  bool get hasYesNo => noTokenId != null && noTokenId!.isNotEmpty;
}

class PolymarketTopMarket {
  final String question;
  final double yesPrice;
  final double noPrice;
  final double volume;
  final String? imageUrl;
  final String conditionId;
  final String? yesTokenId;
  final String? noTokenId;

  const PolymarketTopMarket({
    required this.question,
    required this.yesPrice,
    required this.noPrice,
    required this.volume,
    this.imageUrl,
    required this.conditionId,
    this.yesTokenId,
    this.noTokenId,
  });
}

/// A sports/esports team on an event, from Gamma's `teams` array. Carries
/// the real crest logo so the vs-header shows actual badges instead of
/// initial placeholders.
/// Words a club's name carries that say what it is, not which one
/// ("Leeds United FC", "AFC Bournemouth").
const Set<String> kPolyClubTags = {'fc', 'afc', 'cf', 'sc', 'club'};

/// Whether [side] reads as one side of a match title rather than part of
/// a question that mentions one: at most four words and 30 characters.
/// A club tag ("FC", "AFC") and a bare "&" are not counted as words, so
/// "Brighton & Hove Albion FC" is a team.
bool polyLooksLikeTeamName(String side) {
  final s = side.trim();
  if (s.isEmpty || s.length > 30) return false;
  final words = s.split(RegExp(r'\s+')).where((w) =>
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(w) &&
      !kPolyClubTags.contains(w.toLowerCase().replaceAll('.', '')));
  return words.length <= 4;
}

class PolymarketTeam {
  final String name;
  final String? logo;
  final String? abbreviation;
  final String? alias;
  final String? ordering; // 'home' | 'away'

  const PolymarketTeam({
    required this.name,
    this.logo,
    this.abbreviation,
    this.alias,
    this.ordering,
  });

  factory PolymarketTeam.fromJson(Map<String, dynamic> j) {
    return PolymarketTeam(
      name: (j['name'] as String?) ?? '',
      logo: polymarketArtworkUrl(j['logo']) ?? polymarketArtworkFromJson(j),
      abbreviation: j['abbreviation'] as String?,
      alias: j['alias'] as String?,
      ordering: j['ordering'] as String?,
    );
  }
}

/// Periods Gamma and the sports feed send for games that are not running:
/// not started, finished, cancelled, postponed, abandoned, awarded.
const Set<String> kPolyNotInPlayPeriods = {
  'NS', 'FT', 'VFT', 'AET', 'AP', 'CAN', 'CANC', 'PST', 'POST', 'ABD',
  'AWD', 'FINAL', 'F', 'END', 'ENDED',
};

/// False when [period] says the game is not running ([kPolyNotInPlayPeriods]);
/// true otherwise, including when there is no period.
bool polyPeriodMayBeInPlay(String? period) {
  final p = period?.trim().toUpperCase() ?? '';
  return !kPolyNotInPlayPeriods.contains(p);
}

class PolymarketEvent {
  final String id;
  final String slug;
  final String title;
  final String? imageUrl;
  final double volume;
  final double volume24hr;
  final double liquidity;
  final String category;
  /// Scheduled start/kickoff (Gamma `startDate`). For sports this is the
  /// kickoff; for most non-sports markets it is the market open time (already
  /// past). Null when Gamma omits it. Used to gate LIVE / "Ending soon" /
  /// "Starts in" affordances so a not-yet-started game never reads as live.
  final DateTime? startDate;

  /// A game's kickoff (Gamma market `gameStartTime`, else event
  /// `startTime`). Gamma's event `startDate` is when the market opened,
  /// often weeks before the game, so anything that needs the game's own
  /// window reads this. Null for non-sports events.
  final DateTime? gameStart;

  /// The event's own kickoff (Gamma event `startTime`, which the Kute feed
  /// passes through). Null when the event does not carry one.
  final DateTime? startTime;

  /// When the game is played, as the app shows it: the event's own
  /// [startTime], else [gameStart] (which falls back to the market's
  /// `gameStartTime`). Null when no kickoff is known.
  DateTime? get kickoff => startTime ?? gameStart;

  /// When a game was seen to finish (Gamma `finishedTimestamp`). Null
  /// while it has not, and when the feed does not carry it.
  final DateTime? finishedAt;
  final DateTime? endDate;
  final bool active;
  /// Gamma `closed` flag — the single reliable "this market has settled"
  /// signal. Distinct from [ended] (which Gamma sets on the underlying game
  /// finishing): a market can be `closed:true` while `ended` stays false/null,
  /// e.g. a geopolitical market that resolved early. Used by the resolved-
  /// market filter so a truly-settled market (e.g. a ceasefire question that
  /// landed at 100%) is hidden from active browse / search instead of being
  /// shown as a tappable card the CLOB would reject.
  final bool closed;
  final String? description;
  final String conditionId;
  final List<PolymarketOutcome> outcomes;
  /// Live broadcast URL (Twitch/YouTube/Kick) when the event is streaming —
  /// derived from Gamma's `resolutionSource`, which for live esports /
  /// sports events is the channel URL. Null for events without a stream.
  final String? streamUrl;
  /// Gamma `live` flag — true while the event is actively broadcasting.
  final bool isLive;
  /// Stable numeric id of the underlying game, used to join the live sports
  /// WS feed (`SportsMatchUpdate.gameId`) to this event, and to collapse
  /// sibling market fragments of the same match into a single feed card.
  /// Null for non-sports / outright events.
  final int? gameId;
  /// Gamma `eventMetadata.gameId` — a string id ("id2705074469517978") that
  /// some sports (cricket) carry instead of the numeric [gameId]. The live
  /// sports WS sends it as `metadataGameId` with no `gameId`, so it is the
  /// only join for those games' live scores.
  final String? metadataGameId;
  /// Live scoreline straight from Gamma, e.g. "1-1" (soccer) or
  /// "6-3, 3-6, 2-6" (tennis). Seeds the detail header before the WS ticks.
  final String? score;
  /// Match period from Gamma, e.g. "1H", "HT", "Q4", "FT".
  final String? period;
  /// In-period elapsed time from Gamma when present mid-game, e.g. "36'".
  final String? elapsed;
  /// Gamma `ended` flag — the game has finished (distinct from market close).
  final bool ended;
  /// Teams (with crest logos) for sports/esports matches; empty otherwise.
  final List<PolymarketTeam> teams;
  /// True for the synthetic Yes/No event we build when drilling into a single
  /// WDL / candidate outcome. Suppresses sports-team detection so the detail
  /// sheet shows a plain Yes/No (its title is a single question like "Will the
  /// match end in a draw?", which the vs-parser otherwise garbles).
  final bool isSyntheticBinary;

  /// Gamma `negRisk` — the event's markets settle on the negRisk CTF
  /// exchange, which changes the EIP-712 verifying contract orders must
  /// be signed against. Passed down to order placement as the fallback
  /// when the CLOB /neg-risk probe fails (defaulting to false there
  /// signs against the wrong exchange). False when Gamma omits it.
  final bool negRisk;

  /// Gamma tag slugs, in the event's order (analytics: kind of bet).
  final List<String> tags;

  /// How far the lead outcome's price moved in the last 24 h, as a
  /// fraction (0.18 is 18 points). Null when the read did not carry it:
  /// the Kute backend feed trims Gamma's `oneDayPriceChange`.
  final double? oneDayPriceChange;

  /// Gamma series id of a recurring event (a league season, a crypto
  /// window series); groups Live cards under their league.
  final String? seriesId;

  /// Running count of a count market ("Elon Musk # of tweets"), from Gamma
  /// `tweetCount`; null on every other market.
  final int? tweetCount;

  const PolymarketEvent({
    required this.id,
    required this.slug,
    required this.title,
    this.imageUrl,
    required this.volume,
    this.volume24hr = 0,
    required this.liquidity,
    required this.category,
    this.startDate,
    this.gameStart,
    this.startTime,
    this.finishedAt,
    this.endDate,
    this.active = true,
    this.closed = false,
    this.description,
    required this.conditionId,
    required this.outcomes,
    this.streamUrl,
    this.isLive = false,
    this.gameId,
    this.metadataGameId,
    this.score,
    this.period,
    this.elapsed,
    this.ended = false,
    this.negRisk = false,
    this.teams = const [],
    this.isSyntheticBinary = false,
    this.tags = const [],
    this.oneDayPriceChange,
    this.seriesId,
    this.tweetCount,
  });

  /// True once the event's scheduled start has passed. A null [startDate]
  /// (non-dated / non-sports markets) is treated as already started so those
  /// markets behave exactly as before — only events that ship a real future
  /// startDate are gated as "not started yet".
  bool get hasStarted {
    final s = startDate;
    return s == null || !s.isAfter(DateTime.now());
  }

  /// Real in-play signal for sports/esports: the game has actually kicked off
  /// (a live score or period is seeded) and hasn't ended. This is the
  /// authoritative "has started" signal for sports — Gamma's bare `live` flag
  /// fires pre-kickoff and is unreliable, so it must never gate LIVE alone.
  ///
  /// Gamma also seeds a period on games that are not running: "NS" (not
  /// started), "FT" / "VFT" (finished), "CAN" (cancelled), "PST"
  /// (postponed). Those are never in play.
  bool get isInPlay {
    if (ended) return false;
    if (!polyPeriodMayBeInPlay(period)) return false;
    final hasScore = score?.trim().isNotEmpty ?? false;
    final hasPeriod = period?.trim().isNotEmpty ?? false;
    return hasScore || hasPeriod;
  }

  /// True when the category is a sports / esports one — the set the matchup
  /// rendering keys off.
  bool get isSportsCategory {
    final cat = category.toLowerCase();
    if (cat.contains('sport')) return true;
    const exact = {
      'nfl', 'nba', 'soccer', 'mlb', 'nhl', 'ufc', 'mma', 'tennis', 'f1', 'golf'
    };
    return exact.contains(cat);
  }

  /// True when the title is a genuine head-to-head matchup ("Team A vs Team
  /// B") rather than a novelty / prop market that merely MENTIONS one (e.g.
  /// "What will the announcers say during Scotland vs Brazil World Cup
  /// Match?"). Sides must be short proper-noun names with no trailing "?".
  /// Lets the search row (matchup → flag-pair art, else neutral glyph) and the
  /// detail sheet's VS header agree on what counts as a real matchup.
  bool get looksLikeMatchup {
    if (isSyntheticBinary) return false;
    final t = title.replaceFirst(RegExp(r'^[A-Za-z0-9\- ]+:\s+'), '');
    if (t.trimRight().endsWith('?')) return false;
    final m =
        RegExp(r'^(.+?)\s+vs\.?\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (m == null) return false;
    String clean(String s) => s
        .replaceFirst(RegExp(r'\s+-\s+.*$'), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '')
        .trim();
    return polyLooksLikeTeamName(clean(m.group(1)!)) &&
        polyLooksLikeTeamName(clean(m.group(2)!));
  }

  /// Resolves a team's crest [logo] by fuzzy-matching [name] against the
  /// event's `teams`. Returns null if there's no team data or no match.
  String? teamLogoFor(String name) => logoFromTeams(teams, name);

  /// Static variant so callers can resolve against a team list that didn't
  /// come from this event (e.g. teams lazily re-fetched by slug because the
  /// search API path doesn't include them).
  static String? logoFromTeams(List<PolymarketTeam> teams, String name) {
    final n = _teamName(name);
    if (n.isEmpty) return null;
    final exact = teams.where((team) =>
        team.logo?.isNotEmpty == true &&
        [_teamName(team.name), _teamName(team.alias ?? ''),
          _teamName(team.abbreviation ?? '')].contains(n)).toList();
    if (exact.length == 1) return exact.single.logo;
    if (exact.length > 1) return null;
    // A shared club suffix (FC/CF/SC) is not an identity. Only accept a
    // shortened name when it identifies one team in this event unambiguously.
    final words = _teamWords(name);
    if (words.isEmpty) return null;
    final matches = teams.where((team) {
      if (team.logo?.isNotEmpty != true) return false;
      return [team.name, team.alias ?? ''].any((candidate) {
        final other = _teamWords(candidate);
        return other.isNotEmpty &&
            (other.containsAll(words) || words.containsAll(other));
      });
    }).toList();
    return matches.length == 1 ? matches.single.logo : null;
  }

  static String _teamName(String name) => name.toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

  static Set<String> _teamWords(String name) => _teamName(name).split(' ')
      .where((word) => word.isNotEmpty &&
          !{'fc', 'cf', 'afc', 'sc', 'club'}.contains(word)).toSet();

  /// Crest whose team NAME appears inside free text (a market question like
  /// "Will Portugal win on 2026-07-06?"). Safer than [logoFromTeams] for
  /// sentences (no abbreviation fuzz).
  static String? logoForText(List<PolymarketTeam> teams, String text) {
    final sentence = ' ${_teamName(text)} ';
    final matches = teams.where((team) => team.logo?.isNotEmpty == true &&
        [team.name, team.alias ?? ''].any((name) {
          final n = _teamName(name);
          return n.isNotEmpty && sentence.contains(' $n ');
        })).toList();
    return matches.length == 1 ? matches.single.logo : null;
  }

  /// The highest-priced (leading) outcome — the candidate whose portrait /
  /// crest best represents a multi-outcome event's thumbnail.
  PolymarketOutcome? get _leadingOutcomeByPrice {
    if (outcomes.isEmpty) return null;
    final sorted = [...outcomes]..sort((a, b) => b.price.compareTo(a.price));
    return sorted.first;
  }

  /// Best icon URL for this event's thumbnail — the single resolver shared by
  /// the big market cards, the unified-search rows and any compact list, so
  /// every surface shows the SAME real crest/portrait instead of a generic
  /// league ball or a placeholder glyph.
  ///
  /// Precedence (mirrors the card): real team crest (H2H) > per-candidate
  /// outcome image (multi-outcome) > the event image. Sports/esports ship a
  /// generic league ball as BOTH the event image and every sub-market image,
  /// so the crest must win whenever team data exists. Returns null only when
  /// nothing resolves (caller shows its own fallback). NOTE: the crest URLs
  /// are frequently `.svg` (national-team flags), so render this through a
  /// widget that decodes SVG (e.g. `PolyCrestImage`), not a raster-only loader.
  String? get displayIconUrl => displayIconUrlWithTeams(teams);

  /// [displayIconUrl] resolved against [resolvedTeams] instead of this
  /// event's own `teams` — for callers that lazily backfilled the crests by
  /// slug (`polymarketEventTeamsProvider`) because the search API path drops
  /// `teams[]`. Same precedence: crest > leading-outcome image > event image.
  String? displayIconUrlWithTeams(List<PolymarketTeam> resolvedTeams) {
    if (resolvedTeams.isNotEmpty) {
      final lead = _leadingOutcomeByPrice;
      if (lead != null) {
        final crest = logoFromTeams(resolvedTeams, lead.name);
        if (crest != null && crest.isNotEmpty) return crest;
      }
      final firstLogo = resolvedTeams.first.logo;
      if (firstLogo != null && firstLogo.isNotEmpty) return firstLogo;
    }
    if (!isBinary) {
      final lead = _leadingOutcomeByPrice;
      if (lead?.imageUrl != null && lead!.imageUrl!.isNotEmpty) {
        return lead.imageUrl;
      }
    }
    return imageUrl;
  }

  /// The embeddable broadcast behind [streamUrl] (Twitch channel, YouTube
  /// video, Kick channel); null when the URL is not one.
  LivestreamSource? get livestream => LivestreamSource.parse(streamUrl);

  /// A Mentions market ("What will Trump say …"): one Yes/No market per
  /// term. Gamma tag `mention-markets`.
  bool get isMentionMarket => tags.contains('mention-markets');

  /// True when there's a watchable stream to embed. Sports and esports
  /// streams show while Gamma flags the event `live`. A Mentions market
  /// links the speech or video itself (a YouTube URL) and Gamma never
  /// flags it live, so it shows its stream until the market closes.
  bool get hasLivestream {
    final source = livestream;
    if (source == null || ended || closed) return false;
    if (isLive) return true;
    return isMentionMarket && source.host == LivestreamHost.youtube;
  }

  /// Extracts a Twitch/YouTube/Kick broadcast URL from Gamma's
  /// `resolutionSource` (which doubles as the broadcast link on live
  /// events). Returns null for non-stream resolution sources (news links,
  /// docs, score sites).
  static String? streamUrlFrom(String? resolutionSource) {
    if (LivestreamSource.parse(resolutionSource) == null) return null;
    return resolutionSource!.trim();
  }

  /// Gamma `eventMetadata.gameId` as a string, when the event has one.
  static String? metadataGameIdFrom(Map<String, dynamic> e) {
    final meta = e['eventMetadata'];
    if (meta is! Map) return null;
    final id = meta['gameId']?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  /// Twitch channel name parsed from [streamUrl], or null if not Twitch.
  String? get twitchChannel {
    final url = streamUrl;
    if (url == null) return null;
    final m = RegExp(r'twitch\.tv/([A-Za-z0-9_]+)', caseSensitive: false)
        .firstMatch(url);
    return m?.group(1);
  }

  bool get isBinary =>
      outcomes.length == 2 &&
      outcomes.any((o) => o.name.toLowerCase() == 'yes') &&
      outcomes.any((o) => o.name.toLowerCase() == 'no');

  double get yesPrice {
    // Prefer the named "yes" outcome even when its price is 0 —
    // that's a RESOLVED market where No won, not a missing-data
    // signal. The earlier `price > 0` guard collapsed those rows to
    // 0.5 alongside the No 100% side, breaking the Yes+No=1.0
    // invariant.
    final yes =
        outcomes.where((o) => o.name.toLowerCase() == 'yes').firstOrNull;
    if (yes != null) return yes.price;
    // No "yes"-named outcome at all (unusual Gamma shape). If outcomes[0]
    // has a non-zero price, use it; if outcomes[1] is "no", derive
    // yes = 1 - no; otherwise fall back to 0.5.
    if (outcomes.isNotEmpty && outcomes.first.price > 0) {
      return outcomes.first.price;
    }
    if (outcomes.length > 1) {
      final no =
          outcomes.where((o) => o.name.toLowerCase() == 'no').firstOrNull;
      if (no != null) return (1.0 - no.price).clamp(0.0, 1.0);
    }
    return 0.5;
  }

  double get noPrice {
    // Same logic — prefer the named "no" outcome even at 0.
    final no = outcomes.where((o) => o.name.toLowerCase() == 'no').firstOrNull;
    if (no != null) return no.price;
    if (outcomes.length > 1 && outcomes[1].price > 0) {
      return outcomes[1].price;
    }
    return (1.0 - yesPrice).clamp(0.0, 1.0);
  }

  String? get yesTokenId {
    final yes =
        outcomes.where((o) => o.name.toLowerCase() == 'yes').firstOrNull;
    return yes?.tokenId ?? (outcomes.isNotEmpty ? outcomes.first.tokenId : null);
  }

  String? get noTokenId {
    final no = outcomes.where((o) => o.name.toLowerCase() == 'no').firstOrNull;
    return no?.tokenId ??
        (outcomes.length > 1 ? outcomes[1].tokenId : null);
  }

  int get outcomeCount => outcomes.length;
}

class PolymarketPricePoint {
  final DateTime timestamp;
  final double price;

  const PolymarketPricePoint({
    required this.timestamp,
    required this.price,
  });
}

// Top-level functions for Isolate.run() – must not be closures or instance methods.
//
// Data API v2 (https://docs.polymarket.com/migrate/data-api-v1-to-v2): every
// response is wrapped in `{data: [...], pagination: {next_cursor}}`, rows are
// snake_case, and several v1 names changed. The polybrainz models this app
// still renders through were generated against the v1 names (snake-cased),
// so each row is re-keyed here to that contract and the resulting Dart
// objects are identical to what the v1 routes produced.

/// Rows of a v2 envelope. A documented miss is `data: null`, which reads as
/// no rows. A bare JSON array (the retired v1 shape) is still accepted so a
/// cached body or fixture in the old shape cannot crash a parser.
List<Map<String, dynamic>> _dataApiV2Rows(dynamic decoded) {
  final rows = decoded is Map<String, dynamic> ? decoded['data'] : decoded;
  if (rows is! List) return const [];
  return rows.whereType<Map<String, dynamic>>().toList();
}

/// `pagination.next_cursor` of a v2 envelope; null on the last page.
String? _dataApiV2NextCursor(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) return null;
  final pagination = decoded['pagination'];
  if (pagination is! Map<String, dynamic>) return null;
  final cursor = pagination['next_cursor'];
  return cursor is String && cursor.isNotEmpty ? cursor : null;
}

double _v2Num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

int _v2Int(dynamic v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

String _v2Str(dynamic v) => v?.toString() ?? '';

/// Optional string: null stays null and an empty string reads as absent, so
/// `side == null` checks keep working where v2 sends `""` in place of null.
String? _v2OptStr(dynamic v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

/// `GET /v2/positions` row -> the v1-named snake_case map that polybrainz
/// `Position.fromJson` reads. Field mapping (v1 -> v2): asset -> token_id,
/// size -> current_size, initialValue -> entry_cost_usdc (fee-exclusive entry
/// basis, same semantics), cashPnl -> unrealized_pnl, totalBought ->
/// total_size, curPrice -> current_price, oppositeAsset -> opposite_token_id;
/// the rest only changed casing.
Map<String, dynamic> _positionSnakeFromV2(Map<String, dynamic> r) => {
      'proxy_wallet': _v2Str(r['proxy_wallet']),
      'asset': _v2Str(r['token_id']),
      'condition_id': _v2Str(r['condition_id']),
      'size': _v2Num(r['current_size']),
      'avg_price': _v2Num(r['avg_price']),
      'initial_value': _v2Num(r['entry_cost_usdc']),
      'current_value': _v2Num(r['current_value']),
      'cash_pnl': _v2Num(r['unrealized_pnl']),
      'percent_pnl': _v2Num(r['percent_pnl']),
      'total_bought': _v2Num(r['total_size']),
      'realized_pnl': _v2Num(r['realized_pnl']),
      'percent_realized_pnl': _v2Num(r['percent_realized_pnl']),
      'cur_price': _v2Num(r['current_price']),
      'redeemable': r['redeemable'] == true,
      'mergeable': r['mergeable'] == true,
      'title': _v2Str(r['title']),
      'slug': _v2Str(r['slug']),
      'icon': r['icon']?.toString(),
      'event_slug': _v2Str(r['event_slug']),
      'outcome': _v2Str(r['outcome']),
      'outcome_index': _v2Int(r['outcome_index']),
      'opposite_outcome': _v2Str(r['opposite_outcome']),
      'opposite_asset': _v2Str(r['opposite_token_id']),
      'end_date': r['end_date']?.toString(),
      'negative_risk': r['negative_risk'] == true,
    };

/// `GET /v2/positions?status=CLOSED` row -> the map polybrainz
/// `ClosedPosition.fromJson` reads. v2 has no `payout` / `won` /
/// `resolution_date`; they are derived, which is only sound once the market
/// has settled (the outcome token marked to 0 or 1). Rows exited while the
/// market was still trading return null and are skipped: this app renders a
/// closed position as a WON / LOST resolved card, and no such verdict exists
/// for a position sold mid-market.
///
/// On the CLOSED arm `current_size` / `entry_cost_usdc` are the ~0 residual,
/// so the lifetime basis is `total_size * avg_price` (the denominator the
/// API itself uses for `percent_realized_pnl`), and the P&L is
/// `realized_pnl`. `last_event_at` (the settling redeem / final sell) stands
/// in for the resolution date; the v1 `sortBy=resolution_date` order is
/// reproduced by requesting `sort_by=TIMESTAMP` on the same field.
///
/// A row sold mid-market keeps following the market's price after the
/// user left, so once the market settles it is priced 1 or 0 like a row
/// held to the result. It is still not a win or a loss: what the exit paid
/// per share says so, and such a row returns null too. The rule is
/// [closedPredictionWon] (prediction_results.dart), which the Statistics
/// drill-down reads its records' results by as well.
Map<String, dynamic>? _closedPositionSnakeFromV2(Map<String, dynamic> r) {
  if (_v2ClosedWon(r) == null) return null;
  return _closedSnake(r);
}

bool? _v2ClosedWon(Map<String, dynamic> r) => closedPredictionWon(
      totalSize: _v2Num(r['total_size']),
      avgPrice: _v2Num(r['avg_price']),
      realizedPnl: _v2Num(r['realized_pnl']),
      curPrice: _v2Num(r['current_price']),
    );

/// A settled closed row sold before its result ([predictionClosedBySale])
/// as a [ClosedPosition] for the trading provider's on-chain claim scan
/// only (shares left on the wallet still claim once the result is on
/// chain); never shown as a win or a loss. Null for any other row. A CS2
/// position sold on 5 Oct 2026 for 94¢ a share while the game was being
/// reported later read 1.0 and "Won"; one sold for a profit before its
/// side lost read "Lost". The history says Sold for both.
Map<String, dynamic>? _soldClosedPositionSnakeFromV2(Map<String, dynamic> r) {
  final price = _v2Num(r['current_price']);
  if (!predictionPriceSettled(price) ||
      !predictionClosedBySale(
          totalSize: _v2Num(r['total_size']),
          avgPrice: _v2Num(r['avg_price']),
          realizedPnl: _v2Num(r['realized_pnl']),
          curPrice: price)) {
    return null;
  }
  return _closedSnake(r);
}

Map<String, dynamic> _closedSnake(Map<String, dynamic> r) {
  final won = _v2Num(r['current_price']) >= 0.5;
  final totalSize = _v2Num(r['total_size']);
  final avgPrice = _v2Num(r['avg_price']);
  final initialValue = totalSize * avgPrice;
  final realized = _v2Num(r['realized_pnl']);
  final payout = initialValue + realized;
  final percent = initialValue > 0 ? realized / initialValue * 100 : 0.0;
  final lastEventAt = _v2Int(r['last_event_at']);
  return {
    'proxy_wallet': _v2Str(r['proxy_wallet']),
    'asset': _v2Str(r['token_id']),
    'condition_id': _v2Str(r['condition_id']),
    'size': totalSize,
    'avg_price': avgPrice,
    'initial_value': initialValue,
    'payout': payout > 0 ? payout : 0.0,
    'cash_pnl': realized,
    'percent_pnl': percent,
    'title': _v2Str(r['title']),
    'slug': _v2Str(r['slug']),
    'icon': r['icon']?.toString(),
    'event_slug': _v2Str(r['event_slug']),
    'outcome': _v2Str(r['outcome']),
    'outcome_index': _v2Int(r['outcome_index']),
    'won': won,
    'resolution_date': lastEventAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(lastEventAt * 1000, isUtc: true)
            .toIso8601String()
        : null,
  };
}

/// `GET /v2/activity` row -> the map polybrainz `Activity.fromJson` reads.
/// Only `asset -> token_id` changed beyond casing.
Map<String, dynamic> _activitySnakeFromV2(Map<String, dynamic> r) => {
      'proxy_wallet': _v2Str(r['proxy_wallet']),
      'timestamp': _v2Int(r['timestamp']),
      'condition_id': _v2Str(r['condition_id']),
      'type': _v2Str(r['type']),
      'size': _v2Num(r['size']),
      'usdc_size': _v2Num(r['usdc_size']),
      'transaction_hash': _v2Str(r['transaction_hash']),
      'price': r['price'] == null ? null : _v2Num(r['price']),
      'asset': _v2OptStr(r['token_id']),
      'side': _v2OptStr(r['side']),
      'outcome_index':
          r['outcome_index'] == null ? null : _v2Int(r['outcome_index']),
      'title': r['title']?.toString(),
      'slug': r['slug']?.toString(),
      'icon': r['icon']?.toString(),
      'event_slug': r['event_slug']?.toString(),
      'outcome': r['outcome']?.toString(),
      'name': r['name']?.toString(),
      'pseudonym': r['pseudonym']?.toString(),
      'bio': r['bio']?.toString(),
      'profile_image': r['profile_image']?.toString(),
    };

List<Position> _parsePositions(String body) {
  return _dataApiV2Rows(jsonDecode(body))
      .map((row) => Position.fromJson(_positionSnakeFromV2(row)))
      .toList();
}

({
  List<ClosedPosition> closed,
  List<ClosedPosition> sold,
  Set<String> negRisk,
}) _parseClosedPositionsAndNegRisk(String body) {
  final rows = _dataApiV2Rows(jsonDecode(body));
  return (
    closed: rows
        .map(_closedPositionSnakeFromV2)
        .whereType<Map<String, dynamic>>()
        .map(ClosedPosition.fromJson)
        .toList(),
    sold: rows
        .map(_soldClosedPositionSnakeFromV2)
        .whereType<Map<String, dynamic>>()
        .map(ClosedPosition.fromJson)
        .toList(),
    negRisk: {
      for (final r in rows)
        if (r['negative_risk'] == true) _v2Str(r['condition_id']),
    },
  );
}

/// The `/v2/positions` parse the app reads positions with, for tests that
/// check a row reads the same everywhere: the open arm's [Position]s and
/// the settled CLOSED list.
@visibleForTesting
List<Position> debugParseOpenPositions(String body) => _parsePositions(body);

@visibleForTesting
List<ClosedPosition> debugParseSettledClosedPositions(String body) =>
    _parseClosedPositionsAndNegRisk(body).closed;

List<Activity> _parseUserActivity(String body) {
  return _dataApiV2Rows(jsonDecode(body))
      .map((row) => Activity.fromJson(_activitySnakeFromV2(row)))
      .toList();
}

/// One `GET /v2/prices-history` page: `{timestamp, price}` rows (epoch
/// seconds, 0..1) become the same [PolymarketPricePoint]s the CLOB `{t, p}`
/// rows did, plus the cursor of the next page when the series continues.
({List<PolymarketPricePoint> points, String? nextCursor}) _parsePriceHistoryPage(
    String body) {
  final decoded = jsonDecode(body);
  final points = <PolymarketPricePoint>[];
  for (final row in _dataApiV2Rows(decoded)) {
    final t = row['timestamp'];
    final p = row['price'];
    if (t is! num || p is! num) continue;
    points.add(PolymarketPricePoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000),
      price: p.toDouble(),
    ));
  }
  return (points: points, nextCursor: _dataApiV2NextCursor(decoded));
}

/// Per-token stablecoin balance read from the Polymarket Safe. All three
/// tokens are 1:1 USD; the breakdown only matters for the "Available to
/// claim" UI where we want to show the user exactly which tokens they
/// hold (pUSD vs USDC.e is meaningful — pUSD = active-bet collateral form,
/// USDC.e = post-redeem unwrapped form, native USDC = canonical form for
/// any future settlement that delivers it directly).
class StablesBreakdown {
  final double usdcE;
  final double pusd;
  final double usdc;

  const StablesBreakdown({
    required this.usdcE,
    required this.pusd,
    required this.usdc,
  });

  double get total => usdcE + pusd + usdc;
}

class PolymarketModel {
  bool _disposed = false;
  http.Client? _searchClient;

  PolymarketModel({http.Client? searchClient}) : _searchClient = searchClient;

  /// Always returns false now that order placement has moved entirely
  /// to `polymarket_trading_provider` + `polymarket_backend_service`
  /// (local EIP-712 signing). Kept as a getter so older call sites
  /// that gate on it compile, but the model itself no longer holds
  /// trading state.
  bool get canTrade => false;

  // Order placement / cancellation lives in `polymarket_trading_provider`
  // and `polymarket_backend_service` — they sign V2 orders locally with
  // EIP-712 and POST to the CLOB (or our HMAC-injecting relay for
  // builder attribution). No `model.placeOrder` wrapper is needed here.

  /// Data API v2 (`https://data-api.polymarket.com/v2`). v1 is retired on
  /// 2026-10-24; the v2 contract is one `{data, pagination}` envelope with
  /// snake_case rows and opaque `cursor` paging. Row re-keying lives in the
  /// top-level `_*SnakeFromV2` helpers above.
  static const _dataApiBase = 'https://data-api.polymarket.com';
  static const _dataApiV2 = '$_dataApiBase/v2';

  /// v1 `/positions` paged 100 rows by default and `/activity` 100; the app
  /// never paged past that, so the v2 reads ask for the same single page.
  static const _kDataApiPageLimit = 100;

  /// v1 `/positions` hid dust below `sizeThreshold=1` share by default; v2's
  /// default floor is 0.1, so the old floor is restated explicitly.
  static const _kPositionsMinShares = '1';

  /// Bound on cursor-following for the one v2 read that can span pages
  /// (`/v2/prices-history`, 10,000 points per page); 20 pages is far beyond
  /// any chart window this app requests.
  static const _kPriceHistoryMaxPages = 20;

  // Long-lived client for the per-tick Data API polls below. Top-level
  // `http.get` spins up (and tears down) a fresh `Client` — and with it
  // a fresh TLS handshake — on every call; at the trading provider's
  // 3-5s refresh cadence that's three handshakes per tick. Static so it
  // survives model re-creation (the provider disposes and rebuilds the
  // model on wallet switch) and keeps its connections pooled for the
  // life of the process; deliberately never closed.
  static final http.Client _dataApiClient = http.Client();

  /// Gamma keyset list routes (`/events/keyset`, `/markets/keyset`) replace
  /// the offset-paged `/events` and `/markets`, which "remain available but
  /// will be deprecated" (changelog 2026-04-10). Pages are capped at 100
  /// rows and continue through `after_cursor`.
  static const _kGammaKeysetPageMax = 100;
  static const _kGammaKeysetMaxPages = 10;
  static const _gammaBase = 'https://gamma-api.polymarket.com';

  /// Rows of a Gamma keyset list, following `next_cursor` until [limit]
  /// rows (after skipping [offset]) are collected or the list ends.
  /// [resource] is `events` or `markets`; the response keys its rows by the
  /// same name (`{"events": [...], "next_cursor": "..."}`).
  ///
  /// The keyset routes have no `active` filter (the offset routes did), so
  /// `active=true` in [params] is not sent; rows Gamma marks `active:false`
  /// are dropped here instead, which keeps the old contract without
  /// depending on an unlisted parameter. `offset` is rejected by keyset
  /// (422) and is never sent either.
  ///
  /// Throws on a failed first page (callers already map failures to an
  /// empty list); a failure on a later page returns the rows read so far.
  static Future<List<Map<String, dynamic>>> fetchGammaKeyset(
    String resource,
    Map<String, String> params, {
    required int limit,
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var rows = <Map<String, dynamic>>[];
    await for (final read in streamGammaKeyset(resource, params,
        limit: limit, offset: offset, timeout: timeout)) {
      rows = read;
    }
    return rows;
  }

  /// [fetchGammaKeyset] a page at a time: after every page it yields all
  /// the rows read so far. [firstPage] caps the first page, so a screen
  /// that shows a few cards can draw them from a small read while the
  /// rest follows on the same cursor. Same errors as [fetchGammaKeyset]:
  /// a failed first page is a stream error, a failed later page ends the
  /// stream.
  static Stream<List<Map<String, dynamic>>> streamGammaKeyset(
    String resource,
    Map<String, String> params, {
    required int limit,
    int offset = 0,
    int? firstPage,
    Duration timeout = const Duration(seconds: 15),
  }) async* {
    final wanted = offset + limit;
    final activeOnly = params['active'] == 'true';
    final base = Map<String, String>.of(params)
      ..remove('active')
      ..remove('offset')
      ..remove('limit');
    final out = <Map<String, dynamic>>[];
    String? cursor;
    for (var page = 0; page < _kGammaKeysetMaxPages && out.length < wanted;
        page++) {
      final cap = page == 0 && firstPage != null && firstPage > 0
          ? firstPage.clamp(1, _kGammaKeysetPageMax)
          : _kGammaKeysetPageMax;
      final pageSize = (wanted - out.length).clamp(1, cap);
      final query = {
        ...base,
        'limit': '$pageSize',
        if (cursor != null) 'after_cursor': cursor,
      };
      final _KeysetPage decoded;
      try {
        decoded = await _raceKeysetRead(resource, query,
            timeout: timeout,
            decode: (body) => _decodeKeysetPage(body, resource));
      } catch (_) {
        if (out.isEmpty) rethrow;
        break;
      }
      for (final row in decoded.rows) {
        if (activeOnly && row['active'] == false) continue;
        out.add(row);
      }
      yield out.skip(offset).take(limit).toList();
      final next = decoded.next;
      if (next == null || next.isEmpty || decoded.rows.length < pageSize) {
        break;
      }
      cursor = next;
    }
  }

  /// [streamGammaKeyset] for `events`, parsed: the rows are decoded and
  /// read into [PolymarketEvent]s in one step, off the UI isolate when the
  /// page is large (a 100-row sports page is tens of megabytes of JSON).
  static Future<List<PolymarketEvent>> _fetchGammaEvents(
    Map<String, String> params, {
    required int limit,
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final wanted = offset + limit;
    final activeOnly = params['active'] == 'true';
    final base = Map<String, String>.of(params)
      ..remove('active')
      ..remove('offset')
      ..remove('limit');
    final out = <PolymarketEvent>[];
    String? cursor;
    for (var page = 0; page < _kGammaKeysetMaxPages && out.length < wanted;
        page++) {
      final pageSize = (wanted - out.length).clamp(1, _kGammaKeysetPageMax);
      final query = {
        ...base,
        'limit': '$pageSize',
        if (cursor != null) 'after_cursor': cursor,
      };
      final _KeysetEvents decoded;
      try {
        decoded = await _raceKeysetRead('events', query,
            timeout: timeout,
            decode: (body) => _decodeKeysetEvents(body, activeOnly));
      } catch (_) {
        if (out.isEmpty) rethrow;
        break;
      }
      out.addAll(decoded.events);
      final next = decoded.next;
      if (next == null || next.isEmpty || decoded.rowCount < pageSize) break;
      cursor = next;
    }
    return out.skip(offset).take(limit).toList();
  }

  /// How long a keyset read waits on the Kute feed alone before Gamma is
  /// asked too; the first good answer is used.
  static const Duration kFeedHeadStart = Duration(milliseconds: 500);

  /// The longest the Kute feed is waited on at all.
  static const Duration kFeedTimeout = Duration(seconds: 3);

  /// One keyset page from the Kute backend feed (the same page trimmed to
  /// the keys the cards read, about a quarter of Gamma's bytes, cached and
  /// coalesced) or from Gamma, whichever gives a good answer first. The
  /// feed is asked first; Gamma starts when the feed has not answered in
  /// [kFeedHeadStart], or at once when the feed fails. The read that loses
  /// is closed, so its bytes stop. Without a backend (or with [direct])
  /// Gamma alone is read. Throws when neither answers.
  static Future<T> _raceKeysetRead<T extends Object>(
    String resource,
    Map<String, dynamic> query, {
    required Duration timeout,
    required Future<T?> Function(String body) decode,
    bool direct = false,
  }) {
    final backend = direct ? null : _feedBackend();
    final gammaUri = Uri.parse('$_gammaBase/$resource/keyset')
        .replace(queryParameters: query);
    final done = Completer<T>();
    http.Client? feedClient;
    http.Client? gammaClient;
    Timer? headStart;
    Object? gammaError;
    var feedOver = backend == null;
    var gammaOver = false;
    var gammaStarted = false;

    void win(T page) {
      if (done.isCompleted) return;
      done.complete(page);
      headStart?.cancel();
      feedClient?.close();
      gammaClient?.close();
    }

    void failIfBothOver() {
      if (done.isCompleted || !feedOver || !gammaOver) return;
      done.completeError(gammaError ??
          http.ClientException('$resource keyset read failed', gammaUri));
    }

    void startGamma() {
      if (gammaStarted || done.isCompleted) return;
      gammaStarted = true;
      final client = gammaClient = http.Client();
      () async {
        try {
          final resp = await client.get(gammaUri).timeout(timeout);
          if (done.isCompleted) return;
          if (resp.statusCode != 200) {
            throw http.ClientException(
                'gamma $resource keyset read failed (${resp.statusCode})',
                gammaUri);
          }
          final page = await decode(resp.body);
          if (page == null) {
            throw http.ClientException(
                'gamma $resource keyset unreadable', gammaUri);
          }
          win(page);
        } catch (e) {
          gammaError = e;
        } finally {
          client.close();
          gammaOver = true;
          failIfBothOver();
        }
      }();
    }

    if (backend == null) {
      startGamma();
      return done.future;
    }
    headStart = Timer(kFeedHeadStart, startGamma);
    final client = feedClient = http.Client();
    () async {
      try {
        final resp = await client
            .get(Uri.parse('$backend/api/v1/pm/feed/$resource')
                .replace(queryParameters: query))
            .timeout(timeout < kFeedTimeout ? timeout : kFeedTimeout);
        if (resp.statusCode == 200 && !done.isCompleted) {
          final page = await decode(resp.body);
          if (page != null) {
            win(page);
            return;
          }
        }
      } catch (_) {
        // Gamma answers instead.
      } finally {
        client.close();
        feedOver = true;
      }
      // The feed could not answer: Gamma now, without waiting out the
      // head start.
      headStart?.cancel();
      startGamma();
      failIfBothOver();
    }();
    return done.future;
  }

  /// The query of one keyset page: [params] without the offset-route
  /// keys, [multi] repeated, the page size and the cursor.
  static Map<String, dynamic> _keysetQuery(
    Map<String, String> params, {
    required int limit,
    String? cursor,
    Map<String, List<String>> multi = const {},
  }) =>
      <String, dynamic>{
        ...(Map<String, String>.of(params)
          ..remove('active')
          ..remove('offset')
          ..remove('limit')),
        for (final e in multi.entries)
          if (e.value.isNotEmpty) e.key: e.value,
        'limit': '${limit.clamp(1, _kGammaKeysetPageMax)}',
        if (cursor != null && cursor.isNotEmpty) 'after_cursor': cursor,
      };

  /// The cursor of the page after one of [rowCount] rows read for
  /// [limit]; null at the end of the list.
  static String? _pageAfter(String? next, int rowCount, int limit) =>
      next == null || next.isEmpty || rowCount < limit ? null : next;

  /// One page of a Gamma keyset list, for lists that load as the person
  /// scrolls: the rows and the cursor of the next page (null at the end).
  ///
  /// [multi] carries parameters Gamma takes more than once
  /// (`exclude_tag_id`). [direct] skips the Kute backend feed and reads
  /// Gamma itself, for the views that need a parameter the feed does not
  /// pass on (`end_date_min`) or a key it trims (`oneDayPriceChange`).
  /// `active=true` is applied to the rows, as in [streamGammaKeyset].
  /// Throws when neither source answers.
  static Future<({List<Map<String, dynamic>> rows, String? next})>
      readGammaKeysetPage(
    String resource,
    Map<String, String> params, {
    required int limit,
    String? cursor,
    Map<String, List<String>> multi = const {},
    bool direct = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final activeOnly = params['active'] == 'true';
    final decoded = await _raceKeysetRead(
      resource,
      _keysetQuery(params, limit: limit, cursor: cursor, multi: multi),
      direct: direct,
      timeout: timeout,
      decode: (body) => _decodeKeysetPage(body, resource),
    );
    final rows = [
      for (final row in decoded.rows)
        if (!activeOnly || row['active'] != false) row
    ];
    return (
      rows: rows,
      next: _pageAfter(decoded.next, decoded.rows.length, limit),
    );
  }

  /// [readGammaKeysetPage] for `events`, read into [PolymarketEvent]s: the
  /// page is decoded and parsed in one step, off the UI isolate when it is
  /// large. For the lists that only draw cards.
  static Future<({List<PolymarketEvent> events, String? next})>
      readGammaEventsPage(
    Map<String, String> params, {
    required int limit,
    String? cursor,
    Map<String, List<String>> multi = const {},
    bool direct = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final activeOnly = params['active'] == 'true';
    final decoded = await _raceKeysetRead(
      'events',
      _keysetQuery(params, limit: limit, cursor: cursor, multi: multi),
      direct: direct,
      timeout: timeout,
      decode: (body) => _decodeKeysetEvents(body, activeOnly),
    );
    return (
      events: decoded.events,
      next: _pageAfter(decoded.next, decoded.rowCount, limit),
    );
  }

  /// The Kute backend origin, or null when the build has none configured.
  static String? _feedBackend() {
    try {
      final raw = dotenv.env['BACKEND']?.trim() ?? '';
      if (raw.isEmpty) return null;
      return raw.replaceFirst(RegExp(r'/+$'), '');
    } catch (_) {
      return null;
    }
  }

  /// Decodes one keyset page off the UI isolate: a page of a hundred
  /// events is megabytes of JSON, and decoding it inline was a visible
  /// freeze on a phone. Null when the body is not a keyset envelope.
  static Future<_KeysetPage?> _decodeKeysetPage(
      String body, String resource) async {
    if (body.length < 64 * 1024) return _parseKeysetPage(body, resource);
    return Isolate.run(() => _parseKeysetPage(body, resource));
  }

  /// [_decodeKeysetPage] for an events page, also read into
  /// [PolymarketEvent]s (rows Gamma marks inactive dropped with
  /// [activeOnly]): one hop to a worker isolate for a large page, so
  /// neither the decode nor the parse runs on the UI isolate.
  static Future<_KeysetEvents?> _decodeKeysetEvents(
      String body, bool activeOnly) async {
    if (body.length < 64 * 1024) {
      return _parseKeysetEvents(
          (body: body, activeOnly: activeOnly, protocol: null));
    }
    final protocol = PolyMarketProtocol.workerState();
    return Isolate.run(() => _parseKeysetEvents(
        (body: body, activeOnly: activeOnly, protocol: protocol)));
  }

  Uri _positionsUri(String addr) => Uri.parse('$_dataApiV2/positions').replace(
        queryParameters: {
          'user': addr,
          'status': 'OPEN',
          'limit': '$_kDataApiPageLimit',
          'filter_type': 'TOKENS',
          'filter_amount': _kPositionsMinShares,
          // v1 sorted by TOKENS desc by default; v2's default is
          // CURRENT_VALUE, so the old order is restated.
          'sort_by': 'TOKENS',
          'sort_direction': 'DESC',
        },
      );

  /// `GET /v2/positions` (was v1 `/positions`). `status=OPEN` is the same
  /// superset v1 served: live positions plus settled-but-unredeemed ones,
  /// flagged `redeemable`. [client] is injectable for tests.
  Future<List<Position>> getPositions(
    String walletAddress, {
    http.Client? client,
  }) async {
    final addr = walletAddress.toLowerCase();
    final resp = await (client ?? _dataApiClient)
        .get(_positionsUri(addr))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final body = resp.body;
    return await Isolate.run(() => _parsePositions(body));
  }

  /// Like [getPositions] but THROWS on a non-200 or malformed body, so a
  /// failed read is flagged instead of rendering as "no positions"
  /// (Wallet hardening Phase 3, Ledger read providers). [client] is
  /// injectable for tests.
  Future<List<Position>> getPositionsOrThrow(
    String walletAddress, {
    http.Client? client,
  }) async {
    final addr = walletAddress.toLowerCase();
    final resp = await (client ?? _dataApiClient)
        .get(_positionsUri(addr))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw http.ClientException(
          'positions read failed (${resp.statusCode})', resp.request?.url);
    }
    return _parsePositions(resp.body);
  }

  /// `GET /v2/positions?status=CLOSED` (was v1 `/positions?closed=true`,
  /// folded into the unified lifecycle route). Newest exit first, like the
  /// old `resolution_date desc`. Only settled markets held to their result
  /// are returned; see `_closedPositionSnakeFromV2`. The settled rows sold
  /// before their result go to [closedSoldPositions]. [client] is
  /// injectable for tests.
  Future<List<ClosedPosition>> getClosedPositions(
    String walletAddress, {
    http.Client? client,
  }) async {
    final addr = walletAddress.toLowerCase();
    try {
      final uri = Uri.parse('$_dataApiV2/positions').replace(queryParameters: {
        'user': addr,
        'status': 'CLOSED',
        'limit': '$_kDataApiPageLimit',
        'sort_by': 'TIMESTAMP',
        'sort_direction': 'DESC',
      });
      final resp = await (client ?? _dataApiClient)
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final body = resp.body;
      final parsed =
          await Isolate.run(() => _parseClosedPositionsAndNegRisk(body));
      closedNegRiskConditionIds = parsed.negRisk;
      closedSoldPositions = parsed.sold;
      return parsed.closed;
    } catch (e) {
      return [];
    }
  }

  /// Conditions among the last [getClosedPositions] answer that are
  /// neg-risk markets. `ClosedPosition` has no such field, but a closed
  /// row the trading provider puts back on the Claim rail (tokens still
  /// held on chain) must be redeemed through the neg-risk adapter.
  Set<String> closedNegRiskConditionIds = const {};

  /// Settled rows among the last [getClosedPositions] answer that the user
  /// sold before the result (`_v2ClosedBySale`): neither won nor lost, so
  /// they are not in its list. The trading provider still scans them for
  /// shares left on the wallet, which claim once the result is on chain.
  List<ClosedPosition> closedSoldPositions = const [];

  /// `GET /v2/value` (was v1 `/value`): `{data: {proxy_wallet, value}}`.
  /// The v1 `[{user, value}]` shape is still read so a cached body cannot
  /// zero the balance. [client] is injectable for tests.
  Future<double> getPortfolioTotalValue(
    String walletAddress, {
    http.Client? client,
  }) async {
    final addr = walletAddress.toLowerCase();
    try {
      final resp = await (client ?? _dataApiClient)
          .get(Uri.parse('$_dataApiV2/value').replace(
            queryParameters: {'user': addr},
          ))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return 0;
      final decoded = jsonDecode(resp.body);
      final data = decoded is Map ? decoded['data'] : decoded;
      if (data is Map) {
        return (data['value'] as num?)?.toDouble() ?? 0;
      } else if (data is List && data.isNotEmpty && data[0] is Map) {
        return (data[0]['value'] as num?)?.toDouble() ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  // Cache to avoid hammering RPCs on every refresh (30s interval).
  double _cachedUsdcBalance = 0;
  DateTime? _lastBalanceFetch;
  static int _rpcIndex = 0; // Rotate RPCs across calls to spread load

  static const _polygonRpcs = [
    'https://polygon-bor-rpc.publicnode.com',
    'https://polygon.drpc.org',
    'https://1rpc.io/matic',
  ];

  // Task #170: Safe now holds pUSD at rest. USDC.e is only transient
  // mid-flow (deposit arrives as USDC.e then wraps to pUSD; cashout
  // unwraps pUSD → USDC.e then ships out). Native USDC is rare but
  // read for the legacy-deposit path. All three are 1:1 USD — sum and
  // surface as one USDC balance.
  static final _usdcAddresses = [
    EthereumAddress.fromHex('0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'), // USDC.e
    EthereumAddress.fromHex('0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB'), // pUSD
    EthereumAddress.fromHex('0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359'), // Native USDC (Polygon)
  ];

  // Minimal ERC-20 ABI — only balanceOf needed
  static final _erc20Abi = ContractAbi.fromJson(
    '[{"type":"function","name":"balanceOf","inputs":[{"name":"account","type":"address"}],"outputs":[{"name":"","type":"uint256"}],"stateMutability":"view"}]',
    'ERC20',
  );

  /// Drop the on-chain balance cache so the next read forces a fresh RPC
  /// query. Call this immediately after any flow that mutates the Safe's
  /// USDC.e/pUSD/USDC balance — sell, redeem, sweep, top-up — otherwise
  /// the polling refresh inside the 30-second window keeps returning the
  /// pre-action snapshot and the user thinks nothing happened.
  void invalidateBalanceCache() {
    _lastBalanceFetch = null;
    _cachedBreakdown = null;
  }

  // Per-token cache so the home row's breakdown chip and the Claim sheet
  // share the same RPC call as the summed balance read.
  StablesBreakdown? _cachedBreakdown;
  DateTime? _lastBreakdownFetch;

  /// Per-token stablecoin balance for [walletAddress] (the Safe), in human
  /// dollars. Used by the "Available to claim" row to show pUSD / USDC.e /
  /// USDC separately. Cached for 30s like [getOnChainUsdcBalance].
  Future<StablesBreakdown> getOnChainStablesBreakdown(String walletAddress) async {
    if (_lastBreakdownFetch != null &&
        DateTime.now().difference(_lastBreakdownFetch!).inSeconds < 30 &&
        _cachedBreakdown != null) {
      return _cachedBreakdown!;
    }

    final owner = EthereumAddress.fromHex(walletAddress);
    for (var attempt = 0; attempt < _polygonRpcs.length; attempt++) {
      final rpcUrl = _polygonRpcs[(_rpcIndex + attempt) % _polygonRpcs.length];
      final client = Web3Client(rpcUrl, http.Client());
      try {
        final results = await Future.wait(
          _usdcAddresses.map((contractAddr) {
            final contract = DeployedContract(_erc20Abi, contractAddr);
            final balanceOf = contract.function('balanceOf');
            return client.call(
              contract: contract,
              function: balanceOf,
              params: [owner],
            );
          }),
        ).timeout(const Duration(seconds: 8));

        double readAt(int i) {
          if (i >= results.length || results[i].isEmpty) return 0;
          final raw = results[i][0] as BigInt;
          return raw.toDouble() / 1e6;
        }

        // Index order matches `_usdcAddresses` above:
        //   0 = USDC.e, 1 = pUSD, 2 = native USDC
        final breakdown = StablesBreakdown(
          usdcE: readAt(0),
          pusd: readAt(1),
          usdc: readAt(2),
        );
        _rpcIndex = (_rpcIndex + attempt + 1) % _polygonRpcs.length;
        _cachedBreakdown = breakdown;
        _lastBreakdownFetch = DateTime.now();
        // Keep the legacy summed cache in sync so concurrent readers see
        // the same numbers regardless of which entry point they hit.
        _cachedUsdcBalance = breakdown.total;
        _lastBalanceFetch = DateTime.now();
        return breakdown;
      } catch (_) {
        continue;
      } finally {
        client.dispose();
      }
    }
    return _cachedBreakdown ?? const StablesBreakdown(usdcE: 0, pusd: 0, usdc: 0);
  }

  Future<double> getOnChainUsdcBalance(String walletAddress) async {
    // Return cached value if fresh (< 30s old)
    if (_lastBalanceFetch != null &&
        DateTime.now().difference(_lastBalanceFetch!).inSeconds < 30 &&
        _cachedUsdcBalance > 0) {
      return _cachedUsdcBalance;
    }

    final owner = EthereumAddress.fromHex(walletAddress);

    // Try each RPC with round-robin
    for (var attempt = 0; attempt < _polygonRpcs.length; attempt++) {
      final rpcUrl = _polygonRpcs[(_rpcIndex + attempt) % _polygonRpcs.length];
      final client = Web3Client(rpcUrl, http.Client());
      try {

        // Query both USDC contracts in parallel
        final balances = await Future.wait(
          _usdcAddresses.map((contractAddr) {
            final contract = DeployedContract(_erc20Abi, contractAddr);
            final balanceOf = contract.function('balanceOf');
            return client.call(
              contract: contract,
              function: balanceOf,
              params: [owner],
            );
          }),
        ).timeout(const Duration(seconds: 8));

        double total = 0;
        for (final result in balances) {
          if (result.isNotEmpty) {
            final raw = result[0] as BigInt;
            total += raw.toDouble() / 1e6; // 6 decimals
          }
        }

        _rpcIndex = (_rpcIndex + attempt + 1) % _polygonRpcs.length;
        _cachedUsdcBalance = total;
        _lastBalanceFetch = DateTime.now();
        return total;
      } catch (e) {
        continue;
      } finally {
        client.dispose();
      }
    }
    return _cachedUsdcBalance; // Return last known value instead of 0
  }

  Future<List<Activity>> getUserActivity(String walletAddress) async {
    try {
      return await getUserActivityOrThrow(walletAddress);
    } catch (_) {
      return [];
    }
  }

  /// Strict variant for wallet-scoped history: a failed read is unknown, not an
  /// empty activity list. Uses only the public Data API; no CLOB credentials.
  /// `GET /v2/activity` (was v1 `/activity`): same default window, newest
  /// first, deposits / withdrawals excluded, 100 rows. [client] is
  /// injectable for tests.
  Future<List<Activity>> getUserActivityOrThrow(
    String walletAddress, {
    http.Client? client,
  }) async {
    final addr = walletAddress.toLowerCase();
    final uri = Uri.parse('$_dataApiV2/activity').replace(queryParameters: {
      'user': addr,
      'limit': '$_kDataApiPageLimit',
    });
    final resp = await (client == null ? http.get(uri) : client.get(uri))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw StateError('Polymarket activity read failed (${resp.statusCode})');
    }
    final body = resp.body;
    return Isolate.run(() => _parseUserActivity(body));
  }

  Future<Profile?> getProfile(String eoaAddress) async {
    try {
      final uri = Uri.parse('https://gamma-api.polymarket.com/public-profile')
          .replace(queryParameters: {'address': eoaAddress.toLowerCase()});
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return null;
      return Profile.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  Future<double> getBestPrice(String tokenId, OrderSide side) async {
    final sideStr = side == OrderSide.buy ? 'BUY' : 'SELL';
    final uri = Uri.parse('https://clob.polymarket.com/price')
        .replace(queryParameters: {'token_id': tokenId, 'side': sideStr});
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return 0.0;
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) return 0.0;
    return double.tryParse(body['price']?.toString() ?? '') ?? 0.0;
  }

  /// Top of the `/markets/keyset` list (was offset-paged `/markets`), same
  /// filters: open, not closed, by 24h volume descending, 20 rows.
  Future<PolymarketTopMarket?> getTopMarket() async {
    if (_disposed) return null;
    try {
      final rows = await fetchGammaKeyset(
        'markets',
        {
          'active': 'true',
          'closed': 'false',
          'order': 'volume24hr',
          'ascending': 'false',
        },
        limit: 20,
        timeout: const Duration(seconds: 10),
      );
      final markets = rows
          .map((r) => Market.fromJson(PolyMarketProtocol.withTradingIds(r)))
          .toList();

      if (markets.isEmpty) return null;

      for (final market in markets) {
        final tokenIds = market.tokenIdsList;
        if (tokenIds.isEmpty) continue;

        final yesPrice = market.yesPrice;
        if (yesPrice < 0.05 || yesPrice > 0.95) continue;

        String? imageUrl;
        final events = market.events;
        if (events != null && events.isNotEmpty) {
          imageUrl = events.first.image;
        }

        return PolymarketTopMarket(
          question: market.question ?? 'Unknown Market',
          yesPrice: yesPrice,
          noPrice: market.noPrice,
          volume: market.volumeNum ?? 0,
          imageUrl: imageUrl,
          conditionId: market.conditionId,
          yesTokenId: tokenIds[0],
          noTokenId: tokenIds.length > 1 ? tokenIds[1] : null,
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// `GET /v2/prices-history` on the Data API (changelog 2026-09-04: replaces
  /// the CLOB-hosted route). Same `interval` vocabulary (`max`, `1m`, `1w`,
  /// `1d`, `6h`, `1h`); the CLOB's `fidelity` (minutes per point) becomes
  /// `bucket_seconds` (60..86400). Pages are 10,000 points; the cursor is
  /// followed so the series is as complete as the single CLOB response was.
  /// [client] is injectable for tests.
  Future<List<PolymarketPricePoint>> getPriceHistory(
    String tokenId, {
    String interval = 'max',
    int fidelity = 100,
    http.Client? client,
  }) async =>
      await fetchPriceHistory(tokenId,
          interval: interval, fidelity: fidelity, client: client) ??
      [];

  /// [getPriceHistory], but null when the read failed (non-200 first page,
  /// network error or [timeout]) so a caller can retry instead of caching
  /// an empty series.
  Future<List<PolymarketPricePoint>?> fetchPriceHistory(
    String tokenId, {
    String interval = 'max',
    int fidelity = 100,
    Duration timeout = const Duration(seconds: 15),
    http.Client? client,
  }) async {
    try {
      final bucketSeconds = (fidelity * 60).clamp(60, 86400);
      return await _priceHistoryPages({
        'token_id': tokenId,
        'interval': interval,
        'bucket_seconds': '$bucketSeconds',
      }, client, timeout: timeout);
    } catch (e) {
      return null;
    }
  }

  /// One explicit window of `GET /v2/prices-history`: points from
  /// [startSec] (inclusive) to [endSec] (exclusive), at [bucketSeconds].
  /// The API caps explicit windows at 15 days back from now, so the chart
  /// pages older history with this only inside that horizon. Null when the
  /// request failed (so a pager can retry), an empty list when the window
  /// simply has no points.
  Future<List<PolymarketPricePoint>?> getPriceHistoryWindow(
    String tokenId, {
    required int startSec,
    required int endSec,
    required int bucketSeconds,
    http.Client? client,
  }) async {
    try {
      return await _priceHistoryPages({
        'token_id': tokenId,
        'start': '$startSec',
        'end': '$endSec',
        'bucket_seconds': '${bucketSeconds.clamp(60, 86400)}',
      }, client);
    } catch (e) {
      return null;
    }
  }

  /// Follows the prices-history cursor for one query. Null on a non-200
  /// first page; a later page failing keeps what already arrived.
  ///
  /// The API sets the grain per range (a whole-life `max` read at 12 h
  /// buckets is ~700 points, ~45 KB), so in practice this is one page.
  /// Bodies under 64 KB decode inline: spawning an isolate costs more than
  /// decoding a few hundred rows.
  Future<List<PolymarketPricePoint>?> _priceHistoryPages(
    Map<String, String> params,
    http.Client? client, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final points = <PolymarketPricePoint>[];
    String? cursor;
    for (var page = 0; page < _kPriceHistoryMaxPages; page++) {
      final uri = Uri.parse('$_dataApiV2/prices-history').replace(
        queryParameters: {...params, if (cursor != null) 'cursor': cursor},
      );
      final response =
          await (client ?? _dataApiClient).get(uri).timeout(timeout);
      if (response.statusCode != 200) return page == 0 ? null : points;
      final body = response.body;
      final parsed = body.length < 64 * 1024
          ? _parsePriceHistoryPage(body)
          : await Isolate.run(() => _parsePriceHistoryPage(body));
      points.addAll(parsed.points);
      cursor = parsed.nextCursor;
      if (cursor == null) break;
    }
    return points;
  }

  static List<PolymarketOutcome> _parseOutcomes(Market? market) {
    if (market == null) return [];
    final names = market.outcomesList;
    final prices = market.outcomePricesList;
    final tokens = market.tokenIdsList;

    return List.generate(names.length, (i) {
      return PolymarketOutcome(
        gammaMarketId: market.id.toString(),
        name: names[i],
        price: i < prices.length ? prices[i] : 0.0,
        tokenId: i < tokens.length ? tokens[i] : null,
      );
    });
  }

  /// Multi-market events: each market becomes an outcome (question as name, YES price).
  /// Single-market events: use the market's own outcomes (Yes/No or custom).
  static List<PolymarketOutcome> _buildEventOutcomes(List<Market> markets) {
    if (markets.isEmpty) return [];

    // Single market → use its own outcomes (Yes/No or custom)
    if (markets.length == 1) return _parseOutcomes(markets.first);

    // Multiple markets → each market is an outcome. Both YES and NO token ids
    // are kept; otherwise the bet slip falls back to a "Predict" CTA with no
    // YES/NO toggle, because `_isCandidatePicker` keys off `noTokenId`.
    return markets.map((m) {
      final question = m.question ?? 'Unknown';
      final yesPrice = m.yesPrice;
      final tokens = m.tokenIdsList;
      final yesTokenId = tokens.isNotEmpty ? tokens.first : null;
      final noTokenId = tokens.length > 1 ? tokens[1] : null;

      return PolymarketOutcome(
        gammaMarketId: m.id.toString(),
        name: question,
        price: yesPrice,
        tokenId: yesTokenId,
        noTokenId: noTokenId,
      );
    }).toList();
  }

  /// Build outcomes from raw JSON so we can pull `groupItemTitle` (candidate
  /// name), per-market `image`, and both YES/NO token ids — none of which are
  /// exposed by the SDK's Market model.
  static List<PolymarketOutcome> _buildOutcomesFromRaw(List<dynamic> markets) {
    if (markets.isEmpty) return [];

    if (markets.length == 1) {
      final m = markets.first as Map<String, dynamic>;
      final names = _jsonListStrings(m['outcomes']);
      final prices = _jsonListDoubles(m['outcomePrices']);
      final tokens = PolyMarketProtocol.outcomeIds(m);
      return List.generate(names.length, (i) {
        return PolymarketOutcome(
          name: names[i],
          price: i < prices.length ? prices[i] : 0.0,
          tokenId: i < tokens.length ? tokens[i] : null,
          conditionId: m['conditionId'] as String?,
          gammaMarketId: m['id']?.toString(),
        );
      });
    }

    // Multi-outcome (one market per candidate). `groupItemTitle` is
    // usually a candidate / team / option name ("Argentina",
    // "Tunisia") and that's what we show on the row.
    //
    // BUT some Polymarket events use `groupItemTitle` to label
    // SUB-QUESTIONS rather than candidates ("Map 1 Winner", "O/U 3.5
    // Games", "Odd/Even Total Rounds" on a CS:GO match event). For
    // those the short label loses the meaning — "Map 1 Winner · YES"
    // doesn't tell the user which team a YES bet wins on. Detect the
    // question-shaped labels and fall back to the full market
    // `question` field which carries the full context (e.g. "Will
    // Team Falcons win Map 1?").
    return markets.map((raw) {
      final m = raw as Map<String, dynamic>;
      final tokens = PolyMarketProtocol.outcomeIds(m);
      final prices = _jsonListDoubles(m['outcomePrices']);
      final candidate = (m['groupItemTitle'] as String?)?.trim();
      final question = (m['question'] as String?)?.trim() ?? 'Unknown';
      final isQuestionShaped =
          candidate != null && _kQuestionShapedRegex.hasMatch(candidate);
      final kind = (m['sportsMarketType'] as String?)?.trim() ?? '';
      final name = (candidate != null &&
              candidate.isNotEmpty &&
              !isQuestionShaped)
          ? candidate
          : question;
      final yesTokenId = tokens.isNotEmpty ? tokens.first : null;
      final noTokenId = tokens.length > 1 ? tokens[1] : null;
      // Polymarket's rule for the chance shown: the midpoint, or the last
      // trade when the spread is wider than 10¢ (Gamma's own figure counts
      // a missing bid as 0, so an ask alone at 74¢ read as 37%).
      final shown =
          polyGammaShownPrice(m, prices.isNotEmpty ? prices.first : 0.0);
      return PolymarketOutcome(
        name: name,
        price: shown.price,
        unpriced: shown.unpriced,
        tokenId: yesTokenId,
        noTokenId: noTokenId,
        // groupItemImage is the per-candidate image (team logo,
        // flag, candidate portrait) — exactly what polymarket.com
        // renders alongside each sub-market row. Fall back to the
        // generic per-market `image`/`icon` fields when the API
        // omits the group-item image.
        imageUrl: polymarketArtworkUrl(m['groupItemImage']) ??
            polymarketArtworkFromJson(m),
        volume: (m['volumeNum'] as num?)?.toDouble(),
        conditionId: m['conditionId'] as String?,
        gammaMarketId: m['id']?.toString(),
        marketLine: kind.isEmpty
            ? null
            : PolymarketMarketLine(
                kind: kind,
                question: question,
                line: _jsonNum(m['line']),
                sides: _jsonListStrings(m['outcomes']),
                prices: prices,
                closed: m['closed'] == true,
              ),
      );
    }).toList();
  }

  /// A sub-market label that reads as a question ("Map 1 Winner", "O/U
  /// 3.5 Games") rather than a candidate. Compiled once: the parser ran it
  /// for every market of every event (311 on one football game).
  static final RegExp _kQuestionShapedRegex = RegExp(
    r'\b(winner|total|over|under|o/u|odd/even|odd|even|spread|moneyline|first|last|exact|map\s*\d|game\s*\d|round\s*\d|set\s*\d|period|half|quarter|inning)\b',
    caseSensitive: false,
  );

  static double? _jsonNum(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static List<String> _jsonListStrings(dynamic v) {
    if (v == null) return [];
    try {
      final parsed = v is String ? jsonDecode(v) : v;
      if (parsed is List) return parsed.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }

  static List<double> _jsonListDoubles(dynamic v) {
    if (v == null) return [];
    try {
      final parsed = v is String ? jsonDecode(v) : v;
      if (parsed is List) {
        return parsed
            .map((e) => double.tryParse(e.toString()) ?? 0.0)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<PolymarketEvent>> listEvents({
    TagSlug? tag,
    int limit = 100,
    int offset = 0,
    bool hot = false,
    bool featured = false,
    String order = 'liquidity',
    bool preserveApiOrder = false,
  }) async {
    if (_disposed) return [];
    try {
      // Raw JSON fetch — the SDK's Market model omits groupItemTitle / image /
      // full clobTokenIds, which are needed to render candidate-style
      // multi-outcome rows (name, photo, YES/NO per candidate).
      // `/events/keyset` (was offset-paged `/events`); `hot` is passed
      // through unchanged — verified live that it orders both routes the
      // same way.
      final params = <String, String>{
        'active': 'true',
        'closed': 'false',
        'order': order,
        'ascending': 'false',
      };
      if (tag != null) params['tag_slug'] = tag.value;
      if (hot) params['hot'] = 'true';
      if (featured) params['featured'] = 'true';

      // Read and parsed off the UI isolate when large.
      final parsed =
          await _fetchGammaEvents(params, limit: limit, offset: offset);

      if (preserveApiOrder) return parsed;

      // Sort by 24h volume (trending = most bets recently) then liquidity
      parsed.sort((a, b) {
        final cmp = b.volume24hr.compareTo(a.volume24hr);
        return cmp != 0 ? cmp : b.liquidity.compareTo(a.liquidity);
      });

      return parsed;
    } catch (e) {
      return [];
    }
  }

  /// Markets with the largest 24h price move — backs the /breaking tab on
  /// Polymarket's web homepage ("markets that moved the most in the last
  /// 24h"). We hit Polymarket's own `/api/biggest-movers` because that's
  /// the endpoint the `/breaking` page uses (found by scanning their
  /// Next.js chunks). Gamma's `/markets/keyset?order=oneDayPriceChange`
  /// returns the same raw dataset but without the noise filters the
  /// frontend applies, so our rail ended up polluted with daily-temperature
  /// and micro-sports markets that the website hides.
  ///
  /// [category] is one of the page's own topic filters (`politics`,
  /// `world`, `sports`, `crypto`, `finance`, `tech`, `culture`); null is
  /// all of them. Rows come ranked by the size of the 24 h move, as the
  /// page shows them, and carry it in [PolymarketEvent.oneDayPriceChange].
  Future<List<PolymarketEvent>> listBiggestMovers(
      {int limit = 40, String? category}) async {
    if (_disposed) return [];
    try {
      final uri = Uri.parse('https://polymarket.com/api/biggest-movers')
          .replace(
              queryParameters: category == null || category == 'all'
                  ? null
                  : {'category': category});
      final resp = await http.get(
        uri,
        headers: {'user-agent': 'Mozilla/5.0 (KuteApp)'},
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body);
      final data = decoded is Map<String, dynamic>
          ? (decoded['markets'] as List? ?? const [])
          : const [];

      return data.take(limit).map<PolymarketEvent?>((raw) {
        final m = raw as Map<String, dynamic>;
        final names = _jsonListStrings(m['outcomes']);
        final prices = _jsonListDoubles(m['outcomePrices']);
        final tokens = PolyMarketProtocol.outcomeIds(m);
        final outcomes = List.generate(
          names.isEmpty ? prices.length : names.length,
          (i) {
            final name = i < names.length
                ? names[i]
                : (i == 0 ? 'Yes' : 'No');
            return PolymarketOutcome(
              name: name,
              price: i < prices.length ? prices[i] : 0.0,
              tokenId: i < tokens.length ? tokens[i] : null,
              conditionId: m['conditionId'] as String?,
              gammaMarketId: m['id']?.toString(),
            );
          },
        );
        // biggest-movers is a Yes/No markets endpoint; if the API didn't
        // return `outcomes`, synthesize Yes/No from prices so the card still
        // renders the right pills.
        final finalOutcomes = outcomes.isEmpty && prices.length >= 2
            ? [
                PolymarketOutcome(
                  name: 'Yes',
                  price: prices[0],
                  tokenId: tokens.isNotEmpty ? tokens[0] : null,
                  conditionId: m['conditionId'] as String?,
                  gammaMarketId: m['id']?.toString(),
                ),
                PolymarketOutcome(
                  name: 'No',
                  price: prices[1],
                  tokenId: tokens.length > 1 ? tokens[1] : null,
                  conditionId: m['conditionId'] as String?,
                  gammaMarketId: m['id']?.toString(),
                ),
              ]
            : outcomes;

        final parentEvents = (m['events'] as List?) ?? const [];
        final parent = parentEvents.isNotEmpty
            ? parentEvents.first as Map<String, dynamic>
            : null;

        DateTime? endDate;
        final endDateStr = m['endDate'] as String?;
        if (endDateStr != null) endDate = DateTime.tryParse(endDateStr);

        return PolymarketEvent(
          id: (m['id'] ?? '').toString(),
          slug: (parent?['slug'] as String?) ?? (m['slug'] as String? ?? ''),
          title: (m['question'] as String?) ?? 'Unknown',
          imageUrl: polymarketArtworkFromJson(m) ??
              polymarketArtworkFromJson(parent),
          volume: (parent?['volume'] as num?)?.toDouble() ?? 0,
          volume24hr: 0,
          liquidity: (m['liquidityNum'] as num?)?.toDouble() ?? 0,
          category: 'other',
          endDate: endDate,
          active: (m['active'] as bool?) ?? true,
          description: m['description'] as String?,
          conditionId: (m['conditionId'] as String?) ?? '',
          outcomes: finalOutcomes,
          negRisk: (m['negRisk'] as bool?) ??
              ((parent?['negRisk'] as bool?) ?? false),
          oneDayPriceChange: _moverChange(m),
          // The page's topic filter is the only category a mover row
          // carries; it lets the sports/politics policy see it.
          tags: category == null || category == 'all'
              ? const []
              : [category],
        );
      }).whereType<PolymarketEvent>().toList()
        ..sort((a, b) => (b.oneDayPriceChange ?? 0)
            .abs()
            .compareTo((a.oneDayPriceChange ?? 0).abs()));
    } catch (_) {
      return [];
    }
  }

  /// A mover's 24 h change as a fraction. polymarket.com/breaking ranks
  /// by `livePriceChange` (points, from the live price) and falls back to
  /// Gamma's `oneDayPriceChange` (a fraction).
  static double? _moverChange(Map<String, dynamic> m) {
    final live = m['livePriceChange'];
    if (live is num) return live.toDouble() / 100;
    final day = m['oneDayPriceChange'];
    if (day is num) return day.toDouble();
    return double.tryParse('${day ?? ''}');
  }

  /// Public wrapper around the private `_eventFromRawJson` parser so
  /// providers that fetch gamma JSON themselves (e.g.
  /// `polymarketEventsByTagIdProvider` filtering by `tag_id` instead
  /// of `tag_slug`) can normalise the response without duplicating
  /// the markets/outcomes parsing logic.
  List<PolymarketEvent> parseEventsRaw(List<Map<String, dynamic>> raw) {
    return raw.map(_eventFromRawJson).toList();
  }

  /// The feed's league code of a raw Gamma event: its teams' `league`
  /// ("nfl"), else the code its slug starts with.
  static String? _eventLeague(Map<String, dynamic> e) {
    for (final t in (e['teams'] as List? ?? const [])) {
      final league = t is Map ? t['league']?.toString().trim() : null;
      if (league != null && league.isNotEmpty) return league;
    }
    return leagueOfEventSlug(e['slug']?.toString());
  }

  static PolymarketEvent _eventFromRawJson(Map<String, dynamic> e) {
    // One entry per market when a V1 and a V2 twin are both listed.
    final markets =
        PolyMarketProtocol.withoutTwins((e['markets'] as List?) ?? const []);
    final primaryMarket =
        markets.isNotEmpty ? markets.first as Map<String, dynamic> : null;
    final outcomes = _buildOutcomesFromRaw(markets);
    double totalVolume = 0;
    double totalLiquidity = 0;
    for (final m in markets) {
      if (m is Map<String, dynamic>) {
        totalVolume += (m['volumeNum'] as num?)?.toDouble() ?? 0;
        // Gamma's per-market liquidity can land under any of these
        // keys depending on payload shape: `liquidityNum`,
        // `liquidityClob`, `liquidity`, or `liquidityAmm`. Falling
        // back through them keeps the displayed liquidity > 0 across
        // both the orderbook-only markets and the CLOB+AMM ones.
        final mLiq = (m['liquidityNum'] as num?)?.toDouble() ??
            (m['liquidityClob'] as num?)?.toDouble() ??
            (m['liquidity'] as num?)?.toDouble() ??
            (m['liquidityAmm'] as num?)?.toDouble() ??
            0;
        totalLiquidity += mLiq;
      }
    }
    // Event-level liquidity (`liquidityClob` / `liquidity`) is more
    // reliable than summing per-market values, which can be null or
    // 0 for sub-markets that haven't been seeded into Gamma's index.
    // Prefer event-level when it's non-zero.
    final eventLevelLiq = (e['liquidityClob'] as num?)?.toDouble() ??
        (e['liquidity'] as num?)?.toDouble() ??
        (e['liquidityNum'] as num?)?.toDouble() ??
        (e['liquidityAmm'] as num?)?.toDouble() ??
        0;
    if (eventLevelLiq > totalLiquidity) {
      totalLiquidity = eventLevelLiq;
    }

    DateTime? endDate;
    final endDateStr = e['endDate'] as String?;
    if (endDateStr != null) {
      endDate = DateTime.tryParse(endDateStr);
    }

    // Scheduled start/kickoff. Mirror endDate parsing. For sports Gamma also
    // exposes a per-market `gameStartTime`; prefer event `startDate` and fall
    // back to the primary market's gameStartTime when the event omits it.
    DateTime? startDate;
    final startDateStr = (e['startDate'] as String?) ??
        (primaryMarket?['gameStartTime'] as String?);
    if (startDateStr != null) {
      startDate = DateTime.tryParse(startDateStr);
    }
    // The kickoff itself, for the game's own window (chart, momentum).
    DateTime? parseDate(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    final gameStart = parseDate(primaryMarket?['gameStartTime']) ??
        parseDate(e['startTime']);
    final finishedAt = parseDate(e['finishedTimestamp']);

    final tagSlugs = <String>{};
    final tagList = e['tags'];
    if (tagList is List) {
      for (final t in tagList) {
        if (t is Map<String, dynamic>) {
          final slug = (t['slug'] as String?)?.toLowerCase();
          if (slug != null && slug.isNotEmpty) tagSlugs.add(slug);
        }
      }
    }

    String category;
    if (tagSlugs.contains('crypto') || tagSlugs.contains('cryptocurrency')) {
      category = 'crypto';
    } else if (tagSlugs.contains('sports')) {
      category = 'sports';
    } else if (tagSlugs.contains('politics')) {
      category = 'politics';
    } else if (tagSlugs.contains('science') || tagSlugs.contains('tech')) {
      category = 'science';
    } else {
      category = 'other';
    }

    // SAFE gameId parse: Gamma sends `gameId` as a number or string depending
    // on payload shape. A raw `as num?` cast throws on a String and would
    // bubble up to empty the whole event list, so switch + int.tryParse.
    final rawGameId = e['gameId'];
    int? gameId;
    switch (rawGameId) {
      case final int v:
        gameId = v;
      case final num v:
        gameId = v.toInt();
      case final String v:
        gameId = int.tryParse(v.trim());
      default:
        gameId = null;
    }

    final teams = (e['teams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PolymarketTeam.fromJson)
            .toList() ??
        const <PolymarketTeam>[];

    // Icon fallback chain (missing-event-icon fix): event image → event
    // icon → primary market image/icon → first outcome image → first team
    // crest. Gamma occasionally ships events (especially sports payload
    // variants) with a null or EMPTY-STRING top-level image while the
    // sub-markets or `teams[]` still carry real art; the old single
    // `image ?? icon` read left those cards on the generic category
    // placeholder. Empty strings are treated as missing so a "" never
    // shadows a usable fallback (an empty URL just errors the loader).
    final imageUrl = <String?>[
      polymarketArtworkFromJson(e),
      for (final market in markets.whereType<Map<String, dynamic>>())
        polymarketArtworkFromJson(market),
      for (final o in outcomes) polymarketArtworkUrl(o.imageUrl),
      for (final t in teams) t.logo,
    ].whereType<String>().firstOrNull;

    return PolymarketEvent(
      id: (e['id'] ?? '').toString(),
      slug: (e['slug'] as String?) ?? '',
      title: (e['title'] as String?) ?? 'Unknown Event',
      imageUrl: imageUrl,
      volume: totalVolume,
      volume24hr: (e['volume24hr'] as num?)?.toDouble() ?? 0,
      liquidity: totalLiquidity,
      category: category,
      startDate: startDate,
      endDate: endDate,
      active: (e['active'] as bool?) ?? true,
      // `closed` is the reliable Gamma settlement flag. Parse it on BOTH
      // event parse paths (here + `_flattenEventsForSearch`) so the
      // resolved-market filter catches a settled-but-still-`active:true`
      // market everywhere, including search-sourced cards.
      closed: (e['closed'] as bool?) ?? false,
      description: e['description'] as String?,
      conditionId: (primaryMarket?['conditionId'] as String?) ?? '',
      outcomes: outcomes,
      streamUrl:
          PolymarketEvent.streamUrlFrom(e['resolutionSource'] as String?),
      tags: tagSlugs.toList(growable: false),
      isLive: (e['live'] as bool?) ?? false,
      gameId: gameId,
      gameStart: gameStart,
      startTime: parseDate(e['startTime']),
      finishedAt: finishedAt,
      metadataGameId: PolymarketEvent.metadataGameIdFrom(e),
      // score/period/elapsed seed the detail header's score/clock from the
      // existing REST poll before the live WS ticks. All are String? — score
      // is "1-1" / "6-3, 3-6" not an int, but Gamma may still send any of them
      // as a number depending on payload shape. A raw `as String?` cast THROWS
      // on a non-null non-String (it does not yield null) and bubbles up to
      // empty the whole event list, so coerce with `?.toString()` to match the
      // elapsed/gameId/WS pattern and stay throw-safe.
      // Home first: Gamma writes the North American leagues away first
      // (feed_score_order.dart). The league is the teams' own, else the
      // code the slug starts with.
      score: feedScoreHomeFirst(e['score']?.toString(),
          league: _eventLeague(e)),
      period: e['period']?.toString(),
      elapsed: e['elapsed']?.toString(),
      ended: (e['ended'] as bool?) ?? false,
      negRisk: (e['negRisk'] as bool?) ?? false,
      teams: teams,
      oneDayPriceChange: _eventDayChange(markets),
      seriesId: _seriesIdOf(e),
      tweetCount: (e['tweetCount'] as num?)?.toInt(),
    );
  }

  /// The largest 24 h move among an event's markets (Gamma's
  /// `oneDayPriceChange`, a fraction), keeping its sign. Null when no
  /// market carries it.
  static double? _eventDayChange(List markets) {
    double? best;
    for (final m in markets.whereType<Map<String, dynamic>>()) {
      final raw = m['oneDayPriceChange'];
      final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
      if (v == null || !v.isFinite) continue;
      if (best == null || v.abs() > best.abs()) best = v;
    }
    return best;
  }

  static String? _seriesIdOf(Map<String, dynamic> e) {
    final series = e['series'];
    if (series is List && series.isNotEmpty && series.first is Map) {
      final id = (series.first as Map)['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// Bounded public typeahead. Never download the entire event catalog for
  /// each query; Gamma already searches event titles and outcome names.
  /// [eventsTag] limits the results to events carrying that tag slug
  /// (Gamma's `events_tag`), for a search scoped to one category.
  Future<List<PolymarketEvent>> searchEvents(String query,
      {String? eventsTag}) async {
    final q = query.trim();
    if (_disposed || q.isEmpty || q.length > 4000) return [];
    return _serverSearch(q, eventsTag: eventsTag);
  }

  /// One Gamma tag by slug (`/tags/slug/{slug}`): id, label, slug.
  Future<Map<String, dynamic>?> fetchGammaTag(String slug) async {
    if (_disposed) return null;
    final resp = await http
        .get(Uri.parse('$_gammaBase/tags/slug/${Uri.encodeComponent(slug)}'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic> || decoded['id'] == null) return null;
    return {
      'id': decoded['id'],
      'slug': decoded['slug'],
      'label': decoded['label'],
    };
  }

  /// The tags Polymarket relates to [tagId] that have open events
  /// (`/tags/{id}/related-tags/tags?status=active&omit_empty=true`), each
  /// with its `activeEventsCount`. Throws when Gamma does not answer.
  Future<List<Map<String, dynamic>>> fetchRelatedTags(int tagId) async {
    if (_disposed) return const [];
    final uri = Uri.parse('$_gammaBase/tags/$tagId/related-tags/tags')
        .replace(queryParameters: {'status': 'active', 'omit_empty': 'true'});
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw http.ClientException('related tags failed (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];
    return [
      for (final t in decoded.whereType<Map<String, dynamic>>())
        if (t['id'] != null)
          {
            'id': t['id'],
            'slug': t['slug'],
            'label': t['label'],
            'activeEventsCount': t['activeEventsCount'],
          }
    ];
  }

  /// Open-market counts per crypto subcategory, as polymarket.com's crypto
  /// page shows them (`/api/crypto/counts`: `{"all":"290","fiveM":"7",…}`).
  Future<Map<String, dynamic>?> fetchCryptoCounts() async {
    if (_disposed) return null;
    final resp = await http.get(
      Uri.parse('https://polymarket.com/api/crypto/counts'),
      headers: {'user-agent': 'Mozilla/5.0 (KuteApp)'},
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Gamma `/sports`: one row per league with its name, logo, series id
  /// and tag ids (`{sport, name, image, series, tags}`; `tags` is Gamma's
  /// comma-separated list, where 64 marks an esports league). Throws when
  /// Gamma does not answer.
  Future<List<Map<String, dynamic>>> fetchSportsLeagues() async {
    if (_disposed) return const [];
    final resp = await http
        .get(Uri.parse('$_gammaBase/sports'))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw http.ClientException('sports failed (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];
    return [
      for (final l in decoded.whereType<Map<String, dynamic>>())
        if (l['series'] != null)
          {
            'sport': l['sport'],
            'name': l['name'],
            'image': l['image'],
            'series': '${l['series']}',
            'tags': l['tags'],
          }
    ];
  }

  /// True when the query matches a candidate / outcome name (or a per-market
  /// question) on [e] as a whole word or word-prefix. Used to surface a match
  /// event by team / candidate name ("Spain", "Lakers") without the
  /// description-substring noise of the old over-broad matcher.
  static bool _candidateMatches(Event e, String ql) {
    if (ql.isEmpty) return false;
    final markets = e.markets;
    if (markets == null || markets.isEmpty) return false;
    bool tokenHit(String? raw) {
      if (raw == null) return false;
      final s = raw.toLowerCase();
      if (!s.contains(ql)) return false;
      // Whole-word or word-prefix: the query starts the string, or is
      // preceded by a non-letter (space, hyphen, etc.). Avoids matching
      // "spa" inside "transparency".
      for (final m in RegExp(RegExp.escape(ql)).allMatches(s)) {
        final i = m.start;
        if (i == 0) return true;
        final prev = s.codeUnitAt(i - 1);
        final isLetter =
            (prev >= 97 && prev <= 122) || (prev >= 48 && prev <= 57);
        if (!isLetter) return true;
      }
      return false;
    }

    for (final m in markets) {
      if (tokenHit(m.question)) return true;
      // `outcomes` is a JSON-encoded string list ("[\"Spain\",\"Cabo Verde\"]").
      final names = _jsonListStrings(m.outcomes);
      for (final n in names) {
        if (tokenHit(n)) return true;
      }
    }
    return false;
  }

  Future<List<PolymarketEvent>> _serverSearch(String query,
      {String? eventsTag}) async {
    final client = _searchClient ??= http.Client();
    try {
      final uri = Uri.parse('https://gamma-api.polymarket.com/public-search')
          .replace(queryParameters: {
        'q': query,
        if (eventsTag != null) 'events_tag': eventsTag,
        'events_status': 'active',
        'keep_closed_markets': '0',
        'limit_per_type': '30',
        'search_tags': 'false',
        'search_profiles': 'false',
        'sort': 'relevance',
      });
      final response = await client.send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 8));
      if (_disposed || response.statusCode != 200) return [];
      // Bound bytes before JSON decoding, even if a provider ignores its cap.
      const maxBytes = 4 * 1024 * 1024;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream
          .timeout(const Duration(seconds: 8))) {
        if (_disposed || bytes.length + chunk.length > maxBytes) return [];
        bytes.add(chunk);
      }
      if (_disposed) return [];
      final body = bytes.takeBytes();
      final result = await _parseSearchOffThread(body, query);
      return _disposed ? [] : result;
    } catch (_) {
      return [];
    } finally {
      client.close();
      if (identical(_searchClient, client)) _searchClient = null;
    }
  }

  // Only the bounded PUBLIC response is copied to the worker. Parsing and
  // sorting never block keyboard/scroll frames on older devices.
  static Future<List<PolymarketEvent>> _parseSearchOffThread(
      Uint8List bytes, String query) =>
      Isolate.run(() => _parseSearchResponse(bytes, query));

  static List<PolymarketEvent> _parseSearchResponse(
      Uint8List bytes, String query) {
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final rows = data['events'] as List? ?? [];
    final q = query.toLowerCase();
    final seen = <String>{};
    final ranked = <(int, int, Event)>[];
    for (final raw in rows.take(30)) {
      try {
        final event = Event.fromJson(PolyMarketProtocol.eventWithTradingIds(
            raw as Map<String, dynamic>));
        if (!event.active || event.closed || !seen.add(event.id)) continue;
        final title = (event.title ?? '').toLowerCase();
        final slug = (event.slug ?? '').toLowerCase();
        final rank = title.startsWith(q) ? 0
            : title.contains(q) ? 1
            : slug.contains(q) ? 2
            : _candidateMatches(event, q) ? 3 : 4;
        ranked.add((rank, ranked.length, event));
      } catch (_) {
        // A malformed event must not discard the other matching events.
      }
    }
    ranked.sort((a, b) {
      final rank = a.$1.compareTo(b.$1);
      return rank != 0 ? rank : a.$2.compareTo(b.$2);
    });
    return _flattenEventsForSearch(
        ranked.map((row) => row.$3).toList(), query);
  }

  static List<PolymarketEvent> _flattenEventsForSearch(
      List<Event> events, String query) {
    final results = <PolymarketEvent>[];

    for (final e in events) {
      final markets = e.markets ?? [];
      if (markets.isEmpty) continue;

      // Event-level liquidity (clob / amm / generic) is far more
      // reliable than the per-market liquidityNum which is often
      // null in Gamma's search payload — that's the root of the
      // long-standing "Liquidity $0" bug.
      final eventLiquidity = e.liquidityClob ??
          e.liquidity ??
          e.liquidityAmm ??
          0;

      // Single market → keep as one event (normal behavior)
      if (markets.length == 1) {
        final m = markets.first;
        results.add(PolymarketEvent(
          id: e.id,
          slug: e.slug ?? '',
          title: e.title ?? 'Unknown Event',
          // Same fallback spirit as `_eventFromRawJson`: the search payload
          // sometimes omits `image` while `featuredImage`/`icon` carry art.
          imageUrl: e.image ?? e.featuredImage ?? e.icon,
          volume: m.volumeNum ?? 0,
          volume24hr: e.volume24hr ?? 0,
          liquidity: (m.liquidityNum ?? 0) > 0
              ? (m.liquidityNum ?? 0)
              : eventLiquidity,
          category: _tagToCategory(e.tags),
          startDate: e.startDate,
          endDate: e.endDate,
          active: e.active,
          // Carry `closed` AND `ended` through the SEARCH path too. Without
          // this a settled-but-active:true market (Gamma keeps active:true
          // for a while after `closed`) slips through search as a tappable
          // card the CLOB rejects — the resolved-filter on
          // `polymarketSearchProvider` keys off these flags.
          closed: e.closed,
          ended: e.ended,
          negRisk: e.negRisk,
          description: e.description,
          conditionId: m.conditionId,
          outcomes: _parseOutcomes(m),
          streamUrl: PolymarketEvent.streamUrlFrom(e.resolutionSource),
          isLive: e.live,
          tags: _tagSlugs(e.tags),
        ));
        continue;
      }

      // Multi-market event → keep grouped, with each market as one
      // outcome. The previous behavior flattened each market into its
      // own result card, which produced the noisy "Will X win? / Will
      // they draw? / Will Y win?" row triplet for a single Porto vs
      // Santa Clara match. Polymarket's web UI shows one card per
      // event with three buttons (POR / DRAW / CDS), and we now match
      // that shape: one PolymarketEvent per event, with `outcomes`
      // carrying the per-market questions + yes-prices.
      final totalVolume = markets.fold<double>(
          0, (sum, m) => sum + (m.volumeNum ?? 0));
      final perMarketMax = markets.fold<double>(
          0, (max, m) => (m.liquidityNum ?? 0) > max ? (m.liquidityNum ?? 0) : max);
      final maxLiquidity = eventLiquidity > perMarketMax
          ? eventLiquidity
          : perMarketMax;
      results.add(PolymarketEvent(
        id: e.id,
        slug: e.slug ?? '',
        title: e.title ?? 'Unknown Event',
        imageUrl: e.image ?? e.featuredImage ?? e.icon,
        volume: totalVolume,
        volume24hr: e.volume24hr ?? 0,
        liquidity: maxLiquidity,
        category: _tagToCategory(e.tags),
        startDate: e.startDate,
        endDate: e.endDate,
        active: e.active,
        closed: e.closed,
        ended: e.ended,
        negRisk: e.negRisk,
        description: e.description,
        // For a multi-market event there's no single conditionId —
        // fall back to the first market's so the live-price cache
        // has something to key against. Per-outcome conditionIds
        // live on the individual `PolymarketOutcome` entries.
        conditionId: markets.first.conditionId,
        outcomes: _buildEventOutcomes(markets),
        streamUrl: PolymarketEvent.streamUrlFrom(e.resolutionSource),
        isLive: e.live,
        tags: _tagSlugs(e.tags),
      ));
    }

    return results;
  }

  static List<String> _tagSlugs(List<Tag>? tags) => [
        for (final t in tags ?? const <Tag>[])
          if ((t.slug ?? '').isNotEmpty) t.slug!.toLowerCase(),
      ];

  static String _tagToCategory(List<Tag>? tags) {
    if (tags == null || tags.isEmpty) return 'other';
    final slugs = tags
        .map((t) => t.slug?.toLowerCase() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    if (slugs.contains('crypto') || slugs.contains('cryptocurrency')) {
      return 'crypto';
    }
    if (slugs.contains('sports')) return 'sports';
    if (slugs.contains('politics')) return 'politics';
    if (slugs.contains('science') || slugs.contains('tech')) return 'science';
    return 'other';
  }

  Future<Map<String, dynamic>> getSportsMetadata() async {
    if (_disposed) return {};
    try {
      final resp = await http.get(
        Uri.parse('https://gamma-api.polymarket.com/sports'),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return {};
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) return data;
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<List<String>> getSportsMarketTypes() async {
    if (_disposed) return [];
    try {
      final resp = await http.get(
        Uri.parse('https://gamma-api.polymarket.com/sports/market-types'),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is List) return data.cast<String>();
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Events belonging to a specific series (e.g. all weekly / monthly
  /// instances of a recurring market). Uses the Gamma API's `series_id`
  /// filter and reuses the main event parser so cards render the same
  /// way as the category streams.
  Future<List<PolymarketEvent>> getEventsForSeries(int seriesId) async {
    if (_disposed || seriesId == 0) return [];
    try {
      final params = <String, String>{
        'series_id': '$seriesId',
        'active': 'true',
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
      };
      final data = await fetchGammaKeyset('events', params, limit: 100);
      return data.map(_eventFromRawJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Series>> listSeries({
    int limit = 50,
    int offset = 0,
    RecurrenceType? recurrence,
    bool? closed,
  }) async {
    if (_disposed) return [];
    try {
      final params = <String, String>{
        'limit': '$limit',
        'offset': '$offset',
        'closed': '${closed ?? false}',
        'order': 'volume',
        'ascending': 'false',
      };
      if (recurrence != null) {
        params['recurrence'] = recurrence.toString().split('.').last;
      }
      final uri = Uri.parse('https://gamma-api.polymarket.com/series')
          .replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body);
      if (body is! List) return [];
      return body
          .whereType<Map<String, dynamic>>()
          .map(Series.fromJson)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Tag>> listTags({int limit = 100}) async {
    if (_disposed) return [];
    try {
      final uri = Uri.parse('https://gamma-api.polymarket.com/tags')
          .replace(queryParameters: {'limit': '$limit'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body);
      if (body is! List) return [];
      return body
          .whereType<Map<String, dynamic>>()
          .map(Tag.fromJson)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Tag>> getRelatedTags(int tagId) async {
    if (_disposed) return [];
    try {
      final uri =
          Uri.parse('https://gamma-api.polymarket.com/tags/$tagId/related-tags');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body);
      if (body is! List) return [];
      return body
          .whereType<Map<String, dynamic>>()
          .map(Tag.fromJson)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, String>> getAccountingSnapshot(String walletAddress) async {
    if (_disposed) return {};
    try {
      final addr = walletAddress.toLowerCase();
      final result = <String, String>{};

      // Raw v2 bodies (`{data: [...], pagination}` envelopes, snake_case
      // rows); `/v2/trades` serves at most 1000 rows per page.
      final tradesResp = await http.get(
        Uri.parse('$_dataApiV2/trades').replace(
          queryParameters: {'user': addr, 'limit': '1000'},
        ),
      ).timeout(const Duration(seconds: 15));
      if (tradesResp.statusCode == 200) {
        result['trades'] = tradesResp.body;
      }

      final actResp = await http.get(
        Uri.parse('$_dataApiV2/activity').replace(
          queryParameters: {'user': addr},
        ),
      ).timeout(const Duration(seconds: 15));
      if (actResp.statusCode == 200) {
        result['activity'] = actResp.body;
      }

      return result;
    } catch (e) {
      return {};
    }
  }

  /// Fetches a single Gamma event by slug from `GET /events/slug/{slug}`,
  /// which returns the event object itself (the same item shape the offset
  /// `GET /events?slug=` list carried; that list route answers
  /// `deprecation: true` with a `sunset` of 2026-05-01 and is gone at any
  /// moment). A 404 means no such event. Throws on 404 / parse failure so
  /// callers' try/catch retry blocks (previous/current 5-min window etc.)
  /// keep working.
  Future<Map<String, dynamic>> _fetchEventBySlugRaw(String slug) async {
    final uri = Uri.parse(
        '$_gammaBase/events/slug/${Uri.encodeComponent(slug)}');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 404) {
      throw Exception('event not found for slug=$slug');
    }
    if (resp.statusCode != 200) {
      throw Exception('event slug fetch failed: ${resp.statusCode}');
    }
    // A game's event is about a megabyte of JSON (every sub-market with
    // its description): decoded off the UI isolate.
    final text = resp.body;
    final body = text.length < 64 * 1024
        ? jsonDecode(text)
        : await Isolate.run(() => jsonDecode(text));
    if (body is! Map<String, dynamic> || body['slug'] == null) {
      throw Exception('malformed event payload for slug=$slug');
    }
    return body;
  }

  /// Fetch just the `teams` (crest logos) for an event by slug. Used to
  /// backfill team logos on events that arrived without them — the search
  /// API path parses through polybrainz `Event`, which drops the `teams`
  /// array, so search-opened sports events otherwise show initials.
  Future<List<PolymarketTeam>> fetchEventTeams(String slug) async {
    if (slug.isEmpty) return const [];
    try {
      final raw = await _fetchEventBySlugRaw(slug);
      final t = raw['teams'];
      if (t is List) {
        return t
            .whereType<Map<String, dynamic>>()
            .map(PolymarketTeam.fromJson)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  // Use the same raw parser the browse list uses. Going through the SDK's
  // `Market` model dropped per-row `noTokenId`, which collapsed the bet slip
  // back to a "Predict" CTA on every multi-outcome event opened by slug
  // (e.g. soccer 1X2 sheets like Portugal vs DR Congo).
  Future<PolymarketEvent?> getEventDetailsBySlug(String slug) async {
    if (_disposed || slug.isEmpty) return null;
    try {
      final raw = await _fetchEventBySlugRaw(slug);
      return _eventFromRawJson(raw);
    } catch (e) {
      return null;
    }
  }

  Future<List<Comment>> getEventComments(
    int eventId, {
    int limit = 20,
    CommentOrderBy? order,
  }) async {
    if (_disposed) return [];
    try {
      final orderValue =
          (order ?? CommentOrderBy.createdAt).toString().split('.').last;
      final uri = Uri.parse('https://gamma-api.polymarket.com/comments')
          .replace(queryParameters: {
        'parent_entity_type': 'Event',
        'parent_entity_id': '$eventId',
        'limit': '$limit',
        'order': orderValue,
        'ascending': 'false',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body);
      if (body is! List) return [];
      return body
          .whereType<Map<String, dynamic>>()
          .map(Comment.fromJson)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// The windows Polymarket publishes crypto Up-or-Down markets in, in
  /// minutes, that this app knows how to name. Which of them exist for
  /// an asset today is asked of Polymarket ([discoverCryptoWindows]),
  /// never assumed.
  static const kCryptoWindowCandidates = [5];

  /// Slug of the Up-or-Down market for [asset] in the [minutes]-long
  /// window that contains now, or [windowsBack] windows earlier.
  static String cryptoWindowSlug(String asset, int minutes,
      {int windowsBack = 0}) {
    final span = minutes * 60;
    final epoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final windowStart = ((epoch ~/ span) - windowsBack) * span;
    return '${asset.toLowerCase()}-updown-${minutes}m-$windowStart';
  }

  /// The live Up-or-Down market for [asset] in the [minutes] window: the
  /// current window, or the previous one while the current is not yet
  /// created. Null when Polymarket has neither.
  Future<Btc5MinEvent?> getCryptoWindowEvent(String asset, int minutes) async {
    if (_disposed) return null;
    try {
      try {
        return await _fetchCryptoWindowEvent(cryptoWindowSlug(asset, minutes));
      } catch (_) {
        return await _fetchCryptoWindowEvent(
            cryptoWindowSlug(asset, minutes, windowsBack: 1));
      }
    } catch (e) {
      return null;
    }
  }

  /// One Up-or-Down window by slug, with Gamma's own price to beat when
  /// it carries one (`eventMetadata.priceToBeat`: present on finished
  /// windows, often missing on the live one). Throws when Gamma has no
  /// such event.
  Future<Btc5MinEvent> _fetchCryptoWindowEvent(String slug) async {
    final raw = await _fetchEventBySlugRaw(slug);
    final meta = raw['eventMetadata'];
    final ptb = meta is Map ? meta['priceToBeat'] : null;
    final priceToBeat = ptb is num ? ptb.toDouble() : double.tryParse('$ptb');
    return Btc5MinEvent.fromEvent(
      Event.fromJson(PolyMarketProtocol.eventWithTradingIds(raw)),
      priceToBeat:
          priceToBeat != null && priceToBeat.isFinite && priceToBeat > 0
              ? priceToBeat
              : null,
    );
  }

  /// Which of [kCryptoWindowCandidates] Polymarket currently runs for
  /// [asset], asked in parallel; a window counts when its current or
  /// previous market exists. Falls back to the five-minute window alone
  /// when nothing answers, so the screen always has one.
  Future<List<int>> discoverCryptoWindows(String asset) async {
    if (_disposed) return const [5];
    final found = await Future.wait(kCryptoWindowCandidates.map((m) async {
      for (final back in const [0, 1]) {
        try {
          await _fetchEventBySlugRaw(
              cryptoWindowSlug(asset, m, windowsBack: back));
          return m;
        } catch (_) {}
      }
      return null;
    }));
    final windows = found.whereType<int>().toList()..sort();
    return windows.isEmpty ? const [5] : windows;
  }

  Future<Btc5MinEvent?> getBtc5MinEvent() => getCryptoWindowEvent('BTC', 5);

  Future<Btc5MinEvent?> getCryptoUpdown5MinEvent(
    String asset, {
    /// When non-null, fetches the specific window whose start epoch
    /// (seconds, aligned to [minutes]) is `targetWindowEpoch`. Used by
    /// the Instant tab's window-picker so users can pre-stage a bet on
    /// an upcoming round (#163). When null, falls back to the
    /// current/previous window.
    int? targetWindowEpoch,
    int minutes = 5,
  }) async {
    if (_disposed) return null;
    try {
      if (targetWindowEpoch != null) {
        final slug =
            '${asset.toLowerCase()}-updown-${minutes}m-$targetWindowEpoch';
        return await _fetchCryptoWindowEvent(slug);
      }
      return await getCryptoWindowEvent(asset, minutes);
    } catch (e) {
      return null;
    }
  }

  /// Polymarket's own "Price to beat" for a crypto Up/Down window: the
  /// `openPrice` polymarket.com shows, from the endpoint its event page
  /// calls (`/api/crypto/crypto-price`, with the TWAP parameters every
  /// crypto Up/Down market carries today). It equals the Chainlink TWAP
  /// point stamped at the window start, and Gamma's
  /// `eventMetadata.priceToBeat` once Gamma has it. Null when the window
  /// length has no variant name, the window has not opened, or the
  /// answer is not in yet (it can lag the boundary by several seconds).
  Future<double?> fetchCryptoWindowOpenPrice({
    required String asset,
    required DateTime windowStart,
    required int minutes,
  }) async {
    if (_disposed) return null;
    const variants = {5: 'fiveminute', 15: 'fifteen', 240: 'fourhour'};
    final variant = variants[minutes];
    if (variant == null) return null;
    String iso(DateTime t) =>
        '${t.toUtc().toIso8601String().split('.').first}Z';
    try {
      final uri = Uri.parse('https://polymarket.com/api/crypto/crypto-price')
          .replace(queryParameters: {
        'symbol': asset.toUpperCase(),
        'eventStartTime': iso(windowStart),
        'variant': variant,
        'endDate': iso(windowStart.add(Duration(minutes: minutes))),
        'twapEnabled': 'true',
        'twapLookbackSeconds': '$kCryptoTwapLookbackSeconds',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map) return null;
      final open = body['openPrice'];
      final p = open is num ? open.toDouble() : double.tryParse('$open');
      return p != null && p.isFinite && p > 0 ? p : null;
    } catch (_) {
      return null;
    }
  }

  /// One (timestamp, price) tuple — wire shape mirrors the chart's
  /// `BtcPriceSnapshot` but the model layer can't depend on the
  /// provider layer where that class lives, so we keep it self-typed.
  ///
  /// See [fetchCoingeckoRecentPrices].
  // ignore: unintended_html_in_doc_comment
  /// Returns recent USD prices for `coingeckoId` from CoinGecko's free
  /// `market_chart` endpoint over the last ~hour. Used by [BtcPredictChart]
  /// to bootstrap `priceHistory` so the curve shows up immediately
  /// instead of sitting on "Loading prices..." for ~10s while the
  /// reference-price socket spins up (#164). Returns an empty list on any failure —
  /// the chart already has a CoinGecko spot-poll fallback after that.
  ///
  /// CoinGecko's free tier serves 5-minute granularity at `days=1`,
  /// which is enough resolution for the 5-min chart window: 12 points
  /// in the last hour gives the curve a visible shape on first paint
  /// before the live ticker starts filling in.
  /// Dense per-second price backfill from Binance's public klines REST
  /// (interval=1s), so the 5-minute hero chart opens with the FULL window
  /// already drawn instead of only accumulating ticks from mount (the
  /// CoinGecko bootstrap serves 5-minute granularity, i.e. one point per
  /// window). All four predict assets trade on Binance as `<ASSET>USDT`.
  /// Returns close prices with their close times, oldest first; empty on
  /// any failure so callers fall back to CoinGecko.
  Future<List<({DateTime t, double p})>> fetchBinanceRecentPrices(
    String asset, {
    int seconds = 360,
  }) async {
    if (_disposed) return const [];
    try {
      final symbol = '${asset.toUpperCase()}USDT';
      final uri = Uri.parse(
          'https://api.binance.com/api/v3/klines?symbol=$symbol'
          '&interval=1s&limit=${seconds.clamp(1, 1000)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return const [];
      final out = <({DateTime t, double p})>[];
      for (final row in decoded) {
        if (row is! List || row.length < 7) continue;
        final closeTime = (row[6] as num?)?.toInt();
        final close = double.tryParse(row[4]?.toString() ?? '');
        if (closeTime == null || close == null || close <= 0) continue;
        out.add((
          t: DateTime.fromMillisecondsSinceEpoch(closeTime),
          p: close,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<({DateTime t, double p})>> fetchCoingeckoRecentPrices(
    String coingeckoId,
  ) async {
    if (_disposed) return const [];
    try {
      // `days=1` returns auto-granularity (5min for the free tier).
      // We grab the whole day and let the caller window-clip it down
      // to whatever range its UI cares about.
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/$coingeckoId/market_chart'
        '?vs_currency=usd&days=1',
      );
      final resp = await http
          .get(uri, headers: {'accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body);
      if (body is! Map) return const [];
      final prices = body['prices'];
      if (prices is! List) return const [];
      final out = <({DateTime t, double p})>[];
      for (final entry in prices) {
        if (entry is! List || entry.length < 2) continue;
        final tsMs = entry[0];
        final price = entry[1];
        final tsInt = tsMs is int
            ? tsMs
            : tsMs is double
                ? tsMs.toInt()
                : int.tryParse(tsMs.toString());
        final priceNum = price is num
            ? price.toDouble()
            : double.tryParse(price.toString());
        if (tsInt == null || priceNum == null || priceNum <= 0) continue;
        out.add((
          t: DateTime.fromMillisecondsSinceEpoch(tsInt),
          p: priceNum,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Recent spot prices for the crypto Up/Down charts: Binance 1 s klines
  /// ([fetchBinanceRecentPrices]), with CoinGecko's 5-minute candles
  /// ([fetchCoingeckoRecentPrices], when [coingeckoId] is known) started as
  /// soon as Binance comes back empty or has not answered within
  /// [hedgeAfter]. Where Binance is unreachable it used to cost its whole
  /// 6 s timeout before the fallback even started; the chart sat on its
  /// skeleton meanwhile. The first non-empty answer wins, with the feed
  /// it came from so the caller never mixes the two; empty when both
  /// fail. Used only while Polymarket's own Chainlink feed is silent.
  Future<({CryptoPriceFeed feed, List<({DateTime t, double p})> points})>
      fetchRecentSpotPrices(
    String asset,
    String? coingeckoId, {
    Duration hedgeAfter = const Duration(milliseconds: 1500),
  }) {
    final done = Completer<
        ({CryptoPriceFeed feed, List<({DateTime t, double p})> points})>();
    var binanceDone = false;
    var geckoDone = coingeckoId == null;
    var geckoStarted = false;
    void settle(CryptoPriceFeed feed, List<({DateTime t, double p})> points) {
      if (done.isCompleted) return;
      if (points.isNotEmpty || (binanceDone && geckoDone)) {
        done.complete((feed: feed, points: points));
      }
    }

    void startGecko() {
      if (geckoStarted || coingeckoId == null) return;
      geckoStarted = true;
      fetchCoingeckoRecentPrices(coingeckoId).then((points) {
        geckoDone = true;
        settle(CryptoPriceFeed.coingecko, points);
      });
    }

    final hedge = Timer(hedgeAfter, startGecko);
    fetchBinanceRecentPrices(asset).then((points) {
      binanceDone = true;
      hedge.cancel();
      if (points.isEmpty) startGecko();
      settle(CryptoPriceFeed.binance, points);
    });
    return done.future;
  }

  /// USD spot prices from CoinGecko's public `simple/price`, ONE request
  /// for every id in [coingeckoIds] (the endpoint accepts a
  /// comma-separated list). The last-resort live feed for the crypto
  /// Up/Down cards, used only while Polymarket's Chainlink feed is silent
  /// and Binance did not answer. Returns whatever subset parsed; empty
  /// map on failure.
  Future<Map<String, double>> fetchCoingeckoSpotUsdMulti(
    List<String> coingeckoIds,
  ) async {
    if (_disposed || coingeckoIds.isEmpty) return const {};
    try {
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price'
        '?ids=${coingeckoIds.join(',')}&vs_currencies=usd',
      );
      final resp = await http
          .get(uri, headers: {'accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return const {};
      final body = jsonDecode(resp.body);
      if (body is! Map) return const {};
      final out = <String, double>{};
      for (final id in coingeckoIds) {
        final entry = body[id];
        if (entry is! Map) continue;
        final usd = entry['usd'];
        final p = usd is num
            ? usd.toDouble()
            : usd is String
                ? double.tryParse(usd)
                : null;
        if (p != null && p > 0) out[id] = p;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<OrderBook> getOrderBook(String tokenId) async {
    final uri = Uri.parse('https://clob.polymarket.com/book')
        .replace(queryParameters: {'token_id': tokenId});
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('orderbook fetch failed: ${resp.statusCode}');
    }
    return parsePolymarketOrderBook(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  void dispose() {
    _disposed = true;
    _searchClient?.close();
    _searchClient = null;
  }
}

class Btc5MinEvent {
  final String slug;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? windowStartTime; // parsed from slug
  final double upPrice; // probability of "Up"
  final double downPrice; // probability of "Down"
  final String? upTokenId;
  final String? downTokenId;
  /// CLOB `conditionId` of the underlying market. Needed by the
  /// chart's WS trade-stream consumer (#164/#166) to seed initial
  /// trades from the Data API before the live stream kicks in.
  final String? conditionId;
  final String? image;
  final bool active;
  final bool closed;

  /// Gamma's `eventMetadata.priceToBeat` — Polymarket's own strike for
  /// the window, when Gamma already carries it.
  final double? priceToBeat;

  const Btc5MinEvent({
    required this.slug,
    required this.title,
    this.startDate,
    this.endDate,
    this.windowStartTime,
    required this.upPrice,
    required this.downPrice,
    this.upTokenId,
    this.downTokenId,
    this.conditionId,
    this.image,
    this.active = true,
    this.closed = false,
    this.priceToBeat,
  });

  static DateTime? _parseWindowStart(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    final parts = slug.split('-');
    final ts = int.tryParse(parts.last);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
  }

  factory Btc5MinEvent.fromEvent(Event event, {double? priceToBeat}) {
    final markets = event.markets ?? [];
    final market = markets.isNotEmpty ? markets.first : null;

    final outcomes = market?.outcomesList ?? [];
    final prices = market?.outcomePricesList ?? [];
    final tokens = market?.tokenIdsList ?? [];

    // Outcomes are typically ["Up", "Down"]
    final upIdx = outcomes.indexWhere(
        (o) => o.toLowerCase() == 'up' || o.toLowerCase() == 'yes');
    final downIdx = outcomes.indexWhere(
        (o) => o.toLowerCase() == 'down' || o.toLowerCase() == 'no');

    return Btc5MinEvent(
      slug: event.slug ?? '',
      title: event.title ?? 'BTC 5 Min Up or Down',
      startDate: event.startDate,
      endDate: event.endDate,
      windowStartTime: _parseWindowStart(event.slug),
      upPrice: (upIdx >= 0 && upIdx < prices.length) ? prices[upIdx] : 0.50,
      downPrice:
          (downIdx >= 0 && downIdx < prices.length) ? prices[downIdx] : 0.50,
      upTokenId: (upIdx >= 0 && upIdx < tokens.length) ? tokens[upIdx] : null,
      downTokenId:
          (downIdx >= 0 && downIdx < tokens.length) ? tokens[downIdx] : null,
      conditionId: market?.conditionId,
      image: event.image,
      active: event.active,
      closed: event.closed,
      priceToBeat: priceToBeat,
    );
  }

  int get secondsRemaining {
    if (endDate == null) return 0;
    final diff = endDate!.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  bool get isExpired => secondsRemaining <= 0;
}

/// One decoded keyset page: its rows and the cursor for the next.
class _KeysetPage {
  const _KeysetPage(this.rows, this.next);
  final List<Map<String, dynamic>> rows;
  final String? next;
}

_KeysetPage? _parseKeysetPage(String body, String resource) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return null;
  final rows = decoded[resource];
  if (rows is! List) return null;
  final next = decoded['next_cursor'];
  return _KeysetPage(
    rows.whereType<Map<String, dynamic>>().toList(),
    next is String ? next : null,
  );
}

/// One parsed events page: the events, the rows the page held before any
/// were dropped (for paging) and the cursor of the next page.
class _KeysetEvents {
  const _KeysetEvents(this.events, this.rowCount, this.next);
  final List<PolymarketEvent> events;
  final int rowCount;
  final String? next;
}

/// Decodes and parses one events page; in a worker isolate [protocol]
/// carries the app isolate's V2 switches in first.
_KeysetEvents? _parseKeysetEvents(
    ({
      String body,
      bool activeOnly,
      ({bool tradingEnabled, Set<String> debugV2Ids})? protocol,
    }) args) {
  if (args.protocol case final p?) PolyMarketProtocol.adoptWorkerState(p);
  final page = _parseKeysetPage(args.body, 'events');
  if (page == null) return null;
  final events = <PolymarketEvent>[
    for (final row in page.rows)
      if (!args.activeOnly || row['active'] != false)
        PolymarketModel._eventFromRawJson(row),
  ];
  return _KeysetEvents(events, page.rows.length, page.next);
}
