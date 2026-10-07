import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/address_model.dart';
import 'package:kute/models/send_tx_model.dart';

void main() {
  group('AddressAndAmount', () {
    test('constructor sets all fields', () {
      final aa = AddressAndAmount('bc1qtest', 50000, 'btc');
      expect(aa.address, 'bc1qtest');
      expect(aa.amount, 50000);
      expect(aa.assetId, 'btc');
      expect(aa.type, PaymentType.Unknown);
    });

    test('default type is Unknown', () {
      final aa = AddressAndAmount('addr', 100, null);
      expect(aa.type, PaymentType.Unknown);
    });

    test('explicit type overrides default', () {
      final aa = AddressAndAmount('lnbc1...', 1000, null, type: PaymentType.Lightning);
      expect(aa.type, PaymentType.Lightning);
    });

    test('type can be Bitcoin', () {
      final aa = AddressAndAmount('bc1qxyz', 500, null, type: PaymentType.Bitcoin);
      expect(aa.type, PaymentType.Bitcoin);
    });

    test('type can be Spark', () {
      final aa = AddressAndAmount('sp1abc', 200, 'spark_asset', type: PaymentType.Spark);
      expect(aa.type, PaymentType.Spark);
    });

    test('type can be NonNative', () {
      final aa = AddressAndAmount('0xabc', 0, 'eth', type: PaymentType.NonNative);
      expect(aa.type, PaymentType.NonNative);
    });

    test('amount can be null', () {
      final aa = AddressAndAmount('addr', null, null);
      expect(aa.amount, isNull);
    });

    test('assetId can be null', () {
      final aa = AddressAndAmount('addr', 100, null);
      expect(aa.assetId, isNull);
    });

    test('amount can be zero', () {
      final aa = AddressAndAmount('addr', 0, null);
      expect(aa.amount, 0);
    });

    test('empty address string', () {
      final aa = AddressAndAmount('', 0, null);
      expect(aa.address, '');
    });

    test('large amount value', () {
      final aa = AddressAndAmount('addr', 2100000000000000, null);
      expect(aa.amount, 2100000000000000);
    });

    test('negative amount value', () {
      final aa = AddressAndAmount('addr', -1, null);
      expect(aa.amount, -1);
    });
  });

  group('Address', () {
    test('constructor with required fields', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
      );
      expect(addr.bitcoinAddressIndex, 0);
      expect(addr.bitcoinAddress, 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      expect(addr.lightningAddress, isNull);
    });

    test('constructor with lightningAddress', () {
      final addr = Address(
        bitcoinAddressIndex: 5,
        bitcoinAddress: 'bc1qtest',
        lightningAddress: 'user@getalby.com',
      );
      expect(addr.lightningAddress, 'user@getalby.com');
    });

    test('copyWith overrides bitcoinAddressIndex', () {
      final addr = Address(bitcoinAddressIndex: 0, bitcoinAddress: 'bc1q');
      final copy = addr.copyWith(bitcoinAddressIndex: 10);
      expect(copy.bitcoinAddressIndex, 10);
      expect(copy.bitcoinAddress, 'bc1q');
      expect(copy.lightningAddress, isNull);
    });

    test('copyWith overrides bitcoinAddress', () {
      final addr = Address(bitcoinAddressIndex: 0, bitcoinAddress: 'old');
      final copy = addr.copyWith(bitcoinAddress: 'new');
      expect(copy.bitcoinAddress, 'new');
      expect(copy.bitcoinAddressIndex, 0);
    });

    test('copyWith overrides lightningAddress', () {
      final addr = Address(bitcoinAddressIndex: 0, bitcoinAddress: 'bc1q');
      final copy = addr.copyWith(lightningAddress: 'ln@example.com');
      expect(copy.lightningAddress, 'ln@example.com');
    });

    test('copyWith preserves all when no args', () {
      final addr = Address(
        bitcoinAddressIndex: 3,
        bitcoinAddress: 'bc1qabc',
        lightningAddress: 'test@ln.com',
      );
      final copy = addr.copyWith();
      expect(copy.bitcoinAddressIndex, 3);
      expect(copy.bitcoinAddress, 'bc1qabc');
      expect(copy.lightningAddress, 'test@ln.com');
    });

    test('copyWith does not modify original', () {
      final addr = Address(bitcoinAddressIndex: 0, bitcoinAddress: 'original');
      final copy = addr.copyWith(bitcoinAddress: 'modified');
      expect(addr.bitcoinAddress, 'original');
      expect(copy.bitcoinAddress, 'modified');
    });

    test('copyWith with all parameters overridden', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'old',
        lightningAddress: 'old@ln.com',
      );
      final copy = addr.copyWith(
        bitcoinAddressIndex: 99,
        bitcoinAddress: 'new_addr',
        lightningAddress: 'new@ln.com',
      );
      expect(copy.bitcoinAddressIndex, 99);
      expect(copy.bitcoinAddress, 'new_addr');
      expect(copy.lightningAddress, 'new@ln.com');
    });

    test('lightningAddress defaults to null', () {
      final addr = Address(bitcoinAddressIndex: 0, bitcoinAddress: 'addr');
      expect(addr.lightningAddress, isNull);
    });

    test('empty bitcoinAddress string', () {
      final addr = Address(bitcoinAddressIndex: 0, bitcoinAddress: '');
      expect(addr.bitcoinAddress, '');
    });

    test('negative bitcoinAddressIndex', () {
      final addr = Address(bitcoinAddressIndex: -1, bitcoinAddress: 'addr');
      expect(addr.bitcoinAddressIndex, -1);
    });

    test('large bitcoinAddressIndex', () {
      final addr = Address(bitcoinAddressIndex: 999999, bitcoinAddress: 'addr');
      expect(addr.bitcoinAddressIndex, 999999);
    });
  });

  group('Address with Bitcoin address formats', () {
    test('bech32 mainnet address (bc1q)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
      );
      expect(addr.bitcoinAddress, startsWith('bc1q'));
    });

    test('bech32m mainnet address (bc1p - taproot)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297',
      );
      expect(addr.bitcoinAddress, startsWith('bc1p'));
    });

    test('bech32 testnet address (tb1q)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      );
      expect(addr.bitcoinAddress, startsWith('tb1'));
    });

    test('bech32 regtest address (bcrt1)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bcrt1q6rhpng9evdsfnn833a4f4vmd8czlm0cjeh9f7n',
      );
      expect(addr.bitcoinAddress, startsWith('bcrt1'));
    });

    test('legacy P2PKH address (starts with 1)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
      );
      expect(addr.bitcoinAddress, startsWith('1'));
    });

    test('P2SH address (starts with 3)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
      );
      expect(addr.bitcoinAddress, startsWith('3'));
    });
  });

  group('Address with Lightning formats', () {
    test('lightning address (email-like)', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1qtest',
        lightningAddress: 'user@getalby.com',
      );
      expect(addr.lightningAddress, contains('@'));
    });

    test('lightning address empty string', () {
      final addr = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1qtest',
        lightningAddress: '',
      );
      expect(addr.lightningAddress, '');
    });
  });

  group('AddressAndAmount with address format validation patterns', () {
    // These tests verify that AddressAndAmount can store various address
    // formats. The actual validation/parsing happens in the scanner/breez
    // layer, but the model should faithfully store any string.

    group('Bitcoin mainnet addresses', () {
      test('bech32 (P2WPKH) address', () {
        final aa = AddressAndAmount(
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
          100000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('bc1q'));
        expect(aa.type, PaymentType.Bitcoin);
      });

      test('bech32m (P2TR / taproot) address', () {
        final aa = AddressAndAmount(
          'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297',
          50000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('bc1p'));
      });

      test('legacy P2PKH address', () {
        final aa = AddressAndAmount(
          '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
          10000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('1'));
      });

      test('P2SH address', () {
        final aa = AddressAndAmount(
          '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
          20000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('3'));
      });
    });

    group('Bitcoin testnet addresses', () {
      test('bech32 testnet address (tb1q)', () {
        final aa = AddressAndAmount(
          'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
          5000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('tb1'));
      });

      test('bech32m testnet taproot address (tb1p)', () {
        final aa = AddressAndAmount(
          'tb1p5cyxnuxmeuwuvkwfem96lqzszjjc7hsg55hrzke0tm85syvpenqs3yvjq2',
          0,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('tb1p'));
      });

      test('regtest bech32 address (bcrt1)', () {
        final aa = AddressAndAmount(
          'bcrt1q6rhpng9evdsfnn833a4f4vmd8czlm0cjeh9f7n',
          1000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('bcrt1'));
      });
    });

    group('Lightning addresses', () {
      test('bolt11 invoice (lnbc)', () {
        final aa = AddressAndAmount(
          'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq',
          100000,
          null,
          type: PaymentType.Lightning,
        );
        expect(aa.address, startsWith('lnbc'));
        expect(aa.type, PaymentType.Lightning);
      });

      test('testnet bolt11 invoice (lntb)', () {
        final aa = AddressAndAmount(
          'lntb1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypq',
          50000,
          null,
          type: PaymentType.Lightning,
        );
        expect(aa.address, startsWith('lntb'));
      });

      test('bolt12 offer (lno1)', () {
        final aa = AddressAndAmount(
          'lno1qgsyxjtl6luzd9t3pr62xr7eemp6awlejukt2rcn8r53hkftr38m6',
          0,
          null,
          type: PaymentType.Lightning,
        );
        expect(aa.address, startsWith('lno1'));
      });

      test('LNURL', () {
        final aa = AddressAndAmount(
          'lnurl1dp68gurn8ghj7mrfva58gumpw3ejucm0d5hkzurf9ask2ep0',
          0,
          null,
          type: PaymentType.Lightning,
        );
        expect(aa.address, startsWith('lnurl'));
      });

      test('lightning address (email format)', () {
        final aa = AddressAndAmount(
          'user@walletofsatoshi.com',
          10000,
          null,
          type: PaymentType.Lightning,
        );
        expect(aa.address, contains('@'));
      });
    });

    group('Spark addresses', () {
      test('spark address', () {
        final aa = AddressAndAmount(
          'sp1qqw5hn4hlkuu2lesxpqh6w6rm0krsjr0xn6yrefvnmsq8mzqxw40qzuy7nt',
          25000,
          null,
          type: PaymentType.Spark,
        );
        expect(aa.type, PaymentType.Spark);
      });

      test('spark address with amount zero', () {
        final aa = AddressAndAmount(
          'sp1qqw5hn4hlkuu2lesxpqh6w6rm0krsjr0xn6yrefvnmsq8mzqxw40qzuy7nt',
          0,
          null,
          type: PaymentType.Spark,
        );
        expect(aa.amount, 0);
        expect(aa.type, PaymentType.Spark);
      });
    });

    group('NonNative / cross-chain addresses', () {
      test('Ethereum address', () {
        final aa = AddressAndAmount(
          '0x742d35Cc6634C0532925a3b844Bc9e7595f2bD28',
          0,
          'eth',
          type: PaymentType.NonNative,
        );
        expect(aa.address, startsWith('0x'));
        expect(aa.type, PaymentType.NonNative);
        expect(aa.assetId, 'eth');
      });

      test('Solana address', () {
        final aa = AddressAndAmount(
          '7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV',
          0,
          'sol',
          type: PaymentType.NonNative,
        );
        expect(aa.type, PaymentType.NonNative);
        expect(aa.assetId, 'sol');
      });
    });

    group('BIP21 URI formats', () {
      test('simple BIP21 URI stored as address', () {
        final aa = AddressAndAmount(
          'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
          0,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, startsWith('bitcoin:'));
      });

      test('BIP21 URI with amount', () {
        final aa = AddressAndAmount(
          'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4?amount=0.001',
          100000,
          null,
          type: PaymentType.Bitcoin,
        );
        expect(aa.address, contains('?amount='));
      });

      test('BIP21 URI with lightning parameter', () {
        final aa = AddressAndAmount(
          'bitcoin:bc1qtest?lightning=lnbc1pvjluez',
          50000,
          null,
          type: PaymentType.Lightning,
        );
        expect(aa.address, contains('lightning='));
      });
    });

    group('Edge cases', () {
      test('empty string address', () {
        final aa = AddressAndAmount('', 0, null);
        expect(aa.address, '');
        expect(aa.type, PaymentType.Unknown);
      });

      test('whitespace-only address', () {
        final aa = AddressAndAmount('   ', 0, null);
        expect(aa.address, '   ');
      });

      test('very long address string', () {
        final longAddr = 'a' * 1000;
        final aa = AddressAndAmount(longAddr, 0, null);
        expect(aa.address.length, 1000);
      });

      test('address with special characters', () {
        final aa = AddressAndAmount('addr!@#\$%^&*()', 0, null);
        expect(aa.address, 'addr!@#\$%^&*()');
      });

      test('null amount with valid address', () {
        final aa = AddressAndAmount('bc1qtest', null, null);
        expect(aa.amount, isNull);
      });

      test('address with unicode characters', () {
        final aa = AddressAndAmount('\u00e9\u00e8\u00ea', 0, null);
        expect(aa.address, '\u00e9\u00e8\u00ea');
      });

      test('case sensitivity preserved in address', () {
        final mixed = 'Bitcoin:BC1QTest123';
        final aa = AddressAndAmount(mixed, 0, null);
        expect(aa.address, mixed);
      });

      test('address with newlines', () {
        final aa = AddressAndAmount('addr\nline2', 0, null);
        expect(aa.address, contains('\n'));
      });

      test('address with leading/trailing whitespace', () {
        final aa = AddressAndAmount(' bc1qtest ', 0, null);
        expect(aa.address, ' bc1qtest ');
      });
    });
  });

  group('Bitcoin address regex validation (mirrors scanner patterns)', () {
    // These tests verify the same regex patterns used in SmartScannerScreen
    // to ensure correctness of the address matching logic.
    final bitcoinRegex = RegExp(
      r'^(bc1|tb1|bcrt1)[a-z0-9]{25,}$|'
      r'^[13][1-9A-HJ-NP-Za-km-z]{25,34}$|'
      r'^(bitcoin:)',
      caseSensitive: false,
    );

    group('valid mainnet bech32 addresses', () {
      test('P2WPKH (bc1q)', () {
        expect(bitcoinRegex.hasMatch('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'), isTrue);
      });

      test('P2TR taproot (bc1p)', () {
        expect(bitcoinRegex.hasMatch('bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297'), isTrue);
      });

      test('bc1q uppercase (case insensitive)', () {
        expect(bitcoinRegex.hasMatch('BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4'), isTrue);
      });
    });

    group('valid testnet addresses', () {
      test('tb1q address', () {
        expect(bitcoinRegex.hasMatch('tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx'), isTrue);
      });

      test('tb1p taproot address', () {
        expect(bitcoinRegex.hasMatch('tb1p5cyxnuxmeuwuvkwfem96lqzszjjc7hsg55hrzke0tm85syvpenqs3yvjq2'), isTrue);
      });
    });

    group('valid regtest addresses', () {
      test('bcrt1 address', () {
        expect(bitcoinRegex.hasMatch('bcrt1q6rhpng9evdsfnn833a4f4vmd8czlm0cjeh9f7n'), isTrue);
      });
    });

    group('valid legacy addresses', () {
      test('P2PKH (starts with 1)', () {
        expect(bitcoinRegex.hasMatch('1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2'), isTrue);
      });

      test('P2SH (starts with 3)', () {
        expect(bitcoinRegex.hasMatch('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy'), isTrue);
      });
    });

    group('valid BIP21 URIs', () {
      test('simple BIP21', () {
        expect(bitcoinRegex.hasMatch('bitcoin:bc1qtest'), isTrue);
      });

      test('BIP21 with amount', () {
        expect(bitcoinRegex.hasMatch('bitcoin:bc1qtest?amount=0.001'), isTrue);
      });

      test('BIP21 uppercase scheme', () {
        expect(bitcoinRegex.hasMatch('BITCOIN:bc1qtest'), isTrue);
      });

      test('BIP21 mixed case', () {
        expect(bitcoinRegex.hasMatch('Bitcoin:bc1qtest?amount=1.0'), isTrue);
      });
    });

    group('invalid addresses rejected', () {
      test('empty string', () {
        expect(bitcoinRegex.hasMatch(''), isFalse);
      });

      test('random text', () {
        expect(bitcoinRegex.hasMatch('hello world'), isFalse);
      });

      test('bc1 with too few characters', () {
        expect(bitcoinRegex.hasMatch('bc1qshort'), isFalse);
      });

      test('address starting with 2', () {
        expect(bitcoinRegex.hasMatch('2BvBMSEYstWetqTFn5Au4m4GFg'), isFalse);
      });

      test('lightning invoice not matched', () {
        expect(bitcoinRegex.hasMatch('lnbc1pvjluezpp5qqqsyqcyq5rqwzqf'), isFalse);
      });

      test('Ethereum address not matched', () {
        expect(bitcoinRegex.hasMatch('0x742d35Cc6634C0532925a3b844Bc9e7595f2bD28'), isFalse);
      });

      test('just bc1 prefix alone', () {
        expect(bitcoinRegex.hasMatch('bc1'), isFalse);
      });

      test('P2PKH address too short (under 26 chars after prefix)', () {
        expect(bitcoinRegex.hasMatch('1Short'), isFalse);
      });

      test('P2PKH with invalid base58 char (0, O, I, l)', () {
        // '0' is not in base58
        expect(bitcoinRegex.hasMatch('10000000000000000000000000000'), isFalse);
      });

      test('Solana address not matched', () {
        expect(bitcoinRegex.hasMatch('7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV'), isFalse);
      });

      test('spark address not matched', () {
        expect(bitcoinRegex.hasMatch('sp1qqw5hn4hlkuu2lesxpqh6w6rm0krsjr0xn6yref'), isFalse);
      });
    });
  });

  group('Lightning address regex validation (mirrors scanner patterns)', () {
    final lightningRegex = RegExp(
      r'^(lnbc|lntb|lnurl|lightning:)',
      caseSensitive: false,
    );

    group('valid Lightning patterns', () {
      test('mainnet bolt11 (lnbc)', () {
        expect(lightningRegex.hasMatch('lnbc1pvjluezpp5qqqsyqcyq5rqwzqf'), isTrue);
      });

      test('testnet bolt11 (lntb)', () {
        expect(lightningRegex.hasMatch('lntb1pvjluezpp5qqqsyqcyq5rqwzqf'), isTrue);
      });

      test('LNURL', () {
        expect(lightningRegex.hasMatch('lnurl1dp68gurn8ghj7mrfva58gumpw3ejucm0d5hkzurf'), isTrue);
      });

      test('lightning: URI scheme', () {
        expect(lightningRegex.hasMatch('lightning:lnbc1pvjluez'), isTrue);
      });

      test('uppercase LNBC (case insensitive)', () {
        expect(lightningRegex.hasMatch('LNBC1PVJLUEZPP5QQQSYQCYQ5RQWZQF'), isTrue);
      });

      test('mixed case lnurl', () {
        expect(lightningRegex.hasMatch('LNURL1DP68GURN'), isTrue);
      });
    });

    group('invalid Lightning patterns', () {
      test('empty string', () {
        expect(lightningRegex.hasMatch(''), isFalse);
      });

      test('Bitcoin address not matched', () {
        expect(lightningRegex.hasMatch('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'), isFalse);
      });

      test('random text', () {
        expect(lightningRegex.hasMatch('hello world'), isFalse);
      });

      test('lightning address (email format) not matched by regex', () {
        // Note: email-format lightning addresses are handled by Breez SDK,
        // not by this regex pattern.
        expect(lightningRegex.hasMatch('user@getalby.com'), isFalse);
      });

      test('Ethereum address not matched', () {
        expect(lightningRegex.hasMatch('0x742d35Cc6634C0532925a3b844Bc9e7595f2bD28'), isFalse);
      });

      test('BIP21 URI not matched', () {
        expect(lightningRegex.hasMatch('bitcoin:bc1qtest'), isFalse);
      });

      test('partial prefix ln not matched', () {
        expect(lightningRegex.hasMatch('ln1pvjluez'), isFalse);
      });
    });
  });

  group('AddressModel', () {
    test('initial state is preserved', () {
      final initialAddress = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1qinitial',
      );
      final model = AddressModel(initialAddress, 'wallet_1');
      expect(model.state.bitcoinAddressIndex, 0);
      expect(model.state.bitcoinAddress, 'bc1qinitial');
      expect(model.state.lightningAddress, isNull);
    });

    test('null walletId is accepted', () {
      final initialAddress = Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: 'bc1qtest',
      );
      final model = AddressModel(initialAddress, null);
      expect(model.state.bitcoinAddress, 'bc1qtest');
    });

    test('initial state with lightningAddress', () {
      final initialAddress = Address(
        bitcoinAddressIndex: 2,
        bitcoinAddress: 'bc1qabc',
        lightningAddress: 'user@ln.com',
      );
      final model = AddressModel(initialAddress, 'w1');
      expect(model.state.lightningAddress, 'user@ln.com');
    });
  });

  group('xpub / descriptor regex (mirrors scanner patterns)', () {
    final xpubRegex = RegExp(r'^[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]{100,108}$');
    final descriptorRegex = RegExp(
      r'^(tr|wpkh|sh\(wpkh|pkh)\(.*[xyzvtmu]pub[1-9A-HJ-NP-Za-km-z]+.*\)$',
    );

    test('xpub prefix matched', () {
      // A valid-length xpub string (111 chars after "xpub")
      final xpub = 'xpub${'6' * 105}';
      expect(xpubRegex.hasMatch(xpub), isTrue);
    });

    test('zpub prefix matched', () {
      final zpub = 'zpub${'6' * 105}';
      expect(zpub.startsWith('zpub'), isTrue);
      expect(xpubRegex.hasMatch(zpub), isTrue);
    });

    test('ypub prefix matched', () {
      final ypub = 'ypub${'6' * 105}';
      expect(xpubRegex.hasMatch(ypub), isTrue);
    });

    test('tpub prefix matched', () {
      final tpub = 'tpub${'6' * 105}';
      expect(xpubRegex.hasMatch(tpub), isTrue);
    });

    test('too short xpub not matched', () {
      final shortXpub = 'xpub${'6' * 50}';
      expect(xpubRegex.hasMatch(shortXpub), isFalse);
    });

    test('invalid prefix not matched', () {
      final bad = 'apub${'6' * 105}';
      expect(xpubRegex.hasMatch(bad), isFalse);
    });

    test('descriptor with wpkh matched', () {
      final desc = 'wpkh(xpub${'6' * 105})';
      expect(descriptorRegex.hasMatch(desc), isTrue);
    });

    test('descriptor with tr matched', () {
      final desc = 'tr(xpub${'6' * 105})';
      expect(descriptorRegex.hasMatch(desc), isTrue);
    });

    test('descriptor with pkh matched', () {
      final desc = 'pkh(xpub${'6' * 105})';
      expect(descriptorRegex.hasMatch(desc), isTrue);
    });

    test('random string not matched as descriptor', () {
      expect(descriptorRegex.hasMatch('hello world'), isFalse);
    });
  });
}
