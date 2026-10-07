// lib/screens/shared/category_pill_strip.dart
//
// A side-scrolling strip of squared category chips (user decision: no
// "Categories" section header above it, the pills are self-explanatory
// and sit directly under each pool screen's balance header). Labels
// stream from the same
// source that builds the sections (Polymarket tags / HL browse tabs) so
// the strip and the feed can never disagree. Chips are links, not
// filters: no selected state, no content swap, just scroll. They are
// the shared KutePill (the Home Activity/Balance/Price chip: squared
// corners, white/surface ground, hairline border) so every pill row in
// the app reads the same (user decision). The tap handler owns
// the scroll mechanics (lazy-mount bump + step-scroll to the section's
// GlobalKey) because those live with each screen's controller;
// revealSectionStart below is the shared landing math.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';

/// Scrolls so the section widget behind [ctx] lands at the TOP of the
/// viewport (start of the category, user decision), pushed down by
/// [clearance] so it clears the floating top nav bar instead of hiding
/// under it — plain ensureVisible aligns to the viewport edge, which the
/// nav overlays, making the jump look like it landed mid-section.
Future<void> revealSectionStart(
  BuildContext ctx,
  ScrollController controller, {
  required double clearance,
}) async {
  double? target() {
    if (!ctx.mounted || !controller.hasClients) return null;
    final ro = ctx.findRenderObject();
    if (ro == null || !ro.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return null;
    return (viewport.getOffsetToReveal(ro, 0.0).offset - clearance)
        .clamp(0.0, controller.position.maxScrollExtent);
  }

  final first = target();
  if (first == null) return;
  await controller.animateTo(
    first,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
  // The sections ABOVE the target keep growing for a moment after the
  // jump (lazy mounts + each section's market fetch landing), pushing
  // the header back down toward the bottom of the screen. Re-pin it for
  // a short settling window so it stays at the top where the tap put
  // it; bail the instant the user scrolls themselves.
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!ctx.mounted || !controller.hasClients) return;
    if (controller.position.isScrollingNotifier.value) return;
    final t = target();
    if (t == null) return;
    if ((controller.offset - t).abs() > 8.0) controller.jumpTo(t);
  }
}

class CategoryPillStrip extends StatelessWidget {
  final List<String> labels;

  /// Accepted and ignored: the pills are label only now. Callers still
  /// pass their glyph lists; nothing renders them.
  final List<IconData?>? icons;
  final void Function(int index) onTap;

  const CategoryPillStrip({
    super.key,
    required this.labels,
    required this.onTap,
    this.icons,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.length <= 1) return const SizedBox.shrink();
    // The pills are the Home Activity/Balance/Price row (user decision:
    // one chip design everywhere). No selection: every pill is a link,
    // so each wears the card chrome and the row side-scrolls.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 12.h),
        KutePillTabs(
          horizontalPadding: 16,
          items: [
            for (int i = 0; i < labels.length; i++)
              // Label only. The glyphs added nothing a category name did
              // not already say, and they made a row of short names look
              // busier than the words deserved (user decision).
              KutePillItem(label: labels[i]),
          ],
          onTap: onTap,
        ),
      ],
    );
  }
}
