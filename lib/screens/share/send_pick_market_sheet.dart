// lib/screens/share/send_pick_market_sheet.dart
//
// SEND A PREDICTION OR INVESTMENT FROM THE DOLLAR SEND (founder, 31
// October 2026): people must be able to send a pick from the Send screen,
// not only from a market page. The "Send a prediction or investment" row
// of the dollar send's Send to card opens this picker: the search sheet's
// own result rows (search_rows.dart) scoped to Predictions and Investing,
// "Trending predictions" from the loaded trending feed and "Moving now"
// from the loaded Investing universe, a search field filtering both. A
// picked market opens the side choice (Yes / No with the leading outcome
// preselected on a binary prediction, the outcomes as rows otherwise;
// Long / Short with Long preselected on Investing) as the slip's own
// pair, then Send to anyone for dollars with the pick, exactly as a
// market page's bar does (kute_share_actions.dart). A recipient picked
// before the row (a contact) rides along as the link's label.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart'
    show kShareVenueHyperliquid, kShareVenuePolymarket, polymarketLeadingPick;
import 'package:kute/screens/shared/market_side_toggle.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard, SendToListRow;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The two feeds the picker lists.
typedef SendPickFeeds = ({
  List<PolymarketEvent> predictions,
  List<HlMarket> investing,
});

/// Opens the picker over the dollar send. Resolves to true when a link
/// was created. [senderLabel] and [recipientPhone] are the recipient
/// picked before the row, if any (send_to_anyone_sheet.dart).
Future<bool?> showSendPickMarketSheet(
  BuildContext context, {
  required String entrySource,
  String? senderLabel,
  String? recipientPhone,
}) {
  TrackingService.track('send_pick_market_opened', params: {'source': 'send'});
  return showAppBottomSheet<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'send_pick_market'),
    builder: (_) => SendPickMarketSheet(
      entrySource: entrySource,
      senderLabel: senderLabel,
      recipientPhone: recipientPhone,
    ),
  );
}

class SendPickMarketSheet extends ConsumerStatefulWidget {
  const SendPickMarketSheet({
    super.key,
    required this.entrySource,
    this.senderLabel,
    this.recipientPhone,
  });

  final String entrySource;
  final String? senderLabel;
  final String? recipientPhone;

  /// Test seam: the feeds in place of the live providers.
  @visibleForTesting
  static SendPickFeeds? debugFeeds;

  @override
  ConsumerState<SendPickMarketSheet> createState() =>
      _SendPickMarketSheetState();
}

class _SendPickMarketSheetState extends ConsumerState<SendPickMarketSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  SendPickFeeds _feeds() {
    final debug = SendPickMarketSheet.debugFeeds;
    if (debug != null) return debug;
    final universe =
        ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ?? const [];
    final movers = [
      for (final m in universe)
        if (m.prevDayPx > 0 &&
            m.markPx > 0 &&
            m.dayNtlVlm >= kHlLowLiquidityDayVolumeUsd)
          m,
    ]..sort((a, b) => (b.markPx / b.prevDayPx - 1)
        .abs()
        .compareTo((a.markPx / a.prevDayPx - 1).abs()));
    final trending = ref
        .watch(polyBrowseFeedProvider(
            const PolyFeedQuery(pill: PolyPill.trending)))
        .events;
    return (predictions: trending, investing: movers);
  }

  HlMarketSearchResult _result(HlMarket m) => HlMarketSearchResult(
        coin: m.coin,
        wireCoin: m.wireCoin,
        kind: m.kind,
        isStock: isHlStockMarket(m),
        name: null,
        category: m.category,
        iconUrl: m.iconUrl,
        markPx: m.markPx,
        dayChangePct: m.dayChangePct,
        maxLeverage: m.isSpot ? null : m.offeredMaxLeverage,
        pxDecimalCap: m.pxDecimalCap,
        unitAssetName: m.unitAssetName,
        market: m,
      );

  Future<void> _pickPrediction(PolymarketEvent e) async {
    final lead = polymarketLeadingPick(e);
    if (lead == null) return;
    final pick = await _choosePredictionSide(context, e, lead);
    if (pick == null || !mounted) return;
    await _finish(
      marketSlug: e.slug,
      marketTitle: e.title,
      venue: kShareVenuePolymarket,
      outcome: pick.label,
      outcomeIndex: pick.index,
      side: 'buy',
    );
  }

  Future<void> _pickInvesting(HlMarket m) async {
    final long = await _chooseInvestingSide(context, m);
    if (long == null || !mounted) return;
    final l10n = context.l10n;
    await _finish(
      marketSlug: m.coin,
      marketTitle: m.coin,
      venue: kShareVenueHyperliquid,
      outcome: long ? l10n.longLabel : l10n.shortLabel,
      outcomeIndex: null,
      side: long ? 'long' : 'short',
    );
  }

  Future<void> _finish({
    required String marketSlug,
    required String marketTitle,
    required String venue,
    required String outcome,
    required int? outcomeIndex,
    required String side,
  }) async {
    final created = await showSendToAnyoneSheet(
      context,
      kind: ShareLinkKind.dollars,
      marketSlug: marketSlug,
      marketTitle: marketTitle,
      venue: venue,
      outcome: outcome,
      outcomeIndex: outcomeIndex,
      side: side,
      senderLabel: widget.senderLabel,
      recipientPhone: widget.recipientPhone,
      entrySource: widget.entrySource,
    );
    if (!mounted) return;
    if (created == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final feeds = _feeds();
    final q = _query.text.trim().toLowerCase();
    final predictions = q.isEmpty
        ? feeds.predictions.take(8).toList()
        : [
            for (final e in feeds.predictions)
              if (e.title.toLowerCase().contains(q)) e
          ].take(12).toList();
    final investing = q.isEmpty
        ? feeds.investing.take(8).toList()
        : [
            for (final m in feeds.investing)
              if (m.coin.toLowerCase().contains(q) ||
                  (m.unitAssetName?.toLowerCase().contains(q) ?? false))
                m
          ].take(12).toList();
    final empty = predictions.isEmpty && investing.isEmpty;
    return AppBottomSheetContainer(
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      followKeyboard: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.sendPickMarket,
            subtitle: l10n.sendPickMarketSub,
            icon: Icons.ios_share_rounded,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      color: c.textSecondary, size: 20.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('send-pick-market-search'),
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.sendPickMarketSearchHint,
                        hintStyle: TextStyle(
                          color: c.textSecondary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 32.h),
              children: [
                if (empty)
                  SearchEmptyState(text: l10n.sendPickMarketNoResults),
                if (predictions.isNotEmpty) ...[
                  SearchBlockHeader(text: l10n.searchHomeTrendingPredictions),
                  SearchSheetCard(
                    key: const ValueKey('send-pick-predictions'),
                    children: [
                      for (final e in predictions)
                        SearchPredictionRow(
                            event: e,
                            onTap: () => unawaited(_pickPrediction(e))),
                    ],
                  ),
                  SizedBox(height: 20.h),
                ],
                if (investing.isNotEmpty) ...[
                  SearchBlockHeader(text: l10n.searchHomeMovingNow),
                  SearchSheetCard(
                    key: const ValueKey('send-pick-investing'),
                    children: [
                      for (final m in investing)
                        SearchInvestingRow(
                            result: _result(m),
                            onTap: () => unawaited(_pickInvesting(m))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yes / No as the slip's pair, the leading outcome preselected; the
/// outcomes as rows on a market with more than two.
Future<({String label, int index})?> _choosePredictionSide(
  BuildContext context,
  PolymarketEvent e,
  ({String label, int index, double chance}) lead,
) {
  if (!e.isBinary) {
    return showAppBottomSheet<({String label, int index})>(
      context: context,
      builder: (sheetCtx) => AppBottomSheetContainer(
        maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: sheetCtx.l10n.sendPickSideTitle,
              subtitle: e.title,
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 32.h),
                children: [
                  SendToListCard(
                    colors: sheetCtx.colors,
                    rows: [
                      for (var i = 0; i < e.outcomes.length; i++)
                        SendToListRow(
                          key: ValueKey('send-pick-outcome-$i'),
                          colors: sheetCtx.colors,
                          leading: Icon(
                              i == lead.index
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: sheetCtx.colors.textPrimary,
                              size: 22.sp),
                          title: e.outcomes[i].name,
                          trailingTitle:
                              '${(e.outcomes[i].price * 100).round()}%',
                          onTap: () => Navigator.of(sheetCtx)
                              .pop((label: e.outcomes[i].name, index: i)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  return showAppBottomSheet<({String label, int index})>(
    context: context,
    builder: (sheetCtx) => _SideSheet(
      title: e.title,
      upLabel: sheetCtx.l10n.yes,
      downLabel: sheetCtx.l10n.betNo,
      initialUp: lead.label == 'Yes',
      onPicked: (up) {
        final label = up ? 'Yes' : 'No';
        final index = e.outcomes
            .indexWhere((o) => o.name.toLowerCase() == label.toLowerCase());
        Navigator.of(sheetCtx).pop((label: label, index: index < 0 ? 0 : index));
      },
    ),
  );
}

/// Long / Short, Long preselected. Resolves to whether Long was picked.
Future<bool?> _chooseInvestingSide(BuildContext context, HlMarket m) =>
    showAppBottomSheet<bool>(
      context: context,
      builder: (sheetCtx) => _SideSheet(
        title: m.coin,
        upLabel: sheetCtx.l10n.longLabel,
        downLabel: sheetCtx.l10n.shortLabel,
        initialUp: true,
        onPicked: (up) => Navigator.of(sheetCtx).pop(up),
      ),
    );

class _SideSheet extends StatefulWidget {
  const _SideSheet({
    required this.title,
    required this.upLabel,
    required this.downLabel,
    required this.initialUp,
    required this.onPicked,
  });

  final String title;
  final String upLabel;
  final String downLabel;
  final bool initialUp;
  final ValueChanged<bool> onPicked;

  @override
  State<_SideSheet> createState() => _SideSheetState();
}

class _SideSheetState extends State<_SideSheet> {
  late bool _up = widget.initialUp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.sendPickSideTitle,
            subtitle: widget.title,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarketSideToggle(
                  key: const ValueKey('send-pick-side-toggle'),
                  isUp: _up,
                  upLabel: widget.upLabel,
                  downLabel: widget.downLabel,
                  onChanged: (up) => setState(() => _up = up),
                ),
                // Continue is the bar (kute_bar_context.dart).
                KuteBarContextScope(
                  barContext: KuteBarContext.primary(
                    label: l10n.continueLabel,
                    onPrimary: () => widget.onPicked(_up),
                    source: 'send_pick_side',
                  ),
                  child: SizedBox(height: kuteBarScrollClearance.h),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
