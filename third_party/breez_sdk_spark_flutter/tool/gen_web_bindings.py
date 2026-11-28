#!/usr/bin/env python3
"""Generates lib/src/web/convert.g.dart and lib/src/web/sdk_web.g.dart.

Reads the flutter_rust_bridge Dart models (lib/src/rust/{models,errors,events,
logger}.dart), the BreezSdk interface (lib/src/rust/sdk.dart) and the
TypeScript definitions of the official wasm build
(@breeztech/breez-sdk-spark, web/breez_sdk_spark_wasm.d.ts), and emits Dart
converters between the FRB model classes and the plain JS values the wasm SDK
takes and returns.

Conventions shared by both sides (serde rename_all = camelCase, tag = "type"):
  * struct field `fooBar`           <-> JS property `fooBar`
  * Dart enum value `fooBar`        <-> JS string "fooBar"
  * sealed variant `.foo({a, b})`   <-> JS `{type: "foo", a, b}`
  * sealed variant `.foo(Inner x)`  <-> JS `{type: "foo", ...inner}`
  * u64/u128 (Dart BigInt)          <-> JS number | bigint | string, per the d.ts
  * Vec<u8> (Dart Uint8List)        <-> JS Uint8Array | number[], per the d.ts

Usage: python3 tool/gen_web_bindings.py path/to/breez_sdk_spark_wasm.d.ts && dart format -l 110 lib/src/web
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUST = os.path.join(ROOT, 'lib', 'src', 'rust')
OUT = os.path.join(ROOT, 'lib', 'src', 'web')

# Types that are never exchanged as data with the wasm SDK (errors are JS
# Error strings and are parsed by hand in errors_web.dart).
SKIP = {'SdkError', 'PasskeyError', 'PrfProviderError', 'SignerError', 'ParseError',
        'ChainServiceError', 'StorageError', 'ServiceConnectivityError'}

warnings = []


def warn(msg):
    warnings.append(msg)


# --------------------------------------------------------------------------
# Dart parsing
# --------------------------------------------------------------------------

def strip_comments(src):
    return '\n'.join(l for l in src.split('\n') if not l.strip().startswith('//'))


def split_top(s, sep=','):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '<({[':
            depth += 1
        elif ch in '>)}]':
            depth -= 1
        if ch == sep and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out if x.strip()]


def parse_params(params):
    """'{required T a, U? b}' or 'T field0' -> [(type, name, positional)]"""
    params = params.strip()
    res = []
    if not params:
        return res
    named = params.startswith('{')
    body = params.strip('{}').strip()
    for p in split_top(body):
        p = re.sub(r'^required\s+', '', p)
        p = re.sub(r'^@\w+\s+', '', p)
        m = re.match(r'^(.*\S)\s+(\w+)$', p)
        if not m:
            raise Exception('cannot parse param %r' % p)
        res.append((m.group(1).strip(), m.group(2), not named))
    return res


classes = {}   # name -> [(type, name)]
sealed = {}    # name -> [(variant, implClass, [(type, name, positional)])]
enums = {}     # name -> [values]


def parse_dart(path):
    src = strip_comments(open(path).read())
    # enums
    for m in re.finditer(r'^enum (\w+) \{([^}]*)\}', src, re.M):
        vals = [v.strip() for v in m.group(2).split(';')[0].split(',') if v.strip()]
        enums[m.group(1)] = vals
    # plain classes
    for m in re.finditer(r'^class (\w+) \{\n(.*?)^\}', src, re.M | re.S):
        name, body = m.group(1), m.group(2)
        fields = []
        for fm in re.finditer(r'^  final (.+?) (\w+);', body, re.M):
            fields.append((fm.group(1), fm.group(2)))
        classes[name] = fields
    # sealed (freezed) classes
    for m in re.finditer(r'^sealed class (\w+) with .*?\{\n(.*?)^\}', src, re.M | re.S):
        name, body = m.group(1), m.group(2)
        variants = []
        body1 = re.sub(r'\s+', ' ', body)
        for vm in re.finditer(r'const factory (\w+)\.(\w+)\((.*?)\) = (\w+);', body1):
            assert vm.group(1) == name
            variants.append((vm.group(2), vm.group(4), parse_params(vm.group(3))))
        sealed[name] = variants


for f in ['models.dart', 'errors.dart', 'events.dart', 'logger.dart']:
    parse_dart(os.path.join(RUST, f))

# --------------------------------------------------------------------------
# TypeScript parsing
# --------------------------------------------------------------------------

ts_ifaces = {}   # name -> {field: tstype}
ts_unions = {}   # name -> {variant: ('fields', {f: t}) | ('flat', Inner) | ('lit', None)}
ts_class_methods = {}  # class -> {method: (params_str, return_type)}


def parse_ts(path):
    src = open(path).read()
    for m in re.finditer(r'^export interface (\w+) \{\n(.*?)^\}', src, re.M | re.S):
        fields = {}
        for fm in re.finditer(r'^    (\w+)(\??): (.+);$', m.group(2), re.M):
            t = fm.group(3)
            if fm.group(2):
                t += ' | undefined'
            fields[fm.group(1)] = t
        ts_ifaces[m.group(1)] = fields
    for m in re.finditer(r'^export interface (\w+) \{\}$', src, re.M):
        ts_ifaces[m.group(1)] = {}
    for m in re.finditer(r'^export type (\w+) = (.+);$', src, re.M):
        name, body = m.group(1), m.group(2)
        members = split_top(body, '|')
        variants = {}
        for mem in members:
            mem = mem.strip()
            lit = re.match(r'^"(\w+)"$', mem)
            if lit:
                variants[lit.group(1)] = ('lit', None)
                continue
            flat = re.match(r'^\(\{ type: "(\w+)" \} & (.+)\)$', mem)
            if flat:
                variants[flat.group(1)] = ('flat', flat.group(2).strip())
                continue
            obj = re.match(r'^\{ type: "(\w+)"(.*)\}$', mem)
            if obj:
                fields = {}
                for part in split_top(obj.group(2), ';'):
                    fm = re.match(r'^(\w+)(\??): (.+)$', part.strip())
                    if fm:
                        t = fm.group(3).strip()
                        if fm.group(2):
                            t += ' | undefined'
                        fields[fm.group(1)] = t
                variants[obj.group(1)] = ('fields', fields)
                continue
        ts_unions[name] = variants
    for m in re.finditer(r'^export class (\w+) \{\n(.*?)^\}', src, re.M | re.S):
        meths = {}
        for mm in re.finditer(r'^    (?:static )?(\w+)\((.*)\): (.+);$', m.group(2), re.M):
            meths[mm.group(1)] = (mm.group(2), mm.group(3))
        ts_class_methods[m.group(1)] = meths


parse_ts(sys.argv[1])

# --------------------------------------------------------------------------
# Conversion expressions
# --------------------------------------------------------------------------


def ts_clean(t):
    if t is None:
        return None
    t = t.strip()
    parts = [p for p in split_top(t, '|') if p not in ('undefined', 'null')]
    t = ' | '.join(parts)
    if t.startswith('(') and t.endswith(')'):
        t = t[1:-1]
    return t


def ts_elem(t):
    t = ts_clean(t)
    if t is None:
        return None
    if t.endswith('[]'):
        return ts_clean(t[:-2])
    m = re.match(r'^Array<(.+)>$', t)
    if m:
        return m.group(1)
    return None


def ts_map_value(t):
    t = ts_clean(t)
    if t is None:
        return None
    m = re.match(r'^(?:Map|Record)<string, (.+)>$', t)
    if m:
        return m.group(1)
    m = re.match(r'^\{ \[\w+: string\]: (.+) \}$', t)
    return m.group(1) if m else None


def known(name):
    return name in classes or name in sealed or name in enums


def from_js(dt, ts, e):
    """Dart expression converting normalized JS value `e` into Dart type dt."""
    dt = dt.strip()
    if dt.endswith('?'):
        inner = dt[:-1]
        return '(%s == null ? null : %s)' % (e, from_js(inner, ts, e))
    if dt == 'String':
        return 'jsString(%s)' % e
    if dt == 'bool':
        return 'jsBool(%s)' % e
    if dt == 'int':
        return 'jsInt(%s)' % e
    if dt == 'double':
        return 'jsDouble(%s)' % e
    if dt == 'BigInt':
        return 'jsBigInt(%s)' % e
    if dt == 'Uint8List':
        return 'jsBytes(%s)' % e
    if dt == 'Uint64List':
        return 'jsU64List(%s)' % e
    m = re.match(r'^List<(.+)>$', dt)
    if m:
        el = m.group(1)
        return 'jsList(%s, (x) => %s)' % (e, from_js(el, ts_elem(ts), 'x'))
    m = re.match(r'^Map<String, (.+)>$', dt)
    if m:
        return 'jsMap(%s, (x) => %s)' % (e, from_js(m.group(1), ts_map_value(ts), 'x'))
    if known(dt) and dt not in SKIP:
        return 'fromJs%s(%s)' % (dt, e)
    warn('from_js: unsupported Dart type %s' % dt)
    return 'unsupportedFromJs(%r)' % dt


def to_js(dt, ts, e):
    """Dart expression converting Dart value `e` (type dt) into a JS-ready tree."""
    dt = dt.strip()
    if dt.endswith('?'):
        inner = dt[:-1]
        return '(%s == null ? null : %s)' % (e, to_js(inner, ts, '%s!' % e if not re.match(r'^\w+$', e) else e))
    if dt in ('String', 'bool', 'int', 'double'):
        return e
    tsc = ts_clean(ts)
    if dt == 'BigInt':
        if tsc == 'bigint':
            return 'JsBig(%s)' % e
        if tsc == 'string':
            return '%s.toString()' % e
        if tsc not in (None, 'number'):
            warn('BigInt with TS type %s' % tsc)
        return '%s.toInt()' % e
    if dt == 'Uint8List':
        if tsc is not None and tsc.startswith('Uint8Array'):
            return 'JsTyped(%s)' % e
        return 'List<int>.of(%s)' % e
    if dt == 'Uint64List':
        return 'jsFromU64List(%s)' % e
    m = re.match(r'^List<(.+)>$', dt)
    if m:
        el = m.group(1)
        return '%s.map((x) => %s).toList()' % (e, to_js(el, ts_elem(ts), 'x'))
    m = re.match(r'^Map<String, (.+)>$', dt)
    if m:
        return '%s.map((k, x) => MapEntry(k, %s))' % (e, to_js(m.group(1), ts_map_value(ts), 'x'))
    if known(dt) and dt not in SKIP:
        return 'toJs%s(%s)' % (dt, e)
    warn('to_js: unsupported Dart type %s' % dt)
    return 'unsupportedToJs(%r)' % dt


def js_key(dart_name):
    return dart_name[:-1] if dart_name.endswith('_') else dart_name


def norm(s):
    return s.replace('_', '').lower()


out = []
w = out.append
w('// GENERATED by tool/gen_web_bindings.py from the FRB models and the')
w('// @breeztech/breez-sdk-spark d.ts. Do not edit by hand.')
w('')
w('// ignore_for_file: non_constant_identifier_names, unnecessary_null_comparison, unused_element, prefer_null_aware_operators')
w('')
w("import '../rust/errors.dart';")
w("import '../rust/events.dart';")
w("import '../rust/logger.dart';")
w("import '../rust/models.dart';")
w("import 'js_values.dart';")
w('')

for name in sorted(enums):
    if name in SKIP:
        continue
    vals = enums[name]
    tsu = ts_unions.get(name)
    lits = list(tsu.keys()) if tsu else []
    pairs = []
    for v in vals:
        lit = next((l for l in lits if norm(l) == norm(v)), None)
        if lit is None:
            if tsu is not None:
                warn('enum %s.%s has no TS literal (TS: %s)' % (name, v, lits))
            lit = js_key(v)
        pairs.append((v, lit))
    w('%s fromJs%s(Object? o) => switch (o) {' % (name, name))
    for v, lit in pairs:
        w("  '%s' => %s.%s," % (lit, name, v))
    w("  _ => throw ArgumentError.value(o, '%s'),"  % name)
    w('};')
    w('')
    w('String toJs%s(%s v) => switch (v) {' % (name, name))
    for v, lit in pairs:
        w("  %s.%s => '%s'," % (name, v, lit))
    w('};')
    w('')

for name in sorted(classes):
    if name in SKIP:
        continue
    fields = classes[name]
    tsf = ts_ifaces.get(name)
    if tsf is None:
        warn('class %s has no TS interface' % name)
        tsf = {}
    else:
        dk = {js_key(n) for _, n in fields}
        for k in tsf:
            if k not in dk:
                warn('TS %s.%s not in Dart' % (name, k))
        for _, n in fields:
            if js_key(n) not in tsf:
                warn('Dart %s.%s not in TS' % (name, n))
    w('%s fromJs%s(Object? o) {' % (name, name))
    w('  final m = jsObj(o);' if fields else '  jsObj(o);')
    args = ', '.join('%s: %s' % (n, from_js(t, tsf.get(js_key(n)), "m['%s']" % js_key(n))) for t, n in fields)
    w('  return %s(%s);' % (name, args))
    w('}')
    w('')
    w('Map<String, Object?> toJs%s(%s v) => {' % (name, name))
    for t, n in fields:
        w("  '%s': %s," % (js_key(n), to_js(t, tsf.get(js_key(n)), 'v.%s' % n)))
    w('};')
    w('')

for name in sorted(sealed):
    if name in SKIP:
        continue
    variants = sealed[name]
    tsu = ts_unions.get(name)
    if tsu is None:
        warn('sealed %s has no TS union' % name)
        tsu = {}
    tsu = {next((v for v, _, _ in variants if norm(v) == norm(k)), k): (k, val) for k, val in tsu.items()}
    for k in tsu:
        if k not in [v for v, _, _ in variants]:
            warn('TS %s variant %s not in Dart' % (name, k))
    tag = {v: (tsu[v][0] if v in tsu else js_key(v)) for v, _, _ in variants}
    tsu = {k: val for k, (_, val) in tsu.items()}
    w('%s fromJs%s(Object? o) {' % (name, name))
    w("  if (o is String) o = {'type': o};")
    w('  final m = jsObj(o);')
    w("  switch (m['type']) {")
    for v, impl, params in variants:
        tv = tsu.get(v)
        if tv is None and tsu:
            warn('Dart %s.%s not in TS' % (name, v))
        w("    case '%s':" % tag[v])
        if len(params) == 1 and params[0][2]:
            t = params[0][0]
            if tv and tv[0] == 'flat' and tv[1] not in ('string', 'number[]'):
                w('      return %s.%s(%s);' % (name, v, from_js(t, None, 'm')))
            elif t == 'String':
                w("      return %s.%s(jsString(m['field0'] ?? m['value'] ?? m['message'] ?? ''));" % (name, v))
            else:
                w("      return %s.%s(%s);" % (name, v, from_js(t, None, "m['field0']")))
        else:
            tfs = tv[1] if tv and tv[0] == 'fields' else {}
            args = ', '.join('%s: %s' % (n, from_js(t, tfs.get(js_key(n)), "m['%s']" % js_key(n))) for t, n, _ in params)
            w('      return %s.%s(%s);' % (name, v, args))
    w('  }')
    w("  throw ArgumentError.value(m['type'], '%s.type');" % name)
    w('}')
    w('')
    w('Map<String, Object?> toJs%s(%s v) => switch (v) {' % (name, name))
    for v, impl, params in variants:
        tv = tsu.get(v)
        if len(params) == 1 and params[0][2]:
            t = params[0][0]
            if tv and tv[0] == 'flat' and tv[1] not in ('string', 'number[]'):
                w("  final %s x => {...%s, 'type': '%s'}," % (impl, to_js(t, None, 'x.field0'), tag[v]))
            else:
                w("  final %s x => {'type': '%s', 'field0': %s}," % (impl, tag[v], to_js(t, None, 'x.field0')))
        else:
            tfs = tv[1] if tv and tv[0] == 'fields' else {}
            parts = ["'type': '%s'" % tag[v]] + ["'%s': %s" % (js_key(n), to_js(t, tfs.get(js_key(n)), 'x.%s' % n)) for t, n, _ in params]
            w('  %s %s => {%s},' % (('final %s' % impl) if params else impl, 'x' if params else '()', ', '.join(parts)))
    w('};')
    w('')

os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'convert.g.dart'), 'w').write('\n'.join(out) + '\n')

# --------------------------------------------------------------------------
# BreezSdk / TokenIssuer method forwarding
# --------------------------------------------------------------------------


def parse_abstract(path, cls):
    src = open(path).read()
    m = re.search(r'abstract class %s implements RustOpaqueInterface \{\n(.*?)^\}' % cls, src, re.M | re.S)
    body = strip_comments(m.group(1))
    body = re.sub(r'\s+', ' ', body)
    meths = []
    for mm in re.finditer(r'([\w<>?, ]+?) (\w+)\(([^()]*(?:\([^()]*\)[^()]*)*)\);', body):
        ret, name, params = mm.group(1).strip(), mm.group(2), mm.group(3)
        if 'factory' in ret:
            continue
        meths.append((ret, name, params))
    return meths


HANDWRITTEN = {'addEventListener', 'getTokenIssuer', 'unilateralExit', 'unilateralExitWithSigner',
               'parse', 'deleteContact', 'removeEventListener'}


def gen_forwarders(cls, tscls, rust_file, mixin):
    meths = parse_abstract(os.path.join(RUST, rust_file), cls)
    tsm = ts_class_methods.get(tscls, {})
    o = []
    o.append('mixin %s on JsHandle implements %s {' % (mixin, cls))
    for ret, name, params in meths:
        if name in HANDWRITTEN:
            continue
        rm = re.match(r'^Future<(.+)>$', ret)
        if not rm:
            warn('%s.%s: non-future return %s' % (cls, name, ret))
            continue
        rdt = rm.group(1)
        ps = parse_params(params)
        tsr = None
        if name in tsm:
            tr = re.match(r'^Promise<(.+)>$', tsm[name][1])
            tsr = tr.group(1) if tr else None
        else:
            warn('%s.%s missing in TS class %s' % (cls, name, tscls))
        sig = ', '.join('required %s %s' % (t, n) for t, n, _ in ps)
        args = ', '.join(to_js(t, None, n) for t, n, _ in ps)
        o.append('  @override')
        if ps:
            o.append('  %s %s({%s}) =>' % (ret, name, sig))
        else:
            o.append('  %s %s() =>' % (ret, name))
        if rdt == 'void':
            o.append("      callVoid('%s', [%s]);" % (name, args))
        else:
            o.append("      call('%s', [%s], (r) => %s);" % (name, args, from_js(rdt, tsr, 'r')))
        o.append('')
    o.append('}')
    return o


out2 = ['// GENERATED by tool/gen_web_bindings.py. Do not edit by hand.', '',
        '// ignore_for_file: unnecessary_null_comparison', '',
        "import '../rust/issuer.dart';",
        "import '../rust/models.dart';",
        "import '../rust/sdk.dart';",
        "import 'convert.g.dart';",
        "import 'js_values.dart';",
        '']
out2 += gen_forwarders('BreezSdk', 'BreezSdk', 'sdk.dart', 'BreezSdkForwarders')
out2.append('')
out2 += gen_forwarders('TokenIssuer', 'TokenIssuer', 'issuer.dart', 'TokenIssuerForwarders')
open(os.path.join(OUT, 'sdk_web.g.dart'), 'w').write('\n'.join(out2) + '\n')

for x in warnings:
    print('warning:', x)
print('classes=%d sealed=%d enums=%d warnings=%d' % (len(classes), len(sealed), len(enums), len(warnings)))
