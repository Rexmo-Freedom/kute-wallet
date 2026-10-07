import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/outlogic_model.dart';

void main() {
  group('OutlogicTrade', () {
    test('fromJson complete', () {
      final trade = OutlogicTrade.fromJson({
        'from_amount': '100.5',
        'from_asset': 'CHF',
        'to_amount': '0.00105',
        'to_asset': 'BTC',
        'fee_amount': '1.5',
        'price': '95000.25',
        'timestamp': '2025-01-15T12:00:00Z',
      });
      expect(trade.fromAmount, 100.5);
      expect(trade.fromAsset, 'CHF');
      expect(trade.toAmount, 0.00105);
      expect(trade.toAsset, 'BTC');
      expect(trade.feeAmount, 1.5);
      expect(trade.price, 95000.25);
      expect(trade.timestamp, '2025-01-15T12:00:00Z');
    });

    test('fromJson with numeric values', () {
      final trade = OutlogicTrade.fromJson({
        'from_amount': 200,
        'from_asset': 'EUR',
        'to_amount': 0.002,
        'to_asset': 'BTC',
        'fee_amount': 2,
        'price': 100000,
        'timestamp': '2025-06-01T00:00:00Z',
      });
      expect(trade.fromAmount, 200.0);
      expect(trade.toAmount, 0.002);
      expect(trade.feeAmount, 2.0);
      expect(trade.price, 100000.0);
    });

    test('fromJson missing fields default to zero/empty', () {
      final trade = OutlogicTrade.fromJson({});
      expect(trade.fromAmount, 0);
      expect(trade.fromAsset, '');
      expect(trade.toAmount, 0);
      expect(trade.toAsset, '');
      expect(trade.feeAmount, 0);
      expect(trade.price, 0);
      expect(trade.timestamp, '');
    });

    test('fromJson null values default to zero/empty', () {
      final trade = OutlogicTrade.fromJson({
        'from_amount': null,
        'from_asset': null,
        'to_amount': null,
        'to_asset': null,
        'fee_amount': null,
        'price': null,
        'timestamp': null,
      });
      expect(trade.fromAmount, 0);
      expect(trade.fromAsset, '');
      expect(trade.toAmount, 0);
      expect(trade.toAsset, '');
      expect(trade.feeAmount, 0);
      expect(trade.price, 0);
      expect(trade.timestamp, '');
    });

    test('fromJson with invalid numeric strings default to zero', () {
      final trade = OutlogicTrade.fromJson({
        'from_amount': 'invalid',
        'to_amount': 'abc',
        'fee_amount': '',
        'price': 'N/A',
      });
      expect(trade.fromAmount, 0);
      expect(trade.toAmount, 0);
      expect(trade.feeAmount, 0);
      expect(trade.price, 0);
    });
  });

  group('OutlogicOrder', () {
    test('fromJson complete with all fields', () {
      final order = OutlogicOrder.fromJson({
        'id': 'order-123',
        'status': 'WAITING_FOR_DEPOSIT',
        'email': 'test@example.com',
        'deposit_crypto_address': 'bc1qxyz...',
        'from_amount': '500.00',
        'from_asset': 'CHF',
        'to_asset': 'BTC',
        'destination_type': 'crypto',
        'destination_crypto_address': 'bc1qabc...',
        'destination_bank_address': 'Bank St 1',
        'destination_bank_name': 'Swiss Bank',
        'destination_bank_account_number': 'CH1234567890',
        'created_at': '2025-01-15T12:00:00Z',
        'expires_at': '2025-01-15T13:00:00Z',
        'transfer_code': 'TC-12345',
        'deposit_sepa_address': 'SEPA-IBAN-123',
        'deposit_sepa_bic': 'SWIFTCODE',
        'deposit_sepa_beneficiary': 'Outlogic AG',
        'deposit_sepa_bank_name': 'SEPA Bank',
        'trade': {
          'from_amount': '500.00',
          'from_asset': 'CHF',
          'to_amount': '0.005',
          'to_asset': 'BTC',
          'fee_amount': '2.50',
          'price': '95000',
          'timestamp': '2025-01-15T12:30:00Z',
        },
      });
      expect(order.id, 'order-123');
      expect(order.status, 'WAITING_FOR_DEPOSIT');
      expect(order.email, 'test@example.com');
      expect(order.depositCryptoAddress, 'bc1qxyz...');
      expect(order.fromAmount, 500.0);
      expect(order.fromAsset, 'CHF');
      expect(order.toAsset, 'BTC');
      expect(order.destinationType, 'crypto');
      expect(order.destinationCryptoAddress, 'bc1qabc...');
      expect(order.destinationBankAddress, 'Bank St 1');
      expect(order.destinationBankName, 'Swiss Bank');
      expect(order.destinationBankAccountNumber, 'CH1234567890');
      expect(order.createdAt, '2025-01-15T12:00:00Z');
      expect(order.expiresAt, '2025-01-15T13:00:00Z');
      expect(order.transferCode, 'TC-12345');
      expect(order.depositSepaAddress, 'SEPA-IBAN-123');
      expect(order.depositSepaBic, 'SWIFTCODE');
      expect(order.depositSepaBeneficiary, 'Outlogic AG');
      expect(order.depositSepaBankName, 'SEPA Bank');
      expect(order.trade, isNotNull);
      expect(order.trade!.fromAmount, 500.0);
      expect(order.trade!.toAmount, 0.005);
    });

    test('fromJson minimal required fields', () {
      final order = OutlogicOrder.fromJson({
        'id': 'order-456',
        'status': 'COMPLETED',
        'email': 'user@test.com',
        'deposit_crypto_address': 'addr1',
        'from_amount': '100',
        'from_asset': 'EUR',
        'to_asset': 'BTC',
        'destination_type': 'crypto',
        'destination_crypto_address': 'addr2',
        'created_at': '2025-02-01T00:00:00Z',
      });
      expect(order.id, 'order-456');
      expect(order.destinationBankAddress, isNull);
      expect(order.destinationBankName, isNull);
      expect(order.destinationBankAccountNumber, isNull);
      expect(order.expiresAt, isNull);
      expect(order.trade, isNull);
      expect(order.transferCode, isNull);
      expect(order.depositSepaAddress, isNull);
      expect(order.depositSepaBic, isNull);
      expect(order.depositSepaBeneficiary, isNull);
      expect(order.depositSepaBankName, isNull);
    });

    test('fromJson missing fields default to empty/zero', () {
      final order = OutlogicOrder.fromJson({});
      expect(order.id, '');
      expect(order.status, '');
      expect(order.email, '');
      expect(order.depositCryptoAddress, '');
      expect(order.fromAmount, 0);
      expect(order.fromAsset, '');
      expect(order.toAsset, '');
      expect(order.destinationType, '');
      expect(order.destinationCryptoAddress, '');
      expect(order.createdAt, '');
      expect(order.trade, isNull);
    });

    test('fromJson with invalid from_amount defaults to zero', () {
      final order = OutlogicOrder.fromJson({
        'from_amount': 'not_a_number',
      });
      expect(order.fromAmount, 0);
    });

    group('isTerminal', () {
      test('returns true for COMPLETED', () {
        final order = OutlogicOrder.fromJson({'status': 'COMPLETED'});
        expect(order.isTerminal, isTrue);
      });

      test('returns true for CANCELED', () {
        final order = OutlogicOrder.fromJson({'status': 'CANCELED'});
        expect(order.isTerminal, isTrue);
      });

      test('returns true for EXPIRED', () {
        final order = OutlogicOrder.fromJson({'status': 'EXPIRED'});
        expect(order.isTerminal, isTrue);
      });

      test('returns true for REJECTED', () {
        final order = OutlogicOrder.fromJson({'status': 'REJECTED'});
        expect(order.isTerminal, isTrue);
      });

      test('returns true for REFUNDED', () {
        final order = OutlogicOrder.fromJson({'status': 'REFUNDED'});
        expect(order.isTerminal, isTrue);
      });

      test('returns false for WAITING_FOR_DEPOSIT', () {
        final order = OutlogicOrder.fromJson({'status': 'WAITING_FOR_DEPOSIT'});
        expect(order.isTerminal, isFalse);
      });

      test('returns false for PROCESSING', () {
        final order = OutlogicOrder.fromJson({'status': 'PROCESSING'});
        expect(order.isTerminal, isFalse);
      });

      test('returns false for empty status', () {
        final order = OutlogicOrder.fromJson({});
        expect(order.isTerminal, isFalse);
      });
    });

    group('isCancellable', () {
      test('returns true for WAITING_FOR_DEPOSIT', () {
        final order = OutlogicOrder.fromJson({'status': 'WAITING_FOR_DEPOSIT'});
        expect(order.isCancellable, isTrue);
      });

      test('returns false for COMPLETED', () {
        final order = OutlogicOrder.fromJson({'status': 'COMPLETED'});
        expect(order.isCancellable, isFalse);
      });

      test('returns false for PROCESSING', () {
        final order = OutlogicOrder.fromJson({'status': 'PROCESSING'});
        expect(order.isCancellable, isFalse);
      });

      test('returns false for empty status', () {
        final order = OutlogicOrder.fromJson({});
        expect(order.isCancellable, isFalse);
      });

      test('returns false for CANCELED', () {
        final order = OutlogicOrder.fromJson({'status': 'CANCELED'});
        expect(order.isCancellable, isFalse);
      });
    });
  });

}
