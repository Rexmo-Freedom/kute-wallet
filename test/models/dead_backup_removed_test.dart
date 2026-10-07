import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the password-encrypted backup export and import code is gone', () {
    const removed = [
      'exportEncryptedBackup',
      'importEncryptedBackup',
      '_encryptData(',
      '_decryptData(',
      'kute_backup_',
    ];
    final hits = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') && !f.path.contains('l10n/generated'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final symbol in removed) {
        if (source.contains(symbol)) hits.add('${file.path}: $symbol');
      }
    }
    expect(hits, isEmpty);
  });

  test('the key export copy and events are gone', () {
    const keys = [
      'confirmPassword',
      'enterAPasswordToAuthorizeTheKeyExport',
      'exportEncryptedPdf',
      'keyBackupExportedSuccessfully',
      'password',
      'passwordIsRequired',
      'passwordMustBeAtLeast6Characters',
      'passwordsDoNotMatch',
      'useAStrongUniquePasswordYouWillNeedItToDecryptThisFile',
    ];
    for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_pt.arb']) {
      final arb = File(path).readAsStringSync();
      for (final key in keys) {
        expect(arb, isNot(contains('"$key":')), reason: '$path: $key');
      }
    }
    final tracking =
        File('lib/services/tracking_service.dart').readAsStringSync();
    for (final event in ['keyPdf', 'key_pdf_']) {
      expect(tracking, isNot(contains(event)), reason: event);
    }
  });
}
