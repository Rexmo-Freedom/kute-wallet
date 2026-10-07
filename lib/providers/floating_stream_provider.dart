import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/polymarket/livestream_source.dart';

/// The stream currently handed to the floating mini player. While active,
/// the player is rendered at the app root (above every route, the bet slip
/// included) so it keeps playing as the person navigates and places bets.
class FloatingStream {
  final LivestreamSource? source;

  /// Market title, shown in the player's strip.
  final String title;

  /// Slug of the market the stream belongs to, so that market's sheet can
  /// take the stream back when the person returns to it.
  final String? eventSlug;

  /// True when the market sheet handed the stream over for the bet slip
  /// (and takes it back when the slip closes); false for a pop-out the
  /// person asked for.
  final bool forBetSlip;

  const FloatingStream({
    this.source,
    this.title = '',
    this.eventSlug,
    this.forBetSlip = false,
  });

  bool get isActive => source != null;

  static const FloatingStream none = FloatingStream();
}

final floatingStreamProvider =
    NotifierProvider<FloatingStreamController, FloatingStream>(
  FloatingStreamController.new,
);

class FloatingStreamController extends Notifier<FloatingStream> {
  @override
  FloatingStream build() => FloatingStream.none;

  void show({
    required LivestreamSource source,
    String title = '',
    String? eventSlug,
    bool forBetSlip = false,
  }) {
    state = FloatingStream(
      source: source,
      title: title,
      eventSlug: eventSlug,
      forBetSlip: forBetSlip,
    );
  }

  void hide() => state = FloatingStream.none;
}
