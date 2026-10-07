import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/orchestra/cash_app_onramp_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

int _polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) == 1) chk ^= gen[i];
    }
  }
  return chk;
}

List<int> _words(int value, int count) =>
    [for (var i = count - 1; i >= 0; i--) (value >> (5 * i)) & 31];

/// A BOLT11-shaped invoice with a valid bech32 checksum. The signature is
/// zeros: the guard never checks it.
String _invoice({
  String hrp = 'lnbc',
  required int timestamp,
  int? expirySeconds,
}) {
  final data = <int>[
    ..._words(timestamp, 7),
    // p tag: 52 words of payment hash.
    1, 1, 20, ...List.filled(52, 3),
    if (expirySeconds != null) ...[6, 0, 4, ..._words(expirySeconds, 4)],
    ...List.filled(104, 0),
  ];
  final expanded = [
    for (final c in hrp.codeUnits) c >> 5,
    0,
    for (final c in hrp.codeUnits) c & 31,
  ];
  final mod = _polymod([...expanded, ...data, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksum = [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  return '${hrp}1${[...data, ...checksum].map((w) => _charset[w]).join()}';
}

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);
  final ts = now.millisecondsSinceEpoch ~/ 1000;
  // $50 at $100,000 is 50,000 sats = 500u.
  final invoice = _invoice(hrp: 'lnbc500u', timestamp: ts, expirySeconds: 600);

  OrchestraOnrampResponse order({
    String? deposit,
    String? cashApp,
    String? shortUrl,
  }) =>
      OrchestraOnrampResponse(
        orderId: 'ord_1',
        quoteId: 'q_1',
        depositAddress: deposit ?? invoice,
        paymentLinks: OrchestraPaymentLinks(
          cashApp: cashApp ?? 'https://cash.app/launch/lightning/$invoice',
          shortUrl: shortUrl ?? 'https://orchestration.flashnet.xyz/pay/8fQ2kL',
        ),
        amountIn: '50000',
        estimatedOut: '49000000',
        expiresAt: '',
      );

  VerifiedCashAppOnramp verify(OrchestraOnrampResponse o,
          {double usd = 50, double? price = 100000, DateTime? at}) =>
      verifyCashAppOnramp(o,
          requestedUsd: usd, usdPerBtc: price, now: at ?? now);

  Matcher rejects(WalletGuardReason reason) => throwsA(
      isA<WalletGuardException>().having((e) => e.reason, 'reason', reason));

  group('decodeBolt11Summary', () {
    test('reads network, amount and expiry', () {
      final s = decodeBolt11Summary(invoice)!;
      expect(s.network, 'bc');
      expect(s.amountMsat, BigInt.from(50000000));
      expect(s.expiresAt, now.add(const Duration(seconds: 600)));
    });

    test('defaults the expiry to an hour and accepts a lightning: prefix', () {
      final s = decodeBolt11Summary(
          'lightning:${_invoice(hrp: 'lnbc1m', timestamp: ts)}')!;
      expect(s.amountMsat, BigInt.from(100000000));
      expect(s.expiresAt, now.add(const Duration(hours: 1)));
    });

    test('decodes the BOLT11 spec vector', () {
      // BOLT #11 "Please send \$3 for a cup of coffee ... within one minute".
      const v = 'lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3'
          'zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfq'
          'ypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmd'
          'la2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven0'
          '9sam30g4vgpfna3rh';
      final s = decodeBolt11Summary(v)!;
      expect(s.network, 'bc');
      expect(s.amountMsat, BigInt.from(250000000));
      expect(s.createdAt, DateTime.utc(2017, 6, 1, 10, 57, 38));
      expect(s.expiresAt, DateTime.utc(2017, 6, 1, 10, 58, 38));
    });

    test('refuses a broken checksum or a non-invoice', () {
      final broken = '${invoice.substring(0, invoice.length - 1)}'
          '${invoice.endsWith('q') ? 'p' : 'q'}';
      expect(decodeBolt11Summary(broken), isNull);
      expect(decodeBolt11Summary('bc1qnotaninvoice'), isNull);
      expect(decodeBolt11Summary(''), isNull);
    });
  });

  group('verifyCashAppOnramp', () {
    test('passes a well-formed reply and keeps the Cash App link', () {
      final v = verify(order());
      expect(v.order.paymentLinks.cashApp,
          'https://cash.app/launch/lightning/$invoice');
      // Orchestra's short link is on its own host: dropped, not opened.
      expect(v.order.paymentLinks.shortUrl, isEmpty);
      expect(v.order.depositAddress, invoice);
    });

    test('keeps a cash.app short link', () {
      final v = verify(order(shortUrl: 'https://cash.app/\$kute'));
      expect(v.order.paymentLinks.shortUrl, 'https://cash.app/\$kute');
    });

    test('refuses a malformed invoice', () {
      expect(() => verify(order(deposit: 'lnbc-garbage')),
          rejects(WalletGuardReason.depositAddressFormat));
    });

    test('refuses a testnet invoice on mainnet', () {
      final tb = _invoice(hrp: 'lntb500u', timestamp: ts, expirySeconds: 600);
      expect(
          () => verify(order(
              deposit: tb, cashApp: 'https://cash.app/launch/lightning/$tb')),
          rejects(WalletGuardReason.depositAddressFormat));
    });

    test('refuses an expired or nearly expired invoice', () {
      expect(() => verify(order(), at: now.add(const Duration(minutes: 10))),
          rejects(WalletGuardReason.quoteExpired));
      expect(
          () => verify(order(),
              at: now.add(const Duration(seconds: 600 - 10))),
          rejects(WalletGuardReason.quoteExpired));
    });

    test('refuses an amountless invoice', () {
      final none = _invoice(timestamp: ts, expirySeconds: 600);
      expect(
          () => verify(order(
              deposit: none,
              cashApp: 'https://cash.app/launch/lightning/$none')),
          rejects(WalletGuardReason.amountMismatch));
    });

    test('allows the amount within 15% of the typed dollars', () {
      expect(() => verify(order(), usd: 44), returnsNormally); // +13.6%
      expect(() => verify(order(), usd: 57), returnsNormally); // -12.3%
      expect(() => verify(order(), usd: 40),
          rejects(WalletGuardReason.amountMismatch)); // +25%
      expect(() => verify(order(), usd: 100),
          rejects(WalletGuardReason.amountMismatch)); // -50%
    });

    test('skips the amount rule without a local price', () {
      expect(() => verify(order(), usd: 500, price: null), returnsNormally);
      expect(() => verify(order(), usd: 500, price: 0), returnsNormally);
    });

    test('refuses a Cash App link on another host or scheme', () {
      for (final link in [
        'http://cash.app/launch/lightning/$invoice',
        'https://cash.app.evil.example/launch/lightning/$invoice',
        'https://evilcash.app/launch/lightning/$invoice',
        'https://user@cash.app/launch/lightning/$invoice',
        'https://cash.app:8443/launch/lightning/$invoice',
        'cashapp://launch/lightning/$invoice',
        'javascript:alert(1)',
      ]) {
        expect(() => verify(order(cashApp: link)),
            rejects(WalletGuardReason.echoMismatch),
            reason: link);
      }
    });

    test('refuses a Cash App link carrying another invoice', () {
      final other =
          _invoice(hrp: 'lnbc500u', timestamp: ts + 1, expirySeconds: 600);
      expect(
          () => verify(
              order(cashApp: 'https://cash.app/launch/lightning/$other')),
          rejects(WalletGuardReason.echoMismatch));
      expect(
          () => verify(order(
              cashApp: 'https://cash.app/launch/lightning?invoice=$other')),
          rejects(WalletGuardReason.echoMismatch));
    });

    test('drops a cash.app short link that carries another invoice', () {
      final other =
          _invoice(hrp: 'lnbc500u', timestamp: ts + 1, expirySeconds: 600);
      final v = verify(
          order(shortUrl: 'https://cash.app/launch/lightning/$other'));
      expect(v.order.paymentLinks.shortUrl, isEmpty);
    });

    test('matches the invoice case-insensitively', () {
      expect(
          () => verify(order(
              cashApp:
                  'https://cash.app/launch/lightning/${invoice.toUpperCase()}')),
          returnsNormally);
    });
  });

  group('isAllowedCashAppLink', () {
    test('accepts cash.app and subdomains over https only', () {
      expect(isAllowedCashAppLink('https://cash.app/x', invoice), isTrue);
      expect(isAllowedCashAppLink('https://www.cash.app/x', invoice), isTrue);
      expect(isAllowedCashAppLink('https://cash.apps/x', invoice), isFalse);
      expect(
          isAllowedCashAppLink(
              'https://orchestration.flashnet.xyz/pay/abc', invoice),
          isFalse);
      expect(isAllowedCashAppLink('not a url', invoice), isFalse);
    });
  });
}
