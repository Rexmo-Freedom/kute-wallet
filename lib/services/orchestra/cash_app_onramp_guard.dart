// lib/services/orchestra/cash_app_onramp_guard.dart
//
// The check every Cash App buy passes before the app hands the person to
// Cash App. The backend proxy passes Orchestra's onramp reply through
// unchanged, so the reply is compared only with what the person typed,
// local constants and the independently fetched local BTC price.
// Pure: no network, no Riverpod, no widgets.

import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

/// What a decoded BOLT11 invoice states. Signature and payee are not
/// checked: the payee is Orchestra's and no local key could vouch for it.
class Bolt11Summary {
  const Bolt11Summary({
    required this.network,
    required this.amountMsat,
    required this.createdAt,
    required this.expiresAt,
  });

  /// `bc`, `tb`, `tbs` or `bcrt`.
  final String network;

  /// Null for an amountless invoice.
  final BigInt? amountMsat;
  final DateTime createdAt;
  final DateTime expiresAt;
}

const int _bolt11MaxLength = 12000;
const int _signatureWords = 104;
final RegExp _hrpPattern = RegExp(r'^ln(bcrt|bc|tbs|tb)(\d+)?([munp])?$');

int _number(Iterable<int> words) => words.fold(0, (n, w) => n * 32 + w);

/// Strips a `lightning:` prefix and surrounding space.
String _normalizeInvoice(String raw) => raw
    .trim()
    .replaceFirst(RegExp(r'^lightning:', caseSensitive: false), '');

/// Decodes the parts of a BOLT11 invoice the onramp check needs, with
/// full bech32 checksum verification. Null for anything malformed.
Bolt11Summary? decodeBolt11Summary(String raw) {
  final invoice = _normalizeInvoice(raw);
  final decoded = decodeBech32(invoice, maxLength: _bolt11MaxLength);
  if (decoded == null || decoded.encoding != Bech32Encoding.bech32) {
    return null;
  }
  final hrp = _hrpPattern.firstMatch(decoded.hrp);
  if (hrp == null) return null;
  final network = hrp.group(1)!;
  final digits = hrp.group(2);
  final multiplier = hrp.group(3);
  BigInt? amountMsat;
  if (digits != null) {
    // BOLT11: no leading zeros, and a bare multiplier is malformed.
    if (digits.length > 1 && digits.startsWith('0')) return null;
    final n = BigInt.parse(digits);
    switch (multiplier) {
      case null:
        amountMsat = n * BigInt.from(100000000000);
      case 'm':
        amountMsat = n * BigInt.from(100000000);
      case 'u':
        amountMsat = n * BigInt.from(100000);
      case 'n':
        amountMsat = n * BigInt.from(100);
      case 'p':
        if (n % BigInt.from(10) != BigInt.zero) return null;
        amountMsat = n ~/ BigInt.from(10);
    }
    if (amountMsat! <= BigInt.zero) return null;
  } else if (multiplier != null) {
    return null;
  }

  final data = decoded.data;
  if (data.length < 7 + _signatureWords) return null;
  final created = _number(data.take(7));
  var expiry = 3600; // BOLT11 default when the x tag is absent.
  var seenExpiry = false;
  final end = data.length - _signatureWords;
  for (var i = 7; i < end;) {
    if (i + 3 > end) return null;
    final tag = data[i];
    final length = data[i + 1] * 32 + data[i + 2];
    i += 3;
    if (i + length > end) return null;
    if (tag == 6) {
      if (seenExpiry || length > 7) return null;
      seenExpiry = true;
      expiry = _number(data.sublist(i, i + length));
    }
    i += length;
  }
  return Bolt11Summary(
    network: network,
    amountMsat: amountMsat,
    createdAt:
        DateTime.fromMillisecondsSinceEpoch(created * 1000, isUtc: true),
    expiresAt: DateTime.fromMillisecondsSinceEpoch((created + expiry) * 1000,
        isUtc: true),
  );
}

/// A Cash App onramp reply that passed [verifyCashAppOnramp]. [order]
/// carries only the payment links the app may open; any other link is
/// blanked so nothing downstream can launch it.
class VerifiedCashAppOnramp {
  const VerifiedCashAppOnramp._(this.order, this.invoice);

  final OrchestraOnrampResponse order;
  final Bolt11Summary invoice;
}

/// How far the invoice may sit from the typed dollars at the local price.
/// ±15% covers Orchestra's fee and spread on a small buy plus the drift
/// between the local price feed and the provider's, while still catching
/// an invoice for a different amount than the person asked to buy.
const double kCashAppInvoiceUsdTolerance = 0.15;

/// The invoice must stay payable for at least this long after the check,
/// or Cash App would open on an invoice it can no longer pay.
const Duration kCashAppInvoiceMinRemaining = Duration(seconds: 15);

bool _isCashAppHost(String host) {
  final h = host.toLowerCase();
  return h == 'cash.app' || h.endsWith('.cash.app');
}

bool _looksLikeInvoice(String value) =>
    RegExp(r'^(lightning:)?ln(bcrt|bc|tbs|tb)[0-9a-z]*1[0-9a-z]+$',
            caseSensitive: false)
        .hasMatch(value.trim());

bool _sameInvoice(String a, String b) =>
    _normalizeInvoice(a).toLowerCase() == _normalizeInvoice(b).toLowerCase();

/// Every invoice-shaped value a link carries, in its path or its query.
Iterable<String> _embeddedInvoices(Uri uri) sync* {
  for (final segment in uri.pathSegments) {
    if (_looksLikeInvoice(segment)) yield segment;
  }
  for (final values in uri.queryParametersAll.values) {
    for (final v in values) {
      if (_looksLikeInvoice(v)) yield v;
    }
  }
  final fragment = uri.fragment;
  if (_looksLikeInvoice(fragment)) yield fragment;
}

/// Whether [link] is a Cash App link the app may open for [invoice]:
/// https on `cash.app` (or a subdomain), with no userinfo or port, and
/// every invoice it embeds equal to [invoice].
bool isAllowedCashAppLink(String link, String invoice) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !_isCashAppHost(uri.host)) {
    return false;
  }
  return _embeddedInvoices(uri).every((e) => _sameInvoice(e, invoice));
}

Never _reject(WalletGuardReason reason, [String? field]) =>
    throw WalletGuardException(reason, field: field);

/// Checks a Cash App onramp reply before Cash App is opened. Throws
/// [WalletGuardException] on the first failed rule:
///
/// 1. `depositAddress` is a well-formed BOLT11 invoice on the app's
///    network, carries an amount and is still payable.
/// 2. When [usdPerBtc] (the locally fetched price) is known, the invoice
///    is within [kCashAppInvoiceUsdTolerance] of [requestedUsd]. With no
///    local price the amount rule is skipped rather than blocking the buy:
///    Cash App still shows the dollar total before the person pays.
/// 3. `paymentLinks.cashApp`, when present, passes [isAllowedCashAppLink].
///    A link anywhere else is a tampered reply and refuses the order.
/// 4. `paymentLinks.shortUrl` is kept only when it passes the same rule.
///    Orchestra's own short links live on its host, not Cash App's, and
///    cannot be checked for the invoice, so they are dropped, not opened.
VerifiedCashAppOnramp verifyCashAppOnramp(
  OrchestraOnrampResponse order, {
  required double requestedUsd,
  required double? usdPerBtc,
  required DateTime now,
  bool mainnet = true,
  double tolerance = kCashAppInvoiceUsdTolerance,
}) {
  final invoice = order.depositAddress;
  final summary = decodeBolt11Summary(invoice);
  if (summary == null) {
    _reject(WalletGuardReason.depositAddressFormat, 'invoice');
  }
  if ((summary.network == 'bc') != mainnet) {
    _reject(WalletGuardReason.depositAddressFormat, 'invoice_network');
  }
  final amountMsat = summary.amountMsat;
  if (amountMsat == null) {
    _reject(WalletGuardReason.amountMismatch, 'invoice_amount');
  }
  if (!summary.expiresAt.isAfter(now.add(kCashAppInvoiceMinRemaining))) {
    _reject(WalletGuardReason.quoteExpired, 'invoice');
  }

  final price = usdPerBtc;
  if (price != null && price.isFinite && price > 0) {
    if (!requestedUsd.isFinite || requestedUsd <= 0) {
      _reject(WalletGuardReason.amountMismatch, 'requested_usd');
    }
    final invoiceUsd = amountMsat.toDouble() / 1e11 * price;
    final ratio = invoiceUsd / requestedUsd;
    if (!ratio.isFinite ||
        ratio < 1 - tolerance ||
        ratio > 1 + tolerance) {
      _reject(WalletGuardReason.amountMismatch, 'invoice_amount');
    }
  }

  final cashApp = order.paymentLinks.cashApp.trim();
  if (cashApp.isNotEmpty && !isAllowedCashAppLink(cashApp, invoice)) {
    _reject(WalletGuardReason.echoMismatch, 'cash_app_link');
  }
  final short = order.paymentLinks.shortUrl.trim();
  final keptShort =
      short.isNotEmpty && isAllowedCashAppLink(short, invoice) ? short : '';

  final sanitized = cashApp == order.paymentLinks.cashApp &&
          keptShort == order.paymentLinks.shortUrl
      ? order
      : OrchestraOnrampResponse(
          orderId: order.orderId,
          quoteId: order.quoteId,
          depositAddress: order.depositAddress,
          paymentLinks:
              OrchestraPaymentLinks(cashApp: cashApp, shortUrl: keptShort),
          amountIn: order.amountIn,
          estimatedOut: order.estimatedOut,
          expiresAt: order.expiresAt,
        );
  return VerifiedCashAppOnramp._(sanitized, summary);
}
