import 'package:flutter/material.dart';

/// Cash-register / odometer roll for a number string. Each digit
/// position has its own little reel — when the digit changes the
/// new digit slides in from the top while the old one slides out
/// through the bottom, exactly like the wheels on a mechanical
/// register. Non-digit characters (`$`, `,`, `.`, ` `, `%`, `-`)
/// stay put as plain `Text`s.
///
/// Used on chart tooltips so values feel "alive" while scrubbing
/// across the chart (matches the Polymarket web tooltip).
///
/// Implementation notes:
///   - Each digit is wrapped in `_RollingDigit`, a small stateful
///     widget with its own `AnimationController`. Position-keyed
///     so the same digit position keeps its controller across
///     rebuilds (digit "2" rolling to "4" reuses the same reel).
///   - Width is measured per-character via `TextPainter` so we
///     don't depend on tabular figures being available in the
///     selected font. Slightly more allocation than a tabular-
///     figure approach but fonts in this app aren't all tabular.
///   - Direction: new digit comes from above (`-lineHeight` →
///     `0`), old digit exits through below (`0` → `+lineHeight`).
class RollingNumberText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// How long each digit's roll takes. Short (~250 ms) on settle
  /// updates; very short (~120 ms) is right while scrubbing so
  /// the reel keeps up with finger drags.
  final Duration duration;

  /// When set, paints every char before the first non-zero digit
  /// (treating `'0'`, `'.'`, `' '`, `'\u{2009}'`, and `','` as
  /// dim-eligible) in this color. The rest stays in `style.color`.
  /// Used by the BTC balance cards to grey out leading zeros so
  /// the eye locks onto the significant figures first.
  final Color? dimColor;

  const RollingNumberText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 250),
    this.dimColor,
  });

  static final _digitMatcher = RegExp(r'\d');

  /// Returns the index of the first char that should render in the
  /// bright (style.color) color. All chars before this index render
  /// dim. If the whole string is dim-eligible, returns `chars.length`
  /// (caller should treat the whole string as dim).
  static int _firstBrightIndex(List<String> chars) {
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      if (ch == '0' || ch == '.' || ch == ' ' || ch == '\u{2009}' || ch == ',') {
        continue;
      }
      return i;
    }
    return chars.length;
  }

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    final brightIdx = dimColor != null ? _firstBrightIndex(chars) : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (int i = 0; i < chars.length; i++)
          () {
            final isDim = dimColor != null && i < brightIdx;
            final charStyle =
                isDim ? style.copyWith(color: dimColor) : style;
            return _digitMatcher.hasMatch(chars[i])
                ? _RollingDigit(
                    // Keyed by index so the same reel handles the
                    // same column across rebuilds. Length changes
                    // (e.g. "9.99" → "10.00") allocate a fresh reel
                    // for the new column, which is fine — the new
                    // column doesn't have a "previous digit" to
                    // animate away from.
                    key: ValueKey<int>(i),
                    digit: chars[i],
                    style: charStyle,
                    duration: duration,
                  )
                : Text(
                    chars[i],
                    style: charStyle,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  );
          }(),
      ],
    );
  }
}

class _RollingDigit extends StatefulWidget {
  final String digit;
  final TextStyle style;
  final Duration duration;

  const _RollingDigit({
    super.key,
    required this.digit,
    required this.style,
    required this.duration,
  });

  @override
  State<_RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<_RollingDigit>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CurvedAnimation _animation;
  String _previous = '';

  @override
  void initState() {
    super.initState();
    _previous = widget.digit;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1.0, // start fully settled — first paint shows the
                  // current digit, not an in-flight roll
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(_RollingDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.digit != widget.digit) {
      _previous = oldWidget.digit;
      // The roll is a decorative transition between two values — the
      // value itself is conveyed by the settled text, not the motion.
      // Honour reduce-motion by snapping straight to the new digit.
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Measures one character at the size it will actually paint at.
  ///
  /// The cell this returns becomes a `SizedBox` around a `ClipRect`, while
  /// the digit inside is an ordinary `Text`, which grows with the OS text
  /// size. Measuring without that same scale gave a cell narrower than the
  /// glyph, and the clip then shaved the right edge off every digit. It
  /// showed up as a balance that looked cut off, worst on small screens,
  /// where a raised text size is most common.
  Size _measureChar(String char, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: char, style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout();
    return tp.size;
  }

  @override
  Widget build(BuildContext context) {
    // Use the wider of (previous, current) so the digit cell
    // doesn't visibly resize mid-roll on proportional fonts.
    final scaler = MediaQuery.textScalerOf(context);
    final currentSize = _measureChar(widget.digit, scaler);
    final previousSize = _measureChar(_previous, scaler);
    final width = currentSize.width > previousSize.width
        ? currentSize.width
        : previousSize.width;
    final height = currentSize.height > previousSize.height
        ? currentSize.height
        : previousSize.height;

    return SizedBox(
      width: width,
      height: height,
      // The clip exists for the vertical roll. Sideways it lets the glyph
      // bleed a little: Android paints a glyph a hair wider than the
      // measured cell, and a tight clip shaved the right edge off the
      // last digit of every balance.
      child: ClipRect(
        clipper: const _RollClipper(),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            // t = 0 → previous fully visible, new sitting one cell above.
            // t = 1 → previous one cell below, new fully visible.
            final t = _animation.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: t * height,
                  child: Text(
                    _previous,
                    style: widget.style,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: -height + t * height,
                  child: Text(
                    widget.digit,
                    style: widget.style,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Clips only vertically to the cell; horizontally it allows a small
/// bleed on both sides so glyph edges are never shaved.
class _RollClipper extends CustomClipper<Rect> {
  const _RollClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-3, 0, size.width + 3, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
