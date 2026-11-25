// The Sal toast replaced the top message bar without touching a call
// site (9 November 2026): every screen still calls showMessageSnackBar /
// showMessageSnackBarInfo with the signatures it always had, and nothing
// in lib draws a top message any other way.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _call = RegExp(r'\bshowMessageSnackBar(Info)?\(');

Iterable<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('the files that showed the old bar still call the same helpers', () {
    final callers = _dartFiles()
        .where((f) => _call.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toSet();
    expect(callers, contains('lib/screens/shared/message_display.dart'));
    // 56 screens (189 calls) and the helpers' own file on 9 November 2026;
    // a screen added since may join, none may leave for another way to
    // say it.
    expect(callers.length, greaterThanOrEqualTo(57),
        reason: 'call sites moved off showMessageSnackBar: $callers');
  });

  test('the helpers keep their signatures and draw the Sal toast', () {
    final source =
        File('lib/screens/shared/message_display.dart').readAsStringSync();
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
    final text = flat(source);
    expect(
        text,
        contains(flat('void showMessageSnackBar({ required BuildContext '
            'context, required String message, required bool error, bool '
            'info = false, Duration duration = const Duration(seconds: 4), '
            '})')));
    expect(
        text,
        contains(flat('void showMessageSnackBarInfo({ required BuildContext '
            'context, required String message, Duration duration = const '
            'Duration(seconds: 4), })')));
    expect(text, contains('SalToast.show('));
    // Material's own bar is never drawn here.
    expect(RegExp(r'\bSnackBar\(').hasMatch(text), isFalse);
    expect(text, isNot(contains('ScaffoldMessenger')));
  });

  test('nothing in lib draws the old top bar', () {
    final strays = <String>[];
    for (final f in _dartFiles()) {
      final text = f.readAsStringSync();
      if (text.contains('ToastService') || text.contains('ToastMessage(')) {
        strays.add(f.path);
      }
    }
    expect(strays, isEmpty);
  });
}
