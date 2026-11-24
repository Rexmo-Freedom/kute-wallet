// flutter_test's old default window, 800 x 600 at 3x, for a file whose
// figures were written against it (test/flutter_test_config.dart now
// starts every test on a 430 x 932 phone). Call at the top of `main`.

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

void useLegacyTestWindow() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(2400, 1800);
    view.devicePixelRatio = 3;
  });
}
