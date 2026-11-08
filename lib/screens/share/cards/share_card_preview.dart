// lib/screens/share/cards/share_card_preview.dart
//
// SHARING ALWAYS SHOWS THE CARD FIRST (founder, 1 November 2026: never
// straight to the OS sheet without the card). The pieces every share
// entry point uses, in the brag preview's layout (brag_preview_sheet
// .dart):
//
//   * [ShareCardPreviewBox]: the card (share_cards.dart) scaled to fit the
//     sheet, exactly the pixels that will be sent, in a RepaintBoundary;
//   * [shareCardImage]: captures that boundary at 1080 × 1350 (toImage →
//     PNG) and hands the OS share sheet the PNG with the message: the
//     card's headline, then the entry point's own text and link
//     (shareCardMessage, share_card_copy.dart; the edgy line is on the
//     card, picked by the sheet's seed once on open);
//   * [showShareCardPreviewSheet]: a sheet with the box and the bar as
//     the primary button, "Share" (a pending link's Share again).
//
// The market share sheet (share_market_sheet.dart) and Send to anyone's
// last step (send_to_anyone_sheet.dart) put the same box in their own
// sheets, the bar "Share" too.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardMessage;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart'
    show ShareCardWatch;
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

/// The test seams of every card share.
abstract final class ShareCardShare {
  /// What Share hands the OS (the PNG and the text); resolves to the
  /// result's name. Null opens the share sheet.
  @visibleForTesting
  static Future<String> Function(XFile image, String text)? debugSharer;

  /// The card's edgy line seed (null: random on open).
  @visibleForTesting
  static int? debugLineSeed;

  /// A seed for a sheet opening now.
  static int seed() => debugLineSeed ?? math.Random().nextInt(1 << 16);
}

/// Captures [boundary] as the card's PNG and opens the OS share sheet with
/// it and [text]. Resolves to the result's name (`success`, `dismissed`,
/// `unavailable`), or `error` when the capture or the share failed.
Future<String> shareCardImage(
  BuildContext context,
  GlobalKey boundary, {
  required String text,
  required String name,
}) async {
  final render =
      boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (render == null) return 'error';
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? (box.localToGlobal(Offset.zero) & box.size)
      : (Offset.zero & const Size(1, 1));
  try {
    final image = await render.toImage(pixelRatio: kShareCardPixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return 'error';
    final file = XFile.fromData(bytes.buffer.asUint8List(),
        mimeType: 'image/png', name: 'kute-$name.png');
    final debug = ShareCardShare.debugSharer;
    if (debug != null) return await debug(file, text);
    final r = await SharePlus.instance.share(
        ShareParams(files: [file], text: text, sharePositionOrigin: origin));
    return r.status.name;
  } catch (_) {
    return 'error';
  }
}

/// The card scaled to fit, its pixels in [boundaryKey]'s RepaintBoundary.
/// [heightFraction] caps its height as a share of the screen's.
class ShareCardPreviewBox extends StatefulWidget {
  const ShareCardPreviewBox({
    super.key,
    required this.data,
    required this.boundaryKey,
    this.heightFraction = 0.52,
    this.widthFraction = 1,
    this.lineSeed = 0,
  });

  final ShareCardData data;
  final GlobalKey boundaryKey;

  /// The edgy line's pick (ShareCard.lineSeed).
  final int lineSeed;
  final double heightFraction;

  /// The share of the sheet's width it may take (the naming step's live
  /// card is smaller).
  final double widthFraction;

  @override
  State<ShareCardPreviewBox> createState() => _ShareCardPreviewBoxState();
}

class _ShareCardPreviewBoxState extends State<ShareCardPreviewBox> {
  @override
  void initState() {
    super.initState();
    if (ShareCardSal.peek() == null) {
      unawaited(ShareCardSal.load().then((_) {
        if (mounted) setState(() {});
      }));
    }
    // A card with a Sal of its own (a level's): that still too.
    final data = widget.data;
    if (data is GoalCardData && ShareCardSal.still(data.still) == null) {
      unawaited(ShareCardSal.loadStill(data.still).then((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final usable = size.height - MediaQuery.viewInsetsOf(context).bottom;
    final width = math.max(
        120.0,
        math.min(
            (size.width - 40) * widget.widthFraction,
            usable *
                widget.heightFraction *
                kShareCardSize.width /
                kShareCardSize.height));
    return Center(
      child: Container(
        key: const ValueKey('share-card-preview'),
        width: width,
        height: width * kShareCardSize.height / kShareCardSize.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
              kShareCardRadius * width / kShareCardSize.width),
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
          borderRadius: BorderRadius.circular(
              kShareCardRadius * width / kShareCardSize.width),
          child: FittedBox(
            child: RepaintBoundary(
              key: widget.boundaryKey,
              child: ShareCard(
                  data: widget.data,
                  mark: ShareCardSal.peek(),
                  lineSeed: widget.lineSeed),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the preview sheet: [title] over the card [build] makes (live,
/// from the providers), the bar "Share" sending the PNG with [text];
/// [onShared] gets the result's name.
Future<void> showShareCardPreviewSheet(
  BuildContext context, {
  required String title,
  required ShareCardData Function(ShareCardWatch watch) build,
  required String Function(BuildContext context) text,
  required String shareLabel,
  void Function(String result)? onShared,
  String routeName = 'share_card_preview',
  String source = 'share_card',
}) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: RouteSettings(name: routeName),
      builder: (_) => ShareCardPreviewSheet(
        title: title,
        build: build,
        text: text,
        shareLabel: shareLabel,
        onShared: onShared,
        source: source,
      ),
    );

class ShareCardPreviewSheet extends ConsumerStatefulWidget {
  const ShareCardPreviewSheet({
    super.key,
    required this.title,
    required this.build,
    required this.text,
    required this.shareLabel,
    this.onShared,
    this.source = 'share_card',
  });

  final String title;
  final ShareCardData Function(ShareCardWatch watch) build;
  final String Function(BuildContext context) text;
  final String shareLabel;
  final void Function(String result)? onShared;
  final String source;

  @override
  ConsumerState<ShareCardPreviewSheet> createState() =>
      _ShareCardPreviewSheetState();
}

class _ShareCardPreviewSheetState extends ConsumerState<ShareCardPreviewSheet> {
  final GlobalKey _boundary = GlobalKey();
  final int _seed = ShareCardShare.seed();
  bool _busy = false;

  Future<void> _share(ShareCardData data) async {
    if (_busy) return;
    setState(() => _busy = true);
    final text = shareCardMessage(context.l10n, data, widget.text(context));
    final result =
        await shareCardImage(context, _boundary, text: text, name: data.kind);
    widget.onShared?.call(result);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.build(<T>(p) => ref.watch(p));
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
              title: widget.title, icon: Icons.ios_share_rounded),
          ShareCardPreviewBox(
              data: data, boundaryKey: _boundary, lineSeed: _seed),
          // THE BAR IS THE BUTTON (kute_bar_context.dart): Share.
          KuteBarContextScope(
            barContext: KuteBarContext.primary(
              label: widget.shareLabel,
              onPrimary: () => unawaited(_share(data)),
              busy: _busy,
              // Never off: busy while the image renders.
              disabledLabel: null,
              source: widget.source,
            ),
            child: SizedBox(height: (kuteBarScrollClearance + 24).h),
          ),
        ],
      ),
    );
  }
}
