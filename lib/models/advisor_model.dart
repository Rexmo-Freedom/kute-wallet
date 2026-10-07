// lib/models/advisor_model.dart
//
// Response contract for Sal public information and educational answers
// (backend schema version 3). The app renders [AdvisorResponse.blocks] as
// answer text, verified market cards and tappable [AdvisorActionButton]s
// wired through the ActionDispatcher. A market's figures arrive typed on
// [AdvisorBlock.card], built by the backend from provider data; the model
// never writes them. Parsing is defensive: a malformed field never throws,
// it just degrades (skipped block / dropped button / missing figure).

import 'package:kute/l10n/l10n.dart' show appL10n;
import 'package:flutter/foundation.dart';

@immutable
class AdvisorResponse {
  final List<AdvisorBlock> blocks;

  const AdvisorResponse({this.blocks = const []});

  factory AdvisorResponse.fromJson(Map<String, dynamic> json) {
    final blocks = <AdvisorBlock>[];
    final rawBlocks = json['blocks'];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is Map) {
          final block = AdvisorBlock.tryParse(Map<String, dynamic>.from(b));
          if (block != null) blocks.add(block);
        }
      }
    }
    return AdvisorResponse(blocks: blocks);
  }
}

enum AdvisorBlockKind { answer, info, market }

@immutable
class AdvisorBlock {
  final String id;
  final AdvisorBlockKind kind;
  final String markdown;
  final String? title;

  /// The verified public snapshot of a market (kind `market` only).
  final AdvisorCard? card;
  final List<AdvisorActionButton> actions;
  final String? section;
  final List<AdvisorSource> sources;
  final String? transactionDate;
  final String? disclosureDate;

  const AdvisorBlock({
    required this.id,
    required this.kind,
    required this.markdown,
    this.title,
    this.card,
    this.actions = const [],
    this.section,
    this.sources = const [],
    this.transactionDate,
    this.disclosureDate,
  });

  /// Returns null when there is nothing renderable (no text, buttons, or
  /// market card).
  static AdvisorBlock? tryParse(Map<String, dynamic> j) {
    var markdown = (j['markdown'] ?? '').toString();
    // Defensive guard: never render the raw advisor-contract JSON to the user.
    // If a regressed backend dumped the model's unparsed output into a
    // block's markdown, swap it for a friendly line instead of showing braces.
    final trimmed = markdown.trimLeft();
    if (trimmed.startsWith('{') &&
        (trimmed.contains('"blocks"') || trimmed.contains('"schemaVersion"'))) {
      markdown = appL10n().salCouldNotCompose;
    }

    final actions = <AdvisorActionButton>[];
    final rawActions = j['actions'];
    if (rawActions is List) {
      for (final a in rawActions) {
        if (a is Map) {
          final btn = AdvisorActionButton.tryParse(a.cast<String, dynamic>());
          if (btn != null) actions.add(btn);
        }
      }
    }

    final sources = <AdvisorSource>[];
    if (j['sources'] is List) {
      for (final raw in (j['sources'] as List).take(8)) {
        if (raw is Map) {
          final source = AdvisorSource.tryParse(Map<String, dynamic>.from(raw));
          if (source != null) sources.add(source);
        }
      }
    }

    final rawCard = j['card'];
    final card = rawCard is Map
        ? AdvisorCard.tryParse(Map<String, dynamic>.from(rawCard))
        : null;

    if (markdown.trim().isEmpty && actions.isEmpty && card == null) {
      return null;
    }

    return AdvisorBlock(
      id: (j['id'] ?? '').toString(),
      kind: card != null
          ? AdvisorBlockKind.market
          : j['kind'] == 'info'
              ? AdvisorBlockKind.info
              : AdvisorBlockKind.answer,
      markdown: markdown,
      title: _nonEmpty(j['title']),
      card: card,
      actions: actions,
      section: const {'stocks', 'crypto_perps', 'predictions', 'activity'}
              .contains(j['section'])
          ? j['section'] as String
          : null,
      sources: sources,
      transactionDate: _nonEmpty(j['transactionDate']),
      disclosureDate: _nonEmpty(j['disclosureDate']),
    );
  }
}

/// A verified market snapshot. Prices and deltas of [outcomes] are
/// fractions (0..1); [AdvisorCardPerp.change24hPct] is already a percent.
@immutable
class AdvisorCard {
  final String venue; // hyperliquid | polymarket
  final String id; // Hyperliquid wire coin, or the Polymarket event slug
  final String? slug;
  final String? submarketId;
  final String? instrument;
  final String? category;
  final String? imageUrl;
  final String? asOf;
  final String? closesAt;
  final List<AdvisorCardOutcome> outcomes;
  final AdvisorCardLive? live;
  final AdvisorCardPerp? perp;
  final AdvisorCardSpot? spot;
  final List<AdvisorCardRelated> related;
  final String? resolutionRules;

  const AdvisorCard({
    required this.venue,
    required this.id,
    this.slug,
    this.submarketId,
    this.instrument,
    this.category,
    this.imageUrl,
    this.asOf,
    this.closesAt,
    this.outcomes = const [],
    this.live,
    this.perp,
    this.spot,
    this.related = const [],
    this.resolutionRules,
  });

  /// The market's identity across the `card` event and the `done` blocks.
  String get key => '$venue:$id${submarketId == null ? '' : ':$submarketId'}';

  static AdvisorCard? tryParse(Map<String, dynamic> j) {
    final venue = _nonEmpty(j['venue']);
    final id = _nonEmpty(j['id']);
    if (id == null || !const {'hyperliquid', 'polymarket'}.contains(venue)) {
      return null;
    }
    List<T> list<T>(Object? raw, T? Function(Map<String, dynamic>) parse,
        {int max = 12}) {
      final out = <T>[];
      if (raw is List) {
        for (final item in raw) {
          if (out.length == max) break;
          if (item is Map) {
            final parsed = parse(Map<String, dynamic>.from(item));
            if (parsed != null) out.add(parsed);
          }
        }
      }
      return out;
    }

    Map<String, dynamic>? map(Object? raw) =>
        raw is Map ? Map<String, dynamic>.from(raw) : null;
    final live = map(j['live']);
    final perp = map(j['perp']);
    final spot = map(j['spot']);
    return AdvisorCard(
      venue: venue!,
      id: id,
      slug: _nonEmpty(j['slug']),
      submarketId: _nonEmpty(j['submarketId']),
      instrument: _nonEmpty(j['instrument']),
      category: _nonEmpty(j['category']),
      imageUrl: _nonEmpty(j['imageUrl']),
      asOf: _nonEmpty(j['asOf']),
      closesAt: _nonEmpty(j['closesAt']),
      outcomes: list(j['outcomes'], AdvisorCardOutcome.tryParse),
      live: live == null ? null : AdvisorCardLive.tryParse(live),
      perp: perp == null ? null : AdvisorCardPerp.tryParse(perp),
      spot: spot == null ? null : AdvisorCardSpot.tryParse(spot),
      related: list(j['related'], AdvisorCardRelated.tryParse, max: 6),
      resolutionRules: _nonEmpty(j['resolutionRules']),
    );
  }
}

@immutable
class AdvisorCardOutcome {
  final String id;
  final String label;
  final double price;
  final double? delta24h;
  const AdvisorCardOutcome(
      {required this.id,
      required this.label,
      required this.price,
      this.delta24h});

  static AdvisorCardOutcome? tryParse(Map<String, dynamic> j) {
    final label = _nonEmpty(j['label']);
    final price = _number(j['price']);
    if (label == null || price == null || price < 0 || price > 1) return null;
    final delta = _number(j['delta24h']);
    return AdvisorCardOutcome(
      id: _nonEmpty(j['id']) ?? label,
      label: label,
      price: price,
      delta24h: delta != null && delta >= -1 && delta <= 1 ? delta : null,
    );
  }
}

@immutable
class AdvisorCardLive {
  final String state; // scheduled | live | ended
  final String? home;
  final String? away;
  final String? score;
  final String? period;
  final String? elapsed;
  final String? startsAt;
  final String? finishedAt;
  const AdvisorCardLive({
    required this.state,
    this.home,
    this.away,
    this.score,
    this.period,
    this.elapsed,
    this.startsAt,
    this.finishedAt,
  });

  static AdvisorCardLive? tryParse(Map<String, dynamic> j) {
    final state = j['state'];
    if (!const {'scheduled', 'live', 'ended'}.contains(state)) return null;
    return AdvisorCardLive(
      state: state as String,
      home: _nonEmpty(j['home']),
      away: _nonEmpty(j['away']),
      score: _nonEmpty(j['score']),
      period: _nonEmpty(j['period']),
      elapsed: _nonEmpty(j['elapsed']),
      startsAt: _nonEmpty(j['startsAt']),
      finishedAt: _nonEmpty(j['finishedAt']),
    );
  }
}

@immutable
class AdvisorCardPerp {
  final double markPx;
  final double? prevDayPx;
  final double? change24hPct;
  final double? fundingHourly;
  final double? fundingAnnualizedPct;
  final double? openInterestBase;
  final double? openInterestUsd;
  final double? volume24hUsd;
  final int? maxLeverage;
  const AdvisorCardPerp({
    required this.markPx,
    this.prevDayPx,
    this.change24hPct,
    this.fundingHourly,
    this.fundingAnnualizedPct,
    this.openInterestBase,
    this.openInterestUsd,
    this.volume24hUsd,
    this.maxLeverage,
  });

  static AdvisorCardPerp? tryParse(Map<String, dynamic> j) {
    final mark = _number(j['markPx']);
    if (mark == null || mark <= 0) return null;
    final oi = j['openInterest'];
    final leverage = _number(j['maxLeverage']);
    return AdvisorCardPerp(
      markPx: mark,
      prevDayPx: _positive(j['prevDayPx']),
      change24hPct: _number(j['change24hPct']),
      fundingHourly: _number(j['fundingHourly']),
      fundingAnnualizedPct: _number(j['fundingAnnualizedPct']),
      openInterestBase: oi is Map ? _positive(oi['base']) : null,
      openInterestUsd: oi is Map ? _positive(oi['usd']) : null,
      volume24hUsd: _positive(j['volume24hUsd']),
      maxLeverage: leverage != null && leverage >= 1 ? leverage.round() : null,
    );
  }
}

@immutable
class AdvisorCardSpot {
  final double markPx;
  final double? prevDayPx;
  final double? change24hPct;
  final double? volume24hUsd;
  const AdvisorCardSpot(
      {required this.markPx,
      this.prevDayPx,
      this.change24hPct,
      this.volume24hUsd});

  static AdvisorCardSpot? tryParse(Map<String, dynamic> j) {
    final mark = _number(j['markPx']);
    if (mark == null || mark <= 0) return null;
    return AdvisorCardSpot(
      markPx: mark,
      prevDayPx: _positive(j['prevDayPx']),
      change24hPct: _number(j['change24hPct']),
      volume24hUsd: _positive(j['volume24hUsd']),
    );
  }
}

@immutable
class AdvisorCardRelated {
  final String venue;
  final String id;
  final String title;
  const AdvisorCardRelated(
      {required this.venue, required this.id, required this.title});

  static AdvisorCardRelated? tryParse(Map<String, dynamic> j) {
    final venue = _nonEmpty(j['venue']);
    final id = _nonEmpty(j['id']);
    final title = _nonEmpty(j['title']);
    if (venue == null || id == null || title == null) return null;
    return AdvisorCardRelated(venue: venue, id: id, title: title);
  }
}

@immutable
class AdvisorActionButton {
  final String label;
  final String actionId;
  final Map<String, dynamic> params;
  final String style; // primary | secondary

  const AdvisorActionButton({
    required this.label,
    required this.actionId,
    this.params = const {},
    this.style = 'primary',
  });

  static AdvisorActionButton? tryParse(Map<String, dynamic> j) {
    final actionId = (j['actionId'] ?? '').toString().trim();
    final label = (j['label'] ?? '').toString().trim();
    if (actionId.isEmpty || label.isEmpty) return null;
    final rawParams = j['params'];
    final params = <String, dynamic>{};
    if (rawParams is Map) {
      rawParams.forEach((k, v) => params[k.toString()] = v);
    }
    final style = (j['style'] ?? 'primary').toString();
    return AdvisorActionButton(
      label: label,
      actionId: actionId,
      params: params,
      style: style,
    );
  }
}

String? _nonEmpty(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

double? _number(dynamic v) => v is num && v.isFinite ? v.toDouble() : null;

double? _positive(dynamic v) {
  final n = _number(v);
  return n != null && n > 0 ? n : null;
}

@immutable
class AdvisorSource {
  final String title;
  final String url;
  const AdvisorSource({required this.title, required this.url});

  static AdvisorSource? tryParse(Map<String, dynamic> json) {
    final title = _nonEmpty(json['title']);
    final url = _nonEmpty(json['url']);
    final uri = url == null ? null : Uri.tryParse(url);
    if (title == null ||
        uri == null ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return AdvisorSource(title: title, url: url!);
  }
}
