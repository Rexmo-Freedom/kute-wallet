// Source scanning helpers shared by architecture-style tests.

/// Removes `//` line comments and `/* */` block comments, keeping string
/// literals intact.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (quote != null) {
      out.write(c);
      if (c == r'\' && i + 1 < source.length) {
        out.write(next);
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    if (c == "'" || c == '"') quote = c;
    out.write(c);
    i++;
  }
  return out.toString();
}
