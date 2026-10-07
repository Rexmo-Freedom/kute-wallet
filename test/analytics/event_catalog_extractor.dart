// Static extraction of every PostHog event name the app can send.
//
// Pure `dart:io` text scanning (no analyzer, no Flutter bindings) so the
// drift test stays fast and `tool/analytics_events.dart` can reuse it.
//
// What counts as an emitting call:
//   * `TrackingService.track('name', ...)` anywhere in lib/, and bare
//     `track(` inside tracking_service.dart. A ternary of literals
//     (`ok ? 'a_done' : 'a_failed'`) contributes every literal.
//   * The money-flow helpers: `<flow>_started` / `_step` / `_submitted` /
//     `_failed` / `_abandoned`, with the `event:` / `abandonEvent:`
//     overrides that `moneyFlowStarted` and `moneyFlowSubmitted` accept.
//   * `VenueAnalytics.settingChanged('name', ...)`.
//   * `LatencyTracker` (lib/services/tracking/latency_tracker.dart)
//     forwards `track(event, …)` for the duration events it measures; the
//     event names are the `static const` strings of its `LatencyKeys`
//     class, which count as sent.
//
// Events sent from a TrackingService helper count only when the helper
// is reachable: referenced as `TrackingService.<helper>` outside the
// service, or called (transitively) from such a helper. A helper nobody
// calls cannot send anything, so its events stay out of the catalog.
//
// A bare identifier argument resolves through a same-file
// `const String name = '...'` (e.g. `MoveFlowOutcome.flow`). Anything
// else the scanner cannot resolve is reported in [CatalogScan.unresolved]
// and fails the test: keep event names static so they can be catalogued.

import 'dart:io';

const String trackingServicePath = 'lib/services/tracking_service.dart';
const String latencyTrackerPath = 'lib/services/tracking/latency_tracker.dart';

/// The money-flow helpers and the suffix each one appends to the flow.
const Map<String, String> moneyFlowSuffix = {
  'moneyFlowStarted': '_started',
  'moneyFlowStep': '_step',
  'moneyFlowSubmitted': '_submitted',
  'moneyFlowFailed': '_failed',
  'moneyFlowAbandoned': '_abandoned',
};

class CatalogScan {
  /// Every event name the app can send, sorted.
  final Set<String> events = {};

  /// Every literal property key passed to an emitting call (any nesting).
  final Set<String> propertyKeys = {};

  /// `file:line: expr` for event-name arguments the scanner cannot resolve.
  final List<String> unresolved = [];

  /// Keys `TrackingService.sanitizeParams` replaces with a one-way
  /// reference (`_orderRefKeys`), read from the service source.
  final Set<String> orderRefKeys = {};

  int filesScanned = 0;
  int callsSeen = 0;
}

/// Scans every `.dart` file under [lib] (default `lib/` in the current
/// directory, which is the package root under `flutter test`).
CatalogScan scanAnalyticsEvents({Directory? lib}) {
  final root = lib ?? Directory('lib');
  final scan = CatalogScan();
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final calls = <_Call>[];
  String? serviceSource;
  final otherSources = StringBuffer();
  for (final file in files) {
    final rel = _relative(file.path, root.parent.path);
    final source = stripCommentsKeepingLines(file.readAsStringSync());
    scan.filesScanned++;
    if (rel == trackingServicePath) {
      serviceSource = source;
    } else {
      otherSources.write(source);
    }
    if (rel == latencyTrackerPath) {
      scan.events.addAll(_latencyKeys(source));
    }
    calls.addAll(_findCalls(rel, source));
  }
  scan.callsSeen = calls.length;

  final reachable = serviceSource == null
      ? const <String>{}
      : _reachableHelpers(serviceSource, otherSources.toString());
  if (serviceSource != null) {
    scan.orderRefKeys.addAll(_orderRefKeys(serviceSource));
  }

  // First pass: money-flow overrides registered by `moneyFlowStarted`.
  final abandonOverrides = <String, Set<String>>{};
  for (final c in calls) {
    if (c.helper != 'moneyFlowStarted') continue;
    final flow = c.literalArg(0);
    if (flow == null) continue;
    final overrides = abandonOverrides.putIfAbsent(flow, () => {});
    overrides.add(c.namedLiteral('abandonEvent') ?? '${flow}_abandoned');
  }

  for (final c in calls) {
    if (c.file == trackingServicePath) {
      // Money-flow bodies build `'${flow}_x'`: expanded from call sites.
      if (moneyFlowSuffix.containsKey(c.enclosingMethod)) continue;
      if (c.enclosingMethod != null && !reachable.contains(c.enclosingMethod)) {
        continue;
      }
    }
    for (final key in _propertyKeys(c.argsText)) {
      scan.propertyKeys.add(key);
    }
    if (c.helper == 'track' || c.helper == 'settingChanged') {
      if (c.file == 'lib/services/venue_analytics.dart' &&
          c.helper == 'track' &&
          c.args.first.trim() == 'event') {
        continue; // settingChanged's forwarding call; expanded from sites.
      }
      if (c.file == latencyTrackerPath &&
          c.helper == 'track' &&
          c.args.first.trim() == 'event') {
        continue; // LatencyTracker.record's forwarding call; see LatencyKeys.
      }
      final names = c.eventLiterals(0);
      if (names == null) {
        scan.unresolved.add('${c.file}:${c.line}: ${c.args.first}');
      } else {
        scan.events.addAll(names);
      }
      continue;
    }
    final flow = c.literalArg(0);
    if (flow == null) {
      scan.unresolved.add('${c.file}:${c.line}: ${c.args.first}');
      continue;
    }
    switch (c.helper) {
      case 'moneyFlowStarted':
        scan.events.add(c.namedLiteral('event') ?? '${flow}_started');
      case 'moneyFlowSubmitted':
        scan.events.add(c.namedLiteral('event') ?? '${flow}_submitted');
      case 'moneyFlowAbandoned':
        scan.events.addAll(abandonOverrides[flow] ?? {'${flow}_abandoned'});
      default:
        scan.events.add('$flow${moneyFlowSuffix[c.helper]}');
    }
  }
  return scan;
}

/// Raw-value property keys. Categorical keys built on the same words
/// (`address_type`, `has_address`, `invoice_type`) are fine: only a key
/// that IS the value's name, or ends in an unambiguous secret suffix,
/// is flagged. The `_orderRefKeys` the service hashes are exempt.
final RegExp forbiddenExactKey =
    RegExp(r'^(xpub|xprv|ypub|zpub|seed|seed_phrase|seed_words|mnemonic|'
        r'private_key|privkey|secret|address|from_address|to_address|'
        r'destination_address|invoice|bolt11|txid|tx_hash|tx_id|order_id|'
        r'provider_order_id|quote_id|claim_id|payment_hash|preimage|token|'
        r'api_key|email|phone)$');
final RegExp forbiddenSuffixKey =
    RegExp(r'_(xpub|xprv|mnemonic|seed_phrase|private_key|privkey|txid|tx_hash|'
        r'payment_hash|preimage|secret|api_key)$');

/// Keys whose suffix looks raw but that carry a count, never a value.
const Set<String> allowedRawLookingKeys = {'wallets_without_address'};

bool isForbiddenKey(String key, {Set<String> hashedKeys = const {}}) {
  if (hashedKeys.contains(key) || allowedRawLookingKeys.contains(key)) {
    return false;
  }
  return forbiddenExactKey.hasMatch(key) || forbiddenSuffixKey.hasMatch(key);
}

// ---------------------------------------------------------------------------
// Scanning internals.

class _Call {
  _Call(this.file, this.line, this.helper, this.enclosingMethod, this.args,
      this.argsText, this.source);
  final String file;
  final int line;
  final String helper;
  final String? enclosingMethod;
  final List<String> args;
  final String argsText;
  final String source;

  /// The positional argument [i] as a plain literal (or a same-file const).
  String? literalArg(int i) {
    if (i >= args.length) return null;
    return _resolveLiteral(args[i].trim(), source);
  }

  String? namedLiteral(String name) {
    for (final a in args) {
      final t = a.trim();
      if (t.startsWith('$name:')) {
        return _resolveLiteral(t.substring(name.length + 1).trim(), source);
      }
    }
    return null;
  }

  /// Every event literal an argument can evaluate to, or null when it
  /// cannot be resolved statically.
  Set<String>? eventLiterals(int i) =>
      i < args.length ? _branchLiterals(args[i], source) : null;
}

/// Literals of `expr` when it is a literal, a same-file const, or a
/// ternary / `??` chain whose branches all are (the condition of a
/// ternary is ignored, so `flow == 'receive' ? 'a' : 'b'` yields a, b).
Set<String>? _branchLiterals(String expr, String source) {
  var e = expr.trim();
  while (e.startsWith('(') && _matchingClose(e, 0) == e.length - 1) {
    e = e.substring(1, e.length - 1).trim();
  }
  final single = _resolveLiteral(e, source);
  if (single != null) return {single};
  final q = _topLevelIndex(e, '?');
  if (q >= 0) {
    // The `:` that closes this ternary, past any nested ones.
    var depth = 1;
    var i = q + 1;
    var colon = -1;
    while (i < e.length) {
      final t = _topLevelIndex(e, '?', from: i);
      final c = _topLevelIndex(e, ':', from: i);
      if (c < 0) break;
      if (t >= 0 && t < c) {
        depth++;
        i = t + 1;
        continue;
      }
      depth--;
      if (depth == 0) {
        colon = c;
        break;
      }
      i = c + 1;
    }
    if (colon < 0) return null;
    final then = _branchLiterals(e.substring(q + 1, colon), source);
    final orElse = _branchLiterals(e.substring(colon + 1), source);
    if (then == null || orElse == null) return null;
    return {...then, ...orElse};
  }
  final n = _topLevelIndex(e, '??');
  if (n >= 0) {
    final left = _branchLiterals(e.substring(0, n), source);
    final right = _branchLiterals(e.substring(n + 2), source);
    if (left == null || right == null) return null;
    return {...left, ...right};
  }
  return null;
}

/// Index of [token] outside strings and brackets, or -1. A lone `?` is
/// the ternary operator only (not `??`, `?.` or `?[`).
int _topLevelIndex(String s, String token, {int from = 0}) {
  var depth = 0;
  var i = from;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || (c == 'r' && _quoteAt(s, i + 1))) {
      i = _skipString(s, i);
      continue;
    }
    if (_openers.containsKey(c)) depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (depth == 0 && s.startsWith(token, i)) {
      if (token == '?') {
        final next = i + 1 < s.length ? s[i + 1] : '';
        final prev = i > 0 ? s[i - 1] : '';
        if (next == '?' || next == '.' || next == '[' || prev == '?') {
          i += next == '?' ? 2 : 1;
          continue;
        }
      }
      return i;
    }
    i++;
  }
  return -1;
}

final RegExp _plainLiteral =
    RegExp(r'''(?<![\w])r?'([^'$\\\n]*)'|"([^"$\\\n]*)"''');

Set<String> _plainLiterals(String expr) => {
      for (final m in _plainLiteral.allMatches(expr)) m.group(1) ?? m.group(2)!,
    };

String? _resolveLiteral(String expr, String source) {
  final m = RegExp(r'''^r?'([^'$\\]*)'$|^r?"([^"$\\]*)"$''').firstMatch(expr);
  if (m != null) return m.group(1) ?? m.group(2);
  if (RegExp(r'^[A-Za-z_]\w*$').hasMatch(expr)) {
    final c = RegExp(r'''\bconst\s+(?:String\s+)?''' +
            RegExp.escape(expr) +
            r'''\s*=\s*(?:'([^'$\\]*)'|"([^"$\\]*)")\s*;''')
        .firstMatch(source);
    if (c != null) return c.group(1) ?? c.group(2);
  }
  return null;
}

final RegExp _keyPattern = RegExp(r'''(?<![\w])'([^'$\\\n]+)'\s*:(?!:)''');

/// Map keys at any nesting: a literal followed by `:` that opens an entry
/// (after `{`, `,` or a collection-`if`/`for` header), so the `:` of a
/// ternary value (`'k': a ? 'x' : 'y'`) does not make `'x'` a key.
Iterable<String> _propertyKeys(String argsText) sync* {
  for (final m in _keyPattern.allMatches(argsText)) {
    var i = m.start - 1;
    while (i >= 0 && (argsText[i] == ' ' || argsText[i] == '\n')) {
      i--;
    }
    if (i < 0) continue;
    final prev = argsText[i];
    if (prev == '{' || prev == ',' || prev == ')') yield m.group(1)!;
  }
}

final RegExp _callPattern = RegExp(r'\b(TrackingService\.|VenueAnalytics\.)?'
    r'(track|moneyFlowStarted|moneyFlowStep|moneyFlowSubmitted|'
    r'moneyFlowFailed|moneyFlowAbandoned|settingChanged)\s*\(');

List<_Call> _findCalls(String file, String source) {
  final calls = <_Call>[];
  final isService = file == trackingServicePath;
  final isVenue = file == 'lib/services/venue_analytics.dart';
  final methodStarts = isService ? _staticMethodStarts(source) : null;
  for (final m in _callPattern.allMatches(source)) {
    final qualifier = m.group(1);
    final helper = m.group(2)!;
    if (qualifier == null && !isService && !(isVenue && helper == 'track')) {
      continue;
    }
    if (qualifier == 'VenueAnalytics.' && helper != 'settingChanged') continue;
    if (qualifier == 'TrackingService.' && helper == 'settingChanged') continue;
    // Skip the declaration itself (`static void track(`).
    final before = source.substring(m.start < 40 ? 0 : m.start - 40, m.start);
    if (RegExp(r'\b(void|bool|Future<void>)\s+$').hasMatch(before)) continue;
    final open = m.end - 1;
    final close = _matchingClose(source, open);
    if (close < 0) continue;
    final argsText = source.substring(open + 1, close);
    final args = _splitTopLevel(argsText);
    if (args.isEmpty) continue;
    final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
    String? enclosing;
    if (methodStarts != null) {
      for (final s in methodStarts) {
        if (s.offset > m.start) break;
        enclosing = s.name;
      }
    }
    calls.add(_Call(file, line, helper, enclosing, args, argsText, source));
  }
  return calls;
}

class _MethodStart {
  _MethodStart(this.offset, this.name);
  final int offset;
  final String name;
}

final RegExp _staticMethod =
    RegExp(r'^  static [^=(\n]*?\b(\w+)\s*\(', multiLine: true);

List<_MethodStart> _staticMethodStarts(String source) => [
      for (final m in _staticMethod.allMatches(source))
        _MethodStart(m.start, m.group(1)!),
    ];

/// TrackingService static methods that can run: referenced from outside
/// the service, or called from another reachable method.
Set<String> _reachableHelpers(String service, String others) {
  final starts = _staticMethodStarts(service);
  final bodies = <String, StringBuffer>{};
  for (var i = 0; i < starts.length; i++) {
    final end = i + 1 < starts.length ? starts[i + 1].offset : service.length;
    bodies
        .putIfAbsent(starts[i].name, StringBuffer.new)
        .write(service.substring(starts[i].offset, end));
  }
  final reachable = <String>{
    for (final m in RegExp(r'\bTrackingService\.(\w+)').allMatches(others))
      if (bodies.containsKey(m.group(1))) m.group(1)!,
  };
  var changed = true;
  while (changed) {
    changed = false;
    for (final name in reachable.toList()) {
      final body = bodies[name]!.toString();
      for (final other in bodies.keys) {
        if (reachable.contains(other)) continue;
        if (RegExp('\\b${RegExp.escape(other)}\\s*\\(').hasMatch(body)) {
          reachable.add(other);
          changed = true;
        }
      }
    }
  }
  return reachable;
}

Set<String> _orderRefKeys(String service) {
  final m = RegExp(r'_orderRefKeys\s*=\s*\{([^}]*)\}').firstMatch(service);
  if (m == null) return {};
  return _plainLiterals(m.group(1)!);
}

/// The `static const name = '...'` strings declared in the `LatencyKeys`
/// class: every duration event `LatencyTracker` can forward.
Set<String> _latencyKeys(String source) {
  final start = source.indexOf(RegExp(r'class\s+LatencyKeys\b'));
  if (start < 0) return {};
  final open = source.indexOf('{', start);
  if (open < 0) return {};
  final close = _matchingClose(source, open);
  if (close < 0) return {};
  final body = source.substring(open + 1, close);
  return {
    for (final m in RegExp(r'''static\s+const\s+(?:String\s+)?\w+\s*=\s*'([^'$\\]+)'\s*;''')
        .allMatches(body))
      m.group(1)!,
  };
}

String _relative(String path, String root) {
  final r = root.endsWith('/') ? root : '$root/';
  return path.startsWith(r) ? path.substring(r.length) : path;
}

// ---------------------------------------------------------------------------
// Lexing helpers: strings (with `${}` nesting), comments, brackets.

/// Replaces `//` and `/* */` comments with spaces, keeping every newline
/// so line numbers survive. String literals (including interpolations
/// that contain nested strings) are left untouched.
String stripCommentsKeepingLines(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"' || (c == 'r' && _quoteAt(source, i + 1))) {
      final end = _skipString(source, i);
      out.write(source.substring(i, end));
      i = end;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? source.length : end + 2;
      for (; i < stop; i++) {
        out.write(source[i] == '\n' ? '\n' : ' ');
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

bool _quoteAt(String s, int i) => i < s.length && (s[i] == "'" || s[i] == '"');

/// Index just past the string literal starting at [start] (`r`, triple
/// quotes, escapes and `${...}` with nested strings all handled).
int _skipString(String s, int start) {
  var i = start;
  final raw = s[i] == 'r';
  if (raw) i++;
  final q = s[i];
  final triple = s.startsWith(q * 3, i);
  i += triple ? 3 : 1;
  while (i < s.length) {
    final c = s[i];
    if (!raw && c == r'\') {
      i += 2;
      continue;
    }
    if (!raw && c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
      i = _skipBraces(s, i + 1) + 1;
      continue;
    }
    if (triple ? s.startsWith(q * 3, i) : c == q) {
      return i + (triple ? 3 : 1);
    }
    if (!triple && c == '\n') return i; // unterminated: stop at line end
    i++;
  }
  return s.length;
}

/// Index of the `}` matching the `{` at [open], skipping nested strings.
int _skipBraces(String s, int open) {
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || (c == 'r' && _quoteAt(s, i + 1))) {
      i = _skipString(s, i);
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return s.length - 1;
}

const _openers = {'(': ')', '[': ']', '{': '}'};

/// Index of the bracket matching the opener at [open], or -1.
int _matchingClose(String s, int open) {
  final stack = <String>[_openers[s[open]]!];
  var i = open + 1;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || (c == 'r' && _quoteAt(s, i + 1))) {
      i = _skipString(s, i);
      continue;
    }
    if (_openers.containsKey(c)) {
      stack.add(_openers[c]!);
    } else if (c == ')' || c == ']' || c == '}') {
      if (stack.removeLast() != c) return -1;
      if (stack.isEmpty) return i;
    }
    i++;
  }
  return -1;
}

/// Splits an argument list on top-level commas.
List<String> _splitTopLevel(String s) {
  final parts = <String>[];
  final current = StringBuffer();
  var depth = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || (c == 'r' && _quoteAt(s, i + 1))) {
      final end = _skipString(s, i);
      current.write(s.substring(i, end));
      i = end;
      continue;
    }
    if (_openers.containsKey(c)) depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      parts.add(current.toString());
      current.clear();
    } else {
      current.write(c);
    }
    i++;
  }
  if (current.toString().trim().isNotEmpty) parts.add(current.toString());
  return [for (final p in parts) p.trim()];
}
