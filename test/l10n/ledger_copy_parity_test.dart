import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';

const _ledgerKeys = [
  'ledgerErrorLocked',
  'ledgerErrorOpenApp',
  'ledgerErrorInstallApp',
  'ledgerErrorUpdateApp',
  'ledgerErrorRejected',
  'ledgerErrorDataRejected',
  'ledgerErrorPayloadTooLarge',
  'ledgerErrorDisconnected',
  'ledgerErrorWrongDevice',
  'ledgerErrorWrongSigner',
  'ledgerErrorTimeout',
  'ledgerErrorBusy',
  'ledgerErrorPermission',
  'ledgerErrorUnknown',
  'ledgerErrorUnknownCode',
  'ledgerFailureCodeDetail',
  'ledgerTransportLabel',
  'ledgerMakeSureUnlockedUsb',
];

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  final en = _arb('en');
  final pt = _arb('pt');

  test('every Ledger key exists in EN and PT with matching placeholders', () {
    for (final key in _ledgerKeys) {
      expect(en[key], isA<String>(), reason: 'EN missing $key');
      expect(pt[key], isA<String>(), reason: 'PT missing $key');
      expect((en[key] as String).trim(), isNotEmpty);
      expect((pt[key] as String).trim(), isNotEmpty);
      expect(_placeholders(pt[key] as String), _placeholders(en[key] as String),
          reason: 'placeholder drift in $key');
    }
  });

  test('Ledger copy has no em dash and says Ledger Live for installs', () {
    for (final key in _ledgerKeys) {
      expect((en[key] as String).contains('—'), isFalse, reason: key);
      expect((pt[key] as String).contains('—'), isFalse, reason: key);
    }
    expect(en['ledgerErrorInstallApp'], contains('Ledger Live'));
    expect(pt['ledgerErrorInstallApp'], contains('Ledger Live'));
  });

  test('every failure code has localized copy in both locales', () {
    for (final locale in const [Locale('en'), Locale('pt')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final code in LedgerFailureCode.values) {
        for (final app in LedgerAppId.values) {
          final text = ledgerFailureMessage(
              l10n, LedgerFailure(code, statusWord: 0x6b00, app: app));
          expect(text.trim(), isNotEmpty, reason: '$locale ${code.name}');
          expect(text.contains('—'), isFalse);
          expect(text.contains('LedgerFailure'), isFalse);
        }
      }
      expect(
          ledgerFailureMessage(l10n,
              const LedgerFailure(LedgerFailureCode.appNotInstalled,
                  app: LedgerAppId.ethereum)),
          contains('Ethereum'));
      // The status word left the primary sentence (ce3748c3): the user
      // reads the generic Ledger sentence and the code lives in the nerd
      // data detail line.
      const unknownWithCode =
          LedgerFailure(LedgerFailureCode.unknown, statusWord: 0x6b00);
      final unknownText = ledgerFailureMessage(l10n, unknownWithCode);
      expect(unknownText, l10n.ledgerErrorUnknown);
      expect(unknownText.contains('6B00'), isFalse);
      expect(ledgerFailureDetail(l10n, unknownWithCode), contains('6B00'));
      expect(
          ledgerFailureDetail(
              l10n, const LedgerFailure(LedgerFailureCode.unknown)),
          isNull);
    }
  });
}
