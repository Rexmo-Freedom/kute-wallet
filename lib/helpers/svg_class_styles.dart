// lib/helpers/svg_class_styles.dart
//
// Inlines CSS class rules into an SVG as presentation attributes.
//
// flutter_svg does not apply CSS selectors, so a logo exported the way
// Illustrator exports one,
//
//   <style>.cls-1{fill:url(#g)}</style> … <path class="cls-1" …/>
//
// loses every fill it declares and falls back to the default, which is
// solid black. Zcash ships exactly that file, and since its first path
// is the full disc, the whole mark came through as a black circle.
//
// This rewrites the simple single-declaration rules those exports use
// into attributes flutter_svg does honour. Anything it cannot read in
// full is left alone, so a file it does not understand renders exactly
// as it did before rather than worse.

/// Properties safe to move from a CSS rule onto the element. Layout and
/// transform properties are deliberately absent: they do not mean the
/// same thing as attributes and moving them would change the drawing.
const Set<String> _inlineableProperties = {
  'fill',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-dasharray',
  'opacity',
  'fill-opacity',
  'stroke-opacity',
  'fill-rule',
  'clip-rule',
};

final RegExp _styleBlock =
    RegExp(r'<style[^>]*>([\s\S]*?)</style>', caseSensitive: false);
final RegExp _classRule = RegExp(r'\.([A-Za-z_][\w-]*)\s*\{([^}]*)\}');
final RegExp _openTag = RegExp(r'<[A-Za-z][^>]*>');
final RegExp _classAttribute =
    RegExp(r'''\sclass\s*=\s*(?:"([^"]*)"|'([^']*)')''');

/// Returns [svg] with its CSS class fills written onto the elements that
/// carry those classes. Returns the input unchanged when there is no
/// style block, no rule it can read, or no element using one.
String inlineSvgClassStyles(String svg) {
  final rules = <String, Map<String, String>>{};
  for (final block in _styleBlock.allMatches(svg)) {
    for (final rule in _classRule.allMatches(block.group(1)!)) {
      final declarations = <String, String>{};
      for (final part in rule.group(2)!.split(';')) {
        final colon = part.indexOf(':');
        if (colon <= 0) continue;
        final property = part.substring(0, colon).trim().toLowerCase();
        final value = part.substring(colon + 1).trim();
        if (value.isEmpty || !_inlineableProperties.contains(property)) {
          continue;
        }
        declarations[property] = value;
      }
      if (declarations.isNotEmpty) {
        rules.putIfAbsent(rule.group(1)!, () => <String, String>{})
          ..addAll(declarations);
      }
    }
  }
  if (rules.isEmpty) return svg;

  return svg.replaceAllMapped(_openTag, (match) {
    var tag = match.group(0)!;
    final classMatch = _classAttribute.firstMatch(tag);
    if (classMatch == null) return tag;
    final names = (classMatch.group(1) ?? classMatch.group(2) ?? '')
        .trim()
        .split(RegExp(r'\s+'));
    final declarations = <String, String>{};
    for (final name in names) {
      final rule = rules[name];
      if (rule != null) declarations.addAll(rule);
    }
    if (declarations.isEmpty) return tag;
    // A stylesheet outranks a presentation attribute, so drop any
    // attribute the rule replaces rather than leaving the element with
    // the property declared twice.
    for (final property in declarations.keys) {
      tag = tag.replaceAll(
        RegExp('''\\s$property\\s*=\\s*(?:"[^"]*"|'[^']*')''',
            caseSensitive: false),
        '',
      );
    }
    final attributes =
        declarations.entries.map((e) => '${e.key}="${e.value}"').join(' ');
    final close = tag.endsWith('/>') ? '/>' : '>';
    final head = tag.substring(0, tag.length - close.length).trimRight();
    return '$head $attributes$close';
  });
}

final RegExp _clipPathBlock = RegExp(
    r'<clipPath\b([^>]*)>([\s\S]*?)</clipPath>',
    caseSensitive: false);
final RegExp _idAttribute = RegExp(r'''\sid\s*=\s*(?:"([^"]*)"|'([^']*)')''');
final RegExp _tagName = RegExp(r'<\s*([A-Za-z][\w:-]*)');

/// Removes clip paths that are nothing but a bounding box around the
/// artwork, and the `clip-path` attributes pointing at them.
///
/// Design tools export these as a crop frame, usually a single `<rect>`
/// carrying a `transform`. flutter_svg does not apply that transform, so
/// it clips to the wrong region and most of the mark disappears: Meta's
/// logo came through as one small arc of its loop, because the frame
/// landed at the origin instead of over the artwork.
///
/// Only a clip path whose entire content is ONE rect is dropped. That is
/// the exporter artifact, and the drawing already sits inside it, so
/// removing it changes nothing except that the whole mark renders. A
/// clip path that actually shapes the drawing has more than one child,
/// or a non-rect child, and is left exactly as it is.
String dropBoundingBoxClipPaths(String svg) {
  final droppable = <String>{};
  for (final block in _clipPathBlock.allMatches(svg)) {
    final attrs = block.group(1) ?? '';
    final id = _idAttribute.firstMatch(attrs);
    final name = id?.group(1) ?? id?.group(2);
    if (name == null || name.isEmpty) continue;
    final children =
        _tagName.allMatches(block.group(2) ?? '').map((m) => m.group(1)!);
    if (children.length == 1 && children.first.toLowerCase() == 'rect') {
      droppable.add(name);
    }
  }
  if (droppable.isEmpty) return svg;

  var out = svg;
  for (final id in droppable) {
    out = out.replaceAll(
      RegExp('''\\sclip-path\\s*=\\s*(?:"url\\(#$id\\)"|'url\\(#$id\\)')''',
          caseSensitive: false),
      '',
    );
  }
  // Leave the definitions in place: nothing references them now, and
  // rewriting defs risks disturbing the gradients sitting beside them.
  return out;
}
