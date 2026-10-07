import 'package:kute/l10n/generated/app_localizations.dart';

/// Why a funding guard refused to proceed. [code] is the analytics value;
/// it never carries amounts, addresses or ids.
enum WalletGuardReason {
  quoteMissingId('quote_missing_id'),
  depositAddressFormat('deposit_address_format'),
  depositMemoPresent('deposit_memo_present'),
  amountMismatch('amount_mismatch'),
  quoteExpired('expired'),
  refundAddressChain('refund_address_chain'),
  recipientAddressChain('recipient_address_chain'),
  recipientNotOwn('recipient_not_own'),
  refundNotOwn('refund_not_own'),
  ownAddressUnavailable('own_address_unavailable'),
  feeAboveCap('fee_above_cap'),
  outputBelowFloor('output_below_floor'),
  outputMalformed('output_malformed'),
  noReferencePrice('no_reference_price'),
  echoMismatch('echo_mismatch'),
  decimalsMismatch('decimals_mismatch'),
  depositTermsRejected('deposit_terms_rejected'),
  withdrawDestinationRejected('withdraw_destination_rejected');

  const WalletGuardReason(this.code);

  final String code;
}

/// Expected guard refusal. The UI shows [messageFor] instead of the
/// exception text.
class WalletGuardException implements Exception {
  const WalletGuardException(this.reason, {this.field});

  final WalletGuardReason reason;

  /// Non-sensitive label of the value that failed (e.g. `bridge`,
  /// `chain_id`, `source_chain`), for analytics and logs.
  final String? field;

  String messageFor(AppLocalizations l10n) {
    switch (reason) {
      case WalletGuardReason.quoteExpired:
        return l10n.guardQuoteExpired;
      case WalletGuardReason.decimalsMismatch:
      case WalletGuardReason.ownAddressUnavailable:
        return l10n.swapRouteTemporarilyUnavailable;
      case WalletGuardReason.depositTermsRejected:
        return l10n.guardDepositTermsRejected;
      case WalletGuardReason.withdrawDestinationRejected:
        return l10n.guardWithdrawDestinationRejected;
      // The one refusal the user can act on: the route would deliver far
      // less than it was handed. "We couldn't verify this transfer" gave
      // them nothing to do about it.
      case WalletGuardReason.outputBelowFloor:
        return l10n.guardAmountTooSmall;
      case WalletGuardReason.quoteMissingId:
      case WalletGuardReason.depositAddressFormat:
      case WalletGuardReason.depositMemoPresent:
      case WalletGuardReason.amountMismatch:
      case WalletGuardReason.refundAddressChain:
      case WalletGuardReason.recipientAddressChain:
      case WalletGuardReason.recipientNotOwn:
      case WalletGuardReason.refundNotOwn:
      case WalletGuardReason.feeAboveCap:
      case WalletGuardReason.outputMalformed:
      case WalletGuardReason.noReferencePrice:
      case WalletGuardReason.echoMismatch:
        return l10n.guardQuoteRejected;
    }
  }

  @override
  String toString() => field == null
      ? 'WalletGuardException(${reason.code})'
      : 'WalletGuardException(${reason.code}, $field)';
}
