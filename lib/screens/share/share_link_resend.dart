// lib/screens/share/share_link_resend.dart
//
// "Send again via WhatsApp / SMS" for a link made for a contact: the
// contact's number (PendingShareLink.recipientPhone, kept on the phone
// only) prefilled in the OS intent with the link's own share text. The
// number never leaves the device except in the intent the person opens.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/services/share_link_events.dart';

enum ShareLinkResendChannel { whatsapp, sms }

/// Test seam: what the resend opens. Null launches the URL.
@visibleForTesting
Future<bool> Function(Uri uri)? debugShareLinkResendLauncher;

/// The intent for [channel] with [phone] and [text] prefilled.
Uri shareLinkResendUri(
    ShareLinkResendChannel channel, String phone, String text) {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  switch (channel) {
    case ShareLinkResendChannel.whatsapp:
      return Uri.https('wa.me', '/${digits.replaceAll('+', '')}',
          {'text': text});
    case ShareLinkResendChannel.sms:
      return Uri(scheme: 'sms', path: digits, queryParameters: {'body': text});
  }
}

/// Opens WhatsApp or the SMS composer for [row]'s contact.
Future<void> resendShareLinkVia(BuildContext context, WidgetRef ref,
    PendingShareLink row, ShareLinkResendChannel channel) async {
  final phone = row.recipientPhone;
  if (phone == null || phone.isEmpty || row.url.isEmpty) return;
  final amount = shareLinkAmountLabel(context, ref, row.kind, row.amountMinor);
  final text = shareLinkMessage(context,
      name: row.label,
      amount: amount,
      url: row.url,
      outcome: row.outcome,
      title: row.marketTitle,
      venue: row.venue);
  final uri = shareLinkResendUri(channel, phone, text);
  try {
    final launch = debugShareLinkResendLauncher;
    final ok = launch != null
        ? await launch(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    ShareLinkEvents.shared(row.kind, result: ok ? channel.name : 'error');
  } catch (_) {
    ShareLinkEvents.shared(row.kind, result: 'error');
  }
}
