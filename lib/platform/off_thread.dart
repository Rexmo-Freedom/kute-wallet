// lib/platform/off_thread.dart
//
// Heavy pure work (parsing a large response) off the UI thread. On iOS and
// Android that is `Isolate.run`, exactly as before. A browser has no
// isolates: there `Isolate.run` throws UnsupportedError, which silently
// emptied every Predictions list parsed this way (Trending, search,
// activity, closed positions). On the web the same work runs on the
// page's thread after the caller's frame: a short pause, not an error.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

Future<R> runOffThread<R>(FutureOr<R> Function() work) =>
    kIsWeb ? Future<R>(work) : Isolate.run<R>(work);
