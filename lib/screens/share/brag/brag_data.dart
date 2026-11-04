// lib/screens/share/brag/brag_data.dart
//
// WHAT A BRAG CARD SAYS (founder, 1 November 2026: "open positions and
// the portfolio should also be shareable with a friend, to brag"). The
// card (brag_card.dart) draws one of two pictures, built here from the
// providers the pages already read, never from a figure of its own:
//
//   * a POSITION ([BragPosition]): the market, the side, the result (the
//     signed amount, and the percent on what was put in when the page has
//     a cost base), entry and now, and the held side's line since the buy
//     when the page has read it (Predictions; an Investing position has no
//     open time, so no line);
//   * the PORTFOLIO ([BragPortfolio]): the allocation as shares only, the
//     all-time P&L (each venue's PortfolioPerformance.totalPnlUsd, the
//     predictions at the live prices, as the Portfolio ring's hole reads
//     it), and the three open positions with the best result, each with
//     its logo;
//   * a WON PREDICTION ([BragWin], founder, 4 November 2026: "Able to
//     share past prediction brags also, won ones"): a prediction held to
//     its resolved market whose side won, from the figures the venue
//     confirmed (the resolved position: Polymarket's data API, a claimed
//     payout's redeem, a result read from the resolved market): the side,
//     what it cost (the average price paid), what it paid out, the profit
//     and its percent on the cost, and when it resolved. Only
//     [bragWonPrediction] makes one, and only for a win in profit: a
//     loss, an open position or a win with no profit (bought at a dollar)
//     is never a won card ([canBragWin]);
//   * the P&L ([BragPnl], founder, 2 November 2026: the P&L Charts
//     section shares its own card, "Share P&L"): what the P&L chart shows
//     for the range picked, the P&L over the range (its figure,
//     pnlRangeChange), the range ("1M", "Past month") and the line over
//     it, of the series the chart draws (both venues, or the one picked
//     in "By venue"). No percent: no provider gives a base for a P&L (the
//     chart writes none either), so none is invented. It is a
//     BragPortfolio, so the card's switch stays whole; its own card is
//     pnl_share_card.dart.
//
// THE TONE ([BragTone]): Sal's one-liner in the share message follows
// the result (brag_lines.dart): a BIG WIN (a percent of at least
// [kBragBigWinPercent]), a WIN, a SMALL WIN (under [kBragSmallWinPercent],
// or under [kBragSmallWinUsd] when there is no percent), a LOSS, or FLAT.
// The portfolio has no all-time percent (no provider gives a base for
// it), so its tone reads the open positions' combined return
// ([BragPortfolio.returnPercent]: their P&L over what they cost) when
// there are any; that figure is never drawn.
//
// AMOUNTS: the card always shows the real money figures (founder,
// 1 November 2026: "don't even give the option"), with the percents where
// a cost base exists. The allocation stays shares only (no balance). A
// figure the providers do not have is left out, never estimated.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/balance_history.dart' show BalanceRange;
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProviderFromUSD;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidPerpPositionsProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart'
    show hyperliquidLiveMidProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider;
import 'package:kute/providers/one_balance_provider.dart'
    show oneBalanceProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show
        PolymarketPosition,
        polymarketActivePositionsProvider,
        positionCrestImage;
import 'package:kute/providers/polymarket_cost_basis_provider.dart'
    show polymarketPositionCostBasis;
import 'package:kute/providers/polymarket_live_prices_provider.dart'
    show livePriceProvider;
import 'package:kute/providers/portfolio_performance_provider.dart'
    show portfolioPerformanceDisplayProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlPrice;
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart'
    show hlLivePnl, hlPositionMargin;
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show formatPolyBoughtCents;
import 'package:kute/screens/polymarket/components/position_journey.dart'
    show polyPositionJourneyProvider;
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyCents;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlRangeChange;
import 'package:kute/screens/portfolio/portfolio_filters.dart'
    show portfolioVenuesProvider;
import 'package:kute/screens/shared/charts/kute_trend_window.dart'
    show kuteTrendWindow;
import 'package:kute/screens/shared/kute_share_actions.dart'
    show kMarketLinkInvesting, kMarketLinkPredictions, marketShareLink;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceState, OneBalanceVenue;

/// Which card: the analytics `kind`.
enum BragKind { position, portfolio }

/// Under this a figure is nothing: no sign, no colour.
const double kBragCentUsd = 0.005;

/// A provider read: `ref.watch` of a Ref or a WidgetRef (a build), or
/// `ref.read` (a tap).
typedef BragWatch = T Function<T>(ProviderListenable<T> provider);

/// What one card shows (see the file header).
sealed class BragData {
  const BragData({required this.title, required this.link, this.referralCode});

  /// What the share text names: "{title} on Kute {link}".
  final String title;

  /// The link the share text carries; the referral code goes on it as
  /// `?ref=CODE` when there is one (share_market_sheet.dart).
  final String link;

  /// The sharer's own referral code (AffiliateService), drawn in the
  /// footer; null without one.
  final String? referralCode;

  BragKind get kind;

  /// The result reads up rather than down.
  bool get up;

  /// The result's tone: the card's edgy line (brag_lines.dart).
  BragTone get tone;
}

/// How the result reads on the card (see the file header).
enum BragTone { bigWin, win, smallWin, loss, flat }

/// At or over this percent a win is big.
const double kBragBigWinPercent = 10;

/// Under this percent a win is small.
const double kBragSmallWinPercent = 2;

/// Without a percent, a win under this many dollars is small (and never
/// big).
const double kBragSmallWinUsd = 10;

/// The tone of [usd] with its [percent] when there is one.
BragTone bragTone(double usd, {double? percent}) {
  if (usd <= -kBragCentUsd) return BragTone.loss;
  if (usd < kBragCentUsd) return BragTone.flat;
  final pct = percent != null && percent.isFinite ? percent : null;
  if (pct == null) {
    return usd < kBragSmallWinUsd ? BragTone.smallWin : BragTone.win;
  }
  if (pct >= kBragBigWinPercent) return BragTone.bigWin;
  if (pct < kBragSmallWinPercent) return BragTone.smallWin;
  return BragTone.win;
}

/// A signed result: [usd] (exact, for the colour and the order) and its
/// text in the person's currency ("+$36.90"), and the percent on what was
/// put in when there is a cost base.
class BragResult {
  const BragResult({required this.usd, required this.text, this.percent});

  final double usd;
  final String text;
  final double? percent;

  bool get up => usd >= kBragCentUsd;
  bool get down => usd <= -kBragCentUsd;
}

class BragPosition extends BragData {
  const BragPosition({
    required super.title,
    required super.link,
    super.referralCode,
    required this.investing,
    required this.side,
    required this.result,
    this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    this.imageUrl,
    this.entryText,
    this.nowText,
    this.series,
    this.entryValue,
    this.chance,
  });

  /// An Investing position (Hyperliquid) rather than a prediction.
  final bool investing;

  /// "Long", "Short", the outcome held ("Yes", "Gen.G").
  final String side;
  final BragResult result;

  /// Investing: the coin icon (HlCoinIcon's inputs).
  final String? coin;
  final String? wireCoin;
  final String? iconUrl;
  final String? category;

  /// Predictions: the market's picture.
  final String? imageUrl;

  /// The price paid and the price now, formatted the way the page shows
  /// them; null when unknown.
  final String? entryText;
  final String? nowText;

  /// The held side's price since the buy, oldest first, ending at now;
  /// null when the page has not read it (no line is drawn).
  final List<double>? series;

  /// The price paid on [series]' scale.
  final double? entryValue;

  /// Predictions: the held side's chance now, 0 to 1 (its live price),
  /// the card's speedometer; null on an Investing position.
  final double? chance;

  @override
  BragKind get kind => BragKind.position;

  @override
  bool get up => !result.down;

  @override
  BragTone get tone => bragTone(result.usd, percent: result.percent);
}

/// A resolved prediction that won (see the file header). Built only by
/// [bragWonPrediction].
class BragWin extends BragData {
  const BragWin({
    required super.title,
    required super.link,
    super.referralCode,
    required this.side,
    required this.result,
    required this.paidText,
    required this.payoutText,
    this.entryValue,
    this.entryText,
    this.imageUrl,
    this.resolvedAt,
  });

  /// The side that won, as the market names it ("Yes", "Gen.G").
  final String side;

  /// The profit (what it paid out less what it cost) and its percent on
  /// the cost.
  final BragResult result;

  /// What it cost and what it paid out, in the person's currency.
  final String paidText;
  final String payoutText;

  /// The average price paid, 0 to 1 (the dot on the dial), and as the
  /// position page's "since 41¢" writes it; null when the share count is
  /// unknown.
  final double? entryValue;
  final String? entryText;

  /// The market's picture.
  final String? imageUrl;

  /// When the market resolved (or the payout came in); null: unknown.
  final DateTime? resolvedAt;

  @override
  BragKind get kind => BragKind.position;

  @override
  bool get up => true;

  @override
  BragTone get tone => bragTone(result.usd, percent: result.percent);
}

/// One slice of the allocation ring: its share 0..1 only, never money.
class BragSlice {
  const BragSlice({required this.part, required this.share});

  final BragSlicePart part;
  final double share;
}

enum BragSlicePart { dollars, investing, predictions }

/// One of the top positions on the portfolio card.
class BragTopPosition {
  const BragTopPosition({
    required this.title,
    required this.result,
    this.side,
    this.investing = false,
    this.coin,
    this.wireCoin,
    this.iconUrl,
    this.category,
    this.imageUrl,
  });

  final String title;
  final String? side;
  final BragResult result;

  /// An Investing position: its logo is the coin icon ([coin], [wireCoin],
  /// [iconUrl], [category], HlCoinIcon's inputs); a prediction's is the
  /// market's picture ([imageUrl]).
  final bool investing;
  final String? coin;
  final String? wireCoin;
  final String? iconUrl;
  final String? category;
  final String? imageUrl;
}

class BragPortfolio extends BragData {
  const BragPortfolio({
    required super.title,
    required super.link,
    super.referralCode,
    this.slices = const [],
    this.allTime,
    this.returnPercent,
    this.top = const [],
    this.series,
  });

  /// The allocation, in ring order; empty while any part is unknown.
  final List<BragSlice> slices;

  /// The all-time P&L (no percent: no cost base for the combined figure).
  final BragResult? allTime;

  /// The open positions' combined return in percent (their P&L over
  /// what they cost), for the tone only; null without an open position.
  final double? returnPercent;

  /// Up to three open positions, best result first.
  final List<BragTopPosition> top;

  /// The all-time P&L line (both venues as one account, the Statistics
  /// tab's PortfolioPerformance.combine), thinned; null while any venue
  /// is unknown or when it never moved. The card draws it in place of
  /// the rows.
  final List<double>? series;

  @override
  BragKind get kind => BragKind.portfolio;

  @override
  bool get up => !(allTime?.down ?? false);

  @override
  BragTone get tone {
    final r = allTime;
    if (r == null) return BragTone.flat;
    return bragTone(r.usd, percent: r.percent ?? returnPercent);
  }

  /// Something to brag about: a position open or a P&L that is not zero.
  bool get hasSomething =>
      top.isNotEmpty || (allTime != null && (allTime!.up || allTime!.down));
}

/// The P&L Charts card (see the file header): [allTime] is the P&L over
/// [range] (named so for the card's switch and its tone), [series] the
/// line over the range, [venue] the venue charted alone (null: both).
class BragPnl extends BragPortfolio {
  const BragPnl({
    required super.title,
    required super.link,
    super.referralCode,
    required this.range,
    this.venue,
    super.allTime,
    super.series,
  });

  /// The range picked on the chart.
  final BalanceRange range;

  /// The venue picked in "By venue"; null: both, added.
  final PortfolioPerformanceVenue? venue;

  /// The P&L over [range].
  BragResult? get result => allTime;

  @override
  bool get hasSomething => allTime != null && (allTime!.up || allTime!.down);
}

/// [usd] in the person's currency, as the Predictions amounts read it
/// (polymarket_amount_formatter.dart), through [watch].
String bragMoney(BragWatch watch, double usd, {int digits = 2}) {
  final currency = watch(settingsProvider).currency;
  double rate = 1;
  if (currency != 'USD') {
    rate = watch(selectedCurrencyProviderFromUSD(currency)).toDouble();
  }
  final valid = rate.isFinite && rate > 0;
  return NumberFormat.simpleCurrency(
          name: valid ? currency : 'USD', decimalDigits: digits)
      .format(usd * (valid ? rate : 1));
}

/// "+$36.90", "−$12.00", "$0.00".
String bragSignedMoney(BragWatch watch, double usd) {
  final abs = bragMoney(watch, usd.abs());
  if (usd >= kBragCentUsd) return '+$abs';
  if (usd <= -kBragCentUsd) return '−$abs';
  return abs;
}

/// "+42.1%", "−3.0%", "0.0%".
String bragPercent(double pct) {
  final abs = pct.abs().toStringAsFixed(1);
  if (abs == '0.0') return '0.0%';
  return '${pct > 0 ? '+' : '−'}$abs%';
}

BragResult bragResult(BragWatch watch, double usd, {double? percent}) =>
    BragResult(
        usd: usd,
        text: bragSignedMoney(watch, usd),
        percent: percent != null && percent.isFinite ? percent : null);

// ─── Positions ───────────────────────────────────────────────────────

/// An Investing position as its page reads it: [pnl] the live P&L, the
/// percent on the position's margin ([hlPositionMargin], the page's own
/// return figure), [markPx] the price now.
BragPosition bragHlPosition(
  BragWatch watch, {
  required HlPerpPosition position,
  required String title,
  required String side,
  required double pnl,
  required double markPx,
  String? wireCoin,
  String? iconUrl,
  String? category,
  int? decimalCap,
}) {
  final margin = hlPositionMargin(position);
  return BragPosition(
    title: title,
    link: marketShareLink(venue: kMarketLinkInvesting, slug: position.coin),
    referralCode: _referralCode(),
    investing: true,
    side: side,
    result:
        bragResult(watch, pnl, percent: margin > 0 ? pnl / margin * 100 : null),
    coin: title,
    wireCoin: wireCoin ?? position.coin,
    iconUrl: iconUrl,
    category: category,
    entryText: position.entryPx > 0
        ? formatHlPrice(position.entryPx, decimalCap: decimalCap)
        : null,
    nowText: markPx > 0 ? formatHlPrice(markPx, decimalCap: decimalCap) : null,
  );
}

/// A prediction as its page reads it: [costBasis] what was paid (the
/// page's polymarketPositionCostBasis), [currentPrice] the held side's
/// price now. The line since the buy comes from the journey the page
/// draws, when it has been read and starts at the buy.
BragPosition bragPolyPosition(
  BragWatch watch, {
  required PolymarketPosition position,
  required double costBasis,
  required double currentPrice,
  String? imageUrl,
}) {
  final pnl = currentPrice * position.size - costBasis;
  final entry =
      position.size > 0 && costBasis > 0 ? costBasis / position.size : null;
  List<double>? series;
  final token = position.tokenId;
  if (token != null && token.isNotEmpty) {
    final journey = watch(polyPositionJourneyProvider(
        (tokenId: token, fallbackSince: position.createdAt))).valueOrNull;
    if (journey != null && journey.fromBuy && journey.points.isNotEmpty) {
      series = [
        if (entry != null) entry,
        for (final p in journey.points) p.price,
        currentPrice,
      ];
    }
  }
  return BragPosition(
    title: position.marketQuestion,
    link: marketShareLink(
        venue: kMarketLinkPredictions, slug: position.eventSlug),
    referralCode: _referralCode(),
    investing: false,
    side: position.outcome,
    result: bragResult(watch, pnl,
        percent: costBasis > 0 ? pnl / costBasis * 100 : null),
    imageUrl: imageUrl ?? position.marketImage,
    entryText: entry != null ? formatPolyCents(entry) : null,
    nowText: formatPolyCents(currentPrice),
    series: series != null && series.length >= 2 ? series : null,
    entryValue: entry,
    chance: currentPrice >= 0 && currentPrice <= 1 ? currentPrice : null,
  );
}

/// Whether a prediction is a win to brag about: resolved, its side won,
/// what it cost known, and a profit of at least a cent. A loss, an open
/// position, or a win that cost what it paid out never is.
bool canBragWin({
  required bool resolved,
  required bool? won,
  required double costUsd,
  required double payoutUsd,
}) =>
    resolved &&
    won == true &&
    costUsd.isFinite &&
    costUsd > 0 &&
    payoutUsd.isFinite &&
    payoutUsd - costUsd >= kBragCentUsd;

/// The won card of a resolved prediction (see the file header), or null
/// when it is not one ([canBragWin]). [costUsd] is what the shares cost,
/// [payoutUsd] what the market paid for them, [shares] how many (the
/// average price paid is the cost over them), [resolvedAt] when it
/// resolved. Every figure is the caller's, as its page shows it.
BragWin? bragWonPrediction(
  BragWatch watch, {
  required String title,
  required String side,
  required bool resolved,
  required bool? won,
  required double costUsd,
  required double payoutUsd,
  double? shares,
  String? eventSlug,
  String? imageUrl,
  DateTime? resolvedAt,
}) {
  if (!canBragWin(
      resolved: resolved, won: won, costUsd: costUsd, payoutUsd: payoutUsd)) {
    return null;
  }
  final profit = payoutUsd - costUsd;
  final n = shares;
  final avg = n != null && n.isFinite && n > 0 ? costUsd / n : null;
  final entry = avg != null && avg > 0 && avg < 1 ? avg : null;
  final image = imageUrl?.trim();
  return BragWin(
    title: title,
    link: marketShareLink(venue: kMarketLinkPredictions, slug: eventSlug),
    referralCode: _referralCode(),
    side: side.trim(),
    result: bragResult(watch, profit, percent: profit / costUsd * 100),
    paidText: bragMoney(watch, costUsd),
    payoutText: bragMoney(watch, payoutUsd),
    entryValue: entry,
    // The position page's own "since 41¢", apart from the percent.
    entryText: entry != null ? formatPolyBoughtCents(entry) : null,
    imageUrl: image == null || image.isEmpty ? null : image,
    resolvedAt: resolvedAt,
  );
}

/// The won card of a resolved [position] as its page reads it: what it
/// cost ([costBasis], the page's polymarketPositionCostBasis) and what it
/// pays, a dollar a share (the page's Payout tile). Null for a loss, an
/// open position or a win with no profit. For the position page and the
/// Portfolio's past positions.
BragWin? bragWonPosition(
  BragWatch watch, {
  required PolymarketPosition position,
  required double costBasis,
  String? imageUrl,
}) =>
    bragWonPrediction(
      watch,
      title: position.marketQuestion,
      side: position.outcome,
      resolved: position.isResolved,
      won: position.won,
      costUsd: costBasis,
      payoutUsd: position.size,
      shares: position.size,
      eventSlug: position.eventSlug,
      imageUrl: imageUrl ?? position.marketImage,
      resolvedAt: position.resolvedAt,
    );

// ─── Portfolio ───────────────────────────────────────────────────────

/// The all-time P&L, each venue's published figure added (the Portfolio
/// ring's hole, balances_overview.dart); null while any venue's history
/// is unread.
double? bragPortfolioPnl(BragWatch watch) {
  double total = 0;
  for (final v in PortfolioPerformanceVenue.values) {
    final data = watch(portfolioPerformanceDisplayProvider(
            PortfolioPerformanceRequest(venue: v)))
        .valueOrNull;
    if (data == null) return null;
    final p = v == PortfolioPerformanceVenue.predictions
        ? data.withLivePredictions(watch(livePriceProvider).prices)
        : data;
    if (p.points.isEmpty) continue; // never published: nothing made
    final usd = p.totalPnlUsd;
    if (usd == null || !usd.isFinite) return null;
    total += usd;
  }
  return total;
}

/// The most points the portfolio's line draws.
const int kBragSeriesPoints = 60;

/// The all-time P&L line of both venues as one account (see
/// [BragPortfolio.series]); null while any venue is unknown or when it
/// never moved.
List<double>? bragPortfolioSeries(BragWatch watch) {
  final parts = <PortfolioPerformance>[];
  for (final v in PortfolioPerformanceVenue.values) {
    final data = watch(portfolioPerformanceDisplayProvider(
            PortfolioPerformanceRequest(venue: v)))
        .valueOrNull;
    if (data == null) return null;
    parts.add(v == PortfolioPerformanceVenue.predictions
        ? data.withLivePredictions(watch(livePriceProvider).prices)
        : data);
  }
  final all = PortfolioPerformance.combine(parts);
  if (all.points.length < 2 || !all.hasMovement) return null;
  final values = [
    for (final p in all.points)
      if (p.pnlUsd.isFinite) p.pnlUsd
  ];
  if (values.length < 2) return null;
  if (values.length <= kBragSeriesPoints) return values;
  final step = (values.length - 1) / (kBragSeriesPoints - 1);
  return [
    for (var i = 0; i < kBragSeriesPoints; i++) values[(i * step).round()]
  ];
}

/// The allocation as shares (cash anywhere, Investing at work,
/// Predictions at work); empty while any part is unknown or when there is
/// nothing at all.
List<BragSlice> bragSlices(OneBalanceState s) {
  if (!s.dollarsKnown || !s.investingKnown || !s.predictionsKnown) {
    return const [];
  }
  double clean(double? v) => v != null && v.isFinite && v > 0 ? v : 0;
  final cash = clean(s.availableUsd) +
      s.waiting.values.fold<double>(0, (t, v) => t + clean(v));
  final investing = clean(s.investedByVenue[OneBalanceVenue.investing]);
  final predictions = clean(s.investedByVenue[OneBalanceVenue.predictions]);
  final total = cash + investing + predictions;
  if (total < kBragCentUsd) return const [];
  return [
    BragSlice(part: BragSlicePart.investing, share: investing / total),
    BragSlice(part: BragSlicePart.predictions, share: predictions / total),
    BragSlice(part: BragSlicePart.dollars, share: cash / total),
  ];
}

/// The portfolio card for the spending account, from a build ([ref]
/// watches, so the preview follows the live prices).
BragPortfolio bragPortfolio(WidgetRef ref, {required String title}) {
  final watch = ref.watch;
  final top = <BragTopPosition>[];
  // The open positions' combined return (the tone's, never drawn).
  double openPnl = 0, openBase = 0;
  for (final p in ref.watch(hyperliquidPerpPositionsProvider)) {
    final pnl =
        hlLivePnl(p, liveMid: ref.watch(hyperliquidLiveMidProvider(p.coin)));
    final margin = hlPositionMargin(p);
    final m = ref.watch(hyperliquidAccountMarketProvider(p.coin));
    if (margin > 0 && pnl.isFinite) {
      openPnl += pnl;
      openBase += margin;
    }
    top.add(BragTopPosition(
      title: m?.coin ?? p.coin,
      side: null,
      result: bragResult(watch, pnl,
          percent: margin > 0 ? pnl / margin * 100 : null),
      investing: true,
      coin: m?.coin ?? p.coin,
      wireCoin: m?.wireCoin ?? p.coin,
      iconUrl: m?.iconUrl,
      category: m?.category,
    ));
  }
  final live = ref.watch(livePriceProvider).prices;
  for (final p in ref.watch(polymarketActivePositionsProvider)) {
    final price =
        (p.tokenId != null ? live[p.tokenId] : null) ?? p.currentPrice;
    final cost = polymarketPositionCostBasis(ref, p);
    final pnl = price * p.size - cost;
    if (cost > 0 && pnl.isFinite) {
      openPnl += pnl;
      openBase += cost;
    }
    top.add(BragTopPosition(
      title: p.marketQuestion,
      side: p.outcome,
      result:
          bragResult(watch, pnl, percent: cost > 0 ? pnl / cost * 100 : null),
      imageUrl: positionCrestImage(ref, p),
    ));
  }
  top.sort((a, b) => b.result.usd.compareTo(a.result.usd));
  final pnl = bragPortfolioPnl(watch);
  return BragPortfolio(
    title: title,
    link: marketShareLink(venue: kMarketLinkInvesting, slug: null),
    referralCode: _referralCode(),
    slices: bragSlices(ref.watch(oneBalanceProvider)),
    allTime: pnl == null ? null : bragResult(watch, pnl),
    returnPercent: openBase > 0 ? openPnl / openBase * 100 : null,
    top: top.take(3).toList(growable: false),
    series: bragPortfolioSeries(watch),
  );
}

/// The P&L Charts card for the spending account over [range], of the
/// series the chart draws: [venue] alone when picked, else the venues on
/// the account added (PortfolioPerformance.combine), each with the
/// predictions at the live prices, as the chart reads them. From a build
/// ([ref] watches, so the preview follows the live figures). Unknown (a
/// venue not read yet): no figure and no line.
BragPnl bragPnl(WidgetRef ref,
    {required String title,
    required BalanceRange range,
    PortfolioPerformanceVenue? venue,
    DateTime? now}) {
  final shown = ref.watch(portfolioVenuesProvider);
  final venues = [
    if (shown.trading) PortfolioPerformanceVenue.trading,
    if (shown.predictions) PortfolioPerformanceVenue.predictions,
  ];
  final parts = <PortfolioPerformanceVenue, PortfolioPerformance>{};
  var known = venues.isNotEmpty;
  for (final v in venues) {
    final data = ref
        .watch(portfolioPerformanceDisplayProvider(
            PortfolioPerformanceRequest(venue: v)))
        .valueOrNull;
    if (data == null) {
      known = false;
      continue;
    }
    parts[v] = v == PortfolioPerformanceVenue.predictions
        ? data.withLivePredictions(ref
            .watch(livePriceProvider.select(
                (s) => HeldPredictionPrices.of(data.predictions, s.prices)))
            .prices)
        : data;
  }
  final picked = venue != null && parts.containsKey(venue) ? venue : null;
  final charted = picked != null
      ? parts[picked]!
      : known
          ? PortfolioPerformance.combine(parts.values.toList())
          : null;
  BragResult? result;
  List<double>? series;
  if (charted != null && charted.hasMovement) {
    final grid = pnlSeries(charted, now ?? DateTime.now());
    final values = kuteTrendWindow(grid, grid.spanFor(range)).values;
    final change = pnlRangeChange(values, range) ?? grid.values.last;
    result = bragResult(ref.watch, change);
    final line = [
      for (final v in values)
        if (v.isFinite) v
    ];
    if (line.length >= 2) {
      if (line.length <= kBragSeriesPoints) {
        series = line;
      } else {
        final step = (line.length - 1) / (kBragSeriesPoints - 1);
        series = [
          for (var i = 0; i < kBragSeriesPoints; i++) line[(i * step).round()]
        ];
      }
    }
  } else if (charted != null) {
    result = bragResult(ref.watch, 0);
  }
  return BragPnl(
    title: title,
    link: marketShareLink(venue: kMarketLinkInvesting, slug: null),
    referralCode: _referralCode(),
    range: range,
    venue: picked,
    allTime: result,
    series: series,
  );
}

/// Whether the P&L Charts section offers its card: a P&L off zero at a
/// venue on the account, the predictions at the live prices (the chart
/// is drawn).
final bragPnlAvailableProvider = Provider.autoDispose<bool>((ref) {
  final shown = ref.watch(portfolioVenuesProvider);
  for (final (on, v) in [
    (shown.trading, PortfolioPerformanceVenue.trading),
    (shown.predictions, PortfolioPerformanceVenue.predictions),
  ]) {
    if (!on) continue;
    final data = ref
        .watch(portfolioPerformanceDisplayProvider(
            PortfolioPerformanceRequest(venue: v)))
        .valueOrNull;
    if (data == null) continue;
    final p = v == PortfolioPerformanceVenue.predictions
        ? data.withLivePredictions(ref
            .watch(livePriceProvider.select(
                (s) => HeldPredictionPrices.of(data.predictions, s.prices)))
            .prices)
        : data;
    final now = p.totalPnlUsd ?? (p.points.isEmpty ? 0.0 : p.points.last.pnlUsd);
    if (p.hasMovement || now.abs() >= kBragCentUsd) return true;
  }
  return false;
});

/// Whether the Portfolio screen offers its card: a position open at
/// either venue, or an all-time P&L that is not zero.
final bragPortfolioAvailableProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(hyperliquidPerpPositionsProvider).isNotEmpty) return true;
  if (ref.watch(polymarketActivePositionsProvider).isNotEmpty) return true;
  final pnl = bragPortfolioPnl(ref.watch);
  return pnl != null && pnl.abs() >= kBragCentUsd;
});

String? _referralCode() {
  final code = AffiliateService.affiliateCode?.trim() ?? '';
  return code.isEmpty ? null : code;
}
