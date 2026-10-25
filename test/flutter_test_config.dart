import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/theme/app_theme.dart';

/// Runs before every test file: Inter is in the engine before any test
/// lays out text, as it is before the app's first frame.
///
/// Left to the themes, the font landed whenever its asset read finished:
/// on a slow runner in the middle of a test, between a figure's layout and
/// a change of its colour alone, which trips TextPainter's
/// `debugSize == size` assertion (see [loadAppFonts]).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  await testMain();
}
