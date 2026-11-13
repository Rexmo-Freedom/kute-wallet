// lib/screens/hyperliquid/components/hl_format.dart
//
// Shared formatting + micro-branding helpers for the Hyperliquid Trading
// tab. Mirrors the role price_format.dart plays for the Polymarket
// surfaces: every screen/sheet in lib/screens/hyperliquid renders prices,
// sizes, compact USD figures and letter badges through these helpers so
// the tab reads as one product surface.
//
// Prices: crypto prices span ~9 orders of magnitude ($0.000012 PEPE →
// $100k BTC), so a fixed 2-decimal format is wrong at both ends.
// [formatHlPrice] follows Hyperliquid's own tick rule: up to 5 significant
// figures (whole-number prices are always shown in full), never more
// decimals than the market allows (HlMarket.pxDecimalCap: 6 − szDecimals
// for perps, 8 − szDecimals for spot). The browse LIST writes a shorter
// price ([formatHlListPrice]: four figures, two decimals at least), since
// a row is read at a glance, not traded on.
//
// Letter badges: Hyperliquid lists hundreds of coins and we deliberately
// ship NO network icon fetching (same call the home stocks rail made —
// see stocks_coming_soon_section caveat #1). A deterministic HSL tint
// per symbol gives each row a stable visual identity for free.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/theme/app_theme.dart';

/// Hyperliquid surface accent — the mint/emerald tone of the HL brand,
/// desaturated to sit next to the app's palette the way `_kPolyPurple`
/// does on Predictions.
const Color kHlAccent = Color(0xFF0EA57C);

/// Hyperliquid's price precision: at most this many significant figures.
const int kHlPriceSigFigs = 5;

/// The decimals Hyperliquid prices [px] with: 5 significant figures,
/// never more than [decimalCap] (HlMarket.pxDecimalCap; 8, the spot
/// maximum, when the market is unknown). Whole-number prices of 6+ digits
/// keep every digit and take no decimals.
int hlPriceDecimals(double px, {int? decimalCap}) {
  if (px <= 0 || !px.isFinite) return 2;
  var magnitude = (math.log(px) / math.ln10).floor();
  // log10 is inexact at powers of ten (log10(1000) → 2.999…); settle it.
  if (math.pow(10, magnitude + 1) <= px) magnitude += 1;
  if (math.pow(10, magnitude) > px) magnitude -= 1;
  final decimals = math.max(0, kHlPriceSigFigs - 1 - magnitude);
  return math.min(decimals, decimalCap ?? 8);
}

/// Venue-accurate price ("$110,234", "$3,912.4", "$12.345", "$0.012345"):
/// [hlPriceDecimals], then trailing zeros dropped down to two decimals so
/// "$12.30" doesn't read "$12.300". Two neighbouring ticks never collapse
/// into the same text, so the order book ladder and the trades tape show
/// one row per level. Every Hyperliquid price on screen goes through here.
String formatHlPrice(double px, {int? decimalCap}) {
  if (px <= 0 || !px.isFinite) return '—';
  return NumberFormat.currency(
          symbol: r'$', decimalDigits: _shownDecimals(px, decimalCap))
      .format(px);
}

/// The decimals [formatHlPrice] writes [px] with.
int _shownDecimals(double px, int? decimalCap) {
  final decimals = hlPriceDecimals(px, decimalCap: decimalCap);
  var shown = decimals;
  final keep = math.min(2, decimals);
  final exact = _roundTo(px, decimals);
  while (shown > keep && _roundTo(px, shown - 1) == exact) {
    shown -= 1;
  }
  return shown;
}

/// [px] written with the decimals [formatHlPrice] gives [reference] (the
/// market's price now), so every tag on one chart reads in one format: a
/// liquidation far under a $7,748.6 market is "$1.5", never "$1.486",
/// which beside "$7,748.3" reads as a thousand and a half.
String formatHlPriceLike(double px, double reference, {int? decimalCap}) {
  if (px <= 0 || !px.isFinite) return '—';
  if (reference <= 0 || !reference.isFinite) {
    return formatHlPrice(px, decimalCap: decimalCap);
  }
  return NumberFormat.currency(
          symbol: r'$', decimalDigits: _shownDecimals(reference, decimalCap))
      .format(px);
}

/// The Investing LIST's price (the browse rows and the "Moving now"
/// cards): a short price, the way Revolut / Coinbase / Robinhood write
/// theirs, not the venue's tick ("$47.91", "$4,128.40", "$2.631",
/// "$0.2051"): four significant figures, never fewer than two decimals,
/// never more than the market allows ([decimalCap]), trailing zeros
/// dropped down to two decimals. The charts, the order ladder and the
/// slip keep [formatHlPrice], whose five figures tell two ticks apart.
String formatHlListPrice(double px, {int? decimalCap}) {
  if (px <= 0 || !px.isFinite) return '—';
  return NumberFormat.currency(
          symbol: r'$', decimalDigits: hlListPriceDecimals(px, decimalCap))
      .format(px);
}

/// The decimals [formatHlListPrice] writes [px] with.
int hlListPriceDecimals(double px, int? decimalCap) {
  if (px <= 0 || !px.isFinite) return 2;
  var magnitude = (math.log(px) / math.ln10).floor();
  if (math.pow(10, magnitude + 1) <= px) magnitude += 1;
  if (math.pow(10, magnitude) > px) magnitude -= 1;
  var decimals = kHlListPriceSigFigs - 1 - magnitude;
  if (decimalCap != null) decimals = math.min(decimals, decimalCap);
  decimals = math.max(2, decimals);
  final exact = _roundTo(px, decimals);
  var shown = decimals;
  while (shown > 2 && _roundTo(px, shown - 1) == exact) {
    shown -= 1;
  }
  return shown;
}

/// The list price's precision: at most this many significant figures.
const int kHlListPriceSigFigs = 4;

double _roundTo(double v, int decimals) {
  final f = math.pow(10, decimals).toDouble();
  return (v * f).roundToDouble() / f;
}

/// $1.2B / $345.1M / $12.3K / $980 — volume/open-interest style figures.
String formatHlCompactUsd(double v) {
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}K';
  return '\$${v.toStringAsFixed(0)}';
}

/// Plain 2-decimal USD ("$1,234.56") for balances/notional rows.
String formatHlUsd(double v) =>
    NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(v);

/// Order/position size with the trailing zeros trimmed ("0.0012", "25").
String formatHlSize(double sz, {int maxDecimals = 6}) {
  var s = sz.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Signed percent chip text: +2.5% / −1.2%. [fraction] is 0.025 == 2.5%.
String formatHlPct(double fraction, {int decimals = 1}) {
  final pct = fraction * 100;
  final sign = pct >= 0 ? '+' : '−';
  return '$sign${pct.abs().toStringAsFixed(decimals)}%';
}

/// Symbol → human-friendly name shown as the card/row subtitle (e.g.
/// 'TSLA' → 'Tesla', 'BTC' → 'Bitcoin'). Covers the tokenized-equity set
/// ([kHlStockSymbols]) plus the top crypto majors — the same grammar the
/// search fallback uses. Returns null for coins with no friendly name so
/// the caller can omit the subtitle entirely.
String? hlFriendlyName(String coin) => _kHlFriendlyNames[coin];

const Map<String, String> _kHlFriendlyNames = {
  // Crypto majors.
  'BTC': 'Bitcoin',
  'ETH': 'Ethereum',
  'SOL': 'Solana',
  'XRP': 'XRP',
  'DOGE': 'Dogecoin',
  'HYPE': 'Hyperliquid',
  'SUI': 'Sui',
  'AVAX': 'Avalanche',
  'LINK': 'Chainlink',
  'LTC': 'Litecoin',
  'BNB': 'BNB',
  'ADA': 'Cardano',
  'TRX': 'TRON',
  'DOT': 'Polkadot',
  'MATIC': 'Polygon',
  'ARB': 'Arbitrum',
  'OP': 'Optimism',
  'ATOM': 'Cosmos',
  'NEAR': 'Near',
  'APT': 'Aptos',
  'PEPE': 'Pepe',
  'WIF': 'dogwifhat',
  'BONK': 'Bonk',
  // Tokenized equities / commodity proxies (kHlStockSymbols).
  'AAPL': 'Apple',
  'AMD': 'AMD',
  'AMZN': 'Amazon',
  'COIN': 'Coinbase',
  'CRCL': 'Circle',
  'GLD': 'Gold',
  'GOOGL': 'Google',
  'HOOD': 'Robinhood',
  'INTC': 'Intel',
  'META': 'Meta',
  'MSFT': 'Microsoft',
  'MSTR': 'Strategy',
  'NFLX': 'Netflix',
  'NVDA': 'Nvidia',
  'PLTR': 'Palantir',
  'QQQ': 'Nasdaq 100',
  'SLV': 'Silver',
  'SPY': 'S&P 500',
  'TSLA': 'Tesla',
  'XAUT0': 'Tether Gold',
  // Private companies' pre-IPO perps.
  'ANTH': 'Anthropic',
  'OAI': 'OpenAI',
  // Builder-dex commodity and index perps, by their bare symbol.
  'GOLD': 'Gold',
  'SILVER': 'Silver',
  'COPPER': 'Copper',
  'PLATINUM': 'Platinum',
  'PALLADIUM': 'Palladium',
  'NATGAS': 'Natural gas',
  'BRENTOIL': 'Brent oil',
  'CL': 'Crude oil',
  'SP500': 'S&P 500',
  'XYZ100': 'Nasdaq 100',
};

/// The venue's asset classes whose markets are the same thing under
/// several builders' tickers (gold on xyz, flx and km; Anthropic as ANTH,
/// ANT and ANTHROPIC), where [hlUnderlyingKey] reads [_kHlUnderlyingAliases].
const Set<String> _kHlAliasedCategories = {
  'stocks',
  'indices',
  'commodities',
  'preipo',
};

/// Every ticker and name, folded ([hlNormalizeName]), the builder dexes and
/// tracker tokens use for one underlying, onto that underlying. Read only
/// for the tradfi classes ([_kHlAliasedCategories]): the main dex's GAS
/// is a crypto coin, flx:GAS is natural gas.
const Map<String, String> _kHlUnderlyingAliases = {
  'anthropic': 'anthropic',
  'anth': 'anthropic',
  'ant': 'anthropic',
  'openai': 'openai',
  'oai': 'openai',
  'spacex': 'spacex',
  'spcx': 'spacex',
  'gold': 'gold',
  'xaut': 'gold',
  'xaut0': 'gold',
  'tethergold': 'gold',
  'paxg': 'gold',
  'gld': 'gold',
  'silver': 'silver',
  'slv': 'silver',
  'cl': 'wtioil',
  'wti': 'wtioil',
  'wtioil': 'wtioil',
  'usoil': 'wtioil',
  'oil': 'wtioil',
  'crudeoil': 'wtioil',
  'natgas': 'natgas',
  'gas': 'natgas',
  'naturalgas': 'natgas',
  'sp500': 'sp500',
  'spx': 'sp500',
  'spy': 'sp500',
  'us500': 'sp500',
  'usa500': 'sp500',
  'xyz100': 'nasdaq100',
  'nasdaq100': 'nasdaq100',
  'qqq': 'nasdaq100',
  'ndx': 'nasdaq100',
  'us100': 'nasdaq100',
};

/// Lower case with everything but letters and digits removed
/// ("Tether Gold" → "tethergold", "S&P 500" → "sp500").
String hlNormalizeName(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// What [m] is a market ON, so two markets on one underlying count as one
/// (the big-card strip never shows two cards for it, and the list under
/// the strip never repeats it). Not the coin id: Anthropic trades as
/// io:ANTH, para:ANTH, xyz:ANT and vntl:ANTHROPIC, gold as xyz:GOLD,
/// flx:GOLD, km:GOLD and the XAUT0 token. A tradfi market resolves through
/// [_kHlUnderlyingAliases] on its ticker, the app's name for it, the
/// venue's display name or the Unit asset; anything else is its display
/// name ([hlFriendlyName], the Unit asset, else the ticker), folded. The
/// asset class leads the key, so a crypto token that borrows a tradfi
/// name is never taken for the tradfi market. A token that holds a stock
/// (NVDAX, EQNVDA: [HlMarket.wrappedTicker]) is read by the stock's
/// ticker, so it is on that stock.
String hlUnderlyingKey(HlMarket m) => _hlUnderlyingKeys[m] ??= _keyOf(m);

/// Each market's key, computed once: the lists group the whole universe
/// on every build, and a market never changes.
final Expando<String> _hlUnderlyingKeys = Expando<String>();

String _keyOf(HlMarket m) {
  final tradfi = _kHlAliasedCategories.contains(m.category) ||
      m.category == 'fx';
  final ticker = m.underlyingTicker;
  final friendly = hlFriendlyName(ticker);
  if (_kHlAliasedCategories.contains(m.category)) {
    for (final n in [
      ticker,
      friendly,
      m.annotatedName,
      m.unitAssetName,
    ]) {
      if (n == null || n.isEmpty) continue;
      final alias = _kHlUnderlyingAliases[hlNormalizeName(n)];
      if (alias != null) return 't:$alias';
    }
  }
  final name = hlNormalizeName(friendly ?? m.unitAssetName ?? ticker);
  return '${tradfi ? 't' : 'c'}:${name.isEmpty ? ticker : name}';
}

/// The order one underlying's listings are ranked in, best first: a perp
/// before a spot token, then the most traded in 24 h, then the larger
/// open interest in dollars, then the wire id, so the pick never flips
/// between two equal listings. The best is the PRIMARY listing.
int hlCompareListings(HlMarket a, HlMarket b) {
  if (a.isSpot != b.isSpot) return a.isSpot ? 1 : -1;
  final v = b.dayNtlVlm.compareTo(a.dayNtlVlm);
  if (v != 0) return v;
  double oi(HlMarket m) => (m.openInterest ?? 0) * m.markPx;
  final o = oi(b).compareTo(oi(a));
  if (o != 0) return o;
  return a.wireCoin.compareTo(b.wireCoin);
}

/// One underlying's listings ([hlUnderlyingKey]) among a list of markets:
/// the [primary] ([hlCompareListings]' best) and the [alternatives], best
/// first. Nvidia trades as xyz:NVDA and io:NVDA and as the NVDAX and
/// EQNVDA tokens: one group, xyz:NVDA its primary.
class HlListingGroup {
  const HlListingGroup({
    required this.key,
    required this.primary,
    this.alternatives = const [],
  });

  final String key;
  final HlMarket primary;
  final List<HlMarket> alternatives;

  /// Every listing, the primary first.
  List<HlMarket> get listings => [primary, ...alternatives];

  /// The ticker the group trades, as its primary is read
  /// ([HlMarket.underlyingTicker]): NVDA for Nvidia, even where only its
  /// tokens are offered.
  String get ticker => primary.underlyingTicker;
}

/// [markets] grouped by underlying ([HlListingGroup]), the groups in the
/// order their primaries stand in [markets]. THE one grouping search,
/// the Investing lists, the big squares and the market map share, so they
/// agree on which listing stands for an underlying.
List<HlListingGroup> hlListingGroups(Iterable<HlMarket> markets) {
  final byKey = <String, List<HlMarket>>{};
  for (final m in markets) {
    (byKey[hlUnderlyingKey(m)] ??= <HlMarket>[]).add(m);
  }
  final byPrimary = <HlMarket, HlListingGroup>{};
  for (final e in byKey.entries) {
    final ranked = [...e.value]..sort(hlCompareListings);
    byPrimary[ranked.first] = HlListingGroup(
        key: e.key, primary: ranked.first, alternatives: ranked.sublist(1));
  }
  return [
    for (final m in markets)
      if (byPrimary.remove(m) case final HlListingGroup g) g,
  ];
}

/// [markets] with one listing per underlying: each underlying's primary
/// ([hlListingGroups]), at its own place in [markets]. A list with no
/// underlying twice comes back as it is (the same list).
List<HlMarket> hlPrimaryListings(List<HlMarket> markets) {
  final keys = <String>{};
  if (markets.every((m) => keys.add(hlUnderlyingKey(m)))) return markets;
  return [for (final g in hlListingGroups(markets)) g.primary];
}

/// Deterministic per-symbol tint for the letter badge (same HSL trick as
/// the Polymarket comment avatars) — stable across sessions, no assets.
Color hlBadgeColor(String coin) {
  return HSLColor.fromAHSL(1.0, (coin.hashCode % 360).toDouble(), 0.48, 0.45)
      .toColor();
}

/// Circular letter badge used for every market/position/fill row — the
/// Trading tab's stand-in for network coin icons.
class HlLetterBadge extends StatelessWidget {
  final String coin;
  final double size;
  const HlLetterBadge({super.key, required this.coin, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final tint = hlBadgeColor(coin);
    return Container(
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size.w * 0.25),
      ),
      child: Center(
        child: Text(
          coin.isNotEmpty ? coin[0].toUpperCase() : '?',
          style: TextStyle(
            color: tint,
            fontSize: (size * 0.4).sp,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Small LONG/SHORT (or BUY/SELL) chip — same chip grammar as the
/// Polymarket outcome badges.
class HlSideChip extends StatelessWidget {
  final String text;
  final Color color;
  const HlSideChip({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      // Solid fill with a contrast-picked label (no pastel tints, user
      // rule) so LONG/SHORT reads like the paired side buttons.
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: contrastingOnColor(color),
          fontSize: 13.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Neutral metadata chip ("5x isolated", "Delayed").
class HlMetaChip extends StatelessWidget {
  final String text;
  const HlMetaChip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The two words the whole Investing surface uses for what a market IS:
/// a spot market is something you **Own**, a perp is **Leveraged**. The
/// venue's own vocabulary ('spot' / 'perp') never reaches the screen — it
/// stays in analytics event params and on the order wire.
String hlKindLabel(AppLocalizations l10n, {required bool isSpot}) =>
    isSpot ? l10n.investingKindOwn : l10n.investingKindLeveraged;

/// The kind badge: neutral grey chip, the word carrying the meaning (no
/// accent wash, no tint). Rendered beside the ticker on every market row,
/// on the market detail header and on every holding.
class HlKindBadge extends StatelessWidget {
  final bool isSpot;
  const HlKindBadge({super.key, required this.isSpot});

  @override
  Widget build(BuildContext context) {
    return HlMetaChip(text: hlKindLabel(context.l10n, isSpot: isSpot));
  }
}

/// "Low liquidity", in the kind badge's own neutral chip: shown on the
/// header of a thinly traded market ([HlMarket.isLowLiquidity]).
class HlLowLiquidityBadge extends StatelessWidget {
  const HlLowLiquidityBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      HlMetaChip(text: context.l10n.investingLowLiquidity);
}
