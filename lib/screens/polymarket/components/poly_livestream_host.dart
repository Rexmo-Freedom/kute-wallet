// Watch and bet: a Predictions screen whose market has a watchable
// broadcast (Twitch / YouTube / Kick) offers "Market" and "Livestream" as
// two of the app's pills, plays the stream in place when Livestream is
// picked, and hands it to the floating mini player while another route
// covers the screen (the bet slip, an outcome's own sheet), taking it
// back when the screen is on top again.
//
// The market sheet and the open-position screen both mix this in, so the
// two behave the same. The player is only built while Livestream is
// picked: nothing of the stream loads before that.
//
// Analytics: livestream_opened (stream host, surface, entry source,
// category, whether it is a Mentions market) and livestream_minimized
// (stream host, reason, category). No ids.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/floating_stream_provider.dart';
import 'package:kute/screens/polymarket/components/market_livestream_view.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/livestream_source.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

mixin PolyLivestreamHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The event whose broadcast this screen plays; null while it is not
  /// known (the open-position screen reads it by slug).
  PolymarketEvent? get streamEvent;

  /// Where the screen was opened from (analytics `entry_source`).
  String get streamEntrySource;

  /// The screen, as livestream_opened names it ('market_detail',
  /// 'position').
  String get streamSurface;

  /// Market (chart) vs Livestream pill.
  bool showLivestream = false;

  /// True while the stream plays in the mini player because another route
  /// covers this screen.
  bool streamHandedOff = false;

  /// Set while the bet slip is being opened, for the hand-off's reason.
  bool openingBetSlip = false;

  /// The event has a stream to watch now.
  bool get hasStream => streamEvent?.hasLivestream ?? false;

  /// Livestream is picked and there is a stream.
  bool get watchingStream => hasStream && showLivestream;

  /// Called from build: while another route covers this one the stream
  /// plays on in the mini player, and comes back here when this screen is
  /// on top again. A screen being closed is no longer active: its stream
  /// stops with it.
  void syncStreamHandoff(BuildContext context) {
    final route = ModalRoute.of(context);
    final onTop = route?.isCurrent ?? true;
    final watching = watchingStream && (route?.isActive ?? true);
    final event = streamEvent;
    final source = event?.livestream;
    if (event == null || source == null) return;
    if (watching && !onTop && !streamHandedOff) {
      streamHandedOff = true;
      final reason = openingBetSlip ? 'bet_slip' : 'navigated';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !streamHandedOff) return;
        TrackingService.track('livestream_minimized', params: {
          'stream_host': source.host.key,
          'reason': reason,
          if (event.category.isNotEmpty)
            'category': event.category.toLowerCase(),
        });
        ref.read(floatingStreamProvider.notifier).show(
              source: source,
              title: event.title,
              eventSlug: event.slug,
              forBetSlip: true,
            );
      });
    } else if (onTop && streamHandedOff) {
      streamHandedOff = false;
      openingBetSlip = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        takeStreamFromMiniPlayer();
      });
    }
  }

  /// This screen plays the stream itself: a mini player showing the same
  /// stream (handed over earlier, or popped out from here before) stops,
  /// so it never plays twice.
  void takeStreamFromMiniPlayer() {
    final source = streamEvent?.livestream;
    final floating = ref.read(floatingStreamProvider);
    if (source == null || floating.source?.key != source.key) return;
    ref.read(floatingStreamProvider.notifier).hide();
  }

  /// The player, or — while the stream plays in the mini player — a quiet
  /// stand-in of the same height.
  Widget buildWatchPlayer(AppColorsExtension c) {
    final event = streamEvent!;
    final source = event.livestream!;
    if (streamHandedOff) {
      return LayoutBuilder(builder: (context, constraints) {
        return Container(
          height: source.playerHeightFor(constraints.maxWidth),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_in_picture_alt_rounded,
                  size: 18.sp, color: c.textTertiary),
              SizedBox(width: 8.w),
              Text(
                context.l10n.livestreamInMiniPlayer,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      });
    }
    // Sized to the host's minimum (Twitch 400x300 CSS, YouTube 200x200)
    // with its controls in a strip under the video — nothing over the
    // player.
    return MarketLivestreamView(
      source: source,
      onPopOut: () {
        TrackingService.track('livestream_minimized', params: {
          'stream_host': source.host.key,
          'reason': 'pop_out',
          if (event.category.isNotEmpty)
            'category': event.category.toLowerCase(),
        });
        ref.read(floatingStreamProvider.notifier).show(
              source: source,
              title: event.title,
              eventSlug: event.slug,
            );
        // Close the screen so the user is back in the app with the stream
        // floating; they can navigate and bet while it keeps playing.
        Navigator.of(context).maybePop();
      },
    );
  }

  /// The person started watching this market's stream (host and kind of
  /// market only).
  void trackLivestreamOpened() {
    final event = streamEvent;
    final source = event?.livestream;
    if (event == null || source == null) return;
    TrackingService.track('livestream_opened', params: {
      'stream_host': source.host.key,
      'surface': streamSurface,
      'entry_source': streamEntrySource,
      if (event.category.isNotEmpty) 'category': event.category.toLowerCase(),
      'mentions': event.isMentionMarket,
    });
  }

  /// "Market" and "Livestream" as the app's own pills (the category rows'
  /// pill, selected the same way), left-aligned on the screen's margin.
  /// Only built when the event has a watchable broadcast.
  Widget buildMediaToggle(AppColorsExtension c) {
    void pick(bool live) {
      if (showLivestream == live) return;
      HapticFeedback.selectionClick();
      if (live) {
        trackLivestreamOpened();
        takeStreamFromMiniPlayer();
      }
      setState(() => showLivestream = live);
    }

    return Row(
      children: [
        KutePill(
          label: context.l10n.betMarketCategory,
          selected: !showLivestream,
          onTap: () => pick(false),
        ),
        SizedBox(width: 6.w),
        KutePill(
          label: context.l10n.betLivestream,
          selected: showLivestream,
          onTap: () => pick(true),
        ),
      ],
    );
  }
}
