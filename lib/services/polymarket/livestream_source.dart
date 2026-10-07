// lib/services/polymarket/livestream_source.dart
//
// A market's live broadcast, parsed from Gamma's `resolutionSource` (the
// only place Polymarket puts it), and the embed rules of each host.
//
// Hosts and their embed rules:
//   * Twitch  — `player.twitch.tv/?channel=…&parent=<embed domain>`; the
//     `parent` must be the domain of the page that embeds it (we load the
//     page with base URL https://kute.app and pass parent=kute.app). The
//     player must be at least 400x300 CSS pixels, and on mobile playback
//     starts from a tap on the player.
//   * YouTube — `youtube.com/embed/<video id>` inside a page loaded with the
//     kute.app base URL, so the request's Referer names the client. Nothing
//     may be drawn over the player; the viewport must be at least 200x200
//     (480x270 recommended).
//   * Kick    — `player.kick.com/<channel>`.
//
// Embeds are always the host's own player in an iframe, never the full
// watch page.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Embedding host paired with the Twitch `parent` param, and the base URL
/// every embed page is loaded with (it becomes the iframe's Referer).
const String kLivestreamEmbedHost = 'kute.app';
const String kLivestreamEmbedBaseUrl = 'https://$kLivestreamEmbedHost';

/// Twitch's minimum player size, in CSS pixels.
const double kTwitchMinPlayerWidth = 400;
const double kTwitchMinPlayerHeight = 300;

/// YouTube's minimum player viewport, in CSS pixels.
const double kYouTubeMinPlayerSide = 200;

enum LivestreamHost { twitch, youtube, kick }

extension LivestreamHostX on LivestreamHost {
  /// Analytics value and display name key.
  String get key => switch (this) {
        LivestreamHost.twitch => 'twitch',
        LivestreamHost.youtube => 'youtube',
        LivestreamHost.kick => 'kick',
      };

  String get displayName => switch (this) {
        LivestreamHost.twitch => 'Twitch',
        LivestreamHost.youtube => 'YouTube',
        LivestreamHost.kick => 'Kick',
      };
}

/// One embeddable broadcast.
@immutable
class LivestreamSource {
  final LivestreamHost host;

  /// Twitch / Kick channel name, or the YouTube video id. For a YouTube
  /// channel's live stream ([youtubeChannelLive]) it is the channel id.
  final String id;

  /// A YouTube `/channel/<UC…>/live` link: embedded as the channel's
  /// current live stream rather than a fixed video.
  final bool youtubeChannelLive;

  const LivestreamSource._(this.host, this.id,
      {this.youtubeChannelLive = false});

  static final _twitch =
      RegExp(r'twitch\.tv/([A-Za-z0-9_]{2,40})', caseSensitive: false);
  static final _kick = RegExp(
      r'(?:^|[/.])kick\.com/([A-Za-z0-9_\-]{2,40})',
      caseSensitive: false);
  static final _ytId = RegExp(r'^[A-Za-z0-9_\-]{11}$');
  static final _ytChannel =
      RegExp(r'youtube\.com/channel/(UC[A-Za-z0-9_\-]{22})', caseSensitive: false);

  /// Path segments that are Twitch / Kick pages, not channels.
  static const _reserved = {
    'videos', 'directory', 'p', 'search', 'settings', 'downloads',
    'jobs', 'turbo', 'subscriptions', 'inventory', 'wallet', 'embed',
    'categories', 'following', 'browse',
  };

  /// Parses [url] (a market's `resolutionSource`). Null for anything that
  /// is not an embeddable Twitch, YouTube or Kick broadcast — news pages,
  /// score sites, a YouTube @handle with no video.
  static LivestreamSource? parse(String? url) {
    if (url == null) return null;
    final s = url.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();

    if (lower.contains('twitch.tv/')) {
      // player.twitch.tv/?channel=x
      final uri = Uri.tryParse(s);
      final q = uri?.queryParameters['channel'];
      if (q != null && q.isNotEmpty) {
        return LivestreamSource._(LivestreamHost.twitch, q.toLowerCase());
      }
      final m = _twitch.firstMatch(s);
      final ch = m?.group(1);
      if (ch == null || _reserved.contains(ch.toLowerCase())) return null;
      return LivestreamSource._(LivestreamHost.twitch, ch.toLowerCase());
    }

    if (lower.contains('kick.com/')) {
      final m = _kick.firstMatch(s);
      final ch = m?.group(1);
      if (ch == null || _reserved.contains(ch.toLowerCase())) return null;
      return LivestreamSource._(LivestreamHost.kick, ch.toLowerCase());
    }

    if (lower.contains('youtube.com/') || lower.contains('youtu.be/')) {
      final uri = Uri.tryParse(s);
      if (uri == null) return null;
      final v = uri.queryParameters['v'];
      if (v != null && _ytId.hasMatch(v)) {
        return LivestreamSource._(LivestreamHost.youtube, v);
      }
      final segs = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (uri.host.toLowerCase().endsWith('youtu.be') && segs.isNotEmpty) {
        return _ytId.hasMatch(segs.first)
            ? LivestreamSource._(LivestreamHost.youtube, segs.first)
            : null;
      }
      if (segs.length >= 2 &&
          const {'live', 'embed', 'shorts', 'v'}.contains(segs.first) &&
          _ytId.hasMatch(segs[1])) {
        return LivestreamSource._(LivestreamHost.youtube, segs[1]);
      }
      final ch = _ytChannel.firstMatch(s)?.group(1);
      if (ch != null) {
        return LivestreamSource._(LivestreamHost.youtube, ch,
            youtubeChannelLive: true);
      }
      return null;
    }
    return null;
  }

  /// A stable key for "is this the same stream" checks.
  String get key => '${host.key}:$id';

  /// Width / height of the player box for [width] logical pixels of room,
  /// meeting the host's minimum. Twitch is 4:3 and is laid out on a page
  /// at least [kTwitchMinPlayerWidth] CSS pixels wide (see [embedHtml]), so
  /// a 4:3 box always gives the player at least 400x300 CSS pixels.
  /// YouTube and Kick are 16:9, never under 200 high (letterboxed).
  double playerHeightFor(double width) => switch (host) {
        LivestreamHost.twitch => width * 3 / 4,
        LivestreamHost.youtube || LivestreamHost.kick =>
          (width * 9 / 16).clamp(kYouTubeMinPlayerSide, double.infinity),
      };

  /// Smallest box width this host's player may be shown at. Twitch fits
  /// any width through the page's 400 CSS pixel layout viewport.
  double get minBoxWidth => switch (host) {
        LivestreamHost.twitch => 0,
        LivestreamHost.youtube || LivestreamHost.kick => kYouTubeMinPlayerSide,
      };

  /// The embed page for a [boxWidth]-wide player, loaded with base URL
  /// [kLivestreamEmbedBaseUrl]. Only the host's player iframe, full size;
  /// nothing over it.
  String embedHtml({double boxWidth = 0}) {
    final String src;
    switch (host) {
      case LivestreamHost.twitch:
        src = 'https://player.twitch.tv/?channel=${Uri.encodeComponent(id)}'
            '&parent=$kLivestreamEmbedHost&autoplay=true&muted=false'
            '&playsinline=true';
      case LivestreamHost.youtube:
        src = youtubeChannelLive
            ? 'https://www.youtube.com/embed/live_stream'
                '?channel=${Uri.encodeComponent(id)}&playsinline=1'
                '&autoplay=1&origin=$kLivestreamEmbedBaseUrl'
            : 'https://www.youtube.com/embed/${Uri.encodeComponent(id)}'
                '?playsinline=1&autoplay=1&origin=$kLivestreamEmbedBaseUrl';
      case LivestreamHost.kick:
        src = 'https://player.kick.com/${Uri.encodeComponent(id)}'
            '?autoplay=true&muted=false';
    }
    // Twitch measures its player in CSS pixels: a box narrower than 400
    // logical pixels lays the page out 400 CSS pixels wide and lets the
    // web view scale it to fit, so the player is never under 400x300.
    final viewport = host == LivestreamHost.twitch &&
            boxWidth > 0 &&
            boxWidth < kTwitchMinPlayerWidth
        ? 'width=${kTwitchMinPlayerWidth.toInt()}'
        : 'width=device-width, initial-scale=1';
    return '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="$viewport">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{border:0;display:block;width:100%;height:100%}</style>
</head>
<body>
<iframe src="$src" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"
  allow="autoplay; encrypted-media; fullscreen; picture-in-picture"></iframe>
</body>
</html>''';
  }
}

/// A web view controller for a livestream player: inline playback on
/// iPhone (WebKit otherwise jumps to fullscreen), playback started by a
/// tap on the player, and the page's viewport honoured on Android so the
/// Twitch page keeps its 400 CSS pixel width.
WebViewController buildLivestreamWebViewController({
  VoidCallback? onPageFinished,
}) {
  PlatformWebViewControllerCreationParams params =
      const PlatformWebViewControllerCreationParams();
  if (WebViewPlatform.instance is WebKitWebViewPlatform) {
    params = WebKitWebViewControllerCreationParams(
      allowsInlineMediaPlayback: true,
    );
  }
  final controller = WebViewController.fromPlatformCreationParams(params)
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) => onPageFinished?.call(),
    ));
  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    platform.setMediaPlaybackRequiresUserGesture(true);
    platform.setUseWideViewPort(true);
  }
  return controller;
}

/// Loads [source]'s embed page for a [boxWidth]-wide player.
Future<void> loadLivestream(
    WebViewController controller, LivestreamSource source,
    {double boxWidth = 0}) {
  return controller.loadHtmlString(
    source.embedHtml(boxWidth: boxWidth),
    baseUrl: kLivestreamEmbedBaseUrl,
  );
}
