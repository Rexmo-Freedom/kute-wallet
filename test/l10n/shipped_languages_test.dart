import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final generated =
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();

  test('the Settings picker lists exactly the generated locales', () {
    expect(languageNativeNames.keys.toSet(), generated);
  });

  test('every shipped language has every template key and no extra ones', () {
    final template = _messageKeys(_arb('en'));
    for (final code in languageNativeNames.keys) {
      final keys = _messageKeys(_arb(code));
      expect(template.difference(keys), isEmpty, reason: '$code is missing');
      expect(keys.difference(template), isEmpty, reason: '$code has extra');
    }
  });

  test('iOS offers every shipped language (CFBundleLocalizations)', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final block = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(block, isNotNull);
    final listed = RegExp(r'<string>([^<]+)</string>')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
    expect(listed, languageNativeNames.keys.toSet());
  });

  test('every shipped language resolves to its own translation', () {
    for (final code in languageNativeNames.keys) {
      expect(l10nForLanguage(code).localeName, code);
    }
    expect(l10nForLanguage('zz').localeName, 'en');
  });
}
