import 'package:flutter/material.dart';
import 'package:kute/theme/app_theme.dart';

/// Splits a BTC display string ("0.00 011 172", "0", or "12,345" sats) into
/// the leading-zero prefix and the significant remainder. Any character in
/// `{'0', '.', ' ', '\u{2009}', ','}` that precedes the first non-zero digit
/// goes into `dim`; everything from the first non-zero digit onward
/// (inclusive) goes into `bright`. If the whole string is dim-eligible
/// (balance == 0), `bright` is empty and the caller should render `dim` in
/// the tertiary color.
({String dim, String bright}) _splitLeadingZeros(String s) {
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == '0' || ch == '.' || ch == ' ' || ch == '\u{2009}' || ch == ',') {
      i++;
      continue;
    }
    // First "real" digit (1-9) or unexpected glyph (e.g. '-') — split here.
    break;
  }
  if (i >= s.length) {
    // String was entirely zeros / dots / spaces.
    return (dim: s, bright: '');
  }
  return (dim: s.substring(0, i), bright: s.substring(i));
}

/// Renders a BTC (or sats) amount string with the leading-zero prefix dimmed
/// so the eye locks onto the significant digits first. Falls back to a
/// single-color render when [dim] is false (e.g. masked "•••••" display)
/// since the dot mask has no leading-zero semantics.
class BtcAmountText extends StatelessWidget {
  /// The pre-formatted amount string, e.g. "0.00 011 172" or "12,345".
  final String text;

  /// Base style (size, weight, height, etc.) — color is overridden per-span.
  final TextStyle style;

  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  /// Color for the leading-zero prefix. Defaults to `c.textTertiary`.
  final Color? dimColor;

  /// Color for the significant digits. Defaults to `c.textPrimary`.
  final Color? brightColor;

  /// When false, render the entire string in [brightColor] (e.g. masked).
  final bool dim;

  const BtcAmountText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.dimColor,
    this.brightColor,
    this.dim = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bright = brightColor ?? c.textPrimary;
    final dimC = dimColor ?? c.textTertiary;

    if (!dim) {
      return Text(
        text,
        style: style.copyWith(color: bright),
        textAlign: textAlign,
        overflow: overflow,
        maxLines: maxLines,
      );
    }

    final parts = _splitLeadingZeros(text);
    if (parts.bright.isEmpty) {
      // All-zero balance — render the whole thing in the dim color.
      return Text(
        parts.dim,
        style: style.copyWith(color: dimC),
        textAlign: textAlign,
        overflow: overflow,
        maxLines: maxLines,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          if (parts.dim.isNotEmpty)
            TextSpan(text: parts.dim, style: style.copyWith(color: dimC)),
          TextSpan(text: parts.bright, style: style.copyWith(color: bright)),
        ],
      ),
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}

/// `BtcAmountText` that interpolates between consecutive `text` values
/// using a numeric tween — so when sats land on the wallet the headline
/// counts UP from the previous balance instead of snapping. Keeps the
/// dim/bright leading-zero treatment by re-rendering through
/// [BtcAmountText] each frame.
///
/// Numbers are extracted via a `[^\d.,  ]` strip (BTC's thin-
/// space grouping is preserved by the template, then reapplied on
/// format). If the old/new strings aren't both numeric (e.g. masked
/// "•••••"), falls back to a static render so we never animate
/// nonsense.
class AnimatedBtcAmountText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final Color? dimColor;
  final Color? brightColor;
  final bool dim;
  final Duration duration;

  const AnimatedBtcAmountText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.dimColor,
    this.brightColor,
    this.dim = true,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedBtcAmountText> createState() => _AnimatedBtcAmountTextState();
}

class _AnimatedBtcAmountTextState extends State<AnimatedBtcAmountText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _curve;
  String _oldText = '';

  @override
  void initState() {
    super.initState();
    _oldText = widget.text;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(AnimatedBtcAmountText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _oldText = old.text;
      // Count-up is decorative polish; the target value is shown either
      // way. Respect reduce-motion by snapping straight to the result.
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (_, __) {
        final oldN = _parse(_oldText);
        final newN = _parse(widget.text);
        // Either side unparseable → render the target as-is (e.g.
        // masked "•••••" or a non-numeric placeholder).
        if (oldN == null || newN == null) {
          return BtcAmountText(
            text: widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
            overflow: widget.overflow,
            maxLines: widget.maxLines,
            dimColor: widget.dimColor,
            brightColor: widget.brightColor,
            dim: widget.dim,
          );
        }
        final current = oldN + (newN - oldN) * _curve.value;
        final rendered = _formatLike(current, widget.text);
        return BtcAmountText(
          text: rendered,
          style: widget.style,
          textAlign: widget.textAlign,
          overflow: widget.overflow,
          maxLines: widget.maxLines,
          dimColor: widget.dimColor,
          brightColor: widget.brightColor,
          dim: widget.dim,
        );
      },
    );
  }

  /// Strip currency symbols / suffixes / thin-spaces and parse the
  /// remaining numeric body. Returns null if nothing parseable was
  /// found (so we can fall back to a non-animated render).
  double? _parse(String s) {
    final cleaned = s
        .replaceAll('\u{2009}', '')
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'[^\d.,\-]'), '');
    if (cleaned.isEmpty) return null;
    // BTC headlines we render here use US-style separators (group ',',
    // decimal '.'). Strip group commas and parse.
    final normalized = cleaned.replaceAll(',', '');
    return double.tryParse(normalized);
  }

  /// Re-emit `value` in the same shape as `template` — preserving:
  ///   * the decimal-place count (if any)
  ///   * group separators (commas every 3 digits in the integer part)
  ///   * BTC thin-space grouping in the fractional part (e.g.
  ///     "0.00 011 172" → "0.00 011 173" etc.)
  ///   * any leading/trailing non-digit affixes (a leading "₿", etc.)
  String _formatLike(double value, String template) {
    final decIdx = template.lastIndexOf('.');
    final hasDecimal = decIdx >= 0 &&
        decIdx < template.length - 1 &&
        RegExp(r'\d').hasMatch(template.substring(decIdx));
    if (!hasDecimal) {
      final intVal = value.round();
      return _withAffixes(_groupInt(intVal.abs().toString()), template, intVal);
    }
    final templateDec = template.substring(decIdx + 1);
    final places = templateDec.replaceAll(RegExp(r'[^\d]'), '').length;
    final absStr =
        value.abs().toStringAsFixed(places > 0 ? places : 2);
    final dot = absStr.indexOf('.');
    final intPart = dot >= 0 ? absStr.substring(0, dot) : absStr;
    var decPart = dot >= 0 ? absStr.substring(dot + 1) : '';

    // Re-apply thin-space grouping every 3 digits after the leading
    // two if the template uses it (BTC "00 000 000" convention).
    if (templateDec.contains('\u{2009}') && decPart.length > 2) {
      final buf = StringBuffer()..write(decPart.substring(0, 2));
      for (var i = 2; i < decPart.length; i++) {
        if ((i - 2) % 3 == 0) buf.write('\u{2009}');
        buf.write(decPart[i]);
      }
      decPart = buf.toString();
    }
    final body = '${_groupInt(intPart)}.$decPart';
    return _withAffixes(body, template, value.toInt());
  }

  String _groupInt(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  String _withAffixes(String body, String template, num value) {
    final prefix = RegExp(r'^[^\d\-]*').firstMatch(template)?.group(0) ?? '';
    final suffix = RegExp(r'[^\d]*$').firstMatch(template)?.group(0) ?? '';
    final sign = value < 0 ? '-' : '';
    return '$prefix$sign$body$suffix';
  }
}
