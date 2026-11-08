// lib/screens/polymarket/components/instant_round_strip.dart
//
// The window strip on the Instant card (instant_strip.dart for the
// rules): the last rounds of the asset as the card's result dots
// ([PastRoundDots]), then the round in play, the next and the one after as
// the app's compact pills ([KutePill]): "Now · 1:49", "Next · 7:20",
// "7:25". The picked one wears the pill's selected chrome; a round without
// real prices reads "7:25 · No prices yet", dimmed, and takes no tap; the
// round in play without Gamma's event reads its start the same way ("7:20
// · No prices yet"), never "Now · 0:00:00". A
// round the person holds a side of carries a small dot at its top right.
// Nothing here is a button that buys: the one pair of Up and Down pills
// sits under the strip, on the card (founder, 8 November 2026: "the 5
// minutes ones seem to have many buttons up and down, does not look good").
// The row scrolls sideways where a narrow phone cannot hold it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/crypto_round_card.dart'
    show PastRoundDots;
import 'package:kute/screens/polymarket/components/round_window_label.dart'
    show polyRoundClock;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart'
    show CryptoWindowResult;
import 'package:kute/services/polymarket/instant_strip.dart';
import 'package:kute/theme/app_theme.dart';

class InstantRoundStrip extends StatelessWidget {
  const InstantRoundStrip({
    super.key,
    required this.rounds,
    required this.selectedStart,
    required this.countdown,
    required this.onPick,
  });

  /// The strip, oldest first ([polyInstantStrip]).
  final List<PolyStripRound> rounds;

  /// The start (UTC seconds) of the round the buttons bet on.
  final int selectedStart;

  /// The round in play's time left, as the card's countdown writes it;
  /// null while it is not known (no event).
  final String? countdown;

  /// A tap on a round that can be picked.
  final void Function(PolyStripRound round) onPick;

  /// The key of a round's pill.
  static Key pillKey(int start) => ValueKey('instant-round-$start');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    String clock(DateTime t) =>
        polyRoundClock(t, locale: l10n.localeName, use24h: use24h);
    final past = [
      for (final r in rounds)
        if (r.slot == PolyRoundSlot.past) r,
    ];
    final ahead = [
      for (final r in rounds)
        if (r.slot != PolyRoundSlot.past) r,
    ];
    Widget pill(PolyStripRound r) {
      final label = switch (r.slot) {
        PolyRoundSlot.live when countdown != null =>
          l10n.predictRoundNow(countdown!),
        PolyRoundSlot.next => l10n.predictNextWindow(clock(r.startTime)),
        _ => clock(r.startTime),
      };
      final selected = r.start == selectedStart;
      Widget chip = KutePill(
        key: pillKey(r.start),
        label: label,
        detail: r.selectable ? null : l10n.predictRoundNoPricesYet,
        selected: selected,
        size: KutePillSize.compact,
        onTap: () {
          if (!r.selectable || selected) return;
          HapticFeedback.selectionClick();
          onPick(r);
        },
      );
      if (!r.selectable) {
        chip = Opacity(
          opacity: 0.55,
          child: ExcludeSemantics(
            excluding: false,
            child: Semantics(enabled: false, child: chip),
          ),
        );
      }
      if (!r.held) return chip;
      // The person holds a side of this round: a small dot at the pill's
      // top right, in the accent, as the dock marks what is open. The pill
      // sits centred in its 44 touch box, so the dot is set down to its
      // visible top edge.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          Positioned(
            top: (44 - KutePillSize.compact.height) / 2 - 3,
            right: -1,
            child: Container(
              key: ValueKey('instant-round-held-${r.start}'),
              width: 8.sp,
              height: 8.sp,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      key: const ValueKey('instant-round-strip'),
      height: KutePillSize.compact.height + 4,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            if (past.isNotEmpty) ...[
              PastRoundDots(results: [
                for (final r in past) CryptoWindowResult(r.start, r.result),
              ]),
              SizedBox(width: 10.w),
            ],
            for (var i = 0; i < ahead.length; i++) ...[
              if (i > 0) SizedBox(width: 6.w),
              pill(ahead[i]),
            ],
          ],
        ),
      ),
    );
  }
}
