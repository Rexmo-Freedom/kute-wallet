import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';

const _phase2Keys = [
  'guardQuoteRejected',
  'guardQuoteExpired',
  'guardDepositTermsRejected',
  'guardWithdrawDestinationRejected',
  'investingAccountNotReady',
  'invalidRecipientNothingSent',
  'swapRouteTemporarilyUnavailable',
  'walletSessionUnavailable',
];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  for (final file in ['app_en.arb', 'app_pt.arb']) {
    test('$file has every Phase 2 key with dash-free copy', () {
      final arb = _arb(file);
      for (final key in _phase2Keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$file is missing $key');
        expect((value as String).trim(), isNotEmpty, reason: '$file $key');
        expect(value.contains('—'), isFalse,
            reason: '$file $key contains an em dash');
      }
    });
  }

  test('l10nForLanguage follows the app language and falls back to English',
      () {
    expect(l10nForLanguage('pt').invalidRecipientNothingSent,
        'Endereço de destinatário inválido. Nada foi enviado.');
    expect(l10nForLanguage('en').invalidRecipientNothingSent,
        'Invalid recipient address. Nothing was sent.');
    expect(l10nForLanguage('zh').invalidRecipientNothingSent,
        'Invalid recipient address. Nothing was sent.');
  });
}
