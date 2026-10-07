import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/qr_scanner_provider.dart';

// ---------------------------------------------------------------------------
// Regex patterns extracted from SmartScannerScreen for unit-testing the
// detection/parsing logic used by the QR scanner flow.
// These mirror the static fields in lib/screens/scanner/smart_scanner_screen.dart.
// ---------------------------------------------------------------------------

/// Matches Bitcoin on-chain addresses (mainnet + testnet).
final _bitcoinRegex = RegExp(
  r'^(bc1|tb1|bcrt1)[a-z0-9]{25,}$|'      // bech32 / bech32m
  r'^[13][1-9A-HJ-NP-Za-km-z]{25,34}$|'   // P2PKH / P2SH
  r'^(bitcoin:)',                            // BIP21 URI
  caseSensitive: false,
);

/// Matches Lightning invoices / LNURL / Lightning addresses.
final _lightningRegex = RegExp(
  r'^(lnbc|lntb|lnurl|lightning:)',
  caseSensitive: false,
);

/// xpub / zpub / ypub etc.
final _xpubRegex =
    RegExp(r'^[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]{100,108}$');

/// Output descriptors.
final _descriptorRegex =
    RegExp(r'^(tr|wpkh|sh\(wpkh|pkh)\(.*[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]+.*\)$');

/// Helper that mirrors SmartScannerScreen._extractLightningParam.
String? extractLightningParam(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed != null) {
    final ln = parsed.queryParameters['lightning'];
    if (ln != null && ln.isNotEmpty) return ln;
  }
  return null;
}

/// Mirrors the manual BIP21 parsing in SmartScannerScreen._processInputManually.
/// Returns (address, amountSats).
(String, int) parseBip21Manually(String input) {
  final stripped =
      input.replaceFirst(RegExp(r'^bitcoin:', caseSensitive: false), '');
  final parts = stripped.split('?');
  final address = parts[0];
  int amount = 0;

  if (parts.length > 1) {
    final params = Uri.splitQueryString(parts[1]);
    final amountBtc = double.tryParse(params['amount'] ?? '');
    if (amountBtc != null) amount = (amountBtc * 100000000).round();
  }

  return (address, amount);
}

void main() {
  // =========================================================================
  // QrScannerState
  // =========================================================================
  group('QrScannerState', () {
    test('default values', () {
      const s = QrScannerState();
      expect(s.isScanningAnimated, false);
      expect(s.hasResult, false);
      expect(s.resultData, isNull);
      expect(s.progress, 0.0);
    });

    test('copyWith updates individual fields', () {
      const s = QrScannerState();
      final updated = s.copyWith(hasResult: true, resultData: 'data');
      expect(updated.hasResult, true);
      expect(updated.resultData, 'data');
      // untouched
      expect(updated.isScanningAnimated, false);
      expect(updated.progress, 0.0);
    });

    test('copyWith preserves existing values when nothing passed', () {
      final s = const QrScannerState().copyWith(
        isScanningAnimated: true,
        progress: 0.5,
      );
      final again = s.copyWith();
      expect(again.isScanningAnimated, true);
      expect(again.progress, 0.5);
    });
  });

  // =========================================================================
  // QrScannerNotifier — basic state machine
  // =========================================================================
  group('QrScannerNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('initial state is default QrScannerState', () {
      final state = container.read(qrScannerProvider);
      expect(state.hasResult, false);
      expect(state.resultData, isNull);
      expect(state.isScanningAnimated, false);
    });

    test('provider is autoDispose — fresh state after listeners removed', () async {
      final sub = container.listen(qrScannerProvider, (_, __) {});
      // read once to ensure state is alive
      expect(container.read(qrScannerProvider).hasResult, false);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      // After autoDispose, reading again gives a fresh notifier
      expect(container.read(qrScannerProvider).hasResult, false);
      expect(container.read(qrScannerProvider).resultData, isNull);
    });
  });

  // =========================================================================
  // Bitcoin address detection (regex)
  // =========================================================================
  group('Bitcoin address regex', () {
    test('matches bech32 mainnet address (bc1q)', () {
      expect(
        _bitcoinRegex.hasMatch('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        true,
      );
    });

    test('matches bech32m mainnet address (bc1p — taproot)', () {
      expect(
        _bitcoinRegex.hasMatch(
            'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297'),
        true,
      );
    });

    test('matches bech32 testnet address (tb1q)', () {
      expect(
        _bitcoinRegex.hasMatch('tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx'),
        true,
      );
    });

    test('matches regtest address (bcrt1)', () {
      expect(
        _bitcoinRegex.hasMatch('bcrt1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl'),
        true,
      );
    });

    test('matches P2PKH address (starts with 1)', () {
      expect(
        _bitcoinRegex.hasMatch('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'),
        true,
      );
    });

    test('matches P2SH address (starts with 3)', () {
      expect(
        _bitcoinRegex.hasMatch('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy'),
        true,
      );
    });

    test('matches BIP21 URI', () {
      expect(
        _bitcoinRegex.hasMatch('bitcoin:bc1qtest?amount=0.001'),
        true,
      );
    });

    test('matches BIP21 URI case-insensitive', () {
      expect(
        _bitcoinRegex.hasMatch('BITCOIN:BC1QTEST?amount=0.5'),
        true,
      );
    });

    test('rejects random string', () {
      expect(_bitcoinRegex.hasMatch('hello world'), false);
    });

    test('rejects empty string', () {
      expect(_bitcoinRegex.hasMatch(''), false);
    });

    test('rejects Ethereum address', () {
      expect(
        _bitcoinRegex.hasMatch('0x742d35Cc6634C0532925a3b844Bc9e7595f2bD28'),
        false,
      );
    });

    test('rejects Lightning invoice', () {
      expect(
        _bitcoinRegex.hasMatch(
            'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq'),
        false,
      );
    });

    test('rejects address that is too short', () {
      // P2PKH must be 25-34 chars after the first character
      expect(_bitcoinRegex.hasMatch('1abc'), false);
    });
  });

  // =========================================================================
  // Lightning regex
  // =========================================================================
  group('Lightning regex', () {
    test('matches BOLT11 mainnet invoice (lnbc)', () {
      expect(
        _lightningRegex.hasMatch(
            'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq'),
        true,
      );
    });

    test('matches BOLT11 testnet invoice (lntb)', () {
      expect(
        _lightningRegex.hasMatch('lntb100u1p0test'),
        true,
      );
    });

    test('matches lnurl', () {
      expect(
        _lightningRegex.hasMatch(
            'lnurl1dp68gurn8ghj7ctsdyh85etzv4jx2efwd9hj7a3s9acxz7tvdaskgtthd96xserjv9mkzmpdwfjhgatp'),
        true,
      );
    });

    test('matches LNURL uppercase', () {
      expect(
        _lightningRegex.hasMatch(
            'LNURL1DP68GURN8GHJ7CTSDYH85ETZV4JX2EFWD9HJ7A3S9ACXZ7TVDASKGTTHD96XSERJV9MKZMPDWFJHGATP'),
        true,
      );
    });

    test('matches lightning: URI scheme', () {
      expect(
        _lightningRegex.hasMatch('lightning:lnbc100n1p0testabc'),
        true,
      );
    });

    test('rejects Bitcoin address', () {
      expect(
        _lightningRegex.hasMatch('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        false,
      );
    });

    test('rejects empty string', () {
      expect(_lightningRegex.hasMatch(''), false);
    });

    test('rejects random string', () {
      expect(_lightningRegex.hasMatch('hello world'), false);
    });

    test('rejects BIP21 URI', () {
      expect(
        _lightningRegex.hasMatch('bitcoin:bc1qtest?amount=0.001'),
        false,
      );
    });
  });

  // =========================================================================
  // BIP21 URI parsing (manual)
  // =========================================================================
  group('BIP21 URI manual parsing', () {
    test('extracts address from simple BIP21', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      expect(address, 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      expect(amount, 0);
    });

    test('extracts address and amount', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=0.001');
      expect(address, 'bc1qtest');
      expect(amount, 100000); // 0.001 BTC = 100,000 sats
    });

    test('extracts amount of 1 BTC', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=1.0');
      expect(amount, 100000000);
    });

    test('extracts fractional amount 0.00000001 BTC (1 sat)', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=0.00000001');
      expect(amount, 1);
    });

    test('handles BIP21 with label parameter (label is ignored, amount extracted)', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=0.5&label=Donation');
      expect(address, 'bc1qtest');
      expect(amount, 50000000);
    });

    test('handles BIP21 with message parameter', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=0.01&message=Thank%20you');
      expect(address, 'bc1qtest');
      expect(amount, 1000000);
    });

    test('handles BIP21 with no amount parameter', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?label=MyAddress');
      expect(address, 'bc1qtest');
      expect(amount, 0);
    });

    test('handles BIP21 with only label (no amount)', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa?label=Satoshi');
      expect(address, '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa');
      expect(amount, 0);
    });

    test('handles case-insensitive BITCOIN: prefix', () {
      final (address, amount) = parseBip21Manually(
          'BITCOIN:bc1qtest?amount=0.1');
      expect(address, 'bc1qtest');
      expect(amount, 10000000);
    });

    test('handles BIP21 with invalid amount (non-numeric)', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=abc');
      expect(address, 'bc1qtest');
      expect(amount, 0); // double.tryParse returns null
    });

    test('handles BIP21 with zero amount', () {
      final (_, amount) = parseBip21Manually('bitcoin:bc1qtest?amount=0');
      expect(amount, 0);
    });

    test('handles BIP21 with P2PKH address', () {
      final (address, _) = parseBip21Manually(
          'bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa');
      expect(address, '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa');
    });

    test('handles BIP21 with P2SH address', () {
      final (address, _) = parseBip21Manually(
          'bitcoin:3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy');
      expect(address, '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy');
    });

    test('handles BIP21 with multiple query parameters', () {
      final (address, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=0.05&label=Test&message=Hello&req-custom=value');
      expect(address, 'bc1qtest');
      expect(amount, 5000000);
    });
  });

  // =========================================================================
  // Lightning parameter extraction from BIP21
  // =========================================================================
  group('extractLightningParam from BIP21', () {
    test('extracts lightning invoice from unified BIP21', () {
      final result = extractLightningParam(
          'bitcoin:bc1qtest?amount=0.001&lightning=lnbc100n1p0testabc');
      expect(result, 'lnbc100n1p0testabc');
    });

    test('returns null when no lightning param', () {
      final result = extractLightningParam('bitcoin:bc1qtest?amount=0.001');
      expect(result, isNull);
    });

    test('returns null for empty lightning param', () {
      final result = extractLightningParam('bitcoin:bc1qtest?lightning=');
      expect(result, isNull);
    });

    test('returns null for non-URI string', () {
      final result = extractLightningParam('just a random string');
      expect(result, isNull);
    });

    test('extracts lightning param with other params', () {
      final result = extractLightningParam(
          'bitcoin:bc1qtest?label=Donation&lightning=lnbc500n1xyz&amount=0.005');
      expect(result, 'lnbc500n1xyz');
    });

    test('handles URL-encoded lightning param', () {
      final result = extractLightningParam(
          'bitcoin:bc1qtest?lightning=lnbc100n1p0test%20abc');
      expect(result, 'lnbc100n1p0test abc');
    });
  });

  // =========================================================================
  // Amount extraction edge cases
  // =========================================================================
  group('Amount extraction from BIP21', () {
    test('large BTC amount (21 million)', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=21000000');
      expect(amount, 2100000000000000);
    });

    test('very small BTC amount', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=0.00001');
      expect(amount, 1000);
    });

    test('amount with trailing zeros', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=1.00000000');
      expect(amount, 100000000);
    });

    test('amount without decimal', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=5');
      expect(amount, 500000000);
    });

    test('negative amount returns negative sats', () {
      final (_, amount) = parseBip21Manually(
          'bitcoin:bc1qtest?amount=-0.001');
      expect(amount, -100000);
    });
  });

  // =========================================================================
  // Label parsing
  // =========================================================================
  group('Label parsing from BIP21 query params', () {
    test('label is present in query string', () {
      final uri = Uri.parse('bitcoin:bc1qtest?label=My%20Wallet&amount=0.01');
      expect(uri.queryParameters['label'], 'My Wallet');
    });

    test('label with special characters', () {
      final uri = Uri.parse(
          'bitcoin:bc1qtest?label=Caf%C3%A9%20Payment&amount=0.5');
      expect(uri.queryParameters['label'], 'Caf\u00e9 Payment');
    });

    test('label missing from query string', () {
      final uri = Uri.parse('bitcoin:bc1qtest?amount=0.01');
      expect(uri.queryParameters['label'], isNull);
    });

    test('empty label', () {
      final uri = Uri.parse('bitcoin:bc1qtest?label=&amount=0.01');
      expect(uri.queryParameters['label'], '');
    });

    test('message parameter is also accessible', () {
      final uri = Uri.parse(
          'bitcoin:bc1qtest?label=Store&message=Order%20%231234');
      expect(uri.queryParameters['message'], 'Order #1234');
    });
  });

  // =========================================================================
  // Spark address detection
  // =========================================================================
  group('Spark address detection', () {
    // Spark addresses typically start with "sp1" (mainnet) or "sprt1" (regtest).
    // The Breez SDK handles actual validation; here we verify the patterns that
    // would NOT match the Bitcoin/Lightning regexes (and thus fall through to
    // the SDK-based identifyInputTypeProvider which returns AnalyzedPaymentType.spark).

    test('sp1 address does not match Bitcoin regex', () {
      const sparkAddr =
          'sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgqjuexzk6murw56suy3e0rd2cgqvycxttddwsvgxe2usfpxumr70xc9pkqwv';
      expect(_bitcoinRegex.hasMatch(sparkAddr), false);
    });

    test('sp1 address does not match Lightning regex', () {
      const sparkAddr =
          'sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgqjuexzk6murw56suy3e0rd2cgqvycxttddwsvgxe2usfpxumr70xc9pkqwv';
      expect(_lightningRegex.hasMatch(sparkAddr), false);
    });

    test('sprt1 address does not match Bitcoin regex', () {
      const sparkAddr = 'sprt1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgtest';
      expect(_bitcoinRegex.hasMatch(sparkAddr), false);
    });

    test('sprt1 address does not match Lightning regex', () {
      const sparkAddr = 'sprt1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgtest';
      expect(_lightningRegex.hasMatch(sparkAddr), false);
    });
  });

  // =========================================================================
  // LNURL detection
  // =========================================================================
  group('LNURL detection', () {
    test('lnurl bech32 string matches Lightning regex', () {
      const lnurl =
          'lnurl1dp68gurn8ghj7ctsdyh85etzv4jx2efwd9hj7a3s9acxz7tvdaskgtthd96xserjv9mkzmpdwfjhgatp';
      expect(_lightningRegex.hasMatch(lnurl), true);
    });

    test('LNURL uppercase matches Lightning regex', () {
      const lnurl =
          'LNURL1DP68GURN8GHJ7CTSDYH85ETZV4JX2EFWD9HJ7A3S9ACXZ7TVDASKGTTHD96XSERJV9MKZMPDWFJHGATP';
      expect(_lightningRegex.hasMatch(lnurl), true);
    });

    test('lightning address (user@domain) does not match Bitcoin regex', () {
      // Lightning addresses like user@domain.com are handled by Breez SDK,
      // not by the regex patterns, so they should NOT match either regex.
      const lnAddr = 'user@walletofsatoshi.com';
      expect(_bitcoinRegex.hasMatch(lnAddr), false);
      expect(_lightningRegex.hasMatch(lnAddr), false);
    });

    test('lightning: URI with lnurl matches', () {
      expect(
        _lightningRegex.hasMatch(
            'lightning:lnurl1dp68gurn8ghj7ctsdyh85etzv4jx2efwd9hj7test'),
        true,
      );
    });
  });

  // =========================================================================
  // xpub / descriptor detection
  // =========================================================================
  group('xpub regex', () {
    test('matches xpub', () {
      // 111 chars after "xpub" prefix
      final xpub = 'xpub${'1' * 107}';
      expect(_xpubRegex.hasMatch(xpub), true);
    });

    test('matches zpub', () {
      final zpub = 'zpub${'1' * 104}';
      expect(_xpubRegex.hasMatch(zpub), true);
    });

    test('matches ypub', () {
      final ypub = 'ypub${'1' * 103}';
      expect(_xpubRegex.hasMatch(ypub), true);
    });

    test('matches tpub (testnet)', () {
      final tpub = 'tpub${'1' * 105}';
      expect(_xpubRegex.hasMatch(tpub), true);
    });

    test('rejects too-short xpub', () {
      final shortXpub = 'xpub${'1' * 50}';
      expect(_xpubRegex.hasMatch(shortXpub), false);
    });

    test('rejects too-long xpub', () {
      final longXpub = 'xpub${'1' * 120}';
      expect(_xpubRegex.hasMatch(longXpub), false);
    });

    test('rejects random string', () {
      expect(_xpubRegex.hasMatch('not_an_xpub'), false);
    });
  });

  group('descriptor regex', () {
    test('matches wpkh descriptor', () {
      final desc = 'wpkh(xpub${'1' * 104})';
      expect(_descriptorRegex.hasMatch(desc), true);
    });

    test('matches tr descriptor (taproot)', () {
      final desc = 'tr(xpub${'1' * 104})';
      expect(_descriptorRegex.hasMatch(desc), true);
    });

    test('matches pkh descriptor', () {
      final desc = 'pkh(xpub${'1' * 104})';
      expect(_descriptorRegex.hasMatch(desc), true);
    });

    test('matches sh(wpkh descriptor (nested segwit)', () {
      final desc = 'sh(wpkh(zpub${'1' * 104}))';
      expect(_descriptorRegex.hasMatch(desc), true);
    });

    test('rejects descriptor without valid xpub inside', () {
      expect(_descriptorRegex.hasMatch('wpkh(invalid_key)'), false);
    });
  });

  // =========================================================================
  // Unknown / invalid inputs
  // =========================================================================
  group('Unknown and invalid inputs', () {
    test('empty string matches nothing', () {
      expect(_bitcoinRegex.hasMatch(''), false);
      expect(_lightningRegex.hasMatch(''), false);
      expect(_xpubRegex.hasMatch(''), false);
      expect(_descriptorRegex.hasMatch(''), false);
    });

    test('random text matches nothing', () {
      const input = 'this is not a valid payment request';
      expect(_bitcoinRegex.hasMatch(input), false);
      expect(_lightningRegex.hasMatch(input), false);
    });

    test('Ethereum address matches nothing', () {
      const eth = '0x742d35Cc6634C0532925a3b844Bc9e7595f2bD28';
      expect(_bitcoinRegex.hasMatch(eth), false);
      expect(_lightningRegex.hasMatch(eth), false);
    });

    test('Solana address matches nothing', () {
      const sol = '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T';
      expect(_bitcoinRegex.hasMatch(sol), false);
      expect(_lightningRegex.hasMatch(sol), false);
    });

    test('URL matches nothing', () {
      const url = 'https://example.com/payment';
      expect(_bitcoinRegex.hasMatch(url), false);
      expect(_lightningRegex.hasMatch(url), false);
    });

    test('numeric string matches nothing', () {
      expect(_bitcoinRegex.hasMatch('12345'), false);
      expect(_lightningRegex.hasMatch('12345'), false);
    });

    test('partial prefix "bit" does not match', () {
      expect(_bitcoinRegex.hasMatch('bit:something'), false);
    });

    test('partial prefix "ln" without full match does not match', () {
      expect(_lightningRegex.hasMatch('ln_something'), false);
    });

    test('BIP21 with empty address after prefix', () {
      // "bitcoin:" with no address — still matches the regex (prefix match)
      expect(_bitcoinRegex.hasMatch('bitcoin:'), true);
      // But manual parsing returns empty address
      final (address, amount) = parseBip21Manually('bitcoin:');
      expect(address, '');
      expect(amount, 0);
    });

    test('BIP21 with only query params, no address', () {
      final (address, amount) = parseBip21Manually('bitcoin:?amount=0.01');
      expect(address, '');
      expect(amount, 1000000);
    });
  });

  // =========================================================================
  // QR code routing logic — BBQr vs UR vs plain
  // =========================================================================
  group('QR code routing patterns', () {
    test('BBQr frames start with B\$', () {
      // The notifier routes codes starting with "B$" to _handleBbqrFrame
      expect('B\$001122'.startsWith('B\$'), true);
    });

    test('UR frames start with ur: (case-insensitive)', () {
      expect('ur:crypto-psbt/1-3/abc'.toLowerCase().startsWith('ur:'), true);
      expect('UR:CRYPTO-PSBT/1-3/ABC'.toLowerCase().startsWith('ur:'), true);
    });

    test('plain Bitcoin address does not match BBQr or UR prefix', () {
      const addr = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
      expect(addr.startsWith('B\$'), false);
      expect(addr.toLowerCase().startsWith('ur:'), false);
    });

    test('plain Lightning invoice does not match BBQr or UR prefix', () {
      const invoice = 'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqtest';
      expect(invoice.startsWith('B\$'), false);
      expect(invoice.toLowerCase().startsWith('ur:'), false);
    });

    test('plain BIP21 URI does not match BBQr or UR prefix', () {
      const bip21 = 'bitcoin:bc1qtest?amount=0.001';
      expect(bip21.startsWith('B\$'), false);
      expect(bip21.toLowerCase().startsWith('ur:'), false);
    });
  });

  // =========================================================================
  // Unified BIP21 with Lightning parameter (real-world format)
  // =========================================================================
  group('Unified BIP21 with lightning parameter', () {
    test('detects unified BIP21 with lightning param', () {
      const unified =
          'bitcoin:bc1qtest?amount=0.001&lightning=lnbc100n1p0testabc';
      expect(unified.toLowerCase().startsWith('bitcoin:'), true);
      expect(unified.toLowerCase().contains('lightning='), true);
    });

    test('extracts lightning invoice from unified BIP21', () {
      const unified =
          'bitcoin:bc1qtest?amount=0.001&lightning=lnbc100n1p0testabc';
      final lnParam = extractLightningParam(unified);
      expect(lnParam, 'lnbc100n1p0testabc');
    });

    test('non-unified BIP21 does not have lightning param', () {
      const plain = 'bitcoin:bc1qtest?amount=0.001';
      expect(plain.toLowerCase().contains('lightning='), false);
      final lnParam = extractLightningParam(plain);
      expect(lnParam, isNull);
    });

    test('unified BIP21 with LNURL as lightning param', () {
      const unified =
          'bitcoin:bc1qtest?lightning=lnurl1dp68gurn8ghj7test';
      final lnParam = extractLightningParam(unified);
      expect(lnParam, 'lnurl1dp68gurn8ghj7test');
    });
  });

  // =========================================================================
  // _looksLikeXpub helper (tested via regex since method is private)
  // =========================================================================
  group('looksLikeXpub detection', () {
    // This mirrors the logic of _looksLikeXpub in qr_scanner_provider.dart
    bool looksLikeXpub(String s) {
      return s.startsWith('xpub') || s.startsWith('ypub') ||
          s.startsWith('zpub') || s.startsWith('tpub') ||
          s.startsWith('upub') || s.startsWith('vpub');
    }

    test('xpub is recognized', () {
      expect(looksLikeXpub('xpub661MyMwAqRbcTest'), true);
    });

    test('ypub is recognized', () {
      expect(looksLikeXpub('ypub6QqdH2c5z7Test'), true);
    });

    test('zpub is recognized', () {
      expect(looksLikeXpub('zpub6rFR7y4Q2AijBTest'), true);
    });

    test('tpub (testnet) is recognized', () {
      expect(looksLikeXpub('tpub661TestnetKey'), true);
    });

    test('upub is recognized', () {
      expect(looksLikeXpub('upub5Df31xBPgTest'), true);
    });

    test('vpub is recognized', () {
      expect(looksLikeXpub('vpub5SLqN2bTest'), true);
    });

    test('random string is not recognized', () {
      expect(looksLikeXpub('notaxpub'), false);
    });

    test('empty string is not recognized', () {
      expect(looksLikeXpub(''), false);
    });

    test('Bitcoin address is not recognized', () {
      expect(looksLikeXpub('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'), false);
    });
  });

  // =========================================================================
  // Edge cases: case sensitivity
  // =========================================================================
  group('Case sensitivity handling', () {
    test('BIP21 prefix is case-insensitive', () {
      expect(_bitcoinRegex.hasMatch('Bitcoin:bc1qtest'), true);
      expect(_bitcoinRegex.hasMatch('BITCOIN:BC1QTEST'), true);
      expect(_bitcoinRegex.hasMatch('bitcoin:bc1qtest'), true);
    });

    test('Lightning prefix is case-insensitive', () {
      expect(_lightningRegex.hasMatch('LNBC100test'), true);
      expect(_lightningRegex.hasMatch('lnbc100test'), true);
      expect(_lightningRegex.hasMatch('Lnbc100test'), true);
    });

    test('LNURL is case-insensitive', () {
      expect(_lightningRegex.hasMatch('LNURL1test'), true);
      expect(_lightningRegex.hasMatch('lnurl1test'), true);
    });

    test('bech32 addresses are case-insensitive in regex', () {
      // The regex has caseSensitive: false
      expect(_bitcoinRegex.hasMatch('BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4'), true);
    });
  });

  // =========================================================================
  // Mixed / ambiguous inputs
  // =========================================================================
  group('Mixed and ambiguous inputs', () {
    test('bitcoin: prefix takes priority over address-only matching', () {
      const input = 'bitcoin:lnbc100test';
      // Matches the BIP21 prefix rule
      expect(_bitcoinRegex.hasMatch(input), true);
      // But NOT Lightning regex (doesn't start with ln*)
      expect(_lightningRegex.hasMatch(input), false);
    });

    test('address starting with 1 but too short is rejected', () {
      expect(_bitcoinRegex.hasMatch('1short'), false);
    });

    test('address starting with 3 but too short is rejected', () {
      expect(_bitcoinRegex.hasMatch('3short'), false);
    });

    test('P2PKH address at max length (34 chars total) matches', () {
      final addr = '1${'A' * 33}';
      expect(addr.length, 34);
      // 33 chars after "1", which is within 25-34 range
      expect(_bitcoinRegex.hasMatch(addr), true);
    });

    test('P2PKH address at min length (26 chars total) matches', () {
      final addr = '1${'A' * 25}';
      expect(addr.length, 26);
      expect(_bitcoinRegex.hasMatch(addr), true);
    });
  });
}
