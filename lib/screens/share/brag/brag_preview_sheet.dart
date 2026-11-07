// lib/screens/share/brag/brag_preview_sheet.dart
//
// THE BRAG PREVIEW (founder, 1 November 2026). A sheet with the card
// (brag_card.dart) scaled to fit, exactly the pixels that will be sent,
// always with the real amounts (founder: "don't even give the option"),
// and the bar as the primary button, "Share": the card captured
// from its RepaintBoundary at 1080 × 1350 (toImage → PNG), handed to the
// OS share sheet with "{title} on Kute {link}", the sharer's referral code
// on the link as `?ref=CODE` (share_market_sheet.dart). The edgy line is
// on the card (brag_lines.dart, picked once when the sheet opens), so the
// message does not repeat it.
//
// Two doors:
//   * [showBragPreviewSheet] with the data a position page built
//     (brag_data.dart: bragHlPosition, bragPolyPosition), from its header
//     button and its Sal sheet row (kute_share_actions.dart);
//   * [showBragPortfolioPreviewSheet] from the Portfolio screen's bar on
//     its Portfolio section ("Share portfolio"): the card follows the live
//     providers while the sheet is up (bragPortfolio);
//   * [showBragPnlPreviewSheet] from the same bar on P&L Charts ("Share
//     P&L"; founder, 2 November 2026: the two sections share different
//     cards): the P&L card (pnl_share_card.dart) for the range picked and
//     the venue picked when the bar was tapped, live as well (bragPnl).
//
// A won prediction's card (brag_data.dart: bragWonPosition,
// bragWonPrediction) opens through [showBragPreviewSheet] as well, from
// the resolved position page and a won payout's receipt (BragWinEntry,
// brag_win_entry.dart); its sheet reads "Show off this win".
//
// Analytics: `brag_shared {kind: position | portfolio, card: position |
// won | portfolio | pnl, range, holdings_count}` once the OS share sheet
// has been opened and not dismissed: `card` says which card went (the P&L
// card is a portfolio kind, a won prediction's a position kind), `range`
// the P&L card's range as its pill reads ("1W", "1M", "3M", "1Y", "ALL"),
// `holdings_count` on the portfolio card how many positions are open in
// all (an integer; the card lists up to three). No market, no name, no
// id, no figure.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart' show BalanceRange;
import 'package:kute/models/portfolio_performance.dart'
    show PortfolioPerformanceVenue;
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/pnl_share_card.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardSal, kShareCardRadius, kShareCardSize;
import 'package:kute/screens/share/share_market_sheet.dart'
    show shareLinkWithReferral;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The preview's route name, for the route observers.
const String kBragPreviewRouteName = 'brag_preview';

/// Opens the preview for [data] (a position page's card).
Future<void> showBragPreviewSheet(BuildContext context, BragData data) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kBragPreviewRouteName),
      builder: (_) => BragPreviewSheet(data: data),
    );

/// Opens the preview for the portfolio card, built live.
Future<void> showBragPortfolioPreviewSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kBragPreviewRouteName),
      builder: (_) => const BragPreviewSheet(),
    );

/// Opens the preview for the P&L card over [range] ([venue] alone when
/// one is picked on the chart), built live.
Future<void> showBragPnlPreviewSheet(BuildContext context,
        {required BalanceRange range, PortfolioPerformanceVenue? venue}) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kBragPreviewRouteName),
      builder: (_) => BragPreviewSheet(pnl: (range: range, venue: venue)),
    );

/// The share text: "{title} on Kute {link}?ref={code}".
String bragShareText(BuildContext context, BragData data) =>
    context.l10n.bragShareText(
        data.title, shareLinkWithReferral(data.link, code: data.referralCode));

class BragPreviewSheet extends ConsumerStatefulWidget {
  /// [data] null: the portfolio card, from the live providers; with
  /// [pnl], the P&L card over its range (and venue).
  const BragPreviewSheet({super.key, this.data, this.pnl});

  final BragData? data;

  /// The P&L card's range and venue (null: both venues).
  final ({BalanceRange range, PortfolioPerformanceVenue? venue})? pnl;

  /// Test seam: what Share hands the OS (the PNG and the text). Null opens
  /// the share sheet.
  @visibleForTesting
  static Future<void> Function(XFile image, String text)? debugSharer;

  /// Test seam: the card's edgy line seed (null: random on open).
  @visibleForTesting
  static int? debugLineSeed;

  @override
  ConsumerState<BragPreviewSheet> createState() => _BragPreviewSheetState();
}

class _BragPreviewSheetState extends ConsumerState<BragPreviewSheet> {
  final GlobalKey _boundary = GlobalKey();

  /// The card's edgy line, picked once on open.
  final int _lineSeed =
      BragPreviewSheet.debugLineSeed ?? math.Random().nextInt(1 << 16);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Sal's face for the footer's mark.
    if (ShareCardSal.peek() == null) {
      unawaited(ShareCardSal.load().then((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  BragData _data(BuildContext context) {
    final pnl = widget.pnl;
    return widget.data ??
        (pnl != null
            ? bragPnl(ref,
                title: context.l10n.bragMyPnl,
                range: pnl.range,
                venue: pnl.venue)
            : bragPortfolio(ref,
                title: context.l10n.bragMyPortfolio, date: _rowDate(context)));
  }

  /// Writes an ISO date found in a market's title in the app's language
  /// ("Oct 25"), as the Portfolio's rows do.
  static String Function(DateTime) _rowDate(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return (d) {
      try {
        return DateFormat.MMMd(locale).format(d);
      } catch (_) {
        // Date symbols not loaded for the locale (a test, an early start).
        return DateFormat.MMMd('en').format(d);
      }
    };
  }

  Future<void> _share(BragData data) async {
    if (_busy) return;
    final boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final text = bragShareText(context, data);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? (box.localToGlobal(Offset.zero) & box.size)
        : (Offset.zero & const Size(1, 1));
    setState(() => _busy = true);
    try {
      final image = await boundary.toImage(pixelRatio: kBragCardPixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final file = XFile.fromData(bytes.buffer.asUint8List(),
          mimeType: 'image/png', name: 'kute-${data.kind.name}.png');
      final debug = BragPreviewSheet.debugSharer;
      var opened = true;
      if (debug != null) {
        await debug(file, text);
      } else {
        final r = await SharePlus.instance.share(ShareParams(
            files: [file], text: text, sharePositionOrigin: origin));
        opened = r.status != ShareResultStatus.dismissed;
      }
      if (opened) {
        TrackingService.track('brag_shared', params: {
          'kind': data.kind.name,
          'card': data is BragPnl
              ? 'pnl'
              : data is BragWin
                  ? 'won'
                  : data.kind.name,
          if (data is BragPnl) 'range': data.range.label,
          if (data is BragPortfolio && data is! BragPnl)
            'holdings_count': math.max(data.openCount, data.top.length),
        });
      }
    } catch (_) {
      // A capture or a share that failed: the sheet stays, Share again.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final data = _data(context);
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 40,
        size.height * 0.52 * kBragCardSize.width / kBragCardSize.height);
    final radius = kShareCardRadius * width / kShareCardSize.width;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: data is BragPnl
                ? l10n.bragPnlBarLabel
                : data is BragWin
                    ? l10n.bragWonAction
                    : data.kind == BragKind.portfolio
                        ? l10n.bragPortfolioAction
                        : l10n.bragPositionAction,
            icon: Icons.ios_share_rounded,
          ),
          Center(
            child: Container(
              key: const ValueKey('brag-preview-card'),
              width: width,
              height: width * kBragCardSize.height / kBragCardSize.width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: c.borderSubtle, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: data is BragPnl
                        ? PnlShareCard(
                            data: data,
                            mark: ShareCardSal.peek(),
                            lineSeed: _lineSeed)
                        : BragCard(
                            data: data,
                            mark: ShareCardSal.peek(),
                            lineSeed: _lineSeed),
                  ),
                ),
              ),
            ),
          ),
          // THE BAR IS THE BUTTON (kute_bar_context.dart): Share is the
          // floating bar's primary action; the sheet keeps clear of it.
          KuteBarContextScope(
            barContext: KuteBarContext.primary(
              label: l10n.share,
              onPrimary: () => unawaited(_share(data)),
              busy: _busy,
              // Never off: busy while the image renders, never waiting on input.
              disabledLabel: null,
              category: SearchCategory.all,
              source: 'brag_preview',
            ),
            child: SizedBox(height: (kuteBarScrollClearance + 24).h),
          ),
        ],
      ),
    );
  }
}
