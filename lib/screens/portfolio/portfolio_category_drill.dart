// lib/screens/portfolio/portfolio_category_drill.dart
//
// A Statistics donut slice opened up (PortfolioCategoryCard.drill), for
// Predictions and Investing, Active and Historic, on the spending wallet
// and on a Ledger:
//
//   * Level 1, in the legend's place: what is in the category, largest
//     first, each as a legend row with its image in place of the dot
//     (Predictions: events, by their image and title; Investing: coins,
//     by their logo and ticker), its share of the slice and its amount
//     on the sub-tab's own basis (Active: what it is worth now; Historic:
//     amount predicted, volume traded). Ten at most, "See all" for the
//     rest.
//   * Level 2, a tap on an item opens it under itself (one at a time): a
//     line per position it is made of, with its P&L in the app's up /
//     down colours. Predictions: each market / outcome held (Active: what
//     it is worth now and its open P&L; Historic: won, lost, sold or
//     still open, with what it realised). Investing: Active, the open
//     position (side, leverage, size, entry) or spot holding with its
//     open P&L; Historic, its round trips with what closing realised net
//     of fees.
//   * A tap on a line opens the position's or the market's own screen.
//   * Hidden balances mask every amount, share count, size and P&L.
//   * Analytics: the slice's `portfolio_category_slice_selected` again,
//     `drill_level` 2 with the item's rank when an item opens, 3 with the
//     line's kind when a line opens. Categorical only: never an amount,
//     a market or an id.
//
// The rows are the legend's (its insets, caption type and inset tone)
// and the lines the activity rows' shape (title and caption on the left,
// the figure and the one figure under it on the right); no chrome of
// their own.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlPrice, formatHlSize;
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart'
    show hlCloseValue, hlPositionMargin;
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/polymarket/components/market_card.dart'
    show PolyCardThumbnail, polyCardCaptionStyle;
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/portfolio/portfolio_category_donut.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetAnimatedSize;
import 'package:kute/services/portfolio/portfolio_categories.dart'
    show kPortfolioOtherCategory, predictionLiveValueUsd;
import 'package:kute/services/portfolio/portfolio_category_items.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Items (and an item's lines) shown before "See all".
const int kCategoryDrillCap = 10;

/// The surface analytics name for screens opened from a drill-down line.
const String kCategoryDrillSource = 'portfolio_statistics';

/// The slice's own analytics params (as its pick sent them), for the
/// drill-down's deeper levels.
Map<String, Object> categoryDrillParams(
  CategorySlice slice, {
  required CategoryVenue venue,
  required String walletKind,
  required String scope,
}) =>
    {
      'venue': venue.name,
      'slice_rank': slice.rank,
      'category_kind': slice.kind.name,
      'category': slice.key,
      'wallet_kind': walletKind,
      'scope': scope,
    };

/// One line under an opened item.
class CategoryDrillLine {
  const CategoryDrillLine({
    required this.key,
    required this.kind,
    required this.title,
    required this.caption,
    required this.figure,
    this.status,
    this.statusColor,
    this.figureColor,
    this.detail,
    this.detailColor,
    this.onTap,
  });

  final String key;

  /// What the line is, for analytics ('open', 'won', 'lost', 'sold',
  /// 'perp', 'spot', 'round_trip').
  final String kind;
  final String title;

  /// A word leading the caption in its own colour ("Won · …").
  final String? status;
  final Color? statusColor;
  final String caption;
  final String figure;
  final Color? figureColor;

  /// The one figure under [figure].
  final String? detail;
  final Color? detailColor;
  final VoidCallback? onTap;
}

/// One item of an opened slice.
class CategoryDrillItem {
  const CategoryDrillItem({
    required this.key,
    required this.leading,
    required this.title,
    required this.share,
    required this.amount,
    required this.lines,
  });

  final String key;
  final Widget leading;
  final Widget title;
  final String share;
  final String amount;

  /// Built when the item opens.
  final List<CategoryDrillLine> Function() lines;
}

/// The items of an opened slice, the first [kCategoryDrillCap] and "See
/// all", each opening under itself to its lines (one item open at a
/// time).
class CategoryDrillList extends StatefulWidget {
  const CategoryDrillList({
    super.key,
    required this.items,
    required this.params,
  });

  final List<CategoryDrillItem> items;

  /// The slice's analytics params ([categoryDrillParams]).
  final Map<String, Object> params;

  @override
  State<CategoryDrillList> createState() => _CategoryDrillListState();
}

class _CategoryDrillListState extends State<CategoryDrillList> {
  String? _open;
  bool _all = false;
  final Set<String> _allLines = {};

  void _toggle(CategoryDrillItem item, int rank) {
    HapticFeedback.selectionClick();
    final opening = _open != item.key;
    setState(() => _open = opening ? item.key : null);
    if (opening) {
      TrackingService.track('portfolio_category_slice_selected', params: {
        ...widget.params,
        'drill_level': 2,
        'item_rank': rank,
      });
    }
  }

  void _openLine(CategoryDrillLine line) {
    final onTap = line.onTap;
    if (onTap == null) return;
    HapticFeedback.selectionClick();
    TrackingService.track('portfolio_category_slice_selected', params: {
      ...widget.params,
      'drill_level': 3,
      'line_kind': line.kind,
    });
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final shown =
        _all ? items : items.take(kCategoryDrillCap).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          _ItemRow(
            key: ValueKey('category-drill-item-${shown[i].key}'),
            item: shown[i],
            open: _open == shown[i].key,
            onTap: () => _toggle(shown[i], i + 1),
          ),
          SheetAnimatedSize(
            child: _open == shown[i].key
                ? _lines(shown[i])
                : const SizedBox(width: double.infinity),
          ),
        ],
        if (!_all && items.length > kCategoryDrillCap)
          _SeeAll(
            key: const ValueKey('category-drill-see-all'),
            onTap: () => setState(() => _all = true),
          ),
      ],
    );
  }

  Widget _lines(CategoryDrillItem item) {
    final lines = item.lines();
    final all = _allLines.contains(item.key);
    final shown =
        all ? lines : lines.take(kCategoryDrillCap).toList(growable: false);
    return Padding(
      // Under the item's name, past its image.
      padding: EdgeInsets.only(left: 38.w, bottom: 4.h),
      child: Column(
        key: ValueKey('category-drill-lines-${item.key}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in shown)
            _LineRow(
              key: ValueKey('category-drill-line-${line.key}'),
              line: line,
              onTap: line.onTap == null ? null : () => _openLine(line),
            ),
          if (!all && lines.length > kCategoryDrillCap)
            _SeeAll(
              key: ValueKey('category-drill-lines-see-all-${item.key}'),
              onTap: () => setState(() => _allLines.add(item.key)),
            ),
        ],
      ),
    );
  }
}

/// An item as a legend row: its image where the dot was, its name
/// (wrapping under large text), its share and its amount, and the
/// disclosure chevron. The open item sits on the inset tone.
class _ItemRow extends StatelessWidget {
  const _ItemRow(
      {super.key, required this.item, required this.open, required this.onTap});
  final CategoryDrillItem item;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final caption = polyCardCaptionStyle(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final radius = BorderRadius.circular(AppRadius.sm);
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: open,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: kuteMotion(context, kSelectionFadeDuration),
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: open ? c.surfaceLight : Colors.transparent,
                borderRadius: radius,
              ),
              child: Row(
                children: [
                  SizedBox.square(dimension: 28.w, child: item.leading),
                  SizedBox(width: 10.w),
                  Expanded(
                    flex: 3,
                    child: DefaultTextStyle(
                      style: caption.copyWith(
                        color: c.textPrimary,
                        fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                      ),
                      child: item.title,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Flexible(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.share, style: caption),
                          SizedBox(width: 12.w),
                          Text(
                            item.amount,
                            style: caption.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18.sp,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One P&L line, in the activity row's shape: title over its caption on
/// the left, the figure over the one figure under it on the right.
class _LineRow extends StatelessWidget {
  const _LineRow({super.key, required this.line, this.onTap});
  final CategoryDrillLine line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final caption = polyCardCaptionStyle(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final radius = BorderRadius.circular(AppRadius.sm);
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: caption.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 2.h),
                Text.rich(
                  TextSpan(children: [
                    if (line.status != null) ...[
                      TextSpan(
                          text: line.status,
                          style: TextStyle(
                              color: line.statusColor ?? c.textSecondary,
                              fontWeight: FontWeight.w600)),
                      if (line.caption.isNotEmpty) const TextSpan(text: ' · '),
                    ],
                    TextSpan(text: line.caption),
                  ]),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: caption,
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.figure,
                    style: caption.copyWith(
                        color: line.figureColor ?? c.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  if (line.detail != null && line.detail!.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      line.detail!,
                      style: caption.copyWith(
                          color: line.detailColor ?? c.textTertiary,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: onTap, borderRadius: radius, child: row),
        ),
      ),
    );
  }
}

/// "See all", in the disclosure's quiet type.
class _SeeAll extends StatelessWidget {
  const _SeeAll({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
          child: Text(
            context.l10n.seeAll,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── shared figures ───────────────────────────

/// The figures of a drill-down, masked when balances are hidden.
class _Figures {
  _Figures(this.ref, this.visible, this.c);
  final WidgetRef ref;
  final bool visible;
  final AppColorsExtension c;

  static const _mask = '••••••';

  String money(double v) => visible ? formatPolyAmount(ref, v) : _mask;

  /// "+$3.80" / "−$5.00", the percent after it when given.
  String signed(double v, {double? percent}) {
    if (!visible) return _mask;
    final sign = v > 0
        ? '+'
        : v < 0
            ? '−'
            : '';
    final pct = percent == null || !percent.isFinite
        ? ''
        : ' ($sign${percent.abs().toStringAsFixed(1)}%)';
    return '$sign${formatPolyAmount(ref, v.abs())}$pct';
  }

  Color pnl(double v) => !visible || v == 0
      ? c.textPrimary
      : (v > 0 ? AppColors.marketUp : AppColors.marketDown);

  String share(double part, double total) {
    if (!visible) return '••%';
    if (total <= 0) return '';
    final pct = (part / total * 100).round();
    return pct == 0 ? '<1%' : '$pct%';
  }
}

// ───────────────────────────── predictions ─────────────────────────────

/// A Predictions slice opened up: its events and, under each, its
/// positions. [records] are the sub-tab's (Active: the live ones;
/// Historic: every one), [categories] their markets' categories by
/// condition id.
class PredictionCategoryDrill extends ConsumerWidget {
  const PredictionCategoryDrill({
    super.key,
    required this.records,
    required this.categories,
    required this.inSlice,
    required this.active,
    required this.params,
    this.walletId,
  });

  final List<PredictionRecord> records;
  final Map<String, String> categories;
  final bool Function(String category) inSlice;
  final bool active;
  final Map<String, Object> params;

  /// Null for the spending account; a Ledger wallet's ID otherwise.
  final String? walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // The live prices the donut and the tiles value open predictions at.
    final live = active
        ? ref.watch(livePriceProvider.select((s) => s.prices))
        : const <String, double>{};
    final f = _Figures(ref, visible, c);
    double amount(PredictionRecord r) =>
        active ? predictionLiveValueUsd(r, live) : r.stakeUsd;
    final inThisSlice = records.where((r) => inSlice(
        categories[r.conditionId.toLowerCase()] ?? kPortfolioOtherCategory));
    final events = predictionEventItems(inThisSlice, amount);
    final total = events.fold<double>(0, (sum, e) => sum + e.value);

    CategoryDrillLine line(PredictionRecord r) {
      final shares = l10n.portfolioPredictionEntry(
          formatHlSize(r.size > 0 ? r.size : r.totalSize, maxDecimals: 2),
          '${(r.avgPrice * 100).round()}¢');
      final position = [
        if (r.outcome.isNotEmpty) r.outcome,
        if (visible) shares,
      ].join(' · ');
      final title = r.title.isNotEmpty ? r.title : r.outcome;
      void open() => _openPrediction(context, ref, r);
      if (active) {
        final value = predictionLiveValueUsd(r, live);
        final pnl = value - r.entryCostUsd;
        return CategoryDrillLine(
          key: r.tokenId,
          kind: 'open',
          title: title,
          caption: position,
          figure: f.money(value),
          detail: f.signed(pnl,
              percent: r.entryCostUsd > 0 ? pnl / r.entryCostUsd * 100 : null),
          detailColor: f.pnl(pnl),
          onTap: open,
        );
      }
      final result = predictionLineResult(r);
      final realized = predictionLineRealizedUsd(r);
      return CategoryDrillLine(
        key: r.tokenId,
        kind: result.name,
        title: title,
        status: switch (result) {
          PredictionLineResult.open => l10n.comboLegOpen,
          PredictionLineResult.won => l10n.comboLegWon,
          PredictionLineResult.lost => l10n.comboLegLost,
          PredictionLineResult.sold => l10n.investingSold,
        },
        statusColor: switch (result) {
          PredictionLineResult.won => AppColors.marketUp,
          PredictionLineResult.lost => AppColors.marketDown,
          _ => c.textSecondary,
        },
        caption: position,
        figure: f.signed(realized),
        figureColor: f.pnl(realized),
        detail: f.money(r.stakeUsd),
        onTap: open,
      );
    }

    return CategoryDrillList(
      params: params,
      items: [
        for (final e in events)
          CategoryDrillItem(
            key: e.key,
            leading: _EventThumbnail(item: e),
            title: _EventTitle(item: e),
            share: f.share(e.value, total),
            amount: f.money(e.value),
            lines: () => [for (final r in e.records) line(r)],
          ),
      ],
    );
  }

  /// The position's own screen while it is open on the spending account;
  /// otherwise its event's screen (a Ledger's, or a decided prediction).
  void _openPrediction(
      BuildContext context, WidgetRef ref, PredictionRecord r) {
    if (walletId == null && active) {
      final held = ref
          .read(polymarketActivePositionsProvider)
          .where((p) => p.tokenId == r.tokenId)
          .firstOrNull;
      if (held != null) {
        PositionDetailSheet.show(context, position: held);
        return;
      }
    }
    final slug = r.eventSlug;
    if (slug.isEmpty) return;
    final event = ref.read(polyPositionEventProvider(slug));
    if (event == null) return;
    MarketDetailSheet.show(context,
        event: event, ledgerWalletId: walletId, source: kCategoryDrillSource);
  }
}

/// An event's image: the event's own (read by its slug from the cards'
/// shared batch), else its market's.
class _EventThumbnail extends ConsumerWidget {
  const _EventThumbnail({required this.item});
  final PredictionEventItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = item.eventSlug.isEmpty
        ? null
        : ref.watch(polyPositionEventProvider(item.eventSlug));
    final image = event?.imageUrl;
    return PolyCardThumbnail(
      title: event?.title ?? item.title,
      imageUrl: image != null && image.isNotEmpty ? image : item.icon,
      category: event?.category ?? '',
      size: 28.w,
      radius: 8.r,
    );
  }
}

/// An event's title: the event's own, else its first market's question.
class _EventTitle extends ConsumerWidget {
  const _EventTitle({required this.item});
  final PredictionEventItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = item.eventSlug.isEmpty
        ? null
        : ref.watch(polyPositionEventProvider(item.eventSlug));
    final title = (event?.title ?? '').trim().isNotEmpty
        ? event!.title.trim()
        : item.title.isNotEmpty
            ? item.title
            : context.l10n.betGroupOther;
    return Text(title, maxLines: 3, overflow: TextOverflow.ellipsis);
  }
}

// ────────────────────────────── investing ──────────────────────────────

/// One open Investing holding: a perp position or a spot balance, with
/// its market when known and what the Open tab's card shows it worth.
class TradingHolding {
  const TradingHolding({
    required this.coin,
    required this.market,
    required this.value,
    this.position,
    this.spot,
  });

  /// The wire coin.
  final String coin;
  final HlMarket? market;
  final double value;
  final HlPerpPosition? position;
  final HlSpotBalance? spot;
}

/// An Investing slice opened up: its coins and, under each, the open
/// position (Active) or its round trips (Historic).
class TradingCategoryDrill extends ConsumerWidget {
  const TradingCategoryDrill.active({
    super.key,
    required List<TradingHolding> this.holdings,
    required this.inSlice,
    required this.marketsByWire,
    required this.params,
    this.walletId,
  }) : fills = null;

  const TradingCategoryDrill.historic({
    super.key,
    required List<HlFill> this.fills,
    required this.inSlice,
    required this.marketsByWire,
    required this.params,
    this.walletId,
  }) : holdings = null;

  final List<TradingHolding>? holdings;
  final List<HlFill>? fills;

  /// Whether a coin (with its market when known) is in the slice.
  final bool Function(String coin, HlMarket? market) inSlice;
  final Map<String, HlMarket> marketsByWire;
  final Map<String, Object> params;

  /// Null for the spending account; a Ledger wallet's ID otherwise.
  final String? walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final f = _Figures(ref, visible, c);
    final items = holdings != null
        ? _activeItems(context, f)
        : _historicItems(context, f);
    return CategoryDrillList(params: params, items: items);
  }

  Widget _logo(String coin, HlMarket? market) => ClipOval(
        child: HlCoinIcon(
          coin: market?.coin ?? coin,
          wireCoin: market?.wireCoin ?? coin,
          iconUrl: market?.iconUrl,
          category: market?.category,
          size: 28.w,
        ),
      );

  Widget _ticker(String coin, HlMarket? market) => Text(
        hlBaseCoin(market?.coin ?? coin),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );

  List<CategoryDrillItem> _activeItems(BuildContext context, _Figures f) {
    final l10n = context.l10n;
    final coins = tradingCoinItems<TradingHolding>(
        holdings!.where((h) => inSlice(h.coin, h.market)),
        coinOf: (h) => h.coin,
        amount: (h) => h.value);
    final total = coins.fold<double>(0, (sum, i) => sum + i.value);

    CategoryDrillLine line(TradingHolding h) {
      final p = h.position;
      if (p != null) {
        final pnl = p.unrealizedPnl;
        final margin = hlPositionMargin(p);
        return CategoryDrillLine(
          key: 'perp-${h.coin}',
          kind: 'perp',
          title: '${p.isLong ? l10n.longLabel : l10n.shortLabel} '
              '${p.leverageValue}x',
          caption: [
            if (f.visible) '${l10n.hlBookSize} ${formatHlSize(p.szi.abs())}',
            '${l10n.hlChartEntry} ${formatHlPrice(p.entryPx)}',
          ].join(' · '),
          figure: f.money(hlCloseValue(p)),
          detail:
              f.signed(pnl, percent: margin > 0 ? pnl / margin * 100 : null),
          detailColor: f.pnl(pnl),
          onTap: () => HlPositionDetailSheet.show(context,
              position: p, market: h.market, ledgerWalletId: walletId),
        );
      }
      final spot = h.spot!;
      final cost = spot.costBasis;
      final pnl = cost == null ? null : h.value - cost;
      final market = h.market;
      return CategoryDrillLine(
        key: 'spot-${h.coin}',
        kind: 'spot',
        title: l10n.investingSpot,
        caption: f.visible ? l10n.openInvestHeld(formatHlSize(spot.total)) : '',
        figure: f.money(h.value),
        detail: pnl == null
            ? null
            : f.signed(pnl,
                percent: cost != null && cost > 0 ? pnl / cost * 100 : null),
        detailColor: pnl == null ? null : f.pnl(pnl),
        onTap: market == null
            ? null
            : () => HlMarketDetailSheet.show(context,
                market: market,
                ledgerWalletId: walletId,
                source: kCategoryDrillSource),
      );
    }

    return [
      for (final item in coins)
        CategoryDrillItem(
          key: item.coin,
          leading: _logo(item.coin, item.entries.first.market),
          title: _ticker(item.coin, item.entries.first.market),
          share: f.share(item.value, total),
          amount: f.money(item.value),
          lines: () => [for (final h in item.entries) line(h)],
        ),
    ];
  }

  List<CategoryDrillItem> _historicItems(BuildContext context, _Figures f) {
    final l10n = context.l10n;
    final coins = tradingCoinItems<HlFill>(
        fills!.where((fill) => inSlice(fill.coin, marketsByWire[fill.coin])),
        coinOf: (fill) => fill.coin,
        amount: (fill) => fill.px * fill.sz);
    final total = coins.fold<double>(0, (sum, i) => sum + i.value);
    final day = DateFormat.MMMd();
    String date(int ms) => day.format(DateTime.fromMillisecondsSinceEpoch(ms));

    return [
      for (final item in coins)
        CategoryDrillItem(
          key: item.coin,
          leading: _logo(item.coin, marketsByWire[item.coin]),
          title: _ticker(item.coin, marketsByWire[item.coin]),
          share: f.share(item.value, total),
          amount: f.money(item.value),
          lines: () {
            final market = marketsByWire[item.coin];
            final spot = market?.isSpot ??
                (item.coin.startsWith('@') || item.coin.contains('/'));
            return [
              for (final trip in tradingRoundTrips(item.entries))
                CategoryDrillLine(
                  key: '${item.coin}-${trip.openedAt}-${trip.closedAt}',
                  kind: 'round_trip',
                  title: spot
                      ? l10n.investingSpot
                      : trip.long
                          ? l10n.longLabel
                          : l10n.shortLabel,
                  status: trip.open ? l10n.comboLegOpen : null,
                  caption: trip.open
                      ? date(trip.openedAt)
                      : date(trip.openedAt) == date(trip.closedAt!)
                          ? date(trip.closedAt!)
                          : '${date(trip.openedAt)} – ${date(trip.closedAt!)}',
                  figure: f.signed(trip.realizedUsd),
                  figureColor: f.pnl(trip.realizedUsd),
                  detail: f.money(trip.volumeUsd),
                  onTap: market == null
                      ? null
                      : () => HlMarketDetailSheet.show(context,
                          market: market,
                          ledgerWalletId: walletId,
                          source: kCategoryDrillSource),
                ),
            ];
          },
        ),
    ];
  }
}
