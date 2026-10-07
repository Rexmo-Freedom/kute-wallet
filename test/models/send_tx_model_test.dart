import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/models/currency_conversions.dart';

void main() {
  group('PaymentType', () {
    test('all values exist', () {
      expect(PaymentType.values.length, 5);
      expect(PaymentType.values, contains(PaymentType.Bitcoin));
      expect(PaymentType.values, contains(PaymentType.Lightning));
      expect(PaymentType.values, contains(PaymentType.Spark));
      expect(PaymentType.values, contains(PaymentType.Unknown));
      expect(PaymentType.values, contains(PaymentType.NonNative));
    });
  });

  group('SendTx', () {
    test('constructor', () {
      final tx = SendTx(
        address: 'bc1qtest',
        amount: 50000,
        type: PaymentType.Bitcoin,
        drain: false,
      );
      expect(tx.address, 'bc1qtest');
      expect(tx.amount, 50000);
      expect(tx.type, PaymentType.Bitcoin);
      expect(tx.drain, isFalse);
    });

    test('copyWith overrides address', () {
      final tx = SendTx(address: 'old', amount: 100, type: PaymentType.Unknown, drain: false);
      final copy = tx.copyWith(address: 'new');
      expect(copy.address, 'new');
      expect(copy.amount, 100);
      expect(copy.type, PaymentType.Unknown);
      expect(copy.drain, isFalse);
    });

    test('copyWith overrides amount', () {
      final tx = SendTx(address: 'a', amount: 100, type: PaymentType.Unknown, drain: false);
      final copy = tx.copyWith(amount: 999);
      expect(copy.amount, 999);
    });

    test('copyWith overrides type', () {
      final tx = SendTx(address: 'a', amount: 0, type: PaymentType.Unknown, drain: false);
      final copy = tx.copyWith(type: PaymentType.Lightning);
      expect(copy.type, PaymentType.Lightning);
    });

    test('copyWith overrides drain', () {
      final tx = SendTx(address: 'a', amount: 0, type: PaymentType.Unknown, drain: false);
      final copy = tx.copyWith(drain: true);
      expect(copy.drain, isTrue);
    });

    test('copyWith preserves all when no args', () {
      final tx = SendTx(address: 'addr', amount: 42, type: PaymentType.Spark, drain: true);
      final copy = tx.copyWith();
      expect(copy.address, 'addr');
      expect(copy.amount, 42);
      expect(copy.type, PaymentType.Spark);
      expect(copy.drain, isTrue);
    });
  });

  group('SendTxModel', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('updateAddress', () {
      model.updateAddress('bc1qnew');
      expect(model.state.address, 'bc1qnew');
    });

    test('updateAmount', () {
      model.updateAmount(12345);
      expect(model.state.amount, 12345);
    });

    test('updatePaymentType', () {
      model.updatePaymentType(PaymentType.Lightning);
      expect(model.state.type, PaymentType.Lightning);
    });

    test('updateDrain', () {
      model.updateDrain(true);
      expect(model.state.drain, isTrue);
    });

    test('resetToDefault', () {
      model.updateAddress('bc1q');
      model.updateAmount(999);
      model.updatePaymentType(PaymentType.Bitcoin);
      model.updateDrain(true);
      model.resetToDefault();
      expect(model.state.address, '');
      expect(model.state.amount, 0);
      expect(model.state.type, PaymentType.Unknown);
      expect(model.state.drain, isFalse);
    });

    test('updateAmountFromInput sats', () {
      model.updateAmountFromInput('50000', 'sats');
      expect(model.state.amount, 50000);
    });

    test('updateAmountFromInput empty string sets 0', () {
      model.updateAmount(999);
      model.updateAmountFromInput('', 'sats');
      expect(model.state.amount, 0);
    });

    test('updateAmountFromInput invalid string sets 0', () {
      model.updateAmountFromInput('abc', 'sats');
      expect(model.state.amount, 0);
    });

    test('updateAmountFromInput zero sets 0', () {
      model.updateAmountFromInput('0', 'sats');
      expect(model.state.amount, 0);
    });

    test('updateAmountFromInput unknown denomination sets 0', () {
      model.updateAmountFromInput('100', 'ETH');
      expect(model.state.amount, 0);
    });

    test('updateAmountFromInput comma-separated value', () {
      model.updateAmountFromInput('1,5', 'sats');
      // 1.5 as sats truncates to 1
      expect(model.state.amount, 1);
    });
  });

  group('SendTx - networkHint', () {
    test('constructor with networkHint null by default', () {
      final tx = SendTx(
        address: 'addr',
        amount: 0,
        type: PaymentType.Unknown,
        drain: false,
      );
      expect(tx.networkHint, isNull);
    });

    test('constructor with explicit networkHint', () {
      final tx = SendTx(
        address: 'addr',
        amount: 0,
        type: PaymentType.Unknown,
        drain: false,
        networkHint: 'mainnet',
      );
      expect(tx.networkHint, 'mainnet');
    });

    test('copyWith overrides networkHint', () {
      final tx = SendTx(
        address: 'addr',
        amount: 0,
        type: PaymentType.Unknown,
        drain: false,
        networkHint: 'testnet',
      );
      final copy = tx.copyWith(networkHint: 'mainnet');
      expect(copy.networkHint, 'mainnet');
    });

    test('copyWith preserves networkHint when not specified', () {
      final tx = SendTx(
        address: 'addr',
        amount: 0,
        type: PaymentType.Unknown,
        drain: false,
        networkHint: 'signet',
      );
      final copy = tx.copyWith(amount: 100);
      expect(copy.networkHint, 'signet');
    });
  });

  group('SendTx - copyWith multiple fields', () {
    test('copyWith overrides all fields at once', () {
      final tx = SendTx(
        address: 'old',
        amount: 0,
        type: PaymentType.Unknown,
        drain: false,
      );
      final copy = tx.copyWith(
        address: 'new',
        amount: 500,
        type: PaymentType.Bitcoin,
        drain: true,
        networkHint: 'mainnet',
      );
      expect(copy.address, 'new');
      expect(copy.amount, 500);
      expect(copy.type, PaymentType.Bitcoin);
      expect(copy.drain, isTrue);
      expect(copy.networkHint, 'mainnet');
    });

    test('copyWith does not mutate original', () {
      final tx = SendTx(
        address: 'original',
        amount: 100,
        type: PaymentType.Lightning,
        drain: false,
      );
      tx.copyWith(address: 'changed', amount: 999);
      expect(tx.address, 'original');
      expect(tx.amount, 100);
    });
  });

  group('SendTxModel - address handling', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('updateAddress with empty string', () {
      model.updateAddress('');
      expect(model.state.address, '');
    });

    test('updateAddress with Bitcoin address', () {
      model.updateAddress('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      expect(model.state.address, 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
    });

    test('updateAddress with Lightning invoice', () {
      const invoice = 'lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg';
      model.updateAddress(invoice);
      expect(model.state.address, invoice);
    });

    test('updateAddress with very long string', () {
      final longAddress = 'a' * 1000;
      model.updateAddress(longAddress);
      expect(model.state.address, longAddress);
    });

    test('updateAddress with special characters', () {
      model.updateAddress('addr+with/special=chars');
      expect(model.state.address, 'addr+with/special=chars');
    });

    test('updateAddress preserves other state fields', () {
      model.updateAmount(500);
      model.updatePaymentType(PaymentType.Bitcoin);
      model.updateDrain(true);
      model.updateAddress('newaddr');
      expect(model.state.amount, 500);
      expect(model.state.type, PaymentType.Bitcoin);
      expect(model.state.drain, isTrue);
    });
  });

  group('SendTxModel - updateNetworkHint', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: 'addr', amount: 100, type: PaymentType.Bitcoin, drain: false),
      );
    });

    test('updateNetworkHint sets hint', () {
      model.updateNetworkHint('mainnet');
      expect(model.state.networkHint, 'mainnet');
    });

    test('updateNetworkHint sets null', () {
      model.updateNetworkHint('mainnet');
      model.updateNetworkHint(null);
      expect(model.state.networkHint, isNull);
    });

    test('updateNetworkHint preserves other fields', () {
      model.updateNetworkHint('testnet');
      expect(model.state.address, 'addr');
      expect(model.state.amount, 100);
      expect(model.state.type, PaymentType.Bitcoin);
      expect(model.state.drain, isFalse);
    });
  });

  group('SendTxModel - updateAmountFromInput BTC denomination', () {
    late SendTxModel model;

    setUpAll(() {
      AppCurrencies.registerCustomCurrencies();
    });

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('BTC 1.0 converts to 100000000 sats', () {
      model.updateAmountFromInput('1.0', 'BTC');
      expect(model.state.amount, 100000000);
    });

    test('BTC 0.5 converts to 50000000 sats', () {
      model.updateAmountFromInput('0.5', 'BTC');
      expect(model.state.amount, 50000000);
    });

    test('BTC 0.00000001 converts to 1 sat', () {
      model.updateAmountFromInput('0.00000001', 'BTC');
      expect(model.state.amount, 1);
    });

    test('BTC 0.001 converts to 100000 sats', () {
      model.updateAmountFromInput('0.001', 'BTC');
      expect(model.state.amount, 100000);
    });

    test('BTC 21 converts to 2100000000 sats', () {
      model.updateAmountFromInput('21', 'BTC');
      expect(model.state.amount, 2100000000);
    });

    test('BTC with comma decimal separator', () {
      model.updateAmountFromInput('0,5', 'BTC');
      expect(model.state.amount, 50000000);
    });

    test('BTC empty string sets 0', () {
      model.updateAmountFromInput('', 'BTC');
      expect(model.state.amount, 0);
    });

    test('BTC zero string sets 0', () {
      model.updateAmountFromInput('0', 'BTC');
      expect(model.state.amount, 0);
    });

    test('BTC 0.0 sets 0', () {
      model.updateAmountFromInput('0.0', 'BTC');
      expect(model.state.amount, 0);
    });

    test('BTC invalid string sets 0', () {
      model.updateAmountFromInput('notanumber', 'BTC');
      expect(model.state.amount, 0);
    });
  });

  group('SendTxModel - updateAmountFromInput sats edge cases', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('sats large value', () {
      model.updateAmountFromInput('2100000000000000', 'sats');
      expect(model.state.amount, 2100000000000000);
    });

    test('sats value 1', () {
      model.updateAmountFromInput('1', 'sats');
      expect(model.state.amount, 1);
    });

    test('sats decimal truncates to int', () {
      model.updateAmountFromInput('99.9', 'sats');
      expect(model.state.amount, 99);
    });

    test('sats negative value', () {
      model.updateAmountFromInput('-100', 'sats');
      // double.tryParse succeeds, -100 != 0, so toInt() yields -100
      expect(model.state.amount, -100);
    });

    test('sats with spaces is invalid', () {
      model.updateAmountFromInput(' 100 ', 'sats');
      // double.tryParse handles leading/trailing spaces
      expect(model.state.amount, 100);
    });

    test('sats with multiple commas', () {
      // '1,000,000' becomes '1.000.000' after replaceAll, which fails double.tryParse
      model.updateAmountFromInput('1,000,000', 'sats');
      expect(model.state.amount, 0);
    });

    test('empty denomination sets 0', () {
      model.updateAmountFromInput('100', '');
      expect(model.state.amount, 0);
    });
  });

  group('SendTxModel - payment type cycling', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('can cycle through all payment types', () {
      for (final type in PaymentType.values) {
        model.updatePaymentType(type);
        expect(model.state.type, type);
      }
    });

    test('updatePaymentType does not affect other fields', () {
      model.updateAddress('bc1q');
      model.updateAmount(500);
      model.updateDrain(true);
      model.updatePaymentType(PaymentType.Spark);
      expect(model.state.address, 'bc1q');
      expect(model.state.amount, 500);
      expect(model.state.drain, isTrue);
    });
  });

  group('SendTxModel - drain flag', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('toggle drain on and off', () {
      model.updateDrain(true);
      expect(model.state.drain, isTrue);
      model.updateDrain(false);
      expect(model.state.drain, isFalse);
    });

    test('drain does not affect amount', () {
      model.updateAmount(5000);
      model.updateDrain(true);
      expect(model.state.amount, 5000);
    });
  });

  group('SendTxModel - resetToDefault clears networkHint', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: 'addr', amount: 100, type: PaymentType.Bitcoin, drain: true, networkHint: 'mainnet'),
      );
    });

    test('resetToDefault sets networkHint to null', () {
      model.resetToDefault();
      expect(model.state.networkHint, isNull);
    });

    test('resetToDefault clears all fields completely', () {
      model.resetToDefault();
      expect(model.state.address, '');
      expect(model.state.amount, 0);
      expect(model.state.type, PaymentType.Unknown);
      expect(model.state.drain, isFalse);
      expect(model.state.networkHint, isNull);
    });
  });

  group('SendTxModel - sequential state updates', () {
    late SendTxModel model;

    setUp(() {
      model = SendTxModel(
        SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false),
      );
    });

    test('multiple address updates keep last value', () {
      model.updateAddress('first');
      model.updateAddress('second');
      model.updateAddress('third');
      expect(model.state.address, 'third');
    });

    test('multiple amount updates keep last value', () {
      model.updateAmount(100);
      model.updateAmount(200);
      model.updateAmount(300);
      expect(model.state.amount, 300);
    });

    test('full transaction setup flow', () {
      model.updateAddress('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      model.updatePaymentType(PaymentType.Bitcoin);
      model.updateAmountFromInput('50000', 'sats');
      model.updateNetworkHint('mainnet');

      expect(model.state.address, 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      expect(model.state.type, PaymentType.Bitcoin);
      expect(model.state.amount, 50000);
      expect(model.state.networkHint, 'mainnet');
      expect(model.state.drain, isFalse);
    });

    test('reset mid-flow clears everything', () {
      model.updateAddress('bc1q');
      model.updateAmount(999);
      model.updatePaymentType(PaymentType.Lightning);
      model.updateDrain(true);
      model.updateNetworkHint('testnet');
      model.resetToDefault();
      model.updateAddress('sp1new');
      model.updatePaymentType(PaymentType.Spark);

      expect(model.state.address, 'sp1new');
      expect(model.state.amount, 0);
      expect(model.state.type, PaymentType.Spark);
      expect(model.state.drain, isFalse);
      expect(model.state.networkHint, isNull);
    });
  });
}
