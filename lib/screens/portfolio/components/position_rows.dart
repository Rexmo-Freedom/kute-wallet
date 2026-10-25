// lib/screens/portfolio/components/position_rows.dart
//
// The Portfolio's open positions as plain list rows (founder request,
// October 2026: "those cards are not fintech like"), the way a brokerage
// app lists holdings, with no card, border or fill:
//
//   * leading, the real picture at 40 pt: a Predictions market's image
//     (the held team's crest when the event names one), an Investing
//     market's coin logo through [HlCoinIcon] (HIP-3 tickers such as
//     xyz:NVDA included);
//   * the title on ONE line, cut with an ellipsis: the market's question,
//     the asset's name;
//   * under it one short line of facts: "Yes · 4.99 shares · avg 72¢",
//     "Long · 0.00012 BTC · entry $90,120" (never a leverage figure:
//     leverage is blocked in the app). A position's state replaces the
//     facts where it has one ("Yes · Settled", "Up · Selling…", the
//     awaiting-result caption);
//   * on the right what it is worth now (w600) with the profit or loss
//     under it, "+$0.42 (+4.0%)" in the up colour or "−$0.42 (−4.0%)" in
//     the down colour; a P&L that rounds to no cent reads "$0.00 (0.0%)"
//     in the quiet secondary colour, never a red "−$0.00".
//
// The list draws hairlines between rows ([portfolioRowsWithHairlines]).
// Every row is its own widget watching only what it needs, so a price
// tick repaints one row. Taps open the same screens the cards opened,
// with the same `open_investments_position_tapped` event.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/combo_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/game_time.dart'
    show polyMinuteTickProvider;
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show PolyCardThumbnail;
import 'package:kute/screens/polymarket/components/position_awaiting.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart'
    show PositionDetailSheet, polyPositionEnd;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show PortfolioCardValue;
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A row's picture and the gap after it.
const double kPortfolioRowImage = 40;
const double kPortfolioRowGap = 12;

/// How a P&L reads: a gain, a loss, or nothing worth a colour.
enum PortfolioPnlTone { up, down, flat }

/// The P&L line under a row's value: "+$0.42 (+4.0%)", "−$0.42 (−4.0%)",
/// or "$0.00 (0.0%)" (flat, no sign) when it rounds to no cent. [money]
/// writes an unsigned amount. Pure for the tests.
({String text, PortfolioPnlTone tone}) portfolioPnlLine(
    String Function(double usd) money, double pnl,
    {double? percent}) {
  if (!pnl.isFinite || pnl.abs() < 0.005) {
    final pct = percent == null || !percent.isFinite ? '' : ' (0.0%)';
    return (text: '${money(0)}$pct', tone: PortfolioPnlTone.flat);
  }
  return (
    text: PortfolioCardValue.pnlText(money(pnl.abs()), pnl, percent: percent),
    tone: pnl > 0 ? PortfolioPnlTone.up : PortfolioPnlTone.down,
  );
}

/// [rows] with a hairline between each, starting where the text does.
List<Widget> portfolioRowsWithHairlines(
    BuildContext context, List<Widget> rows) {
  final c = context.colors;
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0)
        Divider(
          color: context.isDark ? c.border : c.borderSubtle,
          height: 1,
          thickness: 0.5,
          indent: kPortfolioRowImage.w + kPortfolioRowGap.w,
        ),
      rows[i],
    ],
  ];
}

/// The quiet count above the rows ("3 positions").
class PortfolioPositionsCount extends StatelessWidget {
  const PortfolioPositionsCount({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 4.h),
        child: Text(
          context.l10n.portfolioPositionsCount(count),
          key: const ValueKey('portfolio-positions-count'),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
      );
}

/// One position as a list row (see the file header): its picture, title
/// and facts, its value with the P&L under it ([pnl] null writes none;
/// [detail] a quiet word in its place, "Est. value").
class PortfolioPositionRow extends StatelessWidget {
  const PortfolioPositionRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.value,
    this.pnl,
    this.detail,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String value;
  final ({String text, PortfolioPnlTone tone})? pnl;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondary = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final under = pnl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          // Titles wrap in full (never cut with an ellipsis), so the row
          // hangs from its top edge.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(dimension: kPortfolioRowImage.w, child: leading),
              SizedBox(width: kPortfolioRowGap.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        key: const ValueKey('portfolio-row-title'),
                        style: AppTextStyles.settingsTitle(context)
                            .copyWith(letterSpacing: -0.2, height: 1.25)),
                    SizedBox(height: 2.h),
                    Text(subtitle,
                        key: const ValueKey('portfolio-row-subtitle'),
                        style: secondary),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 140.w),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RollingFigure(
                        key: const ValueKey('portfolio-row-value'),
                        text: value,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.25,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (under != null) ...[
                        SizedBox(height: 2.h),
                        RollingFigure(
                          key: const ValueKey('portfolio-row-pnl'),
                          text: under.text,
                          style: secondary.copyWith(
                            color: switch (under.tone) {
                              PortfolioPnlTone.up => AppColors.marketUp,
                              PortfolioPnlTone.down => AppColors.marketDown,
                              PortfolioPnlTone.flat => c.textSecondary,
                            },
                          ),
                        ),
                      ] else if (detail case final word?) ...[
                        SizedBox(height: 2.h),
                        Text(word,
                            maxLines: 1,
                            style: secondary),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Predictions picture: the market's image, rounded.
Widget _polyImage(String title, String? imageUrl, {String category = ''}) =>
    PolyCardThumbnail(
      title: title,
      imageUrl: imageUrl,
      category: category,
      size: kPortfolioRowImage.w,
      radius: 10.r,
    );

/// The price paid per share in cents ("72¢").
String _cents(double price) => '${(price * 100).round()}¢';

/// One held Polymarket position. Its value follows the held outcome's
/// live price; a sale on its way, a resolved market or a market waiting
/// for its result says so in place of the facts. Tap: the open-position
/// screen, as the card did.
class PolyPositionRow extends ConsumerWidget {
  const PolyPositionRow({super.key, required this.position});

  final PolymarketPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = position;
    final live = ref.watch(
        livePriceProvider.select((s) => s.live ? s.prices[p.tokenId] : null));
    final price = p.isResolved ? p.currentPrice : live ?? p.currentPrice;
    final value = p.size * price;
    final pnl = (price - p.avgPrice) * p.size;
    final pnlPercent = p.avgPrice > 0 ? (price / p.avgPrice - 1) * 100 : 0.0;
    final selling = p.tokenId != null &&
        ref.watch(polymarketTradingProvider.select((s) =>
            s.valueOrNull?.pendingSaleTokens.contains(p.tokenId) ?? false));

    final slug = p.eventSlug;
    final event = slug == null || slug.isEmpty
        ? null
        : ref.watch(polyPositionEventProvider(slug));
    final isGame = event != null &&
        !event.isSyntheticBinary &&
        (event.gameId != null || event.metadataGameId != null);

    // The state, where the position has one, in place of the facts.
    String? status;
    if (selling) {
      status = l10n.betSellingEllipsis;
    } else if (p.isResolved) {
      // A win is claimed automatically: it reads "Settled" like any
      // closed position.
      status = l10n.activitySettled;
    } else {
      final end = polyPositionEnd(p);
      final shortRound = polyIsShortRound(slug);
      if (shortRound && end != null) {
        final left = end.difference(DateTime.now());
        if (left > Duration.zero && left < const Duration(hours: 1)) {
          ref.watch(polyMinuteTickProvider);
        }
        if (left > Duration.zero && left <= const Duration(minutes: 1)) {
          ref.watch(polyAwaitingTickProvider);
        }
      }
      if (polyMarketHasEnded(
          eventSlug: slug, end: end, event: event, isGame: isGame)) {
        final cid = p.marketId;
        final settleAt = cid.isEmpty
            ? null
            : ref.watch(polyExpectedSettlementProvider(cid)).valueOrNull;
        if (settleAt != null) ref.watch(polyMinuteTickProvider);
        final roundEnd = polyShortRoundEnd(slug);
        if (polyShortRoundEstimating(roundEnd, DateTime.now())) {
          ref.watch(polyAwaitingTickProvider);
        }
        status = polyAwaitingText(
            l10n, polyAwaitingResultFor(p.size > 0 ? value / p.size : null),
            shortRound: shortRound, settleAt: settleAt, roundEnd: roundEnd);
      }
    }
    final facts = status ??
        l10n.portfolioRowShares(
            formatHlSize(p.size, maxDecimals: 2), _cents(p.avgPrice));

    // Crest first: a sports market carries the league's generic ball as
    // its image; the held team's crest is in the event's teams. A bare
    // Yes / No is never matched against a name.
    final teams = event?.teams ?? const [];
    final side = p.outcome.trim().toLowerCase();
    final image = (side == 'yes' || side == 'no'
            ? null
            : PolymarketEvent.logoFromTeams(teams, p.outcome)) ??
        PolymarketEvent.logoForText(teams, p.marketQuestion) ??
        p.marketImage;

    String money(double usd) => formatPolyAmount(ref, usd);
    return LiveTokenScope(
      tokens: [if (!p.isResolved && p.tokenId != null) p.tokenId!],
      keepAlive: true,
      child: PortfolioPositionRow(
        leading: _polyImage(p.marketQuestion, image,
            category: event?.category ?? ''),
        title: p.marketQuestion,
        subtitle: '${p.outcome} · $facts',
        value: money(value),
        pnl: portfolioPnlLine(money, pnl, percent: pnlPercent),
        onTap: () {
          HapticFeedback.selectionClick();
          TrackingService.track('open_investments_position_tapped',
              params: {'product': 'predictions'});
          PositionDetailSheet.show(context, position: p);
        },
      ),
    );
  }
}

/// A held combo (parlay): "Combo · N legs", its stake or its outcome,
/// its value (an estimate while open, labelled so; what it made or lost
/// once settled). Tap: the combo's sheet, as the card did.
class ComboPositionRow extends StatelessWidget {
  const ComboPositionRow({super.key, required this.position});

  final ComboPosition position;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = position;
    final settled = p.settledPayoutUsd;
    final lost = p.isLost;
    final value = lost ? 0.0 : (settled ?? p.estimatedValueUsd);
    final pnl = value - p.stakeUsd;
    final firstImage =
        p.legs.map((l) => l.imageUrl).whereType<String>().firstOrNull;
    final title = l10n.comboLegsLabel(p.legsTotal);
    return PortfolioPositionRow(
      leading: _polyImage(title, firstImage),
      title: title,
      subtitle: lost
          ? l10n.comboLegLost
          : settled != null
              ? l10n.activitySettled
              : '${l10n.comboStake} ${formatHlUsd(p.stakeUsd)}',
      value: formatHlUsd(value),
      pnl: lost || settled != null
          ? portfolioPnlLine(formatHlUsd, pnl,
              percent: p.stakeUsd > 0 ? pnl / p.stakeUsd * 100 : null)
          : null,
      detail: l10n.comboEstimatedValue,
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('open_investments_position_tapped',
            params: {'product': 'predictions', 'kind': 'combo'});
        ComboDetailSheet.show(context, conditionId: p.conditionId);
      },
    );
  }
}

/// A bet on its way to the book: its stake as the number, its step in
/// place of the facts. No tap, as before.
class PlacingBetRow extends ConsumerWidget {
  const PlacingBetRow({super.key, required this.bet});

  final PlacingBet bet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = bet;
    final step = p.status == PlacingBetStatus.failed
        ? l10n.openInvestPlacementFailed
        : p.stepLabel ?? l10n.openInvestUpdatingPosition;
    return PortfolioPositionRow(
      leading: _polyImage(p.marketQuestion, p.marketImage),
      title: p.marketQuestion,
      subtitle: '${p.outcomeName} · $step',
      value: formatPolyAmount(ref, p.amount),
    );
  }
}

/// An Investing logo, round, at the row's size.
Widget _hlImage(
        {required String coin,
        String? wireCoin,
        String? iconUrl,
        String? category}) =>
    ClipOval(
      child: HlCoinIcon(
        coin: coin,
        wireCoin: wireCoin,
        iconUrl: iconUrl,
        category: category,
        size: kPortfolioRowImage.w,
      ),
    );

/// The ticker without its dex ("xyz:NVDA" → "NVDA").
String _ticker(String coin) => coin.contains(':') ? coin.split(':').last : coin;

/// One open Hyperliquid perp: its logo and name, "Long · 0.00012 BTC ·
/// entry $90,120" (no leverage figure), what closing it now gives back
/// ([hlCloseValue]) with the P&L and its return on the margin under it,
/// at the live mid. Tap: the position details, as the card did.
class HlPositionRow extends ConsumerWidget {
  const HlPositionRow({super.key, required this.position});

  final HlPerpPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = position;
    final mid = ref.watch(hyperliquidLiveMidProvider(p.coin));
    final pnl = hlLivePnl(p, liveMid: mid);
    final margin = hlPositionMargin(p);
    final roe = margin > 0 ? pnl / margin : p.returnOnEquity;
    final descriptor = ref.watch(hyperliquidAccountMarketProvider(p.coin));
    final coin = descriptor?.coin ?? p.coin;
    String money(double usd) => formatPolyAmount(ref, usd);
    return PortfolioPositionRow(
      leading: _hlImage(
          coin: coin,
          wireCoin: descriptor?.wireCoin ?? p.coin,
          iconUrl: descriptor?.iconUrl,
          category: descriptor?.category),
      title: hlFriendlyName(p.coin) ??
          hlFriendlyName(coin) ??
          descriptor?.unitAssetName ??
          coin,
      subtitle: [
        p.isLong ? l10n.longLabel : l10n.shortLabel,
        '${formatHlSize(p.szi.abs())} ${_ticker(coin)}',
        l10n.portfolioRowEntry(formatHlPrice(p.entryPx)),
      ].join(' · '),
      value: money(hlCloseValue(p, liveMid: mid)),
      pnl: portfolioPnlLine(money, pnl, percent: roe * 100),
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('open_investments_position_tapped',
            params: {'product': 'trading'});
        HlPositionDetailSheet.show(context, position: p, market: descriptor);
      },
    );
  }
}

/// A spot holding: its logo and name, "0.5 HYPE · Spot", its value at the
/// mid with the P&L against what the venue records as paid (none for a
/// holding with no cost on record). Tap: the market, as the card did.
class HlSpotRow extends ConsumerWidget {
  const HlSpotRow({super.key, required this.balance});

  final HlSpotBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final markets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
        const <HlMarket>[];
    final market = markets.where((m) => m.coin == balance.coin).firstOrNull;
    final value = market != null && market.midPx > 0
        ? balance.total * market.midPx
        : null;
    final cost = balance.costBasis;
    final pnl = cost != null && value != null ? value - cost : null;
    String money(double usd) => formatPolyAmount(ref, usd);
    return PortfolioPositionRow(
      leading: _hlImage(
          coin: balance.coin,
          wireCoin: market?.wireCoin,
          iconUrl: market?.iconUrl,
          category: market?.category),
      title:
          hlFriendlyName(balance.coin) ?? market?.unitAssetName ?? balance.coin,
      subtitle:
          '${formatHlSize(balance.total)} ${balance.coin} · ${l10n.investingSpot}',
      value: value == null ? '—' : money(value),
      pnl: pnl == null
          ? null
          : portfolioPnlLine(money, pnl,
              percent: cost != null && cost > 0 ? pnl / cost * 100 : null),
      onTap: market == null
          ? null
          : () => HlMarketDetailSheet.show(context, market: market),
    );
  }
}
