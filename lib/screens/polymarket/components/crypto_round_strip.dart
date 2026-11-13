// lib/screens/polymarket/components/crypto_round_strip.dart
//
// The window strip on the live crypto round card (crypto_round_strip.dart
// in services for the rules), between the chart and the one pair of Up
// and Down buttons: the last rounds of the asset as the card's result dots
// ([PastRoundDots]), then the round in play, the next and the one after as
// the app's compact pills ([KutePill]), each named by its start alone, the
// round in play with a live dot: "● 7:15", "7:20", "7:25" (polymarket.com's
// own round row; founder, 12 November 2026).
//
// ONE ROW, NOTHING CUT (founder, 12 November 2026, the strip running off
// the card's right edge at "10:25 · No…": "text is cut here"). The pills
// are EQUAL and share the card's width after the dots; each is a proper
// pill: the picked one wears the pill's selected chrome, the others its
// quiet fill ([KutePill.restingFill]). A round without real prices is the
// same pill, dimmed, with no words added to it: picked (or where the roll
// lands), the card says "No prices yet" on the line over its buttons. The
// round in play past its cutoff is dimmed and takes no tap. The row never
// scrolls and never ellipsizes: where the three pills and the dots do not
// fit (a narrow phone, large text), the dots go first, and pills still too
// wide shrink TOGETHER, as one row, never one alone.
//
// A round the person holds a side of carries a small dot at its top right.
// Nothing here is a button that buys: the one pair of Up and Down pills
// sits under the strip, on the card (founder, 8 November 2026: "the 5
// minutes ones seem to have many buttons up and down, does not look good").

import 'dart:math' as math;

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
import 'package:kute/services/polymarket/crypto_round_strip.dart';
import 'package:kute/theme/app_theme.dart';

class CryptoRoundStrip extends StatelessWidget {
  const CryptoRoundStrip({
    super.key,
    required this.rounds,
    required this.selectedStart,
    required this.onPick,
  });

  /// The strip, oldest first ([polyRoundStrip]).
  final List<PolyStripRound> rounds;

  /// The start (UTC seconds) of the round the buttons bet on.
  final int selectedStart;

  /// A tap on a round that can be picked: any round ahead (without prices
  /// the card says so), the round in play until its cutoff.
  final void Function(PolyStripRound round) onPick;

  /// The key of a round's pill.
  static Key pillKey(int start) => ValueKey('crypto-round-pill-$start');

  /// The pills' size.
  static const KutePillSize _size = KutePillSize.compact;

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
    // Each round by its start alone; the round in play with a live dot.
    String labelOf(PolyStripRound r) => r.slot == PolyRoundSlot.live
        ? '● ${clock(r.startTime)}'
        : clock(r.startTime);
    // A pill's own height (its padding, its border, one line of its label
    // at the person's text size) and the row's: the pill and a little air,
    // never less than the strip always was.
    final isLight = Theme.of(context).brightness == Brightness.light;
    final chipHeight = 2 * _size.vPad.h +
        2 * (isLight ? 1.0 : 0.5) +
        MediaQuery.textScalerOf(context).scale(_size.font.sp);
    final height = math.max(_size.height + 4.0, chipHeight + 4);
    // The pills that are not the picked one sit as quiet wells in the
    // card, a step under its surface in either theme, so the picked pill's
    // own chrome (the card's surface, its hairline) stands raised among
    // them, as it does on the page's pill strip.
    final restingFill = context.isDark ? c.background : c.surfaceLight;

    Widget pill(PolyStripRound r) {
      final label = labelOf(r);
      final selected = r.start == selectedStart;
      Widget chip = KutePill(
        key: pillKey(r.start),
        label: label,
        // No words added to a round without prices (see the file header);
        // a screen reader still hears why it takes no pick.
        semanticLabel:
            r.selectable ? null : '$label, ${l10n.predictRoundNoPricesYet}',
        selected: selected,
        fillWidth: true,
        restingFill: restingFill,
        size: _size,
        onTap: () {
          if (selected) return;
          if (r.slot == PolyRoundSlot.live && !r.selectable) return;
          HapticFeedback.selectionClick();
          onPick(r);
        },
      );
      if (!r.selectable) {
        // Dimmed, its time still easy to read.
        chip = Opacity(
          opacity: 0.65,
          child: ExcludeSemantics(
            excluding: false,
            child: Semantics(enabled: false, child: chip),
          ),
        );
      }
      if (!r.held) return chip;
      // The person holds a side of this round: a small dot at the pill's
      // top right, in the accent, as the dock marks what is open. The pill
      // sits centred in the row, so the dot is set down to its visible top
      // edge.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          Positioned(
            top: (height - chipHeight) / 2 - 3,
            right: -1,
            child: Container(
              key: ValueKey('crypto-round-held-${r.start}'),
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
      key: const ValueKey('crypto-round-strip'),
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final gap = 6.w;
          // Every pill as wide as the widest needs for all of its words on
          // one line, measured picked (the bolder weight), so a pick never
          // moves the row.
          var each = 44.0;
          for (final r in ahead) {
            each = math.max(
                each,
                KutePill.naturalWidth(context,
                        item: KutePillItem(label: labelOf(r)),
                        selected: true,
                        size: _size) ??
                    each);
          }
          final n = ahead.length;
          final pillsNeed = n == 0 ? 0.0 : each * n + gap * (n - 1);
          final dotsGap = 10.w;
          final dotsWidth =
              past.isEmpty ? 0.0 : PastRoundDots.widthOf(past.length) + dotsGap;
          // The dots go first where the row is too narrow for both.
          final showDots =
              past.isNotEmpty && pillsNeed + dotsWidth <= box.maxWidth;
          final room = box.maxWidth - (showDots ? dotsWidth : 0);
          final pills = Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: pill(ahead[i])),
              ],
            ],
          );
          return Row(
            children: [
              if (showDots) ...[
                PastRoundDots(results: [
                  for (final r in past) CryptoWindowResult(r.start, r.result),
                ]),
                SizedBox(width: dotsGap),
              ],
              Expanded(
                child: pillsNeed <= room
                    ? pills
                    // Still too wide: the three shrink together, as one
                    // row, each whole.
                    : FittedBox(
                        key: const ValueKey('crypto-round-strip-fitted'),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                            width: pillsNeed, height: height, child: pills),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
