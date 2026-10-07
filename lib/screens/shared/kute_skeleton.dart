import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:shimmer/shimmer.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Shared skeleton primitives, backed by the `skeletonizer` package.
///
/// Loading states across the app mimic the shape of the content that is
/// about to appear (cards, rows, charts) instead of a centered spinner,
/// exactly like the Home screen does while the Breez SDK connects.
///
/// [KuteSkeleton] opens a `Skeletonizer.zone` with the app's de-facto
/// standard palette (same as Home's original activity/hero skeletons).
/// The shape primitives ([SkeletonBar], [SkeletonCircle]) are
/// skeletonizer `Bone`s — the zone's shimmer paints them; they
/// self-wrap in a zone when used bare so call sites can't render a
/// dead (unshimmered) bone by accident. [SkeletonCard] is real card
/// chrome (surface + hairline border) that the zone deliberately does
/// NOT shade; compose bones inside it. The list/grid/chart widgets are
/// complete, self-shimmering skeletons.
class KuteSkeleton extends StatelessWidget {
  final Widget child;

  const KuteSkeleton({super.key, required this.child});

  /// The app-standard shimmer palette (kept identical to the original
  /// hand-rolled skeletons so the sweep reads the same everywhere).
  static ShimmerEffect effectFor(BuildContext context) {
    final isDark = context.isDark;
    return ShimmerEffect(
      baseColor: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade600 : Colors.grey.shade100,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Skeletonizer.zone(
      effect: effectFor(context),
      child: child,
    );
  }
}

/// Wraps [bone] in a [KuteSkeleton] zone unless one is already above it,
/// so bare usages of the shape primitives still shimmer.
Widget _zoned(BuildContext context, Widget bone) =>
    Skeletonizer.maybeOf(context) == null ? KuteSkeleton(child: bone) : bone;

/// Rounded rectangle placeholder for a line of text or a value.
class SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double? radius;

  const SkeletonBar(this.width, this.height, {super.key, this.radius});

  @override
  Widget build(BuildContext context) {
    return _zoned(
      context,
      Bone(
        width: width,
        height: height,
        borderRadius: BorderRadius.circular(radius ?? 6.r),
      ),
    );
  }
}

/// Circular placeholder for an avatar / coin icon.
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle(this.size, {super.key});

  @override
  Widget build(BuildContext context) {
    return _zoned(context, Bone.circle(size: size));
  }
}

/// Card-shaped shell matching the app's real cards (surface fill,
/// hairline border, [AppRadius.xl] corners). Compose bars/circles
/// inside via [child], or leave empty for a blank card block. This is
/// real chrome, not a bone: the zone leaves it unshaded on purpose so
/// the skeleton card looks like the loaded card's frame.
class SkeletonCard extends StatelessWidget {
  final double? height;
  final double? width;
  final double? radius;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const SkeletonCard({
    super.key,
    this.height,
    this.width,
    this.radius,
    this.padding,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: height,
      width: width ?? double.infinity,
      padding: padding ?? EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius ?? AppRadius.xl),
        border: Border.all(
          color: context.isDark ? c.borderSubtle : c.border,
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

/// Shimmering list of activity-style rows: leading circle, two stacked
/// text bars, trailing value bar. Pixel-identical to Home's activity
/// skeleton at the defaults.
class SkeletonRowList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry? padding;

  /// Per-row padding. Defaults to the Home activity-row inset
  /// (16.w horizontal, 10.h vertical); sheets whose ListTiles sit
  /// closer to the edge can pass a tighter inset.
  final EdgeInsetsGeometry? rowPadding;

  const SkeletonRowList({
    super.key,
    this.count = 3,
    this.padding,
    this.rowPadding,
  });

  @override
  Widget build(BuildContext context) {
    Widget row() => Padding(
          padding: rowPadding ??
              EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Row(
            children: [
              SkeletonCircle(40.w),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(140.w, 14.h),
                    SizedBox(height: 6.h),
                    SkeletonBar(90.w, 11.h),
                  ],
                ),
              ),
              SkeletonBar(64.w, 14.h),
            ],
          ),
        );
    return KuteSkeleton(
      child: Padding(
        padding: padding ?? EdgeInsets.only(top: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < count; i++) row()],
        ),
      ),
    );
  }
}

/// Shimmering stack of card-shaped placeholders separated by 12.h,
/// mimicking a feed of content cards (markets, vaults, events...).
class SkeletonCardList extends StatelessWidget {
  final int count;
  final double height;
  final EdgeInsetsGeometry? padding;

  const SkeletonCardList({
    super.key,
    this.count = 4,
    required this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return KuteSkeleton(
      child: Padding(
        padding: padding ?? EdgeInsets.symmetric(horizontal: 16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) SizedBox(height: 12.h),
              SkeletonCard(
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SkeletonCircle(32.w),
                        SizedBox(width: 10.w),
                        Expanded(child: SkeletonBar(double.infinity, 14.h)),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    SkeletonBar(140.w, 12.h),
                    const Spacer(),
                    Row(
                      children: [
                        SkeletonBar(72.w, 12.h),
                        SizedBox(width: 8.w),
                        SkeletonBar(48.w, 12.h),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmering grid of seed-word chip placeholders, mimicking the
/// mnemonic word grids on the creation/backup screens.
class SkeletonWordGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;
  final double aspectRatio;

  const SkeletonWordGrid({
    super.key,
    this.count = 12,
    this.crossAxisCount = 3,
    this.aspectRatio = 2.4,
  });

  @override
  Widget build(BuildContext context) {
    return KuteSkeleton(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10.w,
          mainAxisSpacing: 10.h,
          childAspectRatio: aspectRatio,
        ),
        itemCount: count,
        itemBuilder: (_, __) =>
            Bone(borderRadius: BorderRadius.circular(10.r)),
      ),
    );
  }
}

/// Shimmering BAR-chart placeholder: bottom-aligned candles of varying
/// height with a small axis row. Use for candlestick/volume charts; for
/// smooth price lines use [SkeletonLineChart] instead.
class SkeletonChart extends StatelessWidget {
  /// Fixed height for the chart block; when null the skeleton fills
  /// the parent's (bounded) height instead.
  final double? height;
  final EdgeInsetsGeometry? padding;

  const SkeletonChart({super.key, this.height, this.padding});

  @override
  Widget build(BuildContext context) {
    // Pseudo-random but stable bar heights so the silhouette reads as
    // a chart without jumping between rebuilds.
    const fractions = [0.45, 0.7, 0.55, 0.85, 0.6, 0.95, 0.5, 0.75, 0.65, 0.9];
    return KuteSkeleton(
      child: Padding(
        padding: padding ?? EdgeInsets.symmetric(horizontal: 16.w),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final f in fractions)
                        SkeletonBar(
                          12.w,
                          constraints.maxHeight * f,
                          radius: 3.r,
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 5; i++) SkeletonBar(30.w, 8.h, radius: 4.r),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmering LINE-chart placeholder: a smooth horizontal price line
/// with an emphasized endpoint, mimicking the loaded line chart. Use
/// this (not [SkeletonChart]) wherever the real content is a line —
/// vertical candle bars read as the wrong chart type there.
class SkeletonLineChart extends StatelessWidget {
  /// Fixed height for the chart block; when null the skeleton fills
  /// the parent's (bounded) height instead.
  final double? height;
  final EdgeInsetsGeometry? padding;

  const SkeletonLineChart({super.key, this.height, this.padding});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    // A wavy path is not a skeletonizer Bone, so this one component
    // shimmers via the shimmer package with the SAME palette.
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade600 : Colors.grey.shade100,
      child: Padding(
        padding: padding ?? EdgeInsets.symmetric(horizontal: 16.w),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SkeletonLinePainter(color: context.colors.surfaceLight),
          ),
        ),
      ),
    );
  }
}

class _SkeletonLinePainter extends CustomPainter {
  final Color color;

  const _SkeletonLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Stable gentle waves around the vertical center: reads as a price
    // line without implying a direction.
    const fractions = [0.55, 0.42, 0.60, 0.48, 0.38, 0.52, 0.44, 0.50];
    final dx = size.width / (fractions.length - 1);
    final path = Path()
      ..moveTo(0, size.height * fractions.first);
    for (var i = 1; i < fractions.length; i++) {
      final x = dx * i;
      final y = size.height * fractions[i];
      final prevX = dx * (i - 1);
      final prevY = size.height * fractions[i - 1];
      final midX = (prevX + x) / 2;
      path.cubicTo(midX, prevY, midX, y, x, y);
    }
    canvas.drawPath(path, stroke);

    // Emphasized endpoint dot, like the live charts' last-price marker.
    canvas.drawCircle(
      Offset(size.width, size.height * fractions.last),
      5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SkeletonLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
