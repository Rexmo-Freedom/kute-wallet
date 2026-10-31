// lib/screens/share/share_link_copy.dart
//
// The words every share-link surface uses for an amount and a status, so
// the sender's receipt row, the pay prompt and the recipient's Claim
// screen say the same thing. Dollars are "$12.00" (cents, two decimals);
// bitcoin is the sats as the user's currency plus "in Bitcoin", the
// bitcoin send's own fiat conversion (conversionToFiatProvider).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show conversionToFiatProvider;

/// "$12.00" for dollars; "$12.00 in Bitcoin" for bitcoin.
String shareLinkAmountLabel(
  BuildContext context,
  WidgetRef ref,
  ShareLinkKind kind,
  int amountMinor,
) {
  if (kind == ShareLinkKind.dollars) return shareDollarsLabel(amountMinor);
  String fiat;
  try {
    fiat = ref.watch(conversionToFiatProvider(amountMinor));
  } catch (_) {
    fiat = '$amountMinor sats';
  }
  return context.l10n.shareAmountInBitcoin(fiat);
}

/// Cents as "$12.00". No locale: the dollar send prints its own figures
/// this way too.
String shareDollarsLabel(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// The receipt row's second line for a link this wallet sent.
String shareLinkStatusLabel(BuildContext context, PendingShareLink row) {
  final l10n = context.l10n;
  switch (row.status) {
    case ShareLinkStatus.open:
      final name = row.label;
      return name == null || name.isEmpty
          ? l10n.shareLinkSentWaitingUnnamed
          : l10n.shareLinkSentWaiting(name);
    case ShareLinkStatus.claimed:
      return l10n.shareLinkClaimedReady;
    case ShareLinkStatus.paid:
      return l10n.shareLinkPaid;
    case ShareLinkStatus.cancelled:
      return l10n.shareLinkCancelled;
    case ShareLinkStatus.expired:
      return l10n.shareLinkExpired;
    case ShareLinkStatus.unknown:
      return l10n.shareLinkSentWaitingUnnamed;
  }
}

/// The OS share sheet text for a created link.
String shareLinkMessage(BuildContext context,
    {required String? name, required String amount, required String url}) {
  final l10n = context.l10n;
  final n = name?.trim() ?? '';
  return n.isEmpty
      ? l10n.shareMessageUnnamed(amount, url)
      : l10n.shareMessageNamed(n, amount, url);
}
