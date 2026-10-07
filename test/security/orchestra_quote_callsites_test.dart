import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Orchestra quote must pass the quote gate and be re-checked right
/// before payment. These scans fail with the file and line of any call
/// site that goes around the gate.
void main() {
  const gate = 'lib/services/orchestra/orchestra_quote_gate.dart';
  const api = 'lib/services/api/orchestra_api.dart';

  final sources = <String, List<String>>{
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      file.path.replaceAll(r'\', '/'): file.readAsLinesSync(),
  };

  bool isComment(String line) => line.trimLeft().startsWith('//');

  test('OrchestraService.createQuote is only referenced by the quote gate',
      () {
    final offenders = <String>[];
    var gateCalls = 0;
    final reference =
        RegExp(r'OrchestraService\s*\.\s*createQuote\b(\s*\()?');
    sources.forEach((path, lines) {
      final numbered = [
        for (var i = 0; i < lines.length; i++)
          if (!isComment(lines[i])) (i + 1, lines[i]),
      ];
      final text = numbered.map((l) => l.$2).join('\n');
      for (final match in reference.allMatches(text)) {
        final row = '\n'.allMatches(text.substring(0, match.start)).length;
        final (line, source) = numbered[row];
        if (path == gate && match.group(1) != null) {
          gateCalls++;
        } else {
          offenders.add('$path:$line: ${source.trim()}');
        }
      }
    });
    expect(offenders, isEmpty,
        reason: 'Orchestra quotes must go through OrchestraQuoteGate:\n'
            '${offenders.join('\n')}');
    expect(gateCalls, 1, reason: 'the gate itself must still quote');
  });

  test('no /quote endpoint literal outside the Orchestra API client', () {
    final literal = RegExp(r'''['"][^'"]*/quote\b[^'"]*['"]''');
    final offenders = <String>[];
    sources.forEach((path, lines) {
      if (path == api) return;
      for (var i = 0; i < lines.length; i++) {
        if (!isComment(lines[i]) && literal.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    });
    expect(offenders, isEmpty,
        reason: 'Quote requests must go through OrchestraQuoteGate:\n'
            '${offenders.join('\n')}');
  });

  test('every file that fetches a verified quote re-checks it before paying',
      () {
    final offenders = <String>[];
    sources.forEach((path, lines) {
      if (path == gate) return;
      final text = lines.where((l) => !isComment(l)).join('\n');
      if (!text.contains('OrchestraQuoteGate.fetchVerified(')) return;
      if (!text.contains('OrchestraQuoteGate.ensurePayable(') &&
          !text.contains('OrchestraQuoteGate.confirmStored(')) {
        offenders.add(path);
      }
    });
    expect(offenders, isEmpty,
        reason: 'fetchVerified without ensurePayable or confirmStored:\n'
            '${offenders.join('\n')}');
  });

  test('a shared recipient and ownAddress has an audited local source', () {
    final offenders = <String>[];
    // These funding paths resolve the destination before building the request:
    // PM wallets are re-derived from the Ledger EOA, Bitcoin addresses are
    // confirmed on-device, and hot addresses come from wallet-bound providers.
    // Equality is correct for an owned destination. Count each reviewed site
    // exactly once so an additional use still requires a security review.
    // Address substitutions, wallet switches and cross-account routes are
    // exercised in services/funding/owned_address_resolver_test.dart.
    final reviewed = <(String, String), int>{
      ('lib/services/funding/ledger_polymarket_funding_service.dart', 'wallet'): 1,
      ('lib/services/funding/ledger_polymarket_funding_service.dart',
          'recipient.address'): 1,
      ('lib/services/funding/spark_hypercore_funding_service.dart', 'eoa'): 1,
      ('lib/services/funding/spark_hypercore_funding_service.dart',
          'sparkAddress'): 1,
      ('lib/services/funding/ledger_hypercore_funding_service.dart',
          'ownership.recipient.address'): 1,
    };
    final recipientArg = RegExp(r'recipientAddress:\s*([^,\n]+),');
    final ownArg = RegExp(r'ownAddress:\s*([^,]+),');
    sources.forEach((path, lines) {
      final text = lines.join('\n');
      var start = text.indexOf('OrchestraQuoteRequest(');
      while (start != -1) {
        var depth = 0;
        var end = start + 'OrchestraQuoteRequest'.length;
        for (; end < text.length; end++) {
          final ch = text[end];
          if (ch == '(') depth++;
          if (ch == ')' && --depth == 0) break;
        }
        final call = text.substring(start, end);
        final recipient = recipientArg.firstMatch(call)?.group(1)?.trim();
        final own = ownArg
            .firstMatch(call)
            ?.group(1)
            ?.replaceAll(RegExp(r'\s+'), '');
        if (recipient != null && own != null && own == recipient) {
          final key = (path, own);
          final remaining = reviewed[key] ?? 0;
          if (remaining > 0) {
            reviewed[key] = remaining - 1;
            start = text.indexOf('OrchestraQuoteRequest(', end);
            continue;
          }
          final line = '\n'.allMatches(text.substring(0, start)).length + 1;
          offenders.add('$path:$line: ownAddress: $own');
        }
        start = text.indexOf('OrchestraQuoteRequest(', end);
      }
    });
    expect(offenders, isEmpty,
        reason: 'Resolve ownAddress from its provider, not the recipient:\n'
            '${offenders.join('\n')}');
    expect(reviewed.values, everyElement(0),
        reason: 'Remove or re-review any ownership exception whose site changed.');
  });
}
