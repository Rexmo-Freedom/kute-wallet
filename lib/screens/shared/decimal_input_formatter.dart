import 'package:flutter/services.dart';

/// Text input formatter for decimal amount fields that tolerates both `,`
/// and `.` as the decimal separator. iOS shows whichever one matches the
/// user's system locale — EU locales get a comma on the numeric keyboard
/// and no way to type a period — so a regex that only allows `.` silently
/// rejects every keystroke. This formatter normalizes commas to periods
/// before validating, so the field accepts either typed character and the
/// text that reaches the controller is always period-delimited (parseable
/// by `double.tryParse`).
class DecimalInputFormatter extends TextInputFormatter {
  final int fractionDigits;

  const DecimalInputFormatter({this.fractionDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final normalized = newValue.text.replaceAll(',', '.');
    final pattern = fractionDigits > 0
        ? RegExp('^\\d*\\.?\\d{0,$fractionDigits}\$')
        : RegExp(r'^\d*$');
    if (!pattern.hasMatch(normalized)) return oldValue;

    // Preserve cursor position. Normalizing `,` to `.` is a 1:1 char swap
    // so offsets line up without adjustment.
    final offset = newValue.selection.baseOffset.clamp(0, normalized.length);
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: offset.toInt()),
      composing: TextRange.empty,
    );
  }
}
