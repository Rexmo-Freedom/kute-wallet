// lib/screens/share/brag/brag_preview_sheet.dart
//
// THE BRAG PREVIEW (founder, 1 November 2026). A sheet with the card
// (brag_card.dart) scaled to fit, exactly the pixels that will be sent,
// always with the real amounts (founder: "don't even give the option"),
// and the bar as the primary button, "Share": the card captured
// from its RepaintBoundary at 1080 × 1350 (toImage → PNG), handed to the
// OS share sheet with "{title} on Kute {link}", the sharer's referral code
// on the link as `?ref=CODE` (share_market_sheet.dart).
//
// Two doors:
//   * [showBragPreviewSheet] with the data a position page built
//     (brag_data.dart: bragHlPosition, bragPolyPosition), from its header
//     button and its Sal sheet row (kute_share_actions.dart);
//   * [showBragPortfolioPreviewSheet] from the Portfolio screen's bar: the
//     card follows the live providers while the sheet is up
//     (bragPortfolio).
//
// Analytics: `brag_shared {kind: position | portfolio}`
// once the OS share sheet has been opened and not dismissed. No market,
// no id, no figure.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/brag/brag_sal.dart';
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

/// The share text: "{title} on Kute {link}?ref={code}".
String bragShareText(BuildContext context, BragData data) =>
    context.l10n.bragShareText(
        data.title, shareLinkWithReferral(data.link, code: data.referralCode));

class BragPreviewSheet extends ConsumerStatefulWidget {
  /// [data] null: the portfolio card, from the live providers.
  const BragPreviewSheet({super.key, this.data});

  final BragData? data;

  /// Test seam: what Share hands the OS (the PNG and the text). Null opens
  /// the share sheet.
  @visibleForTesting
  static Future<void> Function(XFile image, String text)? debugSharer;

  /// Test seam: Sal's line seed (null: random on open).
  @visibleForTesting
  static int? debugLineSeed;

  @override
  ConsumerState<BragPreviewSheet> createState() => _BragPreviewSheetState();
}

class _BragPreviewSheetState extends ConsumerState<BragPreviewSheet> {
  final GlobalKey _boundary = GlobalKey();

  /// Sal's line, picked once on open so it holds while the figures move.
  final int _lineSeed =
      BragPreviewSheet.debugLineSeed ?? math.Random().nextInt(1 << 16);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Every still, so the card never waits on a change of tone.
    unawaited(
        Future.wait([for (final t in BragTone.values) BragSalStills.load(t)])
            .then((_) {
      if (mounted) setState(() {});
    }));
  }

  BragData _data(BuildContext context) =>
      widget.data ?? bragPortfolio(ref, title: context.l10n.bragMyPortfolio);

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
    final sal = BragSalStills.peek(data.tone);
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 40,
        size.height * 0.52 * kBragCardSize.width / kBragCardSize.height);
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: data.kind == BragKind.portfolio
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
                borderRadius: BorderRadius.circular(20),
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
                borderRadius: BorderRadius.circular(20),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: BragCard(data: data, sal: sal, lineSeed: _lineSeed),
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
