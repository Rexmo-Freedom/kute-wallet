import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/search_debounce.dart';

void main() {
  test('rapid edits start only the final delayed search', () async {
    final pending = <Future<bool>>[];
    SearchDebounce? previous;
    for (var i = 0; i < 20; i++) {
      previous?.cancel();
      previous = SearchDebounce(const Duration(milliseconds: 2));
      pending.add(previous.ready);
    }
    final ready = await Future.wait(pending);
    expect(ready.where((value) => value).length, 1);
    expect(ready.last, isTrue);
  });

  test('large local scan yields and stops a superseded query', () async {
    var cancelled = false;
    var visited = 0;
    final result = searchInBatches(
      Iterable<int>.generate(100000),
      matches: (_) { visited++; return false; },
      isCancelled: () => cancelled,
      limit: 25,
    );
    scheduleMicrotask(() => cancelled = true);
    expect(await result, isEmpty);
    expect(visited, lessThan(64));
  });

  test('local results remain ordered and stop when enough matches exist', () async {
    var visited = 0;
    final result = await searchInBatches(
      Iterable<int>.generate(100000),
      matches: (value) { visited++; return value.isEven; },
      isCancelled: () => false,
      limit: 25,
    );
    expect(result, List.generate(25, (index) => index * 2));
    expect(visited, 49);
  });
}
