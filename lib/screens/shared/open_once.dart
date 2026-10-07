// lib/screens/shared/open_once.dart
//
// One copy of a screen or sheet at a time. A tap on something that is
// already open (a position's own price line on its position screen, a
// double tap on a card, a row tapped again while its sheet slides in)
// must not push a second copy on top of the first: each key is held from
// the push until its route is popped, and a second open of the same key
// in between does nothing.

import 'package:flutter/foundation.dart';

abstract final class OpenOnce {
  static final Set<String> _open = <String>{};

  /// True while a route opened under [key] is still on screen.
  static bool isOpen(String key) => _open.contains(key);

  /// Runs [open] (which pushes a route and completes when it is popped)
  /// unless [key] is already open, in which case nothing happens and the
  /// result is null.
  static Future<T?> run<T>(String key, Future<T?> Function() open) async {
    if (!_open.add(key)) return null;
    try {
      return await open();
    } finally {
      _open.remove(key);
    }
  }

  @visibleForTesting
  static void reset() => _open.clear();
}
