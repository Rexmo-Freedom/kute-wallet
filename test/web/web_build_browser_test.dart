// The web build id the bootstrap sets, read in a real browser:
//   flutter test --platform chrome test/web/web_build_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_build.dart';

void main() {
  tearDown(() => globalContext.delete('kuteWebBuild'.toJS));

  test('reads window.kuteWebBuild', () {
    globalContext['kuteWebBuild'] = 'c34e8afcf1f3debe9367'.toJS;
    expect(webBuildId(), 'c34e8afcf1f3debe9367');
  });

  test('null when the bootstrap set none (unstamped build)', () {
    expect(webBuildId(), isNull);
  });

  test('null when it is not a string', () {
    globalContext['kuteWebBuild'] = 7.toJS;
    expect(webBuildId(), isNull);
  });
}
