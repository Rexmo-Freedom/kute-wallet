import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

void main() {
  test('every reason maps to localized copy in EN and PT', () {
    for (final locale in const [Locale('en'), Locale('pt')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final reason in WalletGuardReason.values) {
        final message = WalletGuardException(reason).messageFor(l10n);
        expect(message, isNotEmpty, reason: '${locale.languageCode} $reason');
        expect(message.contains('—'), isFalse);
      }
    }
  });

  test('reasons pick their dedicated copy', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    String msg(WalletGuardReason r) => WalletGuardException(r).messageFor(l10n);
    expect(msg(WalletGuardReason.quoteExpired), l10n.guardQuoteExpired);
    expect(msg(WalletGuardReason.amountMismatch), l10n.guardQuoteRejected);
    expect(msg(WalletGuardReason.decimalsMismatch),
        l10n.swapRouteTemporarilyUnavailable);
    expect(msg(WalletGuardReason.depositTermsRejected),
        l10n.guardDepositTermsRejected);
    expect(msg(WalletGuardReason.withdrawDestinationRejected),
        l10n.guardWithdrawDestinationRejected);
  });

  test('codes are unique snake_case and toString carries no values', () {
    final codes = WalletGuardReason.values.map((r) => r.code).toList();
    expect(codes.toSet().length, codes.length);
    for (final code in codes) {
      expect(RegExp(r'^[a-z_]+$').hasMatch(code), isTrue, reason: code);
    }
    expect(
        const WalletGuardException(WalletGuardReason.depositTermsRejected,
                field: 'bridge')
            .toString(),
        'WalletGuardException(deposit_terms_rejected, bridge)');
  });
}
