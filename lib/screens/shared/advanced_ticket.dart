// lib/screens/shared/advanced_ticket.dart
//
// The Advanced order tickets' shared pieces, one hand for both venues
// (Predictions' Advanced prediction and sale, Investing's Advanced order):
// the page with its primary floating ([AdvancedTicketFrame]), the amount as
// the page's hero ([AdvancedHeroAmount]), the order types as graphic tiles
// ([AdvancedTypeTiles]), a price stepper ([AdvancedStepper]), a switch row
// that folds its inputs open ([AdvancedToggleRow]), preset chips
// ([AdvancedChips]), the summary card ([AdvancedSummaryCard]), the
// Investing price map with its risk / reward box ([AdvancedPriceMap]) and
// the Predictions odds rail ([AdvancedOddsTrack]).
//
// Presentation only: every piece takes plain values and calls back; the
// pages keep their state, rules, validation and analytics. Colours, radii,
// type and card chrome come from the theme (context.colors, AppRadius,
// AppDecorations.card) and the slips' side colours; light and dark.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/theme/app_theme.dart';

// ── The page ──────────────────────────────────────────────────────────────

/// The Advanced page: the app bar as every ticket has it (the back button,
/// a centred title), the content scrolling under the page's one primary,
/// which FLOATS at the foot: no bar, no divider, no box behind it, only a
/// fade of the page's own background so text scrolling under the pill
/// stays readable. [primary] is the ticket's own action (the Sal bar's
/// pill, its notes over it) placed exactly as given; [primaryHeight] is the
/// room it takes, so the last card clears it by 40.
class AdvancedTicketFrame extends StatelessWidget {
  const AdvancedTicketFrame({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
    required this.primary,
    required this.primaryHeight,
    this.canPop = true,
    this.scrollKey,
    this.contentKey,
  });

  final String title;
  final VoidCallback onBack;
  final bool canPop;

  /// The page's content, top to bottom (20.w side padding is the frame's).
  final List<Widget> children;

  /// The floating action, as the ticket builds it.
  final Widget primary;
  final double primaryHeight;

  /// The scroll view's key (tests find the form by it).
  final Key? scrollKey;

  /// Wraps the content (a marker a page may need).
  final Key? contentKey;

  /// The fade's height over the foot.
  static const double fadeHeight = 96;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final safe = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: KuteBackButton(onPressed: () {
          if (canPop) onBack();
        }),
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                key: scrollKey,
                physics: const ClampingScrollPhysics(),
                primary: false,
                padding: EdgeInsets.fromLTRB(
                    20.w, 8.h, 20.w, primaryHeight + 40 + safe),
                child: KeyedSubtree(
                  key: contentKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ),
            // The fade: the page's own ground, from clear to ~92%, so a
            // line scrolling under the pill stays readable. Never a bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: fadeHeight + safe,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('advanced-ticket-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        c.background.withValues(alpha: 0),
                        c.background.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: KeyedSubtree(
                  key: const ValueKey('advanced-ticket-primary'),
                  child: primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The amount ────────────────────────────────────────────────────────────

/// The amount as the page's hero: centred, in the plain slip's big figure
/// (`$0` in textTertiary until something is typed), one line under it
/// ([caption], "Available $X"). The existing [controller] stays the input:
/// an invisible field under the figure holds the focus and the keyboard
/// (phone and web alike); a tap on the figure focuses it.
class AdvancedHeroAmount extends StatefulWidget {
  const AdvancedHeroAmount({
    super.key,
    required this.controller,
    this.prefix = r'$',
    this.caption,
    this.captionIsError = false,
    this.inputFormatters = const [],
    this.readOnly = false,
    this.below,
  });

  final TextEditingController controller;
  final String prefix;
  final String? caption;
  final bool captionIsError;
  final List<TextInputFormatter> inputFormatters;
  final bool readOnly;

  /// Under the caption (a minimum line, a share count).
  final Widget? below;

  @override
  State<AdvancedHeroAmount> createState() => _AdvancedHeroAmountState();
}

class _AdvancedHeroAmountState extends State<AdvancedHeroAmount> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(AdvancedHeroAmount old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = widget.controller.text;
    final empty = text.isEmpty || (double.tryParse(text) ?? 0) == 0;
    final shown = text.isEmpty ? '0' : text;
    final focused = _focus.hasFocus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('advanced-hero-amount'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.readOnly ? null : () => _focus.requestFocus(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The real input: invisible, it holds the focus, the
              // keyboard and the formatter (the same controller).
              Opacity(
                opacity: 0,
                child: SizedBox(
                  height: 1,
                  width: 1,
                  child: TextField(
                    focusNode: _focus,
                    controller: widget.controller,
                    readOnly: widget.readOnly,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: widget.inputFormatters,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.prefix}$shown',
                        maxLines: 1,
                        style: TextStyle(
                          color: empty ? c.textTertiary : c.textPrimary,
                          fontSize: 52.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      // The caret while typing, the figure's own colour.
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: focused ? 1 : 0,
                        child: Container(
                          margin: EdgeInsets.only(left: 3.w),
                          width: 2,
                          height: 40.sp,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.caption case final caption?) ...[
          SizedBox(height: 6.h),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.captionIsError ? AppColors.error : c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (widget.below case final below?) ...[
          SizedBox(height: 8.h),
          below,
        ],
      ],
    );
  }
}

// ── Order types ───────────────────────────────────────────────────────────

/// The glyph drawn on an order-type tile.
enum AdvancedTypeGlyph { market, limit, scale, twap }

/// One order type: its [label] and [glyph].
class AdvancedTypeOption {
  const AdvancedTypeOption(
      {required this.label, required this.glyph, this.key});
  final String label;
  final AdvancedTypeGlyph glyph;
  final Key? key;
}

/// The order types as a row of 2 to 4 equal tiles (76 high), each a small
/// painted glyph over its label; the selected one in the side colour. One
/// sentence under the row ([explanation]) says what the selected type does.
class AdvancedTypeTiles extends StatelessWidget {
  const AdvancedTypeTiles({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.sideColor,
    this.explanation,
  });

  final List<AdvancedTypeOption> options;
  final int selected;
  final ValueChanged<int> onSelected;
  final Color sideColor;
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) SizedBox(width: 8.w),
              Expanded(
                child: _TypeTile(
                  key: options[i].key,
                  option: options[i],
                  selected: i == selected,
                  sideColor: sideColor,
                  onTap: () {
                    if (i == selected) return;
                    HapticFeedback.selectionClick();
                    onSelected(i);
                  },
                ),
              ),
            ],
          ],
        ),
        if (explanation case final text?) ...[
          SizedBox(height: 10.h),
          Text(
            text,
            style:
                TextStyle(fontSize: 13.sp, color: c.textSecondary, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    super.key,
    required this.option,
    required this.selected,
    required this.sideColor,
    required this.onTap,
  });

  final AdvancedTypeOption option;
  final bool selected;
  final Color sideColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? sideColor : c.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 76,
          decoration: BoxDecoration(
            color: selected ? sideColor.withValues(alpha: 0.14) : c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? sideColor : c.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(28, 20),
                painter: AdvancedGlyphPainter(option.glyph, ink),
              ),
              SizedBox(height: 8.h),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.textPrimary : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The order types' glyphs, 2 px strokes in [color]: MARKET a rising price
/// line ending in a dot; LIMIT the line with a dashed level under it and a
/// dot on the level; SCALE three short dashed levels stepped like a
/// ladder; TWAP four evenly spaced bars on a baseline.
class AdvancedGlyphPainter extends CustomPainter {
  const AdvancedGlyphPainter(this.glyph, this.color);
  final AdvancedTypeGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void dashed(double y, double x0, double x1) {
      for (var x = x0; x < x1; x += 5) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 2.5, x1), y), stroke);
      }
    }

    switch (glyph) {
      case AdvancedTypeGlyph.market:
        final line = Path()
          ..moveTo(1, h * 0.85)
          ..lineTo(w * 0.32, h * 0.55)
          ..lineTo(w * 0.52, h * 0.68)
          ..lineTo(w * 0.82, h * 0.22);
        canvas.drawPath(line, stroke);
        canvas.drawCircle(Offset(w * 0.82, h * 0.22), 2.6, fill);
      case AdvancedTypeGlyph.limit:
        final line = Path()
          ..moveTo(1, h * 0.25)
          ..lineTo(w * 0.35, h * 0.5)
          ..lineTo(w * 0.55, h * 0.35)
          ..lineTo(w - 1, h * 0.55);
        canvas.drawPath(line, stroke);
        dashed(h * 0.85, 1, w - 1);
        canvas.drawCircle(Offset(w * 0.7, h * 0.85), 2.6, fill);
      case AdvancedTypeGlyph.scale:
        dashed(h * 0.2, w * 0.05, w * 0.45);
        dashed(h * 0.5, w * 0.3, w * 0.7);
        dashed(h * 0.8, w * 0.55, w * 0.95);
      case AdvancedTypeGlyph.twap:
        canvas.drawLine(Offset(1, h - 1), Offset(w - 1, h - 1), stroke);
        for (var i = 0; i < 4; i++) {
          final x = w * (0.16 + i * 0.226);
          canvas.drawLine(Offset(x, h - 4), Offset(x, h * 0.3), stroke);
        }
    }
  }

  @override
  bool shouldRepaint(AdvancedGlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

// ── A stepped value ───────────────────────────────────────────────────────

/// One stepped value in a card: [label] left, the value big (tap to type,
/// [onValueTap]), round `−` / `+` at the ends (holding repeats), and an
/// optional [trailing] text action (the "Market 5.5%" snap).
class AdvancedStepper extends StatelessWidget {
  const AdvancedStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onStep,
    this.onValueTap,
    this.trailing,
    this.onTrailing,
    this.valueKey,
    this.enabled = true,
  });

  final String label;
  final String value;

  /// -1 or +1, per tap or per repeat while held.
  final ValueChanged<int> onStep;
  final VoidCallback? onValueTap;
  final String? trailing;
  final VoidCallback? onTrailing;
  final Key? valueKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14.sp,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              if (trailing case final t?)
                GestureDetector(
                  key: const ValueKey('advanced-stepper-trailing'),
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onTrailing : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                            decoration: TextDecoration.underline,
                            decorationColor: c.textPrimary)),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              _RoundStep(
                  key: const ValueKey('advanced-stepper-minus'),
                  icon: Icons.remove_rounded,
                  enabled: enabled,
                  onStep: () => onStep(-1)),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onValueTap : null,
                  child: Center(
                    child: Text(
                      value,
                      key: valueKey,
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              _RoundStep(
                  key: const ValueKey('advanced-stepper-plus'),
                  icon: Icons.add_rounded,
                  enabled: enabled,
                  onStep: () => onStep(1)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A round 40 px step button; holding it repeats.
class _RoundStep extends StatefulWidget {
  const _RoundStep(
      {super.key,
      required this.icon,
      required this.onStep,
      required this.enabled});
  final IconData icon;
  final VoidCallback onStep;
  final bool enabled;

  @override
  State<_RoundStep> createState() => _RoundStepState();
}

class _RoundStepState extends State<_RoundStep> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onStep();
              }
            : null,
        onLongPressStart: widget.enabled
            ? (_) {
                widget.onStep();
                _repeat = Timer.periodic(const Duration(milliseconds: 90),
                    (_) => widget.onStep());
              }
            : null,
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceLight,
            shape: BoxShape.circle,
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Icon(widget.icon,
              size: 20,
              color: widget.enabled ? c.textPrimary : c.textTertiary),
        ),
      ),
    );
  }
}

// ── A switch that folds its inputs open ───────────────────────────────────

/// A row with an [icon], a [title], a one-line [subtitle] and the app's
/// switch; while [value] is on, [children] fold open under it.
class AdvancedToggleRow extends StatelessWidget {
  const AdvancedToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.children = const [],
    this.switchKey,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final List<Widget> children;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 10.h, 10.w, 10.h),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: c.textSecondary),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary)),
                    if (subtitle case final s?)
                      Text(s,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.sp, color: c.textSecondary)),
                  ],
                ),
              ),
              Switch.adaptive(
                key: switchKey,
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: value && children.isNotEmpty
                ? Padding(
                    padding: EdgeInsets.only(top: 10.h, right: 4.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ── Preset chips ──────────────────────────────────────────────────────────

/// A row of small pill chips for presets: single choice ([selected] the
/// index, or null for none).
class AdvancedChips extends StatelessWidget {
  const AdvancedChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (var i = 0; i < labels.length; i++)
          GestureDetector(
            key: ValueKey('advanced-chip-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(i);
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
              decoration: BoxDecoration(
                color: i == selected ? context.ctaFill : c.surfaceLight,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: i == selected ? context.ctaFill : c.border,
                    width: 0.5),
              ),
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: i == selected
                          ? context.ctaOnColor
                          : c.textSecondary)),
            ),
          ),
      ],
    );
  }
}

// ── The summary ───────────────────────────────────────────────────────────

/// One summary row: [label] and [value]; [onTap] makes it a link (a fee's
/// breakdown).
class AdvancedSummaryRow {
  const AdvancedSummaryRow(this.label, this.value, {this.onTap, this.key});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Key? key;
}

/// Compact label / value rows in one card, under one emphasised
/// [headline] row (bigger, textPrimary; [headlineColor] for a win figure).
/// [footer] widgets (notices, a fee breakdown) follow the rows.
class AdvancedSummaryCard extends StatelessWidget {
  const AdvancedSummaryCard({
    super.key,
    this.headline,
    this.headlineColor,
    this.rows = const [],
    this.footer = const [],
  });

  final AdvancedSummaryRow? headline;
  final Color? headlineColor;
  final List<AdvancedSummaryRow> rows;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(AdvancedSummaryRow r) => GestureDetector(
          key: r.key,
          behavior: HitTestBehavior.opaque,
          onTap: r.onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 5.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label,
                    style: TextStyle(fontSize: 14.sp, color: c.textSecondary)),
                SizedBox(width: 12.w),
                // A long value ("Depends on your open position", a
                // translation) wraps at the right instead of overflowing.
                Expanded(
                  child: Text(r.value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                        decoration:
                            r.onTap != null ? TextDecoration.underline : null,
                        decorationColor: c.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (headline case final h?) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(h.label,
                      style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary)),
                ),
                Text(h.value,
                    key: h.key,
                    style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w800,
                        color: headlineColor ?? c.textPrimary,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
            if (rows.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Divider(height: 1, thickness: 0.5, color: c.borderSubtle),
              SizedBox(height: 4.h),
            ],
          ],
          for (final r in rows) row(r),
          ...footer,
        ],
      ),
    );
  }
}

// ── Investing: the price map ──────────────────────────────────────────────

/// What a price level on [AdvancedPriceMap] is.
enum AdvancedLevelKind { limit, takeProfit, stopLoss, trailing, scaleLeg }

/// One level on [AdvancedPriceMap]: its [price], [kind], its pill's
/// [label] (e.g. "TP") and an optional second line ([detail], e.g. an
/// estimated P&L).
class AdvancedPriceLevel {
  const AdvancedPriceLevel(
      {required this.price, required this.kind, this.label, this.detail});
  final double price;
  final AdvancedLevelKind kind;
  final String? label;
  final String? detail;
}

/// The Investing ticket's price map: a full-width card (about 132 high)
/// with a vertical price axis, a line for "now" ([now], labelled
/// [nowLabel]) and one per [levels], each with a pill naming its price
/// ([formatPrice]) and its distance from now in %; between [entry] and a
/// take profit the band is shaded green at ~12%, between [entry] and a stop
/// loss red (the risk / reward box). Pills never overlap. Plain data only.
class AdvancedPriceMap extends StatelessWidget {
  const AdvancedPriceMap({
    super.key,
    required this.now,
    required this.levels,
    required this.formatPrice,
    this.entry,
    this.nowLabel = 'Now',
    this.height = 132,
  });

  final double now;
  final double? entry;
  final List<AdvancedPriceLevel> levels;
  final String Function(double price) formatPrice;
  final String nowLabel;
  final double height;

  /// The smallest vertical gap between two pills' centres.
  static const double minGap = 22;

  /// The pills' centres for [prices] (top = highest) in a box [height]
  /// high with [pad] at both ends: by price, then pushed apart so no two
  /// are closer than [minGap], kept inside the box.
  static List<double> layout(List<double> prices, double height,
      {double pad = 14}) {
    if (prices.isEmpty) return const [];
    final hi = prices.reduce(math.max), lo = prices.reduce(math.min);
    final span = hi - lo;
    final usable = height - 2 * pad;
    final ys = [
      for (final p in prices)
        span <= 0 ? height / 2 : pad + (hi - p) / span * usable,
    ];
    final order = List<int>.generate(ys.length, (i) => i)
      ..sort((a, b) => ys[a].compareTo(ys[b]));
    for (var k = 1; k < order.length; k++) {
      final prev = ys[order[k - 1]];
      if (ys[order[k]] < prev + minGap) ys[order[k]] = prev + minGap;
    }
    // Pushed past the foot: shift the run back up, never above the top.
    final last = ys[order.last];
    final over = last - (height - pad);
    if (over > 0) {
      for (final i in order) {
        ys[i] = math.max(pad, ys[i] - over);
      }
      for (var k = 1; k < order.length; k++) {
        final prev = ys[order[k - 1]];
        if (ys[order[k]] < prev + minGap) ys[order[k]] = prev + minGap;
      }
    }
    return ys;
  }

  Color _colorOf(BuildContext context, AdvancedLevelKind? kind) {
    final c = context.colors;
    return switch (kind) {
      AdvancedLevelKind.takeProfit => AppColors.marketUp,
      AdvancedLevelKind.stopLoss => AppColors.marketDown,
      AdvancedLevelKind.trailing => AppColors.marketDown,
      AdvancedLevelKind.limit => c.textPrimary,
      AdvancedLevelKind.scaleLeg => c.textSecondary,
      null => c.textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final prices = [now, ...levels.map((l) => l.price)];
    // The lines sit at their true price; only the pills are pushed apart.
    final hi = prices.reduce(math.max), lo = prices.reduce(math.min);
    const pad = 14.0;
    double yOf(double p) =>
        hi - lo <= 0 ? height / 2 : pad + (hi - p) / (hi - lo) * (height - 2 * pad);
    final pillYs = layout(prices, height);
    String pct(double p) {
      if (now == 0) return '';
      final d = (p - now) / now * 100;
      return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(d.abs() < 10 ? 2 : 1)}%';
    }

    final tp = levels
        .where((l) => l.kind == AdvancedLevelKind.takeProfit)
        .map((l) => l.price)
        .firstOrNull;
    final sl = levels
        .where((l) =>
            l.kind == AdvancedLevelKind.stopLoss ||
            l.kind == AdvancedLevelKind.trailing)
        .map((l) => l.price)
        .firstOrNull;
    final base = entry ?? now;
    return Container(
      key: const ValueKey('advanced-price-map'),
      height: height,
      decoration: AppDecorations.card(context),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PriceMapPainter(
                  lines: [
                    (yOf(now), c.textTertiary, true),
                    for (final l in levels)
                      (yOf(l.price), _colorOf(context, l.kind), false),
                  ],
                  bands: [
                    if (tp != null)
                      (yOf(base), yOf(tp),
                          AppColors.marketUp.withValues(alpha: 0.12)),
                    if (sl != null)
                      (yOf(base), yOf(sl),
                          AppColors.marketDown.withValues(alpha: 0.12)),
                  ],
                  axis: c.borderSubtle,
                ),
              ),
            ),
            for (var i = 0; i < prices.length; i++)
              Positioned(
                right: 10,
                top: pillYs[i] - 10,
                child: _PricePill(
                  color: _colorOf(context, i == 0 ? null : levels[i - 1].kind),
                  title: i == 0
                      ? '$nowLabel ${formatPrice(now)}'
                      : '${levels[i - 1].label ?? ''}${levels[i - 1].label == null ? '' : ' '}'
                          '${formatPrice(levels[i - 1].price)} · ${pct(levels[i - 1].price)}',
                  detail: i == 0 ? null : levels[i - 1].detail,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.color, required this.title, this.detail});
  final Color color;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (detail case final d?) ...[
            const SizedBox(width: 6),
            Text(d, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _PriceMapPainter extends CustomPainter {
  _PriceMapPainter(
      {required this.lines, required this.bands, required this.axis});
  final List<(double y, Color color, bool now)> lines;
  final List<(double y0, double y1, Color fill)> bands;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (y0, y1, fill) in bands) {
      canvas.drawRect(
          Rect.fromLTRB(28, math.min(y0, y1), size.width, math.max(y0, y1)),
          Paint()..color = fill);
    }
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(20, 8), Offset(20, size.height - 8), axisPaint);
    for (final (y, color, now) in lines) {
      final p = Paint()
        ..color = color
        ..strokeWidth = now ? 1 : 1.5;
      if (now) {
        for (var x = 20.0; x < size.width; x += 6) {
          canvas.drawLine(Offset(x, y), Offset(x + 3, y), p);
        }
      } else {
        canvas.drawLine(Offset(20, y), Offset(size.width, y), p);
      }
      canvas.drawCircle(Offset(20, y), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_PriceMapPainter old) => true;
}

// ── Predictions: the odds rail ────────────────────────────────────────────

/// Snaps [price] to [tick]'s grid inside [tick, 1 − tick].
double advancedSnapOdds(double price, double tick) {
  final t = tick <= 0 || tick >= 1 ? 0.01 : tick;
  final steps = (price / t).round();
  final maxSteps = (1 / t).round() - 1;
  final n = steps.clamp(1, maxSteps);
  return double.parse((n * t).toStringAsFixed(6));
}

/// The Predictions limit price as a rail from 0 to 100 cents (a card about
/// 96 high): the market's price marked ([marketLabel]), the best bid / ask
/// ticks when the book is known, and a draggable thumb for [price] that
/// snaps to [tick] inside [tick, 1 − tick]. The part of the rail where the
/// order would fill at once ([fillsFrom] up for a buy, down to it for a
/// sell: [buy]) is tinted, and [thumbLabel] sits over the thumb. It calls
/// back with the snapped price only ([onChanged]); the page keeps the
/// price and its rules.
class AdvancedOddsTrack extends StatelessWidget {
  const AdvancedOddsTrack({
    super.key,
    required this.price,
    required this.market,
    required this.tick,
    required this.onChanged,
    required this.sideColor,
    this.marketLabel,
    this.bestBid,
    this.bestAsk,
    this.fillsFrom,
    this.buy = true,
    this.thumbLabel,
    this.formatPrice,
  });

  final double price;
  final double market;
  final double tick;
  final ValueChanged<double> onChanged;
  final Color sideColor;
  final String? marketLabel;
  final double? bestBid;
  final double? bestAsk;
  final double? fillsFrom;
  final bool buy;
  final String? thumbLabel;
  final String Function(double)? formatPrice;

  static const double _inset = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('advanced-odds-track'),
      height: 96,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: AppDecorations.card(context),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth - 2 * _inset;
        double xOf(double p) => _inset + p.clamp(0.0, 1.0) * w;
        void drag(double dx) {
          final p = advancedSnapOdds((dx - _inset) / w, tick);
          if ((p - price).abs() > 1e-9) {
            HapticFeedback.selectionClick();
            onChanged(p);
          }
        }

        final thumbX = xOf(price);
        const railY = 50.0;
        return GestureDetector(
          key: const ValueKey('advanced-odds-rail'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => drag(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => drag(d.localPosition.dx),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _OddsPainter(
                    inset: _inset,
                    railY: railY,
                    market: market,
                    bestBid: bestBid,
                    bestAsk: bestAsk,
                    fillsFrom: fillsFrom,
                    buy: buy,
                    rail: c.surfaceLight,
                    border: c.border,
                    tint: sideColor.withValues(alpha: 0.22),
                    marker: c.textSecondary,
                  ),
                ),
              ),
              // The market's price, under the rail.
              if (marketLabel case final m?)
                Positioned(
                  top: railY + 12,
                  left: (xOf(market) - 60).clamp(0.0, box.maxWidth - 120),
                  width: 120,
                  child: Text(m,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary)),
                ),
              // What the thumb says (fills at once / rests), over it.
              if (thumbLabel case final t?)
                Positioned(
                  top: 0,
                  left: (thumbX - 90).clamp(0.0, box.maxWidth - 180),
                  width: 180,
                  child: Text(t,
                      key: const ValueKey('advanced-odds-thumb-label'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary)),
                ),
              Positioned(
                left: thumbX - 13,
                top: railY - 13,
                child: Container(
                  key: const ValueKey('advanced-odds-thumb'),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: sideColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _OddsPainter extends CustomPainter {
  _OddsPainter({
    required this.inset,
    required this.railY,
    required this.market,
    required this.bestBid,
    required this.bestAsk,
    required this.fillsFrom,
    required this.buy,
    required this.rail,
    required this.border,
    required this.tint,
    required this.marker,
  });
  final double inset, railY, market;
  final double? bestBid, bestAsk, fillsFrom;
  final bool buy;
  final Color rail, border, tint, marker;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - 2 * inset;
    double x(double p) => inset + p.clamp(0.0, 1.0) * w;
    final r = RRect.fromLTRBR(
        inset, railY - 4, size.width - inset, railY + 4, const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = rail);
    if (fillsFrom case final f?) {
      final a = buy ? x(f) : inset, b = buy ? size.width - inset : x(f);
      canvas.drawRRect(
          RRect.fromLTRBR(a, railY - 4, b, railY + 4, const Radius.circular(4)),
          Paint()..color = tint);
    }
    final tick = Paint()
      ..color = marker
      ..strokeWidth = 1.5;
    for (final p in [bestBid, bestAsk]) {
      if (p == null) continue;
      canvas.drawLine(Offset(x(p), railY - 9), Offset(x(p), railY + 9), tick);
    }
    canvas.drawCircle(Offset(x(market), railY), 4, Paint()..color = marker);
  }

  @override
  bool shouldRepaint(_OddsPainter old) => true;
}
