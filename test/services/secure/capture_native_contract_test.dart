import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/secure/keychain_local.dart';

String read(String path) => File(path).readAsStringSync();

String section(String xml, String tag) {
  final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  expect(match, isNotNull, reason: '<$tag> missing');
  return match!.group(1)!;
}

void main() {
  const channel = 'com.kutewallet.app/security';

  test('Android backup and device transfer exclude secure storage', () {
    final rules =
        read('android/app/src/main/res/xml/data_extraction_rules.xml');
    const exclude = '<exclude domain="sharedpref" path="." />';
    expect(section(rules, 'cloud-backup'), contains(exclude));
    expect(section(rules, 'device-transfer'), contains(exclude));
    expect(rules, isNot(contains('<include')));
    expect(rules, isNot(contains('domain="root"')));
  });

  test('the manifest uses the rules and keeps allowBackup off', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
        manifest,
        contains(
            'tools:replace="android:allowBackup,android:dataExtractionRules"'));
  });

  test('Android sets FLAG_SECURE only from setSecureScreen', () {
    final kotlin =
        read('android/app/src/main/kotlin/com/kutewallet/app/MainActivity.kt');
    expect(kotlin, contains('"$channel"'));
    expect(kotlin, contains('"setSecureScreen" ->'));
    expect(kotlin, contains('call.argument<Boolean>("enabled")'));
    expect(
        'addFlags(WindowManager.LayoutParams.FLAG_SECURE)'
            .allMatches(kotlin)
            .length,
        1);
    expect(
        kotlin, contains('clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'));
    expect(kotlin, isNot(contains('override fun onCreate')));
  });

  test('iOS implements the capture and pasteboard methods Dart calls', () {
    final swift = read('ios/Runner/SecurityNativePlugin.swift');
    expect(swift, contains('"$channel"'));
    for (final method in [
      'setSecureScreen',
      'isCaptured',
      'pasteboardChangeCount'
    ]) {
      expect(swift, contains('case "$method":'), reason: method);
    }
    expect(swift, contains('args["enabled"] as? Bool'));
    expect(swift, contains('UIScreen.capturedDidChangeNotification'));
    expect(swift, contains('UIApplication.userDidTakeScreenshotNotification'));
    expect(swift, contains('invokeMethod("captureChanged"'));
    expect(swift, contains('invokeMethod("screenshotTaken"'));
  });

  test('Dart uses the same channel and method names', () {
    expect(KeychainLocal.channel.name, channel);
    final secureScreen = read('lib/helpers/secure_screen.dart');
    for (final name in [
      'setSecureScreen',
      'isCaptured',
      'captureChanged',
      'screenshotTaken',
    ]) {
      expect(secureScreen, contains("'$name'"), reason: name);
    }
    expect(read('lib/helpers/seed_clipboard.dart'),
        contains("'pasteboardChangeCount'"));
  });
}
