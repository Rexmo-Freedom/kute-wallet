// Every primary button the bar draws says what to do while it is off
// (founder, 1 November 2026; kute_bar_context.dart, disabledLabel): each
// `KuteBarContext.primary(` in lib/ names its `disabledLabel`, null only
// where the button never waits on input. Comments are stripped first.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

void main() {
  test('every KuteBarContext.primary call site sets disabledLabel', () {
    final missing = <String>[];
    var sites = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('kute_bar_context.dart')) continue;
      final code = stripComments(entity.readAsStringSync());
      for (final match in RegExp(r'KuteBarContext\.primary\(').allMatches(code)) {
        // The call's own arguments, to its closing parenthesis.
        var depth = 1;
        var i = match.end;
        while (depth > 0 && i < code.length) {
          final ch = code[i];
          if (ch == '(') depth++;
          if (ch == ')') depth--;
          i++;
        }
        sites++;
        if (!code.substring(match.end, i).contains('disabledLabel:')) {
          final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
          missing.add('${entity.path}:$line');
        }
      }
    }
    expect(sites, greaterThan(50));
    expect(missing, isEmpty,
        reason: 'a primary button with no disabledLabel: ${missing.join(', ')}');
  });
}
