// lib/screens/share/send_pick_market_sheet.dart
//
// SEND A PREDICTION OR AN INVESTMENT FROM SEND (founder, 31 October 2026:
// people must be able to send a pick from the Send screen, not only from
// a market page). The Dollars Send's "Send a prediction or investment" row
// opens this sheet.
//
// THE SEARCH WE ALREADY HAVE (founder, 4 November 2026: "Sending the
// actual prediction sucks ... Should just somehow allow you to search the
// prediction you want and open it, use the stuff and design we already
// have for Hyperliquid search and Polymarket"). The sheet is the Sal
// sheet's search, scoped to Predictions and Investing:
//
//   * the search sheet's own line (KuteSearchComposer without Sal: the
//     magnifier, the text, the clear ✕), "Search predictions and
//     investing";
//   * nothing typed: "Trending predictions" from the loaded trending feed
//     and "Moving now" from the loaded Investing universe, the search
//     sheet's rows (SearchPredictionRow, SearchInvestingRow);
//   * typed: the venues' own searches, the ones the search sheet runs
//     (polymarketSearchProvider, hyperliquidMarketSearchProvider), under
//     "Predictions" and "Investing", skeleton rows while they answer, the
//     loaded markets that match standing in meanwhile; Sal's sad face
//     when nothing matches.
//
// A TAP OPENS THE MARKET, AND ITS SLIP SENDS (founder, 5 November 2026:
// the share belongs on the slip, "it carries all the information, even
// the amount"; screens/share/slip_share.dart). A tap on a market opens
// its page, the one the search sheet opens (MarketDetailSheet,
// HlMarketDetailSheet), where the person picks the side as they always
// do (Yes | No, Invest | Short, an outcome's row: nothing chosen for
// them), types the amount on the slip, and sends it with the slip's round
// Sal button. The header says so. The slip is the one place a prediction
// is composed, so a slip cannot open here with a side nobody picked.
//
// A venue the region's policy does not offer, or where this person cannot
// place a prediction (an investment), is left out
// (runtimeCapabilitiesProvider: `polymarket.browse` and `polymarket.trade`,
// `hyperliquid.browse` and `hyperliquid.trade`): a slip there could only
// send the market's card ("when the user is blocked on Polymarket he
// cannot also send the actual prediction, just the card"). The Send
// screen hides its card when neither is open (sendPickOffered).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_rows.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/polymarket/market_detail_sheet.dart'
    show MarketDetailSheet;
import 'package:kute/screens/shared/message_display.dart'
    show showMessageSnackBar;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_skeleton.dart' show SkeletonRowList;
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService, runtimeCapabilitiesProvider;
import 'package:kute/services/tracking_service.dart';

/// The two feeds the sheet lists while nothing is typed.
typedef SendPickFeeds = ({
  List<PolymarketEvent> predictions,
  List<HlMarket> investing,
});

/// How many rows each block shows while nothing is typed.
const int kSendPickHomeRows = 6;

/// How many results each venue shows.
const int kSendPickResultRows = 8;

/// Whether a prediction or an investment can be composed to send here:
/// either venue offered and open to this person (see the file header).
bool sendPickOffered(RuntimeCapabilitiesService policy) =>
    (policy.allows('polymarket.browse') &&
        policy.allows('polymarket.trade')) ||
    (policy.allows('hyperliquid.browse') &&
        policy.allows('hyperliquid.trade'));

/// Opens the sheet over the dollar send. A market tapped opens its page
/// (see the file header); the sheet stays under it. [senderLabel] and
/// [recipientPhone] are the recipient picked before the row, if any:
/// kept for the callers, the slip's send asks the name itself.
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

  /// Test seam: what a tapped market opens (a [PolymarketEvent] or an
  /// [HlMarket]); null opens its page.
  @visibleForTesting
  static void Function(Object market)? debugOpenMarket;

  @override
  ConsumerState<SendPickMarketSheet> createState() =>
      _SendPickMarketSheetState();
}

class _SendPickMarketSheetState extends ConsumerState<SendPickMarketSheet> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  SendPickFeeds _feeds({required bool predictions, required bool investing}) {
    final debug = SendPickMarketSheet.debugFeeds;
    if (debug != null) return debug;
    final universe = investing
        ? ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ??
            const <HlMarket>[]
        : const <HlMarket>[];
    final movers = [
      for (final m in universe)
        if (m.prevDayPx > 0 &&
            m.markPx > 0 &&
            m.dayNtlVlm >= kHlLowLiquidityDayVolumeUsd)
          m,
    ]..sort((a, b) => (b.markPx / b.prevDayPx - 1)
        .abs()
        .compareTo((a.markPx / a.prevDayPx - 1).abs()));
    final trending = predictions
        ? ref
            .watch(polyBrowseFeedProvider(
                const PolyFeedQuery(pill: PolyPill.trending)))
            .events
        : const <PolymarketEvent>[];
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

  void _picked(String venue) {
    TrackingService.track('send_pick_market_picked', params: {
      'venue': venue,
      'searched': _query.text.trim().isNotEmpty,
    });
    _focus.unfocus();
  }

  /// A prediction tapped: its page, as the search sheet opens it.
  void _openPrediction(PolymarketEvent e) {
    _picked('polymarket');
    final debug = SendPickMarketSheet.debugOpenMarket;
    if (debug != null) return debug(e);
    MarketDetailSheet.show(context, event: e, source: 'send_pick');
  }

  /// An Investing market tapped: this row's own instrument (the row's
  /// market, else the one its wire id pins), its page.
  void _openInvesting(HlMarketSearchResult r) {
    _picked('hyperliquid');
    final market = r.market ??
        ref.read(hyperliquidExactMarketProvider(
            '${r.kind.name}:${r.wireCoin}'));
    if (market == null) {
      showMessageSnackBar(
          context: context, message: context.l10n.notAvailable, error: true);
      return;
    }
    final debug = SendPickMarketSheet.debugOpenMarket;
    if (debug != null) return debug(market);
    HlMarketDetailSheet.show(context, market: market, source: 'send_pick');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final debug = SendPickMarketSheet.debugFeeds != null;
    // Only a venue where the slip can send (see the file header).
    final showPredictions = (debug || policy.allows('polymarket.browse')) &&
        policy.allows('polymarket.trade');
    final showInvesting = (debug || policy.allows('hyperliquid.browse')) &&
        policy.allows('hyperliquid.trade');
    final q = _query.text.trim();
    final blocks = q.isEmpty
        ? _home(showPredictions: showPredictions, showInvesting: showInvesting)
        : _results(q,
            showPredictions: showPredictions, showInvesting: showInvesting);
    return AppBottomSheetContainer(
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      followKeyboard: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.sendPickMarket,
            // How it sends: the side and amount on the market's slip, then
            // its Sal button (see the file header).
            subtitle: l10n.sendPickMarketHow,
            icon: Icons.ios_share_rounded,
          ),
          // The search sheet's own line (search_composer.dart), Sal off,
          // on the sheet header's gutters.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: KuteSearchComposer(
              key: const ValueKey('send-pick-market-search'),
              controller: _query,
              focusNode: _focus,
              aiEnabled: false,
              hint: l10n.sendPickMarketSearchHint,
              onChanged: (_) => setState(() {}),
              onSubmit: _focus.unfocus,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0) SizedBox(height: kSearchBlockGap.h),
                  blocks[i],
                ],
                // The rows scroll clear of the floating bar.
                SizedBox(height: kuteBarScrollClearance.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Nothing typed: Trending predictions and Moving now.
  List<Widget> _home(
      {required bool showPredictions, required bool showInvesting}) {
    final l10n = context.l10n;
    final feeds =
        _feeds(predictions: showPredictions, investing: showInvesting);
    final predictions =
        feeds.predictions.take(kSendPickHomeRows).toList(growable: false);
    final investing =
        feeds.investing.take(kSendPickHomeRows).toList(growable: false);
    return [
      if (showPredictions)
        _block(
          l10n.searchHomeTrendingPredictions,
          predictions.isEmpty
              ? _skeleton('send-pick-predictions-loading')
              : SearchRowList(
                  key: const ValueKey('send-pick-predictions'),
                  children: [
                    for (final e in predictions)
                      SearchPredictionRow(
                          event: e, onTap: () => _openPrediction(e)),
                  ],
                ),
        ),
      if (showInvesting && investing.isNotEmpty)
        _block(
          l10n.searchHomeMovingNow,
          SearchRowList(
            key: const ValueKey('send-pick-investing'),
            children: [
              for (final m in investing)
                SearchInvestingRow(
                    result: _result(m),
                    onTap: () => _openInvesting(_result(m))),
            ],
          ),
        ),
    ];
  }

  /// Typed: the venues' own searches, the loaded markets that match
  /// standing in while they answer.
  List<Widget> _results(String q,
      {required bool showPredictions, required bool showInvesting}) {
    final l10n = context.l10n;
    final lower = q.toLowerCase();
    final feeds =
        _feeds(predictions: showPredictions, investing: showInvesting);

    var predictionsLoading = false;
    var predictions = const <PolymarketEvent>[];
    if (showPredictions) {
      final async = ref.watch(polymarketSearchProvider(q));
      final found = async.valueOrNull;
      predictionsLoading = found == null && async.isLoading;
      predictions = (found ??
              [
                for (final e in feeds.predictions)
                  if (e.title.toLowerCase().contains(lower)) e
              ])
          .take(kSendPickResultRows)
          .toList();
    }

    var investingLoading = false;
    var investing = const <HlMarketSearchResult>[];
    if (showInvesting) {
      final async = ref.watch(hyperliquidMarketSearchProvider(q));
      final found = async.valueOrNull;
      investingLoading = found == null && async.isLoading;
      investing = (found ??
              [
                for (final m in feeds.investing)
                  if (m.coin.toLowerCase().contains(lower) ||
                      (m.unitAssetName?.toLowerCase().contains(lower) ??
                          false))
                    _result(m)
              ])
          .take(kSendPickResultRows)
          .toList();
    }

    final blocks = <Widget>[
      if (predictions.isNotEmpty || predictionsLoading)
        _block(
          l10n.predictions,
          predictions.isEmpty
              ? _skeleton('send-pick-predictions-loading')
              : SearchRowList(
                  key: const ValueKey('send-pick-predictions'),
                  children: [
                    for (final e in predictions)
                      SearchPredictionRow(
                          event: e, onTap: () => _openPrediction(e)),
                  ],
                ),
        ),
      if (investing.isNotEmpty || investingLoading)
        _block(
          l10n.trading,
          investing.isEmpty
              ? _skeleton('send-pick-investing-loading')
              : SearchRowList(
                  key: const ValueKey('send-pick-investing'),
                  children: [
                    for (final r in investing)
                      SearchInvestingRow(
                          result: r, onTap: () => _openInvesting(r)),
                  ],
                ),
        ),
    ];
    if (blocks.isEmpty) {
      return [SearchEmptyState(text: l10n.sendPickMarketNoResults)];
    }
    return blocks;
  }

  Widget _block(String header, Widget rows) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SearchBlockHeader(text: header), rows],
      );

  Widget _skeleton(String key) => SkeletonRowList(
        key: ValueKey(key),
        count: 3,
        padding: EdgeInsets.zero,
        rowPadding: EdgeInsets.symmetric(vertical: 8.h),
      );
}
