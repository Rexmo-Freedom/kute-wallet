import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Animated balance display that counts up/down to the target value.
/// Numbers roll through 0-9 like a slot machine effect.
class AnimatedBalance extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;

  const AnimatedBalance({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedBalance> createState() => _AnimatedBalanceState();
}

class _AnimatedBalanceState extends State<AnimatedBalance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  String _oldText = '';

  @override
  void initState() {
    super.initState();
    _oldText = widget.text;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(AnimatedBalance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _oldText = oldWidget.text;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        // Decorative roll/count transition: jump straight to the final value.
        _controller.value = 1.0;
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
      animation: _animation,
      builder: (context, child) {
        return _buildAnimatedText();
      },
    );
  }

  Widget _buildAnimatedText() {
    final oldNum = _extractNumber(_oldText);
    final newNum = _extractNumber(widget.text);

    // If both parseable, animate numerically
    if (oldNum != null && newNum != null) {
      final current = oldNum + (newNum - oldNum) * _animation.value;
      final formatted = _formatLike(current, widget.text);
      return Text(
        formatted,
        style: widget.style ?? _defaultStyle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Otherwise, crossfade the text
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : widget.duration,
      child: Text(
        widget.text,
        key: ValueKey(widget.text),
        style: widget.style ?? _defaultStyle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Detect whether the template uses European-style separators
  /// (. for thousands, , for decimal) by checking if the last separator is a comma.
  bool _isInvertedSeparator(String text) {
    final digitPart = text.replaceAll(RegExp(r'[^\d.,]'), '');
    final lastComma = digitPart.lastIndexOf(',');
    final lastDot = digitPart.lastIndexOf('.');
    // If comma appears after the last dot, it's the decimal separator (European)
    return lastComma > lastDot && lastComma != -1;
  }

  double? _extractNumber(String text) {
    // Remove common currency symbols, thin spaces, and formatting, keep digits, dots, commas, minus
    final cleaned = text.replaceAll(RegExp(r'[^\d.,\-]'), '');
    if (cleaned.isEmpty) return null;

    if (_isInvertedSeparator(text)) {
      // European: 1.234,56 → remove group dots, replace decimal comma with dot
      final normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(normalized);
    } else {
      // US/standard: 1,234.56 → remove group commas
      final normalized = cleaned.replaceAll(',', '');
      return double.tryParse(normalized);
    }
  }

  String _formatLike(double value, String template) {
    final inverted = _isInvertedSeparator(template);

    // Detect if template uses integer format (sats) or decimal format (BTC/fiat)
    final String decimalSep = inverted ? ',' : '.';
    final hasDecimal = template.contains(decimalSep) &&
        template.indexOf(decimalSep) < template.length - 1 &&
        RegExp(r'\d').hasMatch(template.substring(template.lastIndexOf(decimalSep)));

    if (!hasDecimal) {
      // Integer format (sats) — format with group separators
      final intVal = value.round();
      return _formatWithGrouping(intVal, template, inverted);
    }

    // Decimal format (BTC/fiat) — match decimal places from template
    final parts = template.split(decimalSep);
    final templateDecPart = parts.length > 1 ? parts.last : '';
    final decimalPlaces = templateDecPart.replaceAll(RegExp(r'[^\d]'), '').length;

    // Format the number
    final absFormatted = value.abs().toStringAsFixed(decimalPlaces > 0 ? decimalPlaces : 2);
    final numParts = absFormatted.split('.');
    final intPart = numParts[0];
    var decPart = numParts.length > 1 ? numParts[1] : '';

    // Add thin-space grouping to decimal part if template has it (e.g. BTC: "00 000 000")
    if (templateDecPart.contains('\u{2009}') && decPart.length > 2) {
      final buffer = StringBuffer();
      buffer.write(decPart.substring(0, 2));
      for (var i = 2; i < decPart.length; i++) {
        if ((i - 2) % 3 == 0) buffer.write('\u{2009}');
        buffer.write(decPart[i]);
      }
      decPart = buffer.toString();
    }

    // Add group separators to integer part
    final groupSep = inverted ? '.' : ',';
    final groupedInt = _addGroupSeparator(intPart, groupSep);

    final prefix = _extractPrefix(template);
    final suffix = _extractSuffix(template);
    final sign = value < 0 ? '-' : '';
    return '$prefix$sign$groupedInt$decimalSep$decPart$suffix';
  }

  String _formatWithGrouping(int value, String template, bool inverted) {
    final str = value.abs().toString();
    final groupSep = inverted ? '.' : ',';
    final grouped = _addGroupSeparator(str, groupSep);
    final prefix = _extractPrefix(template);
    final suffix = _extractSuffix(template);
    final sign = value < 0 ? '-' : '';
    return '$prefix$sign$grouped$suffix';
  }

  String _addGroupSeparator(String digits, String separator) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String _extractPrefix(String text) {
    final match = RegExp(r'^[^\d\-]*').firstMatch(text);
    return match?.group(0) ?? '';
  }

  String _extractSuffix(String text) {
    final match = RegExp(r'[^\d]*$').firstMatch(text);
    return match?.group(0) ?? '';
  }

  TextStyle _defaultStyle() {
    return TextStyle(
      color: Colors.white,
      fontSize: 34.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      height: 1.0,
    );
  }
}

/// Animated number that counts from 0 to the target value.
/// Used when a balance is first received.
class CountUpBalance extends StatefulWidget {
  final int targetSats;
  final String Function(int) formatter;
  final TextStyle? style;
  final Duration duration;

  const CountUpBalance({
    super.key,
    required this.targetSats,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<CountUpBalance> createState() => _CountUpBalanceState();
}

class _CountUpBalanceState extends State<CountUpBalance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _previousTarget = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutExpo,
    );
    // Decorative count-up: only run it when motion is allowed. MediaQuery is
    // not reliably available in initState, so defer the start to the first
    // frame where we can read reduce-motion safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void didUpdateWidget(CountUpBalance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetSats != widget.targetSats) {
      _previousTarget = oldWidget.targetSats;
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final value = _previousTarget +
            (widget.targetSats - _previousTarget) * _animation.value;
        return Text(
          widget.formatter(value.round()),
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
