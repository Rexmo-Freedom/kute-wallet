import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/floating_stream_provider.dart';
import 'package:kute/screens/polymarket/components/market_livestream_view.dart'
    show LivestreamStrip;
import 'package:kute/services/polymarket/livestream_source.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Draggable mini player rendered at the app root (above every route, the
/// bet slip included). Once a stream is handed over via
/// [floatingStreamProvider], it keeps playing here as the person navigates
/// and places bets.
///
/// The player is never smaller than its host allows: it spans the screen
/// width (up to 480) at the host's aspect (Twitch 4:3 on a 400 CSS pixel
/// page, YouTube and Kick 16:9 and at least 200 high). Its controls sit in
/// a strip under the video, never over it; dragging the strip moves it.
/// Where that size cannot fit (a very small or landscape screen) a small
/// "now playing" bar shows instead of a video below the minimum.
///
/// Mounted once in `AppWidget`'s `MaterialApp.builder` Stack.
class FloatingStreamPlayer extends ConsumerStatefulWidget {
  const FloatingStreamPlayer({super.key});

  @override
  ConsumerState<FloatingStreamPlayer> createState() =>
      _FloatingStreamPlayerState();
}

class _FloatingStreamPlayerState extends ConsumerState<FloatingStreamPlayer> {
  WebViewController? _controller;
  String? _loadedKey; // source key + width currently loaded
  Offset? _pos; // top-left of the card; null until first layout
  bool _loading = true;

  static const double _kMargin = 12;
  static const double _kMaxWidth = 480;

  void _ensureLoaded(LivestreamSource source, double width) {
    final key = '${source.key}@${width.round()}';
    if (key == _loadedKey) return;
    _loadedKey = key;
    _loading = true;
    final c = _controller ??= buildLivestreamWebViewController(
      onPageFinished: () {
        if (mounted) setState(() => _loading = false);
      },
    );
    loadLivestream(c, source, boxWidth: width).catchError((_) {});
  }

  void _stop() {
    // Closing must STOP playback — the controller persists across builds,
    // so without this the player keeps playing audio in the background.
    if (_loadedKey != null) {
      _controller?.loadRequest(Uri.parse('about:blank')).catchError((_) {});
      _loadedKey = null;
    }
  }

  void _close(FloatingStream stream) {
    HapticFeedback.selectionClick();
    TrackingService.track('livestream_closed', params: {
      'stream_host': stream.source?.host.key ?? 'unknown',
      'surface': 'mini_player',
    });
    ref.read(floatingStreamProvider.notifier).hide();
  }

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(floatingStreamProvider);
    final source = stream.source;
    if (source == null) {
      _stop();
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final size = media.size;
    final width = (size.width - 2 * _kMargin).clamp(0.0, _kMaxWidth);
    final videoHeight = source.playerHeightFor(width);
    final stripHeight = 40.h;
    final room = size.height - media.padding.vertical - 2 * _kMargin;
    // The bet slip fills the lower part of the screen; a player taller than
    // about half of it would cover the slip, and one under the host's
    // minimum is not allowed — the bar takes over in both cases.
    final fits =
        width >= source.minBoxWidth && videoHeight + stripHeight <= room * 0.55;
    final cardHeight = fits ? videoHeight + stripHeight : stripHeight + 8.h;

    if (!fits) _stop();
    if (fits) _ensureLoaded(source, width);

    // Default position: the top of the screen, clear of the slip below.
    _pos ??= Offset(
      (size.width - width) / 2,
      media.padding.top + _kMargin,
    );
    final pos = Offset(
      _pos!.dx.clamp(_kMargin, size.width - width - _kMargin + 0.01),
      _pos!.dy.clamp(
        media.padding.top + _kMargin,
        size.height - cardHeight - _kMargin,
      ),
    );

    final c = context.colors;
    void drag(DragUpdateDetails d) => setState(() {
          _pos = Offset(pos.dx + d.delta.dx, pos.dy + d.delta.dy);
        });

    final closeButton = Semantics(
      button: true,
      label: context.l10n.close,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _close(stream),
        child: Padding(
          padding: EdgeInsets.all(4.w),
          child: Icon(Icons.close_rounded, size: 18.sp, color: c.textPrimary),
        ),
      ),
    );

    final controller = _controller;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        borderRadius: BorderRadius.circular(14.r),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.r),
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fits)
                  Container(
                    color: Colors.black,
                    width: width,
                    height: videoHeight,
                    child: controller == null
                        ? null
                        : WebViewWidget(controller: controller),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: drag,
                  child: LivestreamStrip(
                    source: source,
                    loading: fits && _loading,
                    background: c.surface,
                    title: fits
                        ? (stream.title.isEmpty ? null : stream.title)
                        : context.l10n.livestreamNowPlaying(
                            stream.title.isEmpty
                                ? source.host.displayName
                                : stream.title),
                    trailing: closeButton,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
