import 'package:flutter/foundation.dart' show immutable;
import 'package:kute/models/advisor_model.dart';
import 'package:kute/l10n/l10n.dart' show AppLocalizations, l10nForLanguage;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlCompactUsd, formatHlPct, formatHlPrice;
import 'package:kute/screens/hyperliquid/components/hl_market_stats.dart'
    show formatHlFundingRate;
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChance, formatPolyChanceMove;
import 'package:kute/services/polymarket/polymarket_category_gate.dart';

/// Exact identifiers come from the backend's verified market card.
/// Never infer a side, amount or market from the answer's prose.
AdvisorActionButton? advisorMarketAction(AdvisorBlock block,
    [AppLocalizations? l10n]) {
  final l = l10n ?? l10nForLanguage('en');
  final card = block.card;
  if (card == null) return null;
  final instrument = card.instrument ?? '';
  final kind = instrument.endsWith('_perp')
      ? 'perp'
      : instrument.endsWith('_spot')
          ? 'spot'
          : null;
  for (final action in block.actions) {
    if (card.venue == 'hyperliquid' &&
        action.actionId == 'open_hl_market' &&
        action.params['coin'] == card.id &&
        kind != null &&
        action.params['kind'] == kind &&
        action.params.keys.every((k) => k == 'coin' || k == 'kind')) {
      return AdvisorActionButton(
        label: l.salViewMarket,
        actionId: action.actionId,
        params: action.params,
      );
    }
    if (card.venue == 'polymarket' &&
        action.actionId == 'open_market_by_slug' &&
        action.params['slug'] == (card.slug ?? card.id) &&
        action.params.keys.every((k) => k == 'slug')) {
      return AdvisorActionButton(
        label: l.salViewMarket,
        actionId: action.actionId,
        params: action.params,
      );
    }
  }
  return null;
}

/// The jurisdiction gate a Sal market card answers to, or null when none
/// applies: `hyperliquid.stocks` for a stock-linked perpetual (by the
/// backend's instrument, category or the answer's stocks section) and the
/// prediction category gates by the market's category. The card came from
/// the backend, so this is where the app hides it once the policy denies.
String? advisorMarketGateCapability(AdvisorCard card, String? section) {
  if (card.venue == 'polymarket') {
    return polymarketCategoryCapability(card.category, const []);
  }
  if (card.venue != 'hyperliquid') return null;
  final instrument = card.instrument ?? '';
  final stock = instrument == 'stock_perp' ||
      (instrument.endsWith('_perp') &&
          (card.category == 'stocks' || section == 'stocks'));
  return stock ? 'hyperliquid.stocks' : null;
}

/// Product words for a market card: Predictions and Investing, never the
/// venue or the contract type. A stock-linked listing is still never
/// presented as ownership of shares.
String advisorInstrumentLabel(AdvisorCard card, String? section,
    [AppLocalizations? l10n]) {
  final l = l10n ?? l10nForLanguage('en');
  if (card.venue == 'polymarket') return l.salPredictionsMarket;
  if (card.venue != 'hyperliquid') return l.salMarket;
  switch (card.instrument) {
    case 'stock_perp':
    case 'preipo_perp':
      return l.salStockLinkedInvestingMarket;
    case 'crypto_perp':
      return section == 'stocks'
          ? l.salStockLinkedInvestingMarket
          : l.salCryptoInvestingMarket;
    case 'crypto_spot':
      return l.salSpotMarket;
    case 'stock_spot':
      return l.salStockLinkedSpotMarket;
    default:
      return section == 'stocks'
          ? l.salStockLinkedInvestingMarket
          : l.salInvestingMarket;
  }
}

String advisorDisplayDate(String value, {bool includeTime = false}) {
  // Disclosure dates are calendar dates, not local midnight timestamps.
  final dateValue =
      !includeTime && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)
          ? value.substring(0, 10)
          : value;
  final date = DateTime.tryParse(dateValue);
  if (date == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final utc = includeTime ? date.toUtc() : date;
  final day = '${utc.day} ${months[utc.month - 1]} ${utc.year}';
  if (!includeTime) return day;
  return '$day, ${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')} UTC';
}

/// Artwork is accepted only from the public market's known image hosts.
/// The backend fills this from provider metadata; model image URLs are dropped.
String? advisorMarketImageUrl(AdvisorCard card) {
  final uri = advisorSourceUri(card.imageUrl ?? '');
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final allowed = switch (card.venue) {
    'hyperliquid' =>
      host == 'app.hyperliquid.xyz' || host == 'assets.parqet.com',
    'polymarket' => host == 'polymarket.com' ||
        host.endsWith('.polymarket.com') ||
        host == 'polymarket-upload.s3.us-east-2.amazonaws.com',
    _ => false,
  };
  return allowed ? uri.toString() : null;
}

/// The ticker a Hyperliquid card's coin icon reads: the wire coin without
/// its dex prefix or quote, or for a spot pair id (`@107`) the symbol in
/// the block title's parentheses.
String advisorMarketSymbol(AdvisorCard card, String? title) {
  final id = card.id;
  if (id.startsWith('@')) {
    return RegExp(r'\(([^()]+)\)$').firstMatch(title ?? '')?.group(1) ?? '';
  }
  return id.split(':').last.split('/').first;
}

/// One line of a market plate: a label, its figure, and optionally a
/// signed move beside it ([up] colours it; null is neutral).
@immutable
class AdvisorPlateRow {
  final String label;
  final String value;
  final String? move;
  final bool? up;
  const AdvisorPlateRow(this.label, this.value, {this.move, this.up});
}

/// A Hyperliquid card's lead figure: the mark price, with its 24h change.
({String price, String? change, bool? up})? advisorCardPrice(AdvisorCard card) {
  final mark = card.perp?.markPx ?? card.spot?.markPx;
  if (mark == null) return null;
  final pct = card.perp?.change24hPct ?? card.spot?.change24hPct;
  return (
    price: formatHlPrice(mark),
    change: pct == null ? null : formatHlPct(pct / 100, decimals: 2),
    up: pct == null || pct == 0 ? null : pct > 0,
  );
}

/// The plate lines of a verified card, in the app's own words and formats:
/// a prediction's game state, outcomes (chance and the day's move in
/// points) and close; a perpetual's funding, open interest, 24h volume and
/// leverage limit; a spot token's 24h volume. A figure the provider did
/// not give is left out.
List<AdvisorPlateRow> advisorCardRows(AdvisorCard card, AppLocalizations l) {
  final rows = <AdvisorPlateRow>[];
  final live = card.live;
  if (live != null) {
    final teams = [
      if (live.home != null) live.home!,
      if (live.away != null) live.away!,
    ].join(' – ');
    // "Arsenal 1-0 Chelsea", or whichever part the provider gave.
    final score = live.score == null
        ? teams
        : live.home != null && live.away != null
            ? '${live.home} ${live.score} ${live.away}'
            : live.score!;
    final clock = [
      if (live.period != null) live.period!,
      if (live.elapsed != null) live.elapsed!,
    ];
    switch (live.state) {
      case 'live':
        final value = [if (score.isNotEmpty) score, ...clock].join(' · ');
        if (value.isNotEmpty) rows.add(AdvisorPlateRow(l.liveBadge, value));
      case 'ended':
        if (score.isNotEmpty) {
          rows.add(AdvisorPlateRow(l.polyMarkerFinal, score));
        }
      default:
        if (live.startsAt != null && teams.isNotEmpty) {
          rows.add(AdvisorPlateRow(
              teams,
              l.marketCardStartsOn(
                  advisorDisplayDate(live.startsAt!, includeTime: true))));
        }
    }
  }
  for (final outcome in card.outcomes) {
    final move = formatPolyChanceMove(outcome.delta24h);
    rows.add(AdvisorPlateRow(outcome.label, formatPolyChance(outcome.price),
        move: move == null ? null : '$move%',
        up: move == null ? null : outcome.delta24h! > 0));
  }
  if (card.closesAt != null) {
    rows.add(AdvisorPlateRow(
        l.polyStatEnds, advisorDisplayDate(card.closesAt!, includeTime: true)));
  }
  final perp = card.perp;
  if (perp != null) {
    if (perp.fundingHourly != null) {
      rows.add(AdvisorPlateRow(
          l.hlFunding, formatHlFundingRate(perp.fundingHourly!)));
    }
    if (perp.openInterestUsd != null) {
      rows.add(AdvisorPlateRow(
          l.hlOpenInterest, formatHlCompactUsd(perp.openInterestUsd!)));
    }
    if (perp.volume24hUsd != null) {
      rows.add(AdvisorPlateRow(
          l.hl24hVolume, formatHlCompactUsd(perp.volume24hUsd!)));
    }
    if (perp.maxLeverage != null && perp.maxLeverage! > 1) {
      rows.add(AdvisorPlateRow(l.chartMaxLeverage, '${perp.maxLeverage}×'));
    }
  }
  final spot = card.spot;
  if (spot?.volume24hUsd != null) {
    rows.add(AdvisorPlateRow(
        l.hl24hVolume, formatHlCompactUsd(spot!.volume24hUsd!)));
  }
  return rows;
}

/// Links remain native controls: HTTPS on a public hostname, no embedded
/// credentials, no local or private hosts, no other port.
Uri? advisorSourceUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      !uri.host.contains('.') ||
      uri.host.contains(':') ||
      RegExp(r'^[0-9.]+$').hasMatch(uri.host) ||
      uri.host.endsWith('.local') ||
      uri.host.endsWith('.localhost') ||
      uri.host.endsWith('.internal') ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  return uri;
}
