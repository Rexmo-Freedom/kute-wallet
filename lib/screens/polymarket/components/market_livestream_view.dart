// Embeds a market's live broadcast (Twitch / YouTube / Kick) inside the
// market detail sheet. The stream comes from Gamma's `resolutionSource`
// (see `PolymarketEvent.livestream`).
//
// Each host's own player is embedded in an iframe on a tiny page loaded
// with the kute.app base URL (Twitch checks `parent` against it; YouTube
// reads the client from the Referer). The player box meets each host's
// minimum size (`LivestreamSource.playerHeightFor`), and nothing is drawn
// over it: the live label and the mini-player button sit in a strip under
// the video.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/polymarket/livestream_source.dart';
import 'package:kute/theme/app_theme.dart';

class MarketLivestreamView extends StatefulWidget {
  final LivestreamSource source;

  /// Optional "keep watching in the mini player" action. When provided, a
  /// button in the strip under the video hands the stream to the floating
  /// player so it keeps playing as the person navigates and bets.
  final VoidCallback? onPopOut;

  const MarketLivestreamView({
    super.key,
    required this.source,
    this.onPopOut,
  });

  @override
  State<MarketLivestreamView> createState() => _MarketLivestreamViewState();
}

class _MarketLivestreamViewState extends State<MarketLivestreamView> {
  late final WebViewController _controller;
  bool _loading = true;
  double? _loadedWidth;

  @override
  void initState() {
    super.initState();
    _controller = buildLivestreamWebViewController(onPageFinished: () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void didUpdateWidget(covariant MarketLivestreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.key != widget.source.key) _loadedWidth = null;
  }

  @override
  void dispose() {
    // Tear the player down so audio never outlives the view.
    _controller.loadRequest(Uri.parse('about:blank')).catchError((_) {});
    super.dispose();
  }

  /// Loads the embed once the box width is known (the Twitch page is laid
  /// out at 400 CSS pixels when the box is narrower).
  void _ensureLoaded(double width) {
    if (_loadedWidth != null && (_loadedWidth! - width).abs() < 1) return;
    _loadedWidth = width;
    _loading = true;
    loadLivestream(_controller, widget.source, boxWidth: width)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = widget.source.playerHeightFor(width);
      _ensureLoaded(width);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: WebViewWidget(controller: _controller),
              ),
              LivestreamStrip(
                source: widget.source,
                loading: _loading,
                trailing: widget.onPopOut == null
                    ? null
                    : _StripButton(
                        icon: Icons.picture_in_picture_alt_rounded,
                        label: context.l10n.livestreamMiniPlayer,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onPopOut!();
                        },
                      ),
                background: c.surface,
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// The strip under a player: a live dot, "Live on Twitch", a loading
/// indicator while the page loads, and an optional action. Never drawn
/// over the video.
class LivestreamStrip extends StatelessWidget {
  final LivestreamSource source;
  final bool loading;
  final Widget? trailing;
  final Color background;
  final String? title;

  const LivestreamStrip({
    super.key,
    required this.source,
    required this.background,
    this.loading = false,
    this.trailing,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: background,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 7.w,
            height: 7.w,
            decoration: const BoxDecoration(
              color: AppColors.marketDown,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              title ?? context.l10n.livestreamOnHost(source.host.displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (loading) ...[
            LoadingAnimationWidget.staggeredDotsWave(
              color: c.textTertiary,
              size: 18.sp,
            ),
            SizedBox(width: 8.w),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StripButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15.sp, color: c.textPrimary),
              SizedBox(width: 5.w),
              Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
