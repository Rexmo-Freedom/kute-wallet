import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/theme/app_theme.dart';

/// A balance figure that is still updating: [child] keeps its dimmed
/// colour and a soft sweep runs across the digits, so it reads as
/// "refreshing" rather than final (founder request, October 2026).
///
/// The sweep is the app's skeleton shimmer ([KuteSkeleton.effectFor]):
/// the same diagonal gradient, stops, timing and bounds, painted over the
/// text itself instead of a grey bar. Its base is the figure's dimmed
/// colour, so between passes nothing changes; its highlight is that colour
/// lifted by the skeleton's own base-to-highlight step, scaled up a little
/// because a glyph is thinner than a bone. Both light and dark lighten, as
/// the skeleton does, and the digits stay readable at the band's peak.
///
/// The child is never replaced, so a [RollingNumberText] underneath keeps
/// its reels and rolls when the fresh figure lands.
///
/// It holds still (dimmed only) under Reduce Motion, while [stale] is
/// false, while the app is not in the foreground, and, through the ticker,
/// whenever [TickerMode] mutes this subtree (a covered route, an offstage
/// tab). When nothing sweeps, no frame is scheduled and no layer is pushed.
class StaleShimmer extends StatefulWidget {
  const StaleShimmer({
    super.key,
    required this.stale,
    required this.child,
    this.color,
  });

  /// Whether the figure is still updating.
  final bool stale;

  /// The figure. Callers still dim it themselves while [stale].
  final Widget child;

  /// The figure's dimmed colour, the sweep's base. Defaults to the
  /// secondary text colour every stale figure uses.
  final Color? color;

  /// How much further than the skeleton's own step the highlight lifts.
  static const double sweepGain = 2.5;

  /// The sweep's highlight for a figure drawn in [base]: [base] lifted by
  /// the skeleton's base-to-highlight step times [sweepGain].
  static Color highlightFor(BuildContext context, Color base) {
    final skeleton = KuteSkeleton.effectFor(context).colors;
    final from = skeleton.first, to = skeleton[1];
    double lift(double b, double s0, double s1) =>
        (b + (s1 - s0) * sweepGain).clamp(0.0, 1.0);
    return Color.from(
      alpha: base.a,
      red: lift(base.r, from.r, to.r),
      green: lift(base.g, from.g, to.g),
      blue: lift(base.b, from.b, to.b),
    );
  }

  @override
  State<StaleShimmer> createState() => _StaleShimmerState();
}

class _StaleShimmerState extends State<StaleShimmer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _controller;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StaleShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stale != widget.stale) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    setState(() => _foreground = foreground);
    _sync();
  }

  bool get _sweeping => _controller?.isAnimating ?? false;

  /// Starts or stops the sweep to match the inputs. Reads the media query,
  /// so it only runs from the dependency, update and lifecycle hooks.
  void _sync() {
    final run = widget.stale && _foreground && !kuteReduceMotion(context);
    if (run == _sweeping) return;
    if (!run) {
      _controller?.stop();
      return;
    }
    final effect = KuteSkeleton.effectFor(context);
    // The skeleton zone's own loop: lowerBound to upperBound per period.
    (_controller ??= AnimationController(
      vsync: this,
      lowerBound: effect.lowerBound,
      upperBound: effect.upperBound,
    ))
        .repeat(period: effect.duration);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    ShimmerEffect? sweep;
    if (widget.stale && controller != null && controller.isAnimating) {
      final skeleton = KuteSkeleton.effectFor(context);
      final base = widget.color ?? context.colors.textSecondary;
      final highlight = StaleShimmer.highlightFor(context, base);
      sweep = ShimmerEffect.raw(
        colors: [base, highlight, base],
        stops: skeleton.stops,
        begin: skeleton.begin,
        end: skeleton.end,
        tileMode: skeleton.tileMode,
      );
    }
    // The boundary keeps each sweep frame's repaint to the figure alone;
    // it is there whether or not the figure is stale, so the child's
    // element (and its rolling reels) survives the change.
    return RepaintBoundary(
      child: _TextSweep(
        effect: sweep,
        progress: sweep == null ? null : controller,
        textDirection: Directionality.maybeOf(context),
        child: widget.child,
      ),
    );
  }
}

/// Paints [child] through [effect]'s gradient at [progress] (source-in, so
/// the gradient takes the glyphs' place and keeps their shape), or plainly,
/// with no layer, while [effect] is null.
class _TextSweep extends SingleChildRenderObjectWidget {
  const _TextSweep({
    required this.effect,
    required this.progress,
    required this.textDirection,
    required super.child,
  });

  final ShimmerEffect? effect;
  final Animation<double>? progress;
  final TextDirection? textDirection;

  @override
  _RenderTextSweep createRenderObject(BuildContext context) =>
      _RenderTextSweep(effect, progress, textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderTextSweep render) {
    render
      ..effect = effect
      ..progress = progress
      ..textDirection = textDirection;
  }
}

class _RenderTextSweep extends RenderProxyBox {
  _RenderTextSweep(this._effect, this._progress, this._textDirection);

  ShimmerEffect? _effect;
  set effect(ShimmerEffect? value) {
    if (value == _effect) return;
    final toggled = (value == null) != (_effect == null);
    _effect = value;
    if (toggled) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  Animation<double>? _progress;
  set progress(Animation<double>? value) {
    if (value == _progress) return;
    if (attached) _progress?.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) _progress?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  bool get alwaysNeedsCompositing => child != null && _effect != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final effect = _effect;
    if (child == null || effect == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final rect = Offset.zero & size;
    final shader =
        effect.createPaint(_progress?.value ?? 0, rect, _textDirection).shader!;
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.srcIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}
